# Ruling (Krish, 2026-10-23): filearchives never moves a folder Krish made
# without asking first. This proves it against every engine path that can
# move or remove a folder, on a fixture drive, and proves the per-folder yes
# is the only way through.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$structure = Join-Path $repo 'stages' '07_structure'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-new-folder-' + [guid]::NewGuid().ToString('n'))
$drive = Join-Path $scratch 'My Drive'
$audit = Join-Path $scratch 'audit'
$config = Join-Path $scratch 'workspace.json'
$prefsPath = Join-Path $scratch 'folder-preferences.json'
$reportRoot = Join-Path $scratch 'folder-checkin'
$nowPath = Join-Path $scratch 'NOW.md'
$savedPrefsEnv = $env:FILEARCHIVES_FOLDER_PREFERENCES

function Get-TreeSeal {
    param([string] $Root)
    $rows = @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($Root.Length)
        if ($_.PSIsContainer) { "D|$rel" }
        else { "F|$rel|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
    })
    return [string]::Join("`n", $rows)
}

function Assert-Refused {
    param([scriptblock] $Action, [string] $What)
    try { & $Action } catch {
        if ($_.Exception.Message -match 'REFUSED') { return }
        throw "$What failed for the wrong reason: $($_.Exception.Message)"
    }
    throw "$What was NOT refused"
}

function Read-Prefs { Get-Content -LiteralPath $prefsPath -Raw | ConvertFrom-Json -Depth 32 }
function Get-Entry([string] $Path) {
    @((Read-Prefs).folders | Where-Object { $_.path -eq $Path }) | Select-Object -First 1
}

