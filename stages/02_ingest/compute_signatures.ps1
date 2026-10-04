[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $RunId,
    [int] $BatchSize = 1000,
    [int] $MaxBatches = 0,
    [long] $ReadBudget = 32212254720
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$script:FaSignatureAlgorithm = 'sha256-length-first65536-last65536-v1'

function Get-FaQuickSignature {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][long] $Length)
    $chunk = 65536
    $bytesRead = [long]0
    $hash = [Security.Cryptography.IncrementalHash]::CreateHash(
        [Security.Cryptography.HashAlgorithmName]::SHA256)
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        [IO.FileShare]::Read)
    try {
        $hash.AppendData([BitConverter]::GetBytes($Length))
        $buffer = [byte[]]::new($chunk)
        $firstLength = [int][math]::Min($chunk, $Length)
        $read = $stream.Read($buffer, 0, $firstLength)
        if ($read -ne $firstLength) { throw "short first read: expected $firstLength got $read" }
        if ($read -gt 0) { $hash.AppendData($buffer, 0, $read); $bytesRead += $read }
        if ($Length -gt $chunk) {
            $stream.Seek([math]::Max(0, $Length - $chunk), [IO.SeekOrigin]::Begin) | Out-Null
            $lastLength = [int][math]::Min($chunk, $Length)
            $read = $stream.Read($buffer, 0, $lastLength)
            if ($read -ne $lastLength) { throw "short last read: expected $lastLength got $read" }
            $hash.AppendData($buffer, 0, $read)
            $bytesRead += $read
        }
        return [pscustomobject]@{
            Signature = ([Convert]::ToHexString($hash.GetHashAndReset())).ToLowerInvariant()
            BytesRead = $bytesRead
        }
    } finally {
        $stream.Dispose()
        $hash.Dispose()
    }
}

