$ErrorActionPreference = 'Stop'

$script:Options = @{
    Action      = 'Help'
    Edition     = 'auto'
    Instance    = $null
    InstallRoot = $null
    ApkPath     = $null
    GuestScript = $null
    Boots       = 1
}

$script:ExpectedApkSha256 = 'fac319d2de262fcfff1684e13e1a5c61c486d2a773a7a8ffcfdbfe6f763a7fd4'
$script:ExpectedVersionCode = '31000'
$script:ExpectedVersionName = '31.0-kitsune'
$script:PackageName = 'io.github.huskydg.magisk'
$script:RemoteSanitizer = '/data/local/tmp/mumu-magisk-guest-sanitize.sh'
$script:ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:RepositoryRoot = Split-Path -Parent $script:ScriptDirectory
$script:ConfigHelper = Join-Path $script:ScriptDirectory 'MuMuConfig.ps1'
$script:DefaultApk = Join-Path $script:RepositoryRoot 'Tools\app-release.apk'
$script:DefaultGuestScript = Join-Path $script:ScriptDirectory 'mumu-guest-sanitize.sh'

function Read-Arguments {
    for ($i = 0; $i -lt $args.Count; $i++) {
        $argument = [string]$args[$i]
        switch -Regex ($argument) {
            '^-{1,2}action$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for action.' }
                $i++
                $script:Options.Action = [string]$args[$i]
                continue
            }
            '^-{1,2}edition$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for edition.' }
                $i++
                $script:Options.Edition = ([string]$args[$i]).ToLowerInvariant()
                continue
            }
            '^-{1,2}instance$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for instance.' }
                $i++
                $script:Options.Instance = [string]$args[$i]
                continue
            }
            '^-{1,2}install-root$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for install-root.' }
                $i++
                $script:Options.InstallRoot = [string]$args[$i]
                continue
            }
            '^-{1,2}apk$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for apk.' }
                $i++
                $script:Options.ApkPath = [string]$args[$i]
                continue
            }
            '^-{1,2}guest-script$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for guest-script.' }
                $i++
                $script:Options.GuestScript = [string]$args[$i]
                continue
            }
            '^-{1,2}boots$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for boots.' }
                $i++
                $script:Options.Boots = [int]$args[$i]
                continue
            }
            '^-{1,2}help$' {
                $script:Options.Action = 'Help'
                continue
            }
            default {
                if ($argument.StartsWith('-')) { throw "Unknown argument: $argument" }
                $script:Options.Action = $argument
            }
        }
    }

    $script:Options.Action = (Get-Culture).TextInfo.ToTitleCase(([string]$script:Options.Action).ToLowerInvariant())
    switch ($script:Options.Edition) {
        'g' { $script:Options.Edition = 'global' }
        'cn' { $script:Options.Edition = 'chinese' }
    }
    if (@('auto', 'global', 'chinese') -notcontains $script:Options.Edition) {
        throw "Invalid edition '$($script:Options.Edition)'. Use auto, global, or chinese."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$script:Options.Instance) -and
        [string]$script:Options.Instance -notmatch '^\d+$') {
        throw '--instance must be a numeric MuMu instance index.'
    }
    if ($script:Options.Boots -lt 1 -or $script:Options.Boots -gt 5) {
        throw '--boots must be between 1 and 5.'
    }
    if (-not $script:Options.ApkPath) { $script:Options.ApkPath = $script:DefaultApk }
    if (-not $script:Options.GuestScript) { $script:Options.GuestScript = $script:DefaultGuestScript }
}

function Write-Step {
    param([string]$Message)
    Write-Host "[MuMu/Kitsune] $Message"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw 'Administrator rights are required. Run Kitsune.bat so Windows can show the normal UAC prompt.'
    }
}

function ConvertTo-WindowsProcessArgument {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    # Follow CommandLineToArgvW/C-runtime quoting rules: escape quotes and
    # double any backslashes immediately before a quote or the closing quote.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Stop-NativeProcessTree {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)

    $rootId = $Process.Id
    try {
        $snapshot = @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue)
        $descendants = New-Object System.Collections.Generic.List[int]
        $frontier = New-Object System.Collections.Generic.Queue[int]
        $frontier.Enqueue($rootId)
        while ($frontier.Count -gt 0) {
            $parentId = $frontier.Dequeue()
            foreach ($child in $snapshot | Where-Object { [int]$_.ParentProcessId -eq $parentId }) {
                $childId = [int]$child.ProcessId
                if (-not $descendants.Contains($childId)) {
                    $descendants.Add($childId)
                    $frontier.Enqueue($childId)
                }
            }
        }
        for ($i = $descendants.Count - 1; $i -ge 0; $i--) {
            Stop-Process -Id $descendants[$i] -Force -ErrorAction SilentlyContinue
        }
    } catch {
        # The wrapper process is still terminated below even if CIM is unavailable.
    }
    try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$Description = $FilePath,
        [ValidateRange(1, 600)][int]$TimeoutSeconds = 45,
        [switch]$AllowFailure,
        [switch]$ShowOutput
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "Executable was not found: $FilePath"
    }

    $argumentLine = (@($Arguments | ForEach-Object {
        ConvertTo-WindowsProcessArgument -Value ([string]$_)
    }) -join ' ')
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $argumentLine
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    $timedOut = $false
    try {
        if (-not $process.Start()) { throw "$Description did not start." }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            Stop-NativeProcessTree -Process $process
            [void]$process.WaitForExit(5000)
        } else {
            $process.WaitForExit()
        }

        $stdoutText = ''
        $stderrText = ''
        try { if ($stdoutTask.Wait(5000)) { $stdoutText = [string]$stdoutTask.Result } } catch { }
        try { if ($stderrTask.Wait(5000)) { $stderrText = [string]$stderrTask.Result } } catch { }
        $combinedText = (($stdoutText.TrimEnd("`r", "`n"), $stderrText.TrimEnd("`r", "`n")) |
            Where-Object { -not [string]::IsNullOrEmpty($_) }) -join "`n"
        $output = if ([string]::IsNullOrEmpty($combinedText)) {
            @()
        } else {
            @([regex]::Split($combinedText, '\r?\n'))
        }
        $exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
    } finally {
        $process.Dispose()
    }

    if ($ShowOutput) {
        foreach ($line in $output) { Write-Host $line }
    }
    if ($timedOut -and -not $AllowFailure) {
        throw "$Description timed out after $TimeoutSeconds seconds; its exact process tree was stopped."
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $details = ($output -join [Environment]::NewLine).Trim()
        if ([string]::IsNullOrWhiteSpace($details)) { $details = "exit code $exitCode" }
        throw "$Description failed: $details"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $output
        Text     = ($output -join "`n").Trim()
        TimedOut = $timedOut
    }
}

