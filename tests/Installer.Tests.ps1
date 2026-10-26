$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('mumu-installer-tests-' + [Guid]::NewGuid().ToString('N'))
$script:Assertions = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:Assertions++
}

function Get-Definitions {
    param([string]$Name)
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot ('scripts\' + $Name)), [ref]$null, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "Parse errors in $Name"
    return [scriptblock]::Create((@($ast.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.FunctionDefinitionAst]
    } | ForEach-Object { $_.Extent.Text }) -join "`n"))
}

function New-InstallerFixture {
    param([string]$Directory, [string]$Content, [string]$Version)
    [void][IO.Directory]::CreateDirectory($Directory)
    $binary = Join-Path $Directory 'MuMuInstaller_Global.exe'
    [IO.File]::WriteAllBytes($binary, [Text.Encoding]::ASCII.GetBytes($Content))
    $md5 = (Get-FileHash -LiteralPath $binary -Algorithm MD5).Hash.ToLowerInvariant()
    $sha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
    $metadata = "ArtifactType=WindowsBootstrap`nMetadataVersion=$Version`nContentLength=$((Get-Item -LiteralPath $binary).Length)`nMD5=$md5`nSHA256=$sha256`n"
    [IO.File]::WriteAllText((Join-Path $Directory 'installer-url.txt'), $metadata)
}

