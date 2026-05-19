# MuMu Magisk 1-Click Setup

One-click Windows setup for preparing MuMu Player 12 instances for Magisk Kitsune by enabling MuMu root mode and writable system disk settings.

Global MuMu is preferred by default. Chinese MuMu is supported with the same logic when Global is not installed, or when selected explicitly.

## Download MuMu

Recommended for new users: use MuMu Player 12 Global.

[Download MuMuInstaller_Global.exe](https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/MuMuInstaller_Global.exe)

The installer metadata is tracked in [installer-url.txt](installer-url.txt). CI checks the committed EXE against MuMu's official download API and opens an update PR when the scheduled updater sees a change.

You can also download MuMu Global from the official site:

https://www.mumuplayer.com/download/

## Setup

Before running setup:

1. Install MuMu Player 12 Global.
2. Open MuMu once.
3. Use Multi-Instance Manager to create the Android 12 instance you want to root.
4. Start that instance once, then close MuMu completely.
5. Run the setup command below.
6. Accept the Windows admin prompt.
7. Open MuMu again and continue with your Magisk Kitsune install.

This tool prepares MuMu root mode and writable system settings. It does not install Magisk inside Android for you.

Works from PowerShell or Command Prompt:

```cmd
cmd.exe /d /c "curl.exe -fL https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/Setup.bat -o Setup.bat && Setup.bat"
```

`Setup.bat` downloads its PowerShell helper automatically if `scripts\MuMuConfig.ps1` is not already next to it.

You do not need to restart Windows. The PowerShell `ExecutionPolicy Bypass` used by `Setup.bat` applies only to this one command process; it does not permanently change your Windows settings.

If both editions are installed, Global is patched by default. To patch both:

```cmd
Setup.bat --edition all
```

Useful options:

```cmd
Setup.bat --dry-run
Setup.bat --edition global
Setup.bat --edition chinese
Setup.bat --edition all
```

## What It Changes

- Finds MuMu installs from the Windows uninstall registry first, including custom `InstallLocation` paths.
- Falls back to known `Program Files\Netease` paths only if registry discovery fails.
- Patches every non-base instance under `{InstallRoot}\vms\*\configs`.
- Updates MuMu's user-level APK association toggle under `%APPDATA%\Netease\MuMuPlayerGlobal\configs\nx_main.json` or `%APPDATA%\Netease\MuMuPlayer\configs\nx_main.json` when that file exists.
- Clears current-user `.apk`, `.xapk`, and `.apks` Windows file associations only when they currently point to MuMu, and stores a restore value first.
- Creates `.bak` backups before the first write and restores from those backups later.
- Uses PowerShell JSON parsing instead of line-by-line batch text replacement.
- Does not add hosts-file rules, firewall rules, startup entries, services, scheduled tasks, or silent installer execution.

## Requirements

- Windows 10 or 11.
- Administrator rights for setup and restore.
- MuMu Player 12 Global or Chinese installed. Global is recommended for new users.
- Android 12 instance(s) already created in MuMu Multi-Instance Manager.
- MuMu fully closed before running setup.

This project is no longer pinned to Chinese V4.1.24.3688. The scripts target the MuMu 12 config schema and have smoke tests for current Global-style paths. If a future MuMu release changes the config keys, run `Setup.bat --dry-run` first and open an issue with the dry-run output.

## Restore

Run this from PowerShell or Command Prompt:

```cmd
cmd.exe /d /c "curl.exe -fL https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/RestoreMuMuConfig.bat -o RestoreMuMuConfig.bat && RestoreMuMuConfig.bat"
```

Restore copies every `*.bak` file created by setup back to its original filename and restores the current-user APK file associations that setup cleared.

## Patched Files

Per instance, excluding folders ending in `-base`:

| File | Keys |
| --- | --- |
| `customer_config.json` | `setting.other_setting.root_mode` -> `"1"` |
| `customer_config.json` | `setting.disk_share.mode.choose` -> `"disk_share.mode.writable"` |
| `vm_config.json` | `system_vdi.sharable` or `vm.system_vdi.sharable` -> `"Writable"` |
| `shell_config.json` | `player.uu_remote.should_show` -> `"false"` when present |
| `%APPDATA%\Netease\...\configs\nx_main.json` | `nxmain.setting.apk_association` -> `"0"` when present |

## Privacy Tweaks

The setup only changes privacy/debloat keys that already exist in MuMu's JSON. It does not create guessed JSON keys.

Currently documented optional keys:

| File | Key | Value |
| --- | --- | --- |
| `customer_config.json` | `customer.apk_associate` | `"false"` |
| `customer_config.json` | `customer.app_keptlive` | `"false"` |
| `customer_config.json` | `customer.run_limitation` | `"false"` |
| `customer_config.json` | `setting.other_setting.apk_association` | `"0"` |
| `customer_config.json` | `setting.other_setting.app_keptlive` | `"0"` |
| `customer_config.json` | `setting.other_setting.run_limitation` | `"0"` |
| `%APPDATA%\Netease\...\configs\nx_main.json` | `nxmain.setting.apk_association` | `"0"` |
| `shell_config.json` | `player.uu_remote.should_show` | `"false"` |

For the Windows "Associate APK files" toggle, MuMu also writes current-user file associations. Setup clears `.apk`, `.xapk`, and `.apks` only if they currently point to MuMu classes such as `MuMuPlayerGlobal.apk`, then stores the previous value for restore.

