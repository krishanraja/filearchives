$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-ingress-dedupe-' + [guid]::NewGuid().ToString('n'))
$volume = Join-Path $scratch 'volume'
$destination = Join-Path $volume 'canonical'
$evidence = Join-Path $scratch 'evidence'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
try {
    New-Item -ItemType Directory -Path (Join-Path $destination 'a') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $destination 'much-longer-provenance') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $destination 'another-long-provenance') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $destination 'a\same.txt'), 'same bytes')
    [IO.File]::WriteAllText((Join-Path $destination 'much-longer-provenance\copy.txt'), 'same bytes')
    [IO.File]::WriteAllText((Join-Path $destination 'another-long-provenance\copy.txt'), 'same bytes')
    [IO.File]::WriteAllText((Join-Path $destination 'different.txt'), 'different')
    New-Item -ItemType Directory -Path (Join-Path $destination 'stream-a'),(Join-Path $destination 'stream-much-longer') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $destination 'stream-a\same.txt'), 'stream bytes')
    [IO.File]::WriteAllText((Join-Path $destination 'stream-much-longer\copy.txt'), 'stream bytes')
    $rows = @(Get-ChildItem -LiteralPath $destination -Recurse -File | Where-Object FullName -notmatch '\\stream-' | ForEach-Object {
        [pscustomobject]@{
            RelativePath = [IO.Path]::GetRelativePath($destination, $_.FullName)
            Length = [long]$_.Length
            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
    New-Item -ItemType Directory -Path $evidence -Force | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $evidence 'unrelated-report.json'),
        ([ordered]@{ Status='complete'; Note='valid JSON without an evidence kind' } | ConvertTo-Json),
        [Text.UTF8Encoding]::new($false))
    $copyManifest = [ordered]@{ SchemaVersion=1; Kind='verified-folder-copy-v1'; Destination=$destination; Files=$rows }
    [IO.File]::WriteAllText((Join-Path $evidence 'manifest.json'), ($copyManifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $streamFiles = @(Get-ChildItem -LiteralPath $destination -Recurse -File | Where-Object FullName -match '\\stream-' | ForEach-Object {
        [pscustomobject]@{
            Source = Join-Path $scratch ('source\' + $_.Name)
            Destination = $_.FullName
            Length = [long]$_.Length
            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            Status = 'verified-stream-and-readback'
        }
    })
    $streamReceipt = [ordered]@{ SchemaVersion=1; Kind='streaming-folder-copy-receipt-v1'; Status='complete'; Files=$streamFiles }
    [IO.File]::WriteAllText((Join-Path $evidence 'stream.receipt.json'), ($streamReceipt | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $workspace = [ordered]@{
        schema_version=2; audit=$audit
        sources=@(@{id='fixture';path=$volume;kind='test';follow_reparse_points=$false})
        protected_roots=@((Join-Path $scratch 'protected')); protected_names=@()
    }
    [IO.File]::WriteAllText($config, ($workspace | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $manifest=Join-Path $audit 'dedupe.manifest.json';$receipt=Join-Path $audit 'dedupe.receipt.json'
    & (Join-Path $repo 'stages\07_structure\new_ingress_duplicate_quarantine_manifest.ps1') `
        -EvidenceRoot $evidence -VolumeRoot $volume -QuarantineRoot (Join-Path $volume 'quarantine') `
        -ManifestPath $manifest -ApprovalReason 'test exact ingress duplicate' -ConfigPath $config
    $frozen=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
    if($frozen.MoveCount -ne 3 -or
        @($frozen.Moves | Where-Object Survivor -match '\\a\\same\.txt$').Count -ne 2 -or
        @($frozen.Moves | Where-Object Survivor -match '\\stream-a\\same\.txt$').Count -ne 1){
        throw 'ingress duplicate planner did not include streaming receipts or keep shortest proven paths'
    }
    if(@($frozen.Moves.Destination | Sort-Object -Unique).Count -ne $frozen.MoveCount){
        throw 'ingress duplicate planner produced colliding quarantine destinations'
    }
    & (Join-Path $repo 'stages\07_structure\invoke_live_file_move_manifest.ps1') `
        -ManifestPath $manifest -ReceiptPath $receipt -Execute -ConfigPath $config
    if(@($frozen.Moves | Where-Object { -not(Test-Path -LiteralPath $_.Survivor) -or (Test-Path -LiteralPath $_.Source) }).Count -ne 0){
        throw 'ingress duplicate executor did not retain the survivor and quarantine the redundant copy'
    }
    Write-Host 'PASS: exact ingress duplicates are rehashed and quarantined within one authority'
} finally {
    if(Test-Path -LiteralPath $scratch){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
