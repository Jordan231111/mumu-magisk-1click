param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [ValidateSet('global', 'chinese')][string]$Edition = 'global',
    [ValidateRange(1, 5)][int]$Boots = 3,
    [string]$ReportPath
)

# Opt-in only: this suite requires an installed MuMu Android 12 engine.
# It creates its own instance and removes it even if a boot assertion fails.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts\Kitsune.ps1'), [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Kitsune.ps1 has parse errors.' }
. ([scriptblock]::Create((@($ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.FunctionDefinitionAst]
} | ForEach-Object { $_.Extent.Text }) -join "`n")))

Assert-Administrator
$installResult = Invoke-NativeCommand -FilePath (Get-WindowsPowerShellPath) -Arguments @(
    '-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', (Join-Path $repoRoot 'scripts\MuMuConfig.ps1'),
    '-Action', 'FindInstall', '--install-root', $InstallRoot, '--edition', $Edition, '--json'
)
$installs = @($installResult.Text | ConvertFrom-Json)
if ($installs.Count -ne 1) { throw 'Expected exactly one test installation.' }
$context = [pscustomobject]@{
    Install = $installs[0]
    Manager = (Resolve-MuMuManager -InstallRoot $installs[0].install_root)
    Instance = ''
}
$vmsPath = [IO.Path]::GetFullPath($context.Install.vms_path).TrimEnd('\')
$before = @(Get-ChildItem -LiteralPath $vmsPath -Directory | Select-Object -ExpandProperty Name | Sort-Object)
$occupied = @($before | ForEach-Object { if ($_ -match '^MuMuPlayer(?:Global)?-\d+(?:\.\d+)?-(\d+)$') { [int]$Matches[1] } })
$index = 0
while ($occupied -contains $index) { $index++ }
$context.Instance = [string]$index
$prefix = if ($Edition -eq 'global') { 'MuMuPlayerGlobal' } else { 'MuMuPlayer' }
$vmName = "$prefix-12.0-$index"
$instancePath = [IO.Path]::GetFullPath((Join-Path $vmsPath $vmName))
if (-not $instancePath.StartsWith($vmsPath + '\', [StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $instancePath)) { throw 'Unsafe or occupied integration-test instance path.' }
$testName = 'BootRegression-' + [Guid]::NewGuid().ToString('N')
$creationAttempted = $false
$report = [ordered]@{
    mumu_version = (Convert-ManagerJson -Result (Invoke-Manager -Context $context -Arguments @('version')) -Description 'MuMu version').version
    instance = $index
    name = $testName
    original_directories = $before
    boots = @()
    cleaned_up = $false
}

try {
    $creationAttempted = $true
    Write-Step "Creating disposable Android 12 instance $index ($testName)"
    $created = Invoke-Manager -Context $context -Arguments @('create', '-v', $context.Instance, '--version', '12') -TimeoutSeconds 180 -ShowOutput
    if (-not (Test-Path -LiteralPath $instancePath -PathType Container)) { throw "MuMu did not create the requested test instance: $($created.Text)" }
    [void](Invoke-Manager -Context $context -Arguments @('rename', '-v', $context.Instance, '-n', $testName) -ShowOutput)

    for ($boot = 1; $boot -le $Boots; $boot++) {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $info = Invoke-ColdBoot -Context $context
        $timer.Stop()
        $sdk = Invoke-Manager -Context $context -Arguments @('sh', '-v', $context.Instance, '-c', 'getprop ro.build.version.sdk') -TimeoutSeconds 5
        if (-not $info.is_android_started -or $info.boot_probe_output.Trim() -ne '1' -or @('31', '32') -notcontains $sdk.Text.Trim()) {
            throw "Cold boot $boot did not verify the Android 12 guest: $($info | ConvertTo-Json -Compress); SDK=$($sdk.Text)"
        }
        $snapshot = Get-MuMuProcessSnapshot
        $device = @($snapshot.Devices | Where-Object { [int]$_.ProcessId -eq [int]$info.pid })
        $legacyPattern = '(?:^|\s)-v\s+"?' + [regex]::Escape($context.Instance) + '"?(?:\s|$)'
        # Exercise the issue's --vm-only process format against a real guest,
        # even on builds that still supply both -v and --vm in their command line.
        $modernDevices = @($snapshot.Devices | ForEach-Object {
            [pscustomobject]@{
                ExecutablePath = $_.ExecutablePath
                CommandLine = [regex]::Replace($_.CommandLine, '(?:^|\s)-v\s+(?:"\d+"|\d+)(?=\s|$)', '')
                ProcessId = $_.ProcessId
                CreationDate = $_.CreationDate
            }
        })
        $modernInfo = @(Get-InstanceInventoryFromDisk -Context $context -Instance $context.Instance -ProcessSnapshot ([pscustomobject]@{
            Devices = $modernDevices; Headless = $snapshot.Headless
        }))[0]
        if ($device.Count -eq 1 -and $device[0].CommandLine -match '(?:^|\s)--vm\s' -and $modernInfo.pid -ne $info.pid) {
            throw 'The --vm-only process format was not recognized for the real guest.'
        }
        $withoutProcesses = @(Get-InstanceInventoryFromDisk -Context $context -Instance $context.Instance -ProcessSnapshot ([pscustomobject]@{
            Devices = @(); Headless = @()
        }))[0]
        if (-not $modernInfo.is_android_started -or -not $withoutProcesses.is_android_started) {
            throw 'The real Android boot depended on legacy process arguments or Windows process metadata.'
        }
        $report.boots += [ordered]@{
            number = $boot
            seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 2)
            boot_completed = $info.boot_probe_output.Trim()
            sdk = $sdk.Text.Trim()
            device_pid = $info.pid
            headless_pid = $info.headless_pid
            command_line = if ($device.Count -eq 1) { $device[0].CommandLine } else { '' }
            legacy_device_match = ($device.Count -eq 1 -and $device[0].CommandLine -match $legacyPattern)
            vm_name_only_pid = $modernInfo.pid
            ready_without_process_metadata = $withoutProcesses.is_android_started
        }
        # Calling Start-Instance on the running guest must preserve its process.
        $alreadyReady = Start-Instance -Context $context
        if (-not $alreadyReady.is_android_started -or $alreadyReady.headless_pid -ne $info.headless_pid) {
            throw 'An already booted guest was restarted or rejected.'
        }
        Write-Step "Live cold boot $boot of $Boots passed in $($report.boots[-1].seconds) seconds"
    }
} finally {
    if ($creationAttempted -and (Test-Path -LiteralPath $instancePath -PathType Container)) {
        try { Stop-Instance -Context $context } catch { Write-Warning "Clean shutdown failed; asking MuMu to delete its disposable instance: $_" }
        Write-Step "Deleting disposable instance $index ($testName)"
        [void](Invoke-Manager -Context $context -Arguments @('delete', '-v', $context.Instance, '--version', '12') -TimeoutSeconds 180 -ShowOutput)
        if (Test-Path -LiteralPath $instancePath) { throw "MuMu did not remove disposable instance $index." }
    }
    $after = @(Get-ChildItem -LiteralPath $vmsPath -Directory | Select-Object -ExpandProperty Name | Sort-Object)
    $report.cleaned_up = (-not (Test-Path -LiteralPath $instancePath))
    $report.remaining_directories = $after
    if ($ReportPath) {
        $reportFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($reportFile))
        [IO.File]::WriteAllText($reportFile, ($report | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
    }
    if (($before -join "`n") -ne ($after -join "`n")) { throw 'The MuMu directory inventory changed after test cleanup.' }
}
Write-Host "Live MuMu boot tests passed ($Boots cold boots); disposable instance deleted."