function Get-WindowsPowerShellPath {
    $path = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'powershell.exe' }
    return $path
}

function Invoke-ConfigHelperJson {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [switch]$NoKill
    )

    if (-not (Test-Path -LiteralPath $script:ConfigHelper -PathType Leaf)) {
        throw "Required helper is missing: $script:ConfigHelper"
    }
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', $script:ConfigHelper,
        '-Action', $Action, '--edition', $script:Options.Edition, '--json'
    )
    if ($script:Options.InstallRoot) {
        $arguments += @('--install-root', $script:Options.InstallRoot)
    }
    if ($NoKill) { $arguments += '--no-kill' }

    $result = Invoke-NativeCommand -FilePath (Get-WindowsPowerShellPath) -Arguments $arguments -Description "MuMuConfig $Action"
    try {
        return ($result.Text | ConvertFrom-Json)
    } catch {
        throw "MuMuConfig $Action returned invalid JSON: $($result.Text)"
    }
}

function Resolve-MuMuInstall {
    $installs = @(Invoke-ConfigHelperJson -Action 'FindInstall' -NoKill)
    if ($installs.Count -ne 1) {
        throw "Expected exactly one MuMu install for edition '$($script:Options.Edition)', found $($installs.Count). Select --edition global or --edition chinese."
    }
    return $installs[0]
}

