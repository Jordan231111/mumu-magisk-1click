@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "HELPER=%SCRIPT_DIR%scripts\MuMuConfig.ps1"
set "REMOTE_HELPER=https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/scripts/MuMuConfig.ps1"

net session >nul 2>&1
if %errorlevel% neq 0 goto UACPrompt
goto GotAdmin

:UACPrompt
echo Requesting administrative privileges...
set "params="

:BuildArgs
if "%~1"=="" goto RunElevated
set params=%params% "%~1"
shift /1
goto BuildArgs

:RunElevated
set "VBS=%temp%\mumu-magisk-setup-uac.vbs"
> "%VBS%" echo Set UAC = CreateObject^("Shell.Application"^)
>> "%VBS%" echo UAC.ShellExecute "%ComSpec%", "/k ""%~f0""%params%", "", "runas", 1
cscript //nologo "%VBS%" >nul 2>nul
del "%VBS%" >nul 2>nul
exit /b

:GotAdmin
cd /d "%SCRIPT_DIR%"
echo Running MuMu setup from: %CD%
call :EnsureHelper
if errorlevel 1 exit /b 1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action Setup %*
exit /b %errorlevel%

:EnsureHelper
if exist "%SCRIPT_DIR%.git" if exist "%HELPER%" exit /b 0

if exist "%HELPER%" (
    echo Refreshing PowerShell helper from:
) else (
    echo PowerShell helper not found locally.
    echo Downloading helper from:
)
echo %REMOTE_HELPER%

if not exist "%SCRIPT_DIR%scripts" mkdir "%SCRIPT_DIR%scripts" >nul 2>nul
set "TEMP_HELPER=%temp%\mumu-magisk-MuMuConfig-%random%%random%.ps1"
set "REMOTE_HELPER_REFRESH=%REMOTE_HELPER%?refresh=%random%%random%"

curl.exe -fL "%REMOTE_HELPER_REFRESH%" -o "%TEMP_HELPER%"
if exist "%TEMP_HELPER%" goto ReplaceHelper

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%REMOTE_HELPER_REFRESH%' -OutFile '%TEMP_HELPER%'"
if exist "%TEMP_HELPER%" goto ReplaceHelper

if exist "%HELPER%" (
    echo Failed to refresh scripts\MuMuConfig.ps1; using existing local copy.
    exit /b 0
)

echo Failed to download scripts\MuMuConfig.ps1.
exit /b 1

:ReplaceHelper
move /y "%TEMP_HELPER%" "%HELPER%" >nul 2>nul
if exist "%HELPER%" exit /b 0

echo Failed to download scripts\MuMuConfig.ps1.
exit /b 1
