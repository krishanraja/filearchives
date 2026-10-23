Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
    Krish's folders are his. Ruling (Krish, 2026-10-23): filearchives never
    moves a folder Krish made without asking first.

    policy/folder-preferences.json is the record of where Krish wants things:
    the folder tree as it stood when he pressed RECORD-MY-FOLDERS.cmd, every
    folder he has made since (status new-waiting-on-krish until he answers),
    his answers, and his explicit per-folder consents.

    Inside a watched root:
      - a folder is never moved, renamed, merged or removed without a consent
        row naming that exact folder and action, approved by Krish;
      - a folder the record does not know is new, waiting on Krish: nothing
        inside it moves either, until he has answered for it.
    Outside every watched root (engine quarantine, audit trees, retired
    ingress drives) the existing manifest approvals still govern.

    An absent record stops the caller. A missing record and a record that
    knows nothing must never look the same.
#>

function Get-FaFolderPreferencesPath {
    if ($env:FILEARCHIVES_FOLDER_PREFERENCES) { return $env:FILEARCHIVES_FOLDER_PREFERENCES }
    return Join-Path (Split-Path -Parent $PSScriptRoot) 'policy' 'folder-preferences.json'
}

function Get-FaPathSegments {
    param([Parameter(Mandatory)][string] $Path)
    return @([regex]::Split($Path, '[\\/]+') | Where-Object { $_ })
}

function Get-FaRelativeDepth {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][string] $Root)
    $p = ConvertTo-FaCanonicalPath $Path
    $r = ConvertTo-FaCanonicalPath $Root
    if ($p.Equals($r, [StringComparison]::OrdinalIgnoreCase)) { return 0 }
    return @(Get-FaPathSegments $p.Substring($r.Length)).Count
}

function Import-FaFolderPreferences {
    [CmdletBinding()]
    param([string] $Path)
    if (-not $Path) { $Path = Get-FaFolderPreferencesPath }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "folder preferences are absent: $Path - nothing may move until Krish's folders are recorded"
    }
    $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 32 -DateKind String
    if ($data.schema_version -ne 1 -or $data.kind -ne 'krish-folder-preferences-v1') {
        throw "unsupported folder preferences: $Path"
    }
    $byPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($data.folders)) {
        $byPath[(ConvertTo-FaCanonicalPath ([string]$entry.path))] = $entry
    }
    return [pscustomobject]@{
        Path = ConvertTo-FaCanonicalPath $Path
        Data = $data
        Recorded = -not [string]::IsNullOrWhiteSpace([string]$data.recorded_at)
        WatchRoots = @($data.watch_roots | ForEach-Object {
            [pscustomobject]@{ Path = ConvertTo-FaCanonicalPath ([string]$_.path); MaxDepth = [int]$_.max_depth }
        })
        NeverEnter = @($data.never_enter | ForEach-Object { ConvertTo-FaCanonicalPath ([string]$_) })
        SkipNames = @($data.skip_names)
        ByPath = $byPath
    }
}

function Get-FaWatchRoot {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)] $Preferences)
    foreach ($root in $Preferences.WatchRoots) {
        if (Test-FaPathWithin -Path $Path -Root $root.Path) { return $root }
    }
    return $null
}

function Get-FaFolderStatus {
    <#
        known                  - recorded as where Krish wants it, or answered by him
        new-waiting-on-krish   - inside a watched root and not in the record
        watch-root             - the watched root itself
        outside-watch          - not under any watched root
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)] $Preferences)
    $folder = ConvertTo-FaCanonicalPath $Path
    $root = Get-FaWatchRoot -Path $folder -Preferences $Preferences
    if (-not $root) { return 'outside-watch' }
    $depth = Get-FaRelativeDepth -Path $folder -Root $root.Path
    if ($depth -eq 0) { return 'watch-root' }
    # Below the recorded depth a folder belongs to its recorded ancestor.
    while ($depth -gt $root.MaxDepth) {
        $folder = Split-Path -Parent $folder
        $depth--
    }
    if (-not $Preferences.Recorded) { return 'new-waiting-on-krish' }
    if ($Preferences.ByPath.ContainsKey($folder)) {
        $status = [string]$Preferences.ByPath[$folder].status
        if ($status -in @('known', 'answered')) { return 'known' }
    }
    return 'new-waiting-on-krish'
}

