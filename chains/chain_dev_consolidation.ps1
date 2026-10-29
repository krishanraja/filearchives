<#
    Bring a venture's clones home, only with Krish's yes for each folder
    (Wave 3 W3.4). Ruling (Krish, 2026-10-23): filearchives never moves a
    folder Krish made without asking first.

        pwsh -NoProfile -File chains\chain_dev_consolidation.ps1            # plan only
        pwsh -NoProfile -File chains\chain_dev_consolidation.ps1 -Execute   # moves what he said yes to

    1. Reads the dev sprawl report fresh (stages\05_classify\report_dev_sprawl.ps1).
    2. Writes docs/folder-checkin/move-requests.json: one consent row per
       proposed move, ready for Krish to approve, and whether he already has.
       Without -Execute it stops here. Nothing moves.
    3. With -Execute, and only when at least one proposed move has his consent
       row for that exact folder and destination:
         a. snapshots EVERY dirty repository under dev first, with
            stages\02_ingest\snapshot_dirty_repository.ps1, outside dev;
         b. seals each preserved path (Growth's .scratch) before the move;
         c. moves the folder with the existing guarded pair,
            new_folder_move_manifest.ps1 then invoke_verified_folder_move.ps1,
            which refuse it again without his consent row;
         d. proves each preserved path arrived byte for byte;
         e. re-reads the sprawl report, so the number is measured, not assumed.
       A linked worktree, or a clone with linked worktrees, is never moved as
       a folder: Git would lose track of it.
#>
[CmdletBinding()]
param(
    [string] $DevRoot,
    [string] $VenturesPath,
    [string] $ReportRoot,
    [string] $SnapshotRoot,
    [string] $AuditRoot,
    [string] $ConfigPath,
    [switch] $Execute,
    [datetimeoffset] $AsOf = [DateTimeOffset]::Now
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'guards' 'workspace.ps1')
. (Join-Path $repo 'guards' 'atomic.ps1')
. (Join-Path $repo 'guards' 'folder_consent.ps1')
if (-not $ReportRoot) { $ReportRoot = Join-Path $repo 'docs' 'folder-checkin' }
$stamp = $AsOf.ToString('yyyyMMdd-HHmmss')
$report = Join-Path $repo 'stages' '05_classify' 'report_dev_sprawl.ps1'
$reportArgs = @{ ReportRoot = $ReportRoot; AsOf = $AsOf }
if ($DevRoot) { $reportArgs.DevRoot = $DevRoot }
if ($VenturesPath) { $reportArgs.VenturesPath = $VenturesPath }

function Get-FaTreeSeal {
    param([Parameter(Mandatory)][string] $Root)
    $base = ConvertTo-FaCanonicalPath $Root
    if (-not (Test-Path -LiteralPath $base)) { return 'absent' }
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { return "F|$(Get-FaSha256 -Path $base)" }
    $rows = @(Get-ChildItem -LiteralPath $base -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($base.Length).Replace('\', '/')
        if ($_.PSIsContainer) { "D|$rel" } else { "F|$rel|$($_.Length)|$(Get-FaSha256 -Path $_.FullName)" }
    })
    return [string]::Join("`n", $rows)
}

& $report @reportArgs | Out-Host
$sprawl = Get-Content -LiteralPath (Join-Path $ReportRoot 'sprawl.json') -Raw | ConvertFrom-Json -Depth 16
$prefs = Import-FaFolderPreferences

# ---- the requests ----------------------------------------------------------
$requests = @(@($sprawl.Trees) | Where-Object { $_.ProposedDestination } | ForEach-Object {
    $yes = Test-FaKrishConsent -Path ([string]$_.Path) -Action 'move' -Destination ([string]$_.ProposedDestination) -Preferences $prefs
    [pscustomobject][ordered]@{
        consent_row = [ordered]@{
            path = [string]$_.Path; action = 'move'; destination = [string]$_.ProposedDestination
            approved_by = $null; approved_at = $null; words = $null
            what = ('{0} clone, {1}: {2} uncommitted, {3} commits on no remote' -f $_.Venture, $_.Repository, $_.DirtyEntries, $_.NotOnAnyRemote)
        }
        approved = $yes
        dirty = [bool]($_.DirtyEntries -gt 0)
        preserved = @($_.Preserved | ForEach-Object { [string]$_.Path })
    }
})
Write-FaAtomicJson -Path (Join-Path $ReportRoot 'move-requests.json') -Value ([ordered]@{
    SchemaVersion = 1; Kind = 'dev-move-requests-v1'; ObservedAt = $AsOf.ToString('o')
    Note = 'Each consent_row is unapproved until Krish copies it into policy/folder-preferences.json consents with approved_by "Krish", approved_at and his words.'
    Requests = $requests
}) -Depth 8
$approved = @($requests | Where-Object approved)
Write-Host ("move requests: {0} proposed, {1} with Krish's yes" -f $requests.Count, $approved.Count)

if (-not $Execute) {
    Write-Host 'Plan only. Nothing was moved, renamed or deleted.'
    return
}
if ($approved.Count -eq 0) {
    Write-Host "STOPPED: no proposed move has Krish's consent row. Nothing was moved."
    return
}
if (-not $SnapshotRoot) { $SnapshotRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.scratch' 'filearchives-dev-snapshots' $stamp }
if (-not $AuditRoot) { $AuditRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.scratch' 'filearchives-dev-moves' $stamp }
$devRootPath = ConvertTo-FaCanonicalPath ([string]$sprawl.DevRoot)
foreach ($p in @($SnapshotRoot, $AuditRoot)) {
    if (Test-FaPathWithin -Path $p -Root $devRootPath) { throw "REFUSED: $p is inside the dev folder being tidied" }
}

# ---- a. snapshot every dirty repository first ------------------------------
$snapshots = [Collections.Generic.List[object]]::new()
$i = 0
foreach ($t in @(@($sprawl.Trees) | Where-Object { $_.DirtyEntries -gt 0 })) {
    $i++
    $name = '{0:D3}-{1}' -f $i, (Split-Path -Leaf ([string]$t.Path))
    $receipt = Join-Path $AuditRoot 'snapshots' ($name + '.json')
    & (Join-Path $repo 'stages' '02_ingest' 'snapshot_dirty_repository.ps1') -SourceRepository ([string]$t.Path) `
        -DestinationRepository (Join-Path $SnapshotRoot $name) -ReceiptPath $receipt `
        -ApprovalReason 'W3.4: snapshot every dirty repository before any dev move' -ConfigPath $ConfigPath | Out-Host
    $snapshots.Add([pscustomobject]@{ Source = [string]$t.Path; Snapshot = (Join-Path $SnapshotRoot $name); Receipt = $receipt })
}

# ---- b to d. move what he said yes to --------------------------------------
$moves = [Collections.Generic.List[object]]::new()
foreach ($req in $approved) {
    $row = $req.consent_row
    $tree = @(@($sprawl.Trees) | Where-Object { ([string]$_.Path).Equals($row.path, [StringComparison]::OrdinalIgnoreCase) })[0]
    if ($tree.Kind -ne 'clone' -or $tree.LinkedWorktrees -gt 0) {
        throw "REFUSED: $($row.path) is a linked worktree or has linked worktrees; move those with git worktree move"
    }
    $seals = @{}
    foreach ($kept in $req.preserved) { $seals[$kept] = Get-FaTreeSeal (Join-Path $row.path $kept) }
    $name = '{0}' -f (Split-Path -Leaf $row.path)
    $manifest = Join-Path $AuditRoot 'moves' ($name + '-' + $moves.Count + '.manifest.json')
    $receipt = Join-Path $AuditRoot 'moves' ($name + '-' + $moves.Count + '.receipt.json')
    & (Join-Path $repo 'stages' '07_structure' 'new_folder_move_manifest.ps1') -Source $row.path -Destination $row.destination `
        -ManifestPath $manifest -ApprovalReason 'Krish said yes for this folder (consent row in policy/folder-preferences.json)' `
        -ConfigPath $ConfigPath | Out-Host
    & (Join-Path $repo 'stages' '07_structure' 'invoke_verified_folder_move.ps1') -ManifestPath $manifest `
        -ReceiptPath $receipt -Execute -ConfigPath $ConfigPath | Out-Host
    foreach ($kept in $req.preserved) {
        if ((Get-FaTreeSeal (Join-Path $row.destination $kept)) -ne $seals[$kept]) {
            throw "preserved path $kept did not arrive byte for byte at $($row.destination)"
        }
    }
    $moves.Add([pscustomobject]@{ Source = $row.path; Destination = $row.destination; Receipt = $receipt; Preserved = @($req.preserved) })
}

# ---- e. measure again ------------------------------------------------------
& $report @reportArgs | Out-Host
$after = Get-Content -LiteralPath (Join-Path $ReportRoot 'sprawl.json') -Raw | ConvertFrom-Json -Depth 16
Write-FaAtomicJson -Path (Join-Path $AuditRoot 'consolidation-receipt.json') -Value ([ordered]@{
    SchemaVersion = 1; Kind = 'dev-consolidation-receipt-v1'; CompletedAt = [DateTimeOffset]::Now.ToString('o')
    Snapshots = @($snapshots); Moves = @($moves)
    MakeYourMindUpClonesOutsideHomeBefore = $sprawl.MakeYourMindUpClonesOutsideHome
    MakeYourMindUpClonesOutsideHomeAfter = $after.MakeYourMindUpClonesOutsideHome
}) -Depth 8
Write-Host ("moved {0} folder(s) after {1} snapshot(s); Make Your Mind Up clones outside home: {2} -> {3}" -f
    $moves.Count, $snapshots.Count, $sprawl.MakeYourMindUpClonesOutsideHome, $after.MakeYourMindUpClonesOutsideHome)
