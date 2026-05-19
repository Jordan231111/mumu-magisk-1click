$ErrorActionPreference = 'Stop'

$script:Options = @{
    Action       = 'Setup'
    Edition      = 'auto'
    DryRun       = $false
    NoKill       = $false
    InstallRoot  = $null
    RegistryRoot = $null
    UserDataRoot = $null
    ClassesRoot  = $null
    OutputPath   = $null
    MetadataPath = $null
    Json         = $false
}

$script:AssociationBackupValueName = 'mumu_magisk_1click_backup_default'

$script:Editions = @{
    global = [pscustomobject]@{
        Name             = 'Global'
        KeyName          = 'MuMuPlayerGlobal-12.0'
        FolderName       = 'MuMuPlayerGlobal-12.0'
        UserConfigFolder = 'MuMuPlayerGlobal'
        ClassPrefix      = 'MuMuPlayerGlobal'
    }
    chinese = [pscustomobject]@{
        Name             = 'Chinese'
        KeyName          = 'MuMuPlayer-12.0'
        FolderName       = 'MuMuPlayer-12.0'
        UserConfigFolder = 'MuMuPlayer'
        ClassPrefix      = 'MuMuPlayer'
    }
}

function Set-OptionValue {
    param(
        [string]$Name,
        [int]$Index
    )

    if ($Index + 1 -ge $args.Count) {
        throw "Missing value for $Name."
    }
}

function Read-Arguments {
    for ($i = 0; $i -lt $args.Count; $i++) {
        $arg = [string]$args[$i]
        switch -Regex ($arg) {
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
            '^-{1,2}install-root$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for install-root.' }
                $i++
                $script:Options.InstallRoot = [string]$args[$i]
                continue
            }
            '^-{1,2}registry-root$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for registry-root.' }
                $i++
                $script:Options.RegistryRoot = [string]$args[$i]
                continue
            }
            '^-{1,2}user-data-root$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for user-data-root.' }
                $i++
                $script:Options.UserDataRoot = [string]$args[$i]
                continue
            }
            '^-{1,2}classes-root$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for classes-root.' }
                $i++
                $script:Options.ClassesRoot = [string]$args[$i]
                continue
            }
            '^-{1,2}output$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for output.' }
                $i++
                $script:Options.OutputPath = [string]$args[$i]
                continue
            }
            '^-{1,2}metadata$' {
                if ($i + 1 -ge $args.Count) { throw 'Missing value for metadata.' }
                $i++
                $script:Options.MetadataPath = [string]$args[$i]
                continue
            }
            '^-{1,2}dry-run$' {
                $script:Options.DryRun = $true
                continue
            }
            '^-{1,2}no-kill$' {
                $script:Options.NoKill = $true
                continue
            }
            '^-{1,2}json$' {
                $script:Options.Json = $true
                continue
            }
            '^-{1,2}help$' {
                $script:Options.Action = 'Help'
                continue
            }
            default {
                if ($arg.StartsWith('-')) {
                    throw "Unknown argument: $arg"
                }
                $script:Options.Action = $arg
            }
        }
    }

    $script:Options.Action = (Get-Culture).TextInfo.ToTitleCase(([string]$script:Options.Action).ToLowerInvariant())

    switch ($script:Options.Edition) {
        'g' { $script:Options.Edition = 'global' }
        'cn' { $script:Options.Edition = 'chinese' }
    }

    $validEditions = @('auto', 'global', 'chinese', 'all')
    if ($validEditions -notcontains $script:Options.Edition) {
        throw "Invalid edition '$($script:Options.Edition)'. Use auto, global, chinese, or all."
    }
}

function Write-Log {
    param([string]$Message)
    if (-not $script:Options.Json) {
        Write-Host $Message
    }
}

function Write-JsonResult {
    param($Value)
    $json = $Value | ConvertTo-Json -Depth 20
    [Console]::Out.WriteLine($json)
}

function Get-UninstallRoots {
    if ($script:Options.RegistryRoot) {
        return @($script:Options.RegistryRoot)
    }

    return @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
}

function Get-NeteaseRoots {
    return @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Netease',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Netease'
    )
}

function Get-UserDataRoot {
    if ($script:Options.UserDataRoot) {
        return $script:Options.UserDataRoot
    }

    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        return $null
    }

    return Join-ChildPath -Path $env:APPDATA -Child 'Netease'
}

function Get-ClassesRoot {
    if ($script:Options.ClassesRoot) {
        return $script:Options.ClassesRoot
    }

    return 'Registry::HKEY_CURRENT_USER\Software\Classes'
}

function Join-ChildPath {
    param(
        [string]$Path,
        [string]$Child
    )
    return [System.IO.Path]::Combine($Path, $Child)
}

function Normalize-PathCandidate {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Candidate.Trim())
    $expanded = $expanded.Trim('"')
    if ([string]::IsNullOrWhiteSpace($expanded)) {
        return $null
    }

    return $expanded
}

