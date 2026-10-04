$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-repo-test-' + [guid]::NewGuid().ToString('n'))
$sourceRoot = Join-Path $scratch 'source-root'
$source = Join-Path $sourceRoot 'repo'
$destination = Join-Path $scratch 'destination-root\repo-snapshot'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
$receipt = Join-Path $audit 'snapshot.receipt.json'
try {
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    & git -C $source init --quiet -b main
    & git -C $source config user.email 'fixture@example.invalid'
    & git -C $source config user.name 'Fixture'
    [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'before')
    [IO.File]::WriteAllText((Join-Path $source 'deleted.txt'), 'delete me')
    & git -C $source add .
    & git -C $source commit --quiet -m initial
    & git -C $source remote add origin 'https://example.invalid/fixture/repo.git'
    [IO.File]::WriteAllText((Join-Path $source 'modified.txt'), 'after')
    Remove-Item -LiteralPath (Join-Path $source 'deleted.txt')
    [IO.File]::WriteAllText((Join-Path $source 'untracked.txt'), 'unique')
    & git -C $source add modified.txt
    $workspace = [ordered]@{
        schema_version = 2
        audit = $audit
        sources = @(@{ id='fixture'; path=$sourceRoot; kind='test'; follow_reparse_points=$false })
        protected_roots = @((Join-Path $scratch 'protected'))
        protected_names = @()
    }
    New-Item -ItemType Directory -Path $audit -Force | Out-Null
    [IO.File]::WriteAllText($config, ($workspace | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    & (Join-Path $repo 'stages\02_ingest\snapshot_dirty_repository.ps1') `
        -SourceRepository $source -DestinationRepository $destination `
        -ReceiptPath $receipt -ApprovalReason 'test fixture' -ConfigPath $config
    $result = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    if ($result.Status -ne 'complete' -or $result.SourceRetained -ne $true) {
        throw 'repository snapshot receipt is incorrect'
    }
    $expectedHead = (& git -C $source rev-parse HEAD).Trim()
    if ($result.Head -ne $expectedHead -or $result.Head.Length -ne 40) {
        throw 'repository snapshot receipt truncated the Git HEAD'
    }
    $a = @(& git -C $source status --porcelain=v1 --untracked-files=all)
    $b = @(& git -C $destination status --porcelain=v1 --untracked-files=all)
    if ([string]::Join("`n", $a) -ne [string]::Join("`n", $b)) {
        throw 'fixture snapshot status differs'
    }
    if ($result.StatusEquivalent -ne $true) {
        throw 'repository snapshot did not prove final status equivalence'
    }
    $sourceIndexEntries = @(& git -C $source ls-files --stage)
    $destinationIndexEntries = @(& git -C $destination ls-files --stage)
    if ([string]::Join("`n", $sourceIndexEntries) -ne [string]::Join("`n", $destinationIndexEntries) -or
        $result.IndexSemanticEquivalent -ne $true -or
        $result.IndexEntries -ne $sourceIndexEntries.Count) {
        throw 'repository snapshot did not prove semantic index equivalence'
    }
    Write-Host 'PASS: dirty repository snapshot preserves HEAD, index and working state'
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
