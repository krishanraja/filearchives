Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'stages\01_sources\survey_roots.ps1')

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
    $protected = Join-Path $source 'ContentLibrary'
    $normal = Join-Path $source 'normal\sub'
    $empty = Join-Path $source 'empty'
    New-Item -ItemType Directory -Path $protected, $normal, $empty -Force | Out-Null
    Set-Content -LiteralPath $marker -Value 'owned test fixture'
    Set-Content -LiteralPath (Join-Path $source 'a.txt') -Value 'alpha'
    Set-Content -LiteralPath (Join-Path $normal 'b.bin') -Value 'beta'
    Set-Content -LiteralPath (Join-Path $protected 'must-not-be-seen.txt') -Value 'secret fixture'

    $config = Join-Path $testRoot 'workspace.json'
    @{
        schema_version = 2
        audit = $audit
        current = (Join-Path $testRoot 'current')
        archive = (Join-Path $testRoot 'archive')
        protected_roots = @($protected)
        protected_names = @('ContentLibrary')
        sources = @(@{
            id = 'fixture'
            path = $source
            kind = 'filesystem'
            follow_reparse_points = $false
        })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $config -Encoding utf8

    $workspace = Import-FaWorkspace -ConfigPath $config
    Assert-True (Test-FaPathWithin -Path (Join-Path $source 'child') -Root $source) 'child path is within root'
    Assert-True (-not (Test-FaPathWithin -Path ($source + '-other') -Root $source)) 'prefix collision is outside root'
    Assert-True (Test-FaProtectedPath -Path $protected -Workspace $workspace) 'protected root is protected'
    Assert-True (Test-FaProtectedPath -Path (Join-Path $protected 'x') -Workspace $workspace) 'protected descendant is protected'

    $refused = $false
    try { Assert-FaNotProtected -Path $protected -Workspace $workspace } catch { $refused = $true }
    Assert-True $refused 'protected access is refused'

    $result = Invoke-FaSourceSurvey -Workspace $workspace -Source $workspace.Sources[0]
    Assert-Equal 'complete' $result.Status 'fixture survey completes'
    Assert-Equal 2 $result.Files 'protected file is not counted'
    Assert-Equal 3 $result.Directories 'protected directory is not counted'
    Assert-Equal 1 $result.EmptyDirectories 'empty directory is counted'
    Assert-Equal 1 $result.ProtectedEntriesSkipped 'protected directory is skipped once'
    Assert-Equal 0 $result.UnreadableDirectories 'fixture has no unreadable directory'

    $serialized = $result | ConvertTo-Json -Depth 12 -Compress
    Assert-True (-not $serialized.Contains('must-not-be-seen')) 'protected child name never enters result'

    $missingSource = [pscustomobject]@{
        Id = 'missing'
        Path = Join-Path $testRoot 'not-mounted'
        Kind = 'peer'
        FollowReparsePoints = $false
    }
    $missingResult = Invoke-FaSourceSurvey -Workspace $workspace -Source $missingSource
    Assert-Equal 'unavailable' $missingResult.Status 'missing source is explicit'
    Assert-Equal $null $missingResult.Files 'missing source is not reported as zero files'

    Write-Host 'PASS: PowerShell workspace and protected-root survey guards'
} finally {
    if ((Test-Path -LiteralPath $marker) -and
        (Test-FaPathWithin -Path $testRoot -Root 'C:\Users\krish\.scratch\filearchives-tests')) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
