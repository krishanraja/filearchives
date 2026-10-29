<#
    The dev sprawl report (Wave 3 W3.4). Read-only: it never moves, renames,
    deletes, fetches or writes inside a repository.

        pwsh -NoProfile -File stages\05_classify\report_dev_sprawl.ps1

    It finds every Git working tree under the dev root (clones, and the linked
    worktrees each clone knows about), and reports for each: its repository and
    venture (policy/repo-ventures.json), branch, dirty entries, commits not on
    any remote, stashes and size on disk. It groups clones of the same
    repository as duplicates, and counts clones of a venture with a home that
    sit outside it: for Make Your Mind Up, clones outside dev\makeyourmindup.
    For each of those it proposes a destination, as evidence for Krish. Nothing
    moves unless he writes a consent row for that exact folder.

    Writes docs/folder-checkin/SPRAWL.md and sprawl.json, beside the weekly
    check-in, so Monday's check-in carries it. Counts and folder names only:
    no file name inside a repository leaves his machine.

    Git runs with --no-optional-locks, so even `status` leaves the index alone.
    "Not on any remote" is measured against what each clone last fetched; this
    report never fetches.
#>
[CmdletBinding()]
param(
    [string] $DevRoot,
    [string] $VenturesPath,
    [string] $ReportRoot,
    [int] $MaxDepth = 4,
    [datetimeoffset] $AsOf = [DateTimeOffset]::Now
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards' 'workspace.ps1')
. (Join-Path $repo 'guards' 'atomic.ps1')

if (-not $VenturesPath) { $VenturesPath = Join-Path $repo 'policy' 'repo-ventures.json' }
if (-not $ReportRoot) { $ReportRoot = Join-Path $repo 'docs' 'folder-checkin' }
if (-not (Test-Path -LiteralPath $VenturesPath -PathType Leaf)) {
    throw "repo ventures are absent: $VenturesPath"
}
$ventures = Get-Content -LiteralPath $VenturesPath -Raw | ConvertFrom-Json -Depth 16
if ($ventures.schema_version -ne 1 -or $ventures.kind -ne 'krish-repo-ventures-v1') {
    throw "unsupported repo ventures: $VenturesPath"
}
if (-not $DevRoot) { $DevRoot = [string]$ventures.dev_root }
$DevRoot = ConvertTo-FaCanonicalPath $DevRoot
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required for the dev sprawl report' }

$ventureByRepo = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($p in $ventures.repos.PSObject.Properties) { $ventureByRepo[$p.Name] = [string]$p.Value }
$homes = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($ventures.PSObject.Properties.Name -contains 'homes') {
    foreach ($p in $ventures.homes.PSObject.Properties) { $homes[$p.Name] = ConvertTo-FaCanonicalPath ([string]$p.Value.path) }
}
$preserve = @(if ($ventures.PSObject.Properties.Name -contains 'preserve') { $ventures.preserve })
# Krish, 2026-10-29: "standalone/personal projects you dont need to be across". Left out entirely.
$outOfScope = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($ventures.PSObject.Properties.Name -contains 'out_of_scope') { foreach ($r in @($ventures.out_of_scope)) { $null = $outOfScope.Add([string]$r) } }
$skippedOutOfScope = 0
$skipNames = @('.git', 'node_modules', '.venv', 'venv', '__pycache__', '$RECYCLE.BIN', 'System Volume Information')

function Invoke-FaGitRead {
    param([string] $Tree, [string[]] $Arguments)
    $out = @(& git -c "safe.directory=*" -c core.quotepath=false --no-optional-locks -C $Tree @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    return @($out | ForEach-Object { [string]$_ })
}

function Get-FaRepoIdentity {
    param([string] $Url)
    if (-not $Url) { return $null }
    $clean = ($Url.Trim() -replace '\.git$', '').TrimEnd('/')
    if ($clean -match '(?i)github\.com[/:]([^/]+/[^/]+)$') { return $Matches[1].ToLowerInvariant() }
    return $null
}

function Get-FaTreeBytes {
    param([string] $Path)
    $options = [IO.EnumerationOptions]::new()
    $options.RecurseSubdirectories = $true
    $options.IgnoreInaccessible = $true
    $options.AttributesToSkip = [IO.FileAttributes]::ReparsePoint
    [long]$bytes = 0
    foreach ($f in [IO.DirectoryInfo]::new($Path).EnumerateFiles('*', $options)) { $bytes += $f.Length }
    return $bytes
}

function Format-FaBytes([long] $Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

# ---- find working trees ----------------------------------------------------
$trees = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$unreadable = [Collections.Generic.List[string]]::new()
$available = Test-Path -LiteralPath $DevRoot -PathType Container
if ($available) {
    $queue = [Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject]@{ Path = $DevRoot; Depth = 0 })
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $gitMarker = Join-Path $current.Path '.git'
        if ($current.Depth -gt 0 -and (Test-Path -LiteralPath $gitMarker)) {
            $trees[$current.Path] = if (Test-Path -LiteralPath $gitMarker -PathType Leaf) { 'worktree' } else { 'clone' }
            continue
        }
        if ($current.Depth -ge $MaxDepth) { continue }
        try {
            $children = @([IO.DirectoryInfo]::new($current.Path).EnumerateDirectories() | Sort-Object Name)
        } catch {
            $unreadable.Add($current.Path)
            continue
        }
        foreach ($child in $children) {
            if ($skipNames -contains $child.Name) { continue }
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $queue.Enqueue([pscustomobject]@{ Path = (ConvertTo-FaCanonicalPath $child.FullName); Depth = $current.Depth + 1 })
        }
    }
    # Linked worktrees can live anywhere; each clone knows its own.
    foreach ($clone in @($trees.Keys | Where-Object { $trees[$_] -eq 'clone' })) {
        foreach ($line in @(Invoke-FaGitRead $clone @('worktree', 'list', '--porcelain'))) {
            if ($line -notmatch '^worktree (.+)$') { continue }
            $wt = ConvertTo-FaCanonicalPath $Matches[1]
            if ($trees.ContainsKey($wt) -or -not (Test-Path -LiteralPath $wt -PathType Container)) { continue }
            $trees[$wt] = 'worktree'
        }
    }
}

# ---- read each one ---------------------------------------------------------
$rows = [Collections.Generic.List[object]]::new()
foreach ($path in @($trees.Keys | Sort-Object)) {
    $kind = $trees[$path]
    $remote = @(Invoke-FaGitRead $path @('remote', 'get-url', 'origin')) | Select-Object -First 1
    $identity = Get-FaRepoIdentity $remote
    if ($identity -and $outOfScope.Contains($identity)) { $skippedOutOfScope++; continue }
    $venture = if (-not $identity) { 'no-remote' } elseif ($ventureByRepo.ContainsKey($identity)) { $ventureByRepo[$identity] } else { 'unplaced' }
    $branch = @(Invoke-FaGitRead $path @('branch', '--show-current')) | Select-Object -First 1
    $status = @(Invoke-FaGitRead $path @('status', '--porcelain=v1', '--untracked-files=normal'))
    $upstream = @(Invoke-FaGitRead $path @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}')) | Select-Object -First 1
    $aheadText = if ($upstream) { @(Invoke-FaGitRead $path @('rev-list', '--count', '@{upstream}..HEAD')) | Select-Object -First 1 }
        else { @(Invoke-FaGitRead $path @('rev-list', '--count', 'HEAD', '--not', '--remotes')) | Select-Object -First 1 }
    $stashes = @(Invoke-FaGitRead $path @('stash', 'list'))
    $last = @(Invoke-FaGitRead $path @('log', '-1', '--format=%cI')) | Select-Object -First 1
    $linked = if ($kind -eq 'clone') {
        @(Invoke-FaGitRead $path @('worktree', 'list', '--porcelain') | Where-Object { $_ -match '^worktree ' }).Count - 1
    } else { 0 }
    $ventureHome = if ($homes.ContainsKey($venture)) { $homes[$venture] } else { $null }
    $kept = @($preserve | Where-Object { $identity -and ([string]$_.repo).Equals($identity, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object {
        $p = Join-Path $path ([string]$_.path)
        if (Test-Path -LiteralPath $p) { [pscustomobject]@{ Path = [string]$_.path; Bytes = (Get-FaTreeBytes $p) } }
    })
    $rows.Add([pscustomobject][ordered]@{
        Path = $path
        Kind = $kind
        Repository = $identity
        Venture = $venture
        Branch = $branch
        DirtyEntries = $status.Count
        NotOnAnyRemote = if ($null -ne $aheadText) { [int]$aheadText } else { $null }
        Upstream = $upstream
        Stashes = $stashes.Count
        LinkedWorktrees = [math]::Max(0, $linked)
        LastCommit = $last
        Bytes = Get-FaTreeBytes $path
        Home = $ventureHome
        OutsideHome = [bool]($ventureHome -and -not (Test-FaPathWithin -Path $path -Root $ventureHome))
        Preserved = $kept
        ProposedDestination = $null
        ProposalNote = $null
    })
}

# ---- duplicates and proposals ----------------------------------------------
$clones = @($rows | Where-Object { $_.Kind -eq 'clone' })
$duplicates = @($clones | Where-Object Repository | Group-Object Repository | Where-Object Count -gt 1 | ForEach-Object {
    [pscustomobject]@{ Repository = $_.Name; Count = $_.Count; Paths = @($_.Group | ForEach-Object Path) }
})
$taken = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($r in $rows) { $null = $taken.Add($r.Path) }
# The newest clone of a repository gets the plain name; any other waits in .duplicates for Krish.
foreach ($r in @($rows | Where-Object OutsideHome | Sort-Object { [string]$_.LastCommit } -Descending)) {
    if ($r.Kind -ne 'clone') {
        $r.ProposalNote = 'linked worktree: moved with git worktree move from its clone, not as a folder'
        continue
    }
    if ($r.LinkedWorktrees -gt 0) {
        $r.ProposalNote = 'has linked worktrees: they move first, with git worktree move'
        continue
    }
    $name = ($r.Repository -split '/')[-1]
    $dest = ConvertTo-FaCanonicalPath (Join-Path $r.Home $name)
    if ($taken.Contains($dest) -or (Test-Path -LiteralPath $dest)) {
        $parent = Split-Path -Leaf (Split-Path -Parent $r.Path)
        $dest = ConvertTo-FaCanonicalPath (Join-Path $r.Home '.duplicates' ('{0}-{1}' -f $name, $parent))
        $r.ProposalNote = 'another clone holds the plain name; this one waits in .duplicates for you to keep or remove'
    }
    if ($taken.Contains($dest) -or (Test-Path -LiteralPath $dest)) {
        $r.ProposalNote = 'no free destination; needs your call'
        continue
    }
    $null = $taken.Add($dest)
    $r.ProposedDestination = $dest
}

$outsideClones = @($rows | Where-Object { $_.OutsideHome -and $_.Kind -eq 'clone' })
$mymuOutside = @($outsideClones | Where-Object Venture -eq 'makeyourmindup')
$result = [ordered]@{
    SchemaVersion = 1
    Kind = 'dev-sprawl-report-v1'
    ObservedAt = $AsOf.ToString('o')
    DevRoot = $DevRoot
    DevRootAvailable = $available
    ReadOnly = $true
    WorkingTrees = $rows.Count
    Clones = $clones.Count
    Worktrees = @($rows | Where-Object Kind -eq 'worktree').Count
    Dirty = @($rows | Where-Object { $_.DirtyEntries -gt 0 }).Count
    WithWorkNotOnAnyRemote = @($rows | Where-Object { $_.NotOnAnyRemote -gt 0 -or $_.Stashes -gt 0 }).Count
    DuplicateRepositories = $duplicates.Count
    Bytes = [long](($rows | Measure-Object Bytes -Sum).Sum)
    MakeYourMindUpClonesOutsideHome = $mymuOutside.Count
    ClonesOutsideTheirVentureHome = $outsideClones.Count
    OutOfScopeLeftOut = $skippedOutOfScope
    UnreadableFolders = @($unreadable)
    Duplicates = $duplicates
    Trees = @($rows)
}
Write-FaAtomicJson -Path (Join-Path $ReportRoot 'sprawl.json') -Value $result -Depth 12

# ---- the page Krish reads --------------------------------------------------
function Format-FaCell([string] $Text) { return ($Text -replace '\|', '/' -replace '[\r\n]+', ' ').Trim() }
function Get-FaRel([string] $Path) {
    if (Test-FaPathWithin -Path $Path -Root $DevRoot) { return 'dev' + $Path.Substring($DevRoot.Length) }
    return $Path
}
$day = $AsOf.ToString('yyyy-MM-dd')
$md = [Text.StringBuilder]::new()
[void]$md.AppendLine("# Dev sprawl, $day")
[void]$md.AppendLine()
[void]$md.AppendLine("Read-only. Nothing was moved, renamed, deleted or fetched. Folder names and counts only; ``dev`` is ``$DevRoot``.")
[void]$md.AppendLine()
if (-not $available) {
    [void]$md.AppendLine('The dev folder was not there this time, so nothing was counted. Absent is not empty.')
} else {
    [void]$md.AppendLine('## The number')
    [void]$md.AppendLine()
    [void]$md.AppendLine("- Make Your Mind Up clones outside ``dev\makeyourmindup``: **$($mymuOutside.Count)**")
    [void]$md.AppendLine()
    [void]$md.AppendLine('## At a glance')
    [void]$md.AppendLine()
    [void]$md.AppendLine("- Working trees: $($rows.Count) ($($clones.Count) clones, $($result.Worktrees) linked worktrees), $(Format-FaBytes $result.Bytes) in all")
    [void]$md.AppendLine("- With uncommitted changes: $($result.Dirty)")
    [void]$md.AppendLine("- With commits or stashes on no remote: $($result.WithWorkNotOnAnyRemote) (as of each clone's last fetch)")
    [void]$md.AppendLine("- Repositories cloned more than once: $($duplicates.Count)")
    [void]$md.AppendLine("- Personal projects left out, as Krish asked: $skippedOutOfScope")
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Clones outside their venture's folder ($($outsideClones.Count))")
    [void]$md.AppendLine()
    if ($outsideClones.Count -eq 0) { [void]$md.AppendLine('None.') } else {
        [void]$md.AppendLine('Each stays where it is until you say yes for that folder. Dirty clones are snapshotted before any move.')
        [void]$md.AppendLine()
        [void]$md.AppendLine('| Folder | Repository | Uncommitted | On no remote | Size | Proposed home |')
        [void]$md.AppendLine('|---|---|---|---|---|---|')
        foreach ($r in $outsideClones) {
            $to = if ($r.ProposedDestination) { '`' + (Get-FaRel $r.ProposedDestination) + '`' } else { Format-FaCell $r.ProposalNote }
            [void]$md.AppendLine(('| `{0}` | {1} | {2} | {3} | {4} | {5} |' -f (Format-FaCell (Get-FaRel $r.Path)),
                $r.Repository, $r.DirtyEntries, $r.NotOnAnyRemote, (Format-FaBytes $r.Bytes), $to))
        }
    }
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Cloned more than once ($($duplicates.Count))")
    [void]$md.AppendLine()
    if ($duplicates.Count -eq 0) { [void]$md.AppendLine('None.') } else {
        foreach ($d in $duplicates) {
            [void]$md.AppendLine(('- {0}: {1}' -f $d.Repository, (($d.Paths | ForEach-Object { '`' + (Get-FaRel $_) + '`' }) -join ', ')))
        }
    }
    $atRisk = @($rows | Where-Object { $_.DirtyEntries -gt 0 -or $_.NotOnAnyRemote -gt 0 -or $_.Stashes -gt 0 })
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Work that exists only on this PC ($($atRisk.Count))")
    [void]$md.AppendLine()
    if ($atRisk.Count -eq 0) { [void]$md.AppendLine('None.') } else {
        [void]$md.AppendLine('| Folder | Branch | Uncommitted | Commits on no remote | Stashes |')
        [void]$md.AppendLine('|---|---|---|---|---|')
        foreach ($r in $atRisk) {
            [void]$md.AppendLine(('| `{0}` | {1} | {2} | {3} | {4} |' -f (Format-FaCell (Get-FaRel $r.Path)),
                (Format-FaCell ([string]$r.Branch)), $r.DirtyEntries, $r.NotOnAnyRemote, $r.Stashes))
        }
    }
    $wts = @($rows | Where-Object Kind -eq 'worktree')
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Linked worktrees ($($wts.Count))")
    [void]$md.AppendLine()
    if ($wts.Count -eq 0) { [void]$md.AppendLine('None.') } else {
        foreach ($r in $wts) { [void]$md.AppendLine(('- `{0}` ({1}, {2})' -f (Get-FaRel $r.Path), $r.Repository, (Format-FaCell ([string]$r.Branch)))) }
    }
    $unplaced = @($rows | Where-Object { $_.Venture -in @('unplaced', 'no-remote') })
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Not yet placed in a venture ($($unplaced.Count))")
    [void]$md.AppendLine()
    if ($unplaced.Count -eq 0) { [void]$md.AppendLine('None.') } else {
        foreach ($r in $unplaced) {
            $what = if ($r.Repository) { $r.Repository } else { 'no GitHub remote' }
            [void]$md.AppendLine(('- `{0}` ({1})' -f (Get-FaRel $r.Path), $what))
        }
    }
    [void]$md.AppendLine()
    [void]$md.AppendLine('## Largest')
    [void]$md.AppendLine()
    foreach ($r in @($rows | Sort-Object Bytes -Descending | Select-Object -First 10)) {
        [void]$md.AppendLine(('- `{0}`: {1}' -f (Get-FaRel $r.Path), (Format-FaBytes $r.Bytes)))
    }
}
[void]$md.AppendLine()
[void]$md.AppendLine('## Saying yes to a move')
[void]$md.AppendLine()
[void]$md.AppendLine('Add one row per folder under `consents` in `policy/folder-preferences.json` (or ask any Claude session to): the exact `path`, `action: "move"`, the exact `destination`, `approved_by: "Krish"`, `approved_at`, and your words. `chains/chain_dev_consolidation.ps1 -Execute` then snapshots every dirty repository first and moves only the folders you named. `docs/folder-checkin/move-requests.json` holds each row ready to copy.')
Write-FaAtomicUtf8 -Path (Join-Path $ReportRoot 'SPRAWL.md') -Content $md.ToString()

Write-Host ("dev sprawl {0}: trees={1} dirty={2} not-on-remote={3} duplicates={4} mymu-outside-home={5}" -f
    $day, $rows.Count, $result.Dirty, $result.WithWorkNotOnAnyRemote, $duplicates.Count, $mymuOutside.Count)
Write-Host 'Nothing was moved, renamed or deleted.'
