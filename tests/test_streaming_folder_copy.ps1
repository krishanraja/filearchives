$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-streaming-copy-' + [guid]::NewGuid().ToString('n'))
$scope = Join-Path $scratch 'scope'
$source = Join-Path $scope 'source'
$destination = Join-Path $scratch 'destination'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
try {
    New-Item -ItemType Directory -Path (Join-Path $source 'nested'),$audit -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'one.txt'),('one-' * 10000))
    [IO.File]::WriteAllText((Join-Path $source 'nested\two.txt'),('two-' * 3000))
    [IO.File]::WriteAllText((Join-Path $source 'desktop.ini'),'system')
    [IO.File]::WriteAllText((Join-Path $source 'installer.bin'),'not selected')
    $workspace = [ordered]@{
        schema_version = 2
        audit = $audit
        sources = @(@{ id='fixture'; path=$scope; kind='test'; follow_reparse_points=$false })
        protected_roots = @((Join-Path $scratch 'protected'))
        protected_names = @()
    }
    [IO.File]::WriteAllText($config,($workspace|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $parent = Join-Path $audit 'parent.manifest.json'
    & (Join-Path $repo 'stages\02_ingest\new_streaming_folder_copy_manifest.ps1') `
        -Source $source -Destination $destination -ManifestPath $parent -ApprovalReason 'fixture' `
        -IncludeExtension @('.txt') -ConfigPath $config
    $frozen = Get-Content -LiteralPath $parent -Raw|ConvertFrom-Json
    if ($frozen.FileCount -ne 2 -or @($frozen.Skipped).Count -ne 2) { throw 'streaming manifest accounting failed' }
    $shardRoot = Join-Path $audit 'shards'
    & (Join-Path $repo 'stages\02_ingest\split_streaming_folder_copy_manifest.ps1') `
        -InputManifestPath $parent -OutputRoot $shardRoot -ShardCount 2 -ConfigPath $config | Out-Null
    $shards = @(Get-ChildItem -LiteralPath $shardRoot -Filter '*.manifest.json'|Sort-Object Name)
    if ($shards.Count -ne 2) { throw 'expected exactly two streaming shards' }
    foreach ($shard in $shards) {
        $receiptPath = $shard.FullName -replace '\.manifest\.json$','.receipt.json'
        & (Join-Path $repo 'stages\02_ingest\invoke_streaming_folder_copy_manifest.ps1') `
            -ManifestPath $shard.FullName -ReceiptPath $receiptPath -Execute -ConfigPath $config
    }
    $setReport = Join-Path $audit 'shard-set.report.json'
    & (Join-Path $repo 'stages\02_ingest\test_copy_shard_set.ps1') `
        -ParentManifestPath $parent -ShardRoot $shardRoot -ReportPath $setReport -ConfigPath $config
    $set = Get-Content -LiteralPath $setReport -Raw|ConvertFrom-Json
    if ($set.Status -ne 'complete' -or $set.FileCount -ne 2 -or $set.ShardCount -ne 2) {
        throw 'streaming copy shard-set verification failed'
    }
    foreach ($relative in @('one.txt','nested\two.txt')) {
        $sourceHash = (Get-FileHash -LiteralPath (Join-Path $source $relative) -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath (Join-Path $destination $relative) -Algorithm SHA256).Hash
        if ($sourceHash -ne $destinationHash) { throw "streaming copy hash mismatch: $relative" }
    }
    if ((-not (Test-Path -LiteralPath (Join-Path $source 'one.txt'))) -or
        (Test-Path -LiteralPath (Join-Path $destination 'desktop.ini'))) {
        throw 'streaming copy source retention or explicit skip failed'
    }
    Write-Host 'PASS: streaming folder copy shards and their receipts reconcile exactly with hash readback'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