function Get-PathFragments {
    param(
        [string]$Candidate,
        $EditionInfo
    )

    $fragments = New-Object System.Collections.Generic.List[string]
    $normalized = Normalize-PathCandidate $Candidate
    if ($normalized) {
        [void]$fragments.Add($normalized)
    }

    $folderPattern = [regex]::Escape($EditionInfo.FolderName)
    $matches = [regex]::Matches($Candidate, "([A-Za-z]:\\[^`"']*?$folderPattern)", 'IgnoreCase')
    foreach ($match in $matches) {
        if ($match.Groups.Count -gt 1) {
            [void]$fragments.Add($match.Groups[1].Value)
        }
    }

    return $fragments
}

function Resolve-InstallRootCandidate {
    param(
        [string]$Candidate,
        $EditionInfo
    )

    foreach ($fragment in (Get-PathFragments -Candidate $Candidate -EditionInfo $EditionInfo)) {
        $start = Normalize-PathCandidate $fragment
        if (-not $start) { continue }

        if (Test-Path -LiteralPath $start -PathType Leaf) {
            $start = [System.IO.Path]::GetDirectoryName($start)
        }

        $current = $start
        for ($i = 0; $i -lt 8 -and -not [string]::IsNullOrWhiteSpace($current); $i++) {
            $vmsPath = Join-ChildPath -Path $current -Child 'vms'
            if (Test-Path -LiteralPath $vmsPath -PathType Container) {
                return [System.IO.Path]::GetFullPath($current).TrimEnd('\')
            }

            $parentInfo = [System.IO.Directory]::GetParent($current)
            $parent = $null
            if ($parentInfo) {
                $parent = $parentInfo.FullName
            }
            if ($parent -eq $current) {
                break
            }
            $current = $parent
        }
    }

    return $null
}

function New-InstallObject {
    param(
        [string]$Edition,
        [string]$InstallRoot,
        [string]$DisplayVersion,
        [string]$Source
    )

    if (-not $InstallRoot) { return $null }

    $vmsPath = Join-ChildPath -Path $InstallRoot -Child 'vms'
    if (-not (Test-Path -LiteralPath $vmsPath -PathType Container)) {
        return $null
    }

    return [pscustomobject]@{
        edition        = $Edition
        edition_name   = $script:Editions[$Edition].Name
        install_root   = $InstallRoot
        vms_path       = $vmsPath
        display_version = $DisplayVersion
        source         = $Source
    }
}

function Add-InstallCandidate {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Edition,
        [string]$Candidate,
        [string]$DisplayVersion,
        [string]$Source
    )

    $editionInfo = $script:Editions[$Edition]
    $root = Resolve-InstallRootCandidate -Candidate $Candidate -EditionInfo $editionInfo
    $install = New-InstallObject -Edition $Edition -InstallRoot $root -DisplayVersion $DisplayVersion -Source $Source
    if ($install) {
        [void]$List.Add($install)
    }
}

function Get-PropertyValue {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Test-UninstallEntryMatchesEdition {
    param(
        $Entry,
        [string]$KeyName,
        [string]$Edition
    )

    $displayName = [string](Get-PropertyValue -Object $Entry -Name 'DisplayName')
    $combined = "$KeyName $displayName"

    if ($Edition -eq 'global') {
        return ($combined -match 'MuMuPlayerGlobal|MuMu.*Global')
    }

    if ($combined -match 'MuMuPlayerGlobal|MuMu.*Global') {
        return $false
    }

    return ($combined -match 'MuMu|Netease')
}

function Get-InstallCandidatesForEdition {
    param([string]$Edition)

    $candidates = New-Object System.Collections.Generic.List[object]
    $editionInfo = $script:Editions[$Edition]

    if ($script:Options.InstallRoot) {
        Add-InstallCandidate -List $candidates -Edition $Edition -Candidate $script:Options.InstallRoot -DisplayVersion $null -Source 'install-root argument'
        return $candidates
    }

    foreach ($root in (Get-UninstallRoots)) {
        $directKey = Join-ChildPath -Path $root -Child $editionInfo.KeyName
        if (Test-Path -LiteralPath $directKey) {
            $props = Get-ItemProperty -LiteralPath $directKey -ErrorAction SilentlyContinue
            $installLocation = [string](Get-PropertyValue -Object $props -Name 'InstallLocation')
            $displayVersion = [string](Get-PropertyValue -Object $props -Name 'DisplayVersion')
            Add-InstallCandidate -List $candidates -Edition $Edition -Candidate $installLocation -DisplayVersion $displayVersion -Source "uninstall registry direct: $directKey"
        }

        if (Test-Path -LiteralPath $root) {
            foreach ($key in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
                if (-not (Test-UninstallEntryMatchesEdition -Entry $props -KeyName $key.PSChildName -Edition $Edition)) {
                    continue
                }

                $displayVersion = [string](Get-PropertyValue -Object $props -Name 'DisplayVersion')
                foreach ($propertyName in @('InstallLocation', 'DisplayIcon', 'UninstallString')) {
                    $value = [string](Get-PropertyValue -Object $props -Name $propertyName)
                    Add-InstallCandidate -List $candidates -Edition $Edition -Candidate $value -DisplayVersion $displayVersion -Source "uninstall registry scan: $($key.PSPath)"
                }
            }
        }
    }

    if ($script:Options.RegistryRoot) {
        return $candidates
    }

    foreach ($root in (Get-NeteaseRoots)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        $items = New-Object System.Collections.Generic.List[object]
        [void]$items.Add((Get-Item -LiteralPath $root -ErrorAction SilentlyContinue))
        foreach ($child in (Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue)) {
            [void]$items.Add($child)
        }

        foreach ($item in $items) {
            if ($null -eq $item) { continue }
            $props = Get-ItemProperty -LiteralPath $item.PSPath -ErrorAction SilentlyContinue
            foreach ($property in $props.PSObject.Properties) {
                if ($property.Name -match '^PS') { continue }
                if ($property.Value -is [string]) {
                    Add-InstallCandidate -List $candidates -Edition $Edition -Candidate $property.Value -DisplayVersion $null -Source "Netease registry: $($item.PSPath)"
                }
            }
        }
    }

    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne [System.IO.DriveType]::Fixed -or -not $drive.IsReady) {
            continue
        }

        foreach ($programFolder in @('Program Files', 'Program Files (x86)')) {
            $candidate = [System.IO.Path]::Combine($drive.RootDirectory.FullName, $programFolder, 'Netease', $editionInfo.FolderName)
            Add-InstallCandidate -List $candidates -Edition $Edition -Candidate $candidate -DisplayVersion $null -Source 'fallback Program Files\Netease path'
        }
    }

    return $candidates
}

function Select-UniqueInstalls {
    param([object[]]$Candidates)

    $seen = @{}
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in $Candidates) {
        if ($null -eq $candidate) { continue }
        $key = ([string]$candidate.install_root).TrimEnd('\').ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [void]$result.Add($candidate)
        }
    }

    return $result
}

function Find-MuMuInstall {
    param([string]$Edition)

    if ($Edition -eq 'auto') {
        $globalInstalls = @(Select-UniqueInstalls -Candidates (Get-InstallCandidatesForEdition -Edition 'global'))
        if ($globalInstalls.Count -gt 0) { return $globalInstalls }
        return @(Select-UniqueInstalls -Candidates (Get-InstallCandidatesForEdition -Edition 'chinese'))
    }

    if ($Edition -eq 'all') {
        $all = New-Object System.Collections.Generic.List[object]
        foreach ($install in (Get-InstallCandidatesForEdition -Edition 'global')) { [void]$all.Add($install) }
        foreach ($install in (Get-InstallCandidatesForEdition -Edition 'chinese')) { [void]$all.Add($install) }
        return @(Select-UniqueInstalls -Candidates $all)
    }

    return @(Select-UniqueInstalls -Candidates (Get-InstallCandidatesForEdition -Edition $Edition))
}

