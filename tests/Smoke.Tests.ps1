param(
    [switch]$SkipDownload
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts\MuMuConfig.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mumu-magisk-smoke-" + [Guid]::NewGuid().ToString('N'))
$registryRootNative = 'HKEY_CURRENT_USER\Software\mumu-magisk-1click-tests\Uninstall'
$registryRoot = "Registry::$registryRootNative"

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

    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments
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

    New-Item -ItemType Directory -Path $configRoot, $baseConfigRoot, $nxMainRoot -Force | Out-Null

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

    $findGlobal = Invoke-MuMuTool -Arguments @('-Action', 'FindInstall', '--edition', 'global', '--registry-root', $registryRoot, '--json')
    Assert-True ($findGlobal.ExitCode -eq 0) "FindInstall Global failed: $($findGlobal.Output)"
    $globalParsed = $findGlobal.Output | ConvertFrom-Json
    $globalInstall = @($globalParsed)[0]
    Assert-True ((First-Value $globalInstall.install_root) -eq (First-Value $global.InstallRoot)) 'FindInstall Global did not return the registry InstallLocation.'
    Assert-True (Test-Path -LiteralPath (First-Value $globalInstall.vms_path) -PathType Container) 'FindInstall Global returned an install without vms.'

    $findAuto = Invoke-MuMuTool -Arguments @('-Action', 'FindInstall', '--edition', 'auto', '--registry-root', $registryRoot, '--json')
    Assert-True ($findAuto.ExitCode -eq 0) "FindInstall auto failed: $($findAuto.Output)"
    $autoParsed = $findAuto.Output | ConvertFrom-Json
    $autoInstall = @($autoParsed)[0]
    Assert-True ((First-Value $autoInstall.edition) -eq 'global') "Auto discovery did not prefer Global when both editions were present. Output: $($findAuto.Output)"

    $findAll = Invoke-MuMuTool -Arguments @('-Action', 'FindInstall', '--edition', 'all', '--registry-root', $registryRoot, '--json')
    Assert-True ($findAll.ExitCode -eq 0) "FindInstall all failed: $($findAll.Output)"
    $allParsed = $findAll.Output | ConvertFrom-Json
    $allInstalls = @($allParsed)
    Assert-True ($allInstalls.Count -eq 2) "Edition all did not discover both fixtures. Output: $($findAll.Output)"

    $dryRun = Invoke-MuMuTool -Arguments @('-Action', 'Setup', '--edition', 'global', '--registry-root', $registryRoot, '--dry-run', '--no-kill', '--json')
    Assert-True ($dryRun.ExitCode -eq 0) "Setup dry-run failed: $($dryRun.Output)"
    $customerBefore = Read-Json (Join-Path $global.ConfigRoot 'customer_config.json')
    Assert-True ($customerBefore.setting.other_setting.root_mode -eq '0') 'Dry-run modified customer_config.json.'

    $setup = Invoke-MuMuTool -Arguments @('-Action', 'Setup', '--edition', 'global', '--registry-root', $registryRoot, '--no-kill', '--json')
    Assert-True ($setup.ExitCode -eq 0) "Setup failed: $($setup.Output)"

    $customer = Read-Json (Join-Path $global.ConfigRoot 'customer_config.json')
    $vm = Read-Json (Join-Path $global.ConfigRoot 'vm_config.json')
    $shell = Read-Json (Join-Path $global.ConfigRoot 'shell_config.json')
    $baseCustomer = Read-Json (Join-Path $global.BaseRoot 'customer_config.json')

    Assert-True ($customer.setting.other_setting.root_mode -eq '1') 'root_mode was not enabled.'
    Assert-True ($customer.setting.disk_share.mode.choose -eq 'disk_share.mode.writable') 'disk share mode was not made writable.'
    Assert-True ($customer.customer.apk_associate -eq 'false') 'customer.apk_associate privacy tweak was not disabled.'
    Assert-True ($customer.customer.app_keptlive -eq 'false') 'customer.app_keptlive privacy tweak was not disabled.'
    Assert-True ($customer.customer.run_limitation -eq 'false') 'customer.run_limitation privacy tweak was not disabled.'
    Assert-True ($customer.setting.other_setting.apk_association -eq '0') 'setting.other_setting.apk_association privacy tweak was not disabled.'
    Assert-True ($customer.setting.other_setting.app_keptlive -eq '0') 'setting.other_setting.app_keptlive privacy tweak was not disabled.'
    Assert-True ($customer.setting.other_setting.run_limitation -eq '0') 'setting.other_setting.run_limitation privacy tweak was not disabled.'
    Assert-True ($vm.system_vdi.sharable -eq 'Writable') 'system_vdi.sharable was not made Writable.'
    Assert-True ($vm.vm.system_vdi.sharable -eq 'Writable') 'vm.system_vdi.sharable was not made Writable.'
    Assert-True ([string]$shell.player.uu_remote.should_show -eq 'false') 'Optional shell_config remote UI key was not disabled.'
    Assert-True ($baseCustomer.setting.other_setting.root_mode -eq '0') 'Base instance was patched but should be skipped.'

    foreach ($name in @('customer_config.json', 'vm_config.json', 'shell_config.json')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $global.ConfigRoot "$name.bak") -PathType Leaf) "Backup was not created for $name."
    }

    $restore = Invoke-MuMuTool -Arguments @('-Action', 'Restore', '--edition', 'global', '--registry-root', $registryRoot, '--no-kill', '--json')
    Assert-True ($restore.ExitCode -eq 0) "Restore failed: $($restore.Output)"

    $restoredCustomer = Read-Json (Join-Path $global.ConfigRoot 'customer_config.json')
    $restoredVm = Read-Json (Join-Path $global.ConfigRoot 'vm_config.json')
    Assert-True ($restoredCustomer.setting.other_setting.root_mode -eq '0') 'Restore did not restore root_mode.'
    Assert-True ($restoredCustomer.setting.disk_share.mode.choose -eq 'disk_share.mode.readonly') 'Restore did not restore disk share mode.'
    Assert-True ($restoredCustomer.customer.apk_associate -eq 'true') 'Restore did not restore optional privacy keys.'
    Assert-True ($restoredVm.system_vdi.sharable -eq 'Readonly') 'Restore did not restore system_vdi.sharable.'
    Assert-True ($restoredVm.vm.system_vdi.sharable -eq 'Readonly') 'Restore did not restore vm.system_vdi.sharable.'

    $inspect = Invoke-MuMuTool -Arguments @('-Action', 'InspectInstallConfigs', '--edition', 'global', '--registry-root', $registryRoot, '--json')
    Assert-True ($inspect.ExitCode -eq 0) "InspectInstallConfigs failed: $($inspect.Output)"
    $inspectParsed = $inspect.Output | ConvertFrom-Json
    $inspectResult = @($inspectParsed)[0]
    Assert-True (@($inspectResult.files) -contains 'nx_main\configs\sample.ini') 'Install-level config inspection did not report nx_main sample.ini.'

    Remove-Item -Path "HKCU:\Software\mumu-magisk-1click-tests\Uninstall\MuMuPlayerGlobal-12.0" -Recurse -Force
    $findChineseOnly = Invoke-MuMuTool -Arguments @('-Action', 'FindInstall', '--edition', 'auto', '--registry-root', $registryRoot, '--json')
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

    Write-Host 'Smoke tests passed.'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
    if (Test-Path 'HKCU:\Software\mumu-magisk-1click-tests') {
        Remove-Item -Path 'HKCU:\Software\mumu-magisk-1click-tests' -Recurse -Force
    }
}
