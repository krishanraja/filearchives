[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $RunId,
    [datetimeoffset] $AsOf = [DateTimeOffset]::Now
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

function New-FaCounter {
    return [ordered]@{
        Files = [long]0
        Bytes = [long]0
        GeneratedFiles = [long]0
        GeneratedBytes = [long]0
        MediaFiles = [long]0
        MediaBytes = [long]0
        ZeroByteFiles = [long]0
    }
}

function Add-FaCount {
    param([Parameter(Mandatory)] $Counter, [long] $Bytes)
    $Counter.Files = [long]$Counter.Files + 1
    $Counter.Bytes = [long]$Counter.Bytes + $Bytes
}

function Get-FaAgeBand {
    param([datetimeoffset] $LastWrite, [datetimeoffset] $AnalysisDate)
    if ($LastWrite -gt $AnalysisDate.AddDays(1)) { return 'future-or-clock-anomaly' }
    if ($LastWrite -ge $AnalysisDate.AddYears(-2)) { return 'recent-0-to-2y' }
    if ($LastWrite -ge $AnalysisDate.AddYears(-7)) { return 'established-2-to-7y' }
    return 'legacy-over-7y'
}

function Get-FaTopBucket {
    param([string] $RelativePath, [int] $Depth = 1)
    $parts = @([regex]::Split($RelativePath, '[\\/]') | Where-Object { $_ })
    if ($parts.Count -eq 0) { return '[root]' }
    return ($parts | Select-Object -First $Depth) -join '\'
}

function Convert-FaMapToRows {
    param([Parameter(Mandatory)] $Map, [int] $Top = 0)
    $rows = @($Map.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.Key
            Files = [long]$_.Value.Files
            Bytes = [long]$_.Value.Bytes
            GeneratedFiles = [long]$_.Value.GeneratedFiles
            GeneratedBytes = [long]$_.Value.GeneratedBytes
            MediaFiles = [long]$_.Value.MediaFiles
            MediaBytes = [long]$_.Value.MediaBytes
            ZeroByteFiles = [long]$_.Value.ZeroByteFiles
        }
    } | Sort-Object Bytes, Files -Descending)
    if ($Top -gt 0) { return @($rows | Select-Object -First $Top) }
    return $rows
}

