# Ruling (Krish, 2026-11-14): a folder inside a folder a growth engine declares in
# its Drive map is known without asking. On a fixture drive: a new folder inside a
# declared engine folder (whose Drive name holds a slash, "mind/make", shown as
# "mind make" on the PC) is answered as declared; a new folder elsewhere still
# waits on Krish; a map that cannot be read declares nothing; a declared path
# that matches no recorded folder is never guessed into one. Nothing moves.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$structure = Join-Path $repo 'stages' '07_structure'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-declared-' + [guid]::NewGuid().ToString('n'))
$drive = Join-Path $scratch 'My Drive'
$prefsPath = Join-Path $scratch 'folder-preferences.json'
$reportRoot = Join-Path $scratch 'folder-checkin'
$nowPath = Join-Path $scratch 'NOW.md'
$savedPrefsEnv = $env:FILEARCHIVES_FOLDER_PREFERENCES
function D([string] $Rel) { Join-Path $drive $Rel }
function Get-Entry([string] $Path) {
    @((Get-Content -LiteralPath $prefsPath -Raw | ConvertFrom-Json -Depth 32).folders | Where-Object { $_.path -eq $Path }) | Select-Object -First 1
}
$map = @{ 'growth-mindmake' = '{"root":"03_Growth","drive_map":{"schema":"drive-map/1","roots":[{"path":"Ventures/Active Ventures/mind/make/03_Growth"}]}}'
          'growth-legibility' = 'not json'
          'growth-heartside' = '{"drive_map":{"schema":"drive-map/1","roots":[{"path":"Ventures/Active Ventures/Nowhere"}]}}' }
try {
    foreach ($d in @('Ventures/Active Ventures/mind make/03_Growth', 'Ventures/Other')) { New-Item -ItemType Directory -Path (D $d) -Force | Out-Null }
    $seed = Get-Content -LiteralPath (Join-Path $repo 'policy' 'folder-preferences.json') -Raw | ConvertFrom-Json -Depth 16
    $seed.watch_roots = @(@{ path = $drive; max_depth = 6 })
    $seed.never_enter = @(); $seed.folders = @(); $seed.consents = @(); $seed.recorded_at = $null
    [IO.File]::WriteAllText($prefsPath, ($seed | ConvertTo-Json -Depth 16))
    $env:FILEARCHIVES_FOLDER_PREFERENCES = $prefsPath
    [IO.File]::WriteAllText($nowPath, "## Where it is right now`n`n<!-- north-star-state {`"week_of`": `"2026-11-09`", `"week_target`": 0, `"current`": null, `"current_as_of`": null, `"current_source`": null, `"urgency`": 1} --> **North Star number**`n")
    & (Join-Path $structure 'record_folder_preferences.ps1')

    New-Item -ItemType Directory -Path (D 'Ventures/Active Ventures/mind make/03_Growth/Week specs') -Force | Out-Null
    New-Item -ItemType Directory -Path (D 'Ventures/Other/Mine') -Force | Out-Null
    & (Join-Path $structure 'weekly_folder_checkin.ps1') -ReportRoot $reportRoot -NowPath $nowPath -DeclaredMapTexts $map

    $inside = Get-Entry (D 'Ventures/Active Ventures/mind make/03_Growth/Week specs')
    if ($inside.status -ne 'answered' -or $inside.answered_by -ne 'declared' -or $inside.purpose -notmatch 'growth-mindmake') { throw 'a new folder inside a declared folder was not known without asking' }
    if ((Get-Entry (D 'Ventures/Other/Mine')).status -ne 'new-waiting-on-krish') { throw 'a folder outside every declared folder stopped waiting on Krish' }
    if (Get-Entry (D 'Ventures/Active Ventures/Nowhere')) { throw 'a declared path that matches no folder was invented' }
    foreach ($d in @('Ventures/Active Ventures/mind make/03_Growth/Week specs', 'Ventures/Other/Mine')) { if (-not (Test-Path -LiteralPath (D $d))) { throw "$d was moved" } }
    $log = @(Get-Content -LiteralPath (Join-Path $reportRoot 'LOG.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })[-1]
    if ($log.new_folders_waiting -ne 1) { throw "expected 1 folder waiting on Krish, got $($log.new_folders_waiting)" }
    Write-Host 'PASS: a folder inside a declared engine folder is known without asking; everything else still waits on Krish'
} finally {
    $env:FILEARCHIVES_FOLDER_PREFERENCES = $savedPrefsEnv
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
