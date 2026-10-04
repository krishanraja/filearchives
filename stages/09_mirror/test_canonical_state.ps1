[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $PolicyPath,
    [Parameter(Mandatory)][string] $ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
if (-not $ConfigPath) { $ConfigPath = Get-FaDefaultWorkspacePath }
if (-not $PolicyPath) { $PolicyPath = Join-Path $repo 'policy\estate-policy-v1.json' }
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json -Depth 64

function Get-TopLevelNames {
    param([Parameter(Mandatory)][string] $Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    # Deliberately non-recursive: this is safe even when a protected boundary is
    # a direct child of the root (notably H:\My Drive\ContentLibrary).
    return @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop | ForEach-Object Name)
}

function Get-MissingDirectories {
    param([string] $Root, [string[]] $Names)
    return @($Names | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $Root $_) -PathType Container)
    })
}

$hRoot = [string]$policy.destinations.business_current | Split-Path -Parent
$gPersonal = [string]$policy.destinations.personal
$gRoot = Split-Path -Parent $gPersonal
$cDev = 'C:\Users\krish\dev'
$requiredH = @('CURRENT', 'ARCHIVE', 'CONTENT-EXTRA', 'FAMILY-ADMIN', 'ContentLibrary')
$allowedH = @($requiredH + '00-START-HERE.md')
$hNames = Get-TopLevelNames -Root $hRoot
$gNames = Get-TopLevelNames -Root $gRoot
$cNames = Get-TopLevelNames -Root $cDev
$missingPersonal = Get-MissingDirectories -Root $gPersonal -Names @($policy.structure.personal)
$issues = [Collections.Generic.List[object]]::new()
foreach ($name in @(Get-MissingDirectories -Root $hRoot -Names $requiredH)) {
    $issues.Add([pscustomobject]@{ Code='missing-h-root'; Path=(Join-Path $hRoot $name) })
}
foreach ($name in @($hNames | Where-Object { $allowedH -notcontains $_ })) {
    $issues.Add([pscustomobject]@{ Code='unexpected-h-root'; Path=(Join-Path $hRoot $name) })
}
foreach ($name in $missingPersonal) {
    $issues.Add([pscustomobject]@{ Code='missing-g-personal-category'; Path=(Join-Path $gPersonal $name) })
}
foreach ($name in @($gNames | Where-Object { $_ -notin @('Personal', '_BUSINESS-NATIVE-OWNERSHIP') })) {
    $issues.Add([pscustomobject]@{ Code='unexpected-g-root'; Path=(Join-Path $gRoot $name) })
}
foreach ($name in @($cNames | Where-Object { $_ -notin @('krishanraja', 'README-CANONICAL.md') })) {
    $issues.Add([pscustomobject]@{ Code='unexpected-c-dev-root'; Path=(Join-Path $cDev $name) })
}
if (-not (Test-Path -LiteralPath 'C:\Users\krish\dev\krishanraja\mm-ctrl' -PathType Container)) {
    $issues.Add([pscustomobject]@{ Code='critical-mm-ctrl-missing'; Path='C:\Users\krish\dev\krishanraja\mm-ctrl' })
}
$report = [ordered]@{
    SchemaVersion = 1
    Kind = 'canonical-state-report-v1'
    Status = if ($issues.Count -eq 0) { 'pass' } else { 'issues' }
    Issues = @($issues)
    HTopLevel = $hNames
    GTopLevel = $gNames
    CDevTopLevel = $cNames
    ProtectedBoundaryCheckedByExistenceOnly = @($workspace.ProtectedRoots)
    ProtectedBoundaryTraversalPerformed = $false
    CheckedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReportPath -Value $report -Depth 12
Write-Host ("canonical state: {0}; issues={1}; report={2}" -f $report.Status, $issues.Count, $ReportPath)
if ($issues.Count -gt 0) { exit 2 }