function Test-PathIsUnderRoot {
    param(
        [string]$Path,
        [string[]]$RootPrefixes
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    foreach ($rootPrefix in $RootPrefixes) {
        if ($Path.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Stop-MuMuProcesses {
    param([object[]]$Installs = @())

    $rootPrefixes = @(
        $Installs |
            Where-Object { $_ -and $_.install_root } |
            ForEach-Object { [System.IO.Path]::GetFullPath($_.install_root).TrimEnd('\') + '\' }
    )

    $serviceNames = @(
        'MuMuPlayerService',
        'MuMuVMMSVC',
        'MuMuVMMService',
        'MuMuNxService',
        'MuMuRemoteService',
        'MumuRemoteHealthd',
        'NemuSVC',
        'NemuService'
    )

    $servicesToStop = @{}
    foreach ($serviceName in $serviceNames) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service) {
            $servicesToStop[$service.Name] = $true
        }
    }

    if ($rootPrefixes.Count -gt 0) {
        Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
            Where-Object { Test-PathIsUnderRoot -Path ($_.PathName -replace '^"', '') -RootPrefixes $rootPrefixes } |
            ForEach-Object { $servicesToStop[$_.Name] = $true }
    }

    foreach ($serviceName in $servicesToStop.Keys) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne 'Stopped') {
            Write-Log "Stopping service: $serviceName"
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        }
    }

    $processNames = @(
        'MuMuVMMHeadless',
        'MuMuPlayer',
        'MuMuPlayerService',
        'MuMuVMMSVC',
        'MuMuMultiPlayer',
        'MuMuManager',
        'MuMuNxMain',
        'MuMuNxDevice',
        'MuMuNxService',
        'MuMuNxUpdater',
        'MuMuRemoteBackend',
        'MumuRemoteHealthd',
        'MuMuRemoteService',
        'MuMuVMMVBoxHeadless',
        'NemuPlayer',
        'NemuHeadless',
        'NemuLauncher',
        'NemuMultiPlayer',
        'NemuService',
        'NemuSVC',
        'NemuVMMHeadless'
    )

    $stoppedPids = @{}
    foreach ($processName in $processNames) {
        $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
        foreach ($process in $processes) {
            if ($stoppedPids.ContainsKey($process.Id)) { continue }
            Write-Log "Stopping process: $($process.ProcessName) ($($process.Id))"
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $stoppedPids[$process.Id] = $true
        }
    }

    if ($rootPrefixes.Count -gt 0) {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { Test-PathIsUnderRoot -Path $_.ExecutablePath -RootPrefixes $rootPrefixes } |
            ForEach-Object {
                $pid = [int]$_.ProcessId
                if ($stoppedPids.ContainsKey($pid)) { return }
                Write-Log "Stopping MuMu install process: $($_.Name) ($pid)"
                Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                $stoppedPids[$pid] = $true
            }
    }
}

function Get-JsonNode {
    param(
        $Root,
        [string[]]$Path
    )

    $current = $Root
    foreach ($part in $Path) {
        if ($null -eq $current) { return $null }
        $property = $current.PSObject.Properties[$part]
        if (-not $property) { return $null }
        $current = $property.Value
    }

    return $current
}

function Set-JsonValueIfExists {
    param(
        $Root,
        [string[]]$Path,
        $Value
    )

    if ($Path.Count -lt 1) {
        throw 'JSON path must include at least one segment.'
    }

    $parentPath = @()
    if ($Path.Count -gt 1) {
        $parentPath = $Path[0..($Path.Count - 2)]
    }

    $parent = $Root
    if ($parentPath.Count -gt 0) {
        $parent = Get-JsonNode -Root $Root -Path $parentPath
    }

    if ($null -eq $parent) {
        return [pscustomobject]@{ found = $false; changed = $false; old_value = $null; new_value = $Value }
    }

    $leaf = $Path[$Path.Count - 1]
    $property = $parent.PSObject.Properties[$leaf]
    if (-not $property) {
        return [pscustomobject]@{ found = $false; changed = $false; old_value = $null; new_value = $Value }
    }

    $oldValue = $property.Value
    $newValue = $Value
    if ($oldValue -is [bool] -and $Value -is [string]) {
        if ($Value -ieq 'true') { $newValue = $true }
        if ($Value -ieq 'false') { $newValue = $false }
    }

    $oldComparable = [string]$oldValue
    $newComparable = [string]$newValue
    if ($oldComparable -ne $newComparable) {
        Add-Member -InputObject $parent -NotePropertyName $leaf -NotePropertyValue $newValue -Force
        return [pscustomobject]@{ found = $true; changed = $true; old_value = $oldValue; new_value = $newValue }
    }

    return [pscustomobject]@{ found = $true; changed = $false; old_value = $oldValue; new_value = $newValue }
}

function Read-JsonFile {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "JSON file is empty: $Path"
    }

    return $text | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [string]$Path,
        $Json
    )

    $jsonText = $Json | ConvertTo-Json -Depth 100
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $jsonText + [Environment]::NewLine, $utf8NoBom)
}

function Backup-File {
    param([string]$Path)

    $backupPath = "$Path.bak"
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    }
}

function Invoke-JsonPatchFile {
    param(
        [string]$Path,
        [scriptblock]$Patch
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            file          = $Path
            exists        = $false
            changed       = $false
            would_change  = $false
            changes       = @()
            missing_paths = @()
        }
    }

    $json = Read-JsonFile -Path $Path
    try {
        $patchResult = & $Patch $json
    } catch {
        throw "Failed to patch $Path`: $($_.Exception.Message)"
    }

    try {
        $changes = @($patchResult.PSObject.Properties['changes'].Value)
        $missingPaths = @($patchResult.PSObject.Properties['missing_paths'].Value)
    } catch {
        $resultType = '<null>'
        if ($null -ne $patchResult) {
            $resultType = $patchResult.GetType().FullName
        }
        $propertyNames = @()
        if ($null -ne $patchResult) {
            $propertyNames = @($patchResult.PSObject.Properties | ForEach-Object { $_.Name })
        }
        throw "Failed to read patch result for $Path`: $($_.Exception.Message). Result type: $resultType. Properties: $($propertyNames -join ', ')"
    }
    $changed = $changes.Count -gt 0

    if ($changed -and -not $script:Options.DryRun) {
        Backup-File -Path $Path
        Write-JsonFile -Path $Path -Json $json
    }

    return [pscustomobject]@{
        file          = $Path
        exists        = $true
        changed       = ($changed -and -not $script:Options.DryRun)
        would_change  = $changed
        changes       = $changes
        missing_paths = $missingPaths
    }
}

function New-ChangeObject {
    param(
        [string]$Path,
        $Result
    )

    return [pscustomobject]@{
        path      = $Path
        old_value = $Result.old_value
        new_value = $Result.new_value
    }
}

function Add-JsonPatchResult {
    param(
        [System.Collections.Generic.List[object]]$Changes,
        [System.Collections.Generic.List[string]]$MissingPaths,
        [string]$Path,
        $Result
    )

    if (-not $Result.found) {
        [void]$MissingPaths.Add($Path)
        return
    }

    if ($Result.changed) {
        [void]$Changes.Add((New-ChangeObject -Path $Path -Result $Result))
    }
}

