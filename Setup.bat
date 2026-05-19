@echo off
setlocal enabledelayedexpansion

:: Check for admin rights and self-elevate if needed
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    goto UACPrompt
) else (
    goto gotAdmin
)

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" del "%temp%\getadmin.vbs"
    cd /d "%~dp0"

:: Kill MuMu processes
echo Stopping MuMu processes...
taskkill /f /im MuMuVMMHeadless.exe 2>nul
taskkill /f /im MuMuPlayer.exe 2>nul
taskkill /f /im MuMuPlayerService.exe 2>nul
taskkill /f /im MuMuVMMSVC.exe 2>nul
taskkill /f /im MuMuMultiPlayer.exe 2>nul

set "vms_path="

rem Find MuMu vms directory silently
for %%d in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%d:\Program Files\Netease\MuMuPlayer-12.0\vms" (
        set "vms_path=%%d:\Program Files\Netease\MuMuPlayer-12.0\vms"
        echo Found MuMu at: !vms_path!
        goto :process_vms
    )
    if exist "%%d:\Program Files\Netease\MuMu Player 12\vms" (
        set "vms_path=%%d:\Program Files\Netease\MuMu Player 12\vms"
        echo Found MuMu at: !vms_path!
        goto :process_vms
    )
)

if not defined vms_path (
    echo MuMu not found. Please enter the path to your MuMu installation:
    echo Example:     D:\Software\MuMu Player 12
    set /p custom_path="Path: "
    
    rem Trim leading and trailing spaces from input
    for /f "tokens=*" %%a in ("!custom_path!") do set "custom_path=%%a"
    
    if exist "!custom_path!\vms" (
        set "vms_path=!custom_path!\vms"
        echo Found MuMu at: !vms_path!
    ) else (
        echo MuMu vms folder not found at the specified path. Please check your installation path and try again.
        goto :end
    )
)

:process_vms
rem Process non-base instances silently
for /d %%f in ("!vms_path!\*") do (
    echo %%~nxf | find "-base" > nul
    if errorlevel 1 (
        rem Process customer_config.json
        set "config_file=%%f\configs\customer_config.json"
        if exist "!config_file!" (
            if not exist "!config_file!.bak" (
                copy "!config_file!" "!config_file!.bak" > nul
            )
            
            rem Create temp file and process in one pass
            type nul > "%%f\configs\customer_config_temp.json"
            for /f "usebackq delims=" %%l in ("!config_file!") do (
                set "line=%%l"
                echo !line! | find """root_mode"": ""0""" > nul
                if not errorlevel 1 (
                    set "line=!line:"root_mode": "0"="root_mode": "1"!"
                )
                echo !line! | find """choose"": ""disk_share.mode.readonly""" > nul
                if not errorlevel 1 (
                    set "line=!line:"choose": "disk_share.mode.readonly"="choose": "disk_share.mode.writable"!"
                )
                echo !line!>> "%%f\configs\customer_config_temp.json"
            )
            move /y "%%f\configs\customer_config_temp.json" "!config_file!" > nul
            echo [%%~nxf] Updated root_mode and system disk mode in customer_config.json
        )
        
        rem Process vm_config.json
        set "vm_config_file=%%f\configs\vm_config.json"
        if exist "!vm_config_file!" (
            if not exist "!vm_config_file!.bak" (
                copy "!vm_config_file!" "!vm_config_file!.bak" > nul
            )
            
            rem Create temp file and process in one pass
            type nul > "%%f\configs\vm_config_temp.json"
            for /f "usebackq delims=" %%l in ("!vm_config_file!") do (
                set "line=%%l"
                echo !line! | find """sharable"": ""Readonly""" > nul
                if not errorlevel 1 (
                    set "line=!line:"sharable": "Readonly"="sharable": "Writable"!"
                )
                echo !line!>> "%%f\configs\vm_config_temp.json"
            )
            move /y "%%f\configs\vm_config_temp.json" "!vm_config_file!" > nul
            echo [%%~nxf] Updated sharable in vm_config.json
        )
    )
)

echo Done

:end
endlocal 
