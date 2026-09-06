[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$aapt = Join-Path $root ".compiler\aapt.exe"
$framework = Join-Path $root ".compiler\framework-res.apk"
$signer = Join-Path $root ".compiler\apksigner.bat"
$keystore = Join-Path $root ".compiler\overlaysig.jks"
$buildRoot = Join-Path $root ".build-overlays"
$dist = Join-Path $root "dist"
$bundledJava = Join-Path $root ".compiler\jre"
$pilot = $Target -eq "pilot"

if (-not $env:JAVA_HOME -and (Test-Path -LiteralPath (Join-Path $bundledJava "bin\java.exe"))) {
    $env:JAVA_HOME = $bundledJava
}

$targets = @(
    [pscustomobject]@{ Name = "launcher-black-blue"; Package = "com.android.launcher.black.blue.english.overlay"; Configs = @("values", "values-en", "values-en-rAU", "values-en-rCA", "values-en-rGB", "values-en-rGB-land", "values-en-rIE", "values-en-rIN", "values-en-rUS") },
    [pscustomobject]@{ Name = "backcar"; Package = "com.qf.backcar.english.overlay"; Configs = @("values", "values-en", "values-en-rIE") },
    [pscustomobject]@{ Name = "bluetooth"; Package = "com.qf.bluetooth.english.overlay"; Configs = @("values", "values-en", "values-en-rAU", "values-en-rCA", "values-en-rGB", "values-en-rIE", "values-en-rIN") },
    [pscustomobject]@{ Name = "carsettings"; Package = "com.qf.carsettings.english.overlay"; Configs = @("values", "values-en", "values-en-rAU", "values-en-rCA", "values-en-rGB", "values-en-rIE", "values-en-rIN") },
    [pscustomobject]@{ Name = "fancontrol"; Package = "com.qf.fancontrol.english.overlay"; Configs = @("values", "values-en", "values-en-rAU", "values-en-rCA", "values-en-rGB", "values-en-rIE", "values-en-rIN") },
    [pscustomobject]@{ Name = "keystudy"; Package = "com.qf.keystudy.english.overlay"; Configs = @("values", "values-en", "values-en-rIE") },
    [pscustomobject]@{ Name = "musicplayer"; Package = "com.qf.musicplayer.english.overlay"; Configs = @("values", "values-en", "values-en-rAU", "values-en-rCA", "values-en-rGB", "values-en-rIE", "values-en-rIN") },
    [pscustomobject]@{ Name = "panelkeystudy"; Package = "com.qf.panelkeystudy.english.overlay"; Configs = @("values", "values-en") },
    [pscustomobject]@{ Name = "soundeffect"; Package = "com.qf.soundeffect.english.overlay"; Configs = @("values", "values-en", "values-en-rAU", "values-en-rCA", "values-en-rGB", "values-en-rIE", "values-en-rIN") },
    [pscustomobject]@{ Name = "videoplayer"; Package = "com.qf.videoplayer.english.overlay"; Configs = @("values", "values-en", "values-en-rAU", "values-en-rCA", "values-en-rGB", "values-en-rIE", "values-en-rIN") }
)

if ($pilot) {
    $targets = @($targets | Where-Object Name -in @("launcher-black-blue", "carsettings"))
    $buildRoot = Join-Path $buildRoot "pilot"
    $dist = Join-Path $dist "pilot"
} elseif ($Target -ne "all") {
    $targets = @($targets | Where-Object Name -eq $Target)
    if ($targets.Count -eq 0) {
        throw "Unknown target '$Target'. Use 'all', 'pilot', or one of: launcher-black-blue, backcar, bluetooth, carsettings, fancontrol, keystudy, musicplayer, panelkeystudy, soundeffect, videoplayer"
    }
}

& python (Join-Path $root "tools\validate-overlays.py")
if ($LASTEXITCODE -ne 0) { throw "Overlay validation failed." }

New-Item -ItemType Directory -Force -Path $buildRoot, $dist | Out-Null

foreach ($item in $targets) {
    $sourceRelative = if ($pilot) { "english-overlays\pilot\$($item.Name)" } else { "english-overlays\$($item.Name)" }
    $source = Join-Path $root $sourceRelative
    $stage = Join-Path $buildRoot $item.Name
    $unsigned = Join-Path $stage "$($item.Package)-unsigned.apk"
    $signed = Join-Path $stage "$($item.Package).apk"
    $final = Join-Path $dist "$($item.Package).apk"

    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null

    foreach ($config in $item.Configs) {
        $configDir = Join-Path $stage "res\$config"
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
        Copy-Item -LiteralPath (Join-Path $source "res\values\strings.xml") -Destination (Join-Path $configDir "strings.xml")
    }

    & $aapt p -S (Join-Path $stage "res") -M (Join-Path $source "AndroidManifest.xml") -I $framework -F $unsigned -f
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $unsigned)) { throw "aapt failed for $($item.Name)." }

    & $signer sign --ks $keystore --ks-pass pass:nicholaschum --key-pass pass:nicholaschum --out $signed $unsigned
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $signed)) { throw "Signing failed for $($item.Name)." }
    & $signer verify $signed
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed for $($item.Name)." }

    $badging = (& $aapt dump badging $signed | Select-Object -First 1)
    if ($badging -notmatch "name='$([regex]::Escape($item.Package))'") { throw "Package verification failed for $($item.Name)." }
    $manifestDump = (& $aapt dump xmltree $signed AndroidManifest.xml) -join "`n"
    if ($manifestDump -notmatch "android:targetPackage.*$([regex]::Escape(($item.Package -replace '\.english\.overlay$', '')))") {
        throw "Target-package verification failed for $($item.Name)."
    }

    Move-Item -LiteralPath $signed -Destination $final -Force
    if (Test-Path -LiteralPath "$signed.idsig") { Remove-Item -LiteralPath "$signed.idsig" -Force }
    Write-Host "Built $([IO.Path]::GetFileName($final))"
}

$checksums = Get-ChildItem -LiteralPath $dist -Filter "*.apk" |
    Sort-Object Name |
    ForEach-Object { "$(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName | Select-Object -ExpandProperty Hash)  $($_.Name)" }
[IO.File]::WriteAllLines((Join-Path $dist "SHA256SUMS.txt"), $checksums, [Text.UTF8Encoding]::new($false))
