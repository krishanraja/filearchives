# The cloud steward reconciles Control Center's daily Drive export by key (fleet
# integration I-25). On made-up exports: a baseline, a rename, a move, a binned
# parent with its child (one event), a restore, a missing folder and its return,
# a repeated read, and a partial export that changes nothing. No id or name is ever
# written: the export carries none and the record holds keys and counts only.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repo 'stages' '09_mirror' 'reconcile_drive_tree.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-drive-tree-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$ids = Join-Path $scratch 'drive-ids.json'
$log = Join-Path $scratch 'DRIVE-LOG.jsonl'
$failures = 0
function Check([string] $What, [bool] $Ok) { if ($Ok) { Write-Host "ok    $What" } else { Write-Host "FAIL  $What"; $script:failures++ } }
function F([string] $Key, [string] $Parent, [hashtable] $More = @{}) {
    $f = [ordered]@{ key = $Key; parent_key = $Parent; depth = 1; trashed = $false; protected = $false; link_shared = $false; change_kind = $null; changed_at = $null; missing_since = $null; first_seen_at = '2026-11-13T06:00:00Z' }
    foreach ($k in $More.Keys) { $f[$k] = $More[$k] }
    $f
}
function Run([string] $AsOf, [object[]] $Folders, [bool] $Complete = $true) {
    $p = Join-Path $scratch "export-$([guid]::NewGuid().ToString('n')).json"
    $e = [ordered]@{ ok = $true; schema = 'drive-tree-export/1'; complete = $Complete; as_of = if ($Complete) { $AsOf } else { $null }; latest_partial = if ($Complete) { $null } else { @{ at = $AsOf; reason = 'deadline' } }; folders = $Folders }
    [IO.File]::WriteAllText($p, (([pscustomobject]$e) | ConvertTo-Json -Depth 8))
    & $script -ExportPath $p -IdsPath $ids -LogPath $log -Now $AsOf
    @(Get-Content -LiteralPath $log | ForEach-Object { $_ | ConvertFrom-Json -DateKind String })[-1]
}

try {
    $r1 = Run '2026-11-13T06:02:00Z' @((F 'v' $null), (F 'a' 'v'), (F 'b' 'v'), (F 'c' 'v'), (F 'c1' 'c'), (F 'd' 'v'), (F 'e' 'v' @{ trashed = $true }))
    Check 'the first read is a baseline: nothing counted as made' ($r1.baseline -and $r1.made -eq 0 -and $r1.folders -eq 7)

    $r2 = Run '2026-11-14T06:02:00Z' @(
        (F 'v' $null),
        (F 'a' 'v' @{ change_kind = 'renamed'; changed_at = '2026-11-14T06:01:00Z' }),
        (F 'b' 'a' @{ change_kind = 'moved'; changed_at = '2026-11-14T06:01:00Z' }),
        (F 'c' 'v' @{ trashed = $true; change_kind = 'binned'; changed_at = '2026-11-14T06:01:00Z' }),
        (F 'c1' 'c' @{ trashed = $true; change_kind = 'binned'; changed_at = '2026-11-14T06:01:00Z' }),
        (F 'd' 'v' @{ missing_since = '2026-11-14T06:01:00Z' }),
        (F 'e' 'v' @{ change_kind = 'restored'; changed_at = '2026-11-14T06:01:00Z' }),
        (F 'n' 'v'))
    Check 'a rename is one event' ($r2.renamed -eq 1)
    Check 'a move is one event' ($r2.moved -eq 1)
    Check 'a binned parent is one event with its child' ($r2.binned -eq 1)
    Check 'a restore is recorded' ($r2.restored -eq 1)
    Check 'a folder no longer found is missing, once' ($r2.missing -eq 1)
    Check 'a new folder is made' ($r2.made -eq 1 -and -not $r2.baseline)

    $r3 = Run '2026-11-14T06:02:00Z' @((F 'v' $null))
    Check 'the same read again counts nothing and keeps the record' ($r3.same_read -and ((Get-Content $ids -Raw | ConvertFrom-Json -DateKind String).folders.PSObject.Properties.Name.Count -eq 8))

    $before = Get-Content $ids -Raw
    $r4 = Run '2026-11-15T06:02:00Z' @() $false
    Check 'a partial export is unknown: one row, no counts, the record untouched' (-not $r4.complete -and $r4.reason -eq 'deadline' -and -not ($r4.PSObject.Properties.Name -contains 'made') -and ((Get-Content $ids -Raw) -eq $before))

    $r5 = Run '2026-11-16T06:02:00Z' @((F 'v' $null), (F 'a' 'v' @{ change_kind = 'renamed'; changed_at = '2026-11-14T06:01:00Z' }), (F 'd' 'v'))
    Check 'an old change is not counted twice, and a missing folder that is back is returned' ($r5.renamed -eq 0 -and $r5.returned -eq 1)

    $record = Get-Content $ids -Raw
    Check 'the record holds keys and counts only: no Drive-id-shaped string' (-not ($record -match '[A-Za-z0-9_-]{25,}'))
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failures) { throw "$failures check(s) failed" }
Write-Host 'reconcile_drive_tree: all checks passed'