function Invoke-FaInventoryAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $InventoryRunId,
        [datetimeoffset] $AnalysisDate = [DateTimeOffset]::Now
    )

    $workspace = Import-FaWorkspace -ConfigPath $WorkspacePath
    $inventoryRoot = Join-Path $workspace.Audit ("runs\{0}\inventory" -f $InventoryRunId)
    if (-not (Test-Path -LiteralPath $inventoryRoot -PathType Container)) {
        throw "inventory run is absent: $inventoryRoot"
    }

    $sourceRows = [Collections.Generic.List[object]]::new()
    $globalExtensions = @{}
    $globalAges = @{}
    $globalMedia = @{}
    $sizeCounts = @{}
    $nonGeneratedSizeCounts = @{}
    $totals = [ordered]@{
        Files = [long]0
        Directories = [long]0
        Bytes = [long]0
        EmptyDirectories = [long]0
        GeneratedFiles = [long]0
        GeneratedBytes = [long]0
        ZeroByteFiles = [long]0
        MediaFiles = [long]0
        MediaBytes = [long]0
        GeneratedMediaFiles = [long]0
        GeneratedMediaBytes = [long]0
        VisualMediaCandidateFiles = [long]0
        VisualMediaCandidateBytes = [long]0
        VisualMediaNoiseFiles = [long]0
        VisualMediaNoiseBytes = [long]0
        AudioFiles = [long]0
        AudioBytes = [long]0
        MediaNoiseHints = [long]0
        SensitiveNameHints = [long]0
    }
    $pathSeparators = [char[]]@('\', '/')
    $futureCutoff = $AnalysisDate.AddDays(1)
    $recentCutoff = $AnalysisDate.AddYears(-2)
    $establishedCutoff = $AnalysisDate.AddYears(-7)

    foreach ($source in $workspace.Sources) {
        Write-Host ("  analysis: begin {0}" -f $source.Id)
        $sourceRun = Join-Path $inventoryRoot $source.Id
        $summaryPath = Join-Path $sourceRun 'inventory-summary.json'
        $verificationPath = Join-Path $sourceRun 'inventory-verification.json'
        if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
            $sourceRows.Add([pscustomobject]@{
                SourceId = $source.Id
                SourceRoot = $source.Path
                Status = 'not-inventoried'
            })
            Write-Host ("  analysis: unavailable inventory {0}" -f $source.Id)
            continue
        }
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -Depth 32
        $verification = if (Test-Path -LiteralPath $verificationPath -PathType Leaf) {
            Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json -Depth 32
        } else { $null }
        $extensions = @{}
        $ages = @{}
        $media = @{}
        $top = @{}
        $projects = @{}
        $sourceCounts = [ordered]@{
            Files = [long]0; Directories = [long]0; Bytes = [long]0
            EmptyDirectories = [long]0; GeneratedFiles = [long]0
            GeneratedBytes = [long]0; ZeroByteFiles = [long]0
            MediaFiles = [long]0; MediaBytes = [long]0
            GeneratedMediaFiles = [long]0; GeneratedMediaBytes = [long]0
            VisualMediaCandidateFiles = [long]0; VisualMediaCandidateBytes = [long]0
            VisualMediaNoiseFiles = [long]0; VisualMediaNoiseBytes = [long]0
            AudioFiles = [long]0; AudioBytes = [long]0
            MediaNoiseHints = [long]0; SensitiveNameHints = [long]0
        }

        $segments = @(Get-ChildItem -LiteralPath (Join-Path $sourceRun 'segments') `
            -Filter 'segment-*.json' -File | Sort-Object Name)
        foreach ($segmentFile in $segments) {
            $segment = Get-Content -LiteralPath $segmentFile.FullName -Raw |
                ConvertFrom-Json -Depth 32
            foreach ($directory in @($segment.ProcessedDirectories)) {
                if ($directory.Status -eq 'complete' -and $directory.IsEmpty -eq $true) {
                    $sourceCounts.EmptyDirectories++
                    $totals.EmptyDirectories++
                }
            }
            foreach ($item in @($segment.Items)) {
                if ($item.Kind -eq 'directory') {
                    $sourceCounts.Directories++
                    $totals.Directories++
                    continue
                }
                if ($item.Kind -ne 'file') { continue }
                $length = [long]$item.Length
                $sourceCounts.Files++
                $sourceCounts.Bytes += $length
                $totals.Files++
                $totals.Bytes += $length
                if ($length -eq 0) {
                    $sourceCounts.ZeroByteFiles++
                    $totals.ZeroByteFiles++
                }

                $extension = if ($item.Extension) { [string]$item.Extension } else { '[none]' }
                if (-not $extensions.ContainsKey($extension)) {
                    $extensions[$extension] = New-FaCounter
                }
                $extensions[$extension].Files++
                $extensions[$extension].Bytes += $length
                if (-not $globalExtensions.ContainsKey($extension)) {
                    $globalExtensions[$extension] = New-FaCounter
                }
                $globalExtensions[$extension].Files++
                $globalExtensions[$extension].Bytes += $length
                $lastWrite = [DateTimeOffset]::Parse([string]$item.LastWriteTimeUtc)
                $age = if ($lastWrite -gt $futureCutoff) {
                    'future-or-clock-anomaly'
                } elseif ($lastWrite -ge $recentCutoff) {
                    'recent-0-to-2y'
                } elseif ($lastWrite -ge $establishedCutoff) {
                    'established-2-to-7y'
                } else { 'legacy-over-7y' }
                if (-not $ages.ContainsKey($age)) { $ages[$age] = New-FaCounter }
                $ages[$age].Files++
                $ages[$age].Bytes += $length
                if (-not $globalAges.ContainsKey($age)) { $globalAges[$age] = New-FaCounter }
                $globalAges[$age].Files++
                $globalAges[$age].Bytes += $length

                $relative = [string]$item.RelativePath
                $isGenerated = [bool]$item.GeneratedHint -or
                    $relative -match '(?i)(^|[\\/])\.git([\\/]|$)'
                $firstSlash = $relative.IndexOfAny($pathSeparators)
                if ($firstSlash -lt 0) {
                    $bucket = $relative
                    $projectBucket = $relative
                } else {
                    $bucket = $relative.Substring(0, $firstSlash)
                    $secondSlash = $relative.IndexOfAny($pathSeparators, $firstSlash + 1)
                    $projectBucket = if ($secondSlash -lt 0) {
                        $relative
                    } else { $relative.Substring(0, $secondSlash) }
                }
                if (-not $top.ContainsKey($bucket)) { $top[$bucket] = New-FaCounter }
                $top[$bucket].Files++
                $top[$bucket].Bytes += $length
                if (-not $projects.ContainsKey($projectBucket)) {
                    $projects[$projectBucket] = New-FaCounter
                }
                $projects[$projectBucket].Files++
                $projects[$projectBucket].Bytes += $length

                if ($isGenerated) {
                    $sourceCounts.GeneratedFiles++
                    $sourceCounts.GeneratedBytes += $length
                    $totals.GeneratedFiles++
                    $totals.GeneratedBytes += $length
                    $top[$bucket].GeneratedFiles++
                    $top[$bucket].GeneratedBytes += $length
                    $projects[$projectBucket].GeneratedFiles++
                    $projects[$projectBucket].GeneratedBytes += $length
                }
                if ($item.MediaKind) {
                    $kind = [string]$item.MediaKind
                    if (-not $media.ContainsKey($kind)) { $media[$kind] = New-FaCounter }
                    $media[$kind].Files++
                    $media[$kind].Bytes += $length
                    if (-not $globalMedia.ContainsKey($kind)) {
                        $globalMedia[$kind] = New-FaCounter
                    }
                    $globalMedia[$kind].Files++
                    $globalMedia[$kind].Bytes += $length
                    $sourceCounts.MediaFiles++
                    $sourceCounts.MediaBytes += $length
                    $totals.MediaFiles++
                    $totals.MediaBytes += $length
                    $top[$bucket].MediaFiles++
                    $top[$bucket].MediaBytes += $length
                    $projects[$projectBucket].MediaFiles++
                    $projects[$projectBucket].MediaBytes += $length
                    if ($isGenerated) {
                        $sourceCounts.GeneratedMediaFiles++
                        $sourceCounts.GeneratedMediaBytes += $length
                        $totals.GeneratedMediaFiles++
                        $totals.GeneratedMediaBytes += $length
                    } elseif ($kind -eq 'audio') {
                        $sourceCounts.AudioFiles++
                        $sourceCounts.AudioBytes += $length
                        $totals.AudioFiles++
                        $totals.AudioBytes += $length
                    } else {
                        $pathNoise = [bool]$item.MediaNoiseHint -or
                            $relative -match '(?i)(^|[\\/])(_?thumbs?|thumbnails?|screenshots?|memes?|cache|temp)([\\/]|$)'
                        if ($pathNoise) {
                            $sourceCounts.VisualMediaNoiseFiles++
                            $sourceCounts.VisualMediaNoiseBytes += $length
                            $totals.VisualMediaNoiseFiles++
                            $totals.VisualMediaNoiseBytes += $length
                        } else {
                            $sourceCounts.VisualMediaCandidateFiles++
                            $sourceCounts.VisualMediaCandidateBytes += $length
                            $totals.VisualMediaCandidateFiles++
                            $totals.VisualMediaCandidateBytes += $length
                        }
                    }
                }
                if ($item.MediaNoiseHint) {
                    $sourceCounts.MediaNoiseHints++
                    $totals.MediaNoiseHints++
                }
                if ($item.SensitiveNameHint) {
                    $sourceCounts.SensitiveNameHints++
                    $totals.SensitiveNameHints++
                }
                if ($length -eq 0) {
                    $top[$bucket].ZeroByteFiles++
                    $projects[$projectBucket].ZeroByteFiles++
                }
                $sizeKey = [string]$length
                if ($sizeCounts.ContainsKey($sizeKey)) {
                    $sizeCounts[$sizeKey] = [long]$sizeCounts[$sizeKey] + 1
                } else { $sizeCounts[$sizeKey] = [long]1 }
                if (-not $isGenerated) {
                    if ($nonGeneratedSizeCounts.ContainsKey($sizeKey)) {
                        $nonGeneratedSizeCounts[$sizeKey] = `
                            [long]$nonGeneratedSizeCounts[$sizeKey] + 1
                    } else { $nonGeneratedSizeCounts[$sizeKey] = [long]1 }
                }
            }
        }

        $sourceRows.Add([pscustomobject]@{
            SourceId = $source.Id
            SourceRoot = $source.Path
            Status = [string]$summary.Status
            Verification = if ($verification) { [string]$verification.Status } else { 'missing' }
            TerminalDirectoryErrors = [long]$summary.TerminalDirectoryErrors
            Counts = [pscustomobject]$sourceCounts
            AgeBands = Convert-FaMapToRows $ages
            Media = Convert-FaMapToRows $media
            TopLevel = Convert-FaMapToRows -Map $top -Top 25
            TopTwoLevels = Convert-FaMapToRows -Map $projects -Top 40
            Extensions = Convert-FaMapToRows -Map $extensions -Top 30
        })
        Write-Host ("  analysis: complete {0}, {1:N0} files" -f `
            $source.Id, $sourceCounts.Files)
    }

    $collisionSizes = [long]0
    $collisionFiles = [long]0
    $maximumSameSizeReclaim = [long]0
    foreach ($entry in $sizeCounts.GetEnumerator()) {
        $count = [long]$entry.Value
        if ($count -gt 1) {
            $collisionSizes++
            $collisionFiles += $count
            $maximumSameSizeReclaim += ([long]$entry.Key * ($count - 1))
        }
    }
    $nonGeneratedCollisionSizes = [long]0
    $nonGeneratedCollisionFiles = [long]0
    $nonGeneratedMaximumReclaim = [long]0
    foreach ($entry in $nonGeneratedSizeCounts.GetEnumerator()) {
        $count = [long]$entry.Value
        if ($count -gt 1) {
            $nonGeneratedCollisionSizes++
            $nonGeneratedCollisionFiles += $count
            $nonGeneratedMaximumReclaim += ([long]$entry.Key * ($count - 1))
        }
    }

    $analysis = [pscustomobject]@{
        SchemaVersion = 1
        RunId = $InventoryRunId
        AsOf = $AnalysisDate.ToString('o')
        Scope = [pscustomobject]@{
            AvailableInventories = @($sourceRows | Where-Object Status -ne 'not-inventoried').Count
            MissingInventories = @($sourceRows | Where-Object Status -eq 'not-inventoried' |
                ForEach-Object SourceId)
            ProtectedRoots = @($workspace.ProtectedRoots)
        }
        Totals = [pscustomobject]$totals
        DuplicateSizeCandidates = [pscustomobject]@{
            DistinctCollidingSizes = $collisionSizes
            FilesInCollidingSizeGroups = $collisionFiles
            MaximumBytesIfEveryCollisionWereDuplicate = $maximumSameSizeReclaim
            ProvenDuplicates = [long]0
            Warning = 'Same size only narrows hashing candidates; it never proves duplicate content.'
            NonGenerated = [pscustomobject]@{
                DistinctCollidingSizes = $nonGeneratedCollisionSizes
                FilesInCollidingSizeGroups = $nonGeneratedCollisionFiles
                MaximumBytesIfEveryCollisionWereDuplicate = $nonGeneratedMaximumReclaim
                ProvenDuplicates = [long]0
            }
        }
        AgeBands = Convert-FaMapToRows $globalAges
        Media = Convert-FaMapToRows $globalMedia
        Extensions = Convert-FaMapToRows -Map $globalExtensions -Top 50
        Sources = @($sourceRows)
    }
    $analysisPath = Join-Path $workspace.Audit `
        ("runs\{0}\analysis\inventory-analysis.json" -f $InventoryRunId)
    Write-FaAtomicJson -Path $analysisPath -Value $analysis -Depth 20
    return $analysis
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RunId) { throw '-RunId is required' }
    $result = Invoke-FaInventoryAnalysis -WorkspacePath $ConfigPath `
        -InventoryRunId $RunId -AnalysisDate $AsOf
    [pscustomobject]@{
        RunId = $result.RunId
        Inventories = $result.Scope.AvailableInventories
        Missing = @($result.Scope.MissingInventories)
        Totals = $result.Totals
        DuplicateSizeCandidates = $result.DuplicateSizeCandidates
    } | ConvertTo-Json -Depth 8
}
