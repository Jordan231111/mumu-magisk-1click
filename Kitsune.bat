@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "HELPER=%SCRIPT_DIR%scripts\Kitsune.ps1"
set "CONFIG_HELPER=%SCRIPT_DIR%scripts\MuMuConfig.ps1"
set "GUEST_SCRIPT=%SCRIPT_DIR%scripts\mumu-guest-sanitize.sh"
set "KITSUNE_APK=%SCRIPT_DIR%Tools\app-release.apk"

net session >nul 2>&1
if %errorlevel% equ 0 goto GotAdmin

echo Requesting administrative privileges through the standard Windows UAC prompt...
set "params="
:BuildArgs
if "%~1"=="" goto RunElevated
set params=%params% "%~1"
shift /1
goto BuildArgs

:RunElevated
set "MUMU_ELEVATED_CHILD=1"
set "MUMU_ELEVATE_SCRIPT=%~f0"
set "MUMU_ELEVATE_ARGS=%params%"
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "try { $start = @{ FilePath = $env:MUMU_ELEVATE_SCRIPT; Verb = 'RunAs'; Wait = $true; PassThru = $true }; if ($env:MUMU_ELEVATE_ARGS) { $start.ArgumentList = $env:MUMU_ELEVATE_ARGS }; $process = Start-Process @start; exit $process.ExitCode } catch { Write-Error $_; exit 1 }"
exit /b %errorlevel%

:GotAdmin
cd /d "%SCRIPT_DIR%"
if not exist "%HELPER%" goto MissingFiles
if not exist "%CONFIG_HELPER%" goto MissingFiles
if not exist "%GUEST_SCRIPT%" goto MissingFiles
if not exist "%KITSUNE_APK%" goto MissingFiles

powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%HELPER%" %*
set "EXIT_CODE=%errorlevel%"
if defined MUMU_ELEVATED_CHILD (
    echo.
    pause
)
exit /b %EXIT_CODE%

:MissingFiles
echo One or more required repository files are missing.
echo Run Kitsune.bat from a complete clone or release archive; it never downloads or executes replacement code at runtime.
exit /b 1
