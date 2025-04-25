@echo off
setlocal enabledelayedexpansion

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