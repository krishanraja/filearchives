[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ReceiptPath,
    [Parameter(Mandatory)][switch] $Execute,
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
        throw "folder is absent: $canonical"
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

function Assert-FaSnapshotMatches {
    param([Parameter(Mandatory)] $Actual, [Parameter(Mandatory)] $Manifest)
    if ([long]$Actual.Files -ne [long]$Manifest.ExpectedFiles -or
        [long]$Actual.Directories -ne [long]$Manifest.ExpectedDirectories -or
        [long]$Actual.Bytes -ne [long]$Manifest.ExpectedBytes -or
        [string]$Actual.MetadataSeal -ne [string]$Manifest.ExpectedMetadataSeal) {
        throw 'folder snapshot does not match the frozen manifest'
    }
}

if (-not $Execute) { throw 'execution requires the explicit -Execute switch' }
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "move manifest is absent: $ManifestPath"
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 16
if ($manifest.SchemaVersion -ne 1 -or $manifest.Kind -ne 'verified-folder-move-v1') {
    throw 'unsupported folder move manifest'
}
if ($manifest.Approved -ne $true -or [string]::IsNullOrWhiteSpace([string]$manifest.ApprovalReason)) {
    throw 'folder move manifest is not approved'
}
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourcePath = ConvertTo-FaCanonicalPath ([string]$manifest.Source)
$destinationPath = ConvertTo-FaCanonicalPath ([string]$manifest.Destination)
Assert-FaNotProtected -Path $sourcePath -Workspace $workspace -Operation 'folder move source access'
Assert-FaNotProtected -Path $destinationPath -Workspace $workspace -Operation 'folder move destination access'
if (Test-Path -LiteralPath $destinationPath) {
    throw "destination appeared after manifest freeze: $destinationPath"
}
$before = Get-FaFolderSnapshot -Root $sourcePath
Assert-FaSnapshotMatches -Actual $before -Manifest $manifest

$started = [DateTimeOffset]::Now
try {
    $parent = Split-Path -Parent $destinationPath
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Move-Item -LiteralPath $sourcePath -Destination $destinationPath -ErrorAction Stop
    if (Test-Path -LiteralPath $sourcePath) {
        throw "source remains after move: $sourcePath"
    }
    $after = Get-FaFolderSnapshot -Root $destinationPath
    Assert-FaSnapshotMatches -Actual $after -Manifest $manifest
    $receipt = [ordered]@{
        SchemaVersion = 1
        Kind = 'verified-folder-move-receipt-v1'
        Status = 'complete'
        ManifestSha256 = Get-FaSha256 -Path $ManifestPath
        Source = $sourcePath
        Destination = $destinationPath
        Files = $after.Files
        Directories = $after.Directories
        Bytes = $after.Bytes
        MetadataSeal = $after.MetadataSeal
        VerificationClaim = [string]$manifest.VerificationClaim
        StartedAt = $started.ToString('o')
        CompletedAt = [DateTimeOffset]::Now.ToString('o')
    }
    Write-FaAtomicJson -Path $ReceiptPath -Value $receipt -Depth 8
    Write-Host "verified move complete: $sourcePath -> $destinationPath"
    Write-Host "receipt: $ReceiptPath"
} catch {
    $receipt = [ordered]@{
        SchemaVersion = 1
        Kind = 'verified-folder-move-receipt-v1'
        Status = 'verification-failed'
        Source = $sourcePath
        Destination = $destinationPath
        Error = $_.Exception.Message
        StartedAt = $started.ToString('o')
        CompletedAt = [DateTimeOffset]::Now.ToString('o')
    }
    Write-FaAtomicJson -Path $ReceiptPath -Value $receipt -Depth 8
    throw
}
