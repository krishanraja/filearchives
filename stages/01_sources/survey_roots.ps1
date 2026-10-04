[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string[]] $SourceId,
    [switch] $NoWrite,
    [int] $ProgressEvery = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')

function Add-FaCounter {
    param([hashtable] $Counter, [string] $Key, [long] $Amount = 1)
    if (-not $Counter.ContainsKey($Key)) { $Counter[$Key] = [long]0 }
    $Counter[$Key] = [long]$Counter[$Key] + $Amount
}

function Get-FaTopSegment {
    param([string] $Root, [string] $Path, [bool] $IsContainer)
    $relative = [IO.Path]::GetRelativePath($Root, $Path)
    if ($relative -eq '.') { return '.' }
    $parts = [regex]::Split($relative, '[\\/]')
    if ($parts.Count -eq 1 -and -not $IsContainer) { return '[root]' }
    return $parts[0]
}

function Write-FaSurveyHeartbeat {
    param(
        [Parameter(Mandatory)] $Workspace,
        [Parameter(Mandatory)] $Source,
        [long] $Directories,
        [long] $Files,
        [long] $Bytes
    )
    New-Item -ItemType Directory -Path $Workspace.Audit -Force | Out-Null
    $path = Join-Path $Workspace.Audit ("survey-heartbeat-{0}.json" -f $Source.Id)
    $temp = $path + '.writing'
    $body = [pscustomobject]@{
        SourceId = $Source.Id
        Root = $Source.Path
        Status = 'running'
        DirectoriesProcessed = $Directories
        FilesObserved = $Files
        BytesObserved = $Bytes
        At = [DateTimeOffset]::Now.ToString('o')
    } | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($temp, $body, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp, $path, $true)
}

