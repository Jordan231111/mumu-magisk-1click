param(
    [switch]$SkipDownload
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts\MuMuConfig.ps1'
$kitsuneScriptPath = Join-Path $repoRoot 'scripts\Kitsune.ps1'
$guestSanitizerPath = Join-Path $repoRoot 'scripts\mumu-guest-sanitize.sh'
$kitsuneApkPath = Join-Path $repoRoot 'Tools\app-release.apk'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mumu-magisk-smoke-" + [Guid]::NewGuid().ToString('N'))
$registryRootNative = 'HKEY_CURRENT_USER\Software\mumu-magisk-1click-tests\Uninstall'
$registryRoot = "Registry::$registryRootNative"
$userDataRoot = Join-Path $testRoot 'UserData\Netease'
$classesRootNative = 'HKEY_CURRENT_USER\Software\mumu-magisk-1click-tests\Classes'
$classesRoot = "Registry::$classesRootNative"
$classesRootPs = 'HKCU:\Software\mumu-magisk-1click-tests\Classes'
$commonArgs = @('--registry-root', $registryRoot, '--user-data-root', $userDataRoot, '--classes-root', $classesRoot)

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function First-Value {
    param($Value)
    return @($Value)[0]
}

function Invoke-MuMuTool {
    param([string[]]$Arguments)

    $output = & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File $scriptPath @Arguments
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = ($output -join [Environment]::NewLine)
    }
}

function New-MuMuFixture {
    param(
        [string]$Edition,
        [string]$FolderName
    )

    $installRoot = Join-Path $testRoot "Netease\$FolderName"
    $configRoot = Join-Path $installRoot 'vms\MuMuPlayer-12.0-0\configs'
    $baseConfigRoot = Join-Path $installRoot 'vms\MuMuPlayer-12.0-base\configs'
    $nxMainRoot = Join-Path $installRoot 'nx_main\configs'
    $userFolder = 'MuMuPlayer'
    if ($FolderName -like '*Global*') {
        $userFolder = 'MuMuPlayerGlobal'
    }
    $userConfigRoot = Join-Path $userDataRoot "$userFolder\configs"
    $userTemplateRoot = Join-Path $userConfigRoot 'multi-advanced'
    $engineBaseRoot = $null
    $expectedBaseRoot = $null

    New-Item -ItemType Directory -Path $configRoot, $baseConfigRoot, $nxMainRoot, $userConfigRoot, $userTemplateRoot -Force | Out-Null

    if ($Edition -eq 'Global') {
        $baseName = "$FolderName-base"
        $engineBaseRoot = Join-Path $installRoot "nx_device\12.0\vms\$baseName"
        $expectedBaseRoot = Join-Path $installRoot "vms\$baseName"
        New-Item -ItemType Directory -Path $engineBaseRoot -Force | Out-Null
        $vdiHeader = [System.Text.Encoding]::ASCII.GetBytes("<<< Oracle VM VirtualBox Disk Image >>>`n".PadRight(64, [char]0))
        [System.IO.File]::WriteAllBytes((Join-Path $engineBaseRoot 'system.vdi'), $vdiHeader)
    }

    @'
{
  "customer": {
    "apk_associate": "true",
    "app_keptlive": "true",
    "run_limitation": "true"
  },
  "setting": {
    "other_setting": {
      "root_mode": "0",
      "apk_association": "1",
      "app_keptlive": "1",
      "run_limitation": "1"
    },
    "disk_share": {
      "mode": {
        "choose": "disk_share.mode.readonly"
      }
    }
  }
}
'@ | Set-Content -LiteralPath (Join-Path $configRoot 'customer_config.json') -Encoding UTF8

    @'
{
  "system_vdi": {
    "sharable": "Readonly"
  },
  "vm": {
    "system_vdi": {
      "sharable": "Readonly"
    }
  }
}
'@ | Set-Content -LiteralPath (Join-Path $configRoot 'vm_config.json') -Encoding UTF8

    @'
{
  "player": {
    "uu_remote": {
      "should_show": "true"
    }
  }
}
'@ | Set-Content -LiteralPath (Join-Path $configRoot 'shell_config.json') -Encoding UTF8

    @'
{
  "setting": {
    "other_setting": {
      "root_mode": "0"
    },
    "disk_share": {
      "mode": {
        "choose": "disk_share.mode.readonly"
      }
    }
  }
}
'@ | Set-Content -LiteralPath (Join-Path $baseConfigRoot 'customer_config.json') -Encoding UTF8

    'enabled=true' | Set-Content -LiteralPath (Join-Path $nxMainRoot 'sample.ini') -Encoding ASCII

    @'
{
  "nxmain": {
    "setting": {
      "apk_association": "1"
    }
  }
}
'@ | Set-Content -LiteralPath (Join-Path $userConfigRoot 'nx_main.json') -Encoding UTF8

    @'
{
  "customer": {
    "apk_associate": "true",
    "app_keptlive": "true",
    "run_limitation": "true"
  }
}
'@ | Set-Content -LiteralPath (Join-Path $userTemplateRoot 'customer_config.json') -Encoding UTF8

    $keyName = $FolderName
    $keyPath = "HKCU:\Software\mumu-magisk-1click-tests\Uninstall\$keyName"
    New-Item -Path $keyPath -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name 'InstallLocation' -Value $installRoot -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name 'DisplayVersion' -Value "test-$Edition" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name 'DisplayName' -Value "MuMu Player $Edition" -PropertyType String -Force | Out-Null

    return [pscustomobject]@{
        Edition     = $Edition
        InstallRoot = $installRoot
        ConfigRoot  = $configRoot
        BaseRoot    = $baseConfigRoot
        EngineBaseRoot = $engineBaseRoot
        ExpectedBaseRoot = $expectedBaseRoot
        UserConfigRoot = $userConfigRoot
    }
}

