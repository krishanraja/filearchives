<#
    Record the folder tree as it stands now as Krish's preference for where
    everything goes. Folder names only: no file is opened, listed or moved.

        pwsh -NoProfile -File stages\07_structure\record_folder_preferences.ps1

    Krish presses RECORD-MY-FOLDERS.cmd rather than running this by hand.

    Every folder present now becomes 'known', including any that were waiting
    on him: pressing the button is his statement that the drive is the way he
    wants it. His earlier answers and consents are kept. A watched root that is
    not mounted keeps its earlier record untouched; absent is not empty.
#>
[CmdletBinding()]
param(
    [string] $PreferencesPath,
    [datetimeoffset] $AsOf = [DateTimeOffset]::Now
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards' 'workspace.ps1')
. (Join-Path $repo 'guards' 'atomic.ps1')
. (Join-Path $repo 'guards' 'folder_consent.ps1')

$prefs = Import-FaFolderPreferences -Path $PreferencesPath
$stamp = $AsOf.ToString('o')
$kept = [Collections.Generic.List[object]]::new()
$summary = [Collections.Generic.List[object]]::new()
$unavailable = [Collections.Generic.List[string]]::new()

foreach ($root in $prefs.WatchRoots) {
    $previous = @($prefs.Data.folders | Where-Object {
        Test-FaPathWithin -Path ([string]$_.path) -Root $root.Path
    })
    if (-not (Test-Path -LiteralPath $root.Path -PathType Container)) {
        $unavailable.Add($root.Path)
        foreach ($entry in $previous) { $kept.Add($entry) }
        $summary.Add([pscustomobject]@{ Root = $root.Path; Mounted = $false; Folders = $previous.Count; NoLongerPresent = 0 })
        continue
    }
    $tree = Get-FaFolderTree -Root $root.Path -MaxDepth $root.MaxDepth `
        -NeverEnter $prefs.NeverEnter -SkipNames $prefs.SkipNames
    $present = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($folder in $tree.Folders) {
        $null = $present.Add($folder)
        $entry = if ($prefs.ByPath.ContainsKey($folder)) { $prefs.ByPath[$folder] } else { $null }
        if ($entry) {
            if ([string]$entry.status -ne 'answered') { $entry.status = 'known' }
            $kept.Add($entry)
        } else {
            $kept.Add([pscustomobject][ordered]@{ path = $folder; status = 'known'; since = $stamp })
        }
    }
    # Unreadable folders keep whatever they were; an unreadable folder is not a gone folder.
    $gone = 0
    foreach ($entry in $previous) {
        $path = ConvertTo-FaCanonicalPath ([string]$entry.path)
        if ($present.Contains($path)) { continue }
        if (@($tree.Unreadable | Where-Object { Test-FaPathWithin -Path $path -Root $_ }).Count -gt 0) {
            $kept.Add($entry)
            continue
        }
        $gone++
    }
    $summary.Add([pscustomobject]@{
        Root = $root.Path; Mounted = $true; Folders = $tree.Folders.Count
        NoLongerPresent = $gone; Unreadable = @($tree.Unreadable)
    })
}

if ($summary.Where({ $_.Mounted }).Count -eq 0) {
    Write-Host 'STOPPED: no watched drive is mounted, so nothing was recorded.'
    exit 3
}
$prefs.Data.folders = @($kept)
$prefs.Data.recorded_at = $stamp
$prefs.Data.recorded_on = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [Environment]::MachineName }
Write-FaFolderPreferences -Preferences $prefs

foreach ($row in $summary) {
    if ($row.Mounted) {
        Write-Host ("recorded {0}: {1} folders" -f $row.Root, $row.Folders)
    } else {
        Write-Host ("not mounted, earlier record kept: {0}" -f $row.Root)
    }
}
Write-Host "preferences: $($prefs.Path)"
Write-Host 'Nothing was moved, renamed or deleted, and no file was opened.'