function Resolve-MuMuManager {
    param([Parameter(Mandatory = $true)][string]$InstallRoot)

    $resolvedRoot = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $candidates = @(
        (Join-Path $resolvedRoot 'nx_main\MuMuManager.exe'),
        (Join-Path $resolvedRoot 'shell\MuMuManager.exe'),
        (Join-Path $resolvedRoot 'MuMuManager.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    $matches = @(Get-ChildItem -LiteralPath $resolvedRoot -Filter 'MuMuManager.exe' -File -Recurse -ErrorAction SilentlyContinue)
    if ($matches.Count -ne 1) {
        throw "Could not resolve one MuMuManager.exe below $resolvedRoot (found $($matches.Count))."
    }
    return $matches[0].FullName
}

function Invoke-Manager {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$Description = 'MuMuManager',
        [ValidateRange(1, 600)][int]$TimeoutSeconds = 45,
        [switch]$AllowFailure,
        [switch]$ShowOutput
    )
    return Invoke-NativeCommand -FilePath $Context.Manager -Arguments $Arguments -Description $Description -TimeoutSeconds $TimeoutSeconds -AllowFailure:$AllowFailure -ShowOutput:$ShowOutput
}

function Convert-ManagerJson {
    param($Result, [string]$Description)
    try {
        return ($Result.Text | ConvertFrom-Json)
    } catch {
        throw "$Description returned invalid JSON: $($Result.Text)"
    }
}

function Get-MuMuProcessSnapshot {
    $devices = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'MuMuNxDevice.exe'" -ErrorAction SilentlyContinue)
    $headless = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'MuMuVMMHeadless.exe'" -ErrorAction SilentlyContinue)
    return [pscustomobject]@{
        Devices  = $devices
        Headless = $headless
    }
}

function Get-InstanceInventoryFromDisk {
    param(
        [Parameter(Mandatory = $true)]$Context,
        $ProcessSnapshot
    )

    $vmsPath = [System.IO.Path]::GetFullPath([string]$Context.Install.vms_path)
    if (-not (Test-Path -LiteralPath $vmsPath -PathType Container)) {
        throw "MuMu VMS path is missing: $vmsPath"
    }
    if (-not $ProcessSnapshot) { $ProcessSnapshot = Get-MuMuProcessSnapshot }

    $prefix = if ([string]$Context.Install.edition -eq 'chinese') { 'MuMuPlayer' } else { 'MuMuPlayerGlobal' }
    $namePattern = '^{0}-(?<android>\d+(?:\.\d+)?)-(?<index>\d+)$' -f [regex]::Escape($prefix)
    $instances = @()

    foreach ($directory in Get-ChildItem -LiteralPath $vmsPath -Directory -ErrorAction Stop) {
        $match = [regex]::Match($directory.Name, $namePattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) { continue }

        $index = $match.Groups['index'].Value
        $androidVersion = $match.Groups['android'].Value
        if ($androidVersion -notmatch '\.') { $androidVersion += '.0' }
        $displayName = $directory.Name
        $createdTimestamp = 0L
        $lastLaunchTimestamp = 0L

        $extraPath = Join-Path $directory.FullName 'configs\extra_config.json'
        if (Test-Path -LiteralPath $extraPath -PathType Leaf) {
            try {
                $extra = Get-Content -LiteralPath $extraPath -Raw | ConvertFrom-Json
                if (-not [string]::IsNullOrWhiteSpace([string]$extra.playerName)) { $displayName = [string]$extra.playerName }
                if ([string]$extra.series -match '^\d+(?:\.\d+)?$') {
                    $androidVersion = [string]$extra.series
                    if ($androidVersion -notmatch '\.') { $androidVersion += '.0' }
                }
                if ([string]$extra.createTime -match '^\d+$') { $createdTimestamp = [int64]$extra.createTime }
            } catch {
                throw "MuMu instance metadata is invalid: $extraPath"
            }
        }

        $customerPath = Join-Path $directory.FullName 'configs\customer_config.json'
        if (Test-Path -LiteralPath $customerPath -PathType Leaf) {
            try {
                $customer = Get-Content -LiteralPath $customerPath -Raw | ConvertFrom-Json
                $reportedLaunch = [string]$customer.nxdevice.report.launch.last_timestamp
                if ($reportedLaunch -match '^\d+$') { $lastLaunchTimestamp = [int64]$reportedLaunch }
            } catch {
                # Older builds may not have this optional last-launch metadata.
            }
        }

        $indexPattern = '(?:^|\s)-v\s+' + [regex]::Escape($index) + '(?:\s|$)'
        $device = @($ProcessSnapshot.Devices | Where-Object {
            [string]$_.CommandLine -match $indexPattern
        } | Sort-Object CreationDate -Descending | Select-Object -First 1)
        $vmPattern = '-' + [regex]::Escape($androidVersion) + '-' + [regex]::Escape($index) + '(?:\s|"|$)'
        $headless = @($ProcessSnapshot.Headless | Where-Object {
            [string]$_.CommandLine -match $vmPattern
        } | Sort-Object CreationDate -Descending | Select-Object -First 1)

        $androidStarted = $false
        if ($headless.Count -eq 1) {
            $probe = Invoke-Manager -Context $Context -Arguments @(
                'sh', '-v', $index, '-c', 'getprop sys.boot_completed'
            ) -Description "MuMu Android-ready probe for instance $index" -TimeoutSeconds 5 -AllowFailure
            $androidStarted = ($probe.ExitCode -eq 0 -and $probe.Text -match '(^|\s)1(\s|$)')
        }

        $instances += [pscustomobject]@{
            index                 = $index
            name                  = $displayName
            android_version       = $androidVersion
            error_code            = 0
            disk_size_bytes       = 0
            created_timestamp     = $createdTimestamp
            last_launch_timestamp = $lastLaunchTimestamp
            info_source           = 'verified-vm-metadata'
            is_process_started    = ($device.Count -eq 1)
            is_android_started    = $androidStarted
            pid                   = if ($device.Count -eq 1) { [int]$device[0].ProcessId } else { 0 }
            headless_pid          = if ($headless.Count -eq 1) { [int]$headless[0].ProcessId } else { 0 }
            player_state          = if ($androidStarted) { 'start_finished' } elseif ($headless.Count -eq 1) { 'starting' } else { 'stopped' }
            launch_err_code       = 0
            launch_err_msg        = ''
        }
    }

    return @($instances | Sort-Object { [int]$_.index })
}

function Get-InstanceInfo {
    param([Parameter(Mandatory = $true)]$Context)

    $matches = @(Get-InstanceInventoryFromDisk -Context $Context | Where-Object {
        [string]$_.index -eq [string]$Context.Instance
    })
    if ($matches.Count -ne 1) {
        throw "Expected one MuMu instance with index $($Context.Instance), found $($matches.Count) in $($Context.Install.vms_path)."
    }
    return $matches[0]
}

function Get-InstanceSettings {
    param([Parameter(Mandatory = $true)]$Context)

    $result = Invoke-Manager -Context $Context -Arguments @(
        'setting', '-v', $Context.Instance,
        '-k', 'root_permission', '-k', 'system_disk_readonly'
    ) -Description 'MuMu settings lookup'
    return Convert-ManagerJson -Result $result -Description 'MuMu settings lookup'
}

function Set-InstanceSettings {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][bool]$VendorRootEnabled
    )

    $rootValue = $VendorRootEnabled.ToString().ToLowerInvariant()
    Write-Step "Setting instance $($Context.Instance): MuMu root=$rootValue, system writable=true"
    [void](Invoke-Manager -Context $Context -Arguments @(
        'setting', '-v', $Context.Instance,
        '-k', 'root_permission', '-val', $rootValue,
        '-k', 'system_disk_readonly', '-val', 'false'
    ) -Description 'MuMu settings update' -ShowOutput)

    $settings = Get-InstanceSettings -Context $Context
    if ([string]$settings.root_permission -ne $rootValue -or
        [string]$settings.system_disk_readonly -ne 'false') {
        throw "MuMu settings verification failed: $($settings | ConvertTo-Json -Compress)"
    }
}

