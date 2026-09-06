[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Serial,

    [ValidateSet("status", "preview", "install", "enable", "disable", "uninstall")]
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
$sourceDirectory = if ($Selection -eq "pilot") { Join-Path $dist "pilot" } else { $dist }
$packageErrors = @{}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & $adb -s $Serial @Arguments
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $($Arguments -join ' ')" }
}

function Add-PackageFailure {
    param([string]$Package, [string]$Step, [string]$Message)
    if (-not $packageErrors.ContainsKey($Package)) { $packageErrors[$Package] = @() }
    $packageErrors[$Package] += "${Step}: $Message"
    Write-Warning "FAILED ${Package} (${Step}): $Message"
}

function Invoke-PackageStep {
    param([string]$Package, [string]$Step, [scriptblock]$Operation)
    try {
        & $Operation | Out-Host
        Write-Host "OK ${Package} (${Step})"
    } catch {
        Add-PackageFailure $Package $Step $_.Exception.Message
    }
}

function Initialize-WritableSystem {
    try {
        Invoke-Adb root | Out-Host
        Invoke-Adb wait-for-device | Out-Host
        Invoke-Adb remount | Out-Host
        $probe = "/system/.overlay-write-test-$PID"
        Invoke-Adb shell touch $probe | Out-Host
        Invoke-Adb shell rm -f $probe | Out-Host
        return $true
    } catch {
        foreach ($package in $packages) {
            Add-PackageFailure $package "prepare /system" $_.Exception.Message
        }
        return $false
    }
}

function Complete-Run {
    $succeeded = @($packages | Where-Object { -not $packageErrors.ContainsKey($_) })
    $failed = @($packages | Where-Object { $packageErrors.ContainsKey($_) })
    Write-Host "Succeeded: $(if ($succeeded.Count) { $succeeded -join ', ' } else { '(none)' })"
    Write-Host "Failed: $(if ($failed.Count) { $failed -join ', ' } else { '(none)' })"
    foreach ($package in $failed) {
        Write-Host "  ${package}: $($packageErrors[$package] -join '; ')"
    }
    if ($failed.Count) { exit 1 }
    exit 0
}

if ($Action -eq "preview") {
    Write-Host "Preview only; no adb commands will run for '$Selection'."
    foreach ($package in $packages) {
        $apk = Join-Path $sourceDirectory "$package.apk"
        $temporary = "/data/local/tmp/$package.apk"
        $destination = "$systemDirectory/$package.apk"
        Write-Host $package
        Write-Host "  Source APK: $apk"
        Write-Host "  Temporary path: $temporary"
        Write-Host "  Destination: $destination"
        Write-Host "  Install: remount /system read-write; push to temporary path; move to destination; chmod 644; verify system_file SELinux context"
        Write-Host "  Enable: cmd overlay enable --user <active-user> $package"
        Write-Host "  Disable: cmd overlay disable --user <active-user> $package"
        Write-Host "  Uninstall: disable for <active-user>; remount /system read-write; rm -f $destination"
    }
    exit 0
}

if ($Action -eq "status") {
    Invoke-Adb shell getprop ro.build.version.release
    Invoke-Adb shell am get-current-user
    Invoke-Adb shell getprop persist.sys.locale
    Invoke-Adb shell cmd overlay list
    exit 0
}

if ($Action -eq "install") {
    if (Initialize-WritableSystem) {
        foreach ($package in $packages) {
            Invoke-PackageStep $package "install" {
                $apk = Join-Path $sourceDirectory "$package.apk"
                if (-not (Test-Path -LiteralPath $apk)) { throw "Build output not found: $apk" }
                $temporary = "/data/local/tmp/$package.apk"
                $destination = "$systemDirectory/$package.apk"
                Invoke-Adb push $apk $temporary
                Invoke-Adb shell mv $temporary $destination
                Invoke-Adb shell chmod 644 $destination
                $context = (Invoke-Adb shell ls -Z $destination) -join "`n"
                $context | Out-Host
                if ($context -notmatch "u:object_r:system_file:s0") {
                    throw "Unexpected SELinux context for ${destination}: $context"
                }
            }
        }
    }
    if ($packageErrors.Count -eq 0) {
        Write-Host "Installed $Selection. Reboot the unit, then run this script with -Action enable -Selection $Selection."
    }
    Complete-Run
}

$userId = $null
try {
    $userId = (Invoke-Adb shell am get-current-user | Select-Object -Last 1).Trim()
    if ($userId -notmatch "^\d+$") { throw "Could not determine the active Android user." }
} catch {
    foreach ($package in $packages) {
        Add-PackageFailure $package "get active user" $_.Exception.Message
    }
}

if ($Action -eq "enable" -or $Action -eq "disable") {
    if ($null -ne $userId) {
        foreach ($package in $packages) {
            Invoke-PackageStep $package $Action { Invoke-Adb shell cmd overlay $Action --user $userId $package }
        }
        try {
            Invoke-Adb shell cmd overlay list --user $userId | Out-Host
        } catch {
            Write-Warning "Could not list final overlay state: $($_.Exception.Message)"
        }
    }
    if ($packageErrors.Count -eq 0) { Write-Host "Overlay state changed. Reboot the unit before verification." }
    Complete-Run
}

if ($Action -eq "uninstall") {
    if ($null -ne $userId) {
        foreach ($package in $packages) {
            Invoke-PackageStep $package "disable before uninstall" { Invoke-Adb shell cmd overlay disable --user $userId $package }
        }
    }
    if (Initialize-WritableSystem) {
        foreach ($package in $packages) {
            Invoke-PackageStep $package "remove" { Invoke-Adb shell rm -f "$systemDirectory/$package.apk" }
        }
    }
    if ($packageErrors.Count -eq 0) { Write-Host "Removed $Selection. Reboot the unit to finish rollback." }
    Complete-Run
}
