# 🚀 MuMu Magisk 1-Click Setup

![MuMu Magisk Setup](https://i.imgur.com/yourimage.png)

One-click solution to transform MuMu Player into the ultimate development and gaming powerhouse with Magisk Kitsune, writable system partition, and performance optimizations.

## ✨ Features

- **Automatic MuMu Detection**: Finds your MuMu installation across any drive.
- **Root Access**: Enables root mode in MuMu configuration.
- **Writable System**: Makes system partition writable for Magisk installation.
- **Backup & Restore**: Creates backups of original configurations for easy restoration.
- **Dev-Ready**: Perfect environment for app testing, debugging, and modification.
- **Gaming Optimized**: Performance tweaks for maximum FPS and smoothness.

## 🔧 Quick Installation

### Windows

**Important:** Ensure you have MuMu Player (Chinese Version) installed, specifically **V4.1.24.3688**. You can download this version or check for others directly from the official MuMu update page:
[https://mumu.163.com/update/](https://mumu.163.com/update/)
or

```cmd
curl -L "https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/MuMuInstaller_3.1.13.1_V4.1.24.
3688_zh-Hans_1745029888_2.exe" -o mumu_installer.exe && mumu_installer.exe
```

*Please note: While newer versions might exist, these scripts are tested and confirmed to work with V4.1.24.3688.*

**Before running the setup script:**

1. Launch MuMu Player.
2. Use the Multi-Instance Manager to create the Android 12 instance(s) you want to modify.
3. **Important:** Completely close MuMu Player and all its running instances.

Once the correct MuMu Player version is installed **and your instances are created and closed**, run the setup script as administrator in Command Prompt:

```cmd
curl -s https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/Setup.bat -o setup.bat && setup.bat
```

## ⚙️ Visual Settings Guide (Chinese vs English)

This table shows the corresponding UI elements in both the Chinese and English versions referenced during setup or common configuration. The English labels provide context for the Chinese UI screenshots.

| Setting (English Label)      | Chinese UI (`ChineseAssets/`)                                       | English UI (`assets/`)                                                 |
| ---------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| **Performance Settings**     | ![Perf Settings](ChineseAssets/MuMuPlayer_syw6Ig9jQV.png)             | ![Perf Settings](assets/MuMuPlayer_syw6Ig9jQV.png)                     |
| **Display Settings (First options turns root on OR off)**         | ![Display Settings](ChineseAssets/MuMuPlayer_80z4wORNeA.png)          | ![Display Settings](assets/MuMuPlayer_80z4wORNeA%20(1).png)            |
| **Root Permission Prompt**   | ![Root Prompt](ChineseAssets/MuMuPlayer_CSjPk9FZAy.png)               | ![Root Prompt](assets/MuMuPlayer_CSjPk9FZAy.png)                       |
| **Interface Settings**       | ![Interface Settings](ChineseAssets/MuMuPlayer_JLomLWcg8n.png)        | ![Interface Settings](assets/MuMuPlayer_JLomLWcg8n.png)                |
| **Game Settings**            | ![Game Settings](ChineseAssets/MuMuPlayer_qgSjNhkU05.png)             | ![Game Settings](assets/MuMuPlayer_qgSjNhkU05.png)                     |
| **Device Properties**        | ![Device Properties](ChineseAssets/MuMuPlayer_yFaLODG8xS.png)         | ![Device Properties](assets/MuMuPlayer_yFaLODG8xS.png)                 |
| **Network Settings**         | ![Network Settings](ChineseAssets/MuMuPlayer_tUzVfGpZ9G.png)          | ![Network Settings](assets/MuMuPlayer_tUzVfGpZ9G.png)                  |
| **FPS settings**      | ![Shortcuts](ChineseAssets/MuMuPlayer_9t5cRTMdC6.png)                 | ![Shortcuts](assets/MuMuPlayer_9t5cRTMdC6.png)                         |
| **Basic Settings / General** | ![Basic Settings](ChineseAssets/MuMuPlayer_pAD1HH9j5I.png)            | ![Basic Settings](assets/MuMuPlayer_pAD1HH9j5I.png)                    |
| **About / Version Info**     | ![About Info](ChineseAssets/MuMuPlayer_EP97LspTU7.png)                | ![About Info](assets/MuMuPlayer_EP97LspTU7.png)                        |
| **Multi-Instance Manager**   | ![Multi-Instance Mgr](ChineseAssets/MuMuPlayer_QNt9uBiTYE.png)        | ![Multi-Instance Mgr](assets/MuMuPlayer_QNt9uBiTYE.png)                |

### What Happens Behind the Scenes

1. The script searches all drives for MuMu 12.0 installation.
2. When found, it backs up original configuration files.
3. Updates `customer_config.json` to enable root mode.
4. Updates `vm_config.json` to make the system partition writable.
5. Prepares the environment for Magisk Kitsune installation.

## 🔄 Restore Original Settings

If you need to revert changes, simply run:

```cmd
curl -s https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/RestoreMuMuConfig.bat -o restore.bat && restore.bat
```

## 📋 Requirements

- MuMu Player (Chinese Version) - **V4.1.24.3688** recommended (Download from [official site](https://mumu.163.com/update/)).
- Windows 10/11.
- Administrator rights.
- Internet connection (for initial script download).

## 🛠️ Advanced Usage

After running the setup, you can:

1. Install Magisk Kitsune directly in MuMu.
2. Apply other system modifications freely due to writable system.
3. Use ADB/development tools with root access.
4. Test apps with elevated permissions and hooks.

## 🤝 Contributing

Contributions welcome! Feel free to:

- Report bugs.
- Suggest enhancements.
- Submit pull requests.
- Share your experiences.

## ⚠️ Disclaimer

This tool is for educational and development purposes only. Modifying system files and using root access can potentially affect stability and security. Use at your own risk. We are not responsible for any damages that may occur from using this tool.

## 📜 License

See LICENSE file for details.
