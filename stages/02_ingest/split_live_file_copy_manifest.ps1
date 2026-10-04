[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $InputManifestPath,
    [Parameter(Mandatory)][string] $OutputRoot,
    [ValidateRange(2, 32)][int] $ShardCount = 4,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$inputPath = ConvertTo-FaCanonicalPath $InputManifestPath
if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
    throw "live-file copy manifest is absent: $inputPath"
}
$input = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
if ($input.SchemaVersion -ne 1 -or $input.Kind -ne 'live-file-copy-v1' -or $input.Approved -ne $true) {
    throw 'input must be an approved live-file-copy-v1 manifest'
}
$sourceRoot = ConvertTo-FaCanonicalPath ([string]$input.SourceRoot)
Assert-FaNotProtected -Path $sourceRoot -Workspace $workspace -Operation 'copy-shard source root'
$output = ConvertTo-FaCanonicalPath $OutputRoot
Assert-FaNotProtected -Path $output -Workspace $workspace -Operation 'copy-shard artifact root'
$parentHash = Get-FaSha256 -Path $inputPath
$copies = @($input.Copies)
$emitted = [Collections.Generic.List[object]]::new()
for ($shardIndex = 0; $shardIndex -lt $ShardCount; $shardIndex++) {
    $rows = [Collections.Generic.List[object]]::new()
    for ($index = $shardIndex; $index -lt $copies.Count; $index += $ShardCount) {
        $rows.Add($copies[$index])
    }
    $manifest = [ordered]@{
        SchemaVersion = 1
        Kind = 'live-file-copy-v1'
        SourceRoot = $sourceRoot
        SourceId = [string]$input.SourceId
        ParentManifest = $inputPath
        ParentManifestSha256 = $parentHash
        ShardIndex = $shardIndex
        ShardCount = $ShardCount
        Copies = @($rows)
        CopyCount = [long]$rows.Count
        Approved = $true
        ApprovalReason = "Deterministic non-overlapping shard of approved manifest: $($input.ApprovalReason)"
        CreatedAt = [DateTimeOffset]::Now.ToString('o')
    }
    $path = Join-Path $output ('shard-{0:D2}.manifest.json' -f $shardIndex)
    Write-FaAtomicJson -Path $path -Value $manifest -Depth 24
    $emitted.Add([pscustomobject]@{ ShardIndex=$shardIndex; Copies=[long]$rows.Count; Path=$path })
}
if ([long](@($emitted | Measure-Object Copies -Sum).Sum) -ne [long]$copies.Count) {
    throw 'shard copy counts do not reconcile to the parent manifest'
}
Write-Host ("copy manifest shards: parent-copies={0} shards={1} output={2}" -f $copies.Count,$ShardCount,$output)
$emitted