function Stop-Instance {
    param([Parameter(Mandatory = $true)]$Context)

    $info = Get-InstanceInfo -Context $Context
    $headlessAlive = $false
    if ([int]$info.headless_pid -gt 0) {
        $headlessAlive = [bool](Get-Process -Id ([int]$info.headless_pid) -ErrorAction SilentlyContinue)
    }
    if (-not [bool]$info.is_android_started -and -not $headlessAlive) {
        Start-Sleep -Seconds 2
        return
    }
    Write-Step "Stopping instance $($Context.Instance) cleanly"
    [void](Invoke-Manager -Context $Context -Arguments @('control', '-v', $Context.Instance, 'shutdown') -Description 'MuMu shutdown' -AllowFailure -ShowOutput)
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    $nextRetry = [DateTime]::UtcNow.AddSeconds(15)
    $stableSince = $null
    do {
        Start-Sleep -Milliseconds 500
        $info = Get-InstanceInfo -Context $Context
        $headlessAlive = $false
        if ([int]$info.headless_pid -gt 0) {
            $headlessAlive = [bool](Get-Process -Id ([int]$info.headless_pid) -ErrorAction SilentlyContinue)
        }
        if (-not [bool]$info.is_android_started -and -not $headlessAlive) {
            if (-not $stableSince) { $stableSince = [DateTime]::UtcNow }
            if (([DateTime]::UtcNow - $stableSince).TotalSeconds -ge 5) {
                Start-Sleep -Seconds 2
                return
            }
        } else {
            $stableSince = $null
        }
        if ([DateTime]::UtcNow -ge $nextRetry) {
            Write-Step 'MuMu reported a transient stop; repeating the clean shutdown request'
            [void](Invoke-Manager -Context $Context -Arguments @('control', '-v', $Context.Instance, 'shutdown') -Description 'MuMu shutdown retry' -AllowFailure -ShowOutput)
            $nextRetry = [DateTime]::UtcNow.AddSeconds(15)
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Instance $($Context.Instance) Android runtime did not remain stopped for five seconds within the 90-second safety window. No forced process kill was used."
}

function Start-Instance {
    param([Parameter(Mandatory = $true)]$Context)

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Step "Launching instance $($Context.Instance) (verified attempt $attempt of 3)"
        [void](Invoke-Manager -Context $Context -Arguments @('control', '-v', $Context.Instance, 'launch') -Description 'MuMu launch' -AllowFailure -ShowOutput)
        $deadline = [DateTime]::UtcNow.AddSeconds(120)
        do {
            Start-Sleep -Seconds 1
            $info = Get-InstanceInfo -Context $Context
            if ([bool]$info.is_process_started -and [bool]$info.is_android_started -and
                [string]$info.player_state -eq 'start_finished') {
                $bootDeadline = [DateTime]::UtcNow.AddSeconds(30)
                do {
                    $bootResult = Invoke-Manager -Context $Context -Arguments @(
                        'sh', '-v', $Context.Instance, '-c', 'getprop sys.boot_completed'
                    ) -Description 'Android boot check' -AllowFailure
                    if ($bootResult.Text -match '(^|\s)1(\s|$)') {
                        Write-Step "Instance $($Context.Instance) is Android-ready"
                        return (Get-InstanceInfo -Context $Context)
                    }
                    Start-Sleep -Seconds 1
                } while ([DateTime]::UtcNow -lt $bootDeadline)
            }
            if ([int]$info.launch_err_code -ne 0) { break }
        } while ([DateTime]::UtcNow -lt $deadline)

        if ($attempt -lt 3) {
            Write-Step 'MuMu did not reach Android-ready state; retrying after a clean stop'
            Stop-Instance -Context $Context
        }
    }
    $finalInfo = Get-InstanceInfo -Context $Context
    throw "Instance $($Context.Instance) failed to boot. state=$($finalInfo.player_state), code=$($finalInfo.launch_err_code), message=$($finalInfo.launch_err_msg)"
}

function Invoke-ColdBoot {
    param([Parameter(Mandatory = $true)]$Context)
    Stop-Instance -Context $Context
    return Start-Instance -Context $Context
}

function Invoke-ManagerShell {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Command,
        [ValidateRange(1, 600)][int]$TimeoutSeconds = 45,
        [switch]$AllowFailure,
        [switch]$ShowOutput
    )
    return Invoke-Manager -Context $Context -Arguments @('sh', '-v', $Context.Instance, '-c', $Command) -Description 'MuMu guest command' -TimeoutSeconds $TimeoutSeconds -AllowFailure:$AllowFailure -ShowOutput:$ShowOutput
}

function ConvertTo-ShellSingleQuoted {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + $Value.Replace("'", "'`"'`"'") + "'"
}

function Invoke-RootShell {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Command,
        [string]$Phase = 'Kitsune'
    )

    $marker = '__MUMU_MAGISK_ROOT_COMMAND_OK__'
    $payload = 'set -eu; test "$(id -u)" = 0; ' + $Command + '; echo ' + $marker
    $guestCommand = '/system/bin/su -c ' + (ConvertTo-ShellSingleQuoted -Value $payload)
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        $result = Invoke-ManagerShell -Context $Context -Command $guestCommand -AllowFailure
        if ($result.ExitCode -eq 0 -and $result.Output -contains $marker) {
            return @($result.Output | Where-Object { $_ -ne $marker })
        }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)

    $details = $result.Text
    if ([string]::IsNullOrWhiteSpace($details)) { $details = 'no root response after 45 seconds' }
    throw "$Phase root access was not authorized for Android Shell. Open Kitsune, enable [SharedUID] Shell on the Superuser tab (or accept and remember the MuMu root prompt during prepare), then rerun this command. Details: $details"
}

function Invoke-VendorRootShell {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Command
    )

    if ($Command -notmatch '^[A-Za-z0-9_./ -]+$') {
        throw 'Refusing unsafe characters in a vendor-root ADB command.'
    }
    $settings = Get-InstanceSettings -Context $Context
    if ([string]$settings.root_permission -ne 'true') {
        throw 'MuMu vendor root is not enabled for this instance.'
    }

    [void](Invoke-Manager -Context $Context -Arguments @('adb', '-v', $Context.Instance, '-c', 'root') -Description 'MuMu root ADB bootstrap' -AllowFailure)
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    do {
        $probe = Invoke-Manager -Context $Context -Arguments @('adb', '-v', $Context.Instance, '-c', 'shell id') -Description 'MuMu root ADB check' -AllowFailure
        if ($probe.Text -match 'uid=0\(root\)') {
            $result = Invoke-Manager -Context $Context -Arguments @('adb', '-v', $Context.Instance, '-c', "shell $Command") -Description 'MuMu root ADB command' -AllowFailure
            if ($result.ExitCode -eq 0) { return @($result.Output) }
            throw "MuMu root ADB command failed: $($result.Text)"
        }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)

    $details = $result.Text
    if ([string]::IsNullOrWhiteSpace($details)) { $details = 'root ADB did not become ready within 45 seconds' }
    throw "MuMu's temporary root ADB bootstrap is unavailable. Confirm Root permission is on and cold-start the instance. Details: $details"
}

