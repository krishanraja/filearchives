$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-family-test-' + [guid]::NewGuid().ToString('n'))
$scope = Join-Path $scratch 'scope'
$current = Join-Path $scope 'CURRENT'
$archive = Join-Path $scope 'ARCHIVE\05_CANONICAL-OLD-VERSIONS'
$quarantine = Join-Path $scope 'ARCHIVE\99_DELETE-QUARANTINE\Temporary-Families'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
$manifest = Join-Path $audit 'manifest.json'
$receipt = Join-Path $audit 'receipt.json'
try {
    New-Item -ItemType Directory -Path $current,$archive,$audit -Force | Out-Null
    $old = Join-Path $current 'Agent Instructions (1).md'
    $new = Join-Path $current 'Agent Instructions FINAL.md'
    $theoryA = Join-Path $current 'Business Theory Corpus (1).md'
    $theoryB = Join-Path $current 'Business Theory Corpus FINAL.md'
    [IO.File]::WriteAllText($old, 'old instructions')
    [IO.File]::WriteAllText($new, 'new instructions')
    [IO.File]::WriteAllText($theoryA, 'old theory')
    [IO.File]::WriteAllText($theoryB, 'new theory')
    (Get-Item $old).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-2)
    (Get-Item $new).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-1)
    $workspace = [ordered]@{
        schema_version = 2
        audit = $audit
        sources = @(@{ id='fixture'; path=$scope; kind='test'; follow_reparse_points=$false })
        protected_roots = @((Join-Path $scratch 'protected'))
        protected_names = @()
    }
    [IO.File]::WriteAllText($config, ($workspace | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    & (Join-Path $repo 'stages\07_structure\new_temporary_family_consolidation_manifest.ps1') `
        -SearchRoot $current -ArchiveRoot $archive -QuarantineRoot $quarantine `
        -ManifestPath $manifest -ApprovalReason 'test fixture' -ConfigPath $config
    $frozen = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ($frozen.FamilyCount -ne 1 -or $frozen.MoveCount -ne 2) { throw 'expected one two-member temporary family' }
    if (@($frozen.Moves | Where-Object Source -match 'Theory Corpus').Count -ne 0) {
        throw 'evergreen theory/corpus entered temporary-family consolidation'
    }
    & (Join-Path $repo 'stages\07_structure\invoke_live_file_move_manifest.ps1') `
        -ManifestPath $manifest -ReceiptPath $receipt -Execute -ConfigPath $config
    if (-not (Test-Path -LiteralPath (Join-Path $archive 'Temporary-Family-Keepers\Agent Instructions FINAL.md'))) {
        throw 'newest temporary family representative was not archived'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $quarantine 'agent-instructions\Agent Instructions (1).md'))) {
        throw 'superseded temporary family member was not quarantined'
    }
    if (-not (Test-Path -LiteralPath $theoryA) -or -not (Test-Path -LiteralPath $theoryB)) {
        throw 'evergreen theory/corpus was moved'
    }
    Write-Host 'PASS: temporary AI document families keep newest and quarantine older variants'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
