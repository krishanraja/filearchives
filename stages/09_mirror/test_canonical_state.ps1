[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $CDevRoot = 'C:\Users\krish\dev',
    [Parameter(Mandatory)][string] $ReportPath
)

<#
    Check the top of every watched drive against Krish's folder record, the
    authority for where things live since 2026-10-23. Deliberately shallow: a
    never-enter boundary is checked for existence only.

    issues (exit 2):  a recorded top-level folder is missing, a never-enter
                      boundary is missing, a loose file sits at the top of a
                      drive, or the critical mm-ctrl worktree is gone
    not issues:       a top-level folder the record does not know; it is new,
                      waiting on Krish, and is reported and left in place
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards' 'workspace.ps1')
. (Join-Path $repo 'guards' 'atomic.ps1')
. (Join-Path $repo 'guards' 'folder_consent.ps1')
if (-not $ConfigPath) { $ConfigPath = Get-FaDefaultWorkspacePath }
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$prefs = Import-FaFolderPreferences
if (-not $prefs.Recorded) { throw 'Krish has not recorded his folders; there is nothing to check against' }

$issues = [Collections.Generic.List[object]]::new()
$waitingOnKrish = [Collections.Generic.List[string]]::new()
$unavailable = [Collections.Generic.List[string]]::new()
$topLevel = [ordered]@{}
foreach ($root in $prefs.WatchRoots) {
    if (-not (Test-Path -LiteralPath $root.Path -PathType Container)) {
        $unavailable.Add($root.Path)
        continue
    }
    $children = @(Get-ChildItem -LiteralPath $root.Path -Force -ErrorAction Stop)
    $topLevel[$root.Path] = @($children | ForEach-Object Name)
    foreach ($child in $children) {
        if ($child.PSIsContainer) {
            if (@($prefs.SkipNames) -contains $child.Name) { continue }
            if ((Get-FaFolderStatus -Path $child.FullName -Preferences $prefs) -ne 'known') {
                $waitingOnKrish.Add((ConvertTo-FaCanonicalPath $child.FullName))
            }
        } elseif (@($prefs.Data.root_files_allowed) -notcontains $child.Name) {
            $issues.Add([pscustomobject]@{ Code = 'loose-root-file'; Path = $child.FullName })
        }
    }
    foreach ($entry in @($prefs.Data.folders)) {
        $path = ConvertTo-FaCanonicalPath ([string]$entry.path)
        if ([string]$entry.status -notin @('known', 'answered')) { continue }
        if (-not (Test-FaPathWithin -Path $path -Root $root.Path)) { continue }
        if ((Get-FaRelativeDepth -Path $path -Root $root.Path) -ne 1) { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            $issues.Add([pscustomobject]@{ Code = 'missing-recorded-root'; Path = $path })
        }
    }
}
foreach ($boundary in $prefs.NeverEnter) {
    $root = Get-FaWatchRoot -Path $boundary -Preferences $prefs
    if ($root -and $unavailable -contains $root.Path) { continue }
    $recorded = $prefs.ByPath.ContainsKey($boundary)
    if ($recorded -and -not (Test-Path -LiteralPath $boundary -PathType Container)) {
        $issues.Add([pscustomobject]@{ Code = 'missing-protected-boundary'; Path = $boundary })
    }
}
$mmCtrl = Join-Path $CDevRoot 'krishanraja' 'mm-ctrl'
if (-not (Test-Path -LiteralPath $mmCtrl -PathType Container)) {
    $issues.Add([pscustomobject]@{ Code = 'critical-mm-ctrl-missing'; Path = $mmCtrl })
}
$report = [ordered]@{
    SchemaVersion = 2
    Kind = 'canonical-state-report-v2'
    Authority = $prefs.Path
    RecordedAt = [string]$prefs.Data.recorded_at
    Status = if ($issues.Count -eq 0) { 'pass' } else { 'issues' }
    Issues = @($issues)
    NewFoldersWaitingOnKrish = @($waitingOnKrish)
    RootsNotMounted = @($unavailable)
    TopLevel = $topLevel
    ProtectedBoundaryCheckedByExistenceOnly = @($workspace.ProtectedRoots)
    ProtectedBoundaryTraversalPerformed = $false
    CheckedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReportPath -Value $report -Depth 12
Write-Host ("canonical state: {0}; issues={1}; new folders waiting on Krish={2} (left in place); report={3}" -f
    $report.Status, $issues.Count, $waitingOnKrish.Count, $ReportPath)
if ($issues.Count -gt 0) { exit 2 }
