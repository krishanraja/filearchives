[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $SourceId,
    [string] $RunId,
    [int] $BatchDirectories = 250,
    [int] $MaxSegments = 0,
    [long] $ItemBudget = 5000000,
    [int] $DirectoryAttemptBudget = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FaInventoryScriptPath = $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

$script:FaImageExtensions = @(
    '.jpg', '.jpeg', '.png', '.heic', '.gif', '.bmp', '.tif', '.tiff',
    '.webp', '.raw', '.dng', '.cr2', '.nef', '.arw'
)
$script:FaVideoExtensions = @(
    '.mp4', '.mov', '.avi', '.wmv', '.m4v', '.webm', '.flv', '.mkv',
    '.3gp', '.mts', '.m2ts'
)
$script:FaAudioExtensions = @(
    '.mp3', '.wav', '.m4a', '.aiff', '.flac', '.ogg', '.aax', '.opus', '.aac'
)
$script:FaGeneratedSegments = @(
    'node_modules', '__pycache__', '.venv', 'venv', 'dist', 'build',
    '.next', '.turbo', 'coverage', '.cache'
)

function Get-FaTextSha256 {
    param([Parameter(Mandatory)][string] $Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([Convert]::ToHexString($sha.ComputeHash($bytes))).ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-FaMediaKind {
    param([string] $Extension)
    $ext = if ($Extension) { $Extension.ToLowerInvariant() } else { '' }
    if ($ext -in $script:FaImageExtensions) { return 'image' }
    if ($ext -in $script:FaVideoExtensions) { return 'video' }
    if ($ext -in $script:FaAudioExtensions) { return 'audio' }
    return $null
}

function Get-FaMediaNoiseHint {
    param([string] $Name, [string] $MediaKind)
    if (-not $MediaKind) { return $null }
    $stem = [IO.Path]::GetFileNameWithoutExtension($Name)
    if ($stem -match '(?i)(^|[ _-])(screenshot|screen.?shot|screen.?capture|meme|thumbnail|thumb)([ _-]|$)') {
        return 'possible-screenshot-meme-or-thumbnail'
    }
    return $null
}

function Get-FaSensitiveNameHint {
    param([string] $Name)
    if ($Name -match '(?i)^(\.env($|\.)|id_rsa|id_ed25519|credentials?\.json$|.*\.(pem|pfx|p12|key|kdbx)$)') {
        return 'possible-credential-or-secret'
    }
    if ($Name -match '(?i)(password|secret|recovery.?code|private.?key)') {
        return 'sensitive-name'
    }
    return $null
}

function Get-FaGeneratedHint {
    param([string] $RelativePath)
    $segments = [regex]::Split($RelativePath, '[\\/]')
    foreach ($segment in $segments) {
        if ($segment.ToLowerInvariant() -in $script:FaGeneratedSegments) {
            return "generated-tree:$($segment.ToLowerInvariant())"
        }
    }
    return $null
}

function New-FaInventoryItem {
    param(
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)][string] $Root,
        [string] $Traversal = $null
    )
    $relative = [IO.Path]::GetRelativePath($Root, $Item.FullName)
    $extension = if ($Item.PSIsContainer) { '' } elseif ($Item.Extension) {
        $Item.Extension.ToLowerInvariant()
    } else { '' }
    $mediaKind = if ($Item.PSIsContainer) { $null } else { Get-FaMediaKind $extension }
    return [pscustomobject]@{
        RelativePath = $relative
        Kind = if ($Item.PSIsContainer) { 'directory' } else { 'file' }
        Length = if ($Item.PSIsContainer) { $null } else { [long]$Item.Length }
        Extension = $extension
        CreationTimeUtc = $Item.CreationTimeUtc.ToString('o')
        LastWriteTimeUtc = $Item.LastWriteTimeUtc.ToString('o')
        Attributes = [string]$Item.Attributes
        IsReparsePoint = [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)
        Traversal = $Traversal
        MediaKind = $mediaKind
        MediaNoiseHint = Get-FaMediaNoiseHint -Name $Item.Name -MediaKind $mediaKind
        SensitiveNameHint = Get-FaSensitiveNameHint -Name $Item.Name
        GeneratedHint = Get-FaGeneratedHint -RelativePath $relative
    }
}

function Get-FaInventorySeal {
    param(
        [Parameter(Mandatory)] $Workspace,
        [Parameter(Mandatory)] $Source
    )
    $parts = @(
        'inventory-v1',
        (Get-FaSha256 $Workspace.Origin),
        (Get-FaSha256 $script:FaInventoryScriptPath),
        (Get-FaSha256 (Join-Path $repo 'guards\workspace.ps1')),
        $Source.Id,
        $Source.Path,
        [string]$Source.FollowReparsePoints,
        (@($Workspace.ProtectedRoots) -join '|'),
        (@($Workspace.ProtectedNames) -join '|')
    )
    return Get-FaTextSha256 ($parts -join "`n")
}

function Get-FaInventoryState {
    param([Parameter(Mandatory)][string] $SegmentsPath, [int] $DirectoryAttemptBudget)

    $pending = [Collections.Generic.SortedSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $completed = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $targets = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $attempts = @{}
    $null = $pending.Add('.')
    $itemCount = [long]0
    $terminalErrors = [long]0
    $protectedSkipped = [long]0
    $reparseSkipped = [long]0
    $segments = @(Get-ChildItem -LiteralPath $SegmentsPath -Filter 'segment-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name)

    foreach ($segmentFile in $segments) {
        $segment = Get-Content -LiteralPath $segmentFile.FullName -Raw | ConvertFrom-Json -Depth 32
        $itemCount += [long]$segment.ItemCount
        $protectedSkipped += [long]$segment.ProtectedEntriesSkipped
        $reparseSkipped += [long]$segment.ReparseDirectoriesSkipped
        foreach ($processed in @($segment.ProcessedDirectories)) {
            $null = $pending.Remove([string]$processed.RelativePath)
            if ($processed.Status -eq 'complete') {
                $null = $completed.Add([string]$processed.RelativePath)
            } else {
                $attempt = [int]$processed.Attempt
                $attempts[[string]$processed.RelativePath] = $attempt
                if ($attempt -lt $DirectoryAttemptBudget) {
                    $null = $pending.Add([string]$processed.RelativePath)
                } else {
                    $null = $completed.Add([string]$processed.RelativePath)
                    $terminalErrors++
                }
            }
        }
        foreach ($discovered in @($segment.DiscoveredDirectories)) {
            $relative = [string]$discovered.RelativePath
            if ($discovered.TargetIdentity) {
                $null = $targets.Add([string]$discovered.TargetIdentity)
            }
            if (-not $completed.Contains($relative)) { $null = $pending.Add($relative) }
        }
    }

    return [pscustomobject]@{
        Pending = $pending
        Completed = $completed
        TargetIdentities = $targets
        Attempts = $attempts
        ItemCount = $itemCount
        SegmentCount = $segments.Count
        TerminalErrors = $terminalErrors
        ProtectedSkipped = $protectedSkipped
        ReparseSkipped = $reparseSkipped
    }
}

function Get-FaTraversalDecision {
    param(
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)] $Source,
        [Parameter(Mandatory)] $State
    )
    $isReparse = [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    if (-not $isReparse) {
        return [pscustomobject]@{ Traverse = $true; Reason = 'normal'; TargetIdentity = $null }
    }
    $isSystem = [bool]($Item.Attributes -band [IO.FileAttributes]::System)
    if ($isSystem -or -not $Source.FollowReparsePoints) {
        return [pscustomobject]@{ Traverse = $false; Reason = 'skipped-reparse'; TargetIdentity = $null }
    }
    try {
        $target = $Item.ResolveLinkTarget($true)
        if ($target) {
            $targetPath = ConvertTo-FaCanonicalPath $target.FullName
            if (-not (Test-FaPathWithin -Path $targetPath -Root $Source.Path)) {
                return [pscustomobject]@{ Traverse = $false; Reason = 'reparse-outside-source'; TargetIdentity = $targetPath }
            }
            if ($State.TargetIdentities.Contains($targetPath)) {
                return [pscustomobject]@{ Traverse = $false; Reason = 'reparse-cycle-or-alias'; TargetIdentity = $targetPath }
            }
            return [pscustomobject]@{ Traverse = $true; Reason = 'reparse-in-source'; TargetIdentity = $targetPath }
        }
    } catch {
        # Cloud placeholders can be reparse points without link targets.
    }
    return [pscustomobject]@{ Traverse = $true; Reason = 'cloud-reparse'; TargetIdentity = $null }
}

function Complete-FaInventory {
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)] $Envelope,
        [Parameter(Mandatory)] $State
    )
    $segmentFiles = @(Get-ChildItem -LiteralPath (Join-Path $RunPath 'segments') `
        -Filter 'segment-*.json' -File | Sort-Object Name)
    $segmentEvidence = @($segmentFiles | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Sha256 = Get-FaSha256 $_.FullName; Bytes = $_.Length }
    })
    $status = if ($State.TerminalErrors -gt 0) { 'partial' } else { 'complete' }
    $summary = [pscustomobject]@{
        SchemaVersion = 1
        RunId = $Envelope.RunId
        SourceId = $Envelope.SourceId
        SourceRoot = $Envelope.SourceRoot
        InputSeal = $Envelope.InputSeal
        Status = $status
        Items = $State.ItemCount
        DirectoriesCompleted = $State.Completed.Count
        TerminalDirectoryErrors = $State.TerminalErrors
        ProtectedEntriesSkipped = $State.ProtectedSkipped
        ReparseDirectoriesSkipped = $State.ReparseSkipped
        Segments = $segmentEvidence
        CompletedAt = [DateTimeOffset]::Now.ToString('o')
    }
    $summaryPath = Join-Path $RunPath 'inventory-summary.json'
    Write-FaAtomicJson -Path $summaryPath -Value $summary -Depth 10
    return $summary
}

function Invoke-FaInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $InventorySourceId,
        [Parameter(Mandatory)][string] $InventoryRunId,
        [int] $DirectoriesPerSegment = 250,
        [int] $SegmentLimit = 0,
        [long] $TotalItemBudget = 5000000,
        [int] $PerDirectoryAttemptBudget = 3
    )

    if ($InventoryRunId -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$') {
        throw 'RunId must be 1-80 filesystem-safe characters'
    }
    if ($DirectoriesPerSegment -lt 1) { throw 'BatchDirectories must be positive' }
    if ($TotalItemBudget -lt 1) { throw 'ItemBudget must be positive' }

    $workspace = Import-FaWorkspace -ConfigPath $WorkspacePath
    $source = @($workspace.Sources | Where-Object Id -eq $InventorySourceId)
    if ($source.Count -ne 1) { throw "source id did not resolve exactly once: $InventorySourceId" }
    $source = $source[0]
    Assert-FaNotProtected -Path $source.Path -Workspace $workspace -Operation 'inventory'

    $runPath = Join-Path $workspace.Audit ("runs\{0}\inventory\{1}" -f $InventoryRunId, $source.Id)
    $segmentsPath = Join-Path $runPath 'segments'
    New-Item -ItemType Directory -Path $segmentsPath -Force | Out-Null
    $lockPath = Join-Path $runPath 'inventory.lock'
    $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $seal = Get-FaInventorySeal -Workspace $workspace -Source $source
        $envelopePath = Join-Path $runPath 'run-envelope.json'
        if (Test-Path -LiteralPath $envelopePath) {
            $envelope = Get-Content -LiteralPath $envelopePath -Raw | ConvertFrom-Json -Depth 16
            if ($envelope.InputSeal -ne $seal) {
                throw 'input seal changed; use a new RunId rather than resuming stale state'
            }
            if ([long]$envelope.ItemBudget -ne $TotalItemBudget -or
                [int]$envelope.DirectoryAttemptBudget -ne $PerDirectoryAttemptBudget) {
                throw 'run budgets changed; resume with the original budgets'
            }
        } else {
            $envelope = [pscustomobject]@{
                SchemaVersion = 1
                RunId = $InventoryRunId
                InputSeal = $seal
                CurrentStage = '04_inventory'
                SourceId = $source.Id
                SourceRoot = $source.Path
                Checkpoint = $segmentsPath
                DirectoryAttemptBudget = $PerDirectoryAttemptBudget
                ItemBudget = $TotalItemBudget
                LeaseOwner = "pid:$PID"
                ChildProcesses = @()
                CompletionEvidence = (Join-Path $runPath 'inventory-summary.json')
                RecoveryEntrypoint = "pwsh -File stages\04_inventory\build_inventory.ps1 -ConfigPath <path> -SourceId $($source.Id) -RunId $InventoryRunId"
                Status = 'running'
                CreatedAt = [DateTimeOffset]::Now.ToString('o')
                UpdatedAt = [DateTimeOffset]::Now.ToString('o')
            }
            Write-FaAtomicJson -Path $envelopePath -Value $envelope -Depth 12
        }

        if (-not (Test-Path -LiteralPath $source.Path -PathType Container)) {
            $envelope.Status = 'suspended-source-unavailable'
            $envelope.UpdatedAt = [DateTimeOffset]::Now.ToString('o')
            Write-FaAtomicJson -Path $envelopePath -Value $envelope -Depth 12
            return [pscustomobject]@{ RunId=$InventoryRunId; SourceId=$source.Id; Status=$envelope.Status }
        }

        $state = Get-FaInventoryState -SegmentsPath $segmentsPath `
            -DirectoryAttemptBudget $PerDirectoryAttemptBudget
        if ($state.ItemCount -ge $TotalItemBudget) {
            throw "item budget exhausted at $($state.ItemCount)"
        }
        if ($state.Pending.Count -eq 0) {
            return Complete-FaInventory -RunPath $runPath -Envelope $envelope -State $state
        }

        $segmentsMade = 0
        while ($state.Pending.Count -gt 0 -and
            ($SegmentLimit -eq 0 -or $segmentsMade -lt $SegmentLimit)) {
            $processed = [Collections.Generic.List[object]]::new()
            $discovered = [Collections.Generic.List[object]]::new()
            $itemsOut = [Collections.Generic.List[object]]::new()
            $protectedSkipped = [long]0
            $reparseSkipped = [long]0
            $budgetPaused = $false

            while ($state.Pending.Count -gt 0 -and $processed.Count -lt $DirectoriesPerSegment) {
                $relativeDirectory = $state.Pending.Min
                $null = $state.Pending.Remove($relativeDirectory)
                $absoluteDirectory = if ($relativeDirectory -eq '.') {
                    $source.Path
                } else { Join-Path $source.Path $relativeDirectory }
                Assert-FaNotProtected -Path $absoluteDirectory -Workspace $workspace -Operation 'inventory traversal'

                try {
                    $children = @(Get-ChildItem -LiteralPath $absoluteDirectory -Force -ErrorAction Stop |
                        Sort-Object FullName)
                } catch {
                    $attempt = if ($state.Attempts.ContainsKey($relativeDirectory)) {
                        [int]$state.Attempts[$relativeDirectory] + 1
                    } else { 1 }
                    $processed.Add([pscustomobject]@{
                        RelativePath = $relativeDirectory
                        Status = 'error'
                        Attempt = $attempt
                        ErrorType = $_.Exception.GetType().FullName
                        ErrorMessage = $_.Exception.Message
                        ObservedAt = [DateTimeOffset]::Now.ToString('o')
                    })
                    continue
                }

                $visible = @($children | Where-Object {
                    -not (Test-FaProtectedPath -Path $_.FullName -Workspace $workspace)
                })
                $protectedSkipped += [long]($children.Count - $visible.Count)
                if ($state.ItemCount + $itemsOut.Count + $visible.Count -gt $TotalItemBudget) {
                    $null = $state.Pending.Add($relativeDirectory)
                    $budgetPaused = $true
                    break
                }

                foreach ($item in $visible) {
                    $traversal = $null
                    $targetIdentity = $null
                    if ($item.PSIsContainer) {
                        $decision = Get-FaTraversalDecision -Item $item -Source $source -State $state
                        $traversal = $decision.Reason
                        $targetIdentity = $decision.TargetIdentity
                        if ($decision.Traverse) {
                            $relativeChild = [IO.Path]::GetRelativePath($source.Path, $item.FullName)
                            $discovered.Add([pscustomobject]@{
                                RelativePath = $relativeChild
                                TargetIdentity = $targetIdentity
                            })
                            if ($targetIdentity) { $null = $state.TargetIdentities.Add($targetIdentity) }
                        } else { $reparseSkipped++ }
                    }
                    try {
                        $itemsOut.Add((New-FaInventoryItem -Item $item -Root $source.Path -Traversal $traversal))
                    } catch {
                        $itemsOut.Add([pscustomobject]@{
                            RelativePath = [IO.Path]::GetRelativePath($source.Path, $item.FullName)
                            Kind = if ($item.PSIsContainer) { 'directory-error' } else { 'file-error' }
                            ErrorType = $_.Exception.GetType().FullName
                            ErrorMessage = $_.Exception.Message
                        })
                    }
                }
                $processed.Add([pscustomobject]@{
                    RelativePath = $relativeDirectory
                    Status = 'complete'
                    Attempt = 1
                    VisibleChildren = $visible.Count
                    IsEmpty = ($visible.Count -eq 0)
                    ObservedAt = [DateTimeOffset]::Now.ToString('o')
                })
            }

            if ($processed.Count -eq 0 -and $itemsOut.Count -eq 0) {
                if ($budgetPaused) { throw 'item budget would be exceeded by the next directory' }
                throw 'inventory made no progress'
            }

            $sequence = $state.SegmentCount + 1
            $segment = [pscustomobject]@{
                SchemaVersion = 1
                RunId = $InventoryRunId
                SourceId = $source.Id
                InputSeal = $seal
                Sequence = $sequence
                ProcessedDirectories = @($processed)
                DiscoveredDirectories = @($discovered)
                Items = @($itemsOut)
                ItemCount = $itemsOut.Count
                ProtectedEntriesSkipped = $protectedSkipped
                ReparseDirectoriesSkipped = $reparseSkipped
                CommittedAt = [DateTimeOffset]::Now.ToString('o')
            }
            $segmentPath = Join-Path $segmentsPath ("segment-{0:D8}.json" -f $sequence)
            Write-FaAtomicJson -Path $segmentPath -Value $segment -Depth 16
            $segmentsMade++

            $state = Get-FaInventoryState -SegmentsPath $segmentsPath `
                -DirectoryAttemptBudget $PerDirectoryAttemptBudget
            $envelope.Status = if ($state.Pending.Count -eq 0) { 'verifying' } else { 'running' }
            $envelope.LeaseOwner = "pid:$PID"
            $envelope.UpdatedAt = [DateTimeOffset]::Now.ToString('o')
            $envelope | Add-Member -NotePropertyName SegmentCount -NotePropertyValue $state.SegmentCount -Force
            $envelope | Add-Member -NotePropertyName ItemsCommitted -NotePropertyValue $state.ItemCount -Force
            $envelope | Add-Member -NotePropertyName PendingDirectories -NotePropertyValue $state.Pending.Count -Force
            Write-FaAtomicJson -Path $envelopePath -Value $envelope -Depth 12
            Write-Host ("  {0}: segment {1}, {2:N0} items, {3:N0} pending directories" -f `
                $source.Id, $state.SegmentCount, $state.ItemCount, $state.Pending.Count)
        }

        if ($state.Pending.Count -eq 0) {
            $summary = Complete-FaInventory -RunPath $runPath -Envelope $envelope -State $state
            $envelope.Status = $summary.Status
            $envelope.UpdatedAt = [DateTimeOffset]::Now.ToString('o')
            Write-FaAtomicJson -Path $envelopePath -Value $envelope -Depth 12
            return $summary
        }

        $envelope.Status = 'paused-segment-limit'
        $envelope.UpdatedAt = [DateTimeOffset]::Now.ToString('o')
        Write-FaAtomicJson -Path $envelopePath -Value $envelope -Depth 12
        return [pscustomobject]@{
            RunId = $InventoryRunId
            SourceId = $source.Id
            Status = $envelope.Status
            Segments = $state.SegmentCount
            Items = $state.ItemCount
            PendingDirectories = $state.Pending.Count
        }
    } finally {
        $lock.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $SourceId -or -not $RunId) { throw '-SourceId and -RunId are required' }
    Invoke-FaInventory -WorkspacePath $ConfigPath -InventorySourceId $SourceId `
        -InventoryRunId $RunId -DirectoriesPerSegment $BatchDirectories `
        -SegmentLimit $MaxSegments -TotalItemBudget $ItemBudget `
        -PerDirectoryAttemptBudget $DirectoryAttemptBudget | ConvertTo-Json -Depth 12
}
