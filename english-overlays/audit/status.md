# Release status

| Target package | Named strings audited | Corrections | Full APK | Device verification |
|---|---:|---:|---|---|
| `com.android.launcher.black.blue` | 291 | 61 | Built | Pending |
| `com.qf.backcar` | 29 | 15 | Built | Pending |
| `com.qf.bluetooth` | 97 | 51 | Built | Pending |
| `com.qf.carsettings` | 381 | 212 | Built | Pending |
| `com.qf.fancontrol` | 5 | 1 | Built | Pending |
| `com.qf.keystudy` | 5 | 4 | Built | Pending |
| `com.qf.musicplayer` | 48 | 7 | Built | Pending |
| `com.qf.panelkeystudy` | 2 | 2 | Built | Pending |
| `com.qf.soundeffect` | 50 | 17 | Built | Pending |
| `com.qf.videoplayer` | 46 | 5 | Built | Pending |

The pilot contains four visible corrections each for the Black/Blue launcher and Car Settings. Full overlay manifests use version code 2; pilot manifests use version code 1 so the full release is an explicit upgrade.

Compilation, package/target inspection, English configuration inspection, and v1/v2 APK signature verification pass for all full and pilot artifacts. Physical K706 verification remains pending because no ADB device was connected during the build.

