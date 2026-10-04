$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-sensitive-test-' + [guid]::NewGuid().ToString('n'))
$source = Join-Path $scratch 'source'
$quarantine = Join-Path $scratch 'quarantine'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
$manifest = Join-Path $audit 'manifest.json'
$receipt = Join-Path $audit 'receipt.json'
try {
    New-Item -ItemType Directory -Path $source,$audit -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'backup codes.txt'), 'never log this payload')
    New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'nested\.env'), 'also never log this payload')
    [IO.File]::WriteAllText((Join-Path $source 'ordinary.txt'), 'ordinary')
    $workspace = [ordered]@{
        schema_version = 2
        audit = $audit
        sources = @(@{ id='fixture'; path=$source; kind='test'; follow_reparse_points=$false })
        protected_roots = @((Join-Path $scratch 'protected'))
        protected_names = @()
    }
    [IO.File]::WriteAllText($config, ($workspace | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    & (Join-Path $repo 'stages\07_structure\new_sensitive_name_quarantine_manifest.ps1') `
        -SourceRoot $source -QuarantineRoot $quarantine -NameRegex '(?i)(backup codes|^\.env$)' `
        -ManifestPath $manifest -ApprovalReason 'test fixture' -Recurse -ConfigPath $config
    $frozen = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($frozen.MoveCount -ne 2 -or $frozen.ContentRead -ne $false -or @($frozen.Moves | Where-Object Sha256).Count -ne 0) {
        throw 'sensitive manifest must contain metadata-only moves with no content digest'
    }
    & (Join-Path $repo 'stages\07_structure\invoke_live_file_move_manifest.ps1') `
        -ManifestPath $manifest -ReceiptPath $receipt -Execute -ConfigPath $config
    if (Test-Path -LiteralPath (Join-Path $source 'backup codes.txt')) { throw 'sensitive source remains' }
    if (-not (Test-Path -LiteralPath (Join-Path $quarantine 'backup codes.txt'))) { throw 'sensitive destination absent' }
    if (-not (Test-Path -LiteralPath (Join-Path $quarantine 'nested\.env'))) { throw 'recursive sensitive destination absent' }
    if (-not (Test-Path -LiteralPath (Join-Path $source 'ordinary.txt'))) { throw 'nonmatching file was moved' }
    Write-Host 'PASS: sensitive-name quarantine moves without hashing content'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
