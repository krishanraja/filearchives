$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-atomic-tree-' + [guid]::NewGuid().ToString('n'))
$scope = Join-Path $scratch 'scope'
$source = Join-Path $scope 'source'
$destination = Join-Path $scratch 'quarantine\source'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
try {
    New-Item -ItemType Directory -Path (Join-Path $source 'nested\deep') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $source 'one.txt'), 'alpha')
    [IO.File]::WriteAllText((Join-Path $source 'nested\deep\two.txt'), 'beta')
    $workspace = [ordered]@{
        schema_version = 2; audit = $audit
        sources = @(@{ id='fixture'; path=$scope; kind='test'; follow_reparse_points=$false })
        protected_roots = @((Join-Path $scratch 'protected')); protected_names = @()
    }
    [IO.File]::WriteAllText($config, ($workspace | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    $manifest = Join-Path $audit 'manifest.json'; $receipt = Join-Path $audit 'receipt.json'
    & (Join-Path $repo 'stages\07_structure\new_atomic_tree_relocation_manifest.ps1') `
        -Source $source -Destination $destination -ManifestPath $manifest `
        -ApprovalReason 'test retained-tree quarantine' -ConfigPath $config
    & (Join-Path $repo 'stages\07_structure\invoke_atomic_tree_relocation_manifest.ps1') `
        -ManifestPath $manifest -ReceiptPath $receipt -Execute -ConfigPath $config
    if ((Test-Path -LiteralPath $source) -or
        (Get-Content -LiteralPath (Join-Path $destination 'nested\deep\two.txt') -Raw) -ne 'beta') {
        throw 'atomic tree relocation did not retain the nested tree exactly'
    }
    $result = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if ($result.Status -ne 'complete') { throw 'atomic tree relocation receipt is incomplete' }
    Write-Host 'PASS: large retained trees can be quarantined by verified same-volume rename'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
