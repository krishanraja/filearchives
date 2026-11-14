# The cloud half of filearchives (fleet integration I-25; Ruling, Krish, 2026-11-14:
# Control Center reads folder names and file titles, never contents, under Ventures
# once a day). Control Center's daily read of his Drive is exported as
# drive-tree-export/1: each folder an opaque key (an HMAC of its Drive id), its
# parent's key, its depth, binned or not, shared by link or not, and its last change.
# This reconciles that export with the cloud record by key, so a rename or a move is
# one event, a binned parent is one event with its descendants, and a restore is
# recorded. It writes policy/drive-ids.json and appends one row to
# docs/folder-checkin/DRIVE-LOG.jsonl.
#
# This repository is public: no Drive id and no name is ever written, only keys and
# counts. A partial export (no complete read) is unknown: one row saying so, and the
# record is left exactly as it was. Nothing in his Drive is moved, renamed, merged or
# deleted; this reads a file and writes two.
param(
    [Parameter(Mandatory)] [string] $ExportPath,
    [string] $IdsPath,
    [string] $LogPath,
    [string] $Now
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $IdsPath) { $IdsPath = Join-Path $repo 'policy' 'drive-ids.json' }
if (-not $LogPath) { $LogPath = Join-Path $repo 'docs' 'folder-checkin' 'DRIVE-LOG.jsonl' }
$checkedAt = if ($Now) { $Now } else { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

function Add-LogRow([hashtable] $Row) {
    $dir = Split-Path -Parent $LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $line = ([pscustomobject]$Row | ConvertTo-Json -Compress -Depth 4)
    [IO.File]::AppendAllText($LogPath, $line + "`n")
}
function Write-Atomic([string] $Path, [string] $Text) {
    $tmp = "$Path.tmp-$([guid]::NewGuid().ToString('n'))"
    [IO.File]::WriteAllText($tmp, $Text)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Prop($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value } else { return $null }
}

$export = Get-Content -LiteralPath $ExportPath -Raw | ConvertFrom-Json -Depth 16 -DateKind String
if ((Prop $export 'schema') -ne 'drive-tree-export/1') { throw 'drive_tree_export_unrecognised' }
$partial = Prop $export 'latest_partial'
if (-not (Prop $export 'complete')) {
    Add-LogRow ([ordered]@{ checked_at = $checkedAt; complete = $false; reason = if ($partial) { "$((Prop $partial 'reason'))" } else { 'no_complete_read' } })
    return
}

$asOf = "$((Prop $export 'as_of'))"
$prev = $null
if (Test-Path -LiteralPath $IdsPath) { $prev = Get-Content -LiteralPath $IdsPath -Raw | ConvertFrom-Json -Depth 16 -DateKind String }
$prevAsOf = "$((Prop $prev 'as_of'))"
if ($prev -and $prevAsOf -and ([datetime]$asOf) -le ([datetime]$prevAsOf)) {
    Add-LogRow ([ordered]@{ checked_at = $checkedAt; complete = $true; as_of = $asOf; same_read = $true })
    return
}
$known = @{}
if ($prev) { foreach ($p in (Prop $prev 'folders').PSObject.Properties) { $known[$p.Name] = $p.Value } }
$baseline = -not $prev

$counts = [ordered]@{ made = 0; renamed = 0; moved = 0; binned = 0; restored = 0; missing = 0; returned = 0 }
$newlyBinned = @{}
foreach ($f in $export.folders) {
    $old = $known[$f.key]
    if ($old -and $old.status -ne 'binned' -and $f.trashed) { $newlyBinned[$f.key] = $true }
}
$record = [ordered]@{}
foreach ($f in ($export.folders | Sort-Object key)) {
    $old = $known[$f.key]
    $status = if ($f.missing_since) { 'missing' } elseif ($f.trashed) { 'binned' } else { 'present' }
    $lastChange = $null
    if ($old) { $lastChange = Prop $old 'last_change_at' }
    if (-not $old) {
        if (-not $baseline) { $counts.made++ }
    } else {
        $changed = $f.changed_at -and (-not $lastChange -or ([datetime]$f.changed_at) -gt ([datetime]$lastChange))
        if ($changed -and $f.change_kind -in @('renamed', 'renamed_and_moved')) { $counts.renamed++ }
        if ($changed -and $f.change_kind -in @('moved', 'renamed_and_moved')) { $counts.moved++ }
        if ($newlyBinned.ContainsKey($f.key) -and -not ($f.parent_key -and $newlyBinned.ContainsKey($f.parent_key))) { $counts.binned++ }
        if ($old.status -eq 'binned' -and -not $f.trashed -and -not $f.missing_since) { $counts.restored++ }
        if ($old.status -ne 'missing' -and $f.missing_since) { $counts.missing++ }
        if ($old.status -eq 'missing' -and -not $f.missing_since) { $counts.returned++ }
    }
    $record[$f.key] = [ordered]@{
        parent_key = $f.parent_key; depth = $f.depth; status = $status; protected = [bool]$f.protected; link_shared = [bool]$f.link_shared
        first_seen = if ($old) { $old.first_seen } else { $asOf }
        last_change_at = if ($f.changed_at) { $f.changed_at } else { $lastChange }
    }
}
$out = [ordered]@{
    schema = 'drive-ids/1'
    about = 'The cloud record of the folders under Ventures, by opaque key (never a Drive id or a name: this repository is public). Written by stages/09_mirror/reconcile_drive_tree.ps1 from Control Center''s daily read (fleet integration I-25).'
    as_of = $asOf
    folders = $record
}
Write-Atomic $IdsPath (([pscustomobject]$out) | ConvertTo-Json -Depth 8)
$row = [ordered]@{ checked_at = $checkedAt; complete = $true; as_of = $asOf; baseline = $baseline; folders = $record.Count }
foreach ($k in $counts.Keys) { $row[$k] = $counts[$k] }
$row.link_shared = @($record.Values | Where-Object { $_.link_shared -and $_.status -eq 'present' }).Count
if ($partial) { $row.latest_read_partial = $true }
Add-LogRow $row