function Wait-ForManagerAdb {
    param([Parameter(Mandatory = $true)]$Context)

    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    do {
        $probe = Invoke-Manager -Context $Context -Arguments @(
            'adb', '-v', $Context.Instance, '-c', 'get-state'
        ) -Description 'MuMu ADB readiness probe' -TimeoutSeconds 5 -AllowFailure
        if ($probe.ExitCode -eq 0 -and $probe.Text -match '(?m)^device$') { return }
        Start-Sleep -Seconds 1
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Instance $($Context.Instance) Android booted, but MuMu's ADB transport did not become ready within 60 seconds."
}

function Push-Sanitizer {
    param([Parameter(Mandatory = $true)]$Context)

    $localPath = [System.IO.Path]::GetFullPath([string]$script:Options.GuestScript)
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        throw "Guest sanitizer is missing: $localPath"
    }
    $hostSha256 = (Get-FileHash -LiteralPath $localPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $pushCommand = 'push "{0}" "{1}"' -f $localPath, $script:RemoteSanitizer
    Wait-ForManagerAdb -Context $Context
    Write-Step 'Uploading the transparent guest sanitizer through MuMuManager'
    $pushResult = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $pushResult = Invoke-Manager -Context $Context -Arguments @(
            'adb', '-v', $Context.Instance, '-c', $pushCommand
        ) -Description 'Sanitizer upload' -TimeoutSeconds 20 -AllowFailure -ShowOutput
        if ($pushResult.ExitCode -eq 0) { break }
        if ($attempt -lt 3) {
            Write-Step "ADB upload was transiently unavailable; retrying ($attempt of 3)"
            Start-Sleep -Seconds 2
            Wait-ForManagerAdb -Context $Context
        }
    }
    if (-not $pushResult -or $pushResult.ExitCode -ne 0) {
        throw "Sanitizer upload failed after three bounded attempts: $($pushResult.Text)"
    }
    $verify = Invoke-ManagerShell -Context $Context -Command "sha256sum $script:RemoteSanitizer"
    $match = [regex]::Match($verify.Text, '(?im)^([0-9a-f]{64})\s+')
    if (-not $match.Success -or $match.Groups[1].Value.ToLowerInvariant() -ne $hostSha256) {
        throw 'Guest sanitizer transfer failed SHA-256 verification.'
    }
    [void](Invoke-ManagerShell -Context $Context -Command "chmod 700 $script:RemoteSanitizer")
    return $hostSha256
}

function Get-VendorSuSha256 {
    param([Parameter(Mandatory = $true)]$Context)

    $command = "$script:RemoteSanitizer vendor-hash"
    $output = @(Invoke-VendorRootShell -Context $Context -Command $command)
    $entries = @()
    foreach ($line in $output) {
        $match = [regex]::Match([string]$line, '^([0-9a-fA-F]{64})\s+(/system/(?:bin|xbin)/su)$')
        if ($match.Success) {
            $entries += [pscustomobject]@{ Hash = $match.Groups[1].Value.ToLowerInvariant(); Path = $match.Groups[2].Value }
        }
    }
    if ($entries.Count -lt 1) { throw 'Could not capture a visible MuMu vendor su binary.' }
    $hashes = @($entries | Select-Object -ExpandProperty Hash -Unique)
    if ($hashes.Count -ne 1) { throw 'MuMu vendor su clients do not have one matching SHA-256; refusing to continue.' }
    return $hashes[0]
}

function Assert-ExactKitsuneApk {
    $apkPath = [System.IO.Path]::GetFullPath([string]$script:Options.ApkPath)
    if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) { throw "Kitsune APK is missing: $apkPath" }
    $actual = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $script:ExpectedApkSha256) {
        throw "Wrong Kitsune APK. Expected v31.0-25fa2159 SHA-256 $script:ExpectedApkSha256, got $actual."
    }
    return $apkPath
}

function Get-KitsunePackageInfo {
    param([Parameter(Mandatory = $true)]$Context)

    $command = "dumpsys package $script:PackageName 2>/dev/null | grep -E 'versionCode=|versionName=' | head -n 4"
    $result = Invoke-ManagerShell -Context $Context -Command $command -AllowFailure
    return [pscustomobject]@{
        Installed   = ($result.Text -match 'versionCode=')
        VersionCode = if ($result.Text -match 'versionCode=(\d+)') { $Matches[1] } else { $null }
        VersionName = if ($result.Text -match 'versionName=([^\s]+)') { $Matches[1] } else { $null }
        Text        = $result.Text
    }
}

function Assert-ExactKitsunePackage {
    param([Parameter(Mandatory = $true)]$Context)
    $package = Get-KitsunePackageInfo -Context $Context
    if (-not $package.Installed -or $package.VersionCode -ne $script:ExpectedVersionCode -or
        $package.VersionName -ne $script:ExpectedVersionName) {
        throw "Expected Kitsune $script:ExpectedVersionName ($script:ExpectedVersionCode), but package state was: $($package.Text)"
    }
}

