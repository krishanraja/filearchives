[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Source,
    [Parameter(Mandatory)][string] $Destination,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

function Get-FaFolderSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Root)

    $canonical = ConvertTo-FaCanonicalPath $Root
    if (-not (Test-Path -LiteralPath $canonical -PathType Container)) {
        throw "source folder is absent: $canonical"
    }
    $prefix = $canonical.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $rows = [Collections.Generic.List[string]]::new()
    [long]$files = 0
    [long]$directories = 0
    [long]$bytes = 0
    Get-ChildItem -LiteralPath $canonical -Recurse -Force -ErrorAction Stop |
        Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($prefix.Length).Replace('/', '\')
            if ($_.PSIsContainer) {
                $directories++
                $rows.Add(('D|{0}' -f $relative))
            } else {
                $files++
                $bytes += [long]$_.Length
                $rows.Add(('F|{0}|{1}' -f $relative, [long]$_.Length))
            }
        }
    $payload = [string]::Join("`n", $rows)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))
    } finally {
        $sha.Dispose()
    }
    return [pscustomobject]@{
        Files = $files
        Directories = $directories
        Bytes = $bytes
        MetadataSeal = [Convert]::ToHexString($digest).ToLowerInvariant()
    }
}

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourcePath = ConvertTo-FaCanonicalPath $Source
$destinationPath = ConvertTo-FaCanonicalPath $Destination
Assert-FaNotProtected -Path $sourcePath -Workspace $workspace -Operation 'folder move source access'
Assert-FaNotProtected -Path $destinationPath -Workspace $workspace -Operation 'folder move destination access'
if (Test-Path -LiteralPath $destinationPath) {
    throw "destination already exists; merge moves are refused: $destinationPath"
}
if (-not ([IO.Path]::GetPathRoot($sourcePath)).Equals(
        [IO.Path]::GetPathRoot($destinationPath),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'cross-volume folder moves are refused; use a copy/hash/readback manifest and retire the source separately'
}
foreach ($configuredSource in $workspace.Sources) {
    if ($sourcePath.Equals($configuredSource.Path, [StringComparison]::OrdinalIgnoreCase)) {
        throw "moving a configured source root is refused: $sourcePath"
    }
}
$snapshot = Get-FaFolderSnapshot -Root $sourcePath
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'verified-folder-move-v1'
    Source = $sourcePath
    Destination = $destinationPath
    ExpectedFiles = $snapshot.Files
    ExpectedDirectories = $snapshot.Directories
    ExpectedBytes = $snapshot.Bytes
    ExpectedMetadataSeal = $snapshot.MetadataSeal
    VerificationClaim = 'relative path, item kind and file length; no content hash is claimed'
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 8
Write-Host "manifest: $ManifestPath"
Write-Host ("source: {0}  files={1} dirs={2} bytes={3}" -f
    $sourcePath, $snapshot.Files, $snapshot.Directories, $snapshot.Bytes)
Write-Host "destination: $destinationPath"
