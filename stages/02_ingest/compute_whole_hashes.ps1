[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $RunId,
    [int] $BatchSize = 500,
    [int] $MaxBatches = 0,
    [long] $ReadBudget = 274877906944
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$script:FaWholeHashAlgorithm = 'sha256-whole-file-v1'

function Get-FaWholeHash {
    param([Parameter(Mandatory)][string] $Path)
    $hash = [Security.Cryptography.IncrementalHash]::CreateHash(
        [Security.Cryptography.HashAlgorithmName]::SHA256)
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        [IO.FileShare]::Read, 8388608, [IO.FileOptions]::SequentialScan)
    $readTotal = [long]0
    try {
        $buffer = [byte[]]::new(8388608)
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $hash.AppendData($buffer, 0, $read)
            $readTotal += $read
        }
        return [pscustomobject]@{
            Sha256 = ([Convert]::ToHexString($hash.GetHashAndReset())).ToLowerInvariant()
            BytesRead = $readTotal
        }
    } finally {
        $stream.Dispose()
        $hash.Dispose()
    }
}

function Get-FaCommittedWholeHashState {
    param(
        [Parameter(Mandatory)][string] $SegmentsPath,
        [Parameter(Mandatory)][string] $PlanSha256
    )
    $files = @(Get-ChildItem -LiteralPath $SegmentsPath -Filter 'segment-*.json' `
        -File -ErrorAction SilentlyContinue | Sort-Object Name)
    $cursor = 0
    $read = [long]0
    $rows = [long]0
    $errors = [long]0
    for ($i = 0; $i -lt $files.Count; $i++) {
        $expected = 'segment-{0:D8}.json' -f ($i + 1)
        if ($files[$i].Name -ne $expected) { throw 'whole-hash segments are not contiguous' }
        $segment = Get-Content -LiteralPath $files[$i].FullName -Raw |
            ConvertFrom-Json -Depth 32 -DateKind String
        if ($segment.PlanSha256 -ne $PlanSha256) {
            throw "whole-hash segment belongs to a different plan: $expected"
        }
        if ($segment.PSObject.Properties.Name -contains 'Algorithm' -and
            $segment.Algorithm -ne $script:FaWholeHashAlgorithm) {
            throw "whole-hash algorithm differs at $expected"
        }
        if ([int]$segment.StartIndex -ne $cursor) {
            throw "whole-hash segment cursor gap at $expected"
        }
        $cursor = [int]$segment.EndExclusive
        $read += [long]$segment.BytesRead
        $rows += @($segment.Rows).Count
        $errors += @($segment.Rows | Where-Object Status -ne 'hashed').Count
    }
    return [pscustomobject]@{
        SegmentFiles = $files
        Cursor = $cursor
        BytesRead = $read
        Rows = $rows
        Errors = $errors
    }
}

function Complete-FaWholeHashRun {
    param(
        [Parameter(Mandatory)][string] $RunPath,
        [Parameter(Mandatory)][string] $InventoryRunId,
        [Parameter(Mandatory)] $Plan,
        [Parameter(Mandatory)] $State
    )
    $evidence = @($State.SegmentFiles | ForEach-Object {
        [pscustomobject]@{ Name=$_.Name; Sha256=Get-FaSha256 $_.FullName; Bytes=$_.Length }
    })
    $summary = [pscustomobject]@{
        SchemaVersion = 1
        RunId = $InventoryRunId
        PlanSha256 = $Plan.CandidateArtifact.Sha256
        Algorithm = $script:FaWholeHashAlgorithm
        Status = if ($State.Errors -gt 0) { 'partial' } else { 'complete' }
        CandidateRows = [long]$Plan.CandidateRows
        HashedRows = [long]($State.Rows - $State.Errors)
        UnprovenRows = [long]$State.Errors
        BytesRead = [long]$State.BytesRead
        Segments = $evidence
        CompletedAt = [DateTimeOffset]::Now.ToString('o')
    }
    Write-FaAtomicJson -Path (Join-Path $RunPath 'whole-hash-summary.json') `
        -Value $summary -Depth 12
    return $summary
}

function Invoke-FaWholeHashes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $InventoryRunId,
        [int] $RowsPerBatch = 500,
        [int] $BatchLimit = 0,
        [long] $TotalReadBudget = 274877906944
    )
    if ($RowsPerBatch -lt 1) { throw 'BatchSize must be positive' }
    if ($TotalReadBudget -lt 1) { throw 'ReadBudget must be positive' }
    $workspace = Import-FaWorkspace -ConfigPath $WorkspacePath
    $dedupeRoot = Join-Path $workspace.Audit ("runs\{0}\dedupe" -f $InventoryRunId)
    $planPath = Join-Path $dedupeRoot 'whole-hash-plan-summary.json'
    if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
        throw "whole-hash plan summary is absent: $planPath"
    }
    $plan = Get-Content -LiteralPath $planPath -Raw |
        ConvertFrom-Json -Depth 32 -DateKind String
    $candidatesPath = [string]$plan.CandidateArtifact.Path
    $planSha256 = [string]$plan.CandidateArtifact.Sha256
    if ((Get-FaSha256 $candidatesPath) -ne $planSha256) {
        throw 'whole-hash candidate artifact digest differs from sealed plan'
    }
    $lines = @(Get-Content -LiteralPath $candidatesPath)
    if ($lines.Count -ne [long]$plan.CandidateRows) {
        throw 'whole-hash candidate row count differs from sealed plan'
    }
    if ([long]$plan.CandidateBytes -gt $TotalReadBudget) {
        throw 'whole-hash candidate bytes exceed the explicit read budget'
    }
    $sourceMap = @{}
    foreach ($source in $workspace.Sources) { $sourceMap[$source.Id] = $source }

    $runPath = Join-Path $dedupeRoot 'whole-hashes'
    $segmentsPath = Join-Path $runPath 'segments'
    New-Item -ItemType Directory -Path $segmentsPath -Force | Out-Null
    $lock = [IO.FileStream]::new((Join-Path $runPath 'whole-hash.lock'),
        [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $state = Get-FaCommittedWholeHashState -SegmentsPath $segmentsPath `
            -PlanSha256 $planSha256
        if ($state.BytesRead -gt $TotalReadBudget) {
            throw 'whole-hash read budget was already exceeded'
        }
        if ($state.Cursor -eq $lines.Count) {
            return Complete-FaWholeHashRun -RunPath $runPath -InventoryRunId $InventoryRunId `
                -Plan $plan -State $state
        }
        $batches = 0
        while ($state.Cursor -lt $lines.Count -and
            ($BatchLimit -eq 0 -or $batches -lt $BatchLimit)) {
            $start = $state.Cursor
            $end = [math]::Min($lines.Count, $start + $RowsPerBatch)
            $rows = [Collections.Generic.List[object]]::new()
            $batchRead = [long]0
            for ($index = $start; $index -lt $end; $index++) {
                $candidate = $lines[$index] | ConvertFrom-Json -DateKind String
                $source = $sourceMap[[string]$candidate.SourceId]
                $absolute = Join-Path $source.Path ([string]$candidate.RelativePath)
                Assert-FaNotProtected -Path $absolute -Workspace $workspace `
                    -Operation 'whole-file hash read'
                $result = [ordered]@{
                    Index = $index
                    SignatureGroup = [string]$candidate.SignatureGroup
                    SourceId = [string]$candidate.SourceId
                    RelativePath = [string]$candidate.RelativePath
                    Length = [long]$candidate.Length
                    LastWriteTimeUtc = [string]$candidate.LastWriteTimeUtc
                    Status = 'unproven'
                    Sha256 = $null
                    BytesRead = [long]0
                    ErrorType = $null
                    ErrorMessage = $null
                }
                try {
                    $before = Get-Item -LiteralPath $absolute -Force -ErrorAction Stop
                    $expectedTicks = [DateTimeOffset]::Parse(
                        [string]$candidate.LastWriteTimeUtc).UtcTicks
                    if ($before.PSIsContainer -or [long]$before.Length -ne [long]$candidate.Length -or
                        ([DateTimeOffset]$before.LastWriteTimeUtc).UtcTicks -ne $expectedTicks) {
                        $result.Status = 'stale'
                    } elseif ($state.BytesRead + $batchRead + [long]$candidate.Length -gt
                        $TotalReadBudget) {
                        throw 'whole-hash read budget would be exceeded'
                    } else {
                        $digest = Get-FaWholeHash -Path $absolute
                        $after = Get-Item -LiteralPath $absolute -Force -ErrorAction Stop
                        if ([long]$after.Length -ne [long]$candidate.Length -or
                            ([DateTimeOffset]$after.LastWriteTimeUtc).UtcTicks -ne $expectedTicks) {
                            $result.Status = 'changed-during-read'
                        } else {
                            $result.Status = 'hashed'
                            $result.Sha256 = $digest.Sha256
                        }
                        $result.BytesRead = [long]$digest.BytesRead
                        $batchRead += [long]$digest.BytesRead
                    }
                } catch {
                    $result.Status = 'unproven'
                    $result.ErrorType = $_.Exception.GetType().FullName
                    $result.ErrorMessage = $_.Exception.Message
                }
                $rows.Add([pscustomobject]$result)
            }
            $sequence = $state.SegmentFiles.Count + 1
            $segment = [pscustomobject]@{
                SchemaVersion = 1
                RunId = $InventoryRunId
                PlanSha256 = $planSha256
                Algorithm = $script:FaWholeHashAlgorithm
                Sequence = $sequence
                StartIndex = $start
                EndExclusive = $end
                BytesRead = $batchRead
                Rows = @($rows)
                CommittedAt = [DateTimeOffset]::Now.ToString('o')
            }
            $segmentPath = Join-Path $segmentsPath ('segment-{0:D8}.json' -f $sequence)
            Write-FaAtomicJson -Path $segmentPath -Value $segment -Depth 12
            $batches++
            $batchErrors = @($rows | Where-Object Status -ne 'hashed').Count
            $state = [pscustomobject]@{
                SegmentFiles = @($state.SegmentFiles) + @(Get-Item -LiteralPath $segmentPath)
                Cursor = $end
                BytesRead = [long]$state.BytesRead + $batchRead
                Rows = [long]$state.Rows + $rows.Count
                Errors = [long]$state.Errors + $batchErrors
            }
            Write-Host ("  whole hashes: {0:N0}/{1:N0}, read {2:N2} GB, unproven {3:N0}" -f `
                $state.Cursor, $lines.Count, ($state.BytesRead / 1GB), $state.Errors)
        }
        if ($state.Cursor -eq $lines.Count) {
            return Complete-FaWholeHashRun -RunPath $runPath -InventoryRunId $InventoryRunId `
                -Plan $plan -State $state
        }
        return [pscustomobject]@{
            RunId = $InventoryRunId
            Status = 'paused-batch-limit'
            Cursor = $state.Cursor
            CandidateRows = $lines.Count
            BytesRead = $state.BytesRead
            UnprovenRows = $state.Errors
        }
    } finally { $lock.Dispose() }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RunId) { throw '-RunId is required' }
    Invoke-FaWholeHashes -WorkspacePath $ConfigPath -InventoryRunId $RunId `
        -RowsPerBatch $BatchSize -BatchLimit $MaxBatches -TotalReadBudget $ReadBudget |
        ConvertTo-Json -Depth 12
}
