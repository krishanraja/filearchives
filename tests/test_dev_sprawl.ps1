# Wave 3 W3.4, on a synthetic dev folder: the sprawl report is read-only and
# counts Make Your Mind Up clones outside dev\makeyourmindup; a move happens
# only for a folder Krish said yes to, to the exact destination he named,
# after every dirty repository is snapshotted, and Growth's .scratch arrives
# byte for byte. Synthetic fixtures only: no real repository or remote.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('filearchives-dev-sprawl-' + [guid]::NewGuid().ToString('n'))
$dev = Join-Path $scratch 'dev'
$remotes = Join-Path $scratch 'remotes'
$home_ = Join-Path $dev 'makeyourmindup'
$reportRoot = Join-Path $scratch 'report'
$prefsPath = Join-Path $scratch 'folder-preferences.json'
$venturesPath = Join-Path $scratch 'repo-ventures.json'
$config = Join-Path $scratch 'workspace.json'
$chain = Join-Path $repo 'chains' 'chain_dev_consolidation.ps1'
$savedEnv = @{}
foreach ($k in @('FILEARCHIVES_FOLDER_PREFERENCES', 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL', 'GIT_AUTHOR_DATE', 'GIT_COMMITTER_DATE')) {
    $savedEnv[$k] = [Environment]::GetEnvironmentVariable($k)
}

function Invoke-Git {
    param([string] $Tree, [string[]] $Arguments)
    $out = & git -C $Tree @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed in ${Tree}: $out" }
}

function New-FixtureRepo {
    param([string] $Path, [string] $Identity, [string] $Date, [int] $Ahead = 0, [switch] $Dirty, [string[]] $Ignored = @())
    $bare = Join-Path $remotes ([guid]::NewGuid().ToString('n') + '.git')
    & git init --quiet --bare $bare
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Invoke-Git $Path @('init', '--quiet', '-b', 'main')
    $env:GIT_AUTHOR_DATE = $Date; $env:GIT_COMMITTER_DATE = $Date
    [IO.File]::WriteAllText((Join-Path $Path 'README.md'), "synthetic $Identity`n")
    if ($Ignored.Count -gt 0) { [IO.File]::WriteAllText((Join-Path $Path '.gitignore'), (($Ignored | ForEach-Object { "$_/" }) -join "`n") + "`n") }
    Invoke-Git $Path @('add', '-A')
    Invoke-Git $Path @('commit', '--quiet', '-m', 'synthetic start')
    Invoke-Git $Path @('remote', 'add', 'origin', $bare)
    Invoke-Git $Path @('push', '--quiet', '-u', 'origin', 'main')
    Invoke-Git $Path @('remote', 'set-url', 'origin', "https://github.com/$Identity.git")
    for ($i = 0; $i -lt $Ahead; $i++) {
        [IO.File]::WriteAllText((Join-Path $Path "local-$i.txt"), "only here $i`n")
        Invoke-Git $Path @('add', '-A')
        Invoke-Git $Path @('commit', '--quiet', '-m', "local $i")
    }
    if ($Dirty) {
        [IO.File]::AppendAllText((Join-Path $Path 'README.md'), "uncommitted line`n")
        [IO.File]::WriteAllText((Join-Path $Path 'draft.txt'), "untracked draft`n")
    }
}

function Get-TreeSeal {
    param([string] $Root)
    $rows = @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($Root.Length)
        if ($_.PSIsContainer) { "D|$rel" }
        else { "F|$rel|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)|$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
    })
    return [string]::Join("`n", $rows)
}

