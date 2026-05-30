<div align="center">

# 🐾 MuMu Magisk 1-Click

### Root your MuMu Player 12 Android emulator in one click — no rooting experience needed.

One command turns on MuMu's **root mode** and **writable system** so you can install **Magisk Kitsune**.
It finds your install automatically, backs up every file it touches, and has a one-click undo.

[![Stars](https://img.shields.io/github/stars/Jordan231111/mumu-magisk-1click?style=social)](https://github.com/Jordan231111/mumu-magisk-1click/stargazers) ![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows&logoColor=white) ![MuMu](https://img.shields.io/badge/MuMu-Player%2012-success) ![License](https://img.shields.io/badge/License-CC%20BY--NC--ND%204.0-lightgrey) [![Telegram](https://img.shields.io/badge/Telegram-join-26A5E4?logo=telegram&logoColor=white)](https://t.me/+6EreKfc983UzMjgx)

</div>

---

> [!NOTE]
> This tool prepares the **Windows side** (the part that's tedious and easy to get wrong). The final step — installing Magisk *inside* Android — takes about two minutes and is covered in the [video walkthrough ↓](#-after-setup-install-magisk-inside-android). It does **not** install Magisk into Android for you.

## ⚡ Quick start

### 🟢 Option A — No terminal (recommended)

Best for first-timers. The download includes the setup tool **and** every APK you'll need later.

1. **[⬇️ Download the ZIP](https://github.com/Jordan231111/mumu-magisk-1click/archive/refs/heads/main.zip)**
2. **Right-click the ZIP → Extract All.**
3. Open the extracted folder and **double-click `Setup.bat`**.
4. If Windows shows *"Windows protected your PC"*, click **More info → Run anyway** (it's an unsigned script — see [Is this safe?](#is-this-safe)).
5. Click **Yes** on the admin prompt.
6. When it says **`Done. Files changed: …`**, close the window and reopen MuMu. ✅

### 💻 Option B — One command (faster)

For anyone comfortable with a terminal. Press <kbd>Win</kbd>, type `cmd`, hit Enter, then paste this into **Command Prompt** (or **PowerShell**):

```cmd
cmd.exe /d /c "curl.exe -fL https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/Setup.bat -o Setup.bat && Setup.bat"
```

Accept the admin prompt when it appears. This grabs **only** the setup script, so you'll still want the [bundled tools ↓](#-whats-bundled) for the in-Android steps.

That's it for the Windows side. Next: [install Magisk inside Android ↓](#-after-setup-install-magisk-inside-android).

---

## ✨ What you get

- ✅ **Root mode + writable system** switched on for every instance, automatically.
- ✅ **One action** — double-click a file (or paste one command). It asks for admin, does its thing, done.
- ✅ **Finds MuMu for you** — works wherever it's installed, Global or Chinese edition.
- ✅ **Safe by design** — backs up every file before changing it, and the undo restores everything.
- ✅ **Everything bundled** — Magisk Kitsune, Zygisk, Vector, Hide My Applist, MT Manager and more, all in one download.
- ✅ **Transparent** — plain PowerShell, no obfuscation, no hidden network calls, no persistence. [See exactly what it changes ↓](#-exactly-what-it-changes)

---

## ✅ Before you start

You need just three things:

1. **Windows 10 or 11.**
2. **MuMu Player 12 installed.** New users should pick **Global** — it's in English and recommended.
   <br>👉 [Download MuMu Player 12 Global](https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/MuMuInstaller_Global.exe) (bundled here) · or from the [official site](https://www.mumuplayer.com/download/).
3. **An Android 12 instance, created and started once.** Open MuMu → **Multi-Instance Manager** → create an Android 12 instance → start it once so its files exist → then **close MuMu completely** before running setup.

> 💡 Chinese MuMu works too. If both editions are installed, Global is patched by default — use `Setup.bat --edition all` to do both.

---

## 📦 What's bundled

Everything you need after rooting is already in the [`Tools/`](Tools/) folder — install these **inside** MuMu once Magisk is running:

| Tool | What it's for |
| --- | --- |
| [Magisk Kitsune](Tools/app-release.apk) | The root manager. A [Magisk fork](https://github.com/HuskyDG/Magisk) tuned for emulators. **Install this first.** |
| [NeoZygisk](Tools/NeoZygisk-v2.3-282-8b12252-release.zip) | Zygisk engine — required for most modern root modules. |
| [Vector](Tools/Vector-v2.0-3043-Release.zip) | Module framework (the [successor to LSPosed](https://github.com/JingMatrix/Vector)). |
| [Hide My Applist (HMA-OSS)](Tools/HMA-OSS-oss-161-release.apk) | Hides root from apps that look for it. [Source](https://github.com/frknkrc44/HMA-OSS). Install the APK, then enable it in Vector. |
| [MT Manager](Tools/mtmanager.apk) | The go-to root file manager / APK editor. [Official site](https://mt2.cn/). |
| [CorePatch](Tools/core-patch-4.9.apk) | Lets Android install/patch apps with mismatched signatures. [Source](https://github.com/LSPosed/CorePatch). |

> You can also drag any of these onto the MuMu window to install them.

---

## 👉 After setup: install Magisk & modules inside Android

Setup prepped the **Windows** side. The rest happens **inside MuMu**, and the two videos below walk through every tap.

> 🎞️ **Heads up — the videos are slightly out of date.** They flash **LSPosed**, which is now replaced by the bundled **[Vector](Tools/Vector-v2.0-3043-Release.zip)** (a drop-in successor — same steps), and they download a couple of tools by hand that are now **bundled in [`Tools/`](Tools/)**, so your version is a little shorter. The flow is otherwise identical.

**🎬 [Part 1 — root + Play Store](https://www.youtube.com/watch?v=bBj8CE55lpk)**

1. Open MuMu, start your instance, and accept the **root permission** prompt.
2. Install **Magisk Kitsune** (the app appears as **Kitsune Mask**) — drag [`Tools/app-release.apk`](Tools/app-release.apk) onto the MuMu window, open it, let it finish, and reboot the instance if asked.
3. Sign in to the Play Store.

**🎬 [Part 2 — modules, Core Patch & hiding root](https://www.youtube.com/watch?v=XGNkyvmAckE)**

1. Copy the tools into MuMu — use the **shared-folder button** in MuMu's sidebar, or drag a file straight onto the window.
2. In **Kitsune Mask → Modules → Install from storage**, flash the **[NeoZygisk](Tools/NeoZygisk-v2.3-282-8b12252-release.zip)** and **[Vector](Tools/Vector-v2.0-3043-Release.zip)** ZIPs.
3. Install the apps (APKs): **[Hide My Applist](Tools/HMA-OSS-oss-161-release.apk)**, **[MT Manager](Tools/mtmanager.apk)**, **[CorePatch](Tools/core-patch-4.9.apk)**.
4. Open **Vector** (*LSPosed* in the video) → enable **CorePatch** and **Hide My Applist** as modules, set scope to **System Framework**, and turn on CorePatch's options.
5. Hide root where you want it: **Kitsune Mask → Configure MagiskHide** plus **Hide My Applist → App manage**, then restart the instance.

> 💡 **ZIP vs APK:** a **ZIP** is a Magisk module — flash it *inside Kitsune Mask*. An **APK** is a normal app — install it directly. Mixing them up causes the *"unzip error"* you'll see in the video when HMA is flashed as a module by mistake.

---

## ↩️ Undo / Restore

Changed your mind? This puts everything back exactly as it was — it restores every backup setup made.

**Easiest:** download the ZIP (if you haven't), then double-click **`RestoreMuMuConfig.bat`**.

**One command:**

```cmd
cmd.exe /d /c "curl.exe -fL https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/RestoreMuMuConfig.bat -o RestoreMuMuConfig.bat && RestoreMuMuConfig.bat"
```

---

## ❓ FAQ & troubleshooting

#### Is this safe?
Yes. It's plain, readable PowerShell — **no obfuscation, no encoded commands, no persistence, no firewall/hosts edits, no credential access.** It only edits MuMu's own config files (after backing each one up) and never touches anything outside MuMu. The bundled MuMu installer is the official one, [verified by automated checks](#-trust--how-the-installer-is-verified).

#### My antivirus flagged it / "Windows protected your PC"
Common for any admin script that stops emulator processes and edits config files — it's a false positive, not malware. Click **More info → Run anyway**, or temporarily allow the file. Everything it does is visible in [`scripts/MuMuConfig.ps1`](scripts/MuMuConfig.ps1).

#### It says "No MuMu install found"
MuMu 12 isn't installed where the tool can see it. Install it first ([Global download](https://www.mumuplayer.com/download/)), open it once, then re-run.

#### It says "No instances were found"
You need to **create an Android 12 instance** in MuMu's Multi-Instance Manager and **start it once** so its config files exist. Then close MuMu and re-run.

#### Do I have to restart Windows?
No. And the `ExecutionPolicy Bypass` the launcher uses applies **only to that one run** — it does not change any permanent Windows setting.

#### I have both Global and Chinese MuMu
Global is patched by default. To patch both, run `Setup.bat --edition all`.

#### Where do I type the one command?
Press <kbd>Win</kbd>, type `cmd`, press Enter, paste the command, press Enter. (Or just use the [double-click method](#-quick-start) — no typing.)

---

## 🔧 Advanced & transparency

<details id="-exactly-what-it-changes">
<summary><b>📋 Exactly what it changes (and what it doesn't)</b></summary>

<br>

**Per instance** (folders ending in `-base` are skipped):

| File | Key | Set to |
| --- | --- | --- |
| `customer_config.json` | `setting.other_setting.root_mode` | `"1"` (root on) |
| `customer_config.json` | `setting.disk_share.mode.choose` | `"disk_share.mode.writable"` |
| `vm_config.json` | `system_vdi.sharable` / `vm.system_vdi.sharable` | `"Writable"` |
| `shell_config.json` | `player.uu_remote.should_show` | `"false"` (when present) |

**Optional privacy/debloat keys** — only changed if they already exist; no keys are invented:

| File | Key | Set to |
| --- | --- | --- |
| `customer_config.json` | `customer.apk_associate` | `"false"` |
| `customer_config.json` | `customer.app_keptlive` | `"false"` |
| `customer_config.json` | `customer.run_limitation` | `"false"` |
| `customer_config.json` | `setting.other_setting.apk_association` | `"0"` |
| `customer_config.json` | `setting.other_setting.app_keptlive` | `"0"` |
| `customer_config.json` | `setting.other_setting.run_limitation` | `"0"` |
| `…\Netease\…\configs\nx_main.json` | `nxmain.setting.apk_association` | `"0"` |

For the Windows **"Associate APK files"** behavior, MuMu also writes per-user file associations. Setup clears `.apk`, `.xapk`, and `.apks` **only if they currently point to MuMu**, and stores the previous value first so Restore can put it back.

**It does *not*:** add hosts/firewall rules, startup entries, services, or scheduled tasks; block `netease.com`/`easebar.com` (that breaks updates and login); run any silent installers; or use line-by-line text hacks (it parses real JSON).

</details>

<details>
<summary><b>🔍 How it finds your MuMu install</b></summary>

<br>

- Reads the Windows uninstall registry first, including custom `InstallLocation` paths.
- Falls back to known `Program Files\Netease` paths only if the registry lookup fails.
- Patches every non-base instance under `{InstallRoot}\vms\*\configs`.
- Also updates the user-level toggle in `%APPDATA%\Netease\MuMuPlayerGlobal\configs\nx_main.json` (or `MuMuPlayer` for Chinese) when present.
- Creates a `.bak` next to each file before the first write; Restore copies those back.

This project is not pinned to any single MuMu build — it targets the MuMu 12 config schema and is covered by smoke tests. If a future release changes the keys, run with `--dry-run` first and [open an issue](https://github.com/Jordan231111/mumu-magisk-1click/issues) with the output.

</details>

<details>
<summary><b>⚙️ Command-line options</b></summary>

<br>

```cmd
Setup.bat --dry-run            :: show what would change, write nothing
Setup.bat --edition global     :: Global only
Setup.bat --edition chinese    :: Chinese only
Setup.bat --edition all        :: both editions
```

The same flags work on `RestoreMuMuConfig.bat`. Run a dry-run first if you're unsure.

</details>

<details>
<summary><b>🔐 Trust — how the installer is verified</b></summary>

<br>

The bundled `MuMuInstaller_Global.exe` is the **official** Global installer. CI resolves it through MuMu's own API, follows the redirect chain, and fails unless the final URL is an `.exe` from `a11.gdl.netease.com` with a `200` response. It then downloads the file in CI and compares size + MD5 against the committed copy. Metadata is tracked in [installer-url.txt](installer-url.txt), and a scheduled job opens an update PR when MuMu ships a new version.

```text
https://api.mumuplayer.com/api/website/download_version_info?usage=1
https://api.mumuplayer.com/api/dl/win?channel=gw-win-download
```

</details>

<details>
<summary><b>🧪 Run the smoke tests (developers)</b></summary>

<br>

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\Smoke.Tests.ps1
```

The tests build temporary Global and Chinese fixtures, write test registry keys, and verify discovery, setup, restore, and live download resolution. They never install or launch MuMu.

</details>

---

## 🆘 Need help?

Join the Telegram group: **https://t.me/+6EreKfc983UzMjgx**

## ❤️ Support the project

If this saved you time, a small donation keeps it maintained — **[ko-fi.com/yejordan](https://ko-fi.com/yejordan)**. And a ⭐ on the repo genuinely helps!

## 🙏 Credits

- [Magisk Kitsune](https://github.com/HuskyDG/Magisk) · [Magisk (upstream)](https://github.com/topjohnwu/Magisk)
- [Vector](https://github.com/JingMatrix/Vector) (successor to LSPosed) · [Hide My Applist (HMA-OSS)](https://github.com/frknkrc44/HMA-OSS) · [CorePatch](https://github.com/LSPosed/CorePatch)
- [MuMu Player](https://www.mumuplayer.com/)

## ⚖️ Disclaimer

For educational and development use. Root access and a writable system can affect emulator stability and security — only use it on instances you're prepared to modify and restore.

## 📄 License

[CC BY-NC-ND 4.0](LICENSE.md).
