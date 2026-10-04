[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $SourceId,
    [string] $RunId,
    [switch] $ReconcileLive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

function Get-FaLiveInventoryIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Workspace,
        [Parameter(Mandatory)] $Source
    )

    $paths = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $pending = [Collections.Generic.Stack[string]]::new()
    $visited = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $targets = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $pending.Push($Source.Path)
    $files = [long]0
    $directories = [long]0
    $bytes = [long]0
    $unreadable = [Collections.Generic.List[string]]::new()

    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        $directoryIdentity = ConvertTo-FaCanonicalPath $directory
        if (-not $visited.Add($directoryIdentity)) { continue }
        Assert-FaNotProtected -Path $directoryIdentity -Workspace $Workspace `
            -Operation 'live inventory verification'
        try {
            $children = @(Get-ChildItem -LiteralPath $directoryIdentity -Force `
                -ErrorAction Stop)
        } catch {
            $relativeError = if ($directoryIdentity -eq $Source.Path) { '.' } else {
                [IO.Path]::GetRelativePath($Source.Path, $directoryIdentity)
            }
            $unreadable.Add($relativeError)
            continue
        }

        foreach ($item in $children) {
            if (Test-FaProtectedPath -Path $item.FullName -Workspace $Workspace) {
                continue
            }
            $relative = [IO.Path]::GetRelativePath($Source.Path, $item.FullName)
            $null = $paths.Add($relative)
            if (-not $item.PSIsContainer) {
                $files++
                $bytes += [long]$item.Length
                continue
            }

            $directories++
            $isReparse = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if (-not $isReparse) {
                $pending.Push($item.FullName)
                continue
            }
            $isSystem = [bool]($item.Attributes -band [IO.FileAttributes]::System)
            if ($isSystem -or -not $Source.FollowReparsePoints) { continue }
            try {
                $target = $item.ResolveLinkTarget($true)
                if ($target) {
                    $targetIdentity = ConvertTo-FaCanonicalPath $target.FullName
                    if (-not (Test-FaPathWithin -Path $targetIdentity -Root $Source.Path)) {
                        continue
                    }
                    if (-not $targets.Add($targetIdentity)) { continue }
                }
            } catch {
                # Some cloud placeholders are reparse points without a link target.
            }
            $pending.Push($item.FullName)
        }
    }

    return [pscustomobject]@{
        Paths = $paths
        Items = [long]($files + $directories)
        Files = $files
        Directories = $directories
        Bytes = $bytes
        UnreadableDirectories = @($unreadable)
    }
}

