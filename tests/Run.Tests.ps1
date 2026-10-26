$ErrorActionPreference = 'Stop'
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$powerShell7 = (Get-Command pwsh.exe -ErrorAction Stop).Source

foreach ($suite in @('Smoke', 'Boot', 'Installer', 'Correctness', 'GuestRecovery', 'OneCommand')) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', (Join-Path $PSScriptRoot ($suite + '.Tests.ps1')))
    if ($suite -eq 'Smoke') { $arguments += '-SkipDownload' }
    Write-Host "Running $suite tests in Windows PowerShell"
    & $windowsPowerShell @arguments
    if ($LASTEXITCODE -ne 0) { throw "$suite tests failed in Windows PowerShell (exit $LASTEXITCODE)." }
}
foreach ($suite in @('Boot', 'Installer', 'Correctness', 'OneCommand')) {
    Write-Host "Running $suite tests in PowerShell 7"
    & $powerShell7 -NoProfile -File (Join-Path $PSScriptRoot ($suite + '.Tests.ps1'))
    if ($LASTEXITCODE -ne 0) { throw "$suite tests failed in PowerShell 7 (exit $LASTEXITCODE)." }
}
Write-Host 'All regression suites passed in both supported PowerShell hosts.'