function Add-CustomerPrivacyChanges {
    param(
        $Json,
        [System.Collections.Generic.List[object]]$Changes
    )

    $found = 0
    $targets = @(
        [pscustomobject]@{ Path = @('customer', 'apk_associate'); Name = 'customer.apk_associate'; Value = 'false' },
        [pscustomobject]@{ Path = @('customer', 'app_keptlive'); Name = 'customer.app_keptlive'; Value = 'false' },
        [pscustomobject]@{ Path = @('customer', 'run_limitation'); Name = 'customer.run_limitation'; Value = 'false' },
        [pscustomobject]@{ Path = @('setting', 'other_setting', 'apk_association'); Name = 'setting.other_setting.apk_association'; Value = '0' },
        [pscustomobject]@{ Path = @('setting', 'other_setting', 'app_keptlive'); Name = 'setting.other_setting.app_keptlive'; Value = '0' },
        [pscustomobject]@{ Path = @('setting', 'other_setting', 'run_limitation'); Name = 'setting.other_setting.run_limitation'; Value = '0' }
    )

    foreach ($target in $targets) {
        $result = Set-JsonValueIfExists -Root $Json -Path $target.Path -Value $target.Value
        if ($result.found) {
            $found++
            if ($result.changed) {
                [void]$Changes.Add((New-ChangeObject -Path $target.Name -Result $result))
            }
        }
    }

    return $found
}

function Patch-CustomerConfig {
    param($Json)

    $changes = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[string]

    Add-JsonPatchResult -Changes $changes -MissingPaths $missing -Path 'setting.other_setting.root_mode' -Result (
        Set-JsonValueIfExists -Root $Json -Path @('setting', 'other_setting', 'root_mode') -Value '1'
    )

    Add-JsonPatchResult -Changes $changes -MissingPaths $missing -Path 'setting.disk_share.mode.choose' -Result (
        Set-JsonValueIfExists -Root $Json -Path @('setting', 'disk_share', 'mode', 'choose') -Value 'disk_share.mode.writable'
    )

    [void](Add-CustomerPrivacyChanges -Json $Json -Changes $changes)

    return [pscustomobject]@{
        changes       = @($changes.ToArray())
        missing_paths = @($missing.ToArray())
    }
}

function Patch-CustomerPrivacyConfig {
    param($Json)

    $changes = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[string]
    $found = Add-CustomerPrivacyChanges -Json $Json -Changes $changes
    if ($found -eq 0) {
        [void]$missing.Add('customer/settings privacy keys')
    }

    return [pscustomobject]@{
        changes       = @($changes.ToArray())
        missing_paths = @($missing.ToArray())
    }
}

function Patch-NxMainConfig {
    param($Json)

    $changes = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[string]
    $found = 0
    $targets = @(
        [pscustomobject]@{ Path = @('nxmain', 'setting', 'apk_association'); Name = 'nxmain.setting.apk_association'; Value = '0' },
        [pscustomobject]@{ Path = @('setting', 'apk_association'); Name = 'setting.apk_association'; Value = '0' },
        [pscustomobject]@{ Path = @('setting', 'other_setting', 'apk_association'); Name = 'setting.other_setting.apk_association'; Value = '0' }
    )

    foreach ($target in $targets) {
        $result = Set-JsonValueIfExists -Root $Json -Path $target.Path -Value $target.Value
        if ($result.found) {
            $found++
            if ($result.changed) {
                [void]$changes.Add((New-ChangeObject -Path $target.Name -Result $result))
            }
        }
    }

    if ($found -eq 0) {
        [void]$missing.Add('nxmain.setting.apk_association or setting.apk_association')
    }

    return [pscustomobject]@{
        changes       = @($changes.ToArray())
        missing_paths = @($missing.ToArray())
    }
}

function Patch-VmConfig {
    param($Json)

    $changes = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[string]

    $directResult = Set-JsonValueIfExists -Root $Json -Path @('system_vdi', 'sharable') -Value 'Writable'
    if ($directResult.found) {
        if ($directResult.changed) {
            [void]$changes.Add((New-ChangeObject -Path 'system_vdi.sharable' -Result $directResult))
        }
    }

    $nestedResult = Set-JsonValueIfExists -Root $Json -Path @('vm', 'system_vdi', 'sharable') -Value 'Writable'
    if ($nestedResult.found) {
        if ($nestedResult.changed) {
            [void]$changes.Add((New-ChangeObject -Path 'vm.system_vdi.sharable' -Result $nestedResult))
        }
    }

    if (-not $directResult.found -and -not $nestedResult.found) {
        [void]$missing.Add('system_vdi.sharable or vm.system_vdi.sharable')
    }

    return [pscustomobject]@{
        changes       = @($changes.ToArray())
        missing_paths = @($missing.ToArray())
    }
}

function Patch-ShellConfig {
    param($Json)

    $changes = New-Object System.Collections.Generic.List[object]
    $missing = New-Object System.Collections.Generic.List[string]

    $result = Set-JsonValueIfExists -Root $Json -Path @('player', 'uu_remote', 'should_show') -Value 'false'
    if ($result.found -and $result.changed) {
        [void]$changes.Add((New-ChangeObject -Path 'player.uu_remote.should_show' -Result $result))
    }

    return [pscustomobject]@{
        changes       = @($changes.ToArray())
        missing_paths = @($missing.ToArray())
    }
}

function Get-InstanceDirectories {
    param([string]$VmsPath)

    if (-not (Test-Path -LiteralPath $VmsPath -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $VmsPath -Directory | Where-Object { $_.Name -notmatch '-base$' })
}

function Format-RelativePath {
    param(
        [string]$BasePath,
        [string]$Path
    )

    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($base.Length)
    }

    return $Path
}

function Get-InstallLevelConfigFiles {
    param([string]$InstallRoot)

    $files = New-Object System.Collections.Generic.List[string]
    foreach ($relative in @('configs', 'nx_device\12.0\configs', 'nx_main\configs')) {
        $path = Join-ChildPath -Path $InstallRoot -Child $relative
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }

        foreach ($file in (Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.json', '.ini') })) {
            [void]$files.Add((Format-RelativePath -BasePath $InstallRoot -Path $file.FullName))
        }
    }

    return $files
}

function Get-UserConfigTargets {
    param($Install)

    $userDataRoot = Get-UserDataRoot
    if ([string]::IsNullOrWhiteSpace($userDataRoot)) {
        return @()
    }

    $editionInfo = $script:Editions[$Install.edition]
    $configRoot = Join-ChildPath -Path (Join-ChildPath -Path $userDataRoot -Child $editionInfo.UserConfigFolder) -Child 'configs'

    return @(
        [pscustomobject]@{
            Path  = Join-ChildPath -Path $configRoot -Child 'nx_main.json'
            Patch = ${function:Patch-NxMainConfig}
        },
        [pscustomobject]@{
            Path  = Join-ChildPath -Path (Join-ChildPath -Path $configRoot -Child 'multi-advanced') -Child 'customer_config.json'
            Patch = ${function:Patch-CustomerPrivacyConfig}
        },
        [pscustomobject]@{
            Path  = Join-ChildPath -Path (Join-ChildPath -Path $configRoot -Child 'multi-batch') -Child 'customer_config.json'
            Patch = ${function:Patch-CustomerPrivacyConfig}
        }
    )
}

