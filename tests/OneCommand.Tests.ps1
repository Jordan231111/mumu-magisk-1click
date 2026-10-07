$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'One-command launcher tests require an elevated console to avoid an interactive UAC prompt.'
    exit 0
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('mumu-one-command-' + [Guid]::NewGuid().ToString('N'))
$assertions = 0

function Invoke-Recipe {
    param([string]$Recipe, [string]$Directory)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $env:ComSpec
    $start.Arguments = $Recipe.Substring('cmd.exe'.Length).TrimStart()
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['MUMU_NO_PAUSE'] = '1'
    $start.EnvironmentVariables.Remove('MUMU_ELEVATED_CHILD')
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { throw 'The README command timed out.' }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Text = $stdout.Result + $stderr.Result }
    } finally {
        if (-not $process.HasExited) {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F 2>&1 | Out-Null
            [void]$process.WaitForExit(5000)
        }
        $process.Dispose()
    }
}

try {
    $sourceRoot = Join-Path $testRoot 'source'
    New-Item -ItemType Directory -Path (Join-Path $sourceRoot 'scripts') -Force | Out-Null
    foreach ($launcher in @('Setup.bat', 'RestoreMuMuConfig.bat')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $launcher) -Destination $sourceRoot
    }
    # Run the actual README command, curl and launchers. A harmless downloaded
    # helper isolates these grammar/download tests from real emulator settings.
    [IO.File]::WriteAllText((Join-Path $sourceRoot 'scripts\MuMuConfig.ps1'), '$ErrorActionPreference = ''Stop''; $null = Get-FileHash -LiteralPath $PSCommandPath; Write-Host "MUMU_ONE_COMMAND_OK"; exit 0')
    $sourceUri = ([Uri]($sourceRoot + '\')).AbsoluteUri
    $readme = [IO.File]::ReadAllText((Join-Path $repoRoot 'README.md'))
    $recipes = [regex]::Matches($readme, '(?m)^cmd\.exe /d /c "[^\r\n]+"')
    if ($recipes.Count -ne 2) { throw 'Expected the Setup and Restore download commands in README.md.' }
    foreach ($entry in $recipes) {
        $recipe = $entry.Value.Replace('https://raw.githubusercontent.com/Jordan231111/mumu-magisk-1click/main/', $sourceUri)
        if ($recipe -eq $entry.Value) { throw 'README download source was not recognized.' }
        $runRoot = Join-Path $testRoot ([Guid]::NewGuid().ToString('N') + ' & [repeat]')
        New-Item -ItemType Directory -Path $runRoot | Out-Null
        foreach ($run in 1, 2) {
            $result = Invoke-Recipe -Recipe $recipe -Directory $runRoot
            if ($result.ExitCode -ne 0 -or $result.Text -notmatch 'MUMU_ONE_COMMAND_OK') {
                throw "README command failed on run $run`: $($result.Text)"
            }
            $assertions++
        }
        $failedRecipe = $recipe.Replace('scripts/MuMuConfig.ps1', 'scripts/missing-helper.ps1')
        $failure = Invoke-Recipe -Recipe $failedRecipe -Directory $runRoot
        if ($failure.ExitCode -eq 0 -or $failure.Text -match 'MUMU_ONE_COMMAND_OK') {
            throw 'A failed download ran the previously downloaded helper.'
        }
        $assertions++
    }
    Write-Host "One-command tests passed ($assertions clean/repeat/failure scenarios)."
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notmatch '^mumu-one-command-[a-f0-9]{32}$') { throw 'Unsafe one-command test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