function Get-FaCommittedSignatureState {
    param([Parameter(Mandatory)][string] $SegmentsPath)
    $files = @(Get-ChildItem -LiteralPath $SegmentsPath -Filter 'segment-*.json' `
        -File -ErrorAction SilentlyContinue | Sort-Object Name)
    $cursor = 0
    $read = [long]0
    $rows = [long]0
    $errors = [long]0
    for ($i = 0; $i -lt $files.Count; $i++) {
        $expected = 'segment-{0:D8}.json' -f ($i + 1)
        if ($files[$i].Name -ne $expected) { throw 'signature segments are not contiguous' }
        $segment = Get-Content -LiteralPath $files[$i].FullName -Raw |
            ConvertFrom-Json -Depth 32
        if ($segment.PSObject.Properties.Name -contains 'Algorithm' -and
            $segment.Algorithm -ne $script:FaSignatureAlgorithm) {
            throw "signature algorithm differs at $($files[$i].Name)"
        }
        if ([int]$segment.StartIndex -ne $cursor) {
            throw "signature segment cursor gap at $($files[$i].Name)"
        }
        $cursor = [int]$segment.EndExclusive
        $read += [long]$segment.BytesRead
        $rows += @($segment.Rows).Count
        $errors += @($segment.Rows | Where-Object Status -ne 'signed').Count
    }
    return [pscustomobject]@{
        SegmentFiles = $files
        Cursor = $cursor
        BytesRead = $read
        Rows = $rows
        Errors = $errors
    }
}

function Complete-FaSignatureRun {
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
        Algorithm = $script:FaSignatureAlgorithm
        Status = if ($State.Errors -gt 0) { 'partial' } else { 'complete' }
        CandidateRows = [long]$Plan.CandidateFiles
        SignedRows = [long]($State.Rows - $State.Errors)
        UnprovenRows = [long]$State.Errors
        BytesRead = [long]$State.BytesRead
        Segments = $evidence
        CompletedAt = [DateTimeOffset]::Now.ToString('o')
    }
    Write-FaAtomicJson -Path (Join-Path $RunPath 'signature-summary.json') `
        -Value $summary -Depth 12
    return $summary
}

function Invoke-FaSignatures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $InventoryRunId,
        [int] $RowsPerBatch = 1000,
        [int] $BatchLimit = 0,
        [long] $TotalReadBudget = 32212254720
    )
    if ($RowsPerBatch -lt 1) { throw 'BatchSize must be positive' }
    if ($TotalReadBudget -lt 1) { throw 'ReadBudget must be positive' }
    $workspace = Import-FaWorkspace -ConfigPath $WorkspacePath
    $dedupeRoot = Join-Path $workspace.Audit ("runs\{0}\dedupe" -f $InventoryRunId)
    $planPath = Join-Path $dedupeRoot 'hash-plan-summary.json'
    if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
        throw "hash plan summary is absent: $planPath"
    }
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 32
    $candidatesPath = [string]$plan.CandidateArtifact.Path
    if ((Get-FaSha256 $candidatesPath) -ne $plan.CandidateArtifact.Sha256) {
        throw 'hash candidate artifact digest differs from sealed plan'
    }
    $lines = @(Get-Content -LiteralPath $candidatesPath)
    if ($lines.Count -ne [long]$plan.CandidateFiles) {
        throw 'hash candidate row count differs from sealed plan'
    }
    $sourceMap = @{}
    foreach ($source in $workspace.Sources) { $sourceMap[$source.Id] = $source }

    $runPath = Join-Path $dedupeRoot 'signatures'
    $segmentsPath = Join-Path $runPath 'segments'
    New-Item -ItemType Directory -Path $segmentsPath -Force | Out-Null
    $lock = [IO.FileStream]::new((Join-Path $runPath 'signature.lock'),
        [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $state = Get-FaCommittedSignatureState -SegmentsPath $segmentsPath
        if ($state.BytesRead -gt $TotalReadBudget) {
            throw 'signature read budget was already exceeded'
        }
        if ($state.Cursor -eq $lines.Count) {
            return Complete-FaSignatureRun -RunPath $runPath -InventoryRunId $InventoryRunId `
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
                # Preserve the inventory's round-trip timestamp. PowerShell's
                # default JSON date coercion drops sub-second precision when a
                # DateTime is later cast back to string, which makes unchanged
                # files look stale.
                $candidate = $lines[$index] | ConvertFrom-Json -DateKind String
                $source = $sourceMap[[string]$candidate.SourceId]
                $absolute = Join-Path $source.Path ([string]$candidate.RelativePath)
                Assert-FaNotProtected -Path $absolute -Workspace $workspace `
                    -Operation 'signature read'
                $result = [ordered]@{
                    Index = $index
                    SourceId = [string]$candidate.SourceId
                    RelativePath = [string]$candidate.RelativePath
                    Length = [long]$candidate.Length
                    LastWriteTimeUtc = [string]$candidate.LastWriteTimeUtc
                    Status = 'unproven'
                    Signature = $null
                    BytesRead = [long]0
                    ErrorType = $null
                    ErrorMessage = $null
                }
                try {
                    $before = Get-Item -LiteralPath $absolute -Force -ErrorAction Stop
                    $expectedWriteTicks = [DateTimeOffset]::Parse(
                        [string]$candidate.LastWriteTimeUtc).UtcTicks
                    if ($before.PSIsContainer -or [long]$before.Length -ne [long]$candidate.Length -or
                        ([DateTimeOffset]$before.LastWriteTimeUtc).UtcTicks -ne $expectedWriteTicks) {
                        $result.Status = 'stale'
                    } elseif ($state.BytesRead + $batchRead +
                        [math]::Min(131072, ([long]$candidate.Length + 65536)) -gt $TotalReadBudget) {
                        throw 'signature read budget would be exceeded'
                    } else {
                        $signature = Get-FaQuickSignature -Path $absolute `
                            -Length ([long]$candidate.Length)
                        $after = Get-Item -LiteralPath $absolute -Force -ErrorAction Stop
                        if ([long]$after.Length -ne [long]$candidate.Length -or
                            ([DateTimeOffset]$after.LastWriteTimeUtc).UtcTicks -ne $expectedWriteTicks) {
                            $result.Status = 'changed-during-read'
                        } else {
                            $result.Status = 'signed'
                            $result.Signature = $signature.Signature
                        }
                        $result.BytesRead = [long]$signature.BytesRead
                        $batchRead += [long]$signature.BytesRead
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
                PlanSha256 = $plan.CandidateArtifact.Sha256
                Algorithm = $script:FaSignatureAlgorithm
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
            # The committed state was fully verified at startup. Advance it
            # from the atomic segment just written instead of reparsing every
            # prior segment after every checkpoint (quadratic on large runs).
            $batchErrors = @($rows | Where-Object Status -ne 'signed').Count
            $state = [pscustomobject]@{
                SegmentFiles = @($state.SegmentFiles) + @(Get-Item -LiteralPath $segmentPath)
                Cursor = $end
                BytesRead = [long]$state.BytesRead + $batchRead
                Rows = [long]$state.Rows + $rows.Count
                Errors = [long]$state.Errors + $batchErrors
            }
            Write-Host ("  signatures: {0:N0}/{1:N0}, read {2:N2} GB, unproven {3:N0}" -f `
                $state.Cursor, $lines.Count, ($state.BytesRead / 1GB), $state.Errors)
        }
        if ($state.Cursor -eq $lines.Count) {
            return Complete-FaSignatureRun -RunPath $runPath -InventoryRunId $InventoryRunId `
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
    Invoke-FaSignatures -WorkspacePath $ConfigPath -InventoryRunId $RunId `
        -RowsPerBatch $BatchSize -BatchLimit $MaxBatches -TotalReadBudget $ReadBudget |
        ConvertTo-Json -Depth 12
}
