$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-empty-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $scratch 'source'
$protected = Join-Path $source 'protected'
try {
    New-Item -ItemType Directory -Path (Join-Path $source 'empty\nested') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $source 'kept') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $protected 'never-read') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $source 'kept\file.txt') -Value 'keep'
    $audit = Join-Path $scratch 'audit'
    $config = Join-Path $scratch 'workspace.json'
    @{schema_version=2;audit=$audit;sources=@(@{id='fixture';path=$source;kind='test';follow_reparse_points=$false});protected_roots=@($protected);protected_names=@()} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $config
    $manifest = Join-Path $audit 'manifest.json'
    $receipt = Join-Path $audit 'receipt.json'
    & (Join-Path $repo 'stages\07_structure\new_empty_directory_manifest.ps1') -SourceRoot $source -ManifestPath $manifest -ApprovalReason 'test' -ConfigPath $config
    & (Join-Path $repo 'stages\07_structure\invoke_empty_directory_manifest.ps1') -ManifestPath $manifest -ReceiptPath $receipt -Execute -ConfigPath $config
    if (Test-Path -LiteralPath (Join-Path $source 'empty')) { throw 'empty tree was not removed' }
    if (-not (Test-Path -LiteralPath (Join-Path $source 'kept\file.txt'))) { throw 'non-empty tree was damaged' }
    if (-not (Test-Path -LiteralPath $protected)) { throw 'protected tree was touched' }
    $r = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if ($r.RemovedCount -ne 2) { throw "expected two removed directories, got $($r.RemovedCount)" }
    Write-Host 'empty directory cleanup test passed'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
