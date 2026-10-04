[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $RunId,
    [string[]] $SourceId = @('c-dev', 'l-dev')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

function Invoke-FaGitText {
    param([string] $Repository, [string[]] $Arguments)
    $output = @(& git -c "safe.directory=$Repository" -C $Repository @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($output -join "`n").Trim()
}

function Protect-FaRemoteUrl {
    param([string] $Url)
    if (-not $Url) { return $null }
    return $Url -replace '(?i)(https?://)[^/@]+@', '$1[redacted]@'
}

function Get-FaRemoteIdentity {
    param([string] $Remote)
    if (-not $Remote) { return $null }
    $clean = $Remote -replace '\.git$', ''
    if ($clean -match '(?i)(?:github\.com|gitlab\.com|bitbucket\.org)[/:]([^/]+/[^/]+)$') {
        return $Matches[1]
    }
    return $null
}

function Get-FaRepositoryRoots {
    param([Parameter(Mandatory)][string] $SourceRoot)
    $results = [Collections.Generic.List[string]]::new()
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($SourceRoot)
    $skipNames = @('.git', 'node_modules', '.venv', 'venv', 'dist', 'build',
        '.next', '.turbo', 'coverage', '.cache', '__pycache__')
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        try {
            $children = @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)
        } catch { continue }
        if (@($children | Where-Object Name -eq '.git').Count -gt 0) {
            $results.Add($directory)
            continue
        }
        foreach ($child in $children) {
            if (-not $child.PSIsContainer) { continue }
            if ($child.Name -in $skipNames) { continue }
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $pending.Push($child.FullName)
        }
    }
    return @($results)
}

function Invoke-FaRepositoryAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $InventoryRunId,
        [string[]] $InventorySourceIds = @('c-dev', 'l-dev')
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git is required for repository analysis'
    }
    $workspace = Import-FaWorkspace -ConfigPath $WorkspacePath
    $repositories = [Collections.Generic.List[object]]::new()
    $unavailable = [Collections.Generic.List[string]]::new()
    $rootsSeen = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)

    foreach ($id in $InventorySourceIds) {
        $source = @($workspace.Sources | Where-Object Id -eq $id)
        if ($source.Count -ne 1) { throw "source id did not resolve exactly once: $id" }
        $source = $source[0]
        if (-not (Test-Path -LiteralPath $source.Path -PathType Container)) {
            $unavailable.Add($id)
            continue
        }
        Write-Host ("  repositories: discovering {0}" -f $id)
        $discoveredRoots = @(Get-FaRepositoryRoots -SourceRoot $source.Path)
        foreach ($discoveredRoot in $discoveredRoots) {
            $root = ConvertTo-FaCanonicalPath $discoveredRoot
            if (-not $rootsSeen.Add($root)) { continue }
            $inside = Invoke-FaGitText -Repository $root -Arguments @('rev-parse', '--is-inside-work-tree')
            if ($inside -ne 'true') { continue }

            $remote = Protect-FaRemoteUrl (Invoke-FaGitText -Repository $root `
                -Arguments @('remote', 'get-url', 'origin'))
            $trackedStatus = Invoke-FaGitText -Repository $root `
                -Arguments @('status', '--porcelain=v1', '--untracked-files=no')
            $fullStatus = Invoke-FaGitText -Repository $root `
                -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
            $trackedCount = if ($trackedStatus) { @($trackedStatus -split "`n").Count } else { 0 }
            $allCount = if ($fullStatus) { @($fullStatus -split "`n").Count } else { 0 }
            $untrackedCount = [math]::Max(0, $allCount - $trackedCount)
            $lastCommitText = Invoke-FaGitText -Repository $root `
                -Arguments @('log', '-1', '--format=%cI')
            $lastCommit = if ($lastCommitText) {
                [DateTimeOffset]::Parse($lastCommitText).ToString('o')
            } else { $null }
            $relative = [IO.Path]::GetRelativePath($source.Path, $root)
            $critical = $id -eq 'c-dev' -and
                $relative.Equals('krishanraja\mm-ctrl', [StringComparison]::OrdinalIgnoreCase)

            $repositories.Add([pscustomobject]@{
                SourceId = $id
                RelativePath = $relative
                RepositoryRoot = $root
                Remote = $remote
                RemoteIdentity = Get-FaRemoteIdentity $remote
                Branch = Invoke-FaGitText -Repository $root `
                    -Arguments @('branch', '--show-current')
                Head = Invoke-FaGitText -Repository $root `
                    -Arguments @('rev-parse', 'HEAD')
                LastCommit = $lastCommit
                Upstream = Invoke-FaGitText -Repository $root `
                    -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}')
                TrackedChanges = [int]$trackedCount
                UntrackedEntries = [int]$untrackedCount
                Dirty = [bool]($allCount -gt 0)
                Critical = $critical
            })
            Write-Host ("  repositories: {0} dirty={1} changes={2}" -f `
                $relative, ($allCount -gt 0), $allCount)
        }
    }

    $duplicates = @($repositories | Where-Object RemoteIdentity |
        Group-Object RemoteIdentity | Where-Object Count -gt 1 | ForEach-Object {
            [pscustomobject]@{
                RemoteIdentity = $_.Name
                Count = $_.Count
                Repositories = @($_.Group | ForEach-Object RepositoryRoot)
            }
        })
    $result = [pscustomobject]@{
        SchemaVersion = 1
        RunId = $InventoryRunId
        ObservedAt = [DateTimeOffset]::Now.ToString('o')
        UnavailableSources = @($unavailable)
        RepositoryCount = $repositories.Count
        DirtyRepositoryCount = @($repositories | Where-Object Dirty).Count
        DuplicateRemoteIdentities = $duplicates
        Repositories = @($repositories | Sort-Object SourceId, RelativePath)
    }
    $path = Join-Path $workspace.Audit `
        ("runs\{0}\analysis\repository-analysis.json" -f $InventoryRunId)
    Write-FaAtomicJson -Path $path -Value $result -Depth 16
    return $result
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RunId) { throw '-RunId is required' }
    $result = Invoke-FaRepositoryAnalysis -WorkspacePath $ConfigPath `
        -InventoryRunId $RunId -InventorySourceIds $SourceId
    [pscustomobject]@{
        RunId = $result.RunId
        Repositories = $result.RepositoryCount
        Dirty = $result.DirtyRepositoryCount
        DuplicateRemoteIdentities = @($result.DuplicateRemoteIdentities).Count
        UnavailableSources = @($result.UnavailableSources)
    } | ConvertTo-Json -Depth 8
}
