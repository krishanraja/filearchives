Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True([bool] $Value, [string] $Message) {
    if (-not $Value) { throw "ASSERT TRUE FAILED: $Message" }
}

$repo = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path 'C:\Users\krish\.scratch\filearchives-tests' ([guid]::NewGuid().ToString('N'))
$marker = Join-Path $testRoot '.filearchives-test-fixture'
try {
    $profile = Join-Path $testRoot 'profile'
    $documents = Join-Path $profile 'Documents'
    $downloads = Join-Path $profile 'Downloads'
    $audit = Join-Path $testRoot 'audit'
    $protected = Join-Path $testRoot 'protected'
    New-Item -ItemType Directory -Path $documents,$downloads,$audit,$protected -Force | Out-Null
    Set-Content -LiteralPath $marker -Value 'owned test fixture'
    $config = Join-Path $testRoot 'workspace.json'
    $report = Join-Path $testRoot 'coverage.json'
    $workspace = @{
        schema_version = 2
        audit = $audit
        protected_roots = @($protected)
        protected_names = @()
        sources = @(@{ id='documents'; path=$documents; kind='fixture'; follow_reparse_points=$false })
    }
    $workspace | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $config -Encoding utf8

    $failed = $false
    $failureMessage = $null
    try {
        & (Join-Path $repo 'stages\01_sources\test_windows_profile_coverage.ps1') `
            -ConfigPath $config -ProfileRoot $profile -ReportPath $report -FailOnUncovered
    } catch { $failed = $true; $failureMessage = $_.Exception.Message }
    Assert-True $failed 'an existing Downloads folder omitted from sources fails the gate'
    if (-not (Test-Path -LiteralPath $report)) { throw "coverage report was not written before failure: $failureMessage" }
    $first = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json -Depth 16
    Assert-True ($first.Uncovered.RelativePath -contains 'Downloads') 'report names Downloads as uncovered'

    $workspace.sources += @{ id='downloads'; path=$downloads; kind='fixture'; follow_reparse_points=$false }
    $workspace | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $config -Encoding utf8
    & (Join-Path $repo 'stages\01_sources\test_windows_profile_coverage.ps1') `
        -ConfigPath $config -ProfileRoot $profile -ReportPath $report -FailOnUncovered
    $second = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json -Depth 16
    Assert-True ($second.Status -eq 'pass') 'all existing known folders are covered'
    Write-Host 'PASS: Windows profile known-folder coverage is a completion gate'
} finally {
    if ((Test-Path -LiteralPath $marker) -and $testRoot.StartsWith('C:\Users\krish\.scratch\filearchives-tests\',[StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
