$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('mumu-boot-' + [Guid]::NewGuid().ToString('N'))
$script:Assertions = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:Assertions++
}

$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts\Kitsune.ps1'), [ref]$null, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'Kitsune.ps1 has parse errors.'
$definitions = [scriptblock]::Create((@($ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.FunctionDefinitionAst]
} | ForEach-Object { $_.Extent.Text }) -join "`n"))

try {
    $vms = Join-Path $testRoot 'vms'
    foreach ($name in @('MuMuPlayerGlobal-12.0-0', 'MuMuPlayerGlobal-12.0-1', 'MuMuPlayerGlobal-12.0-10', 'MuMuPlayer-12.0-0')) {
        New-Item -ItemType Directory -Path (Join-Path $vms $name) -Force | Out-Null
    }

    & {
        . $definitions
        $context = [pscustomobject]@{
            Install = [pscustomobject]@{ edition = 'global'; install_root = $testRoot; vms_path = $vms }
            Instance = '0'
        }
        $script:ProbeResult = [pscustomobject]@{ ExitCode = 0; TimedOut = $false; Text = "1`r`n" }
        $script:ProbedIndices = @()
        function Invoke-Manager {
            param($Context, $Arguments, $Description, $TimeoutSeconds, [switch]$AllowFailure)
            Assert-True ($Arguments[0] -eq 'sh' -and $Arguments[4] -eq 'getprop sys.boot_completed' -and $TimeoutSeconds -eq 5) 'Boot probe was not the bounded, instance-specific getprop command.'
            $script:ProbedIndices += $Arguments[2]
            return $script:ProbeResult
        }

        $device = [pscustomobject]@{
            ExecutablePath = (Join-Path $testRoot 'nx_device\12.0\shell\MuMuNxDevice.exe')
            CommandLine = ''; ProcessId = 41000; CreationDate = [DateTime]::Now
        }
        $snapshot = [pscustomobject]@{ Devices = @($device); Headless = @() }
        foreach ($arguments in @('-v 0', '-v "0"', '--vmindex 0', '--vmindex="0"', '--vm MuMuPlayerGlobal-12.0-0', '--vm "MuMuPlayerGlobal-12.0-0"', '--vm=MuMuPlayerGlobal-12.0-0')) {
            $device.CommandLine = '"C:\MuMu Player\MuMuNxDevice.exe" ' + $arguments
            $info = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '0')[0]
            Assert-True ($info.is_process_started -and $info.pid -eq 41000 -and $info.is_android_started) "Running Android 12 was not recognized: $arguments"
        }

        foreach ($arguments in @('-v 10', '--vm MuMuPlayerGlobal-12.0-10', '--vm MuMuPlayer-12.0-0', '--other MuMuPlayerGlobal-12.0-0', '--vm MuMuPlayerGlobal-12.0-0-extra')) {
            $device.CommandLine = 'MuMuNxDevice.exe ' + $arguments
            $info = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '0')[0]
            Assert-True (-not $info.is_process_started -and $info.pid -eq 0) "Unrelated process matched instance 0: $arguments"
        }
        $device.CommandLine = 'MuMuNxDevice.exe --vm MuMuPlayerGlobal-12.0-0'
        $device.ExecutablePath = $testRoot + '-other\MuMuNxDevice.exe'
        $info = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '0')[0]
        Assert-True (-not $info.is_process_started) 'A similarly named install outside the selected root was accepted.'

        $snapshot.Devices = @()
        $snapshot.Headless = @([pscustomobject]@{
            CommandLine = 'MuMuVMMHeadless.exe --comment "MuMuPlayerGlobal-12.0-0" --startvm uuid'
            ProcessId = 41001; CreationDate = [DateTime]::Now
        })
        $info = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '0')[0]
        Assert-True ($info.is_process_started -and $info.pid -eq 0 -and $info.headless_pid -eq 41001 -and $info.is_android_started) 'A headless guest depended on a frontend PID.'
        $snapshot.Headless[0].CommandLine = 'MuMuVMMHeadless.exe --comment MuMuPlayer-12.0-0'
        $info = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '0')[0]
        Assert-True ($info.headless_pid -eq 0) 'A Chinese hypervisor matched a Global instance.'
        $context.Install.edition = 'chinese'
        $info = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '0')[0]
        Assert-True ($info.headless_pid -eq 41001 -and $info.is_android_started) 'Chinese instance matching regressed.'
        $context.Install.edition = 'global'

        $snapshot.Headless = @()
        $script:ProbedIndices = @()
        $info = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '0')[0]
        Assert-True ($info.is_android_started -and -not $info.is_process_started -and $script:ProbedIndices.Count -eq 1) 'Unavailable Windows process metadata prevented a verified Android boot.'
        $script:ProbedIndices = @()
        [void](Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot)
        Assert-True ($script:ProbedIndices.Count -eq 0) 'Inventory queried stopped or unrelated guests.'

        foreach ($text in @('', '0', 'error code 1', '{"errcode":1}', "1`nerror", 'boot_completed=1')) {
            $script:ProbeResult.Text = $text
            $info = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '0')[0]
            Assert-True (-not $info.is_android_started) "Invalid boot output was accepted: $text"
        }
        $script:ProbeResult.Text = '1'
        $script:ProbeResult.ExitCode = 7
        $info = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '0')[0]
        Assert-True (-not $info.is_android_started -and $info.boot_probe_exit_code -eq 7) 'A failed shell command was accepted as boot success.'
        $script:ProbeResult.ExitCode = 0
        $script:ProbeResult.TimedOut = $true
        $info = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '0')[0]
        Assert-True (-not $info.is_android_started -and $info.boot_probe_timed_out) 'A timed-out shell command was accepted as boot success.'
    }

    & {
        . $definitions
        $context = [pscustomobject]@{ Instance = '0' }
        $script:Polls = 0
        $script:Launches = 0
        $script:Ready = $false
        $script:NeverReady = $false
        function Invoke-Manager {
            param($Context, $Arguments, $Description, [switch]$AllowFailure, [switch]$ShowOutput)
            Assert-True (($Arguments -join ' ') -eq 'control -v 0 launch') 'Startup issued an unexpected command.'
            $script:Launches++
            [pscustomobject]@{ ExitCode = 0; Text = '{"errcode":0}' }
        }
        function Get-InstanceInfo {
            param($Context)
            $script:Polls++
            [pscustomobject]@{
                is_process_started = $false; is_android_started = ($script:Ready -or ($script:Polls -gt 1 -and -not $script:NeverReady))
                player_state = 'start_finished'; launch_err_code = 0; launch_err_msg = ''
                pid = 0; headless_pid = 0; boot_probe_exit_code = 124; boot_probe_timed_out = $true; boot_probe_output = 'probe diagnostic'
            }
        }
        function Stop-Instance { throw 'A healthy guest was unnecessarily stopped.' }

        $info = Start-Instance -Context $context -TimeoutSeconds 1 -MaxAttempts 1
        Assert-True ($info.is_android_started -and $script:Launches -eq 1 -and $script:Polls -eq 2) 'Startup restarted or rejected Android after boot without a frontend PID.'
        $script:Polls = 0
        $script:Ready = $true
        [void](Start-Instance -Context $context)
        Assert-True ($script:Launches -eq 1 -and $script:Polls -eq 1) 'An already booted guest was relaunched.'

        $script:Ready = $false
        $script:NeverReady = $true
        $message = ''
        try { Start-Instance -Context $context -TimeoutSeconds 1 -MaxAttempts 1 | Out-Null } catch { $message = $_.Exception.Message }
        Assert-True ($message -match 'boot_probe_exit=124' -and $message -match 'boot_probe_timed_out=True' -and $message -match 'probe diagnostic') 'Boot failure hid the shell probe diagnostics or accepted manager state alone.'
    }
    Write-Host "Boot regression tests passed ($script:Assertions assertions)."
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notmatch '^mumu-boot-[a-f0-9]{32}$') { throw 'Unsafe test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
