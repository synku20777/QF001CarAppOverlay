[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Serial,

    [ValidateSet("status", "install", "enable", "disable", "uninstall")]
    [string]$Action = "status",

    [ValidateSet("pilot", "batch1", "batch2", "batch3", "all")]
    [string]$Selection = "pilot"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$adb = Join-Path $root ".compiler\adb.exe"
$dist = Join-Path $root "dist"
$systemDirectory = "/system/app"
$groups = @{
    pilot = @(
        "com.android.launcher.black.blue.english.overlay",
        "com.qf.carsettings.english.overlay"
    )
    batch1 = @(
        "com.android.launcher.black.blue.english.overlay",
        "com.qf.carsettings.english.overlay",
        "com.qf.backcar.english.overlay"
    )
    batch2 = @(
        "com.qf.keystudy.english.overlay",
        "com.qf.panelkeystudy.english.overlay",
        "com.qf.soundeffect.english.overlay"
    )
    batch3 = @(
        "com.qf.bluetooth.english.overlay",
        "com.qf.musicplayer.english.overlay",
        "com.qf.videoplayer.english.overlay",
        "com.qf.fancontrol.english.overlay"
    )
}
$groups.all = @($groups.batch1 + $groups.batch2 + $groups.batch3 | Select-Object -Unique)
$packages = @($groups[$Selection])

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & $adb -s $Serial @Arguments
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $($Arguments -join ' ')" }
}

if ($Action -eq "status") {
    Invoke-Adb shell getprop ro.build.version.release
    Invoke-Adb shell am get-current-user
    Invoke-Adb shell getprop persist.sys.locale
    Invoke-Adb shell cmd overlay list
    exit 0
}

if ($Action -eq "install") {
    foreach ($package in $packages) {
        $sourceDirectory = if ($Selection -eq "pilot") { Join-Path $dist "pilot" } else { $dist }
        $apk = Join-Path $sourceDirectory "$package.apk"
        if (-not (Test-Path -LiteralPath $apk)) { throw "Build output not found: $apk" }
    }
    Invoke-Adb root
    Invoke-Adb wait-for-device
    Invoke-Adb remount
    foreach ($package in $packages) {
        $sourceDirectory = if ($Selection -eq "pilot") { Join-Path $dist "pilot" } else { $dist }
        $apk = Join-Path $sourceDirectory "$package.apk"
        $temporary = "/data/local/tmp/$package.apk"
        $destination = "$systemDirectory/$package.apk"
        Invoke-Adb push $apk $temporary
        Invoke-Adb shell mv $temporary $destination
        Invoke-Adb shell chmod 644 $destination
    }
    Write-Host "Installed $Selection. Reboot the unit, then run this script with -Action enable -Selection $Selection."
    exit 0
}

$userId = (Invoke-Adb shell am get-current-user | Select-Object -Last 1).Trim()
if ($userId -notmatch "^\d+$") { throw "Could not determine the active Android user." }

if ($Action -eq "enable" -or $Action -eq "disable") {
    foreach ($package in $packages) {
        Invoke-Adb shell cmd overlay $Action --user $userId $package
    }
    Invoke-Adb shell cmd overlay list --user $userId
    Write-Host "Overlay state changed. Reboot the unit before verification."
    exit 0
}

if ($Action -eq "uninstall") {
    foreach ($package in $packages) {
        Invoke-Adb shell cmd overlay disable --user $userId $package
    }
    Invoke-Adb root
    Invoke-Adb wait-for-device
    Invoke-Adb remount
    foreach ($package in $packages) {
        Invoke-Adb shell rm -f "$systemDirectory/$package.apk"
    }
    Write-Host "Removed $Selection. Reboot the unit to finish rollback."
}