function Test-FaKrishConsent {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Action,
        [string] $Destination,
        [Parameter(Mandatory)] $Preferences
    )
    $folder = ConvertTo-FaCanonicalPath $Path
    foreach ($consent in @($Preferences.Data.consents)) {
        if ([string]$consent.approved_by -ne 'Krish') { continue }
        if ([string]::IsNullOrWhiteSpace([string]$consent.approved_at)) { continue }
        if (-not $folder.Equals((ConvertTo-FaCanonicalPath ([string]$consent.path)), [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ([string]$consent.action -ne $Action) { continue }
        if ($Action -eq 'move') {
            if (-not $Destination -or -not $consent.destination) { continue }
            if (-not (ConvertTo-FaCanonicalPath $Destination).Equals(
                    (ConvertTo-FaCanonicalPath ([string]$consent.destination)), [StringComparison]::OrdinalIgnoreCase)) { continue }
        }
        return $true
    }
    return $false
}

function Assert-FaFolderConsent {
    <#
        -Action move|delete   for a folder itself (move covers rename and merge)
        -Action move-file     for a file; refused while its folder waits on Krish
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][ValidateSet('move', 'delete', 'move-file')][string] $Action,
        [string] $Destination,
        [Parameter(Mandatory)] $Preferences,
        [string] $Operation = 'mutation'
    )
    if ($Action -eq 'move-file') {
        $folder = Split-Path -Parent (ConvertTo-FaCanonicalPath $Path)
        $status = Get-FaFolderStatus -Path $folder -Preferences $Preferences
        if ($status -ne 'new-waiting-on-krish') { return }
        if (Test-FaKrishConsent -Path $folder -Action 'move-contents' -Preferences $Preferences) { return }
        throw "REFUSED: $Operation would take a file out of $folder, a folder that is new, waiting on Krish. Nothing inside it moves until he answers for it."
    }
    $status = Get-FaFolderStatus -Path $Path -Preferences $Preferences
    if ($status -eq 'outside-watch') { return }
    if ($status -eq 'watch-root') {
        throw "REFUSED: $Operation targets the watched root $Path itself"
    }
    if (Test-FaKrishConsent -Path $Path -Action $Action -Destination $Destination -Preferences $Preferences) { return }
    $why = if ($status -eq 'new-waiting-on-krish') { 'is new, waiting on Krish' } else { 'is recorded where Krish wants it' }
    throw "REFUSED: $Operation would $Action $Path, which $why. Moving or removing a folder Krish made needs his explicit yes for that folder."
}

function Get-FaFolderTree {
    <#
        Directories only, breadth first, to MaxDepth. Never opens a file,
        never follows a reparse point, never enters a NeverEnter boundary
        (the boundary folder itself is recorded, its contents are not).
        An unreadable directory is returned as unreadable, never as empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][int] $MaxDepth,
        [string[]] $NeverEnter = @(),
        [string[]] $SkipNames = @()
    )
    $base = ConvertTo-FaCanonicalPath $Root
    $folders = [Collections.Generic.List[string]]::new()
    $unreadable = [Collections.Generic.List[string]]::new()
    $queue = [Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([pscustomobject]@{ Path = $base; Depth = 0 })
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($current.Depth -ge $MaxDepth) { continue }
        try {
            $children = @([IO.DirectoryInfo]::new($current.Path).EnumerateDirectories() | Sort-Object Name)
        } catch {
            $unreadable.Add($current.Path)
            continue
        }
        foreach ($child in $children) {
            if ($SkipNames -contains $child.Name -or $child.Name -like '.tmp.drive*') { continue }
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $path = ConvertTo-FaCanonicalPath $child.FullName
            $folders.Add($path)
            $boundary = @($NeverEnter | Where-Object { Test-FaPathWithin -Path $path -Root $_ }).Count -gt 0
            if (-not $boundary) {
                $queue.Enqueue([pscustomobject]@{ Path = $path; Depth = $current.Depth + 1 })
            }
        }
    }
    return [pscustomobject]@{ Folders = @($folders); Unreadable = @($unreadable) }
}

function Write-FaFolderPreferences {
    param([Parameter(Mandatory)] $Preferences)
    $data = $Preferences.Data
    $data.folders = @($data.folders | Sort-Object { [string]$_.path })
    Write-FaAtomicJson -Path $Preferences.Path -Value $data -Depth 12
}

function Save-FaFolderRecordToGitHub {
    <#
        Commit exactly the named paths on main and push them. Run on Krish's
        machine only after he has said yes on screen. Returns a sentence for
        him; never throws for a git failure, because the record on his machine
        is still good when GitHub cannot be reached.
    #>
    param(
        [Parameter(Mandatory)][string] $Repo,
        [Parameter(Mandatory)][string[]] $Paths,
        [Parameter(Mandatory)][string] $Message
    )
    $branch = (& git -C $Repo rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1)
    if ($branch -ne 'main') { return "Saved on this PC only: the filearchives folder is on branch '$branch', not main." }
    & git -C $Repo add -- @Paths 2>&1 | Out-Null
    & git -C $Repo diff --cached --quiet -- @Paths 2>$null
    if ($LASTEXITCODE -ne 0) {
        & git -C $Repo commit -m $Message -m 'Ruling (Krish, 2026-10-23): filearchives never moves a folder Krish made without asking first.' -- @Paths 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return 'Saved on this PC only: git could not make the commit.' }
    }
    # Pushes anything an earlier, offline save left behind as well.
    & git -C $Repo push origin main 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return 'Saved on this PC. GitHub could not be reached, so it will go up with the next save.' }
    return 'Saved to the filearchives repository on GitHub.'
}
