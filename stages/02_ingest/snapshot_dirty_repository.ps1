[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SourceRepository,
    [Parameter(Mandatory)][string] $DestinationRepository,
    [Parameter(Mandatory)][string] $ReceiptPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$source = ConvertTo-FaCanonicalPath $SourceRepository
$destination = ConvertTo-FaCanonicalPath $DestinationRepository
Assert-FaNotProtected -Path $source -Workspace $workspace -Operation 'dirty repository snapshot source'
Assert-FaNotProtected -Path $destination -Workspace $workspace -Operation 'dirty repository snapshot destination'
if (-not (Test-Path -LiteralPath (Join-Path $source '.git'))) {
    throw "source is not a Git working tree: $source"
}
$manifestPath = $ReceiptPath + '.manifest.json'
$resumeExisting = $false
if (Test-Path -LiteralPath $destination) {
    if (-not (Test-Path -LiteralPath (Join-Path $destination '.git')) -or
        -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "snapshot destination already exists without this operation's recovery manifest: $destination"
    }
    $prior = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 8
    if (-not ([string]$prior.Source).Equals($source, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([string]$prior.Destination).Equals($destination, [StringComparison]::OrdinalIgnoreCase)) {
        throw "snapshot recovery manifest does not match existing destination: $destination"
    }
    $resumeExisting = $true
}

function Invoke-GitLines {
    param([string] $WorkingTree, [string[]] $Arguments)
    $lines = @(& git -c "safe.directory=$WorkingTree" -c core.quotepath=false `
        -C $WorkingTree @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "git failed in ${WorkingTree}: $($Arguments -join ' ')" }
    return @($lines | ForEach-Object { [string]$_ })
}

$head = @(Invoke-GitLines $source @('rev-parse', 'HEAD'))[0]
$branch = (Invoke-GitLines $source @('branch', '--show-current') | Select-Object -First 1)
$origin = (Invoke-GitLines $source @('remote', 'get-url', 'origin') | Select-Object -First 1)
$sourceStatus = @(Invoke-GitLines $source @('status', '--porcelain=v1', '--untracked-files=all'))
$trackedAndUntracked = @(Invoke-GitLines $source @('ls-files', '--cached', '--others', '--exclude-standard') |
    Sort-Object -Unique)
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'dirty-repository-snapshot-v1'
    Source = $source
    Destination = $destination
    Head = $head
    Branch = $branch
    Origin = ($origin -replace '(?i)(https?://)[^/@]+@', '$1[redacted]@')
    StatusEntries = [long]$sourceStatus.Count
    FilesToReconcile = [long]$trackedAndUntracked.Count
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $manifestPath -Value $manifest -Depth 8

New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
if (-not $resumeExisting) {
    & git -c 'safe.directory=*' clone --no-hardlinks --quiet $source $destination
    if ($LASTEXITCODE -ne 0) { throw "git clone failed: $source" }
}
if ($origin) {
    & git -c "safe.directory=$destination" -C $destination remote set-url origin $origin
    if ($LASTEXITCODE -ne 0) { throw 'could not restore the original remote URL in snapshot' }
}

$sourceIndex = Join-Path $source '.git\index'
$destinationIndex = Join-Path $destination '.git\index'
$sourceConfig = Join-Path $source '.git\config'
$destinationConfig = Join-Path $destination '.git\config'
Copy-Item -LiteralPath $sourceConfig -Destination $destinationConfig -Force -ErrorAction Stop
Copy-Item -LiteralPath $sourceIndex -Destination $destinationIndex -Force -ErrorAction Stop
$sourceIndexHash = Get-FaSha256 -Path $sourceIndex
if ((Get-FaSha256 -Path $destinationIndex) -ne $sourceIndexHash) {
    throw 'snapshot Git index failed content verification'
}
[long]$presentFiles = 0
[long]$bytes = 0
foreach ($relative in $trackedAndUntracked) {
    if ([string]::IsNullOrWhiteSpace($relative)) { continue }
    $sourceFile = ConvertTo-FaCanonicalPath (Join-Path $source $relative)
    $destinationFile = ConvertTo-FaCanonicalPath (Join-Path $destination $relative)
    if (-not (Test-FaPathWithin -Path $sourceFile -Root $source) -or
        -not (Test-FaPathWithin -Path $destinationFile -Root $destination)) {
        throw "Git path escapes repository: $relative"
    }
    if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $destinationFile) -Force | Out-Null
        Copy-Item -LiteralPath $sourceFile -Destination $destinationFile -Force -ErrorAction Stop
        $sourceHash = Get-FaSha256 -Path $sourceFile
        $destinationHash = Get-FaSha256 -Path $destinationFile
        if ($sourceHash -ne $destinationHash) { throw "snapshot file hash mismatch: $relative" }
        $item = Get-Item -LiteralPath $sourceFile
        $presentFiles++
        $bytes += [long]$item.Length
    } elseif (Test-Path -LiteralPath $destinationFile -PathType Leaf) {
        Remove-Item -LiteralPath $destinationFile -Force
    }
}
$finalTrackedAndUntracked = @(Invoke-GitLines $source @('ls-files', '--cached', '--others', '--exclude-standard') |
    Sort-Object -Unique)
if ([string]::Join("`n", $finalTrackedAndUntracked) -ne [string]::Join("`n", $trackedAndUntracked)) {
    throw 'source Git file set changed during snapshot reconciliation'
}
foreach ($relative in $finalTrackedAndUntracked) {
    if ([string]::IsNullOrWhiteSpace($relative)) { continue }
    $sourceFile = ConvertTo-FaCanonicalPath (Join-Path $source $relative)
    $destinationFile = ConvertTo-FaCanonicalPath (Join-Path $destination $relative)
    if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
        if (-not (Test-Path -LiteralPath $destinationFile -PathType Leaf) -or
            (Get-FaSha256 -Path $sourceFile) -ne (Get-FaSha256 -Path $destinationFile)) {
            throw "snapshot final content reconciliation failed: $relative"
        }
    } elseif (Test-Path -LiteralPath $destinationFile -PathType Leaf) {
        throw "snapshot retained a source-deleted file: $relative"
    }
}
$sourceStatusFinal = @(Invoke-GitLines $source @('status', '--porcelain=v1', '--untracked-files=all'))
if ([string]::Join("`n", $sourceStatusFinal) -ne [string]::Join("`n", $sourceStatus)) {
    throw 'source Git status changed during snapshot reconciliation'
}
$destinationHead = @(Invoke-GitLines $destination @('rev-parse', 'HEAD'))[0]
$destinationStatus = @(Invoke-GitLines $destination @('status', '--porcelain=v1', '--untracked-files=all'))
if ($destinationHead -ne $head) { throw 'snapshot HEAD does not match source HEAD' }
$statusEquivalent = [string]::Join("`n", $destinationStatus) -eq [string]::Join("`n", $sourceStatus)
if (-not $statusEquivalent) { throw 'snapshot Git status does not match source status' }
$sourceIndexEntries = @(Invoke-GitLines $source @('ls-files', '--stage'))
$destinationIndexEntries = @(Invoke-GitLines $destination @('ls-files', '--stage'))
$indexSemanticEquivalent = [string]::Join("`n", $destinationIndexEntries) -eq
    [string]::Join("`n", $sourceIndexEntries)
if (-not $indexSemanticEquivalent) { throw 'snapshot staged index entries do not match source' }
$receipt = [ordered]@{
    SchemaVersion = 1
    Kind = 'dirty-repository-snapshot-receipt-v1'
    Status = 'complete'
    ManifestSha256 = Get-FaSha256 -Path $manifestPath
    Source = $source
    Destination = $destination
    Head = $head
    Branch = $branch
    StatusEntries = [long]$sourceStatus.Count
    SnapshotStatusEntries = [long]$destinationStatus.Count
    StatusEquivalent = $statusEquivalent
    IndexSha256 = $sourceIndexHash
    IndexSemanticEquivalent = $indexSemanticEquivalent
    IndexEntries = [long]$sourceIndexEntries.Count
    VerifiedWorkingFiles = $presentFiles
    VerifiedWorkingBytes = $bytes
    SourceRetained = $true
    CompletedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReceiptPath -Value $receipt -Depth 8
Write-Host ("dirty repository snapshot verified: {0} source-status={1} snapshot-status={2}" -f
    $destination, $sourceStatus.Count, $destinationStatus.Count)