function Install-KitsuneApk {
    param([Parameter(Mandatory = $true)]$Context)

    $apkPath = Assert-ExactKitsuneApk
    Write-Step "Installing verified Kitsune $script:ExpectedVersionName ($script:ExpectedVersionCode)"
    [void](Invoke-Manager -Context $Context -Arguments @(
        'control', '-v', $Context.Instance, 'app', 'install', '-apk', $apkPath
    ) -Description 'Kitsune APK install' -ShowOutput)

    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    do {
        Start-Sleep -Seconds 1
        $package = Get-KitsunePackageInfo -Context $Context
        if ($package.Installed -and $package.VersionCode -eq $script:ExpectedVersionCode -and
            $package.VersionName -eq $script:ExpectedVersionName) { return }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Kitsune package did not become $script:ExpectedVersionName ($script:ExpectedVersionCode) after installation."
}

function Launch-Kitsune {
    param([Parameter(Mandatory = $true)]$Context)
    [void](Invoke-Manager -Context $Context -Arguments @(
        'control', '-v', $Context.Instance, 'app', 'launch', '-pkg', $script:PackageName
    ) -Description 'Kitsune app launch' -ShowOutput)
}

function Assert-SystemInstallComplete {
    param([Parameter(Mandatory = $true)]$Context)

    Assert-ExactKitsunePackage -Context $Context
    $command = "$script:RemoteSanitizer system-gate"
    try {
        $output = @(Invoke-VendorRootShell -Context $Context -Command $command)
    } catch {
        $output = @(Invoke-RootShell -Context $Context -Command $command -Phase 'Kitsune finalize')
    }
    if ($output -notcontains 'SYSTEM_INSTALL_GATE_OK') {
        throw 'Kitsune direct-system files did not pass the pre-disable safety gate.'
    }
}

function Test-SystemModeRunning {
    param([Parameter(Mandatory = $true)]$Context)

    $result = Invoke-ManagerShell -Context $Context -Command 'test "$(/sbin/magisk -V 2>/dev/null)" = 31000; test "$(pidof magiskd | wc -w)" = 1' -TimeoutSeconds 15 -AllowFailure
    return ($result.ExitCode -eq 0)
}

function Test-KitsuneShellAuthorization {
    param([Parameter(Mandatory = $true)]$Context)

    $settings = Get-InstanceSettings -Context $Context
    if ([string]$settings.root_permission -eq 'true') {
        # During the one transition boot MuMu's ADB shell is already root, so
        # read (but never edit) Kitsune's policy for Android's fixed Shell UID.
        $query = '/sbin/magisk --sqlite ''SELECT policy FROM policies WHERE uid=2000;'''
        $result = Invoke-ManagerShell -Context $Context -Command $query -TimeoutSeconds 15 -AllowFailure
        return ($result.ExitCode -eq 0 -and $result.Text -match '(?m)^policy=2$')
    }

    $marker = '__MUMU_MAGISK_SHELL_AUTHORIZED__'
    $payload = 'test "$(id -u)" = 0; echo ' + $marker
    $guestCommand = '/system/bin/su -c ' + (ConvertTo-ShellSingleQuoted -Value $payload)
    $result = Invoke-ManagerShell -Context $Context -Command $guestCommand -TimeoutSeconds 15 -AllowFailure
    return ($result.ExitCode -eq 0 -and $result.Text -match ('(?m)^' + [regex]::Escape($marker) + '$'))
}

function Ensure-KitsuneShellAuthorization {
    param([Parameter(Mandatory = $true)]$Context)

    if (-not (Test-SystemModeRunning -Context $Context)) {
        Write-Step 'Starting the first System Mode boot; the MuMu su daemon is already disabled'
        [void](Invoke-ColdBoot -Context $Context)
    } else {
        Write-Step 'Kitsune System Mode is already running on this boot'
    }
    [void](Push-Sanitizer -Context $Context)
    Launch-Kitsune -Context $Context

    if (-not (Test-KitsuneShellAuthorization -Context $Context)) {
        Write-Host ''
        Write-Host 'Kitsune is now running in System Mode.' -ForegroundColor Green
        Write-Host 'Open its Superuser tab and enable [SharedUID] Shell.'
        [void](Read-Host 'After the Shell switch is ON, press Enter')
    }
    if (-not (Test-KitsuneShellAuthorization -Context $Context)) {
        throw 'Kitsune did not authorize [SharedUID] Shell. MuMu root has not been disabled; enable the switch and rerun finalize.'
    }
    Write-Step 'Verified Kitsune authorization for [SharedUID] Shell'
}

function Wait-ForStableMagiskDaemon {
    param([Parameter(Mandatory = $true)]$Context)

    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $consecutive = 0
    $lastCount = $null
    do {
        $daemonCountCommand = 'pidof magiskd | wc -w'
        $output = @(Invoke-RootShell -Context $Context -Command $daemonCountCommand -Phase 'Kitsune qualification')
        $line = @($output | Where-Object { [string]$_ -match '^\d+$' } | Select-Object -Last 1)
        if ($line.Count -eq 1) { $lastCount = [int]$line[0] }
        if ($lastCount -eq 1) {
            $consecutive++
            if ($consecutive -ge 3) { return }
        } else {
            $consecutive = 0
        }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Kitsune daemon did not settle at exactly one magiskd process (last count: $lastCount)."
}

function Assert-QualifiedBoot {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][int]$BootNumber
    )

    $settings = Get-InstanceSettings -Context $Context
    if ([string]$settings.root_permission -ne 'false' -or
        [string]$settings.system_disk_readonly -ne 'false') {
        throw "Qualification requires MuMu vendor root off and system writable. Settings: $($settings | ConvertTo-Json -Compress)"
    }
    Assert-ExactKitsunePackage -Context $Context

    $sanitizeOutput = @(Invoke-RootShell -Context $Context -Command "$script:RemoteSanitizer all" -Phase 'Kitsune qualification')
    if ($sanitizeOutput -notcontains 'SANITIZE_OK mode=all recovery=/data/local/tmp/mumu-magisk-vendor-backup') {
        throw 'The collision sanitizer did not report a successful all-mode result.'
    }

    $command = 'test "$(/sbin/magisk -V)" = 31000; test "$(readlink /system/bin/su)" = ./magisk; test ! -e /system/xbin/su; test "$(id -Z)" = u:r:magisk:s0; if ps -A | awk ''$NF == "mu_bak" { found=1 } END { exit found ? 0 : 1 }''; then exit 71; fi; if dmesg 2>/dev/null | grep -q ''hit do_open_execat''; then exit 72; fi; echo QUALIFICATION_GUEST_OK'
    $output = @(Invoke-RootShell -Context $Context -Command $command -Phase 'Kitsune qualification')
    if ($output -notcontains 'QUALIFICATION_GUEST_OK') {
        throw "Guest qualification failed on boot $BootNumber."
    }
    Wait-ForStableMagiskDaemon -Context $Context
    Write-Step "Qualification boot $BootNumber passed"
}

function Get-AllInstanceInfo {
    param([Parameter(Mandatory = $true)]$Context)

    $snapshot = Get-MuMuProcessSnapshot
    return @(Get-InstanceInventoryFromDisk -Context $Context -ProcessSnapshot $snapshot)
}

