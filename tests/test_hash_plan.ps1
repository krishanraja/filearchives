Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'stages\04_inventory\build_inventory.ps1')
. (Join-Path $repo 'stages\02_ingest\build_hash_plan.ps1')
. (Join-Path $repo 'stages\02_ingest\compute_signatures.ps1')
. (Join-Path $repo 'stages\02_ingest\build_whole_hash_plan.ps1')
. (Join-Path $repo 'stages\02_ingest\compute_whole_hashes.ps1')
. (Join-Path $repo 'stages\02_ingest\analyze_duplicate_groups.ps1')

function Assert-True([bool] $Value, [string] $Message) {
    if (-not $Value) { throw "ASSERT TRUE FAILED: $Message" }
}

function Assert-Equal($Expected, $Actual, [string] $Message) {
    if ($Expected -ne $Actual) {
        throw "ASSERT EQUAL FAILED: $Message. expected=$Expected actual=$Actual"
    }
}

$testRoot = Join-Path 'C:\Users\krish\.scratch\filearchives-tests' `
    ([guid]::NewGuid().ToString('N'))
$marker = Join-Path $testRoot '.filearchives-test-fixture'
try {
    $source = Join-Path $testRoot 'source'
    $audit = Join-Path $testRoot 'audit'
    $protected = Join-Path $source 'protected'
    New-Item -ItemType Directory -Path $source, $protected, `
        (Join-Path $source 'node_modules'), (Join-Path $source '.git') -Force | Out-Null
    Set-Content -LiteralPath $marker -Value 'owned test fixture'
    [IO.File]::WriteAllBytes((Join-Path $source 'a.bin'), [byte[]](1, 2, 3, 4))
    [IO.File]::WriteAllBytes((Join-Path $source 'b.bin'), [byte[]](4, 3, 2, 1))
    $middleA = [byte[]]::new(131073)
    $middleB = [byte[]]::new(131073)
    $middleA[65536] = 1
    $middleB[65536] = 2
    [IO.File]::WriteAllBytes((Join-Path $source 'middle-a.bin'), $middleA)
    [IO.File]::WriteAllBytes((Join-Path $source 'middle-a-copy.bin'), $middleA)
    [IO.File]::WriteAllBytes((Join-Path $source 'middle-b.bin'), $middleB)
    [IO.File]::WriteAllBytes((Join-Path $source 'unique.bin'), [byte[]](1, 2, 3))
    [IO.File]::WriteAllBytes((Join-Path $source 'zero.bin'), [byte[]]@())
    [IO.File]::WriteAllBytes((Join-Path $source 'node_modules\generated.bin'),
        [byte[]](1, 2, 3, 4))
    [IO.File]::WriteAllBytes((Join-Path $source '.git\config'), [byte[]](1, 2, 3, 4))

    $config = Join-Path $testRoot 'workspace.json'
    @{
        schema_version = 2
        audit = $audit
        protected_roots = @($protected)
        protected_names = @()
        sources = @(@{
            id = 'fixture'
            path = $source
            kind = 'fixture'
            follow_reparse_points = $false
        })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $config -Encoding utf8

    $null = Invoke-FaInventory -WorkspacePath $config -InventorySourceId 'fixture' `
        -InventoryRunId 'hash-plan-test' -DirectoriesPerSegment 10 `
        -TotalItemBudget 1000 -PerDirectoryAttemptBudget 2
    $plan = Invoke-FaHashPlan -WorkspacePath $config -InventoryRunId 'hash-plan-test'
    Assert-Equal 5 $plan.CandidateFiles 'only meaningful same-size files enter plan'
    Assert-Equal 2 $plan.DistinctCandidateSizes 'two size collisions remain'
    Assert-True ($plan.ExcludedGeneratedFiles -ge 2) 'generated and Git files are excluded'
    Assert-Equal 1 $plan.ExcludedZeroByteFiles 'zero-byte marker is excluded'

    $rows = @(Get-Content -LiteralPath $plan.CandidateArtifact.Path |
        ForEach-Object { $_ | ConvertFrom-Json })
    $paths = @($rows | ForEach-Object RelativePath | Sort-Object)
    Assert-Equal 'a.bin' $paths[0] 'first candidate is retained'
    Assert-Equal 'b.bin' $paths[1] 'second candidate is retained'
    Assert-True ($plan.CandidateArtifact.Sha256 -match '^[0-9a-f]{64}$') `
        'candidate artifact is sealed'

    $first = Invoke-FaSignatures -WorkspacePath $config `
        -InventoryRunId 'hash-plan-test' -RowsPerBatch 1 -BatchLimit 1 `
        -TotalReadBudget 2000000
    Assert-Equal 'paused-batch-limit' $first.Status 'bounded signature pass pauses'
    $finished = Invoke-FaSignatures -WorkspacePath $config `
        -InventoryRunId 'hash-plan-test' -RowsPerBatch 1 -BatchLimit 0 `
        -TotalReadBudget 2000000
    $signatureRows = @(Get-ChildItem -LiteralPath (Join-Path $audit `
            'runs\hash-plan-test\dedupe\signatures\segments') -Filter '*.json' -File |
        Sort-Object Name | ForEach-Object {
            (Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json -Depth 16).Rows
        })
    if ($finished.Status -ne 'complete') {
        Write-Host ($signatureRows | ConvertTo-Json -Depth 8)
    }
    Assert-Equal 'complete' $finished.Status 'signature pass resumes to completion'
    Assert-Equal 5 $finished.SignedRows 'all candidates are signed'
    Assert-Equal 3 @($signatureRows | Select-Object -ExpandProperty Signature -Unique).Count `
        'signatures rule out different edges but retain equal-edge middle changes'

    $wholePlan = Invoke-FaWholeHashPlan -WorkspacePath $config `
        -InventoryRunId 'hash-plan-test'
    Assert-Equal 3 $wholePlan.CandidateRows `
        'only the quick-signature collision advances to whole hashing'
    Assert-Equal 1 $wholePlan.SignatureCollisionGroups `
        'one quick-signature collision group remains'
    $wholeFirst = Invoke-FaWholeHashes -WorkspacePath $config `
        -InventoryRunId 'hash-plan-test' -RowsPerBatch 1 -BatchLimit 1 `
        -TotalReadBudget 2000000
    Assert-Equal 'paused-batch-limit' $wholeFirst.Status `
        'bounded whole-hash pass pauses'
    $wholeFinished = Invoke-FaWholeHashes -WorkspacePath $config `
        -InventoryRunId 'hash-plan-test' -RowsPerBatch 1 -BatchLimit 0 `
        -TotalReadBudget 2000000
    Assert-Equal 'complete' $wholeFinished.Status `
        'whole-hash pass resumes to completion'
    $wholeRows = @(Get-ChildItem -LiteralPath (Join-Path $audit `
            'runs\hash-plan-test\dedupe\whole-hashes\segments') -Filter '*.json' -File |
        Sort-Object Name | ForEach-Object {
            (Get-Content -LiteralPath $_.FullName -Raw |
                ConvertFrom-Json -Depth 16 -DateKind String).Rows
        })
    Assert-Equal 2 @($wholeRows | Select-Object -ExpandProperty Sha256 -Unique).Count `
        'whole-file hashing rejects same-edge different-middle false duplicates'

    $evidence = Invoke-FaDuplicateAnalysis -WorkspacePath $config `
        -InventoryRunId 'hash-plan-test'
    Assert-Equal 1 $evidence.ExactDuplicateGroups `
        'only whole-file matches form a duplicate group'
    Assert-Equal 1 $evidence.RedundantCopies `
        'one byte-identical extra copy is evidenced'
    Assert-Equal 131073 $evidence.TheoreticalMaximumReclaimBytes `
        'reclaim is reported as theoretical until survivor policy exists'

    Write-Host 'PASS: three-tier duplicate proof is sealed, resumable, and content-safe'
} finally {
    if ((Test-Path -LiteralPath $marker) -and
        (Test-FaPathWithin -Path $testRoot -Root 'C:\Users\krish\.scratch\filearchives-tests')) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
