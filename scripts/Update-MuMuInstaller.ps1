[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }

function Read-InstallerMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)

    $metadata = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^([A-Za-z][A-Za-z0-9]*)=(.*)$') {
            if ($metadata.ContainsKey($Matches[1])) { throw "Duplicate installer metadata field: $($Matches[1])" }
            $metadata[$Matches[1]] = $Matches[2]
        }
    }
    if ($metadata.ArtifactType -ne 'WindowsBootstrap' -or
        $metadata.MetadataVersion -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$' -or
        $metadata.ContentLength -notmatch '^[1-9]\d*$' -or
        $metadata.MD5 -notmatch '^[a-fA-F0-9]{32}$' -or
        $metadata.SHA256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw "Missing or invalid installer metadata: $Path"
    }
    return $metadata
}

function Assert-OfficialMuMuInstaller {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Metadata
    )

    $file = Get-Item -LiteralPath $Path
    if ($file.Length -ne [int64]$Metadata.ContentLength) { throw 'Installer size does not match its metadata.' }
    $md5 = (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash.ToLowerInvariant()
    $sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($md5 -ne $Metadata.MD5 -or $sha256 -ne $Metadata.SHA256) { throw 'Installer checksums do not match its metadata.' }

    $stream = [IO.File]::OpenRead($Path)
    try {
        if ($stream.ReadByte() -ne 0x4D -or $stream.ReadByte() -ne 0x5A) { throw 'Installer is not a Windows executable.' }
    } finally { $stream.Dispose() }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ([string]$signature.Status -ne 'Valid' -or
        $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Netease Interactive Entertainment Pte\. Ltd\.(?:,|$)') {
        throw 'Installer must have a valid Authenticode signature from Netease Interactive Entertainment Pte. Ltd.'
    }
    return $sha256
}

function Publish-InstallerFiles {
    param(
        [Parameter(Mandatory = $true)][string]$StageDirectory,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory
    )

    $applied = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($name in @('MuMuInstaller_Global.exe', 'installer-url.txt')) {
            $source = Join-Path $StageDirectory $name
            $destination = Join-Path $DestinationDirectory $name
            $backup = Join-Path $StageDirectory ($name + '.backup')
            $existed = [IO.File]::Exists($destination)
            if ($existed) {
                [IO.File]::Replace($source, $destination, $backup)
            } else {
                [IO.File]::Move($source, $destination)
            }
            $applied.Add([pscustomobject]@{ Destination = $destination; Backup = $backup; Existed = $existed })
        }
    } catch {
        $publishError = $_
        for ($i = $applied.Count - 1; $i -ge 0; $i--) {
            $item = $applied[$i]
            if ($item.Existed) {
                [IO.File]::Replace($item.Backup, $item.Destination, [Management.Automation.Language.NullString]::Value)
            } else {
                [IO.File]::Delete($item.Destination)
            }
        }
        throw $publishError
    }
    foreach ($item in $applied) {
        if ([IO.File]::Exists($item.Backup)) { [IO.File]::Delete($item.Backup) }
    }
}

function Invoke-InstallerDownload {
    param([string]$Root, [string]$StageDirectory)

    $hostPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', (Join-Path $Root 'scripts\MuMuConfig.ps1'),
        '-Action', 'DownloadInstaller', '--output', (Join-Path $StageDirectory 'MuMuInstaller_Global.exe'),
        '--metadata', (Join-Path $StageDirectory 'installer-url.txt'), '--json'
    )
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $json = & $hostPath @arguments
            if ($LASTEXITCODE -ne 0) { throw "DownloadInstaller exited with code $LASTEXITCODE." }
            return ($json | ConvertFrom-Json)
        } catch {
            if ($attempt -eq 3) { throw }
            Write-Warning "MuMu download attempt $attempt failed; retrying: $_"
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}

