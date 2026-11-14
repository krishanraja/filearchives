# Ruling (Krish, 2026-10-23): filearchives never moves a folder Krish made
# without asking first. The weekly check-in counts folders moved or removed
# without his OK. This proves it counts only true losses, on a fixture drive:
# a consent row for a parent covers the folders beneath it, a folder whose Drive
# id now sits elsewhere is one move (still counted without his OK) and not one
# gone plus one new, a folder that comes back is recorded as restored, and an
# unattended run names each folder it could not decide.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$structure = Join-Path $repo 'stages' '07_structure'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-true-losses-' + [guid]::NewGuid().ToString('n'))
$drive = Join-Path $scratch 'My Drive'
$prefsPath = Join-Path $scratch 'folder-preferences.json'
$reportRoot = Join-Path $scratch 'folder-checkin'
$nowPath = Join-Path $scratch 'NOW.md'
$drivePaths = Join-Path $scratch 'drive-paths.json'
$savedPrefsEnv = $env:FILEARCHIVES_FOLDER_PREFERENCES

function Read-Prefs { Get-Content -LiteralPath $prefsPath -Raw | ConvertFrom-Json -Depth 32 }
function Get-Entry([string] $Path) {
    @((Read-Prefs).folders | Where-Object { $_.path -eq $Path }) | Select-Object -First 1
}
function D([string] $Rel) { Join-Path $drive $Rel }
function Write-DrivePaths([hashtable] $Map) {
    $rows = @($Map.GetEnumerator() | ForEach-Object { @{ id = $_.Key; path = $_.Value; state = 'found' } })
    [IO.File]::WriteAllText($drivePaths, (@{ folders = $rows } | ConvertTo-Json -Depth 4))
}
function Invoke-Checkin {
    & (Join-Path $structure 'weekly_folder_checkin.ps1') -ReportRoot $reportRoot -NowPath $nowPath -DrivePathsPath $drivePaths
    return @(Get-Content -LiteralPath (Join-Path $reportRoot 'LOG.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })[-1]
}

try {
    foreach ($d in @('Parent/Child/Grandchild', 'Brand', 'Bin', 'Answered/Inner', 'Untouched')) {
        New-Item -ItemType Directory -Path (D $d) -Force | Out-Null
    }
    $seed = Get-Content -LiteralPath (Join-Path $repo 'policy' 'folder-preferences.json') -Raw | ConvertFrom-Json -Depth 16
    $seed.watch_roots = @(@{ path = $drive; max_depth = 4 })
    $seed.never_enter = @()
    $seed.folders = @()
    $seed.consents = @()
    $seed.recorded_at = $null
    [IO.File]::WriteAllText($prefsPath, ($seed | ConvertTo-Json -Depth 16))
    $env:FILEARCHIVES_FOLDER_PREFERENCES = $prefsPath
    [IO.File]::WriteAllText($nowPath, "## Where it is right now`n`n<!-- north-star-state {`"week_of`": `"2026-11-09`", `"week_target`": 0, `"current`": null, `"current_as_of`": null, `"current_source`": null, `"urgency`": 1} --> **North Star number**`n")
    & (Join-Path $structure 'record_folder_preferences.ps1')

    # Run 1: a clean week. The ids the machine-side map gives are recorded.
    Write-DrivePaths @{ 'id-brand' = (D 'Brand'); 'id-bin' = (D 'Bin') }
    $log = Invoke-Checkin
    if ($log.moved_or_removed_without_ok -ne 0) { throw 'a clean week was miscounted' }
    if ((Get-Entry (D 'Brand')).drive_id -ne 'id-brand') { throw 'the Drive id from drive-paths.json was not recorded' }
    if (-not $log.drive_ids_read) { throw 'the run did not say it read the Drive ids' }

    # Run 2, unattended:
    # (a) Krish's delete row for Parent covers Child and Grandchild.
    # (b) Brand is renamed: same id, new path. One move, not gone plus new.
    # (c) Bin goes with no row and no answer: a true loss.
    # (d) Answered goes, and he wrote that he removed it: covers Inner too.
    $data = Read-Prefs
    $data.consents = @(@{ path = (D 'Parent'); action = 'delete'; approved_by = 'Krish'; approved_at = '2026-11-14T09:00:00Z'
        words = 'fixture: delete Parent'; what = 'fixture' })
    [IO.File]::WriteAllText($prefsPath, ($data | ConvertTo-Json -Depth 16))
    Remove-Item -LiteralPath (D 'Parent') -Recurse -Force
    Rename-Item -LiteralPath (D 'Brand') -NewName 'Brand Kit'
    Write-DrivePaths @{ 'id-brand' = (D 'Brand Kit') }
    Remove-Item -LiteralPath (D 'Bin') -Recurse -Force
    Remove-Item -LiteralPath (D 'Answered') -Recurse -Force
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $reportRoot 'answers.json'), (@{ removed_by_krish = @((D 'Answered')) } | ConvertTo-Json))
    $log = Invoke-Checkin

    foreach ($p in @('Parent', 'Parent/Child', 'Parent/Child/Grandchild')) {
        if ((Get-Entry (D $p)).status -ne 'moved-with-ok') { throw "the row for Parent did not cover $p" }
    }
    $brand = Get-Entry (D 'Brand')
    if ($brand.status -ne 'moved' -or $brand.moved_to -ne (D 'Brand Kit')) { throw 'a renamed folder was not recorded as moved, with where it went' }
    $kit = Get-Entry (D 'Brand Kit')
    if ($kit.status -ne 'known' -or $kit.moved_from -ne (D 'Brand')) { throw 'the moved folder''s new place was recorded as a new folder' }
    if ((Get-Entry (D 'Bin')).status -ne 'missing') { throw 'a folder gone without his OK was not recorded as missing' }
    foreach ($p in @('Answered', 'Answered/Inner')) {
        if ((Get-Entry (D $p)).status -ne 'removed-by-krish') { throw "his written answer for Answered did not cover $p" }
    }
    if ((Get-Entry (D 'Untouched')).status -ne 'known') { throw 'an untouched folder changed status' }
    if ($log.moved_or_removed_without_ok -ne 2 -or $log.moved_without_ok -ne 1) {
        throw "expected 2 without his OK (1 moved, 1 gone), got $($log.moved_or_removed_without_ok) ($($log.moved_without_ok) moved)"
    }
    if ($log.new_folders_waiting -ne 0) { throw 'the renamed folder was counted as new, waiting on him' }
    $latest = Get-Content -LiteralPath (Join-Path $reportRoot 'LATEST.md') -Raw
    if ($log.undecided -ne 2 -or $latest -notmatch 'Could not decide without you \(2\)') {
        throw 'the unattended run did not name the folders it could not decide'
    }
    Write-Host 'PASS: a parent''s row covers its folders, a rename is one move, and an unattended run names what it could not decide'

    # Run 3: Bin comes back from the Drive bin. It is recorded as restored.
    [IO.File]::WriteAllText((Join-Path $reportRoot 'answers.json'), '{}')
    New-Item -ItemType Directory -Path (D 'Bin') -Force | Out-Null
    $log = Invoke-Checkin
    $bin = Get-Entry (D 'Bin')
    if ($bin.status -ne 'known' -or -not $bin.restored_at -or $bin.restored_from_status -ne 'missing') {
        throw 'a folder that came back was not recorded as restored'
    }
    if ($log.restored -ne 1 -or $log.moved_or_removed_without_ok -ne 0) { throw 'the restore was miscounted' }
    if ((Get-Content -LiteralPath (Join-Path $reportRoot 'LATEST.md') -Raw) -notmatch 'Back where they were \(1\)') {
        throw 'LATEST.md did not report the restored folder'
    }
    Write-Host 'PASS: a folder back from the bin is recorded as restored'
} finally {
    $env:FILEARCHIVES_FOLDER_PREFERENCES = $savedPrefsEnv
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