try {
    [void][IO.Directory]::CreateDirectory($testRoot)
    $configDefinitions = Get-Definitions 'MuMuConfig.ps1'
    $updateDefinitions = Get-Definitions 'Update-MuMuInstaller.ps1'
    & {
        . $configDefinitions
        foreach ($url in @('http://a11.gdl.netease.com/setup.exe', 'https://a11.gdl.netease.com.evil.invalid/setup.exe', 'https://evil.invalid/setup.exe', 'https://user@a11.gdl.netease.com/setup.exe', 'https://a11.gdl.netease.com:444/setup.exe', 'file:///C:/setup.exe')) {
            $refused = $false
            try { Assert-MuMuDownloadUrl -Url $url } catch { $refused = $true }
            Assert-True ($refused) "An untrusted download URL was accepted: $url"
        }
        $refused = $false
        try { Assert-MuMuDownloadUrl -Url 'https://api.mumuplayer.com/setup.exe' -Final } catch { $refused = $true }
        Assert-True ($refused) 'A non-CDN response was accepted as the final EXE.'
        $refused = $false
        try { Assert-MuMuDownloadUrl -Url 'https://a11.gdl.netease.com/setup.dmg' -Final } catch { $refused = $true }
        Assert-True ($refused) 'A macOS DMG was accepted as a Windows installer.'

        $script:Redirect = 'https://a11.gdl.netease.com/current.exe'
        $script:Length = 100
        $script:Checksum = '0123456789abcdef0123456789abcdef'
        $script:HeadCalls = 0
        function Invoke-RestMethod {
            param($Uri, $Headers, [switch]$UseBasicParsing, $TimeoutSec)
            [pscustomobject]@{ data = @([pscustomobject]@{ platform = 'win'; version = '6.8.5'; update_time = 1791883201 }) }
        }
        function Invoke-HeadRequest {
            param($Url)
            $script:HeadCalls++
            $response = if ($Url -like 'https://api.mumuplayer.com/*') {
                [pscustomobject]@{ StatusCode = 302; Headers = @{ Location = $script:Redirect }; ContentLength = 0 }
            } else {
                [pscustomobject]@{ StatusCode = 200; Headers = @{ ETag = $script:Checksum }; ContentLength = $script:Length }
            }
            Add-Member -InputObject $response -MemberType ScriptMethod -Name Close -Value { }
            return $response
        }
        $resolved = Resolve-MuMuDownload
        Assert-True ($resolved.metadata_version -eq '6.8.5' -and $resolved.final_md5_hex -eq $script:Checksum) 'The official redirect did not resolve its release and checksum.'
        $script:Redirect = 'https://evil.invalid/current.exe'
        $script:HeadCalls = 0
        $refused = $false
        try { Resolve-MuMuDownload | Out-Null } catch { $refused = $_.Exception.Message -match 'Untrusted' }
        Assert-True ($refused -and $script:HeadCalls -eq 1) 'An untrusted redirect was contacted before validation.'
        $script:Redirect = 'https://a11.gdl.netease.com/current.exe'
        $script:Length = 0
        $refused = $false
        try { Resolve-MuMuDownload | Out-Null } catch { $refused = $_.Exception.Message -match 'Content-Length' }
        Assert-True ($refused) 'A zero-length installer response was accepted.'
        $script:Length = 100
        $script:Checksum = ''
        $refused = $false
        try { Resolve-MuMuDownload | Out-Null } catch { $refused = $_.Exception.Message -match 'MD5' }
        Assert-True ($refused) 'An installer without a CDN checksum was accepted.'
    }

    & {
        . $updateDefinitions
        $destination = Join-Path $testRoot 'repository [literal paths]'
        $candidate = Join-Path $testRoot 'candidate'
        New-InstallerFixture -Directory $destination -Content 'MZoriginal' -Version '6.8.0'
        New-InstallerFixture -Directory $candidate -Content 'MZreplacement' -Version '6.8.5'
        $binary = Join-Path $destination 'MuMuInstaller_Global.exe'
        $metadataPath = Join-Path $destination 'installer-url.txt'
        $original = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
        $originalMetadata = [IO.File]::ReadAllText($metadataPath)
        $script:SignatureStatus = 'Valid'
        $script:Signer = 'CN=NetEase, O=Netease Interactive Entertainment Pte. Ltd., C=SG'
        $script:DownloadFailure = $false
        $script:CorruptDownload = $false
        $script:Downloads = 0
        function Get-AuthenticodeSignature {
            param($LiteralPath)
            [pscustomobject]@{ Status = $script:SignatureStatus; SignerCertificate = [pscustomobject]@{ Subject = $script:Signer } }
        }
        function Invoke-InstallerDownload {
            param($Root, $StageDirectory)
            $script:Downloads++
            Copy-Item -LiteralPath (Join-Path $candidate 'MuMuInstaller_Global.exe') -Destination $StageDirectory
            if ($script:DownloadFailure) { throw 'Simulated interrupted download.' }
            Copy-Item -LiteralPath (Join-Path $candidate 'installer-url.txt') -Destination $StageDirectory
            if ($script:CorruptDownload) { [IO.File]::WriteAllText((Join-Path $StageDirectory 'MuMuInstaller_Global.exe'), 'MZcorruption!') }
            $metadata = Read-InstallerMetadata -Path (Join-Path $candidate 'installer-url.txt')
            [pscustomobject]@{ sha256 = $metadata.SHA256; metadata_version = $metadata.MetadataVersion }
        }
        foreach ($failure in @('network', 'corruption', 'signature', 'publisher')) {
            $script:DownloadFailure = $failure -eq 'network'
            $script:CorruptDownload = $failure -eq 'corruption'
            $script:SignatureStatus = if ($failure -eq 'signature') { 'HashMismatch' } else { 'Valid' }
            $script:Signer = if ($failure -eq 'publisher') { 'CN=Other, O=Other Publisher, C=US' } else { 'CN=NetEase, O=Netease Interactive Entertainment Pte. Ltd., C=SG' }
            $refused = $false
            try { Update-MuMuInstaller -Root $destination | Out-Null } catch { $refused = $true }
            Assert-True ($refused) "An invalid installer was accepted: $failure"
            Assert-True ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -eq $original -and [IO.File]::ReadAllText($metadataPath) -eq $originalMetadata) "Failed $failure validation changed the committed files."
            Assert-True (@(Get-ChildItem -LiteralPath $destination -Directory -Filter '.mumu-installer-*').Count -eq 0) "Failed $failure validation leaked staged files."
        }
        $script:DownloadFailure = $false
        $script:CorruptDownload = $false
        $script:SignatureStatus = 'Valid'
        $script:Signer = 'CN=NetEase, O=Netease Interactive Entertainment Pte. Ltd., C=SG'
        $result = Update-MuMuInstaller -Root $destination
        Assert-True ($result.changed -and $result.binary_changed -and $result.metadata_changed -and [IO.File]::ReadAllText($binary) -eq 'MZreplacement') 'A complete new installer was not published.'
        $result = Update-MuMuInstaller -Root $destination
        Assert-True (-not $result.changed -and -not $result.binary_changed -and -not $result.metadata_changed) 'Identical upstream bytes caused a repeat update.'
        New-InstallerFixture -Directory $candidate -Content 'MZreplacement' -Version '6.8.6'
        $result = Update-MuMuInstaller -Root $destination
        Assert-True ($result.changed -and -not $result.binary_changed -and $result.metadata_changed -and $result.version -eq '6.8.6') 'A player release with unchanged bootstrap bytes was missed.'
        $downloadsBeforeVerify = $script:Downloads
        $result = Update-MuMuInstaller -Root $destination -VerifyOnly
        Assert-True ($script:Downloads -eq $downloadsBeforeVerify -and $result.version -eq '6.8.6') 'Committed-installer verification contacted the live download API.'
        [IO.File]::Delete($binary)
        $result = Update-MuMuInstaller -Root $destination
        Assert-True ($result.changed -and $result.binary_changed -and [IO.File]::Exists($binary)) 'A missing installer was not restored.'

        $invalidMetadata = Join-Path $testRoot 'duplicate.txt'
        [IO.File]::WriteAllText($invalidMetadata, "MD5=first`nMD5=second`n")
        $refused = $false
        try { Read-InstallerMetadata -Path $invalidMetadata | Out-Null } catch { $refused = $_.Exception.Message -match 'Duplicate' }
        Assert-True ($refused) 'Ambiguous duplicate metadata was accepted.'
        New-InstallerFixture -Directory $candidate -Content '<html>error</html>' -Version '6.8.7'
        $refused = $false
        try { Update-MuMuInstaller -Root $destination | Out-Null } catch { $refused = $_.Exception.Message -match 'Windows executable' }
        Assert-True ($refused -and [IO.File]::ReadAllText($binary) -eq 'MZreplacement') 'An HTML response replaced the Windows EXE.'

        # Hold the metadata open: publishing the second file must fail and roll
        # back the already-replaced EXE, preserving the previous matching pair.
        $stage = Join-Path $testRoot 'transaction-stage'
        New-InstallerFixture -Directory $stage -Content 'MZtransaction' -Version '6.8.8'
        $beforeMetadata = [IO.File]::ReadAllText($metadataPath)
        $lock = [IO.File]::Open($metadataPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        $refused = $false
        try { Publish-InstallerFiles -StageDirectory $stage -DestinationDirectory $destination } catch { $refused = $true } finally { $lock.Dispose() }
        Assert-True ($refused -and [IO.File]::ReadAllText($binary) -eq 'MZreplacement' -and [IO.File]::ReadAllText($metadataPath) -eq $beforeMetadata) 'A failed metadata replacement left a mismatched installer pair.'
    }
    Write-Host "Installer regression tests passed ($script:Assertions assertions)."
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -notmatch '^mumu-installer-tests-[a-f0-9]{32}$') { throw 'Unsafe installer test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