function Get-LastLaunchedInstanceFromLogs {
    param([Parameter(Mandatory = $true)]$Context)

    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) { return $null }
    $userFolder = if ([string]$Context.Install.edition -eq 'chinese') { 'MuMuPlayer' } else { 'MuMuPlayerGlobal' }
    $logRoot = Join-Path (Join-Path $env:APPDATA 'Netease') "$userFolder\logs"
    if (-not (Test-Path -LiteralPath $logRoot -PathType Container)) { return $null }

    $logs = @(Get-ChildItem -LiteralPath $logRoot -Filter 'nx_main*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending)
    foreach ($log in $logs) {
        $lines = @(Get-Content -LiteralPath $log.FullName -Tail 10000 -ErrorAction SilentlyContinue)
        for ($lineIndex = $lines.Count - 1; $lineIndex -ge 0; $lineIndex--) {
            if ([string]$lines[$lineIndex] -match 'Launch player, cmd:.*index:\s*(\d+)') {
                return $Matches[1]
            }
        }
    }
    return $null
}

function Resolve-TargetInstance {
    param([Parameter(Mandatory = $true)]$Context)

    $instances = @(Get-AllInstanceInfo -Context $Context)
    $android12 = @($instances | Where-Object { [string]$_.android_version -eq '12.0' })
    if ($android12.Count -eq 0) { throw 'No MuMu Android 12 instance was found.' }

    $running = @($instances | Where-Object { [bool]$_.is_android_started })
    if ($running.Count -gt 0) {
        $runningAndroid12 = @($running | Where-Object { [string]$_.android_version -eq '12.0' })
        if ($runningAndroid12.Count -eq 0) {
            $runningText = ($running | ForEach-Object { "$($_.name) (index $($_.index), Android $($_.android_version))" }) -join ', '
            throw "The last/current running MuMu instance is not Android 12: $runningText"
        }
        if ($runningAndroid12.Count -eq 1) {
            Write-Step "Auto-selected running instance $($runningAndroid12[0].index): $($runningAndroid12[0].name)"
            return [string]$runningAndroid12[0].index
        }

        $ranked = @($runningAndroid12 | ForEach-Object {
            $started = [DateTime]::MinValue
            if ($_.headless_pid) {
                try { $started = (Get-Process -Id ([int]$_.headless_pid) -ErrorAction Stop).StartTime } catch { }
            }
            [pscustomobject]@{ Info = $_; Started = $started }
        } | Sort-Object Started -Descending)
        $selected = $ranked[0].Info
        Write-Step "Auto-selected most recently started instance $($selected.index): $($selected.name)"
        return [string]$selected.index
    }

    $timestamped = @($instances | Where-Object { [int64]$_.last_launch_timestamp -gt 0 } |
        Sort-Object { [int64]$_.last_launch_timestamp } -Descending)
    if ($timestamped.Count -gt 0) {
        $selected = $timestamped[0]
        if ([string]$selected.android_version -ne '12.0') {
            throw "The most recently launched MuMu instance is $($selected.name) (index $($selected.index)), but it uses Android $($selected.android_version). This workflow currently supports Android 12 only."
        }
        Write-Step "Auto-selected most recently launched instance $($selected.index): $($selected.name)"
        return [string]$selected.index
    }

    $lastLaunched = Get-LastLaunchedInstanceFromLogs -Context $Context
    if ($lastLaunched) {
        $selected = @($instances | Where-Object { [string]$_.index -eq [string]$lastLaunched }) | Select-Object -First 1
        if ($selected -and [string]$selected.android_version -ne '12.0') {
            throw "The most recently launched MuMu instance is $($selected.name) (index $($selected.index)), but it uses Android $($selected.android_version). This workflow currently supports Android 12 only."
        }
        if ($selected) {
            Write-Step "Auto-selected most recently launched instance $($selected.index): $($selected.name)"
            return [string]$selected.index
        }
    }

    if ($android12.Count -eq 1) {
        Write-Step "Auto-selected the only Android 12 instance $($android12[0].index): $($android12[0].name)"
        return [string]$android12[0].index
    }

    Write-Host 'Choose the Android 12 instance to modify:'
    foreach ($candidate in $android12 | Sort-Object { [int]$_.index }) {
        Write-Host "  $($candidate.index): $($candidate.name)"
    }
    $choice = (Read-Host 'Instance number').Trim()
    if ($choice -notmatch '^\d+$' -or -not @($android12 | Where-Object { [string]$_.index -eq $choice })) {
        throw "'$choice' is not one of the listed Android 12 instances."
    }
    return $choice
}

function New-Context {
    $install = Resolve-MuMuInstall
    $manager = Resolve-MuMuManager -InstallRoot ([string]$install.install_root)
    $context = [pscustomobject]@{
        Install  = $install
        Manager  = $manager
        Instance = [string]$script:Options.Instance
    }
    if ([string]::IsNullOrWhiteSpace($context.Instance)) {
        $context.Instance = Resolve-TargetInstance -Context $context
        $script:Options.Instance = $context.Instance
    }
    $info = Get-InstanceInfo -Context $context
    if ([string]$info.android_version -ne '12.0') {
        throw "This collision repair was verified only on MuMu Android 12; instance $($context.Instance) is Android $($info.android_version)."
    }
    return $context
}

function Invoke-BasePathRepair {
    Write-Step 'Checking MuMu engine/base paths before launch'
    $results = @(Invoke-ConfigHelperJson -Action 'RepairBasePaths' -NoKill)
    foreach ($result in $results) {
        foreach ($basePath in @($result.engine_base_paths)) {
            Write-Step "Base $($basePath.base_name): $($basePath.status)"
        }
    }
}