function Read-Sprawl { Get-Content -LiteralPath (Join-Path $reportRoot 'sprawl.json') -Raw | ConvertFrom-Json -Depth 16 }
function Read-Requests { @((Get-Content -LiteralPath (Join-Path $reportRoot 'move-requests.json') -Raw | ConvertFrom-Json -Depth 16).Requests) }
function Set-Consents {
    param([object[]] $Rows)
    $data = Get-Content -LiteralPath $prefsPath -Raw | ConvertFrom-Json -Depth 32
    $data.consents = @($Rows | ForEach-Object {
        [ordered]@{ path = $_.Path; action = 'move'; destination = $_.Destination; approved_by = 'Krish'
            approved_at = '2026-11-12T09:00:00Z'; words = 'synthetic yes for this folder' }
    })
    [IO.File]::WriteAllText($prefsPath, ($data | ConvertTo-Json -Depth 32))
}
function Invoke-Chain {
    param([switch] $Execute)
    $args_ = @{ DevRoot = $dev; VenturesPath = $venturesPath; ReportRoot = $reportRoot; ConfigPath = $config
        SnapshotRoot = (Join-Path $scratch 'snapshots' ([guid]::NewGuid().ToString('n')))
        AuditRoot = (Join-Path $scratch 'audit' ([guid]::NewGuid().ToString('n'))) }
    if ($Execute) { & $chain @args_ -Execute *>&1 | Out-String } else { & $chain @args_ *>&1 | Out-String }
}

