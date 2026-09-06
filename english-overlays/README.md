# K706 English overlays

This release corrects English text in the active Black/Blue launcher and nine supplied QF apps. It does not alter layouts, icons, colours, shortcuts, code, app data, or the completed CarApp overlay.

## Contents

- `*/res/values/strings.xml`: editable corrections for each target package.
- `audit/inventory.csv`: every compiled resource name and configuration in the supplied APKs.
- `audit/original-values.csv`: values extracted from the supplied APKs.
- `audit/translations.csv`: original and replacement text with verification state.
- `audit/source-apks.sha256`: exact source APK fingerprints.
- `audit/exceptions.md`: text that this resource-only release cannot safely change.

## Build

From PowerShell:

```powershell
.\build-overlays.ps1 all
.\build-overlays.ps1 pilot
.\build-overlays.ps1 carsettings
```

The build validates every resource name and format argument, compiles isolated overlays, signs them with the existing overlay key, verifies each signature and manifest, and writes successful APKs to `dist/`. The smaller launcher and Car Settings pilot APKs go to `dist/pilot/`. A failed build never replaces the previous output APK.

The canonical string file is copied into every English configuration present in its target APK. The launcher also receives its English landscape configuration. Non-English and `en-XC` pseudolocale resources are not replaced.

## Device test order

Run the read-only inventory first:

```powershell
.\.compiler\adb.exe connect 192.168.0.10:9876
.\install-overlays.ps1 -Serial 192.168.0.10:9876 -Action status
```

Replace the serial with the connected unit shown by `.\.compiler\adb.exe devices`. Save the Android version, active-user ID, locale, and overlay-list output with the test report.

Install the pilot only after reviewing that output:

```powershell
.\install-overlays.ps1 -Serial 192.168.0.10:9876 -Action install -Selection pilot
.\.compiler\adb.exe -s 192.168.0.10:9876 reboot
.\install-overlays.ps1 -Serial 192.168.0.10:9876 -Action enable -Selection pilot
.\.compiler\adb.exe -s 192.168.0.10:9876 reboot
```

Verify the launcher and Car Settings, then install `batch1`, `batch2`, and `batch3` in that order. `batch1` includes the pilot packages, so reinstalling them is harmless.

Disable a batch for an A/B comparison:

```powershell
.\install-overlays.ps1 -Serial 192.168.0.10:9876 -Action disable -Selection pilot
.\.compiler\adb.exe -s 192.168.0.10:9876 reboot
```

Remove only these overlay APKs for a complete rollback:

```powershell
.\install-overlays.ps1 -Serial 192.168.0.10:9876 -Action uninstall -Selection all
.\.compiler\adb.exe -s 192.168.0.10:9876 reboot
```

If `adb remount` reports that verified boot is enabled, use the already-tested CarApp installer preparation before retrying. Do not clear launcher or application data.

## Acceptance checks

- Pilot corrections appear after reboot and revert when the overlays are disabled.
- Launcher navigation, clock, media controls, app grid, Bluetooth, reverse camera, DSP, and learned buttons behave as before.
- Text fits the 1024×600 interface and remains corrected with the configured English locale.
- Update `audit/translations.csv` status only after confirming the affected screens on the unit.
