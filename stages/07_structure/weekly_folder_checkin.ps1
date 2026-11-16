<#
    The weekly folder check-in. It looks and asks; it never moves, renames or
    deletes anything.

        pwsh -NoProfile -File stages\07_structure\weekly_folder_checkin.ps1 -Interactive

    Krish never runs this by hand: the weekly scheduled task does, and so does
    CHECK-MY-NEW-FOLDERS.cmd.

    1. Every folder that is not in Krish's record becomes 'new-waiting-on-krish'
       and is left exactly where he put it. Nothing inside it moves until he
       answers for it, whether or not he is ever asked.
    2. It asks only what it cannot work out, and never the same thing twice
       (Ruling, Krish, 2026-11-16):
       - a folder that moved is one move, not one folder gone plus one new: its
         new place keeps his record and is never asked about. It is found by
         its Drive id or, with no id, by its name and the folders inside it;
       - a new folder inside a folder he already has is worked out from its
         name and where it sits (Immigration\10_passports_and_identity is
         "passports and identity, in Immigration"), listed in LATEST.md and not
         asked about;
       - only a new folder at the top of a drive gets a question: one, with a
         guess in the box, asked once;
       - folders that moved or went get one question for the run, "did you OK
         these?", where an AI session he asked counts as him; "No" asks about
         each one, once.
       Unattended, his written answers in docs/folder-checkin/answers.json.
    3. A recorded folder that has gone without a consent row is counted. That
       count is the North Star number: folders moved or removed without
       Krish's OK. If he says he OK'd it, it is not counted.
    4. Each folder he has answered for gets a cleanliness check against what he
       said goes in it: counts only, no file names leave his machine.

    Only true losses are counted:
    - A consent row for a folder also covers every recorded folder beneath it.
    - A recorded folder whose Drive id now sits at another path (read from the
      drive-paths.json that content-engine's sync writes on each home computer),
      or that arrived elsewhere with the same name and folders inside, is
      recorded as moved, with where it went, and its new path is not a new
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
    [string] $DeclaredMapsPath,
    [hashtable] $DeclaredMapTexts,
    [switch] $Interactive,
    # A test stands in for Krish here: & $Ask <kind> <text> <default> returns what
    # he would press or type. Kinds: 'gone-all' and 'gone-one' (Yes or No), and
    # 'what-goes-in' (his text, or empty for Cancel).
    [scriptblock] $Ask,
    [int] $MaxQuestions = 10,
    [datetimeoffset] $AsOf = [DateTimeOffset]::Now
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards' 'workspace.ps1')
. (Join-Path $repo 'guards' 'atomic.ps1')
. (Join-Path $repo 'guards' 'folder_consent.ps1')
. (Join-Path $repo 'guards' 'declared_folders.ps1')
if (-not $ReportRoot) { $ReportRoot = Join-Path $repo 'docs' 'folder-checkin' }
if (-not $AnswersPath) { $AnswersPath = Join-Path $ReportRoot 'answers.json' }
if (-not $NowPath) { $NowPath = Join-Path $repo 'NOW.md' }
if (-not $DeclaredMapsPath) { $DeclaredMapsPath = Join-Path $repo 'policy' 'declared-maps.json' }
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
$wentThisRun = [Collections.Generic.List[object]]::new()
$restoredThisRun = [Collections.Generic.List[object]]::new()
$newThisRun = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$linkedThisRun = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Get-FaDepth([string] $Path) { return @(Get-FaPathSegments $Path).Count }

function Move-FaRecord {
    # Same folder, new place: one move, not one folder gone plus one new. The new
    # place keeps his record, so it is never asked about. An answer that only
    # said "part of" the old parent does not travel; the folder is then known.
    param($Entry, [string] $To)
    $from = ConvertTo-FaCanonicalPath ([string]$Entry.path)
    Set-FaEntryValue $Entry 'moved_to' $To
    Set-FaEntryValue $Entry 'moved_seen_at' $stamp
    $null = $linkedThisRun.Add($from)
    if (-not ($prefs.ByPath.ContainsKey($To) -and $newThisRun.Contains($To))) { return }
    $arrived = $prefs.ByPath[$To]
    $was = [string](Get-FaEntryValue $Entry 'previous_status')
    if (-not $was) { $was = 'known' }
    if ($was -eq 'answered' -and ([string](Get-FaEntryValue $Entry 'purpose')).StartsWith('part of ')) { $was = 'known' }
    $arrived.status = $was
    if ($was -eq 'answered') {
        foreach ($k in @('important', 'purpose', 'answered_at', 'answered_by')) { Set-FaEntryValue $arrived $k (Get-FaEntryValue $Entry $k) }
    }
    if ($was -eq 'new-waiting-on-krish') { $arrived.first_seen = Get-FaEntryValue $Entry 'first_seen' }
    Set-FaEntryValue $arrived 'moved_from' $from
    $null = $newThisRun.Remove($To)
}
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
        # A folder that went before, came back and went again is a new event.
        foreach ($k in @('moved_to', 'asked_at')) { if (Get-FaEntryValue $entry $k) { Set-FaEntryValue $entry $k $null } }
        $wentThisRun.Add($entry)
        if ($movedTo) { Move-FaRecord -Entry $entry -To $movedTo }
        if (Test-FaReleasedByKrish -Path $path) {
            $entry.status = 'moved-with-ok'
            continue
        }
        $entry.status = if ($movedTo) { 'moved' } else { 'missing' }
        Set-FaEntryValue $entry 'missing_since' $stamp
        $goneThisRun.Add($entry)
    }
}

