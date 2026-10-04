[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ParentManifestPath,
    [Parameter(Mandatory)][string] $ShardRoot,
    [Parameter(Mandatory)][string] $ReportPath,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$parentPath = ConvertTo-FaCanonicalPath $ParentManifestPath
$shardPath = ConvertTo-FaCanonicalPath $ShardRoot
$report = ConvertTo-FaCanonicalPath $ReportPath
Assert-FaNotProtected -Path $shardPath -Workspace $workspace -Operation 'copy shard verification input'
Assert-FaNotProtected -Path $report -Workspace $workspace -Operation 'copy shard verification report'
$parent = Get-Content -LiteralPath $parentPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
if ($parent.SchemaVersion -ne 1 -or $parent.Kind -notin @('live-file-copy-v1','streaming-folder-copy-v1') -or
    $parent.Approved -ne $true) {
    throw 'parent must be an approved live-file-copy-v1 or streaming-folder-copy-v1 manifest'
}
$parentRows = if ($parent.Kind -eq 'live-file-copy-v1') { @($parent.Copies) } else { @($parent.Files) }
$parentHash = Get-FaSha256 -Path $parentPath
$expected = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($row in $parentRows) {
    $key = '{0}|{1}|{2}|{3}' -f $row.Source,$row.Destination,[long]$row.Length,$row.LastWriteTimeUtc
    if ($expected.ContainsKey($key)) { throw "parent contains a duplicate copy identity: $($row.Source)" }
    $expected.Add($key,$row)
}

$shards = @(Get-ChildItem -LiteralPath $shardPath -File -Filter 'shard-*.manifest.json' -ErrorAction Stop | Sort-Object Name)
if ($shards.Count -eq 0) { throw 'copy shard set is empty' }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$indexes = [Collections.Generic.HashSet[int]]::new()
$details = [Collections.Generic.List[object]]::new()
[long]$verifiedBytes = 0
foreach ($shardFile in $shards) {
    $shard = Get-Content -LiteralPath $shardFile.FullName -Raw | ConvertFrom-Json -Depth 32 -DateKind String
    if ($shard.SchemaVersion -ne 1 -or $shard.Kind -ne $parent.Kind -or $shard.Approved -ne $true -or
        (ConvertTo-FaCanonicalPath ([string]$shard.ParentManifest)) -ne $parentPath -or
        [string]$shard.ParentManifestSha256 -ne $parentHash) {
        throw "shard does not authenticate its parent: $($shardFile.FullName)"
    }
    if (-not $indexes.Add([int]$shard.ShardIndex)) { throw "duplicate shard index: $($shard.ShardIndex)" }
    if ([int]$shard.ShardCount -ne $shards.Count) { throw "incomplete shard set: $($shardFile.FullName)" }
    $rows = if ($parent.Kind -eq 'live-file-copy-v1') { @($shard.Copies) } else { @($shard.Files) }
    foreach ($row in $rows) {
        $key = '{0}|{1}|{2}|{3}' -f $row.Source,$row.Destination,[long]$row.Length,$row.LastWriteTimeUtc
        if (-not $expected.ContainsKey($key) -or -not $seen.Add($key)) {
            throw "shard row is foreign or repeated: $($row.Source)"
        }
    }
    $receiptPath = $shardFile.FullName -replace '\.manifest\.json$','.receipt.json'
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
    $expectedReceiptKind = if ($parent.Kind -eq 'live-file-copy-v1') {
        'live-file-copy-receipt-v1'
    } else { 'streaming-folder-copy-receipt-v1' }
    $receiptRows = if ($parent.Kind -eq 'live-file-copy-v1') { @($receipt.Copies) } else { @($receipt.Files) }
    $receiptCount = if ($parent.Kind -eq 'live-file-copy-v1') { [long]$receipt.CopyCount } else { [long]$receipt.FileCount }
    if ($receipt.SchemaVersion -ne 1 -or $receipt.Kind -ne $expectedReceiptKind -or $receipt.Status -ne 'complete' -or
        [string]$receipt.ManifestSha256 -ne (Get-FaSha256 -Path $shardFile.FullName) -or
        $receiptCount -ne $rows.Count -or $receiptRows.Count -ne $rows.Count) {
        throw "copy shard receipt is incomplete or unauthenticated: $receiptPath"
    }
    $receiptKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $receiptRows) {
        $key = '{0}|{1}|{2}' -f $row.Source,$row.Destination,[long]$row.Length
        if (-not $receiptKeys.Add($key) -or -not [string]$row.Sha256) {
            throw "copy shard receipt has a duplicate or unhashed row: $receiptPath"
        }
        $verifiedBytes += [long]$row.Length
    }
    foreach ($row in $rows) {
        $key = '{0}|{1}|{2}' -f $row.Source,$row.Destination,[long]$row.Length
        if (-not $receiptKeys.Contains($key)) { throw "copy shard receipt omits a manifest row: $receiptPath" }
    }
    $details.Add([pscustomobject]@{ShardIndex=[int]$shard.ShardIndex;Rows=[long]$rows.Count;Receipt=$receiptPath})
}
if ($seen.Count -ne $expected.Count) { throw 'copy shard rows do not reconcile exactly to the parent manifest' }

$result = [ordered]@{
    SchemaVersion = 1
    Kind = 'copy-shard-set-verification-v1'
    Status = 'complete'
    ParentManifest = $parentPath
    ParentManifestSha256 = $parentHash
    ParentKind = [string]$parent.Kind
    ShardCount = [long]$shards.Count
    FileCount = [long]$seen.Count
    VerifiedBytes = $verifiedBytes
    Shards = @($details)
    VerificationClaim = 'every exact parent row appears in one shard and every shard has one complete hash-bearing receipt authenticated to its manifest'
    CompletedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $report -Value $result -Depth 16
Write-Host ("copy shard set verified: files={0} bytes={1} shards={2}" -f $seen.Count,$verifiedBytes,$shards.Count)