function Update-MuMuInstaller {
    param([string]$Root, [switch]$VerifyOnly)

    $rootPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root)
    if (-not [IO.Directory]::Exists($rootPath)) { throw "Repository directory does not exist: $rootPath" }
    $installerPath = Join-Path $rootPath 'MuMuInstaller_Global.exe'
    $metadataPath = Join-Path $rootPath 'installer-url.txt'
    if ($VerifyOnly) {
        $metadata = Read-InstallerMetadata -Path $metadataPath
        $sha256 = Assert-OfficialMuMuInstaller -Path $installerPath -Metadata $metadata
        return [pscustomobject]@{ changed = $false; binary_changed = $false; metadata_changed = $false; version = $metadata.MetadataVersion; sha256 = $sha256 }
    }

    # Stage on the destination volume so replacement is atomic for each file.
    $stageDirectory = Join-Path $rootPath ('.mumu-installer-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stageDirectory)
    try {
        $download = Invoke-InstallerDownload -Root $rootPath -StageDirectory $stageDirectory
        $stagedInstaller = Join-Path $stageDirectory 'MuMuInstaller_Global.exe'
        $stagedMetadata = Join-Path $stageDirectory 'installer-url.txt'
        $metadata = Read-InstallerMetadata -Path $stagedMetadata
        $sha256 = Assert-OfficialMuMuInstaller -Path $stagedInstaller -Metadata $metadata
        if ($sha256 -ne $download.sha256 -or $metadata.MetadataVersion -ne $download.metadata_version) {
            throw 'Staged installer does not match the resolved release.'
        }
        $binaryChanged = -not [IO.File]::Exists($installerPath)
        if (-not $binaryChanged) { $binaryChanged = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash -ne $sha256 }
        $metadataChanged = -not [IO.File]::Exists($metadataPath)
        if (-not $metadataChanged) {
            $metadataChanged = (Get-FileHash -LiteralPath $metadataPath -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $stagedMetadata -Algorithm SHA256).Hash
        }
        if ($binaryChanged -or $metadataChanged) {
            # Always publish the entire verified EXE together with its metadata.
            Publish-InstallerFiles -StageDirectory $stageDirectory -DestinationDirectory $rootPath
        }
        return [pscustomobject]@{
            changed = ($binaryChanged -or $metadataChanged)
            binary_changed = $binaryChanged
            metadata_changed = $metadataChanged
            version = $metadata.MetadataVersion
            sha256 = $sha256
        }
    } finally {
        if (@(Get-ChildItem -LiteralPath $stageDirectory -Filter '*.backup' -File).Count -gt 0) {
            Write-Warning "Installer recovery backups were preserved at $stageDirectory"
        } else {
            $resolvedStage = [IO.Path]::GetFullPath($stageDirectory)
            if ([IO.Path]::GetDirectoryName($resolvedStage) -ne $rootPath.TrimEnd('\') -or
                (Split-Path -Leaf $resolvedStage) -notmatch '^\.mumu-installer-[a-f0-9]{32}$') { throw 'Unsafe installer staging cleanup path.' }
            Remove-Item -LiteralPath $resolvedStage -Recurse -Force
        }
    }
}

try {
    $result = Update-MuMuInstaller -Root $RepositoryRoot -VerifyOnly:$VerifyOnly
    if ($env:GITHUB_OUTPUT) {
        [IO.File]::AppendAllText($env:GITHUB_OUTPUT, "changed=$($result.changed.ToString().ToLowerInvariant())`nversion=$($result.version)`n", (New-Object Text.UTF8Encoding($false)))
    }
    if ($env:GITHUB_STEP_SUMMARY) {
        $summary = @(
            '### Global MuMu Windows download', '',
            "- Latest player version advertised by MuMu: $($result.version)",
            '- Artifact: official Windows bootstrap EXE; its bytes can remain unchanged across player releases.',
            "- Binary changed: $($result.binary_changed)",
            "- Metadata changed: $($result.metadata_changed)",
            "- SHA-256: $($result.sha256)",
            '- Size, MD5, SHA-256, and NetEase Authenticode signature verified.'
        ) -join "`n"
        [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, $summary + "`n", (New-Object Text.UTF8Encoding($false)))
    }
    $result | ConvertTo-Json
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