# ---- 1b. a move with no Drive id -----------------------------------------------
# A folder that went and a folder that arrived are the same folder when they
# have the same name and the same folders inside (as deep as both can be seen),
# or when it was renamed where it stands and kept the folders inside it. Only a
# one-to-one match counts; anything ambiguous stays gone plus new, as before.
$sep = [IO.Path]::DirectorySeparatorChar
function Test-FaUnder([string] $Path, [string] $Root) {
    return $Path.StartsWith($Root.TrimEnd($sep) + $sep, [StringComparison]::OrdinalIgnoreCase)
}
function Get-FaLevelsBelow([string] $Path) {
    $root = Get-FaWatchRoot -Path $Path -Preferences $prefs
    if (-not $root) { return 0 }
    return $root.MaxDepth - (Get-FaRelativeDepth -Path $Path -Root $root.Path)
}
function Get-FaShape([string] $Top, $Paths, [int] $Levels) {
    $rows = foreach ($p in @($Paths)) {
        if (-not (Test-FaUnder $p $Top)) { continue }
        $rel = @(Get-FaPathSegments $p.Substring($Top.Length))
        if ($rel.Count -le $Levels) { ($rel -join '/').ToLowerInvariant() }
    }
    return (@($rows | Sort-Object) -join '|')
}
function Get-FaWentOpen {
    return @($wentThisRun | ForEach-Object { ConvertTo-FaCanonicalPath ([string]$_.path) } | Where-Object { -not $linkedThisRun.Contains($_) })
}
function Test-FaSameFolder([string] $Gone, [string] $Arrived) {
    $sameName = (Split-Path -Leaf $Gone).Equals((Split-Path -Leaf $Arrived), [StringComparison]::OrdinalIgnoreCase)
    $renamedHere = (Split-Path -Parent $Gone).Equals((Split-Path -Parent $Arrived), [StringComparison]::OrdinalIgnoreCase)
    if (-not $sameName -and -not $renamedHere) { return $false }
    $levels = [Math]::Min((Get-FaLevelsBelow $Gone), (Get-FaLevelsBelow $Arrived))
    $shape = Get-FaShape $Gone (Get-FaWentOpen) $levels
    # A rename is proven only by the folders it kept inside it.
    if (-not $sameName -and -not $shape) { return $false }
    return $shape -eq (Get-FaShape $Arrived @($newThisRun) $levels)
}
$byShape = 0
foreach ($g in @($wentThisRun | Sort-Object { Get-FaDepth ([string]$_.path) }, { [string]$_.path })) {
    $gone = ConvertTo-FaCanonicalPath ([string]$g.path)
    if ($linkedThisRun.Contains($gone)) { continue }
    $fits = @(@($newThisRun) | Where-Object { Test-FaSameFolder $gone $_ })
    if ($fits.Count -ne 1) { continue }
    $arrived = $fits[0]
    $rivals = @(Get-FaWentOpen | Where-Object { Test-FaSameFolder $_ $arrived })
    if ($rivals.Count -ne 1) { continue }
    # Link it and every folder that went from inside it to the same place inside the arrival.
    foreach ($d in @($wentThisRun | Where-Object {
        $p = ConvertTo-FaCanonicalPath ([string]$_.path)
        $p.Equals($gone, [StringComparison]::OrdinalIgnoreCase) -or (Test-FaUnder $p $gone)
    } | Sort-Object { Get-FaDepth ([string]$_.path) })) {
        $dPath = ConvertTo-FaCanonicalPath ([string]$d.path)
        if ($linkedThisRun.Contains($dPath)) { continue }
        $to = $arrived + $dPath.Substring($gone.Length)
        if (-not $newThisRun.Contains($to)) { continue }
        Move-FaRecord -Entry $d -To $to
        if ([string]$d.status -eq 'missing') { $d.status = 'moved' }
        $byShape++
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

# A waiting folder inside a folder a growth engine declares is known without asking
# (Ruling, Krish, 2026-11-14). Only a declared folder already in his record counts.
$declared = Resolve-FaDeclaredFolders -Roots (Get-FaDeclaredRoots -MapsPath $DeclaredMapsPath -Texts $DeclaredMapTexts) -Preferences $prefs
foreach ($d in $declared) {
    foreach ($e in @($entries | Where-Object {
        [string]$_.status -eq 'new-waiting-on-krish' -and (Test-FaPathWithin -Path ([string]$_.path) -Root $d.path)
    })) {
        $e.status = 'answered'
        $e.important = $true
        $e.purpose = "Declared by $($d.engine) in its Drive map ($($d.drive_path)); known without asking (Ruling, Krish, 2026-11-14)."
        $e.answered_at = $stamp
        Set-FaEntryValue $e 'answered_by' 'declared'
    }
}

# ---- 2b. work out what is obvious ----------------------------------------------
# A new folder inside a folder he already has says what it is by its name and
# where it sits. It is worked out, not asked about (Ruling, Krish, 2026-11-16).
# It stays 'new-waiting-on-krish', so nothing inside it moves until he answers.
function Get-FaReadableName([string] $Path) {
    $name = Split-Path -Leaf $Path
    $readable = (($name -replace '^\d+[\s_.-]+', '') -replace '_+', ' ').Trim()
    if ($readable) { return $readable }
    return $name
}
function Test-FaWatchRoot([string] $Path) {
    return @($prefs.WatchRoots | Where-Object { $_.Path.Equals($Path, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
}
$workedOutThisRun = [Collections.Generic.List[object]]::new()
function Set-FaWorkedOut {
    foreach ($e in @($entries | Where-Object {
        [string]$_.status -eq 'new-waiting-on-krish' -and -not (Get-FaEntryValue $_ 'worked_out')
    } | Sort-Object { Get-FaDepth ([string]$_.path) }, { [string]$_.path })) {
        $path = ConvertTo-FaCanonicalPath ([string]$e.path)
        $parent = ConvertTo-FaCanonicalPath (Split-Path -Parent $path)
        # A new folder at the top of a drive changes his layout: that one is asked.
        if ((Test-FaWatchRoot $parent) -or -not $prefs.ByPath.ContainsKey($parent)) { continue }
        $p = $prefs.ByPath[$parent]
        $ps = [string]$p.status
        if ($ps -notin @('known', 'answered') -and -not ($ps -eq 'new-waiting-on-krish' -and (Get-FaEntryValue $p 'worked_out'))) { continue }
        $text = '{0}, in {1}' -f (Get-FaReadableName $path), (Split-Path -Leaf $parent)
        # His own short answer for the parent says more than its name ("Dipti (my sisters health records)").
        $said = ([string](Get-FaEntryValue $p 'purpose')).Trim()
        if ($ps -eq 'answered' -and $said -and $said.Length -le 60 -and -not $said.StartsWith('part of ')) { $text += ' ({0})' -f $said }
        Set-FaEntryValue $e 'worked_out' $text
        Set-FaEntryValue $e 'worked_out_at' $stamp
        $workedOutThisRun.Add($e)
    }
}
Set-FaWorkedOut

# ---- 2c. ask what is left, once --------------------------------------------------
function Get-FaGoneGroups {
    # Folders that moved or went and that he has not been asked about, one group
    # per topmost folder. A folder never found anywhere comes first.
    $gone = @($entries | Where-Object { [string]$_.status -in @('missing', 'moved') -and -not (Get-FaEntryValue $_ 'asked_at') })
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $gone) { $null = $paths.Add((ConvertTo-FaCanonicalPath ([string]$e.path))) }
    $groups = foreach ($top in @($gone | Where-Object {
        -not $paths.Contains((ConvertTo-FaCanonicalPath (Split-Path -Parent ([string]$_.path))))
    })) {
        $topPath = ConvertTo-FaCanonicalPath ([string]$top.path)
        $members = @($gone | Where-Object {
            $p = ConvertTo-FaCanonicalPath ([string]$_.path)
            $p.Equals($topPath, [StringComparison]::OrdinalIgnoreCase) -or (Test-FaUnder $p $topPath)
        })
        $line = Get-FaGoneLine -Top $top -Members $members
        [pscustomobject]@{ Top = $topPath; Members = $members; Line = $line.Text; Lost = $line.Lost }
    }
    return @($groups | Sort-Object { -not $_.Lost }, { $_.Top })
}
function Get-FaGoneLine {
    param($Top, $Members)
    $topPath = [string]$Top.path
    $inside = $Members.Count - 1
    $with = if ($inside -eq 1) { ' (and the folder inside it)' } elseif ($inside -gt 1) { " (and the $inside folders inside it)" } else { '' }
    if ([string]$Top.status -eq 'moved') {
        $to = [string](Get-FaEntryValue $Top 'moved_to')
        if ((Split-Path -Parent $to).Equals((Split-Path -Parent $topPath), [StringComparison]::OrdinalIgnoreCase)) {
            return @{ Lost = $false; Text = '{0}{1}: renamed to {2}' -f $topPath, $with, (Split-Path -Leaf $to) }
        }
        return @{ Lost = $false; Text = '{0}{1}: moved to {2}' -f $topPath, $with, $to }
    }
    $moved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in @($Members | Where-Object { [string]$_.status -eq 'moved' })) { $null = $moved.Add((ConvertTo-FaCanonicalPath ([string]$m.path))) }
    $dests = @($Members | Where-Object {
        [string]$_.status -eq 'moved' -and -not $moved.Contains((ConvertTo-FaCanonicalPath (Split-Path -Parent ([string]$_.path))))
    } | ForEach-Object { Split-Path -Parent ([string](Get-FaEntryValue $_ 'moved_to')) } | Sort-Object -Unique)
    if ($dests.Count -gt 0) {
        $more = if ($dests.Count -gt 1) { ' and {0} other places' -f ($dests.Count - 1) } else { '' }
        return @{ Lost = $false; Text = '{0}{1}: what was inside it moved to {2}{3}, then it went' -f $topPath, $with, $dests[0], $more }
    }
    return @{ Lost = $true; Text = '{0}{1}: gone, and not found anywhere in your drives' -f $topPath, $with }
}

$canAsk = [bool]$Ask -or ($Interactive -and $IsWindows -and [Environment]::UserInteractive)
$title = 'filearchives weekly folder check-in'
$popups = 0
function Invoke-FaAsk([string] $Kind, [string] $Text, [string] $Default) {
    $script:popups++
    if ($Ask) { return [string](& $Ask $Kind $Text $Default) }
    if ($Kind -eq 'what-goes-in') { return [string][Microsoft.VisualBasic.Interaction]::InputBox($Text, $title, $Default) }
    $icon = if ($Kind -eq 'gone-one') { 'Warning' } else { 'Question' }
    return [string][Windows.Forms.MessageBox]::Show($Text, $title, 'YesNo', $icon)
}
$okWho = 'Yes if you did it yourself, or an AI session you asked did it.'
if ($canAsk) {
    if (-not $Ask) {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName Microsoft.VisualBasic
    }
    # Folders that moved or went: one question for all of them.
    $groups = @(Get-FaGoneGroups)
    if ($groups.Count -gt 0) {
        $shown = @($groups | Select-Object -First 8 | ForEach-Object { '- ' + $_.Line })
        $rest = if ($groups.Count -gt $shown.Count) { "`n- and {0} more, listed in LATEST.md" -f ($groups.Count - $shown.Count) } else { '' }
        $all = Invoke-FaAsk 'gone-all' ("Since the last check-in these folders of yours moved or went. filearchives moved none of them.`n`n{0}{1}`n`nDid you OK these? {2}`nNo: I will ask about each one, once." -f ($shown -join "`n"), $rest, $okWho) ''
        foreach ($grp in $groups) {
            $ok = $all -eq 'Yes'
            if (-not $ok) { $ok = (Invoke-FaAsk 'gone-one' ("{0}`n`nDid you OK this? {1}" -f $grp.Line, $okWho) '') -eq 'Yes' }
            foreach ($m in $grp.Members) {
                Set-FaEntryValue $m 'asked_at' $stamp
                if ($ok) { $m.status = 'removed-by-krish'; Set-FaEntryValue $m 'ok_by' 'pop-up' }
            }
        }
    }
    # A new folder at the top of a drive: one question, with a guess in the box.
    $asked = 0
    foreach ($entry in @($entries | Where-Object {
        [string]$_.status -eq 'new-waiting-on-krish' -and -not (Get-FaEntryValue $_ 'worked_out') -and
        (Test-FaWatchRoot (ConvertTo-FaCanonicalPath (Split-Path -Parent ([string]$_.path))))
    } | Sort-Object { [string]$_.path })) {
        if ([string]$entry.status -ne 'new-waiting-on-krish') { continue }
        if ($asked -ge $MaxQuestions) { break }
        $asked++
        $guess = Get-FaReadableName ([string]$entry.path)
        $typed = Invoke-FaAsk 'what-goes-in' ("A new folder at the top of your drive:`n`n{0}`n`nWhat goes in it? My guess is in the box. OK keeps what is in the box, Cancel keeps my guess, and you will not be asked about it again. Nothing is moved either way." -f $entry.path) $guess
        if ($typed.Trim()) { Set-FaAnswer -Entry $entry -Important $true -Purpose $typed.Trim() -How 'pop-up' }
        else {
            Set-FaEntryValue $entry 'worked_out' $guess
            Set-FaEntryValue $entry 'worked_out_at' $stamp
            $workedOutThisRun.Add($entry)
        }
    }
    # What sits inside a folder he has just answered or left to the guess.
    Set-FaWorkedOut
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
# Waiting folders that have no worked-out answer: the only ones still open to a question.
$toAskNow = @($waitingNow | Where-Object { -not (Get-FaEntryValue $_ 'worked_out') })
$workedOutNow = @($workedOutThisRun | Where-Object { [string]$_.status -eq 'new-waiting-on-krish' } | Sort-Object { [string]$_.path })
$movesFound = @($entries | Where-Object { [string](Get-FaEntryValue $_ 'moved_seen_at') -eq $stamp -and (Get-FaEntryValue $_ 'moved_to') } |
    Sort-Object { [string]$_.path })
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
[void]$md.AppendLine("## New folders at the top of a drive, waiting on you ($($toAskNow.Count))")
[void]$md.AppendLine()
if ($toAskNow.Count -eq 0) { [void]$md.AppendLine('None.') } else {
    [void]$md.AppendLine('Each stays exactly where you put it. One question each, asked once: what goes in it?')
    [void]$md.AppendLine()
    [void]$md.AppendLine('| Folder | First seen |')
    [void]$md.AppendLine('|---|---|')
    foreach ($e in $toAskNow) {
        [void]$md.AppendLine(('| `{0}` | {1} |' -f (Format-FaCell $e.path), ([string]$e.first_seen).Substring(0, 10)))
    }
}
[void]$md.AppendLine()
[void]$md.AppendLine("## New folders worked out from their name and where they sit ($($workedOutNow.Count))")
[void]$md.AppendLine()
if ($workedOutNow.Count -eq 0) { [void]$md.AppendLine('None this time.') } else {
    [void]$md.AppendLine('Not asked about. Nothing inside them moves until you say what goes in them; if a guess is wrong, put your answer in `docs/folder-checkin/answers.json` or tell any Claude session.')
    [void]$md.AppendLine()
    [void]$md.AppendLine('| Folder | Taken as |')
    [void]$md.AppendLine('|---|---|')
    foreach ($e in $workedOutNow) {
        [void]$md.AppendLine(('| `{0}` | {1} |' -f (Format-FaCell $e.path), (Format-FaCell ([string](Get-FaEntryValue $e 'worked_out')))))
    }
}
if ($movesFound.Count -gt 0) {
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Moves found this time ($($movesFound.Count))")
    [void]$md.AppendLine()
    [void]$md.AppendLine('Each new place keeps what the old place had in your record, so it is not asked about as new.')
    [void]$md.AppendLine()
    foreach ($e in $movesFound) {
        [void]$md.AppendLine(('- `{0}` to `{1}`' -f (Format-FaCell $e.path), (Format-FaCell ([string](Get-FaEntryValue $e 'moved_to')))))
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
    [void]$md.AppendLine('This run could not ask you, so these count until you say. If you OK''d one (you did it, or an AI session you asked did), add its path to `removed_by_krish` in `docs/folder-checkin/answers.json`; that covers the folders inside it too.')
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
[void]$md.AppendLine('Edit `docs/folder-checkin/answers.json` on GitHub, or ask any Claude session to do it for you. An AI session that moves or removes a folder because you asked it to can add the old path to `removed_by_krish` there in the same change, and you are not asked about it. Answering "not important" never moves or deletes the folder: that needs your yes for that folder, recorded in `policy/folder-preferences.json` under `consents`.')
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
    new_folders_to_ask = $toAskNow.Count
    worked_out = $workedOutNow.Count
    moves_found = $movesFound.Count
    moves_found_by_shape = $byShape
    popups = $popups
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

Write-Host ("folder check-in {0}: new waiting={1} (to ask={2}, worked out={3}) moves found={4} gone without OK={5} answered folders checked={6} pop-ups={7}" -f
    $day, $waitingNow.Count, $toAskNow.Count, $workedOutNow.Count, $movesFound.Count, $withoutOk.Count, $clean.Count, $popups)
Write-Host 'Nothing was moved, renamed or deleted.'
