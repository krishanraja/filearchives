Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'stages\04_inventory\build_inventory.ps1')
. (Join-Path $repo 'stages\04_inventory\verify_inventory.ps1')

function Assert-True([bool] $Value, [string] $Message) {
    if (-not $Value) { throw "ASSERT TRUE FAILED: $Message" }
}

function Assert-Equal($Expected, $Actual, [string] $Message) {
    if ($Expected -ne $Actual) {
        throw "ASSERT EQUAL FAILED: $Message. expected=$Expected actual=$Actual"
    }
}

$testRoot = Join-Path 'C:\Users\krish\.scratch\filearchives-tests' ([guid]::NewGuid().ToString('N'))
$marker = Join-Path $testRoot '.filearchives-test-fixture'
try {
    $source = Join-Path $testRoot 'source'
    $audit = Join-Path $testRoot 'audit'
    $protected = Join-Path $source 'protected'
    $nested = Join-Path $source 'work\nested'
    $empty = Join-Path $source 'empty'
    New-Item -ItemType Directory -Path $protected, $nested, $empty -Force | Out-Null
    Set-Content -LiteralPath $marker -Value 'owned test fixture'
    Set-Content -LiteralPath (Join-Path $source 'root.txt') -Value 'root'
    Set-Content -LiteralPath (Join-Path $nested 'clip.mp4') -Value 'video fixture'
    Set-Content -LiteralPath (Join-Path $protected 'must-not-be-seen.txt') -Value 'protected fixture'

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

    $first = Invoke-FaInventory -WorkspacePath $config -InventorySourceId 'fixture' `
        -InventoryRunId 'resume-test' -DirectoriesPerSegment 1 -SegmentLimit 1 `
        -TotalItemBudget 1000 -PerDirectoryAttemptBudget 2
    Assert-Equal 'paused-segment-limit' $first.Status 'first bounded pass pauses'
    Assert-Equal 1 $first.Segments 'first pass commits one segment'

    $second = Invoke-FaInventory -WorkspacePath $config -InventorySourceId 'fixture' `
        -InventoryRunId 'resume-test' -DirectoriesPerSegment 1 -SegmentLimit 0 `
        -TotalItemBudget 1000 -PerDirectoryAttemptBudget 2
    Assert-Equal 'complete' $second.Status 'resume reaches completion'
    Assert-Equal 0 $second.TerminalDirectoryErrors 'fixture has no terminal errors'

    $segmentsPath = Join-Path $audit 'runs\resume-test\inventory\fixture\segments'
    $segments = @(Get-ChildItem -LiteralPath $segmentsPath -Filter 'segment-*.json' -File |
        Sort-Object Name | ForEach-Object {
            Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json -Depth 32
        })
    $items = @($segments | ForEach-Object { $_.Items })
    $paths = @($items | ForEach-Object { $_.RelativePath })
    Assert-Equal $paths.Count @($paths | Sort-Object -Unique).Count 'resume emits no duplicate item rows'
    Assert-True ($paths -contains 'root.txt') 'root file is inventoried'
    Assert-True ($paths -contains 'work\nested\clip.mp4') 'nested media is inventoried'
    Assert-True (-not (($paths -join '|').Contains('must-not-be-seen'))) 'protected child never enters inventory'

    $clip = $items | Where-Object RelativePath -eq 'work\nested\clip.mp4' | Select-Object -First 1
    Assert-Equal 'video' $clip.MediaKind 'media kind is recorded'
    $emptyRecord = $segments.ProcessedDirectories |
        Where-Object RelativePath -eq 'empty' | Select-Object -First 1
    Assert-True ([bool]$emptyRecord.IsEmpty) 'empty directory is proven by enumeration'

    $summaryPath = Join-Path $audit 'runs\resume-test\inventory\fixture\inventory-summary.json'
    Assert-True (Test-Path -LiteralPath $summaryPath) 'completion summary exists'
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -Depth 16
    Assert-Equal $segments.Count $summary.Segments.Count 'summary seals every segment'
    Assert-True ($summary.Segments[0].Sha256 -match '^[0-9a-f]{64}$') 'segment digest is recorded'

    $verification = Test-FaInventory -WorkspacePath $config `
        -InventorySourceId 'fixture' -InventoryRunId 'resume-test' -LiveReconciliation
    Assert-Equal 'pass' $verification.Status 'independent live verification passes'
    Assert-Equal $summary.Items $verification.Structural.UniquePaths `
        'verification proves every inventory path is unique'

    Set-Content -LiteralPath (Join-Path $source 'late-arrival.txt') -Value 'drift'
    $drift = Test-FaInventory -WorkspacePath $config `
        -InventorySourceId 'fixture' -InventoryRunId 'resume-test' -LiveReconciliation
    Assert-Equal 'fail' $drift.Status 'live source drift is detected'
    Assert-True ($drift.Failures -contains `
        'live filesystem identity differs from committed inventory') 'drift reason is explicit'

    $driveRoot = [IO.Path]::GetPathRoot($source)
    $drivePrefix = if ($driveRoot.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $driveRoot
    } else { $driveRoot + [IO.Path]::DirectorySeparatorChar }
    Assert-True ($source.StartsWith($drivePrefix, [StringComparison]::OrdinalIgnoreCase)) `
        'drive-root boundary uses exactly one separator'

    Write-Host 'PASS: resumable inventory and independent verification are protected-root-safe'
} finally {
    if ((Test-Path -LiteralPath $marker) -and
        (Test-FaPathWithin -Path $testRoot -Root 'C:\Users\krish\.scratch\filearchives-tests')) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