function Invoke-UserConfigPatches {
    param($Install)

    $fileResults = New-Object System.Collections.Generic.List[object]
    $filesChanged = 0
    $filesWouldChange = 0
    $userDataRoot = Get-UserDataRoot

    foreach ($target in (Get-UserConfigTargets -Install $Install)) {
        $result = Invoke-JsonPatchFile -Path $target.Path -Patch $target.Patch
        [void]$fileResults.Add($result)
        if (-not $result.exists) { continue }

        $relative = $target.Path
        if (-not [string]::IsNullOrWhiteSpace($userDataRoot)) {
            $relative = Format-RelativePath -BasePath $userDataRoot -Path $target.Path
        }

        if ($result.would_change) {
            $filesWouldChange++
            if (-not $script:Options.DryRun) { $filesChanged++ }
            $verb = 'Updated'
            if ($script:Options.DryRun) { $verb = 'Would update' }
            $paths = ($result.changes | ForEach-Object { $_.path }) -join ', '
            Write-Log "[User config] $verb ${relative}: $paths"
        } elseif ($result.missing_paths.Count -eq 0) {
            Write-Log "[User config] $relative already in desired state"
        }
    }

    return [pscustomobject]@{
        files_changed      = $filesChanged
        files_would_change = $filesWouldChange
        files              = $fileResults
    }
}

function Restore-UserConfigBackups {
    param($Install)

    $restored = New-Object System.Collections.Generic.List[string]
    $userDataRoot = Get-UserDataRoot

    foreach ($target in (Get-UserConfigTargets -Install $Install)) {
        $backup = "$($target.Path).bak"
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { continue }

        if (-not $script:Options.DryRun) {
            Copy-Item -LiteralPath $backup -Destination $target.Path -Force
        }

        $relative = $target.Path
        if (-not [string]::IsNullOrWhiteSpace($userDataRoot)) {
            $relative = Format-RelativePath -BasePath $userDataRoot -Path $target.Path
        }
        [void]$restored.Add($relative)
        $verb = 'Restored'
        if ($script:Options.DryRun) { $verb = 'Would restore' }
        Write-Log "[User config] $verb $relative"
    }

    return $restored
}

function Get-RegistryDefaultValue {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Item -LiteralPath $Path).GetValue('')
}

function Set-RegistryDefaultValue {
    param(
        [string]$Path,
        [string]$Value
    )

    Set-ItemProperty -LiteralPath $Path -Name '(default)' -Value $Value
}

