param([Parameter(Mandatory)][string]$Apk, [string]$Device='emulator-5554', [string]$Output='android-launch-check')
$ErrorActionPreference='Stop'
$adb=Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$package='com.wordytwink.cometa'
New-Item -ItemType Directory -Force -Path $Output | Out-Null
$Output=(Resolve-Path -LiteralPath $Output).Path
& $adb -s $Device install -r $Apk
if ($LASTEXITCODE -ne 0) {throw 'APK install failed'}
for ($i=1;$i -le 3;$i++) {
    & $adb -s $Device shell am force-stop $package
    & $adb -s $Device logcat -c
    & $adb -s $Device shell am start -W -n "$package/android.app.NativeActivity"
    Start-Sleep -Seconds 3
    $crash=& $adb -s $Device logcat -d -b crash
    $crash | Set-Content -LiteralPath (Join-Path $Output "crash-$i.txt")
    $appProcess=& $adb -s $Device shell pidof $package
    if (-not $appProcess -or ($crash -match 'FATAL EXCEPTION|Fatal signal')) {throw "Android launch $i failed; see $Output"}
    $messages=& $adb -s $Device logcat -d --pid=$appProcess
    $messages | Set-Content -LiteralPath (Join-Path $Output "app-$i.txt")
    if ($messages -match 'panicked at|Graphics initialization:|\sCometa:\s|GPU flush:') {throw "Native initialization failed on launch $i; see $Output"}
}
& $adb -s $Device shell input keyevent KEYCODE_HOME
Start-Sleep -Seconds 2
& $adb -s $Device shell am start -W -n "$package/android.app.NativeActivity"
Start-Sleep -Seconds 2
if (-not (& $adb -s $Device shell pidof $package)) {throw 'App failed after background/resume'}
& $adb -s $Device shell screencap -p /sdcard/cometa-launch-check.png
& $adb -s $Device pull /sdcard/cometa-launch-check.png (Join-Path $Output 'android-launch.png')
if ($LASTEXITCODE -ne 0) {throw 'Screenshot capture failed'}
Write-Output 'Passed: 3 process-cold launches and background/resume. Inspect android-launch.png to verify the rendered UI.'
