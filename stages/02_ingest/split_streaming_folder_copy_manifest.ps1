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
$input = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
if ($input.SchemaVersion -ne 1 -or $input.Kind -ne 'streaming-folder-copy-v1' -or $input.Approved -ne $true) {
    throw 'input must be an approved streaming-folder-copy-v1 manifest'
}
$sourceRoot = ConvertTo-FaCanonicalPath ([string]$input.SourceRoot)
$destinationRoot = ConvertTo-FaCanonicalPath ([string]$input.DestinationRoot)
$output = ConvertTo-FaCanonicalPath $OutputRoot
Assert-FaNotProtected -Path $sourceRoot -Workspace $workspace -Operation 'streaming shard source'
Assert-FaNotProtected -Path $destinationRoot -Workspace $workspace -Operation 'streaming shard destination'
Assert-FaNotProtected -Path $output -Workspace $workspace -Operation 'streaming shard artifact root'

$buckets = @()
for ($index = 0; $index -lt $ShardCount; $index++) {
    $buckets += [pscustomobject]@{ Index=$index; Bytes=[long]0; Files=[Collections.Generic.List[object]]::new() }
}
foreach ($file in @($input.Files | Sort-Object @{Expression={[long]$_.Length};Descending=$true},RelativePath)) {
    $bucket = $buckets | Sort-Object Bytes,Index | Select-Object -First 1
    $bucket.Files.Add($file)
    $bucket.Bytes = [long]$bucket.Bytes + [long]$file.Length
}

$parentHash = Get-FaSha256 -Path $inputPath
$emitted = [Collections.Generic.List[object]]::new()
foreach ($bucket in $buckets) {
    $manifest = [ordered]@{
        SchemaVersion = 1
        Kind = 'streaming-folder-copy-v1'
        SourceRoot = $sourceRoot
        DestinationRoot = $destinationRoot
        ParentManifest = $inputPath
        ParentManifestSha256 = $parentHash
        ShardIndex = [int]$bucket.Index
        ShardCount = $ShardCount
        Files = @($bucket.Files)
        FileCount = [long]$bucket.Files.Count
        Bytes = [long]$bucket.Bytes
        Skipped = @()
        Approved = $true
        ApprovalReason = "Byte-balanced non-overlapping shard of approved manifest: $($input.ApprovalReason)"
        VerificationClaim = [string]$input.VerificationClaim
        CreatedAt = [DateTimeOffset]::Now.ToString('o')
    }
    $path = Join-Path $output ('shard-{0:D2}.manifest.json' -f $bucket.Index)
    Write-FaAtomicJson -Path $path -Value $manifest -Depth 20
    $emitted.Add([pscustomobject]@{ ShardIndex=$bucket.Index; Files=[long]$bucket.Files.Count; Bytes=[long]$bucket.Bytes; Path=$path })
}
if ([long](@($emitted | Measure-Object Files -Sum).Sum) -ne [long]$input.FileCount -or
    [long](@($emitted | Measure-Object Bytes -Sum).Sum) -ne [long]$input.Bytes) {
    throw 'streaming shard totals do not reconcile to the parent manifest'
}
Write-Host ("streaming copy shards: parent-files={0} bytes={1} shards={2} output={3}" -f
    $input.FileCount,$input.Bytes,$ShardCount,$output)
$emitted
