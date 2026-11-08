param([string]$Sdk = $env:ANDROID_HOME, [string]$NdkVersion = '28.2.13676358', [switch]$SkipRustBuild)
$ErrorActionPreference = 'Stop'
function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with $LASTEXITCODE" }
}
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Sdk) { $Sdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$Sdk = (Resolve-Path -LiteralPath $Sdk).Path
$ndk = (Resolve-Path -LiteralPath (Join-Path $Sdk "ndk/$NdkVersion")).Path
$llvm = Join-Path $ndk 'toolchains/llvm/prebuilt/windows-x86_64/bin'
$cargo = Join-Path $env:USERPROFILE '.cargo/bin/cargo.exe'
$tools = Join-Path $Sdk 'build-tools/36.0.0'
$androidJar = Join-Path $Sdk 'platforms/android-36/android.jar'
$env:JAVA_HOME = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { 'C:/Program Files/Android/Android Studio/jbr' }
$env:ANDROID_NDK_HOME = $ndk
$env:ANDROID_NDK = $ndk
$env:ANDROID_HOME = $Sdk
$env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = Join-Path $llvm 'aarch64-linux-android26-clang.cmd'
$env:CC_aarch64_linux_android = $env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
$env:AR_aarch64_linux_android = Join-Path $llvm 'llvm-ar.exe'
$env:PATH = "$llvm;$env:PATH"
Push-Location -LiteralPath $project
try {
    if (-not $SkipRustBuild) { Run $cargo @('build','--locked','--release','--lib','--target','aarch64-linux-android') }
    $symbols = & (Join-Path $llvm 'llvm-nm.exe') -D --undefined-only (Join-Path $project 'target/aarch64-linux-android/release/libcometa.so')
    if ($LASTEXITCODE -ne 0 -or ($symbols -match '__ndk1')) { throw 'Unresolved Android C++ runtime symbols; refusing to package APK.' }
    $out = Join-Path $project 'android/out'
    $packageRoot = Join-Path $out 'package'
    $lib = Join-Path $packageRoot 'lib/arm64-v8a'
    $res = Join-Path $out 'res'
    $assets = Join-Path $out 'assets'
    $licenses = Join-Path $assets 'licenses'
    New-Item -ItemType Directory -Force -Path $lib,(Join-Path $res 'values'),(Join-Path $res 'drawable') | Out-Null
    New-Item -ItemType Directory -Force -Path $licenses | Out-Null
    Copy-Item -LiteralPath (Join-Path $project '../android/assets/fonts/Outfit-OFL.txt'),(Join-Path $project '../android/assets/fonts/roboto_license.txt') -Destination $licenses
    $metadata = (& $cargo metadata --format-version 1 --locked --offline | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0) { throw 'Could not collect dependency licenses' }
    foreach ($dependency in $metadata.packages) {
        $dependencyRoot = Split-Path -Parent $dependency.manifest_path
        foreach ($license in Get-ChildItem -LiteralPath $dependencyRoot -File -Filter 'LICENSE*') {
            Copy-Item -LiteralPath $license.FullName -Destination (Join-Path $licenses "$($dependency.name)-$($dependency.version)-$($license.Name)")
        }
    }
    Copy-Item -LiteralPath (Join-Path $project 'target/aarch64-linux-android/release/libcometa.so') -Destination $lib
    Copy-Item -LiteralPath (Join-Path $project 'android/res/values/styles.xml') -Destination (Join-Path $res 'values/styles.xml')
    Copy-Item -LiteralPath (Join-Path $project '../android/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png') -Destination (Join-Path $res 'drawable/ic_launcher.png')
    $unsigned = Join-Path $out 'unsigned.apk'
    $aligned = Join-Path $out 'aligned.apk'
    $apk = Join-Path $out 'Cometa-0.1.1-native-graphics-arm64.apk'
    Run (Join-Path $tools 'aapt.exe') @('package','-f','-M',(Join-Path $project 'android/AndroidManifest.xml'),'-S',$res,'-A',$assets,'-I',$androidJar,'-F',$unsigned)
    Push-Location -LiteralPath $packageRoot
    try { Run (Join-Path $tools 'aapt.exe') @('add',$unsigned,'lib/arm64-v8a/libcometa.so') } finally { Pop-Location }
    Run (Join-Path $tools 'zipalign.exe') @('-P','16','-f','4',$unsigned,$aligned)
    Run (Join-Path $tools 'apksigner.bat') @('sign','--ks',(Join-Path $env:USERPROFILE '.android/debug.keystore'),'--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android','--out',$apk,$aligned)
    Run (Join-Path $tools 'apksigner.bat') @('verify',$apk)
    Run (Join-Path $tools 'aapt.exe') @('dump','badging',$apk)
    Write-Output "APK: $apk"
} finally { Pop-Location }
