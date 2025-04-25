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
                echo !line!>> "%%f\configs\customer_config_temp.json"
            )
            move /y "%%f\configs\customer_config_temp.json" "!config_file!" > nul
            echo [%%~nxf] Updated root_mode in customer_config.json
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
