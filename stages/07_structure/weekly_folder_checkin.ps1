<#
    The weekly folder check-in. It looks and asks; it never moves, renames or
    deletes anything.

        pwsh -NoProfile -File stages\07_structure\weekly_folder_checkin.ps1 -Interactive

    Krish never runs this by hand: the weekly scheduled task does, and so does
    CHECK-MY-NEW-FOLDERS.cmd.

    1. Every folder that is not in Krish's record becomes 'new-waiting-on-krish'
       and is left exactly where he put it.
    2. Krish is asked two short questions per new folder: is it important to
       keep, and what goes in it. Pop-ups when -Interactive; otherwise his
       written answers in docs/folder-checkin/answers.json.
    3. A recorded folder that has gone without a consent row is counted. That
       count is the North Star number: folders moved or removed without
       Krish's OK. If he says he did it himself, it is not counted.
    4. Each folder he has answered for gets a cleanliness check against what he
       said goes in it: counts only, no file names leave his machine.

    Only true losses are counted:
    - A consent row for a folder also covers every recorded folder beneath it.
    - A recorded folder whose Drive id now sits at another path (read from the
      drive-paths.json that content-engine's sync writes on each home computer)
      is recorded as moved, with where it went, and its new path is not a new
      folder. A move without his OK still counts: the number is folders moved or
      removed without his OK.
    - A folder that comes back (from the Drive bin, say) is recorded as restored.
    - A run that cannot ask him names, in LATEST.md, each folder it could not
      decide; nothing is guessed.
#>
[CmdletBinding()]
param(
    [string] $PreferencesPath,
    [string] $ReportRoot,
    [string] $AnswersPath,
    [string] $NowPath,
    [string] $DrivePathsPath,
    [switch] $Interactive,
    [int] $MaxQuestions = 10,
    [datetimeoffset] $AsOf = [DateTimeOffset]::Now
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards' 'workspace.ps1')
. (Join-Path $repo 'guards' 'atomic.ps1')
. (Join-Path $repo 'guards' 'folder_consent.ps1')
if (-not $ReportRoot) { $ReportRoot = Join-Path $repo 'docs' 'folder-checkin' }
if (-not $AnswersPath) { $AnswersPath = Join-Path $ReportRoot 'answers.json' }
if (-not $NowPath) { $NowPath = Join-Path $repo 'NOW.md' }
if (-not $DrivePathsPath -and $env:LOCALAPPDATA) {
    $DrivePathsPath = Join-Path $env:LOCALAPPDATA 'makeyourmindup' 'drive-paths.json'
}

$prefs = Import-FaFolderPreferences -Path $PreferencesPath
if (-not $prefs.Recorded) {
    Write-Host 'STOPPED: Krish has not recorded his folders yet. Press RECORD-MY-FOLDERS.cmd first.'
    exit 3
}
$stamp = $AsOf.ToString('o')
$day = $AsOf.ToString('yyyy-MM-dd')
$weekAgo = $AsOf.AddDays(-7)

function Set-FaEntryValue {
    param($Entry, [string] $Name, $Value)
    if ($null -ne $Entry.PSObject.Properties[$Name]) { $Entry.$Name = $Value }
    else { $Entry | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Get-FaEntryValue {
    param($Entry, [string] $Name)
    if ($null -ne $Entry.PSObject.Properties[$Name]) { return $Entry.$Name }
    return $null
}

function Get-FaDrivePathRow($Row) {
    # Fields the contract may use: id or drive_id, path or local_path, state.
    $get = { param($n) if ($null -ne $Row.PSObject.Properties[$n]) { $Row.$n } else { $null } }
    return [pscustomobject]@{ drive_id = (& $get 'drive_id'); id = (& $get 'id'); local_path = (& $get 'local_path')
        path = (& $get 'path'); state = (& $get 'state') }
}

# ---- 1. look ---------------------------------------------------------------
# The machine-side Drive map: folder id -> where it is on this computer now.
# Absent or unreadable means no ids this run; paths are then the only identity.
$idAtPath = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$pathOfId = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
$drivePathsRead = $false
if ($DrivePathsPath -and (Test-Path -LiteralPath $DrivePathsPath -PathType Leaf)) {
    try {
        $dp = Get-Content -LiteralPath $DrivePathsPath -Raw | ConvertFrom-Json -Depth 8
        $rows = if ($dp -is [array]) { $dp }
            elseif ($null -ne $dp.PSObject.Properties['folders']) { $dp.folders }
            elseif ($null -ne $dp.PSObject.Properties['entries']) { $dp.entries }
            else { @() }
        foreach ($row in @($rows)) {
            if (-not $row) { continue }
            $r = Get-FaDrivePathRow $row
            $id = [string](@($r.drive_id, $r.id) | Where-Object { $_ } | Select-Object -First 1)
            $local = [string](@($r.local_path, $r.path) | Where-Object { $_ } | Select-Object -First 1)
            $state = if ($r.state) { [string]$r.state } else { 'found' }
            if (-not $id -or -not $local -or $state -ne 'found') { continue }
            $canon = ConvertTo-FaCanonicalPath $local
            $idAtPath[$canon] = $id
            $pathOfId[$id] = $canon
        }
        $drivePathsRead = $true
    } catch {
        Write-Host "drive-paths.json could not be read ($($_.Exception.Message)); folders are matched by path only this run."
    }
}

function Test-FaReleasedByKrish {
    # A consent row for this folder, or for a folder above it, releases it.
    param([string] $Path)
    return @($prefs.Data.consents | Where-Object {
        [string]$_.approved_by -eq 'Krish' -and $_.approved_at -and [string]$_.action -in @('move', 'delete') -and
        (Test-FaPathWithin -Path $Path -Root ([string]$_.path))
    }).Count -gt 0
}

$entries = [Collections.Generic.List[object]]::new()
foreach ($e in @($prefs.Data.folders)) { $entries.Add($e) }
$unavailable = [Collections.Generic.List[string]]::new()
$unreadable = [Collections.Generic.List[string]]::new()
$goneThisRun = [Collections.Generic.List[object]]::new()
$restoredThisRun = [Collections.Generic.List[object]]::new()
$newThisRun = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($root in $prefs.WatchRoots) {
    if (-not (Test-Path -LiteralPath $root.Path -PathType Container)) {
        $unavailable.Add($root.Path)
        continue
    }
    $tree = Get-FaFolderTree -Root $root.Path -MaxDepth $root.MaxDepth `
        -NeverEnter $prefs.NeverEnter -SkipNames $prefs.SkipNames
    foreach ($u in $tree.Unreadable) { $unreadable.Add($u) }
    $present = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($folder in $tree.Folders) {
        $null = $present.Add($folder)
        if ($prefs.ByPath.ContainsKey($folder)) {
            $entry = $prefs.ByPath[$folder]
            if ($idAtPath.ContainsKey($folder) -and -not (Get-FaEntryValue $entry 'drive_id')) {
                Set-FaEntryValue $entry 'drive_id' $idAtPath[$folder]
            }
            if ([string]$entry.status -in @('missing', 'removed-by-krish', 'moved-with-ok', 'moved')) {
                # It was gone and is back (restored from the bin, or put back).
                $back = Get-FaEntryValue $entry 'previous_status'
                Set-FaEntryValue $entry 'restored_from_status' ([string]$entry.status)
                $entry.status = if ($back -and $back -notin @('missing', 'moved')) { $back } else { 'known' }
                Set-FaEntryValue $entry 'restored_at' $stamp
                $restoredThisRun.Add($entry)
            }
            continue
        }
        $entry = [pscustomobject][ordered]@{
            path = $folder; status = 'new-waiting-on-krish'; first_seen = $stamp
            important = $null; purpose = $null; answered_at = $null
        }
        if ($idAtPath.ContainsKey($folder)) { $entry | Add-Member -NotePropertyName 'drive_id' -NotePropertyValue $idAtPath[$folder] }
        $entries.Add($entry)
        $prefs.ByPath[$folder] = $entry
        $null = $newThisRun.Add($folder)
    }
    foreach ($entry in @($entries | Where-Object { Test-FaPathWithin -Path ([string]$_.path) -Root $root.Path })) {
        $path = ConvertTo-FaCanonicalPath ([string]$entry.path)
        if ($present.Contains($path)) { continue }
        if ([string]$entry.status -notin @('known', 'answered', 'new-waiting-on-krish')) { continue }
        if (@($tree.Unreadable | Where-Object { Test-FaPathWithin -Path $path -Root $_ }).Count -gt 0) { continue }
        $id = [string](Get-FaEntryValue $entry 'drive_id')
        $movedTo = $null
        if ($id -and $pathOfId.ContainsKey($id) -and -not $pathOfId[$id].Equals($path, [StringComparison]::OrdinalIgnoreCase) -and
                (Test-Path -LiteralPath $pathOfId[$id] -PathType Container)) {
            $movedTo = $pathOfId[$id]
        }
        Set-FaEntryValue $entry 'previous_status' ([string]$entry.status)
        if ($movedTo) {
            # Same folder, new place: one move, not one folder gone plus one new.
            Set-FaEntryValue $entry 'moved_to' $movedTo
            Set-FaEntryValue $entry 'moved_seen_at' $stamp
            if ($prefs.ByPath.ContainsKey($movedTo) -and $newThisRun.Contains($movedTo)) {
                $arrived = $prefs.ByPath[$movedTo]
                $arrived.status = [string]$entry.status
                foreach ($k in @('important', 'purpose', 'answered_at')) { Set-FaEntryValue $arrived $k (Get-FaEntryValue $entry $k) }
                Set-FaEntryValue $arrived 'moved_from' $path
                if ([string]$arrived.status -eq 'new-waiting-on-krish') { $arrived.first_seen = Get-FaEntryValue $entry 'first_seen' }
                $null = $newThisRun.Remove($movedTo)
            }
        }
        if (Test-FaReleasedByKrish -Path $path) {
            $entry.status = 'moved-with-ok'
            continue
        }
        $entry.status = if ($movedTo) { 'moved' } else { 'missing' }
        Set-FaEntryValue $entry 'missing_since' $stamp
        $goneThisRun.Add($entry)
    }
}

# ---- 2. ask ----------------------------------------------------------------
function Set-FaAnswer {
    param($Entry, [bool] $Important, [string] $Purpose, [string] $How)
    $parent = ConvertTo-FaCanonicalPath ([string]$Entry.path)
    foreach ($e in @($entries | Where-Object {
        [string]$_.status -eq 'new-waiting-on-krish' -and (Test-FaPathWithin -Path ([string]$_.path) -Root $parent)
    })) {
        $e.status = 'answered'
        $e.important = $Important
        $e.purpose = if ($e -eq $Entry) { $Purpose } else { "part of $parent" }
        $e.answered_at = $stamp
        Set-FaEntryValue $e 'answered_by' $How
    }
}

$written = if (Test-Path -LiteralPath $AnswersPath -PathType Leaf) {
    Get-Content -LiteralPath $AnswersPath -Raw | ConvertFrom-Json -Depth 8
} else { $null }
if ($written) {
    foreach ($a in @(Get-FaEntryValue $written 'folders')) {
        if (-not $a) { continue }
        $path = ConvertTo-FaCanonicalPath ([string]$a.path)
        if (-not $prefs.ByPath.ContainsKey($path)) { continue }
        $entry = $prefs.ByPath[$path]
        if ([string]$entry.status -ne 'new-waiting-on-krish') { continue }
        Set-FaAnswer -Entry $entry -Important ([bool]$a.important) -Purpose ([string]$a.purpose) -How 'answers.json'
    }
    foreach ($p in @(Get-FaEntryValue $written 'removed_by_krish')) {
        if (-not $p) { continue }
        $path = ConvertTo-FaCanonicalPath ([string]$p)
        # His answer for a folder covers the recorded folders beneath it.
        foreach ($e in @($entries | Where-Object {
            [string]$_.status -in @('missing', 'moved') -and (Test-FaPathWithin -Path ([string]$_.path) -Root $path)
        })) {
            $e.status = 'removed-by-krish'
        }
    }
}

$canAsk = $Interactive -and $IsWindows -and [Environment]::UserInteractive
if ($canAsk) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName Microsoft.VisualBasic
    $asked = 0
    $title = 'filearchives weekly folder check-in'
    $waiting = @($entries | Where-Object { [string]$_.status -eq 'new-waiting-on-krish' } |
        Sort-Object { @(Get-FaPathSegments ([string]$_.path)).Count }, { [string]$_.path })
    foreach ($entry in $waiting) {
        if ([string]$entry.status -ne 'new-waiting-on-krish') { continue }
        if ($asked -ge $MaxQuestions) { break }
        $asked++
        $q1 = [Windows.Forms.MessageBox]::Show(
            "You made a new folder:`n`n$($entry.path)`n`nIs this an important folder to keep?`n`n(Cancel: ask me next week. Nothing is moved either way.)",
            $title, 'YesNoCancel', 'Question')
        if ($q1 -eq 'Cancel') { break }
        $purpose = [Microsoft.VisualBasic.Interaction]::InputBox(
            "What goes in this folder?`n`n$($entry.path)`n`n(One line is enough.)", $title, '')
        Set-FaAnswer -Entry $entry -Important ($q1 -eq 'Yes') -Purpose $purpose -How 'pop-up'
    }
    foreach ($entry in @($entries | Where-Object { [string]$_.status -in @('missing', 'moved') })) {
        if ([string]$entry.status -notin @('missing', 'moved')) { continue }
        $what = if ([string]$entry.status -eq 'moved') { "has moved to:`n`n$($entry.moved_to)" } else { 'is gone now.' }
        $q = [Windows.Forms.MessageBox]::Show(
            "This folder was here before:`n`n$($entry.path)`n`nIt $what`n`nDid you move or remove it yourself?",
            $title, 'YesNo', 'Warning')
        if ($q -eq 'Yes') {
            $parent = ConvertTo-FaCanonicalPath ([string]$entry.path)
            foreach ($e in @($entries | Where-Object {
                [string]$_.status -in @('missing', 'moved') -and (Test-FaPathWithin -Path ([string]$_.path) -Root $parent)
            })) { $e.status = 'removed-by-krish' }
        }
    }
}

# ---- 3. the number ---------------------------------------------------------
$withoutOk = @($goneThisRun | Where-Object { [string]$_.status -in @('missing', 'moved') })
# A run that could not ask him leaves these undecided: they count until he answers.
$undecided = @(if (-not $canAsk) { $withoutOk | Sort-Object { [string]$_.path } })

# ---- 4. keep it clean, by his answers --------------------------------------
$clean = [Collections.Generic.List[object]]::new()
foreach ($entry in @($entries | Where-Object {
    [string]$_.status -eq 'answered' -and $_.important -eq $true -and
    -not ([string]$_.purpose).StartsWith('part of ')
} | Sort-Object { [string]$_.path })) {
    $path = [string]$entry.path
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
    $files = @([IO.DirectoryInfo]::new($path).EnumerateFiles())
    $clean.Add([pscustomobject]@{
        Path = $path; Purpose = [string]$entry.purpose
        Files = $files.Count
        NewThisWeek = @($files | Where-Object { $_.LastWriteTimeUtc -ge $weekAgo.UtcDateTime }).Count
    })
}
$loose = [Collections.Generic.List[object]]::new()
foreach ($root in $prefs.WatchRoots) {
    if ($unavailable -contains $root.Path) { continue }
    $count = @([IO.DirectoryInfo]::new($root.Path).EnumerateFiles() | Where-Object {
        @($prefs.Data.root_files_allowed) -notcontains $_.Name
    }).Count
    $loose.Add([pscustomobject]@{ Root = $root.Path; Files = $count })
}

# ---- write it down ---------------------------------------------------------
$prefs.Data.folders = @($entries)
$prefs.Data.last_checkin_at = $stamp
Write-FaFolderPreferences -Preferences $prefs

$waitingNow = @($entries | Where-Object { [string]$_.status -eq 'new-waiting-on-krish' } | Sort-Object { [string]$_.path })
$missingNow = @($entries | Where-Object { [string]$_.status -in @('missing', 'moved') } | Sort-Object { [string]$_.path })
function Format-FaCell([string] $Text) { return ($Text -replace '\|', '/' -replace '[\r\n]+', ' ').Trim() }

$md = [Text.StringBuilder]::new()
[void]$md.AppendLine("# Folder check-in, $day")
[void]$md.AppendLine()
[void]$md.AppendLine('Nothing was moved, renamed or deleted. This check only looks and asks.')
[void]$md.AppendLine()
[void]$md.AppendLine('## The number')
[void]$md.AppendLine()
[void]$md.AppendLine("- Folders moved or removed without Krish's OK this week: **$($withoutOk.Count)**")
[void]$md.AppendLine("- Cleanliness check completed: **yes, $day**")
[void]$md.AppendLine()
[void]$md.AppendLine("## New folders waiting on Krish ($($waitingNow.Count))")
[void]$md.AppendLine()
if ($waitingNow.Count -eq 0) { [void]$md.AppendLine('None.') } else {
    [void]$md.AppendLine('Each stays exactly where you put it. Two questions each: is it important to keep, and what goes in it?')
    [void]$md.AppendLine()
    [void]$md.AppendLine('| Folder | First seen |')
    [void]$md.AppendLine('|---|---|')
    foreach ($e in $waitingNow) {
        [void]$md.AppendLine(('| `{0}` | {1} |' -f (Format-FaCell $e.path), ([string]$e.first_seen).Substring(0, 10)))
    }
}
[void]$md.AppendLine()
[void]$md.AppendLine("## Folders that are gone and nobody recorded your OK ($($missingNow.Count))")
[void]$md.AppendLine()
if ($missingNow.Count -eq 0) { [void]$md.AppendLine('None.') } else {
    [void]$md.AppendLine('| Folder | Gone since |')
    [void]$md.AppendLine('|---|---|')
    foreach ($e in $missingNow) {
        $label = Format-FaCell $e.path
        if ([string]$e.status -eq 'moved') { $label = '{0}` moved to `{1}' -f $label, (Format-FaCell ([string]$e.moved_to)) }
        [void]$md.AppendLine(('| `{0}` | {1} |' -f $label, ([string]$e.missing_since).Substring(0, 10)))
    }
}
if ($undecided.Count -gt 0) {
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Could not decide without you ($($undecided.Count))")
    [void]$md.AppendLine()
    [void]$md.AppendLine('This run could not ask you, so these count until you say. If you moved or removed one yourself, add its path to `removed_by_krish` in `docs/folder-checkin/answers.json`; that covers the folders inside it too.')
    [void]$md.AppendLine()
    foreach ($e in $undecided) { [void]$md.AppendLine(('- `{0}` ({1})' -f (Format-FaCell $e.path), $e.status)) }
}
if ($restoredThisRun.Count -gt 0) {
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Back where they were ($($restoredThisRun.Count))")
    [void]$md.AppendLine()
    [void]$md.AppendLine('These were recorded as gone and are back, restored from the Drive bin or put back by hand.')
    [void]$md.AppendLine()
    foreach ($e in @($restoredThisRun | Sort-Object { [string]$_.path })) {
        [void]$md.AppendLine(('- `{0}` (was {1})' -f (Format-FaCell $e.path), $e.restored_from_status))
    }
}
[void]$md.AppendLine()
[void]$md.AppendLine("## Your folders, checked against what you said goes in them ($($clean.Count))")
[void]$md.AppendLine()
if ($clean.Count -eq 0) { [void]$md.AppendLine('None answered yet.') } else {
    [void]$md.AppendLine('| Folder | What goes in it | Files | New this week |')
    [void]$md.AppendLine('|---|---|---|---|')
    foreach ($c in $clean) {
        [void]$md.AppendLine(('| `{0}` | {1} | {2} | {3} |' -f (Format-FaCell $c.Path), (Format-FaCell $c.Purpose), $c.Files, $c.NewThisWeek))
    }
}
[void]$md.AppendLine()
[void]$md.AppendLine('## Loose files at the top of a drive')
[void]$md.AppendLine()
foreach ($l in $loose) { [void]$md.AppendLine(('- `{0}`: {1}' -f $l.Root, $l.Files)) }
if ($unavailable.Count -gt 0) {
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Not checked this week (not mounted)')
    [void]$md.AppendLine()
    foreach ($u in $unavailable) { [void]$md.AppendLine(('- `{0}`' -f $u)) }
}
[void]$md.AppendLine()
[void]$md.AppendLine('## Answering without the pop-ups')
[void]$md.AppendLine()
[void]$md.AppendLine('Edit `docs/folder-checkin/answers.json` on GitHub, or ask any Claude session to do it for you. Answering "not important" never moves or deletes the folder: that needs your yes for that folder, recorded in `policy/folder-preferences.json` under `consents`.')
Write-FaAtomicUtf8 -Path (Join-Path $ReportRoot 'LATEST.md') -Content $md.ToString()

$log = [ordered]@{
    checked_at = $stamp
    moved_or_removed_without_ok = $withoutOk.Count
    moved_without_ok = @($withoutOk | Where-Object { [string]$_.status -eq 'moved' }).Count
    undecided = $undecided.Count
    restored = $restoredThisRun.Count
    drive_ids_read = $drivePathsRead
    cleanliness_check_completed = $true
    new_folders_waiting = $waitingNow.Count
    answered_folders_checked = $clean.Count
    roots_unavailable = @($unavailable)
    unreadable_folders = $unreadable.Count
}
New-Item -ItemType Directory -Path $ReportRoot -Force | Out-Null
Add-Content -LiteralPath (Join-Path $ReportRoot 'LOG.jsonl') -Value ($log | ConvertTo-Json -Compress) -Encoding utf8

if (Test-Path -LiteralPath $NowPath -PathType Leaf) {
    $now = Get-Content -LiteralPath $NowPath -Raw
    $marker = [regex]::Match($now, '<!-- north-star-state (\{.*?\}) -->')
    if ($marker.Success) {
        $state = $marker.Groups[1].Value | ConvertFrom-Json
        $state.current = $withoutOk.Count
        $state.current_as_of = $day
        $state.current_source = 'docs/folder-checkin/LOG.jsonl'
        $replacement = '<!-- north-star-state ' + ($state | ConvertTo-Json -Compress) + ' -->'
        Write-FaAtomicUtf8 -Path $NowPath -Content ($now.Remove($marker.Index, $marker.Length).Insert($marker.Index, $replacement))
    }
}

Write-Host ("folder check-in {0}: new waiting={1} gone without OK={2} answered folders checked={3}" -f
    $day, $waitingNow.Count, $withoutOk.Count, $clean.Count)
Write-Host 'Nothing was moved, renamed or deleted.'