function Test-MuMuAssociationValue {
    param(
        [string]$Value,
        $Install
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $prefix = [regex]::Escape($script:Editions[$Install.edition].ClassPrefix)
    return ($Value -match "^$prefix\.(apk|xapk|apks)$")
}

function Test-AssociationCommandUnderInstall {
    param(
        [string]$ClassesRoot,
        [string]$ClassName,
        $Install
    )

    if ([string]::IsNullOrWhiteSpace($ClassName)) {
        return $false
    }

    $commandPath = Join-ChildPath -Path (Join-ChildPath -Path $ClassesRoot -Child $ClassName) -Child 'shell\open\command'
    if (-not (Test-Path -LiteralPath $commandPath)) {
        return $false
    }

    $command = [string](Get-RegistryDefaultValue -Path $commandPath)
    $rootPrefix = [System.IO.Path]::GetFullPath($Install.install_root).TrimEnd('\') + '\'
    return (Test-PathIsUnderRoot -Path ($command -replace '^"', '') -RootPrefixes @($rootPrefix))
}

function Invoke-ApkAssociationPatch {
    param($Install)

    $classesRoot = Get-ClassesRoot
    $entries = New-Object System.Collections.Generic.List[object]
    $changed = 0
    $wouldChange = 0

    foreach ($extension in @('.apk', '.xapk', '.apks')) {
        $extensionKey = Join-ChildPath -Path $classesRoot -Child $extension
        $exists = Test-Path -LiteralPath $extensionKey
        $oldValue = $null
        $newValue = $null
        $entryChanged = $false
        $entryWouldChange = $false

        if ($exists) {
            $key = Get-Item -LiteralPath $extensionKey
            $oldValue = [string]$key.GetValue('')
            $matchesMuMu = (Test-MuMuAssociationValue -Value $oldValue -Install $Install) -or
                (Test-AssociationCommandUnderInstall -ClassesRoot $classesRoot -ClassName $oldValue -Install $Install)

            if ($matchesMuMu) {
                $entryWouldChange = $true
                $wouldChange++
                $newValue = ''

                if (-not $script:Options.DryRun) {
                    if ($null -eq $key.GetValue($script:AssociationBackupValueName, $null)) {
                        Set-ItemProperty -LiteralPath $extensionKey -Name $script:AssociationBackupValueName -Value $oldValue
                    }
                    Set-RegistryDefaultValue -Path $extensionKey -Value ''
                    $entryChanged = $true
                    $changed++
                }

                $verb = 'Cleared'
                if ($script:Options.DryRun) { $verb = 'Would clear' }
                Write-Log "[Windows association] $verb $extension from $oldValue"
            }
        }

        [void]$entries.Add([pscustomobject]@{
            extension    = $extension
            key          = $extensionKey
            exists       = $exists
            old_value    = $oldValue
            new_value    = $newValue
            changed      = $entryChanged
            would_change = $entryWouldChange
        })
    }

    return [pscustomobject]@{
        classes_root = $classesRoot
        changed      = $changed
        would_change = $wouldChange
        entries      = $entries
    }
}

function Restore-ApkAssociation {
    param($Install)

    $classesRoot = Get-ClassesRoot
    $entries = New-Object System.Collections.Generic.List[object]
    $restored = 0

    foreach ($extension in @('.apk', '.xapk', '.apks')) {
        $extensionKey = Join-ChildPath -Path $classesRoot -Child $extension
        $exists = Test-Path -LiteralPath $extensionKey
        $backupValue = $null
        $entryRestored = $false

        if ($exists) {
            $key = Get-Item -LiteralPath $extensionKey
            $backupValue = [string]$key.GetValue($script:AssociationBackupValueName, $null)

            if ((Test-MuMuAssociationValue -Value $backupValue -Install $Install) -or
                (Test-AssociationCommandUnderInstall -ClassesRoot $classesRoot -ClassName $backupValue -Install $Install)) {
                if (-not $script:Options.DryRun) {
                    Set-RegistryDefaultValue -Path $extensionKey -Value $backupValue
                    Remove-ItemProperty -LiteralPath $extensionKey -Name $script:AssociationBackupValueName -ErrorAction SilentlyContinue
                    $entryRestored = $true
                }
                $restored++
                $verb = 'Restored'
                if ($script:Options.DryRun) { $verb = 'Would restore' }
                Write-Log "[Windows association] $verb $extension to $backupValue"
            }
        }

        [void]$entries.Add([pscustomobject]@{
            extension      = $extension
            key            = $extensionKey
            exists         = $exists
            backup_value   = $backupValue
            restored       = $entryRestored
            would_restore  = (-not [string]::IsNullOrWhiteSpace($backupValue))
        })
    }

    return [pscustomobject]@{
        classes_root = $classesRoot
        restored     = $restored
        entries      = $entries
    }
}

function Invoke-SetupInstall {
    param($Install)

    Write-Log "Found $($Install.edition_name) MuMu: $($Install.install_root)"
    if ($Install.display_version) {
        Write-Log "Version from registry: $($Install.display_version)"
    }

    $instanceResults = New-Object System.Collections.Generic.List[object]
    $instancesProcessed = 0
    $filesChanged = 0
    $filesWouldChange = 0
    $registryChanged = 0
    $registryWouldChange = 0

    foreach ($instance in (Get-InstanceDirectories -VmsPath $Install.vms_path)) {
        $configsPath = Join-ChildPath -Path $instance.FullName -Child 'configs'
        if (-not (Test-Path -LiteralPath $configsPath -PathType Container)) {
            Write-Log "[$($instance.Name)] configs directory not found; skipped"
            continue
        }

        $fileResults = New-Object System.Collections.Generic.List[object]
        $targets = @(
            [pscustomobject]@{ Name = 'customer_config.json'; Patch = ${function:Patch-CustomerConfig} },
            [pscustomobject]@{ Name = 'vm_config.json'; Patch = ${function:Patch-VmConfig} },
            [pscustomobject]@{ Name = 'shell_config.json'; Patch = ${function:Patch-ShellConfig} }
        )

        $instanceHadConfig = $false
        foreach ($target in $targets) {
            $filePath = Join-ChildPath -Path $configsPath -Child $target.Name
            $result = Invoke-JsonPatchFile -Path $filePath -Patch $target.Patch
            [void]$fileResults.Add($result)

            if ($result.exists) {
                $instanceHadConfig = $true
                if ($result.would_change) {
                    $filesWouldChange++
                    if (-not $script:Options.DryRun) { $filesChanged++ }
                    $verb = 'Updated'
                    if ($script:Options.DryRun) { $verb = 'Would update' }
                    $paths = ($result.changes | ForEach-Object { $_.path }) -join ', '
                    Write-Log "[$($instance.Name)] $verb $($target.Name): $paths"
                } elseif ($result.missing_paths.Count -gt 0) {
                    Write-Log "[$($instance.Name)] $($target.Name) has no applicable target path"
                } else {
                    Write-Log "[$($instance.Name)] $($target.Name) already in desired state"
                }

                if ($result.missing_paths.Count -gt 0) {
                    Write-Log "[$($instance.Name)] $($target.Name) missing expected path(s): $($result.missing_paths -join ', ')"
                }
            }
        }

        if ($instanceHadConfig) {
            $instancesProcessed++
        }

        [void]$instanceResults.Add([pscustomobject]@{
            instance = $instance.Name
            files    = $fileResults
        })
    }

    $userConfigResults = Invoke-UserConfigPatches -Install $Install
    $filesChanged += $userConfigResults.files_changed
    $filesWouldChange += $userConfigResults.files_would_change

    $associationResults = Invoke-ApkAssociationPatch -Install $Install
    $registryChanged += $associationResults.changed
    $registryWouldChange += $associationResults.would_change

    $installLevelConfigs = @(Get-InstallLevelConfigFiles -InstallRoot $Install.install_root)

    return [pscustomobject]@{
        edition                    = $Install.edition
        install_root               = $Install.install_root
        instances_processed        = $instancesProcessed
        files_changed              = $filesChanged
        files_would_change         = $filesWouldChange
        registry_changed           = $registryChanged
        registry_would_change      = $registryWouldChange
        dry_run                    = $script:Options.DryRun
        install_level_config_files = $installLevelConfigs
        user_configs               = $userConfigResults.files
        apk_associations           = $associationResults
        instances                  = $instanceResults
    }
}

function Invoke-RestoreInstall {
    param($Install)

    Write-Log "Found $($Install.edition_name) MuMu: $($Install.install_root)"

    $instancesRestored = 0
    $filesRestored = 0
    $registryRestored = 0
    $instanceResults = New-Object System.Collections.Generic.List[object]

    foreach ($instance in (Get-InstanceDirectories -VmsPath $Install.vms_path)) {
        $configsPath = Join-ChildPath -Path $instance.FullName -Child 'configs'
        if (-not (Test-Path -LiteralPath $configsPath -PathType Container)) {
            continue
        }

        $restoredFiles = New-Object System.Collections.Generic.List[string]
        foreach ($backup in (Get-ChildItem -LiteralPath $configsPath -File -Filter '*.bak' -ErrorAction SilentlyContinue)) {
            $target = $backup.FullName.Substring(0, $backup.FullName.Length - 4)
            if (-not $script:Options.DryRun) {
                Copy-Item -LiteralPath $backup.FullName -Destination $target -Force
            }
            [void]$restoredFiles.Add((Split-Path -Leaf $target))
            $filesRestored++
            $verb = 'Restored'
            if ($script:Options.DryRun) { $verb = 'Would restore' }
            Write-Log "[$($instance.Name)] $verb $(Split-Path -Leaf $target)"
        }

        if ($restoredFiles.Count -gt 0) {
            $instancesRestored++
        }

        [void]$instanceResults.Add([pscustomobject]@{
            instance = $instance.Name
            restored_files = $restoredFiles
        })
    }

    $userRestoredFiles = @(Restore-UserConfigBackups -Install $Install)
    $filesRestored += $userRestoredFiles.Count

    $associationResult = Restore-ApkAssociation -Install $Install
    $registryRestored += $associationResult.restored

    return [pscustomobject]@{
        edition            = $Install.edition
        install_root       = $Install.install_root
        instances_restored = $instancesRestored
        files_restored     = $filesRestored
        registry_restored  = $registryRestored
        dry_run            = $script:Options.DryRun
        user_restored_files = $userRestoredFiles
        apk_associations   = $associationResult
        instances          = $instanceResults
    }
}

function Get-DownloadFileName {
    param(
        [string]$Url,
        [string]$ContentDisposition
    )

    if ($ContentDisposition -and $ContentDisposition -match 'filename="?([^";]+)"?') {
        return $Matches[1]
    }

    $uri = [Uri]$Url
    return [System.IO.Path]::GetFileName($uri.AbsolutePath)
}

function Convert-Base64ToHex {
    param([string]$Base64)

    if ([string]::IsNullOrWhiteSpace($Base64)) {
        return $null
    }

    try {
        $bytes = [Convert]::FromBase64String($Base64)
        return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
    } catch {
        return $null
    }
}

function Get-Md5FromGoogleHashHeader {
    param([string]$Header)

    if ([string]::IsNullOrWhiteSpace($Header)) {
        return $null
    }

    if ($Header -match 'md5=([^,\s]+)') {
        return $Matches[1]
    }

    return $null
}

function Invoke-HeadRequest {
    param([string]$Url)

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = 'HEAD'
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'mumu-magisk-1click-ci'
    $request.Referer = 'https://www.mumuplayer.com/download/'

    try {
        $response = $request.GetResponse()
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $response = $_.Exception.Response
        } else {
            throw
        }
    }

    return $response
}

function Resolve-RedirectUrl {
    param(
        [string]$CurrentUrl,
        [string]$Location
    )

    $base = [Uri]$CurrentUrl
    $resolved = New-Object System.Uri($base, $Location)
    return $resolved.AbsoluteUri
}

function Resolve-MuMuDownload {
    $headers = @{
        Referer = 'https://www.mumuplayer.com/download/'
    }

    $metadataUrl = 'https://api.mumuplayer.com/api/website/download_version_info?usage=1'
    $downloadUrl = 'https://api.mumuplayer.com/api/dl/win?channel=gw-win-download'

    $metadata = Invoke-RestMethod -Uri $metadataUrl -Headers $headers -UseBasicParsing
    $win = @($metadata.data | Where-Object { $_.platform -eq 'win' } | Select-Object -First 1)
    if ($win.Count -eq 0) {
        throw 'Global version metadata did not include a Windows entry.'
    }

    $chain = New-Object System.Collections.Generic.List[object]
    $current = $downloadUrl
    for ($i = 0; $i -lt 8; $i++) {
        $response = Invoke-HeadRequest -Url $current
        try {
            $statusCode = [int]$response.StatusCode
            $location = $response.Headers['Location']
            $contentDisposition = $response.Headers['Content-Disposition']
            [void]$chain.Add([pscustomobject]@{
                status              = $statusCode
                url                 = $current
                location            = $location
                content_length      = $response.ContentLength
                content_disposition = $contentDisposition
                etag                = $response.Headers['ETag']
                last_modified       = $response.Headers['Last-Modified']
                x_goog_hash         = $response.Headers['x-goog-hash']
            })

            if ($statusCode -ge 300 -and $statusCode -lt 400 -and $location) {
                $current = Resolve-RedirectUrl -CurrentUrl $current -Location $location
                continue
            }

            break
        } finally {
            $response.Close()
        }
    }

    if ($chain.Count -eq 0) {
        throw 'No response received from Global download API.'
    }

    $invalid = @($chain | Where-Object { $_.status -ne 200 -and ($_.status -lt 300 -or $_.status -ge 400) })
    if ($invalid.Count -gt 0) {
        throw "Global download API returned unexpected status code(s): $(@($invalid | ForEach-Object { $_.status }) -join ', ')"
    }

    $final = $chain[$chain.Count - 1]
    $finalUrl = $final.url
    if ($final.status -ge 300 -and $final.status -lt 400 -and $final.location) {
        $finalUrl = Resolve-RedirectUrl -CurrentUrl $final.url -Location $final.location
    }

    $exeInChain = @($chain | Where-Object { $_.url -match '\.exe(\?|$)' -or $_.location -match '\.exe(\?|$)' })
    if ($exeInChain.Count -eq 0 -and $finalUrl -notmatch '\.exe(\?|$)') {
        throw 'Global download redirect chain did not include an .exe URL.'
    }

    $fileName = Get-DownloadFileName -Url $finalUrl -ContentDisposition $final.content_disposition
    $md5Base64 = Get-Md5FromGoogleHashHeader -Header $final.x_goog_hash
    $md5Hex = Convert-Base64ToHex -Base64 $md5Base64
    $etag = $final.etag
    if ($etag) {
        $etag = $etag.Trim('"')
        if (-not $md5Hex -and $etag -match '^[a-fA-F0-9]{32}$') {
            $md5Hex = $etag.ToLowerInvariant()
        }
    }

    return [pscustomobject]@{
        metadata_version         = $win[0].version
        metadata_update_time     = $win[0].update_time
        metadata_update_time_utc = ([DateTimeOffset]::FromUnixTimeSeconds([int64]$win[0].update_time)).UtcDateTime.ToString('u')
        download_api             = $downloadUrl
        final_url                = $finalUrl
        filename                 = $fileName
        content_length           = $final.content_length
        final_etag               = $etag
        final_md5_base64         = $md5Base64
        final_md5_hex            = $md5Hex
        final_last_modified      = $final.last_modified
        status_chain             = @($chain | ForEach-Object { $_.status })
        redirect_chain           = $chain
    }
}

function Save-MuMuInstaller {
    param(
        $Info,
        [string]$OutputPath,
        [string]$MetadataPath
    )

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-ChildPath -Path (Get-Location).Path -Child 'MuMuInstaller_Global.exe'
    }

    $resolvedOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedOutput)
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    $headers = @{
        Referer = 'https://www.mumuplayer.com/download/'
    }

    Write-Log "Downloading Global MuMu installer:"
    Write-Log $Info.final_url
    Invoke-WebRequest -UseBasicParsing -Uri $Info.final_url -Headers $headers -OutFile $resolvedOutput

    $file = Get-Item -LiteralPath $resolvedOutput
    if ($Info.content_length -gt 0 -and $file.Length -ne [int64]$Info.content_length) {
        throw "Downloaded installer size mismatch. Expected $($Info.content_length), got $($file.Length)."
    }

    $fileHash = (Get-FileHash -LiteralPath $resolvedOutput -Algorithm MD5).Hash.ToLowerInvariant()
    if ($Info.final_md5_hex -and $fileHash -ne $Info.final_md5_hex.ToLowerInvariant()) {
        throw "Downloaded installer MD5 mismatch. Expected $($Info.final_md5_hex), got $fileHash."
    }

    if ([string]::IsNullOrWhiteSpace($MetadataPath)) {
        $MetadataPath = Join-ChildPath -Path (Get-Location).Path -Child 'installer-url.txt'
    }

    $resolvedMetadata = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($MetadataPath)
    $metadataDirectory = [System.IO.Path]::GetDirectoryName($resolvedMetadata)
    if (-not [string]::IsNullOrWhiteSpace($metadataDirectory) -and -not (Test-Path -LiteralPath $metadataDirectory)) {
        New-Item -ItemType Directory -Path $metadataDirectory -Force | Out-Null
    }

    $metadataLines = @(
        'Global MuMu installer resolved via official API.',
        "MetadataVersion=$($Info.metadata_version)",
        "MetadataUpdateTimeUtc=$($Info.metadata_update_time_utc)",
        "CdnFile=$([System.IO.Path]::GetFileName(([Uri]$Info.final_url).AbsolutePath))",
        "ContentLength=$($Info.content_length)",
        "MD5=$fileHash",
        "ETag=$($Info.final_etag)",
        "LastModified=$($Info.final_last_modified)",
        "DownloadApi=$($Info.download_api)"
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($resolvedMetadata, (($metadataLines -join [Environment]::NewLine) + [Environment]::NewLine), $utf8NoBom)

    return [pscustomobject]@{
        output_path       = $resolvedOutput
        metadata_path     = $resolvedMetadata
        filename          = $Info.filename
        content_length    = $file.Length
        md5               = $fileHash
        metadata_version  = $Info.metadata_version
        final_url         = $Info.final_url
    }
}