function Invoke-FaSourceSurvey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Workspace,
        [Parameter(Mandatory)] $Source,
        [int] $HeartbeatEvery = 1000
    )

    $started = [DateTimeOffset]::Now
    Assert-FaNotProtected -Path $Source.Path -Workspace $Workspace -Operation 'source survey'

    if (-not (Test-Path -LiteralPath $Source.Path -PathType Container)) {
        return [pscustomobject]@{
            SourceId = $Source.Id
            Root = $Source.Path
            Status = 'unavailable'
            Files = $null
            Bytes = $null
            Directories = $null
            EmptyDirectories = $null
            ProtectedEntriesSkipped = $null
            ReparseDirectoriesSkipped = $null
            UnreadableDirectories = $null
            Extensions = @{}
            TopLevel = @{}
            StartedAt = $started.ToString('o')
            FinishedAt = [DateTimeOffset]::Now.ToString('o')
        }
    }

    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($Source.Path)
    $visitedLogical = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $visitedTargets = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $fileCount = [long]0
    $byteCount = [long]0
    $directoryCount = [long]0
    $emptyDirectoryCount = [long]0
    $protectedSkipped = [long]0
    $reparseSkipped = [long]0
    $unreadable = [long]0
    $extensions = @{}
    $topLevel = @{}

    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        $canonicalDirectory = ConvertTo-FaCanonicalPath $directory
        if (-not $visitedLogical.Add($canonicalDirectory)) {
            $reparseSkipped++
            continue
        }
        if (Test-FaProtectedPath -Path $directory -Workspace $Workspace) {
            $protectedSkipped++
            continue
        }

        try {
            $items = @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)
        } catch {
            $unreadable++
            continue
        }

        $visibleChildren = [long]0
        foreach ($item in $items) {
            if (Test-FaProtectedPath -Path $item.FullName -Workspace $Workspace) {
                $protectedSkipped++
                continue
            }
            $visibleChildren++
            $top = Get-FaTopSegment -Root $Source.Path -Path $item.FullName -IsContainer $item.PSIsContainer

            if ($item.PSIsContainer) {
                $directoryCount++
                Add-FaCounter -Counter $topLevel -Key ("directory:" + $top)
                $isReparse = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
                if ($isReparse) {
                    $isSystem = [bool]($item.Attributes -band [IO.FileAttributes]::System)
                    if ($isSystem -or -not $Source.FollowReparsePoints) {
                        $reparseSkipped++
                        continue
                    }
                    try {
                        $target = $item.ResolveLinkTarget($true)
                        if ($target) {
                            $targetPath = ConvertTo-FaCanonicalPath $target.FullName
                            if (-not (Test-FaPathWithin -Path $targetPath -Root $Source.Path) -or
                                -not $visitedTargets.Add($targetPath)) {
                                $reparseSkipped++
                                continue
                            }
                        }
                    } catch {
                        # Cloud placeholder directories can be reparse points
                        # without a conventional link target. They remain
                        # eligible when the source explicitly allows them.
                    }
                }
                $queue.Enqueue($item.FullName)
                continue
            }

            $fileCount++
            $length = [long]$item.Length
            $byteCount += $length
            $extension = if ($item.Extension) { $item.Extension.ToLowerInvariant() } else { '[none]' }
            Add-FaCounter -Counter $extensions -Key $extension
            Add-FaCounter -Counter $topLevel -Key ("files:" + $top)
            Add-FaCounter -Counter $topLevel -Key ("bytes:" + $top) -Amount $length
        }

        if ($visibleChildren -eq 0) { $emptyDirectoryCount++ }
        if ($HeartbeatEvery -gt 0 -and
            $visitedLogical.Count % $HeartbeatEvery -eq 0) {
            Write-FaSurveyHeartbeat -Workspace $Workspace -Source $Source `
                -Directories $visitedLogical.Count -Files $fileCount -Bytes $byteCount
            Write-Host ("  {0}: {1:N0} directories, {2:N0} files" -f `
                $Source.Id, $visitedLogical.Count, $fileCount)
        }
    }

    return [pscustomobject]@{
        SourceId = $Source.Id
        Root = $Source.Path
        Status = if ($unreadable -gt 0) { 'partial' } else { 'complete' }
        Files = $fileCount
        Bytes = $byteCount
        Directories = $directoryCount
        EmptyDirectories = $emptyDirectoryCount
        ProtectedEntriesSkipped = $protectedSkipped
        ReparseDirectoriesSkipped = $reparseSkipped
        UnreadableDirectories = $unreadable
        Extensions = $extensions
        TopLevel = $topLevel
        StartedAt = $started.ToString('o')
        FinishedAt = [DateTimeOffset]::Now.ToString('o')
    }
}

function Write-FaSurveyResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Workspace,
        [Parameter(Mandatory)] $Result
    )

    New-Item -ItemType Directory -Path $Workspace.Audit -Force | Out-Null
    $path = Join-Path $Workspace.Audit 'source-surveys.jsonl'
    $line = $Result | ConvertTo-Json -Depth 12 -Compress
    $encoding = [Text.UTF8Encoding]::new($false)
    $stream = [IO.FileStream]::new(
        $path,
        [IO.FileMode]::Append,
        [IO.FileAccess]::Write,
        [IO.FileShare]::Read)
    try {
        $writer = [IO.StreamWriter]::new($stream, $encoding)
        try {
            $writer.WriteLine($line)
            $writer.Flush()
            $stream.Flush($true)
        } finally {
            $writer.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
    return $path
}

if ($MyInvocation.InvocationName -ne '.') {
    $workspace = Import-FaWorkspace -ConfigPath $ConfigPath
    $selected = @($workspace.Sources | Where-Object {
        -not $SourceId -or $_.Id -in $SourceId
    })
    if ($selected.Count -eq 0) {
        throw 'no configured source matched -SourceId'
    }

    $available = 0
    foreach ($source in $selected) {
        $result = Invoke-FaSourceSurvey -Workspace $workspace -Source $source `
            -HeartbeatEvery $ProgressEvery
        if ($result.Status -ne 'unavailable') { $available++ }
        if (-not $NoWrite) {
            Write-FaSurveyResult -Workspace $workspace -Result $result | Out-Null
        }
        $result | ConvertTo-Json -Depth 12
    }
    if ($available -eq 0) {
        throw 'all selected sources are unavailable; no empty result was accepted'
    }
}
