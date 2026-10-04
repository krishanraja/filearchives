$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-layout-copy-test-' + [guid]::NewGuid().ToString('n'))
$source = Join-Path $scratch 'source'
$current = Join-Path $scratch 'current'
$personal = Join-Path $scratch 'personal'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
$proposal = Join-Path $audit 'layout-proposal.jsonl'
$manifest = Join-Path $audit 'copy.manifest.json'
$receipt = Join-Path $audit 'copy.receipt.json'
$retireManifest = Join-Path $audit 'retire.manifest.json'
try {
    New-Item -ItemType Directory -Path (Join-Path $source 'nested'),$audit -Force | Out-Null
    $paths = @{
        current = Join-Path $source 'nested\brief.md'
        personal = Join-Path $source 'passport.pdf'
        credential = Join-Path $source 'Google backup codes.txt'
        low = Join-Path $source 'mystery.bin'
        system = Join-Path $source 'desktop.ini'
    }
    foreach ($entry in $paths.GetEnumerator()) { [IO.File]::WriteAllText($entry.Value, $entry.Key) }
    $workspace = [ordered]@{
        schema_version = 2
        audit = $audit
        sources = @(@{ id='fixture'; path=$source; kind='test'; follow_reparse_points=$false })
        protected_roots = @((Join-Path $scratch 'protected'))
        protected_names = @()
    }
    [IO.File]::WriteAllText($config, ($workspace | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $rows = @(
        @{ SourceId='fixture'; RelativePath='nested\brief.md'; Length=(Get-Item $paths.current).Length; LastWriteTimeUtc=([DateTimeOffset](Get-Item $paths.current).LastWriteTimeUtc).ToString('o'); Category='venture'; Disposition='current'; Confidence='high'; RuleId='venture'; DestinationRoot=$current; DestinationFolder='01_VENTURE' },
        @{ SourceId='fixture'; RelativePath='passport.pdf'; Length=(Get-Item $paths.personal).Length; LastWriteTimeUtc=([DateTimeOffset](Get-Item $paths.personal).LastWriteTimeUtc).ToString('o'); Category='identity'; Disposition='personal-authority'; Confidence='high'; RuleId='identity'; DestinationRoot=$personal; DestinationFolder='01_IDENTITY' },
        @{ SourceId='fixture'; RelativePath='Google backup codes.txt'; Length=(Get-Item $paths.credential).Length; LastWriteTimeUtc=([DateTimeOffset](Get-Item $paths.credential).LastWriteTimeUtc).ToString('o'); Category='credentials'; Disposition='secure-quarantine-review'; Confidence='medium'; RuleId='credential-name-hint'; DestinationRoot=$null; DestinationFolder=$null },
        @{ SourceId='fixture'; RelativePath='mystery.bin'; Length=(Get-Item $paths.low).Length; LastWriteTimeUtc=([DateTimeOffset](Get-Item $paths.low).LastWriteTimeUtc).ToString('o'); Category='unknown'; Disposition='archive'; Confidence='low'; RuleId='fallback-old'; DestinationRoot=$current; DestinationFolder='90_UNKNOWN' },
        @{ SourceId='fixture'; RelativePath='desktop.ini'; Length=(Get-Item $paths.system).Length; LastWriteTimeUtc=([DateTimeOffset](Get-Item $paths.system).LastWriteTimeUtc).ToString('o'); Category='temporary'; Disposition='archive'; Confidence='high'; RuleId='temporary-path-override'; DestinationRoot=$current; DestinationFolder='99_QUARANTINE' }
    )
    $writer = [IO.StreamWriter]::new($proposal, $false, [Text.UTF8Encoding]::new($false))
    try { foreach($row in $rows){ $writer.WriteLine(($row | ConvertTo-Json -Compress)) } } finally { $writer.Dispose() }

    & (Join-Path $repo 'stages\02_ingest\new_layout_copy_manifest.ps1') `
        -ProposalPath $proposal -SourceRoot $source -SourceId fixture -CohortName 'L-Documents' `
        -ManifestPath $manifest -ApprovalReason 'test fixture' -ConfigPath $config
    $frozen = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($frozen.CopyCount -ne 2) { throw "expected two admitted layout rows, got $($frozen.CopyCount)" }
    if (@($frozen.Copies.Destination | Where-Object { $_ -match 'backup codes|desktop\.ini|mystery\.bin' }).Count -ne 0) {
        throw 'credential, system metadata, or low-confidence row entered layout copy manifest'
    }
    if (@($frozen.Skipped | Where-Object { $_.Reason -eq 'system-metadata-excluded' }).Count -ne 1) {
        throw 'system metadata must be excluded independently of classification order'
    }
    & (Join-Path $repo 'stages\02_ingest\invoke_live_file_copy_manifest.ps1') `
        -ManifestPath $manifest -ReceiptPath $receipt -Execute -ConfigPath $config
    $result = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if ($result.Status -ne 'complete' -or $result.CopyCount -ne 2 -or $result.SourceRetained -ne $true) {
        throw 'layout copy execution receipt is incorrect'
    }
    if ((Get-Content -LiteralPath ($receipt + '.progress.jsonl') | Measure-Object -Line).Lines -ne 2) {
        throw 'live layout copy did not journal per-file progress'
    }
    & (Join-Path $repo 'stages\07_structure\new_copy_retirement_manifest.ps1') `
        -CopyReceiptPath $receipt -CopyManifestPath $manifest -QuarantineRoot (Join-Path $scratch 'quarantine') `
        -ManifestPath $retireManifest -ApprovalReason 'test fixture' -ConfigPath $config
    $retire = Get-Content -LiteralPath $retireManifest -Raw | ConvertFrom-Json
    if ($retire.MoveCount -ne 2 -or
        @($retire.Moves.Destination | Where-Object { $_ -match 'quarantine\\nested\\brief\.md$' }).Count -ne 1) {
        throw 'live layout retirement did not preserve provenance from the frozen source root'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $current '01_VENTURE\L-Documents\nested\brief.md')) -or
        -not (Test-Path -LiteralPath (Join-Path $personal '01_IDENTITY\L-Documents\passport.pdf'))) {
        throw 'layout copy did not preserve relative provenance below the canonical cohort'
    }
    Write-Host 'PASS: recursive layout proposals become verified, credential-safe copy manifests'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