function Test-FaInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $InventorySourceId,
        [Parameter(Mandatory)][string] $InventoryRunId,
        [switch] $LiveReconciliation
    )

    $workspace = Import-FaWorkspace -ConfigPath $WorkspacePath
    $source = @($workspace.Sources | Where-Object Id -eq $InventorySourceId)
    if ($source.Count -ne 1) {
        throw "source id did not resolve exactly once: $InventorySourceId"
    }
    $source = $source[0]
    Assert-FaNotProtected -Path $source.Path -Workspace $workspace -Operation 'inventory verification'
    $sourceRoot = ConvertTo-FaCanonicalPath $source.Path
    $sourcePrefix = if ($sourceRoot.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $sourceRoot
    } else { $sourceRoot + [IO.Path]::DirectorySeparatorChar }
    $protectedBoundaries = @($workspace.ProtectedRoots | ForEach-Object {
        $root = ConvertTo-FaCanonicalPath $_
        [pscustomobject]@{
            Root = $root
            Prefix = if ($root.EndsWith([IO.Path]::DirectorySeparatorChar)) {
                $root
            } else { $root + [IO.Path]::DirectorySeparatorChar }
        }
    })

    $runPath = Join-Path $workspace.Audit `
        ("runs\{0}\inventory\{1}" -f $InventoryRunId, $source.Id)
    $summaryPath = Join-Path $runPath 'inventory-summary.json'
    $envelopePath = Join-Path $runPath 'run-envelope.json'
    $segmentsPath = Join-Path $runPath 'segments'
    foreach ($required in @($summaryPath, $envelopePath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "inventory verification input is absent: $required"
        }
    }

    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -Depth 32
    $envelope = Get-Content -LiteralPath $envelopePath -Raw | ConvertFrom-Json -Depth 32
    $failures = [Collections.Generic.List[string]]::new()
    $paths = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $files = [long]0
    $directories = [long]0
    $bytes = [long]0
    $media = @{ image = [long]0; video = [long]0; audio = [long]0 }
    $noiseHints = [long]0
    $sensitiveHints = [long]0
    $generatedHints = [long]0
    $itemRows = [long]0

    if ($summary.RunId -ne $InventoryRunId -or $envelope.RunId -ne $InventoryRunId) {
        $failures.Add('run identity mismatch')
    }
    if ($summary.SourceId -ne $source.Id -or $envelope.SourceId -ne $source.Id) {
        $failures.Add('source identity mismatch')
    }
    if ($summary.InputSeal -ne $envelope.InputSeal) {
        $failures.Add('summary and envelope input seals differ')
    }

    $segmentFiles = @(Get-ChildItem -LiteralPath $segmentsPath -Filter 'segment-*.json' `
        -File -ErrorAction Stop | Sort-Object Name)
    if ($segmentFiles.Count -ne @($summary.Segments).Count) {
        $failures.Add('segment count differs from completion summary')
    }

    for ($index = 0; $index -lt $segmentFiles.Count; $index++) {
        $file = $segmentFiles[$index]
        $expectedName = 'segment-{0:D8}.json' -f ($index + 1)
        if ($file.Name -ne $expectedName) {
            $failures.Add("non-contiguous segment sequence at $($file.Name)")
        }
        $evidence = @($summary.Segments | Where-Object Name -eq $file.Name)
        if ($evidence.Count -ne 1) {
            $failures.Add("missing or duplicate summary evidence for $($file.Name)")
        } else {
            if ((Get-FaSha256 $file.FullName) -ne $evidence[0].Sha256) {
                $failures.Add("digest mismatch for $($file.Name)")
            }
            if ([long]$file.Length -ne [long]$evidence[0].Bytes) {
                $failures.Add("byte length mismatch for $($file.Name)")
            }
        }

        $segment = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 32
        if ([int]$segment.Sequence -ne ($index + 1)) {
            $failures.Add("embedded sequence mismatch for $($file.Name)")
        }
        if ($segment.RunId -ne $InventoryRunId -or $segment.SourceId -ne $source.Id -or
            $segment.InputSeal -ne $summary.InputSeal) {
            $failures.Add("identity or seal mismatch for $($file.Name)")
        }
        if ([long]$segment.ItemCount -ne @($segment.Items).Count) {
            $failures.Add("item count mismatch for $($file.Name)")
        }

        foreach ($item in @($segment.Items)) {
            $itemRows++
            $relative = [string]$item.RelativePath
            if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative)) {
                $failures.Add('inventory contains a blank or rooted relative path')
                continue
            }
            $absolute = [IO.Path]::GetFullPath([IO.Path]::Combine($sourceRoot, $relative))
            if (-not $absolute.StartsWith($sourcePrefix,
                    [StringComparison]::OrdinalIgnoreCase)) {
                $failures.Add("inventory path escapes source: $relative")
            }
            foreach ($boundary in $protectedBoundaries) {
                if ($absolute.Equals($boundary.Root, [StringComparison]::OrdinalIgnoreCase) -or
                    $absolute.StartsWith($boundary.Prefix,
                        [StringComparison]::OrdinalIgnoreCase)) {
                    $failures.Add("inventory contains protected path: $relative")
                    break
                }
            }
            if (-not $paths.Add($relative)) {
                $failures.Add("duplicate inventory path: $relative")
            }
            if ($item.Kind -eq 'file') {
                $files++
                $bytes += [long]$item.Length
            } elseif ($item.Kind -eq 'directory') {
                $directories++
            }
            if ($item.MediaKind -and $media.ContainsKey([string]$item.MediaKind)) {
                $media[[string]$item.MediaKind]++
            }
            if ($item.MediaNoiseHint) { $noiseHints++ }
            if ($item.SensitiveNameHint) { $sensitiveHints++ }
            if ($item.GeneratedHint) { $generatedHints++ }
        }
    }

    if ($itemRows -ne [long]$summary.Items) {
        $failures.Add('total item rows differ from completion summary')
    }

    $live = $null
    $missingFromLive = @()
    $missingFromInventory = @()
    if ($LiveReconciliation) {
        if (-not (Test-Path -LiteralPath $source.Path -PathType Container)) {
            $failures.Add('source is unavailable for requested live reconciliation')
        } else {
            $live = Get-FaLiveInventoryIdentity -Workspace $workspace -Source $source
            $missingFromLive = @($paths | Where-Object { -not $live.Paths.Contains($_) } |
                Select-Object -First 25)
            $missingFromInventory = @($live.Paths | Where-Object { -not $paths.Contains($_) } |
                Select-Object -First 25)
            if ($live.Items -ne $itemRows -or $missingFromLive.Count -gt 0 -or
                $missingFromInventory.Count -gt 0) {
                $failures.Add('live filesystem identity differs from committed inventory')
            }
        }
    }

    $status = if ($failures.Count -gt 0) {
        'fail'
    } elseif ($summary.Status -eq 'partial' -or [long]$summary.TerminalDirectoryErrors -gt 0) {
        'pass-with-source-errors'
    } else { 'pass' }
    $receipt = [pscustomobject]@{
        SchemaVersion = 1
        RunId = $InventoryRunId
        SourceId = $source.Id
        Status = $status
        InventoryStatus = [string]$summary.Status
        TerminalDirectoryErrors = [long]$summary.TerminalDirectoryErrors
        VerifiedAt = [DateTimeOffset]::Now.ToString('o')
        Structural = [pscustomobject]@{
            Segments = $segmentFiles.Count
            Items = $itemRows
            Files = $files
            Directories = $directories
            Bytes = $bytes
            UniquePaths = $paths.Count
            Media = [pscustomobject]$media
            MediaNoiseHints = $noiseHints
            SensitiveNameHints = $sensitiveHints
            GeneratedTreeHints = $generatedHints
        }
        LiveReconciliation = if ($live) {
            [pscustomobject]@{
                Performed = $true
                Items = $live.Items
                Files = $live.Files
                Directories = $live.Directories
                Bytes = $live.Bytes
                UnreadableDirectories = @($live.UnreadableDirectories)
                MissingFromLiveSample = @($missingFromLive)
                MissingFromInventorySample = @($missingFromInventory)
            }
        } else { [pscustomobject]@{ Performed = $false } }
        Failures = @($failures)
    }
    Write-FaAtomicJson -Path (Join-Path $runPath 'inventory-verification.json') `
        -Value $receipt -Depth 16
    return $receipt
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $SourceId -or -not $RunId) { throw '-SourceId and -RunId are required' }
    $result = Test-FaInventory -WorkspacePath $ConfigPath `
        -InventorySourceId $SourceId -InventoryRunId $RunId `
        -LiveReconciliation:$ReconcileLive
    $result | ConvertTo-Json -Depth 16
    if ($result.Status -eq 'fail') { exit 1 }
}
