@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "HELPER=%SCRIPT_DIR%scripts\MuMuConfig.ps1"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
rem Avoid inheriting incompatible PowerShell 7 modules through cmd.exe.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
set "EXIT_CODE=1"
set "DID_PUSHD="
set "PAUSE_ON_EXIT="
if "%~1"=="" set "PAUSE_ON_EXIT=1"
if defined MUMU_ELEVATED_CHILD set "PAUSE_ON_EXIT=1"

if not exist "%POWERSHELL%" goto MissingPowerShell
if not exist "%HELPER%" goto MissingFiles

"%POWERSHELL%" -NoProfile -Command "try { $identity = [Security.Principal.WindowsIdentity]::GetCurrent(); $principal = New-Object Security.Principal.WindowsPrincipal($identity); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 }; exit 1 } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 2 }"
if errorlevel 2 goto Finish
if not errorlevel 1 goto GotAdmin
if defined MUMU_ELEVATED_CHILD goto ElevationFailed

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
"%POWERSHELL%" -NoProfile -ExecutionPolicy RemoteSigned -Command "try { $start = @{ FilePath = $env:MUMU_ELEVATE_SCRIPT; Verb = 'RunAs'; Wait = $true; PassThru = $true }; if ($env:MUMU_ELEVATE_ARGS) { $start.ArgumentList = $env:MUMU_ELEVATE_ARGS }; $process = Start-Process @start; exit $process.ExitCode } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }"
set "EXIT_CODE=%errorlevel%"
if "%EXIT_CODE%"=="0" set "PAUSE_ON_EXIT="
goto Finish

:GotAdmin
pushd "%SCRIPT_DIR%"
if errorlevel 1 goto Finish
set "DID_PUSHD=1"

rem Unblock only the bundled helper; keep RemoteSigned and permanent policy unchanged.
"%POWERSHELL%" -NoProfile -Command "try { Unblock-File -LiteralPath $env:HELPER -ErrorAction Stop } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }"
if errorlevel 1 goto Finish
echo Running MuMu setup from: "%CD%"
"%POWERSHELL%" -NoProfile -ExecutionPolicy RemoteSigned -File "%HELPER%" -Action Setup %*
set "EXIT_CODE=%errorlevel%"
goto Finish

:MissingFiles
echo Required file is missing: scripts\MuMuConfig.ps1
echo Extract the complete ZIP first, or use the complete download command in README.md.
goto Finish

:MissingPowerShell
echo Windows PowerShell was not found. This tool requires Windows PowerShell 5.1.
goto Finish

:ElevationFailed
echo Administrative privileges were not granted. Run Setup.bat as administrator.

:Finish
if defined DID_PUSHD popd
if not "%EXIT_CODE%"=="0" echo Setup failed with exit code %EXIT_CODE%. See the error above.
if defined MUMU_NO_PAUSE set "PAUSE_ON_EXIT="
if defined PAUSE_ON_EXIT pause
exit /b %EXIT_CODE%