try {
    foreach ($d in @('CURRENT/01_MIND-MAKE', 'CURRENT/00_INBOX', 'ARCHIVE', 'CONTENT-EXTRA',
                     'FAMILY-ADMIN', 'ContentLibrary/inside-protected')) {
        New-Item -ItemType Directory -Path (Join-Path $drive $d) -Force | Out-Null
    }
    [IO.File]::WriteAllText((Join-Path $drive 'CURRENT/01_MIND-MAKE/plan.txt'), 'known work')
    [IO.File]::WriteAllText($config, (@{
        schema_version = 2; audit = $audit
        sources = @(@{ id = 'fixture-drive'; path = $drive; kind = 'test'; follow_reparse_points = $false })
        protected_roots = @((Join-Path $drive 'ContentLibrary')); protected_names = @()
    } | ConvertTo-Json -Depth 8))
    $seed = Get-Content -LiteralPath (Join-Path $repo 'policy' 'folder-preferences.json') -Raw | ConvertFrom-Json -Depth 16
    $seed.watch_roots = @(@{ path = $drive; max_depth = 4 })
    $seed.never_enter = @((Join-Path $drive 'ContentLibrary'))
    [IO.File]::WriteAllText($prefsPath, ($seed | ConvertTo-Json -Depth 16))
    $env:FILEARCHIVES_FOLDER_PREFERENCES = $prefsPath
    [IO.File]::WriteAllText($nowPath, "## Where it is right now`n`n<!-- north-star-state {`"week_of`": `"2026-10-26`", `"week_target`": 0, `"current`": null, `"current_as_of`": null, `"current_source`": null, `"urgency`": 4} --> **North Star number**`n")

    # 1. Before Krish records anything, every folder in a watched root is his.
    Assert-Refused { & (Join-Path $structure 'new_folder_move_manifest.ps1') -Source (Join-Path $drive 'ARCHIVE') `
        -Destination (Join-Path $drive 'CURRENT/ARCHIVE') -ManifestPath (Join-Path $audit 'm0.json') `
        -ApprovalReason 'test' -ConfigPath $config } 'a folder move before the record exists'

    # 2. Record the drive as it stands as Krish's preference.
    & (Join-Path $structure 'record_folder_preferences.ps1')
    $prefs = Read-Prefs
    if (-not $prefs.recorded_at) { throw 'the snapshot did not record' }
    if ((Get-Entry (Join-Path $drive 'CURRENT/01_MIND-MAKE')).status -ne 'known') { throw 'a present folder was not recorded as known' }
    if (-not (Get-Entry (Join-Path $drive 'ContentLibrary'))) { throw 'the protected boundary folder itself was not recorded' }
    if (Get-Entry (Join-Path $drive 'ContentLibrary/inside-protected')) { throw 'the snapshot entered a never-enter boundary' }

    # 3. Krish makes two folders after the record: one empty, one with a file.
    $empty = Join-Path $drive 'Tax 2026'
    $withFile = Join-Path $drive 'Side Project'
    New-Item -ItemType Directory -Path $empty, $withFile -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $withFile 'notes.txt'), 'only copy')
    $before = Get-TreeSeal $drive

    # 4. The canonical audit reports them as waiting on Krish, not as issues.
    $policy = Get-Content -LiteralPath (Join-Path $repo 'policy' 'estate-policy-v1.json') -Raw | ConvertFrom-Json -Depth 64
    $policy.destinations.business_current = Join-Path $drive 'CURRENT'
    $policy.destinations.personal = Join-Path $scratch 'G' 'Personal'
    foreach ($p in @($policy.structure.personal)) { New-Item -ItemType Directory -Path (Join-Path $scratch 'G' 'Personal' $p) -Force | Out-Null }
    New-Item -ItemType Directory -Path (Join-Path $scratch 'dev' 'krishanraja' 'mm-ctrl') -Force | Out-Null
    $policyPath = Join-Path $scratch 'policy.json'
    [IO.File]::WriteAllText($policyPath, ($policy | ConvertTo-Json -Depth 64))
    $canonical = Join-Path $audit 'canonical.json'
    & (Join-Path $repo 'stages' '09_mirror' 'test_canonical_state.ps1') -ConfigPath $config -PolicyPath $policyPath `
        -CDevRoot (Join-Path $scratch 'dev') -ReportPath $canonical
    $report = Get-Content -LiteralPath $canonical -Raw | ConvertFrom-Json
    if ($report.Status -ne 'pass') { throw "canonical audit called Krish's new folders issues: $($report.Issues | ConvertTo-Json -Compress)" }
    if (@($report.NewFoldersWaitingOnKrish).Count -ne 2) { throw 'canonical audit did not list both new folders as waiting on Krish' }

    # 4b. The record outranks the older rules: a passport in a recorded folder
    # stays put, one in a new folder waits on Krish, a loose one still routes.
    . (Join-Path $structure 'propose_layout.ps1')
    $folderPrefs = Import-FaFolderPreferences
    foreach ($case in @(
        @{ Rel = 'CURRENT/01_MIND-MAKE/passport.pdf'; Expect = 'preference-keep-in-place' },
        @{ Rel = 'Side Project/passport.pdf'; Expect = 'ask-krish-first' }
    )) {
        $got = Get-FaFolderPreferenceLayout -Item ([pscustomobject]@{ RelativePath = $case.Rel }) `
            -SourceRoot $drive -Preferences $folderPrefs
        if (-not $got -or $got.Disposition -ne $case.Expect) { throw "layout for $($case.Rel) ignored Krish's record" }
    }
    if (Get-FaFolderPreferenceLayout -Item ([pscustomobject]@{ RelativePath = 'passport.pdf' }) `
            -SourceRoot $drive -Preferences $folderPrefs) {
        throw 'a loose root file was held in place instead of routed'
    }

    # 5. Empty-folder cleanup keeps the empty new folder, and every recorded one.
    $emptyManifest = Join-Path $audit 'empty.json'
    & (Join-Path $structure 'new_empty_directory_manifest.ps1') -SourceRoot $drive -ManifestPath $emptyManifest `
        -ApprovalReason 'test cleanup' -ConfigPath $config
    $m = Get-Content -LiteralPath $emptyManifest -Raw | ConvertFrom-Json
    if ($m.TargetCount -ne 0) { throw "empty-folder cleanup targeted Krish's folders: $($m.Targets.Path -join ', ')" }
    if (@($m.PreservedForKrish) -notcontains $empty) { throw 'the empty new folder was not kept for Krish' }
    & (Join-Path $structure 'invoke_empty_directory_manifest.ps1') -ManifestPath $emptyManifest `
        -ReceiptPath (Join-Path $audit 'empty-receipt.json') -Execute -ConfigPath $config

    # A manifest frozen elsewhere that names the new folder is refused at action time.
    $forged = [ordered]@{ SchemaVersion = 1; Kind = 'empty-directory-removal-v1'; SourceRoot = $drive; IncludeRoot = $false
        PreservedRoots = @(); Targets = @(@{ Path = $empty; Depth = 1 }); TargetCount = 1; Approved = $true; ApprovalReason = 'forged' }
    [IO.File]::WriteAllText((Join-Path $audit 'forged-empty.json'), ($forged | ConvertTo-Json -Depth 8))
    & (Join-Path $structure 'invoke_empty_directory_manifest.ps1') -ManifestPath (Join-Path $audit 'forged-empty.json') `
        -ReceiptPath (Join-Path $audit 'forged-empty-receipt.json') -Execute -ConfigPath $config
    $r = Get-Content -LiteralPath (Join-Path $audit 'forged-empty-receipt.json') -Raw | ConvertFrom-Json
    if ($r.RemovedCount -ne 0 -or @($r.ChangedSinceManifest.Reason) -notcontains 'krish-folder-consent-missing') {
        throw 'an approved empty-folder manifest removed a folder Krish has not released'
    }

    # 6. Every folder move path refuses the new folders.
    Assert-Refused { & (Join-Path $structure 'new_folder_move_manifest.ps1') -Source $withFile `
        -Destination (Join-Path $drive 'CURRENT/Side Project') -ManifestPath (Join-Path $audit 'm1.json') `
        -ApprovalReason 'test' -ConfigPath $config } 'a folder move manifest for a new folder'
    Assert-Refused { & (Join-Path $structure 'new_atomic_tree_relocation_manifest.ps1') -Source $empty `
        -Destination (Join-Path $drive 'ARCHIVE/Tax 2026') -ManifestPath (Join-Path $audit 'm2.json') `
        -ApprovalReason 'test' -ConfigPath $config } 'an atomic relocation manifest for a new folder'
    $forgedMove = [ordered]@{ SchemaVersion = 1; Kind = 'verified-folder-move-v1'; Source = $withFile
        Destination = (Join-Path $drive 'ARCHIVE/Side Project'); ExpectedFiles = 1; ExpectedDirectories = 0
        ExpectedBytes = 9; ExpectedMetadataSeal = 'x'; Approved = $true; ApprovalReason = 'forged' }
    [IO.File]::WriteAllText((Join-Path $audit 'm3.json'), ($forgedMove | ConvertTo-Json))
    Assert-Refused { & (Join-Path $structure 'invoke_verified_folder_move.ps1') -ManifestPath (Join-Path $audit 'm3.json') `
        -ReceiptPath (Join-Path $audit 'm3-receipt.json') -Execute -ConfigPath $config } 'an approved folder move of a new folder'
    $forgedTree = [ordered]@{ SchemaVersion = 1; Kind = 'atomic-tree-relocation-v1'; Source = $empty
        Destination = (Join-Path $drive 'ARCHIVE/Tax 2026'); TopLevelItems = 0; ShallowSeal = 'x'; Approved = $true }
    [IO.File]::WriteAllText((Join-Path $audit 'm4.json'), ($forgedTree | ConvertTo-Json))
    Assert-Refused { & (Join-Path $structure 'invoke_atomic_tree_relocation_manifest.ps1') -ManifestPath (Join-Path $audit 'm4.json') `
        -ReceiptPath (Join-Path $audit 'm4-receipt.json') -Execute -ConfigPath $config } 'an approved atomic relocation of a new folder'
    $note = Get-Item -LiteralPath (Join-Path $withFile 'notes.txt')
    $forgedFiles = [ordered]@{ SchemaVersion = 1; Kind = 'live-file-move-v1'; SourceRoot = $drive; Approved = $true
        Moves = @(@{ Source = $note.FullName; Destination = (Join-Path $drive 'CURRENT/00_INBOX/notes.txt'); Length = $note.Length
            LastWriteTimeUtc = ([DateTimeOffset]$note.LastWriteTimeUtc).ToString('o'); Sha256 = $null; RuleId = 'fallback-recent' }) }
    [IO.File]::WriteAllText((Join-Path $audit 'm5.json'), ($forgedFiles | ConvertTo-Json -Depth 8))
    Assert-Refused { & (Join-Path $structure 'invoke_live_file_move_manifest.ps1') -ManifestPath (Join-Path $audit 'm5.json') `
        -ReceiptPath (Join-Path $audit 'm5-receipt.json') -Execute -ConfigPath $config } 'emptying a new folder file by file'

    # 7. The weekly check-in records them as new, waiting on Krish, and touches nothing.
    & (Join-Path $structure 'weekly_folder_checkin.ps1') -ReportRoot $reportRoot -NowPath $nowPath
    foreach ($p in @($empty, $withFile)) {
        if ((Get-Entry $p).status -ne 'new-waiting-on-krish') { throw "the check-in did not record $p as new, waiting on Krish" }
    }
    $log = @(Get-Content -LiteralPath (Join-Path $reportRoot 'LOG.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })[-1]
    if ($log.moved_or_removed_without_ok -ne 0 -or -not $log.cleanliness_check_completed) { throw 'the check-in miscounted a clean week' }
    if ((Get-Content -LiteralPath $nowPath -Raw) -notmatch '"current":0,"current_as_of":"\d{4}-\d{2}-\d{2}"') {
        throw 'the North Star value in NOW.md was not kept honest'
    }

    $after = Get-TreeSeal $drive
    if ($after -ne $before) { throw "a run changed Krish's drive:`n--- before`n$before`n--- after`n$after" }
    Write-Host 'PASS: an unknown new folder survives a run untouched'

    # 8. His answers are recorded; his yes, folder by folder, is the only way through.
    [IO.File]::WriteAllText((Join-Path $reportRoot 'answers.json'), (@{
        folders = @(@{ path = $withFile; important = $true; purpose = 'side project notes' })
    } | ConvertTo-Json -Depth 4))
    $data = Read-Prefs
    $data.consents = @(@{ path = $empty; action = 'delete'; approved_by = 'Krish'; approved_at = '2026-10-23T09:00:00Z'
        words = 'yes, remove the empty Tax 2026 folder' })
    [IO.File]::WriteAllText($prefsPath, ($data | ConvertTo-Json -Depth 16))
    & (Join-Path $structure 'new_empty_directory_manifest.ps1') -SourceRoot $drive -ManifestPath $emptyManifest `
        -ApprovalReason 'Krish said yes for Tax 2026' -ConfigPath $config
    $m = Get-Content -LiteralPath $emptyManifest -Raw | ConvertFrom-Json
    if ($m.TargetCount -ne 1 -or $m.Targets[0].Path -ne $empty) { throw 'a per-folder yes did not release exactly that folder' }
    & (Join-Path $structure 'invoke_empty_directory_manifest.ps1') -ManifestPath $emptyManifest `
        -ReceiptPath (Join-Path $audit 'empty-receipt-2.json') -Execute -ConfigPath $config
    if (Test-Path -LiteralPath $empty) { throw 'the folder Krish released was not removed' }

    # Something outside the engine removes a recorded folder: that is the number.
    Remove-Item -LiteralPath (Join-Path $drive 'CONTENT-EXTRA') -Force
    & (Join-Path $structure 'weekly_folder_checkin.ps1') -ReportRoot $reportRoot -NowPath $nowPath
    $log = @(Get-Content -LiteralPath (Join-Path $reportRoot 'LOG.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })[-1]
    if ($log.moved_or_removed_without_ok -ne 1) { throw "the check-in counted $($log.moved_or_removed_without_ok) folders gone without OK, expected 1" }
    if ((Get-Entry $empty).status -ne 'moved-with-ok') { throw 'a folder removed with Krish''s yes was counted against the number' }
    $answered = Get-Entry $withFile
    if ($answered.status -ne 'answered' -or $answered.purpose -ne 'side project notes') { throw 'Krish''s written answer was not recorded' }
    if ((Get-Content -LiteralPath (Join-Path $reportRoot 'LATEST.md') -Raw) -notmatch 'side project notes') {
        throw 'the cleanliness check did not report the answered folder against its purpose'
    }
    Write-Host 'PASS: only Krish''s per-folder yes releases a folder, and a folder gone without it is counted'
} finally {
    $env:FILEARCHIVES_FOLDER_PREFERENCES = $savedPrefsEnv
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