function Show-Help {
    Write-Host @'
Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\MuMuConfig.ps1 -Action Setup [options]
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\MuMuConfig.ps1 -Action Restore [options]

Actions:
  Setup                  Patch non-base MuMu instances for root + writable system.
  Restore                Restore *.bak files created under instance configs.
  FindInstall            Print discovered installs.
  InspectInstallConfigs  List install-level JSON/INI files under configs, nx_device, nx_main.
  ResolveDownload        Resolve current Global Windows installer metadata and redirect URL.
  DownloadInstaller      Download current Global installer and write installer-url.txt.

Options:
  --edition auto|global|chinese|all   Default: auto. Auto prefers Global, then Chinese.
  --dry-run                           Report changes without writing files.
  --no-kill                           Do not stop MuMu processes/services.
  --install-root PATH                 Use a specific install root, then derive PATH\vms.
  --registry-root PATH                Test hook for an alternate uninstall registry root.
  --user-data-root PATH               Test hook for alternate %APPDATA%\Netease root.
  --classes-root PATH                 Test hook for alternate HKCU Software\Classes root.
  --output PATH                       Installer output path for DownloadInstaller.
  --metadata PATH                     Metadata output path for DownloadInstaller.
  --json                              Emit machine-readable JSON for the selected action.
'@
}