`run_limitation` is an existing MuMu config toggle. The script keeps it disabled when the key is present, but the exact MuMu behavior is not officially documented.

No `easebar.com` or `netease.com` network blocking is applied because that can break updates and login.

## Bundled Tools

The `Tools/` directory contains utilities that can be useful after setting up Magisk:

- `app-release.apk`: Kitsune Magisk installer, a Magisk fork commonly used for emulators.
- `LSPosed-v1.10.1-7180-zygisk-release.zip`: LSPosed framework for Zygisk module support.
- `NeoZygisk-v1-0.0-233-ce4a658-release.zip`: NeoZygisk for Zygisk-based modules.
- `HMAL_4.2.0.r104_release_2.zip`: Hide My Applist module.
- `MT_2.14.5-clone_MOD-V3-PREVIEW.apk`: MT Manager APK/file tool.
- `core-patch-4.6.apk`: CorePatch helper for Android package/signature workflows.

These tools are provided for convenience. Install them manually inside the MuMu instance after Magisk is running.

## Video Tutorials

Part 1, basic setup and Play Store:

https://www.youtube.com/watch?v=bBj8CE55lpk

Part 2, advanced setup and optimization:

https://www.youtube.com/watch?v=XGNkyvmAckE

## Visual Settings Guide

The screenshot folders are kept as references for users comparing Chinese and English MuMu UI labels. CPU/RAM allocation and FPS/performance settings should be adjusted for your own PC instead of copied blindly.

| Setting | Chinese UI (`ChineseAssets/`) | English UI (`assets/`) |
| --- | --- | --- |
| Other Settings | ![Other Settings](ChineseAssets/MuMuPlayer_syw6Ig9jQV.png) | ![Other Settings](assets/OtherSettings.png) |
| More Other Settings | ![More Settings](ChineseAssets/MuMuPlayer_80z4wORNeA.png) | ![More Settings](assets/otherSettings2.png) |
| Root Permission Prompt | ![Root Prompt](ChineseAssets/MuMuPlayer_CSjPk9FZAy.png) | ![Root Prompt](assets/MuMuPlayer_CSjPk9FZAy.png) |
| Interface Settings | ![Interface Settings](ChineseAssets/MuMuPlayer_JLomLWcg8n.png) | ![Interface Settings](assets/MuMuPlayer_JLomLWcg8n.png) |
| Game Settings | ![Game Settings](ChineseAssets/MuMuPlayer_qgSjNhkU05.png) | ![Game Settings](assets/MuMuPlayer_qgSjNhkU05.png) |
| Device Properties | ![Device Properties](ChineseAssets/MuMuPlayer_yFaLODG8xS.png) | ![Device Properties](assets/MuMuPlayer_yFaLODG8xS.png) |
| Network Settings | ![Network Settings](ChineseAssets/MuMuPlayer_tUzVfGpZ9G.png) | ![Network Settings](assets/MuMuPlayer_tUzVfGpZ9G.png) |
| Performance Monitor / FPS | ![Monitor](ChineseAssets/MuMuPlayer_9t5cRTMdC6.png) | ![Monitor](assets/MuMuPlayer_9t5cRTMdC6.png) |
| Basic Settings | ![Basic Settings](ChineseAssets/MuMuPlayer_pAD1HH9j5I.png) | ![Basic Settings](assets/MuMuPlayer_pAD1HH9j5I.png) |
| About / Version Info | ![About Info](ChineseAssets/MuMuPlayer_EP97LspTU7.png) | ![About Info](assets/MuMuPlayer_EP97LspTU7.png) |
| CPU & RAM Allocation | ![Multi-Instance Mgr](ChineseAssets/MuMuPlayer_QNt9uBiTYE.png) | ![Multi-Instance Mgr](assets/MuMuPlayer_QNt9uBiTYE.png) |

## Antivirus Notes

No project can guarantee that every antivirus product will avoid a false positive, especially for admin scripts that stop emulator processes and edit emulator config files. This repo is kept as transparent as possible: no encoded PowerShell, no obfuscation, no persistence, no credential access, no hosts/firewall edits, and no antivirus tampering. The committed installer is the official Global MuMu installer resolved by CI from MuMu's API.

## Download Metadata

The CI workflow resolves the current Global Windows installer through the official API:

```text
https://api.mumuplayer.com/api/website/download_version_info?usage=1
https://api.mumuplayer.com/api/dl/win?channel=gw-win-download
```

The workflow follows redirects and fails if the final chain does not include an `.exe` URL from `a11.gdl.netease.com` with a successful response. It also downloads the installer in CI and compares size/MD5 against `MuMuInstaller_Global.exe`.

Chinese installer discovery is intentionally separate and is not assumed to use the same Global channel.

## Smoke Tests

Run:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\Smoke.Tests.ps1
```

The tests create temporary Global and Chinese fixtures, write HKCU uninstall-registry test keys, verify Global-first discovery, setup, restore, and live Global download resolution. They do not install or launch MuMu in CI.

## Need Help?

Telegram: https://t.me/+6EreKfc983UzMjgx

## Support The Project

Ko-fi: https://ko-fi.com/yejordan

## Credits

- Magisk Kitsune: https://github.com/HuskyDG/Magisk
- Magisk upstream: https://github.com/topjohnwu/Magisk
- MuMu Player: https://www.mumuplayer.com/

## Disclaimer

This tool is for educational and development use. Root access and writable system settings can affect emulator stability and security. Use it only on instances you are prepared to modify and restore.

## License

See [LICENSE.md](LICENSE.md).