function Set-RegistryDefault {
    param(
        [string]$Path,
        [string]$Value
    )

    Set-ItemProperty -LiteralPath $Path -Name '(default)' -Value $Value
}

function Get-RegistryDefault {
    param([string]$Path)

    return (Get-Item -LiteralPath $Path).GetValue('')
}

function New-ApkAssociationFixture {
    param($GlobalInstall)

    foreach ($extension in @('.apk', '.xapk', '.apks')) {
        $extensionKey = Join-Path $classesRootPs $extension
        New-Item -Path $extensionKey -Force | Out-Null
        Set-RegistryDefault -Path $extensionKey -Value "MuMuPlayerGlobal$extension"

        $commandKey = Join-Path $classesRootPs "MuMuPlayerGlobal$extension\shell\open\command"
        New-Item -Path $commandKey -Force | Out-Null
        Set-RegistryDefault -Path $commandKey -Value "`"$($GlobalInstall.InstallRoot)\nx_main\MuMuNxMain.exe`" -i `"%1`""
    }
}

function Read-Json {
    param([string]$Path)
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    if (Test-Path 'HKCU:\Software\mumu-magisk-1click-tests') {
        Remove-Item -Path 'HKCU:\Software\mumu-magisk-1click-tests' -Recurse -Force
    }

    $global = New-MuMuFixture -Edition 'Global' -FolderName 'MuMuPlayerGlobal-12.0'
    $chinese = New-MuMuFixture -Edition 'Chinese' -FolderName 'MuMuPlayer-12.0'
    New-ApkAssociationFixture -GlobalInstall $global

    $findGlobal = Invoke-MuMuTool -Arguments (@('-Action', 'FindInstall', '--edition', 'global') + $commonArgs + @('--json'))
    Assert-True ($findGlobal.ExitCode -eq 0) "FindInstall Global failed: $($findGlobal.Output)"
    $globalParsed = $findGlobal.Output | ConvertFrom-Json
    $globalInstall = @($globalParsed)[0]
    Assert-True ((First-Value $globalInstall.install_root) -eq (First-Value $global.InstallRoot)) 'FindInstall Global did not return the registry InstallLocation.'
    Assert-True (Test-Path -LiteralPath (First-Value $globalInstall.vms_path) -PathType Container) 'FindInstall Global returned an install without vms.'

    $findAuto = Invoke-MuMuTool -Arguments (@('-Action', 'FindInstall', '--edition', 'auto') + $commonArgs + @('--json'))
    Assert-True ($findAuto.ExitCode -eq 0) "FindInstall auto failed: $($findAuto.Output)"
    $autoParsed = $findAuto.Output | ConvertFrom-Json
    $autoInstall = @($autoParsed)[0]
    Assert-True ((First-Value $autoInstall.edition) -eq 'global') "Auto discovery did not prefer Global when both editions were present. Output: $($findAuto.Output)"

    $findAll = Invoke-MuMuTool -Arguments (@('-Action', 'FindInstall', '--edition', 'all') + $commonArgs + @('--json'))
    Assert-True ($findAll.ExitCode -eq 0) "FindInstall all failed: $($findAll.Output)"
    $allParsed = $findAll.Output | ConvertFrom-Json
    $allInstalls = @($allParsed)
    Assert-True ($allInstalls.Count -eq 2) "Edition all did not discover both fixtures. Output: $($findAll.Output)"

    $dryRun = Invoke-MuMuTool -Arguments (@('-Action', 'Setup', '--edition', 'global') + $commonArgs + @('--dry-run', '--no-kill', '--json'))
    Assert-True ($dryRun.ExitCode -eq 0) "Setup dry-run failed: $($dryRun.Output)"
    $dryRunParsed = @($dryRun.Output | ConvertFrom-Json)[0]
    $customerBefore = Read-Json (Join-Path $global.ConfigRoot 'customer_config.json')
    $nxMainBefore = Read-Json (Join-Path $global.UserConfigRoot 'nx_main.json')
    Assert-True ($customerBefore.setting.other_setting.root_mode -eq '0') 'Dry-run modified customer_config.json.'
    Assert-True ($nxMainBefore.nxmain.setting.apk_association -eq '1') 'Dry-run modified user nx_main.json.'
    Assert-True ((Get-RegistryDefault (Join-Path $classesRootPs '.apk')) -eq 'MuMuPlayerGlobal.apk') 'Dry-run modified APK registry association.'
    Assert-True (-not (Test-Path -LiteralPath $global.ExpectedBaseRoot)) 'Dry-run created a MuMu base junction.'
    Assert-True (@($dryRunParsed.engine_base_paths)[0].status -eq 'would-create-junction') 'Dry-run did not report the missing MuMu base junction.'

    $repair = Invoke-MuMuTool -Arguments (@('-Action', 'RepairBasePaths', '--edition', 'global') + $commonArgs + @('--no-kill', '--json'))
    Assert-True ($repair.ExitCode -eq 0) "RepairBasePaths failed: $($repair.Output)"
    $repairParsed = @($repair.Output | ConvertFrom-Json)[0]
    Assert-True (@($repairParsed.engine_base_paths)[0].status -eq 'created-junction') 'RepairBasePaths did not report its verified junction.'

    $setup = Invoke-MuMuTool -Arguments (@('-Action', 'Setup', '--edition', 'global') + $commonArgs + @('--no-kill', '--json'))
    Assert-True ($setup.ExitCode -eq 0) "Setup failed: $($setup.Output)"
    $setupParsed = @($setup.Output | ConvertFrom-Json)[0]

    $baseJunction = Get-Item -LiteralPath $global.ExpectedBaseRoot -Force
    Assert-True ($baseJunction.LinkType -eq 'Junction') 'Setup did not create a directory junction for the split MuMu base path.'
    Assert-True (([System.IO.Path]::GetFullPath([string](@($baseJunction.Target)[0])).TrimEnd('\')) -eq
        ([System.IO.Path]::GetFullPath($global.EngineBaseRoot).TrimEnd('\'))) 'MuMu base junction points to the wrong engine directory.'
    Assert-True (Test-Path -LiteralPath (Join-Path $global.ExpectedBaseRoot 'system.vdi') -PathType Leaf) 'MuMu base junction does not expose system.vdi.'
    Assert-True (@($setupParsed.engine_base_paths)[0].status -eq 'healthy') 'Setup did not preserve the repaired MuMu base junction as healthy.'

    $repeatSetup = Invoke-MuMuTool -Arguments (@('-Action', 'Setup', '--edition', 'global') + $commonArgs + @('--no-kill', '--json'))
    Assert-True ($repeatSetup.ExitCode -eq 0) "Repeated setup failed: $($repeatSetup.Output)"
    $repeatParsed = @($repeatSetup.Output | ConvertFrom-Json)[0]
    Assert-True (@($repeatParsed.engine_base_paths)[0].status -eq 'healthy') 'Repeated setup did not treat the verified base junction as healthy.'

    $customer = Read-Json (Join-Path $global.ConfigRoot 'customer_config.json')
    $vm = Read-Json (Join-Path $global.ConfigRoot 'vm_config.json')
    $shell = Read-Json (Join-Path $global.ConfigRoot 'shell_config.json')
    $baseCustomer = Read-Json (Join-Path $global.BaseRoot 'customer_config.json')
    $nxMain = Read-Json (Join-Path $global.UserConfigRoot 'nx_main.json')
    $templateCustomer = Read-Json (Join-Path $global.UserConfigRoot 'multi-advanced\customer_config.json')

    Assert-True ($customer.setting.other_setting.root_mode -eq '1') 'root_mode was not enabled.'
    Assert-True ($customer.setting.disk_share.mode.choose -eq 'disk_share.mode.writable') 'disk share mode was not made writable.'
    Assert-True ($customer.customer.apk_associate -eq 'false') 'customer.apk_associate privacy tweak was not disabled.'
    Assert-True ($customer.customer.app_keptlive -eq 'false') 'customer.app_keptlive privacy tweak was not disabled.'
    Assert-True ($customer.customer.run_limitation -eq 'false') 'customer.run_limitation privacy tweak was not disabled.'
    Assert-True ($customer.setting.other_setting.apk_association -eq '0') 'setting.other_setting.apk_association privacy tweak was not disabled.'
    Assert-True ($customer.setting.other_setting.app_keptlive -eq '0') 'setting.other_setting.app_keptlive privacy tweak was not disabled.'
    Assert-True ($customer.setting.other_setting.run_limitation -eq '0') 'setting.other_setting.run_limitation privacy tweak was not disabled.'
    Assert-True ($nxMain.nxmain.setting.apk_association -eq '0') 'User nx_main.apk_association was not disabled.'
    Assert-True ($templateCustomer.customer.apk_associate -eq 'false') 'User template APK association privacy key was not disabled.'
    Assert-True ($vm.system_vdi.sharable -eq 'Writable') 'system_vdi.sharable was not made Writable.'
    Assert-True ($vm.vm.system_vdi.sharable -eq 'Writable') 'vm.system_vdi.sharable was not made Writable.'
    Assert-True ([string]$shell.player.uu_remote.should_show -eq 'false') 'Optional shell_config remote UI key was not disabled.'
    Assert-True ($baseCustomer.setting.other_setting.root_mode -eq '0') 'Base instance was patched but should be skipped.'

    foreach ($name in @('customer_config.json', 'vm_config.json', 'shell_config.json')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $global.ConfigRoot "$name.bak") -PathType Leaf) "Backup was not created for $name."
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $global.UserConfigRoot 'nx_main.json.bak') -PathType Leaf) 'Backup was not created for user nx_main.json.'
    Assert-True ((Get-RegistryDefault (Join-Path $classesRootPs '.apk')) -eq '') 'APK registry association was not cleared.'
    $apkKey = Get-Item -LiteralPath (Join-Path $classesRootPs '.apk')
    Assert-True ([string]$apkKey.GetValue('mumu_magisk_1click_backup_default', $null) -eq 'MuMuPlayerGlobal.apk') 'APK registry association backup was not stored.'

    $restore = Invoke-MuMuTool -Arguments (@('-Action', 'Restore', '--edition', 'global') + $commonArgs + @('--no-kill', '--json'))
    Assert-True ($restore.ExitCode -eq 0) "Restore failed: $($restore.Output)"

    $restoredCustomer = Read-Json (Join-Path $global.ConfigRoot 'customer_config.json')
    $restoredVm = Read-Json (Join-Path $global.ConfigRoot 'vm_config.json')
    $restoredNxMain = Read-Json (Join-Path $global.UserConfigRoot 'nx_main.json')
    Assert-True ($restoredCustomer.setting.other_setting.root_mode -eq '0') 'Restore did not restore root_mode.'
    Assert-True ($restoredCustomer.setting.disk_share.mode.choose -eq 'disk_share.mode.readonly') 'Restore did not restore disk share mode.'
    Assert-True ($restoredCustomer.customer.apk_associate -eq 'true') 'Restore did not restore optional privacy keys.'
    Assert-True ($restoredNxMain.nxmain.setting.apk_association -eq '1') 'Restore did not restore user nx_main.apk_association.'
    Assert-True ((Get-RegistryDefault (Join-Path $classesRootPs '.apk')) -eq 'MuMuPlayerGlobal.apk') 'Restore did not restore APK registry association.'
    Assert-True ($restoredVm.system_vdi.sharable -eq 'Readonly') 'Restore did not restore system_vdi.sharable.'
    Assert-True ($restoredVm.vm.system_vdi.sharable -eq 'Readonly') 'Restore did not restore vm.system_vdi.sharable.'

    $inspect = Invoke-MuMuTool -Arguments (@('-Action', 'InspectInstallConfigs', '--edition', 'global') + $commonArgs + @('--json'))
    Assert-True ($inspect.ExitCode -eq 0) "InspectInstallConfigs failed: $($inspect.Output)"
    $inspectParsed = $inspect.Output | ConvertFrom-Json
    $inspectResult = @($inspectParsed)[0]
    Assert-True (@($inspectResult.files) -contains 'nx_main\configs\sample.ini') 'Install-level config inspection did not report nx_main sample.ini.'

    Remove-Item -Path "HKCU:\Software\mumu-magisk-1click-tests\Uninstall\MuMuPlayerGlobal-12.0" -Recurse -Force
    $findChineseOnly = Invoke-MuMuTool -Arguments (@('-Action', 'FindInstall', '--edition', 'auto') + $commonArgs + @('--json'))
    Assert-True ($findChineseOnly.ExitCode -eq 0) "FindInstall Chinese-only failed: $($findChineseOnly.Output)"
    $chineseParsed = $findChineseOnly.Output | ConvertFrom-Json
    $chineseOnly = @($chineseParsed)[0]
    Assert-True ((First-Value $chineseOnly.edition) -eq 'chinese') "Auto discovery did not fall back to Chinese when Global was absent. Output: $($findChineseOnly.Output)"
    Assert-True ((First-Value $chineseOnly.install_root) -eq (First-Value $chinese.InstallRoot)) 'Chinese fixture InstallLocation was not returned.'

    if (-not $SkipDownload) {
        $download = Invoke-MuMuTool -Arguments @('-Action', 'ResolveDownload', '--json')
        Assert-True ($download.ExitCode -eq 0) "ResolveDownload failed: $($download.Output)"
        $downloadParsed = $download.Output | ConvertFrom-Json
        $downloadInfo = @($downloadParsed)[0]
        Assert-True ($downloadInfo.final_url -match '^https://a11\.gdl\.netease\.com/.*\.exe(\?|$)') 'Global download URL did not match the expected CDN .exe pattern.'
        Assert-True (@($downloadInfo.status_chain) -contains 302) 'Global download resolution did not include the API redirect.'
        Assert-True (@($downloadInfo.status_chain) -contains 200) 'Global download resolution did not include a final 200 response.'
    }

    $kitsuneHelp = & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File $kitsuneScriptPath --help
    Assert-True ($LASTEXITCODE -eq 0) "Kitsune helper help failed: $($kitsuneHelp -join [Environment]::NewLine)"
    Assert-True (($kitsuneHelp -join "`n") -match 'prepare\s+Repair verified MuMu base paths') 'Kitsune helper did not expose the guarded prepare workflow.'
    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
    $missingInstance = & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File $kitsuneScriptPath prepare --instance nope 2>&1
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    Assert-True ($LASTEXITCODE -eq 1) 'Kitsune helper accepted a nonnumeric instance override.'
    Assert-True (($missingInstance -join "`n") -match '--instance must be a numeric') 'Kitsune invalid-instance error was not actionable.'

    $apkSha256 = (Get-FileHash -LiteralPath $kitsuneApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-True ($apkSha256 -eq 'fac319d2de262fcfff1684e13e1a5c61c486d2a773a7a8ffcfdbfe6f763a7fd4') 'Bundled Kitsune APK is not the pinned v31.0-25fa2159 asset.'
    $guestBytes = [System.IO.File]::ReadAllBytes($guestSanitizerPath)
    Assert-True (-not ($guestBytes -contains 13)) 'Guest sanitizer contains CRLF; Android shell scripts must remain LF-only.'

    Write-Host 'Smoke tests passed.'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
    if (Test-Path 'HKCU:\Software\mumu-magisk-1click-tests') {
        Remove-Item -Path 'HKCU:\Software\mumu-magisk-1click-tests' -Recurse -Force
    }
}
