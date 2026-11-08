param(
    [string]$Package = 'com.wordytwink.cometa',
    [string]$Activity = 'android.app.NativeActivity',
    [string]$Device,
    [ValidateRange(3,30)][int]$Runs = 10,
    [string]$Output = 'startup.json',
    [string]$Adb = (Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe')
)
$ErrorActionPreference = 'Stop'
if (-not $Device) {
    $ready = @(& $Adb devices | Select-String '^([^	 ]+)s+device$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
    if ($ready.Count -ne 1) { throw 'Connect exactly one authorized Android device or specify -Device.' }
    $Device = $ready[0]
}
$installed = & $Adb -s $Device shell pm path $Package
if ($LASTEXITCODE -ne 0 -or -not ($installed -match '^package:')) { throw "Package not installed: $Package" }
$results = @()
for ($i = 1; $i -le $Runs; $i++) {
    & $Adb -s $Device shell am force-stop $Package
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop target package.' }
    Start-Sleep -Milliseconds 500
    $launch = @(& $Adb -s $Device shell am start -W -n "$Package/$Activity")
    $total = $launch | Select-String '^TotalTime:s*(d+)'
    if (-not $total -or -not ($launch -match '^Status:s*ok')) { throw "Launch did not report a valid timing: $($launch -join ' ')" }
    $ms = [int]$total.Matches[0].Groups[1].Value
    $results += [pscustomobject]@{ run = $i; activityTotalMs = $ms }
    Write-Output "Run $i`: $ms ms"
    Start-Sleep -Milliseconds 1000
}
$times = @($results.activityTotalMs | Sort-Object)
$mid = [int][Math]::Floor($times.Count / 2)
$median = if ($times.Count % 2) { $times[$mid] } else { ($times[$mid-1]+$times[$mid])/2.0 }
$report = [ordered]@{
    measuredAtUtc = [DateTime]::UtcNow.ToString('o')
    package = $Package; activity = $Activity
    model = ((& $Adb -s $Device shell getprop ro.product.model) -join '').Trim()
    android = ((& $Adb -s $Device shell getprop ro.build.version.release) -join '').Trim()
    scope = 'am start -W TotalTime after force-stop; first activity display, not proof of full data readiness. App data and OS file caches are retained. Network/account state must be recorded separately.'
    medianMs = $median; minMs = $times[0]; maxMs = $times[-1]
    p90Ms = $times[[Math]::Ceiling($times.Count*0.9)-1]
    samples = $results
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Output -Encoding utf8
Write-Output "Saved: $Output"
