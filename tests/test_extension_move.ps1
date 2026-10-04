$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-extension-move-' + [guid]::NewGuid().ToString('n'))
$source = Join-Path $scratch 'source'
$destination = Join-Path $scratch 'destination'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
$manifest = Join-Path $audit 'manifest.json'
$receipt = Join-Path $audit 'receipt.json'
try {
    New-Item -ItemType Directory -Path (Join-Path $source 'nested'),$audit -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'nested\clip.mp4'), 'fixture video')
    [IO.File]::WriteAllText((Join-Path $source 'nested\LICENSE'), 'fixture extensionless file')
    [IO.File]::WriteAllText((Join-Path $source 'keep.txt'), 'keep')
    $workspace = [ordered]@{
        schema_version = 2
        audit = $audit
        sources = @(@{ id='fixture'; path=$source; kind='test'; follow_reparse_points=$false })
        protected_roots = @((Join-Path $scratch 'protected'))
        protected_names = @()
    }
    [IO.File]::WriteAllText($config, ($workspace | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    & (Join-Path $repo 'stages\07_structure\new_extension_move_manifest.ps1') `
        -SourceRoot $source -DestinationRoot $destination -Extension '.mp4' -IncludeExtensionless `
        -ManifestPath $manifest -ApprovalReason 'test same-volume metadata move' -MetadataOnly -ConfigPath $config
    $frozen = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($frozen.MoveCount -ne 2 -or @($frozen.Moves | Where-Object { $_.Sha256 }).Count -ne 0 -or
        @($frozen.Moves | Where-Object { $_.VerificationMode -ne 'metadata-only-same-volume-relocation' }).Count -ne 0) {
        throw 'metadata-only extension manifest read content or emitted the wrong verification contract'
    }
    & (Join-Path $repo 'stages\07_structure\invoke_live_file_move_manifest.ps1') `
        -ManifestPath $manifest -ReceiptPath $receipt -Execute -ConfigPath $config
    if (Test-Path -LiteralPath (Join-Path $source 'nested\clip.mp4')) { throw 'extension source remains' }
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'nested\clip.mp4'))) { throw 'extension destination absent' }
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'nested\LICENSE'))) { throw 'extensionless destination absent' }
    if (-not (Test-Path -LiteralPath (Join-Path $source 'keep.txt'))) { throw 'nonmatching file moved' }
    Write-Host 'PASS: explicit metadata-only same-volume extension routing avoids content reads'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