try {
    $env:GIT_AUTHOR_NAME = 'Synthetic'; $env:GIT_AUTHOR_EMAIL = 'synthetic@invalid'
    $env:GIT_COMMITTER_NAME = 'Synthetic'; $env:GIT_COMMITTER_EMAIL = 'synthetic@invalid'
    New-Item -ItemType Directory -Path $dev, $remotes -Force | Out-Null

    # The real map knows the Make Your Mind Up repositories and their home.
    $real = Get-Content -LiteralPath (Join-Path $repo 'policy' 'repo-ventures.json') -Raw | ConvertFrom-Json -Depth 16
    foreach ($r in @('makeyourmindup', 'growth-makeyourmindup', 'content-engine', 'content-watcher')) {
        if ($real.repos."krishanraja/$r" -ne 'makeyourmindup') { throw "policy/repo-ventures.json does not place krishanraja/$r in makeyourmindup" }
    }
    if ($real.homes.makeyourmindup.path -ne 'C:\Users\krish\dev\makeyourmindup') { throw 'the Make Your Mind Up home is not dev\makeyourmindup' }
    if (@($real.preserve | Where-Object { $_.repo -eq 'krishanraja/growth-makeyourmindup' -and $_.path -eq '.scratch' }).Count -ne 1) {
        throw "Growth's .scratch is not preserved in policy/repo-ventures.json"
    }
    $real.dev_root = $dev
    $real.homes.makeyourmindup.path = $home_
    $real.homes.makeyourmindup.worktrees = Join-Path $home_ '.worktrees'
    [IO.File]::WriteAllText($venturesPath, ($real | ConvertTo-Json -Depth 16))

    # Krish's record: dev watched two levels down, no consents yet.
    $seed = Get-Content -LiteralPath (Join-Path $repo 'policy' 'folder-preferences.json') -Raw | ConvertFrom-Json -Depth 32
    if (@($seed.watch_roots | Where-Object { $_.path -eq 'C:\Users\krish\dev' -and $_.max_depth -eq 2 }).Count -ne 1) {
        throw 'the dev watch depth in policy/folder-preferences.json is not 2'
    }
    $seed.watch_roots = @(@{ path = $dev; max_depth = 2 })
    $seed.never_enter = @(); $seed.folders = @(); $seed.consents = @()
    [IO.File]::WriteAllText($prefsPath, ($seed | ConvertTo-Json -Depth 32))
    $env:FILEARCHIVES_FOLDER_PREFERENCES = $prefsPath
    [IO.File]::WriteAllText($config, (@{
        schema_version = 2; audit = (Join-Path $scratch 'engine-audit')
        sources = @(@{ id = 'fixture-dev'; path = $dev; kind = 'test'; follow_reparse_points = $false })
        protected_roots = @((Join-Path $scratch 'unrelated-protected')); protected_names = @()
    } | ConvertTo-Json -Depth 8))

    # The synthetic dev folder.
    $inHome = Join-Path $home_ 'makeyourmindup'
    $ceNew = Join-Path $dev 'mindmake' 'session-a' 'content-engine'
    $ceOld = Join-Path $dev 'krishanraja' 'content-engine'
    $growth = Join-Path $dev 'krishanraja' 'growth-makeyourmindup'
    $watcher = Join-Path $dev 'krishanraja' 'content-watcher'
    $watcherWt = Join-Path $dev 'mindmake' 'content-watcher-wt'
    $heart = Join-Path $dev 'krishanraja' 'heartside'
    $hunter = Join-Path $dev 'krishanraja' 'hunter'
    New-FixtureRepo $inHome 'krishanraja/makeyourmindup' '2026-10-25T10:00:00Z'
    New-FixtureRepo $ceNew 'krishanraja/content-engine' '2026-10-20T10:00:00Z' -Dirty
    New-FixtureRepo $ceOld 'krishanraja/content-engine' '2026-09-01T10:00:00Z'
    New-FixtureRepo $growth 'krishanraja/growth-makeyourmindup' '2026-10-22T10:00:00Z' -Ahead 1 -Ignored @('.scratch')
    New-Item -ItemType Directory -Path (Join-Path $growth '.scratch' 'taste') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $growth '.scratch' 'taste' 'backstop.jsonl'), "{`"line`":`"synthetic`"}`n")
    $scratchHash = (Get-FileHash -LiteralPath (Join-Path $growth '.scratch' 'taste' 'backstop.jsonl')).Hash
    New-FixtureRepo $watcher 'krishanraja/content-watcher' '2026-10-21T10:00:00Z'
    Invoke-Git $watcher @('worktree', 'add', '--quiet', '-b', 'try-it', $watcherWt)
    New-FixtureRepo $heart 'krishanraja/heartside' '2026-10-10T10:00:00Z'
    New-FixtureRepo $hunter 'krishanraja/hunter' '2026-10-11T10:00:00Z'
    $env:GIT_AUTHOR_DATE = $null; $env:GIT_COMMITTER_DATE = $null

    # 1. The report is read-only, down to every byte under .git.
    $before = Get-TreeSeal $dev
    & (Join-Path $repo 'stages' '05_classify' 'report_dev_sprawl.ps1') -DevRoot $dev -VenturesPath $venturesPath -ReportRoot $reportRoot | Out-Null
    if ((Get-TreeSeal $dev) -ne $before) { throw 'the sprawl report changed the dev folder' }
    $s = Read-Sprawl
    $expect = @{ WorkingTrees = 8; Clones = 7; Worktrees = 1; Dirty = 1; WithWorkNotOnAnyRemote = 1; DuplicateRepositories = 1; MakeYourMindUpClonesOutsideHome = 4 }
    foreach ($k in $expect.Keys) { if ($s.$k -ne $expect[$k]) { throw "sprawl $k is $($s.$k), expected $($expect[$k])" } }
    $byPath = @{}; foreach ($t in $s.Trees) { $byPath[$t.Path] = $t }
    if ($byPath[$hunter].Venture -ne 'unplaced') { throw 'an unmapped repository was given a venture' }
    if ($byPath[$growth].NotOnAnyRemote -ne 1) { throw 'the unpushed commit was not counted' }
    if (@($byPath[$growth].Preserved).Count -ne 1) { throw "Growth's .scratch was not reported as preserved" }
    if ($byPath[$ceNew].ProposedDestination -ne (Join-Path $home_ 'content-engine')) { throw 'the newest clone did not get the plain name' }
    if ($byPath[$ceOld].ProposedDestination -ne (Join-Path $home_ '.duplicates' 'content-engine-krishanraja')) { throw 'the older duplicate was not held in .duplicates' }
    if ($byPath[$watcher].ProposedDestination) { throw 'a clone with a linked worktree was proposed as a folder move' }
    $md = Get-Content -LiteralPath (Join-Path $reportRoot 'SPRAWL.md') -Raw
    if ($md -notmatch 'Make Your Mind Up clones outside `dev\\makeyourmindup`: \*\*4\*\*') { throw 'SPRAWL.md does not carry the number' }
    if ($md -match 'README|draft\.txt|backstop\.jsonl') { throw 'SPRAWL.md leaked a file name from inside a repository' }
    if ($md.Contains([string][char]0x2014)) { throw 'SPRAWL.md has an em dash' }
    Write-Host 'PASS: the sprawl report is read-only and counts what W3.4 asks for'

    # 2. Plan only, and Execute without any yes: nothing moves.
    $null = Invoke-Chain
    $req = Read-Requests
    if ($req.Count -ne 3 -or @($req | Where-Object approved).Count -ne 0) { throw 'the plan did not list three unapproved consent rows' }
    if (@($req | Where-Object { $_.consent_row.approved_by }).Count -ne 0) { throw 'a consent row was pre-approved' }
    $null = Invoke-Chain -Execute
    if ((Get-TreeSeal $dev) -ne $before) { throw 'a run without his yes changed the dev folder' }
    Write-Host 'PASS: without his consent rows nothing moves'

    # 3. His yes for two folders, and a yes for Growth to a different destination.
    Set-Consents @(
        @{ Path = $ceNew; Destination = (Join-Path $home_ 'content-engine') },
        @{ Path = $ceOld; Destination = (Join-Path $home_ '.duplicates' 'content-engine-krishanraja') },
        @{ Path = $growth; Destination = (Join-Path $home_ 'growth') })
    $out = Invoke-Chain -Execute
    if ((Test-Path -LiteralPath $ceNew) -or (Test-Path -LiteralPath $ceOld)) { throw 'a folder he said yes to did not move' }
    if (-not (Test-Path -LiteralPath $growth)) { throw 'a yes for another destination moved the folder' }
    $receipt = @(Get-ChildItem -LiteralPath (Join-Path $scratch 'audit') -Recurse -Filter 'consolidation-receipt.json')[-1] |
        Get-Content -Raw | ConvertFrom-Json -Depth 8
    if (@($receipt.Snapshots).Count -ne 1 -or $receipt.Snapshots[0].Source -ne $ceNew) { throw 'the dirty repository was not snapshotted' }
    if (-not (Test-Path -LiteralPath (Join-Path $receipt.Snapshots[0].Snapshot 'draft.txt'))) { throw 'the snapshot lost uncommitted work' }
    $moved = Join-Path $home_ 'content-engine'
    if (-not (Test-Path -LiteralPath (Join-Path $moved 'draft.txt'))) { throw 'the move lost uncommitted work' }
    if ((Read-Sprawl).MakeYourMindUpClonesOutsideHome -ne 2) { throw 'after two moves the number is not 2' }
    Write-Host 'PASS: only the exact folder and destination he said yes to moved, after a snapshot'

    # 4. His yes for Growth to the proposed home: .scratch arrives byte for byte.
    Set-Consents @(@{ Path = $growth; Destination = (Join-Path $home_ 'growth-makeyourmindup') })
    $null = Invoke-Chain -Execute
    $kept = Join-Path $home_ 'growth-makeyourmindup' '.scratch' 'taste' 'backstop.jsonl'
    if (-not (Test-Path -LiteralPath $kept) -or (Get-FileHash -LiteralPath $kept).Hash -ne $scratchHash) {
        throw "Growth's .scratch did not survive the move byte for byte"
    }
    $s = Read-Sprawl
    if ($s.MakeYourMindUpClonesOutsideHome -ne 1) { throw 'the clone with a linked worktree should be the one left' }
    if ((Get-Content -LiteralPath (Join-Path $reportRoot 'SPRAWL.md') -Raw) -notmatch 'linked worktrees') { throw 'SPRAWL.md does not say why one clone was held' }

    # 5. Once its worktree is gone (his step, with git), his yes brings the last one home.
    Invoke-Git $watcher @('worktree', 'remove', $watcherWt)
    $null = Invoke-Chain
    Set-Consents @(@{ Path = $watcher; Destination = (Join-Path $home_ 'content-watcher') })
    $null = Invoke-Chain -Execute
    $s = Read-Sprawl
    if ($s.MakeYourMindUpClonesOutsideHome -ne 0) { throw "after his consents the report shows $($s.MakeYourMindUpClonesOutsideHome) clones outside home, not 0" }
    foreach ($p in @($inHome, $heart, $hunter)) { if (-not (Test-Path -LiteralPath (Join-Path $p '.git'))) { throw "a folder nobody asked about moved: $p" } }
    Write-Host 'PASS: after his consents the report shows 0 Make Your Mind Up clones outside dev\makeyourmindup'
} finally {
    foreach ($k in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $savedEnv[$k]) }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
