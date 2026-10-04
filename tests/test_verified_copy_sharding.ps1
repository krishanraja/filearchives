$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-verified-shard-' + [guid]::NewGuid().ToString('n'))
$scope = Join-Path $scratch 'scope'
$source = Join-Path $scope 'source'
$destination = Join-Path $scratch 'destination'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
try {
    New-Item -ItemType Directory -Path (Join-Path $source 'nested'),$audit -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'one.txt'), 'one')
    [IO.File]::WriteAllText((Join-Path $source 'nested\two.txt'), 'two')
    [IO.File]::WriteAllText((Join-Path $source 'desktop.ini'), 'system')
    $workspace = [ordered]@{
        schema_version = 2
        audit = $audit
        sources = @(@{ id='fixture'; path=$scope; kind='test'; follow_reparse_points=$false })
        protected_roots = @((Join-Path $scratch 'protected'))
        protected_names = @()
    }
    [IO.File]::WriteAllText($config, ($workspace | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $verifiedPath = Join-Path $audit 'verified.manifest.json'
    & (Join-Path $repo 'stages\02_ingest\new_verified_copy_manifest.ps1') `
        -Source $source -Destination $destination -ManifestPath $verifiedPath `
        -ApprovalReason 'fixture' -ConfigPath $config
    $livePath = Join-Path $audit 'live.manifest.json'
    & (Join-Path $repo 'stages\02_ingest\new_live_file_copy_manifest_from_verified.ps1') `
        -InputManifestPath $verifiedPath -OutputManifestPath $livePath `
        -ApprovalReason 'fixture sharding' -ConfigPath $config
    $live = Get-Content -LiteralPath $livePath -Raw | ConvertFrom-Json
    if ($live.CopyCount -ne 2 -or @($live.Skipped).Count -ne 1) {
        throw 'verified manifest conversion did not account for every parent row'
    }
    if (@($live.Copies | Where-Object { -not [IO.Path]::IsPathRooted([string]$_.Source) -or
        -not [IO.Path]::IsPathRooted([string]$_.Destination) }).Count -ne 0) {
        throw 'verified manifest conversion emitted a relative copy path'
    }
    $shardRoot = Join-Path $audit 'shards'
    & (Join-Path $repo 'stages\02_ingest\split_live_file_copy_manifest.ps1') `
        -InputManifestPath $livePath -OutputRoot $shardRoot -ShardCount 2 -ConfigPath $config | Out-Null
    $shards = @(Get-ChildItem -LiteralPath $shardRoot -Filter '*.manifest.json' | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    })
    if ($shards.Count -ne 2 -or @($shards.Copies).Count -ne 2) {
        throw 'converted verified manifest did not shard exactly'
    }
    Write-Host 'PASS: a frozen verified folder copy converts into exact parallel live-copy shards'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
