$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-copy-test-' + [guid]::NewGuid().ToString('n'))
$scope = Join-Path $scratch 'scope'
$source = Join-Path $scope 'source'
$destination = Join-Path $scratch 'destination'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
$manifest = Join-Path $audit 'copy.manifest.json'
$receipt = Join-Path $audit 'copy.receipt.json'
try {
    New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $source 'empty') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'one.txt'), 'alpha')
    [IO.File]::WriteAllText((Join-Path $source 'nested\two.txt'), 'beta')
    [IO.File]::WriteAllText((Join-Path $source 'nested\one.txt'), 'different file, same leaf name')
    [IO.File]::WriteAllText((Join-Path $source 'ignored.json'), '{}')
    $workspace = [ordered]@{
        schema_version = 2
        audit = $audit
        sources = @(@{ id='fixture'; path=$scope; kind='test'; follow_reparse_points=$false })
        protected_roots = @((Join-Path $scratch 'protected'))
        protected_names = @()
    }
    [IO.File]::WriteAllText($config, ($workspace | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    & (Join-Path $repo 'stages\02_ingest\new_verified_copy_manifest.ps1') `
        -Source $source -Destination $destination -ManifestPath $manifest `
        -ApprovalReason 'test fixture' -IncludeExtension @('.txt') -ConfigPath $config
    $frozen = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($frozen.Excluded.Count -ne 1 -or $frozen.DirectoryCount -ne 1) {
        throw 'extension filtering or required-directory pruning is incorrect'
    }
    & (Join-Path $repo 'stages\02_ingest\invoke_verified_copy_manifest.ps1') `
        -ManifestPath $manifest -ReceiptPath $receipt -Execute -ConfigPath $config
    $result = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if ($result.Status -ne 'complete' -or $result.Files -ne 3 -or $result.SourceRetained -ne $true) {
        throw 'verified-copy receipt is incorrect'
    }
    foreach ($relative in @('one.txt', 'nested\two.txt', 'nested\one.txt')) {
        $a = (Get-FileHash -LiteralPath (Join-Path $source $relative) -Algorithm SHA256).Hash
        $b = (Get-FileHash -LiteralPath (Join-Path $destination $relative) -Algorithm SHA256).Hash
        if ($a -ne $b) { throw "copy hash mismatch: $relative" }
    }
    & (Join-Path $repo 'stages\02_ingest\invoke_verified_copy_manifest.ps1') `
        -ManifestPath $manifest -ReceiptPath $receipt -Execute -ConfigPath $config
    $retireManifest = Join-Path $audit 'retire.manifest.json'
    & (Join-Path $repo 'stages\07_structure\new_copy_retirement_manifest.ps1') `
        -CopyReceiptPath $receipt -CopyManifestPath $manifest `
        -QuarantineRoot (Join-Path $scratch 'quarantine') -ManifestPath $retireManifest `
        -ApprovalReason 'test retirement planning' -ConfigPath $config
    $retire = Get-Content -LiteralPath $retireManifest -Raw | ConvertFrom-Json
    if ($retire.MoveCount -ne 3) { throw 'verified-folder receipt did not produce a retirement manifest' }
    $retireDestinations = @($retire.Moves.Destination)
    if (-not ($retireDestinations -match 'quarantine\\one\.txt$') -or
        -not ($retireDestinations -match 'quarantine\\nested\\one\.txt$')) {
        throw 'retirement manifest flattened repeated leaf names instead of preserving relative provenance'
    }
    Write-Host 'PASS: verified folder copy is content-checked, resumable and source-preserving'
} finally {
    if (Test-Path -LiteralPath $scratch) {
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
}