function Invoke-Main {
    Read-Arguments @args

    switch ($script:Options.Action) {
        'Help' {
            Show-Help
            return 0
        }
        'Resolvedownload' {
            $result = Resolve-MuMuDownload
            if ($script:Options.Json) {
                Write-JsonResult $result
            } else {
                Write-Host "Metadata version: $($result.metadata_version)"
                Write-Host "Metadata update time: $($result.metadata_update_time_utc)"
                Write-Host "Installer URL: $($result.final_url)"
                Write-Host "Filename: $($result.filename)"
                Write-Host "Content-Length: $($result.content_length)"
                Write-Host "MD5: $($result.final_md5_hex)"
                Write-Host "Status chain: $($result.status_chain -join ' -> ')"
            }
            return 0
        }
        'Downloadinstaller' {
            $info = Resolve-MuMuDownload
            $result = Save-MuMuInstaller -Info $info -OutputPath $script:Options.OutputPath -MetadataPath $script:Options.MetadataPath
            if ($script:Options.Json) {
                Write-JsonResult $result
            } else {
                Write-Host "Downloaded: $($result.output_path)"
                Write-Host "Metadata: $($result.metadata_path)"
                Write-Host "Content-Length: $($result.content_length)"
                Write-Host "MD5: $($result.md5)"
            }
            return 0
        }
        'Findinstall' {
            $installs = @(Find-MuMuInstall -Edition $script:Options.Edition)
            if ($script:Options.Json) {
                Write-JsonResult $installs
            } else {
                foreach ($install in $installs) {
                    Write-Host "$($install.edition_name): $($install.install_root)"
                }
            }
            if ($installs.Count -eq 0) { return 1 }
            return 0
        }
        'Inspectinstallconfigs' {
            $installs = @(Find-MuMuInstall -Edition $script:Options.Edition)
            if ($installs.Count -eq 0) {
                throw "No MuMu install found for edition '$($script:Options.Edition)'."
            }

            $result = @($installs | ForEach-Object {
                [pscustomobject]@{
                    edition      = $_.edition
                    install_root = $_.install_root
                    files        = @(Get-InstallLevelConfigFiles -InstallRoot $_.install_root)
                }
            })

            if ($script:Options.Json) {
                Write-JsonResult $result
            } else {
                foreach ($install in $result) {
                    Write-Host "$($install.edition): $($install.install_root)"
                    foreach ($file in $install.files) {
                        Write-Host "  $file"
                    }
                }
            }
            return 0
        }
        'Setup' {
            $installs = @(Find-MuMuInstall -Edition $script:Options.Edition)
            if ($installs.Count -eq 0) {
                throw "No MuMu install found for edition '$($script:Options.Edition)'."
            }

            if (-not $script:Options.NoKill) {
                Write-Log 'Stopping MuMu processes and services...'
                Stop-MuMuProcesses -Installs $installs
            }

            $results = @($installs | ForEach-Object { Invoke-SetupInstall -Install $_ })
            $instances = @($results | Measure-Object -Property instances_processed -Sum).Sum
            if ($instances -lt 1) {
                if ($script:Options.Json) { Write-JsonResult $results }
                throw 'No non-base MuMu instances with target config files were found.'
            }

            if ($script:Options.Json) {
                Write-JsonResult $results
            } else {
                $changed = @($results | Measure-Object -Property files_changed -Sum).Sum
                $wouldChange = @($results | Measure-Object -Property files_would_change -Sum).Sum
                $registryChanged = @($results | Measure-Object -Property registry_changed -Sum).Sum
                $registryWouldChange = @($results | Measure-Object -Property registry_would_change -Sum).Sum
                if ($script:Options.DryRun) {
                    Write-Host "Done. Files that would change: $wouldChange; registry associations that would change: $registryWouldChange"
                } else {
                    Write-Host "Done. Files changed: $changed; registry associations changed: $registryChanged"
                }
            }
            return 0
        }
        'Restore' {
            $installs = @(Find-MuMuInstall -Edition $script:Options.Edition)
            if ($installs.Count -eq 0) {
                throw "No MuMu install found for edition '$($script:Options.Edition)'."
            }

            if (-not $script:Options.NoKill) {
                Write-Log 'Stopping MuMu processes and services...'
                Stop-MuMuProcesses -Installs $installs
            }

            $results = @($installs | ForEach-Object { Invoke-RestoreInstall -Install $_ })
            $restored = @($results | Measure-Object -Property files_restored -Sum).Sum
            $registryRestored = @($results | Measure-Object -Property registry_restored -Sum).Sum
            if ($script:Options.Json) {
                Write-JsonResult $results
            } else {
                Write-Host "Done. Files restored: $restored; registry associations restored: $registryRestored"
            }
            if (($restored + $registryRestored) -lt 1) { return 1 }
            return 0
        }
        default {
            throw "Unknown action '$($script:Options.Action)'."
        }
    }
}

try {
    $exitCode = Invoke-Main @args
    exit $exitCode
} catch {
    $message = $_.Exception.Message
    if ($env:MUMU_DEBUG) {
        $message = "$message`n$($_.ScriptStackTrace)"
    }
    if ($script:Options.Json) {
        Write-JsonResult ([pscustomobject]@{
            error = $message
        })
    } else {
        Write-Error $message
    }
    exit 1
}
