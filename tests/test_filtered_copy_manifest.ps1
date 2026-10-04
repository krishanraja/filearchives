$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-filtered-copy-' + [guid]::NewGuid().ToString('n'))
$source = Join-Path $scratch 'source'
$destination = Join-Path $scratch 'destination'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
try {
    New-Item -ItemType Directory -Path (Join-Path $source 'Downloads\installer'),$audit -Force | Out-Null
    $keep = Join-Path $source 'canon.md'
    $installer = Join-Path $source 'Downloads\installer\payload.bin'
    [IO.File]::WriteAllText($keep, 'canon')
    [IO.File]::WriteAllText($installer, 'installer')
    $workspace = [ordered]@{
        schema_version = 2
        audit = $audit
        sources = @(@{ id='fixture'; path=$source; kind='test'; follow_reparse_points=$false })
        protected_roots = @((Join-Path $scratch 'protected'))
        protected_names = @()
    }
    [IO.File]::WriteAllText($config, ($workspace | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $parentPath = Join-Path $audit 'parent.manifest.json'
    $rows = foreach ($path in @($keep,$installer)) {
        $item = Get-Item -LiteralPath $path
        [ordered]@{
            Source = $item.FullName
            Destination = Join-Path $destination $item.Name
            Length = [long]$item.Length
            LastWriteTimeUtc = ([DateTimeOffset]$item.LastWriteTimeUtc).ToString('o')
            Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            Category = 'fixture'
            RuleId = 'fixture'
        }
    }
    $parent = [ordered]@{
        SchemaVersion = 1
        Kind = 'live-file-copy-v1'
        SourceRoot = $source
        SourceId = 'fixture'
        Copies = @($rows)
        CopyCount = 2
        Approved = $true
        ApprovalReason = 'fixture'
    }
    [IO.File]::WriteAllText($parentPath, ($parent | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $filteredPath = Join-Path $audit 'filtered.manifest.json'
    & (Join-Path $repo 'stages\02_ingest\new_filtered_live_file_copy_manifest.ps1') `
        -InputManifestPath $parentPath -OutputManifestPath $filteredPath `
        -ExcludePathRegex '(?i)[\\/]Downloads[\\/]' `
        -ApprovalReason 'fixture excludes installation media' -ConfigPath $config
    $filtered = Get-Content -LiteralPath $filteredPath -Raw | ConvertFrom-Json
    if ($filtered.CopyCount -ne 1 -or $filtered.ExcludedCount -ne 1) {
        throw 'filtered copy manifest did not partition every parent row'
    }
    if ([string]$filtered.Copies[0].Source -ne $keep -or
        [string]$filtered.Excluded[0].Source -ne $installer -or
        [string]$filtered.Excluded[0].Reason -ne 'path-regex-excluded') {
        throw 'filtered copy manifest kept or excluded the wrong row'
    }
    if ([string]$filtered.ParentManifestSha256 -ne
        (Get-FileHash -LiteralPath $parentPath -Algorithm SHA256).Hash.ToLowerInvariant()) {
        throw 'filtered copy manifest lost authenticated parent lineage'
    }
    Write-Host 'PASS: explicit waste filters preserve useful copy rows and parent lineage'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
