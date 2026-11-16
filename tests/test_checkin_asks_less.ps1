# Ruling (Krish, 2026-11-16): the weekly check-in asks only what it cannot work
# out, never the same thing twice, and counts a move an AI session made on his
# instruction as his. His words: "These pop-ups are becoming redundant and
# annoying and don't really consider what the job of this repository is."
#
# This replays what happened to his Immigration folders, on a fixture drive, and
# counts every pop-up:
#   week 1  a Claude session builds "1 Home & Personal\Immigration\00_..14_" at the
#           top of the drive: one question per new top-level folder, none for
#           anything inside a folder he already has;
#   week 2  the session moves that tree into Immigration and renames "Visa & E3"
#           to "Old E3": one "did you OK these?" pop-up, and no question about
#           the moved folders in their new place (10_passports_and_identity);
#           an ambiguous name is never linked as a move;
#   week 3  a folder he has is truly gone and he says No: asked once, counted;
#   week 4  nothing changed: no pop-up at all.
# A worked-out folder is still guarded as waiting on him. Nothing moves.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$structure = Join-Path $repo 'stages' '07_structure'
. (Join-Path $repo 'guards' 'workspace.ps1')
. (Join-Path $repo 'guards' 'atomic.ps1')
. (Join-Path $repo 'guards' 'folder_consent.ps1')
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-asks-less-' + [guid]::NewGuid().ToString('n'))
$drive = Join-Path $scratch 'My Drive'
$prefsPath = Join-Path $scratch 'folder-preferences.json'
$reportRoot = Join-Path $scratch 'folder-checkin'
$nowPath = Join-Path $scratch 'NOW.md'
$savedPrefsEnv = $env:FILEARCHIVES_FOLDER_PREFERENCES

function D([string] $Rel) { ConvertTo-FaCanonicalPath (Join-Path $drive $Rel) }
function Get-Entry([string] $Path) {
    @((Get-Content -LiteralPath $prefsPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String).folders |
        Where-Object { $_.path -eq $Path }) | Select-Object -First 1
}
function Get-Field($Entry, [string] $Name) { if ($Entry -and $null -ne $Entry.PSObject.Properties[$Name]) { $Entry.$Name } else { $null } }
function New-Folders([string[]] $Rel) { foreach ($r in $Rel) { New-Item -ItemType Directory -Path (D $r) -Force | Out-Null } }

