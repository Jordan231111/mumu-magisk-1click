$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('mumu-correctness-' + [Guid]::NewGuid().ToString('N'))
$script:Assertions = 0
$script:PausePrompt = (& $env:ComSpec /d /c 'pause <nul' | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($script:PausePrompt)) { throw 'Could not determine the native pause prompt.' }

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:Assertions++
}

function Get-ToolDefinitions {
    param([string]$Name)
    $path = Join-Path $repoRoot ('scripts\' + $Name)
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "Parse errors in $Name"
    # Load definitions in a private test scope, without executing the CLI entrypoint.
    return [scriptblock]::Create((@($ast.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.FunctionDefinitionAst]
    } | ForEach-Object { $_.Extent.Text }) -join "`n"))
}

function Invoke-Launcher {
    param([string]$Path, [string]$Arguments, [switch]$ExpectPause, [switch]$NoPause)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $env:ComSpec
    $start.Arguments = '/d /c ""' + $Path + '" ' + $Arguments + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables.Remove('MUMU_ELEVATED_CHILD')
    $start.EnvironmentVariables.Remove('MUMU_NO_PAUSE')
    if ($NoPause) { $start.EnvironmentVariables['MUMU_NO_PAUSE'] = '1' }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $stderr = $process.StandardError.ReadToEndAsync()
        $prefix = ''
        if ($ExpectPause) {
            # Wait for the result, not a fixed startup delay. Otherwise a slow
            # PowerShell child can consume the key intended for cmd.exe's pause.
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            $resultSeen = $false
            do {
                $lineTask = $process.StandardOutput.ReadLineAsync()
                $remaining = [Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds)
                Assert-True ($lineTask.Wait($remaining)) "Launcher did not report a result: $Path"
                $line = $lineTask.Result
                if ($null -eq $line) { break }
                $prefix += $line + "`n"
                $resultSeen = $line -match 'failed with exit code [0-9]+'
            } while (-not $resultSeen -and [DateTime]::UtcNow -lt $deadline)
            Assert-True ($resultSeen) "Launcher did not reach its result prompt: $Path"
            # Service-hosted Windows runners can return from native pause without
            # a console. Verify its localized prompt in both environments, and
            # acknowledge it only when a console actually waits for input.
            if (-not $process.WaitForExit(500)) {
                $process.StandardInput.WriteLine(' ')
                $process.StandardInput.Flush()
            }
        }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        Assert-True ($process.WaitForExit(30000)) "Launcher hung: $Path"
        if ($ExpectPause) {
            Assert-True ($stdout.Result.Trim() -eq $script:PausePrompt) "Launcher did not request acknowledgement: $Path. Remaining output: $($stdout.Result)"
        }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Text = $prefix + $stdout.Result + $stderr.Result }
    } finally {
        if (-not $process.HasExited) {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F 2>&1 | Out-Null
            [void]$process.WaitForExit(5000)
        }
        $process.Dispose()
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $configDefinitions = Get-ToolDefinitions 'MuMuConfig.ps1'
    $kitsuneDefinitions = Get-ToolDefinitions 'Kitsune.ps1'

    & {
        . $configDefinitions
        $script:Options = @{ Json = $false; DryRun = $false; NoKill = $false; Edition = 'auto'; Action = 'Setup' }
        $script:StopIds = @()
        $script:ProcessLookups = 0
        function Write-Log { param($Message) }
        function Get-Service { param($Name, $ErrorAction) }
        function Stop-Service { throw 'A real service must never be stopped by this test.' }
        function Get-Process {
            param($Name, $ErrorAction)
            $script:ProcessLookups++
            [pscustomobject]@{ Id = 41001; ProcessName = 'MuMuNxMain' }
        }
        function Stop-Process { param($Id, [switch]$Force, $ErrorAction) $script:StopIds += $Id }
        function Get-CimInstance {
            param($ClassName, $ErrorAction)
            if ($ClassName -eq 'Win32_Process') {
                [pscustomobject]@{ ProcessId = 41001; Name = 'MuMuNxMain.exe'; ExecutablePath = 'C:\MuMu\nx_main\MuMuNxMain.exe' }
                [pscustomobject]@{ ProcessId = 41002; Name = 'MuMuPlayerRemoteBackend.exe'; ExecutablePath = 'C:\MuMu\nx_main\MuMuPlayerRemoteBackend.exe' }
                [pscustomobject]@{ ProcessId = 41003; Name = 'unrelated.exe'; ExecutablePath = 'C:\MuMuOther\unrelated.exe' }
            }
        }
        Stop-MuMuProcesses -Installs @([pscustomobject]@{ install_root = 'C:\MuMu' })
        Assert-True (($script:StopIds -join ',') -eq '41001,41002') 'Process stopping skipped, repeated, or targeted the wrong PID.'
        Assert-True ($script:ProcessLookups -eq 1) 'Process names should be checked in one enumeration.'

        function Find-MuMuInstall { param($Edition) [pscustomobject]@{ install_root = 'C:\fixture' } }
        function Stop-MuMuProcesses { throw 'Dry-run attempted to stop MuMu.' }
        function Invoke-SetupInstall { param($Install) [pscustomobject]@{ instances_processed = 1; files_changed = 0; files_would_change = 3; registry_changed = 0; registry_would_change = 0 } }
        function Invoke-RestoreInstall { param($Install) [pscustomobject]@{ files_restored = 3; registry_restored = 0 } }
        function Write-JsonResult { param($Value) }
        Assert-True ((Invoke-Main Setup --dry-run --json) -eq 0) 'Setup dry-run failed.'
        Assert-True ((Invoke-Main Restore --dry-run --json) -eq 0) 'Restore dry-run failed.'

        $originalCulture = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            Read-Arguments InspectInstallConfigs
            Assert-True ($script:Options.Action -ceq 'inspectinstallconfigs') 'Action parsing depends on the current culture.'
        } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture }
    }

    & {
        . $configDefinitions
        $script:Options = @{ DryRun = $false; Json = $true }
        $configPath = Join-Path $testRoot 'unicode [config].json'
        $unicodeName = -join ([char]0x6D4B, [char]0x8BD5, [char]0xD83D, [char]0xDE00)
        $json = '{"name":"' + $unicodeName + '","setting":{"other_setting":{"root_mode":"0"},"disk_share":{"mode":{"choose":"disk_share.mode.readonly"}}},"customer":{"apk_associate":true},"unrelated":[1,2,3]}'
        [IO.File]::WriteAllText($configPath, $json, [Text.UTF8Encoding]::new($false))
        $beforeHash = (Get-FileHash -LiteralPath $configPath).Hash
        $result = Invoke-JsonPatchFile -Path $configPath -Patch ${function:Patch-CustomerConfig}
        $patched = Read-JsonFile -Path $configPath
        Assert-True ($result.changed) 'A valid config was not patched.'
        Assert-True ($patched.name -ceq $unicodeName) 'UTF-8 names were corrupted.'
        Assert-True ($patched.customer.apk_associate -is [bool] -and -not $patched.customer.apk_associate) 'A boolean config value changed type.'
        Assert-True (($patched.unrelated -join ',') -eq '1,2,3') 'Unrelated data changed.'
        Assert-True ((Get-FileHash -LiteralPath "$configPath.bak").Hash -eq $beforeHash) 'Backup differs from the original bytes.'
        $afterHash = (Get-FileHash -LiteralPath $configPath).Hash
        $repeat = Invoke-JsonPatchFile -Path $configPath -Patch ${function:Patch-CustomerConfig}
        Assert-True (-not $repeat.changed -and (Get-FileHash -LiteralPath $configPath).Hash -eq $afterHash) 'Repeated Setup rewrote unchanged data.'
        Assert-True ((Get-FileHash -LiteralPath "$configPath.bak").Hash -eq $beforeHash) 'Repeated Setup overwrote the original backup.'
        Assert-True (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.tmp').Count -eq 0) 'Atomic write left temporary files.'

        $lock = [IO.File]::Open($configPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $failed = $false
        try { Write-JsonFile -Path $configPath -Json ([pscustomobject]@{ invalid = 'replacement' }) }
        catch { $failed = $true }
        finally { $lock.Dispose() }
        Assert-True ($failed -and (Get-FileHash -LiteralPath $configPath).Hash -eq $afterHash) 'Failed write damaged the existing config.'
        Assert-True (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.tmp').Count -eq 0) 'Failed write left a temporary file.'

        $malformed = Join-Path $testRoot 'malformed.json'
        [IO.File]::WriteAllText($malformed, '{ invalid')
        $failed = $false
        try { Invoke-JsonPatchFile -Path $malformed -Patch ${function:Patch-CustomerConfig} | Out-Null }
        catch { $failed = $true }
        Assert-True ($failed -and [IO.File]::ReadAllText($malformed) -eq '{ invalid' -and -not (Test-Path -LiteralPath "$malformed.bak")) 'Malformed JSON was changed or backed up.'

        $configs = Join-Path $testRoot 'restore\vms\MuMuPlayer-12.0-0\configs'
        New-Item -ItemType Directory -Path $configs -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $configs 'customer_config.json'), 'changed')
        [IO.File]::WriteAllText((Join-Path $configs 'customer_config.json.bak'), 'original')
        [IO.File]::WriteAllText((Join-Path $configs 'unrelated.json'), 'keep')
        [IO.File]::WriteAllText((Join-Path $configs 'unrelated.json.bak'), 'foreign backup')
        function Restore-UserConfigBackups { param($Install) }
        function Restore-ApkAssociation { param($Install) [pscustomobject]@{ restored = 0 } }
        $restore = Invoke-RestoreInstall -Install ([pscustomobject]@{ vms_path = (Join-Path $testRoot 'restore\vms') })
        Assert-True ($restore.files_restored -eq 1 -and [IO.File]::ReadAllText((Join-Path $configs 'customer_config.json')) -eq 'original') 'Managed backup was not restored.'
        Assert-True ([IO.File]::ReadAllText((Join-Path $configs 'unrelated.json')) -eq 'keep') 'Restore copied an unrelated backup.'
    }

    & {
        . $configDefinitions
        $script:Options = @{ Json = $true }
        function Invoke-RestMethod {
            param($Uri, $Headers, [switch]$UseBasicParsing, $TimeoutSec)
            [pscustomobject]@{ data = @([pscustomobject]@{ platform = 'win'; version = 'test'; update_time = 0 }) }
        }
        function Invoke-HeadRequest {
            param($Url)
            $response = [pscustomobject]@{ StatusCode = 302; Headers = @{ Location = '/loop.exe' }; ContentLength = 1 }
            Add-Member -InputObject $response -MemberType ScriptMethod -Name Close -Value { }
            return $response
        }
        $refused = $false
        try { Resolve-MuMuDownload | Out-Null } catch { $refused = $_.Exception.Message -match 'successful final response' }
        Assert-True ($refused) 'A redirect loop was accepted as a completed download resolution.'

        $output = Join-Path $testRoot 'installer.exe'
        $metadata = Join-Path $testRoot 'installer.txt'
        [IO.File]::WriteAllText($output, 'original installer')
        [IO.File]::WriteAllText($metadata, 'original metadata')
        $script:FailTransfer = $false
        function Invoke-WebRequest {
            param($Uri, $Headers, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
            [IO.File]::WriteAllText($OutFile, 'replacement')
            if ($script:FailTransfer) { throw 'Simulated interrupted download.' }
        }
        $info = [pscustomobject]@{ content_length = 12; final_url = 'https://example.invalid/installer.exe'; final_md5_hex = '' }
        foreach ($failure in @('size', 'hash', 'transfer')) {
            if ($failure -eq 'hash') { $info.content_length = 11; $info.final_md5_hex = '00000000000000000000000000000000' }
            if ($failure -eq 'transfer') { $script:FailTransfer = $true }
            $refused = $false
            try { Save-MuMuInstaller -Info $info -OutputPath $output -MetadataPath $metadata | Out-Null } catch { $refused = $true }
            Assert-True ($refused -and [IO.File]::ReadAllText($output) -eq 'original installer' -and [IO.File]::ReadAllText($metadata) -eq 'original metadata') "Failed $failure verification overwrote an existing download."
            Assert-True (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.download').Count -eq 0) 'A failed download left temporary data.'
        }
        $script:FailTransfer = $false
        $info.content_length = 11
        $info.final_md5_hex = ''
        $saved = Save-MuMuInstaller -Info $info -OutputPath $output -MetadataPath $metadata
        Assert-True ([IO.File]::ReadAllText($output) -eq 'replacement' -and $saved.content_length -eq 11) 'Validated download did not replace the existing installer.'
        Assert-True ([IO.File]::ReadAllText($metadata) -match 'MD5=') 'Validated download metadata was not saved.'
        $refused = $false
        try { Save-MuMuInstaller -Info $info -OutputPath $output -MetadataPath $output | Out-Null } catch { $refused = $true }
        Assert-True ($refused -and [IO.File]::ReadAllText($output) -eq 'replacement') 'Metadata was allowed to overwrite the installer.'
    }

    & {
        . $kitsuneDefinitions
        $script:Options = @{ Instance = $null; Edition = 'auto'; Boots = 1; ApkPath = 'fixture'; GuestScript = 'fixture' }
        $installRoot = Join-Path $testRoot 'inventory'
        $vms = Join-Path $installRoot 'vms'
        foreach ($index in 1, 2) {
            New-Item -ItemType Directory -Path (Join-Path $vms "MuMuPlayerGlobal-12.0-$index\configs") -Force | Out-Null
        }
        $script:ProbedIndices = @()
        function Invoke-Manager {
            param($Context, $Arguments, $Description, $TimeoutSeconds, [switch]$AllowFailure)
            $script:ProbedIndices += $Arguments[2]
            [pscustomobject]@{ ExitCode = 0; Text = '1' }
        }
        $snapshot = [pscustomobject]@{
            Devices = @(
                [pscustomobject]@{ ExecutablePath = "$installRoot\nx_device\12.0\MuMuNxDevice.exe"; CommandLine = 'MuMuNxDevice.exe -v "1"'; ProcessId = 42001; CreationDate = [DateTime]::Now },
                [pscustomobject]@{ ExecutablePath = 'C:\AnotherMuMu\MuMuNxDevice.exe'; CommandLine = 'MuMuNxDevice.exe -v 2'; ProcessId = 42002; CreationDate = [DateTime]::Now }
            )
            Headless = @(
                [pscustomobject]@{ ExecutablePath = 'C:\Program Files\MuMuVMMVbox\Hypervisor\MuMuVMMHeadless.exe'; CommandLine = 'headless --comment "MuMuPlayerGlobal-12.0-1"'; ProcessId = 42003; CreationDate = [DateTime]::Now },
                [pscustomobject]@{ ExecutablePath = 'C:\AnotherMuMu\MuMuVMMHeadless.exe'; CommandLine = 'headless --comment MuMuPlayer-12.0-2'; ProcessId = 42004; CreationDate = [DateTime]::Now }
            )
        }
        $context = [pscustomobject]@{ Install = [pscustomobject]@{ edition = 'global'; install_root = $installRoot; vms_path = $vms }; Instance = '1' }
        $inventory = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot)
        Assert-True ($inventory.Count -eq 2 -and $inventory[0].is_android_started -and $inventory[0].pid -eq 42001) 'Quoted instance arguments were not matched.'
        Assert-True (-not $inventory[1].is_process_started -and $inventory[1].headless_pid -eq 0) 'Another MuMu edition was mistaken for this one.'
        $script:ProbedIndices = @()
        $one = @(Get-InstanceInventoryFromDisk -Context $context -ProcessSnapshot $snapshot -Instance '2')
        Assert-True ($one.Count -eq 1 -and $script:ProbedIndices.Count -eq 0) 'Polling one stopped instance queried other running guests.'

        function Get-AllInstanceInfo {
            param($Context)
            [pscustomobject]@{ index = '1'; name = 'Android 12'; android_version = '12.0'; last_launch_timestamp = 1; is_process_started = $false; is_android_started = $false; headless_pid = 0 }
            [pscustomobject]@{ index = '2'; name = 'Android 15'; android_version = '15.0'; last_launch_timestamp = 2; is_process_started = $false; is_android_started = $false; headless_pid = 0 }
        }
        $refused = $false
        try { Resolve-TargetInstance -Context $context | Out-Null }
        catch { $refused = $_.Exception.Message -match 'Android 15' }
        Assert-True ($refused) 'The most recent unsupported Android instance was not refused.'

        $script:GuestOutput = @()
        function Invoke-ManagerShell {
            param($Context, $Command, $TimeoutSeconds, [switch]$AllowFailure)
            [pscustomobject]@{ ExitCode = 0; Output = $script:GuestOutput; Text = ($script:GuestOutput -join "`n") }
        }
        Assert-True (-not (Test-SystemModeRunning -Context $context)) 'A successful manager exit hid a failed guest system-mode check.'
        $script:GuestOutput = @('__MUMU_MAGISK_SYSTEM_MODE_OK__')
        Assert-True (Test-SystemModeRunning -Context $context) 'A confirmed system-mode check was rejected.'

        $script:Samples = 0
        function Invoke-RootShell {
            param($Context, $Command, $Phase)
            $script:Samples++
            if ($script:Samples -eq 2) { return 'unreadable' }
            if ($script:Samples -gt 5) { throw 'Daemon sampling did not finish.' }
            return '1'
        }
        function Start-Sleep { param($Seconds) }
        Wait-ForStableMagiskDaemon -Context $context
        Assert-True ($script:Samples -eq 5) 'Invalid daemon output reused a previous successful sample.'

        $native = Invoke-NativeCommand -FilePath (Get-WindowsPowerShellPath) -Arguments @('-NoProfile', '-Command', '[Console]::Out.WriteLine("out"); [Console]::Error.WriteLine("err"); exit 7') -AllowFailure
        Assert-True ($native.ExitCode -eq 7 -and $native.Output -contains 'out' -and $native.Output -contains 'err') 'Native command lost output or the exit code.'
        $timeout = Invoke-NativeCommand -FilePath (Get-WindowsPowerShellPath) -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30') -TimeoutSeconds 1 -AllowFailure
        Assert-True ($timeout.TimedOut -and $timeout.ExitCode -eq 124) 'Native command timeout did not terminate the child.'
    }

    & {
        . $kitsuneDefinitions
        $script:PackageName = 'io.github.huskydg.magisk'
        $context = [pscustomobject]@{ Instance = '7' }
        $script:ShellLines = @()
        function Invoke-ManagerShell {
            param($Context, $Command, $TimeoutSeconds, [switch]$AllowFailure)
            [pscustomobject]@{ ExitCode = 0; Output = $script:ShellLines; Text = ($script:ShellLines -join "`n") }
        }
        Assert-True (-not (Test-KitsuneAppRoot -Context $context)) 'Empty MuMu output was accepted as app root.'
        $script:ShellLines = @('10051 io.github.huskydg.magisk:root:0', '0 another.package:root:0')
        Assert-True (-not (Test-KitsuneAppRoot -Context $context)) 'An unprivileged or unrelated process was accepted as Kitsune root.'
        $script:ShellLines = @('    0 io.github.huskydg.magisk:root:0')
        Assert-True (Test-KitsuneAppRoot -Context $context) 'Verified Kitsune root service was rejected.'

        foreach ($lines in @(@('MUMU_SYSTEM_INSTALL_PRESENT'), @())) {
            $script:ShellLines = $lines
            $refused = $false
            try { Assert-NoExistingSystemInstall -Context $context } catch { $refused = $true }
            Assert-True ($refused) 'Existing or unverified System Mode was allowed into preparation.'
        }
        $script:ShellLines = @('MUMU_SYSTEM_INSTALL_ABSENT')
        Assert-NoExistingSystemInstall -Context $context

        $script:AdbUid = '0'
        $script:SuIdentity = 'uid=0(root) gid=0(root) context=u:r:magisk:s0'
        $script:SuExit = 0
        $script:SuRequests = 0
        function Invoke-Manager {
            param($Context, $Arguments, $Description, $TimeoutSeconds, [switch]$AllowFailure)
            if ($Arguments[0] -ne 'adb') { throw 'Authorization used the privileged vendor sh channel.' }
            if ($Arguments[-1] -eq 'shell id -u') { return [pscustomobject]@{ ExitCode = 0; Text = $script:AdbUid } }
            if ($Arguments[-1] -ne 'shell /sbin/magisk su -c id') { throw 'Unexpected authorization command.' }
            $script:SuRequests++
            [pscustomobject]@{ ExitCode = $script:SuExit; Text = $script:SuIdentity }
        }
        Assert-True (-not (Test-KitsuneShellAuthorization -Context $context) -and $script:SuRequests -eq 0) 'Root ADB bypassed the Android Shell authorization check.'
        $script:AdbUid = '2000'
        $script:SuIdentity = 'uid=0(root) gid=0(root) context=u:r:init:s0'
        Assert-True (-not (Test-KitsuneShellAuthorization -Context $context)) 'Vendor root was accepted as Magisk authorization.'
        $script:SuIdentity = 'uid=0(root) gid=0(root) context=u:r:magisk:s0'
        Assert-True (Test-KitsuneShellAuthorization -Context $context) 'Actual Android Shell Magisk root was rejected.'
        $script:SuExit = 13
        Assert-True (-not (Test-KitsuneShellAuthorization -Context $context)) 'A denied su request was accepted.'

        $script:AppLaunches = 0
        function Invoke-Manager { param($Context, $Arguments, $Description) }
        function Launch-Kitsune { param($Context) $script:AppLaunches++ }
        $script:ShellLines = @('MUMU_KITSUNE_STOPPED')
        Restart-Kitsune -Context $context
        Assert-True ($script:AppLaunches -eq 1) 'Kitsune did not relaunch after its stop was verified.'
        $script:AppLaunches = 0
        function Restart-Kitsune { param($Context) $script:AppLaunches++ }
        function Test-KitsuneAppRoot { param($Context) return ($script:AppLaunches -ge 2) }
        Ensure-KitsuneAppRoot -Context $context -RootTimeoutSeconds 1
        Assert-True ($script:AppLaunches -eq 2) 'Preparation did not restart Kitsune after its cached root failure.'
    }

    & {
        . $kitsuneDefinitions
        $script:Options = @{ Action = 'prepare' }
        $script:RemoteSanitizer = '/data/local/tmp/mumu-magisk-guest-sanitize.sh'
        $script:Events = @()
        $script:ExistingInstall = $false
        $script:GatePasses = $true
        function Assert-Administrator { }
        function Assert-ExactKitsuneApk { return 'fixture.apk' }
        function New-Context { [pscustomobject]@{ Instance = '7' } }
        function Get-InstanceInfo { param($Context) [pscustomobject]@{ is_android_started = $false } }
        function Invoke-BasePathRepair { $script:Events += 'repair' }
        function Start-Instance { param($Context) $script:Events += 'start' }
        function Stop-Instance { param($Context) $script:Events += 'stop' }
        function Assert-NoExistingSystemInstall {
            param($Context)
            $script:Events += 'inspect'
            if ($script:ExistingInstall) { throw 'Existing installation.' }
        }
        function Set-InstanceSettings { param($Context, $VendorRootEnabled) $script:Events += "root=$VendorRootEnabled" }
        function Push-Sanitizer { param($Context) $script:Events += 'push'; return 'script-hash' }
        function Get-VendorSuSha256 { param($Context) return 'vendor-hash' }
        function Invoke-VendorRootShell {
            param($Context, $Command)
            if ($Command -match ' prepare ') {
                $script:Events += 'prepare'
                return 'SANITIZE_OK mode=prepare recovery=/data/local/tmp/mumu-magisk-vendor-backup'
            }
            if ($Command -match ' init-only$') {
                $script:Events += 'disable-daemon'
                return 'SANITIZE_OK mode=init-only recovery=/data/local/tmp/mumu-magisk-vendor-backup'
            }
            throw 'Unexpected vendor command.'
        }
        function Install-KitsuneApk { param($Context) $script:Events += 'apk' }
        function Ensure-KitsuneAppRoot { param($Context) $script:Events += 'app-root' }
        Invoke-Prepare
        Assert-True (($script:Events -join ',') -eq 'repair,start,inspect,stop,repair,root=True,start,push,prepare,apk,app-root') 'Preparation disabled vendor root early or omitted verified app root.'
        $script:Events = @()
        $script:ExistingInstall = $true
        $refused = $false
        try { Invoke-Prepare } catch { $refused = $true }
        Assert-True ($refused -and ($script:Events -join ',') -eq 'repair,start,inspect') 'Preparation changed root settings on an existing installation.'

        function Assert-SystemInstallComplete {
            param($Context)
            $script:Events += 'gate'
            if (-not $script:GatePasses) { throw 'System files are incomplete.' }
        }
        function Launch-Kitsune { param($Context) $script:Events += 'app' }
        function Ensure-KitsuneShellAuthorization { param($Context) $script:Events += 'shell-grant' }
        function Invoke-QualificationBoots { param($Context) $script:Events += 'qualify' }
        $script:Events = @()
        Invoke-Finalize
        Assert-True (($script:Events -join ',') -eq 'start,push,gate,disable-daemon,shell-grant,stop,root=False,qualify') 'Finalization disabled vendor root before verifying the system install and Shell grant.'
        $script:Events = @()
        $script:GatePasses = $false
        $refused = $false
        try { Invoke-Finalize } catch { $refused = $true }
        Assert-True ($refused -and ($script:Events -join ',') -eq 'start,push,gate,app') 'A failed install gate disabled the vendor daemon.'
    }

    $emptyRegistry = 'Registry::HKEY_CURRENT_USER\Software\mumu-correctness-no-install-' + [Guid]::NewGuid().ToString('N')
    $emptyJson = & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File (Join-Path $repoRoot 'scripts\MuMuConfig.ps1') FindInstall --registry-root $emptyRegistry --json
    Assert-True ($LASTEXITCODE -eq 1 -and ($emptyJson -join '').Trim() -eq '[]') 'Empty discovery did not return valid JSON and a failure status.'

    # No real MuMu state is touched by launcher tests: only the help action and stub helpers run.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $launcherRoot = Join-Path $testRoot "Downloaded & extracted (test) [brackets]! 'apostrophe'"
        New-Item -ItemType Directory -Path (Join-Path $launcherRoot 'scripts'), (Join-Path $launcherRoot 'Tools') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts\mumu-guest-sanitize.sh') -Destination (Join-Path $launcherRoot 'scripts')
        [IO.File]::WriteAllText((Join-Path $launcherRoot 'Tools\app-release.apk'), 'help-only fixture')
        foreach ($launcher in @('Setup.bat', 'RestoreMuMuConfig.bat', 'Kitsune.bat')) {
            $launcherPath = Join-Path $launcherRoot $launcher
            Copy-Item -LiteralPath (Join-Path $repoRoot $launcher) -Destination $launcherPath
            foreach ($helper in @('MuMuConfig.ps1', 'Kitsune.ps1')) {
                $destination = Join-Path $launcherRoot "scripts\$helper"
                Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\$helper") -Destination $destination
                Set-Content -LiteralPath $destination -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
            }
            $help = Invoke-Launcher -Path $launcherPath -Arguments '--help'
            Assert-True ($help.ExitCode -eq 0 -and $help.Text -match 'Usage:') "Downloaded helper or special-character path failed for $launcher`: $($help.Text)"
            if ($launcher -eq 'Kitsune.bat') {
                $invalidApk = Invoke-Launcher -Path $launcherPath -Arguments ('prepare --install-root "' + (Join-Path $launcherRoot 'missing-install') + '"')
                Assert-True ($invalidApk.ExitCode -eq 1 -and $invalidApk.Text -match 'Wrong Kitsune APK') 'The actual Kitsune launcher could not run its hash preflight (check inherited PowerShell module paths).'
            }
            $helperName = if ($launcher -eq 'Kitsune.bat') { 'Kitsune.ps1' } else { 'MuMuConfig.ps1' }
            $helperPath = Join-Path $launcherRoot "scripts\$helperName"
            [IO.File]::WriteAllText($helperPath, '$ErrorActionPreference = ''Stop''; $null = Get-FileHash -LiteralPath $PSCommandPath; Write-Host "FIXTURE_RESULT"; exit 7')
            $failed = Invoke-Launcher -Path $launcherPath -ExpectPause
            Assert-True ($failed.ExitCode -eq 7 -and $failed.Text -match 'FIXTURE_RESULT') "Launcher lost the helper's failure status: $launcher"
            $automatic = Invoke-Launcher -Path $launcherPath -NoPause
            Assert-True ($automatic.ExitCode -eq 7) "MUMU_NO_PAUSE did not preserve the failure status: $launcher"
            Remove-Item -LiteralPath $helperPath
            $missing = Invoke-Launcher -Path $launcherPath -ExpectPause
            Assert-True ($missing.ExitCode -eq 1 -and $missing.Text -match 'missing') "Missing-file startup failure was not visible: $launcher"
        }
    } else {
        Write-Host 'Launcher elevation tests skipped: run as administrator to avoid an interactive UAC prompt.'
    }
    Write-Host "Correctness tests passed ($script:Assertions assertions)."
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notmatch '^mumu-correctness-[a-f0-9]{32}$') { throw 'Unsafe test cleanup path.' }
    for ($attempt = 1; (Test-Path -LiteralPath $resolved) -and $attempt -le 5; $attempt++) {
        try { Remove-Item -LiteralPath $resolved -Recurse -Force; break }
        catch { if ($attempt -eq 5) { throw }; Start-Sleep -Milliseconds 500 }
    }
}
