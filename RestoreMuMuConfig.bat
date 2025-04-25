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
)

if not defined vms_path (
    echo MuMu not found
    goto :end
)

:process_vms
rem Restore backups silently
for /d %%f in ("!vms_path!\*") do (
    echo %%~nxf | find "-base" > nul
    if errorlevel 1 (
        rem Restore customer_config.json if backup exists
        if exist "%%f\configs\customer_config.json.bak" (
            copy /y "%%f\configs\customer_config.json.bak" "%%f\configs\customer_config.json" > nul
            echo [%%~nxf] Restored customer_config.json
        )
        
        rem Restore vm_config.json if backup exists
        if exist "%%f\configs\vm_config.json.bak" (
            copy /y "%%f\configs\vm_config.json.bak" "%%f\configs\vm_config.json" > nul
            echo [%%~nxf] Restored vm_config.json
        )
    )
)

echo Done

:end
endlocal 