# Krish, played by the test: each pop-up is logged with its kind and text, and
# answered from the replies queued for that kind.
$popups = [Collections.Generic.List[object]]::new()
$replies = @{}
$krish = {
    param([string] $Kind, [string] $Text, [string] $Default)
    $popups.Add([pscustomobject]@{ Kind = $Kind; Text = $Text; Default = $Default })
    $queue = $replies[$Kind]
    if (-not $queue -or $queue.Count -eq 0) { throw "an unexpected pop-up ($Kind): $Text" }
    return $queue.Dequeue()
}.GetNewClosure()
function Set-Replies([hashtable] $Plan) {
    $replies.Clear()
    foreach ($k in $Plan.Keys) { $replies[$k] = [Collections.Generic.Queue[string]]::new([string[]]@($Plan[$k])) }
}
function Invoke-Week([hashtable] $Plan) {
    $popups.Clear()
    Set-Replies $Plan
    & (Join-Path $structure 'weekly_folder_checkin.ps1') -ReportRoot $reportRoot -NowPath $nowPath -Ask $krish | Out-Host
    foreach ($k in $replies.Keys) { if ($replies[$k].Count -gt 0) { throw "an expected pop-up ($k) never came" } }
    return @(Get-Content -LiteralPath (Join-Path $reportRoot 'LOG.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })[-1]
}

try {
    New-Folders @('Immigration/Visa & E3/_IMM_TMP2', 'Family Admin/Krish/Archive', 'Inbox from My AI')
    $seed = Get-Content -LiteralPath (Join-Path $repo 'policy' 'folder-preferences.json') -Raw | ConvertFrom-Json -Depth 16
    $seed.watch_roots = @(@{ path = $drive; max_depth = 4 })
    $seed.never_enter = @(); $seed.folders = @(); $seed.consents = @(); $seed.recorded_at = $null
    [IO.File]::WriteAllText($prefsPath, ($seed | ConvertTo-Json -Depth 16))
    $env:FILEARCHIVES_FOLDER_PREFERENCES = $prefsPath
    [IO.File]::WriteAllText($nowPath, "## Where it is right now`n`n<!-- north-star-state {`"week_of`": `"2026-11-16`", `"week_target`": 0, `"current`": null, `"current_as_of`": null, `"current_source`": null, `"urgency`": 1} --> **North Star number**`n")
    & (Join-Path $structure 'record_folder_preferences.ps1') | Out-Host

    # ---- week 1: a session builds a new tree at the top of the drive -----------
    New-Folders @('1 Home & Personal/Immigration/00_UPLOAD_PACK', '1 Home & Personal/Immigration/10_passports_and_identity',
        '1 Home & Personal/Immigration/14_spouse_e3_details/scans', 'Music Production', 'Family Admin/Krish/DS160 - Final')
    [IO.File]::WriteAllText((Join-Path (D 'Family Admin/Krish/DS160 - Final') 'form.pdf'), 'fixture')
    $log = Invoke-Week @{ 'what-goes-in' = @('Immigration papers', '') }
    $kinds = @($popups | ForEach-Object Kind)
    if ($popups.Count -ne 2 -or @($kinds | Where-Object { $_ -ne 'what-goes-in' }).Count) {
        throw "week 1: expected two questions, one per new folder at the top of the drive; got $($popups.Count): $($kinds -join ', ')"
    }
    if ($popups[0].Text -notmatch '1 Home & Personal' -or $popups[0].Default -ne 'Home & Personal') { throw 'week 1: the question did not carry a guess from the folder name' }
    if ((Get-Entry (D '1 Home & Personal')).purpose -ne 'Immigration papers') { throw 'week 1: his typed answer was not recorded' }
    $music = Get-Entry (D 'Music Production')
    if ($music.status -ne 'new-waiting-on-krish' -or (Get-Field $music 'worked_out') -ne 'Music Production') { throw 'week 1: Cancel did not keep the guess' }
    $ds = Get-Entry (D 'Family Admin/Krish/DS160 - Final')
    if ((Get-Field $ds 'worked_out') -ne 'DS160 - Final, in Krish' -or $ds.status -ne 'new-waiting-on-krish') {
        throw 'week 1: a new folder inside a folder he has was not worked out from its name and place'
    }
    if ($log.popups -ne 2 -or $log.new_folders_to_ask -ne 0) { throw "week 1: the log says $($log.popups) pop-ups and $($log.new_folders_to_ask) still to ask" }
    # Working it out spares him the question; it does not release the folder.
    $prefs = Import-FaFolderPreferences -Path $prefsPath
    try {
        Assert-FaFolderConsent -Path (Join-Path (D 'Family Admin/Krish/DS160 - Final') 'form.pdf') -Action 'move-file' -Preferences $prefs -Operation 'a file move'
        throw 'NOT REFUSED'
    } catch { if ($_.Exception.Message -notmatch '^REFUSED') { throw 'week 1: a worked-out folder lost the guard that keeps its files where they are' } }
    Write-Host 'PASS: week 1 asks once per new folder at the top of a drive, with a guess, and works out the rest'

    # ---- week 2: the session moves the tree into Immigration and renames a folder
    foreach ($n in @('00_UPLOAD_PACK', '10_passports_and_identity', '14_spouse_e3_details')) {
        Move-Item -LiteralPath (D "1 Home & Personal/Immigration/$n") -Destination (D "Immigration/$n")
    }
    Remove-Item -LiteralPath (D '1 Home & Personal') -Recurse -Force
    Rename-Item -LiteralPath (D 'Immigration/Visa & E3') -NewName 'Old E3'
    # One "Archive" goes and two arrive: ambiguous, so never linked as a move.
    Remove-Item -LiteralPath (D 'Family Admin/Krish/Archive') -Force
    New-Folders @('Family Admin/Amil/00_ROUTING', 'Family Admin/Amil/Archive', 'Inbox from My AI/Archive')
    $log = Invoke-Week @{ 'gone-all' = @('Yes') }
    if ($popups.Count -ne 1 -or $popups[0].Kind -ne 'gone-all') {
        throw "week 2: expected one ""did you OK these?"" pop-up; got $($popups.Count): $(@($popups | ForEach-Object Kind) -join ', ')"
    }
    $text = $popups[0].Text
    foreach ($want in @('an AI session you asked', 'renamed to Old E3', ('what was inside it moved to ' + (D 'Immigration')), 'Archive: gone, and not found anywhere')) {
        if ($text.IndexOf($want, [StringComparison]::Ordinal) -lt 0) { throw "week 2: the pop-up did not say: $want`n$text" }
    }
    if ($text.IndexOf('Archive: gone', [StringComparison]::Ordinal) -gt $text.IndexOf('renamed to', [StringComparison]::Ordinal)) {
        throw 'week 2: a folder found nowhere was not listed first'
    }
    $pass = Get-Entry (D 'Immigration/10_passports_and_identity')
    if ($pass.status -ne 'known' -or (Get-Field $pass 'moved_from') -ne (D '1 Home & Personal/Immigration/10_passports_and_identity')) {
        throw 'week 2: the passports folder in its new place was treated as a new folder'
    }
    $up = Get-Entry (D 'Immigration/00_UPLOAD_PACK')
    if ((Get-Field $up 'moved_from') -ne (D '1 Home & Personal/Immigration/00_UPLOAD_PACK')) { throw 'week 2: a moved folder lost where it came from' }
    if ((Get-Field (Get-Entry (D 'Immigration/14_spouse_e3_details/scans')) 'moved_from') -ne (D '1 Home & Personal/Immigration/14_spouse_e3_details/scans')) {
        throw 'week 2: a folder inside a moved folder was not moved with it'
    }
    if ((Get-Field (Get-Entry (D 'Immigration/Old E3')) 'moved_from') -ne (D 'Immigration/Visa & E3') -or
        (Get-Field (Get-Entry (D 'Immigration/Old E3/_IMM_TMP2')) 'moved_from') -ne (D 'Immigration/Visa & E3/_IMM_TMP2')) {
        throw 'week 2: the rename of Visa & E3 to Old E3 was not one move'
    }
    if (Get-Field (Get-Entry (D 'Family Admin/Krish/Archive')) 'moved_to') { throw 'week 2: an ambiguous name was linked as a move' }
    foreach ($p in @('Family Admin/Amil', 'Family Admin/Amil/Archive', 'Inbox from My AI/Archive')) {
        if (-not (Get-Field (Get-Entry (D $p)) 'worked_out')) { throw "week 2: $p was not worked out" }
    }
    if ((Get-Field (Get-Entry (D 'Family Admin/Amil/00_ROUTING')) 'worked_out') -ne 'ROUTING, in Amil') { throw 'week 2: a folder inside a worked-out folder was not worked out' }
    foreach ($p in @('1 Home & Personal', 'Immigration/Visa & E3', 'Family Admin/Krish/Archive', '1 Home & Personal/Immigration/10_passports_and_identity')) {
        if ((Get-Entry (D $p)).status -ne 'removed-by-krish') { throw "week 2: his Yes did not cover $p" }
    }
    if ($log.moved_or_removed_without_ok -ne 0 -or $log.moves_found -ne 6 -or $log.moves_found_by_shape -ne 6 -or $log.new_folders_to_ask -ne 0) {
        throw "week 2: miscounted (without OK $($log.moved_or_removed_without_ok), moves $($log.moves_found), by shape $($log.moves_found_by_shape), to ask $($log.new_folders_to_ask))"
    }
    $latest = Get-Content -LiteralPath (Join-Path $reportRoot 'LATEST.md') -Raw
    if ($latest -notmatch 'Moves found this time \(6\)' -or $latest -notmatch 'worked out from their name and where they sit \(4\)') {
        throw 'week 2: LATEST.md did not list the moves and the worked-out folders'
    }
    Write-Host 'PASS: week 2 asks one question for the moves, none about the moved folders in their new place'

    # ---- week 3: a folder he has is truly gone, and he did not OK it ------------
    Remove-Item -LiteralPath (D 'Inbox from My AI') -Recurse -Force
    $log = Invoke-Week @{ 'gone-all' = @('No'); 'gone-one' = @('No') }
    if ($popups.Count -ne 2 -or $popups[1].Text -notmatch 'Inbox from My AI \(and the folder inside it\): gone, and not found anywhere') {
        throw "week 3: expected the group question then one for the lost folder; got $($popups.Count)"
    }
    if ($log.moved_or_removed_without_ok -ne 2) { throw "week 3: expected 2 folders gone without his OK, got $($log.moved_or_removed_without_ok)" }
    Write-Host 'PASS: week 3 counts a folder gone without his OK, after asking once'

    # ---- week 4: nothing changed --------------------------------------------------
    $log = Invoke-Week @{}
    if ($popups.Count -ne 0 -or $log.popups -ne 0) { throw "week 4: nothing changed and he still got $($popups.Count) pop-ups" }
    if ($log.moved_or_removed_without_ok -ne 0) { throw 'week 4: last week''s loss was counted again' }
    Write-Host 'PASS: week 4, nothing changed and nothing is asked, not even last week''s No again'
} finally {
    $env:FILEARCHIVES_FOLDER_PREFERENCES = $savedPrefsEnv
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
