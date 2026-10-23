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
#>
[CmdletBinding()]
param(
    [string] $PreferencesPath,
    [string] $ReportRoot,
    [string] $AnswersPath,
    [string] $NowPath,
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
    if ($Entry.PSObject.Properties.Name -contains $Name) { $Entry.$Name = $Value }
    else { $Entry | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Get-FaEntryValue {
    param($Entry, [string] $Name)
    if ($Entry.PSObject.Properties.Name -contains $Name) { return $Entry.$Name }
    return $null
}

# ---- 1. look ---------------------------------------------------------------
$entries = [Collections.Generic.List[object]]::new()
foreach ($e in @($prefs.Data.folders)) { $entries.Add($e) }
$unavailable = [Collections.Generic.List[string]]::new()
$unreadable = [Collections.Generic.List[string]]::new()
$goneThisRun = [Collections.Generic.List[object]]::new()
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
            if ([string]$entry.status -eq 'missing') {
                $back = Get-FaEntryValue $entry 'previous_status'
                $entry.status = if ($back) { $back } else { 'known' }
            }
            continue
        }
        $entry = [pscustomobject][ordered]@{
            path = $folder; status = 'new-waiting-on-krish'; first_seen = $stamp
            important = $null; purpose = $null; answered_at = $null
        }
        $entries.Add($entry)
        $prefs.ByPath[$folder] = $entry
    }
    foreach ($entry in @($entries | Where-Object { Test-FaPathWithin -Path ([string]$_.path) -Root $root.Path })) {
        $path = ConvertTo-FaCanonicalPath ([string]$entry.path)
        if ($present.Contains($path)) { continue }
        if ([string]$entry.status -notin @('known', 'answered', 'new-waiting-on-krish')) { continue }
        if (@($tree.Unreadable | Where-Object { Test-FaPathWithin -Path $path -Root $_ }).Count -gt 0) { continue }
        $released = @($prefs.Data.consents | Where-Object {
            [string]$_.approved_by -eq 'Krish' -and $_.approved_at -and [string]$_.action -in @('move', 'delete') -and
            (ConvertTo-FaCanonicalPath ([string]$_.path)).Equals($path, [StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
        if ($released) {
            $entry.status = 'moved-with-ok'
            continue
        }
        Set-FaEntryValue $entry 'previous_status' ([string]$entry.status)
        $entry.status = 'missing'
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
        if ($prefs.ByPath.ContainsKey($path) -and [string]$prefs.ByPath[$path].status -eq 'missing') {
            $prefs.ByPath[$path].status = 'removed-by-krish'
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
    foreach ($entry in @($entries | Where-Object { [string]$_.status -eq 'missing' })) {
        $q = [Windows.Forms.MessageBox]::Show(
            "This folder was here before and is gone now:`n`n$($entry.path)`n`nDid you move or remove it yourself?",
            $title, 'YesNo', 'Warning')
        if ($q -eq 'Yes') { $entry.status = 'removed-by-krish' }
    }
}

# ---- 3. the number ---------------------------------------------------------
$withoutOk = @($goneThisRun | Where-Object { [string]$_.status -eq 'missing' })

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
$missingNow = @($entries | Where-Object { [string]$_.status -eq 'missing' } | Sort-Object { [string]$_.path })
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
        [void]$md.AppendLine(('| `{0}` | {1} |' -f (Format-FaCell $e.path), ([string]$e.missing_since).Substring(0, 10)))
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