function Invoke-Prepare {
    Assert-Administrator
    [void](Assert-ExactKitsuneApk)
    $context = New-Context

    Stop-Instance -Context $context
    Invoke-BasePathRepair
    Set-InstanceSettings -Context $context -VendorRootEnabled $true
    [void](Start-Instance -Context $context)
    $scriptHash = Push-Sanitizer -Context $context
    $vendorHash = Get-VendorSuSha256 -Context $context
    Write-Step "Captured this build's MuMu vendor su SHA-256: $vendorHash"

    $prepareOutput = @(Invoke-VendorRootShell -Context $context -Command "$script:RemoteSanitizer prepare $vendorHash")
    if ($prepareOutput -notcontains 'SANITIZE_OK mode=prepare recovery=/data/local/tmp/mumu-magisk-vendor-backup') {
        throw 'Guest preparation did not finish successfully.'
    }

    Install-KitsuneApk -Context $context
    Write-Host ''
    Write-Host 'MuMu may show its Kitsune root dialog for only about 20 seconds.' -ForegroundColor Yellow
    Write-Host 'When it appears, choose Remember and Allow.'
    Launch-Kitsune -Context $context
    Write-Host ''
    Write-Host 'Preparation is complete and MuMu root is intentionally still ON.' -ForegroundColor Green
    Write-Host 'In the Kitsune window:'
    Write-Host '  1. Accept and remember MuMu''s root prompt for Kitsune.'
    Write-Host '  2. If Direct Install is missing, fully close and reopen Kitsune after granting root.'
    Write-Host '  3. Choose Install -> Direct Install (modify /system directly), then wait for Done.'
    Write-Host '  4. Do not use Kitsune''s Reboot button; return to this console.'
    if ($script:Options.Action -eq 'Install') {
        Write-Host '  5. Press Enter here. The helper will perform the first System Mode boot.'
    } else {
        Write-Host '  5. Run: Kitsune.bat finalize'
    }
    Write-Host ''
    Write-Host "Verified APK SHA-256: $script:ExpectedApkSha256"
    Write-Host "Transferred sanitizer SHA-256: $scriptHash"
}

function Invoke-QualificationBoots {
    param([Parameter(Mandatory = $true)]$Context)

    for ($boot = 1; $boot -le $script:Options.Boots; $boot++) {
        [void](Invoke-ColdBoot -Context $Context)
        [void](Push-Sanitizer -Context $Context)
        Assert-QualifiedBoot -Context $Context -BootNumber $boot
    }
}

function Invoke-Finalize {
    Assert-Administrator
    $context = New-Context
    $info = Get-InstanceInfo -Context $context
    if (-not [bool]$info.is_android_started) { [void](Start-Instance -Context $context) }
    [void](Push-Sanitizer -Context $context)

    Write-Step 'Verifying the direct-system install before disabling MuMu root'
    try {
        Assert-SystemInstallComplete -Context $context
    } catch {
        Launch-Kitsune -Context $context
        throw
    }

    Ensure-KitsuneShellAuthorization -Context $context
    Stop-Instance -Context $context
    Set-InstanceSettings -Context $context -VendorRootEnabled $false
    Invoke-QualificationBoots -Context $context
    Write-Host ''
    Write-Host "Kitsune $script:ExpectedVersionName is qualified on instance $($context.Instance)." -ForegroundColor Green
    Write-Host 'MuMu vendor root is OFF, the system disk remains writable, and the vendor collision checks passed.'
}

function Invoke-Qualify {
    Assert-Administrator
    $context = New-Context
    $settings = Get-InstanceSettings -Context $context
    if ([string]$settings.root_permission -ne 'false') {
        throw 'Refusing qualification while MuMu vendor root is enabled. Run the finalize action after the direct-system install.'
    }
    Invoke-QualificationBoots -Context $context
    Write-Host "Qualified $($script:Options.Boots) cold boot(s) for instance $($context.Instance)." -ForegroundColor Green
}

function Invoke-Install {
    Invoke-Prepare
    [void](Read-Host 'After Direct Install says Done, press Enter')
    Invoke-Finalize
}

function Show-Help {
    Write-Host @'
Usage:
  Kitsune.bat install  [--instance INDEX] [--edition global|chinese] [--boots 1..5]
  Kitsune.bat prepare  [--instance INDEX] [--edition global|chinese]
  Kitsune.bat finalize [--instance INDEX] [--edition global|chinese] [--boots 1..5]
  Kitsune.bat qualify  [--instance INDEX] [--edition global|chinese] [--boots 1..5]

Actions:
  install   Run prepare and finalize from one .bat command, pausing for the in-app step.
  prepare   Repair verified MuMu base paths, enable MuMu root + writable system,
            capture/disable the vendor su daemon safely, and install the exact v31 APK.
  finalize  Verify Direct Install, authorize Shell on the first System Mode boot,
            then turn MuMu root off and qualify a clean cold boot.
  qualify   Repeat root-off cold-boot collision checks without changing root settings.

Options:
  --instance INDEX       Optional override. By default, use the last/current MuMu instance.
  --edition VALUE        auto (default), global, or chinese.
  --install-root PATH    Use a specific MuMu install root.
  --boots N              Qualification cold boots, 1 to 5 (default: 1).
  --apk PATH             Alternate path to the exact verified v31.0-25fa2159 APK.
  --guest-script PATH    Test/development override for the checked-in guest sanitizer.

The script does not patch a Windows kernel image, add antivirus exclusions, download
code at runtime, or remove an unknown guest binary. Vendor client removal is allowed
only when it matches the SHA-256 captured from that instance during prepare.
'@
}

function Invoke-Main {
    Read-Arguments @args
    switch ($script:Options.Action) {
        'Help' { Show-Help; return }
        'Install' { Invoke-Install; return }
        'Prepare' { Invoke-Prepare; return }
        'Finalize' { Invoke-Finalize; return }
        'Qualify' { Invoke-Qualify; return }
        default { throw "Unknown action '$($script:Options.Action)'. Use install, prepare, finalize, or qualify." }
    }
}

try {
    Invoke-Main @args
    exit 0
} catch {
    Write-Error $_.Exception.Message
    if ($env:MUMU_DEBUG) { Write-Error $_.ScriptStackTrace }
    exit 1
}
