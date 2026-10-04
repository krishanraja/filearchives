[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $RunId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

function Invoke-FaDuplicateAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $InventoryRunId
    )
    $workspace = Import-FaWorkspace -ConfigPath $WorkspacePath
    $dedupeRoot = Join-Path $workspace.Audit ("runs\{0}\dedupe" -f $InventoryRunId)
    $hashRoot = Join-Path $dedupeRoot 'whole-hashes'
    $summaryPath = Join-Path $hashRoot 'whole-hash-summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        throw "whole-hash summary is absent: $summaryPath"
    }
    $summary = Get-Content -LiteralPath $summaryPath -Raw |
        ConvertFrom-Json -Depth 32 -DateKind String
    if ([long]$summary.CandidateRows -ne
        ([long]$summary.HashedRows + [long]$summary.UnprovenRows)) {
        throw 'whole-hash summary row counts do not reconcile'
    }
    $wholePlanPath = Join-Path $dedupeRoot 'whole-hash-plan-summary.json'
    $wholePlan = Get-Content -LiteralPath $wholePlanPath -Raw |
        ConvertFrom-Json -Depth 32 -DateKind String
    if ($summary.PlanSha256 -ne $wholePlan.CandidateArtifact.Sha256 -or
        (Get-FaSha256 $wholePlan.CandidateArtifact.Path) -ne
            $wholePlan.CandidateArtifact.Sha256) {
        throw 'whole-hash summary and candidate plan do not share one sealed set'
    }

    $signatureSummaryPath = Join-Path $dedupeRoot 'signatures\signature-summary.json'
    if ((Get-FaSha256 $signatureSummaryPath) -ne $wholePlan.SignatureSummarySha256) {
        throw 'signature summary differs from the one used by the whole-hash plan'
    }
    $signatureUnprovenGroups = @{}
    $signatureSegmentsPath = Join-Path $dedupeRoot 'signatures\segments'
    foreach ($signatureFile in @(Get-ChildItem -LiteralPath $signatureSegmentsPath `
            -Filter 'segment-*.json' -File | Sort-Object Name)) {
        $signatureSegment = Get-Content -LiteralPath $signatureFile.FullName -Raw |
            ConvertFrom-Json -Depth 32 -DateKind String
        foreach ($row in @($signatureSegment.Rows | Where-Object Status -ne 'signed')) {
            $reason = if ($row.Status -eq 'stale') { 'source-drift' }
                elseif ($row.ErrorMessage -like '*cloud file provider is not running*') {
                    'cloud-provider-unavailable'
                } elseif ($row.ErrorType -like '*ItemNotFoundException*') { 'missing' }
                else { 'read-error' }
            $key = '{0}|{1}' -f ([string]$row.SourceId), $reason
            if (-not $signatureUnprovenGroups.ContainsKey($key)) {
                $signatureUnprovenGroups[$key] = [ordered]@{
                    SourceId = [string]$row.SourceId
                    Reason = $reason
                    Files = [long]0
                    Bytes = [long]0
                }
            }
            $signatureUnprovenGroups[$key].Files++
            $signatureUnprovenGroups[$key].Bytes += [long]$row.Length
        }
    }
    $signatureUnprovenRows = [long]0
    foreach ($unprovenGroup in $signatureUnprovenGroups.Values) {
        $signatureUnprovenRows += [long]$unprovenGroup.Files
    }
    if ($signatureUnprovenRows -ne [long]$wholePlan.UnprovenRows) {
        throw 'signature unproven rows differ from the whole-hash plan'
    }

    $segmentsPath = Join-Path $hashRoot 'segments'
    $segments = @(Get-ChildItem -LiteralPath $segmentsPath -Filter 'segment-*.json' -File |
        Sort-Object Name)
    if ($segments.Count -ne @($summary.Segments).Count) {
        throw 'whole-hash segment count differs from sealed summary'
    }

    $groups = @{}
    $unproven = [Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $segments.Count; $i++) {
        $expected = 'segment-{0:D8}.json' -f ($i + 1)
        if ($segments[$i].Name -ne $expected -or
            $summary.Segments[$i].Name -ne $expected -or
            (Get-FaSha256 $segments[$i].FullName) -ne $summary.Segments[$i].Sha256) {
            throw "whole-hash segment seal failed at $expected"
        }
        $segment = Get-Content -LiteralPath $segments[$i].FullName -Raw |
            ConvertFrom-Json -Depth 32 -DateKind String
        foreach ($row in @($segment.Rows)) {
            if ($row.Status -ne 'hashed') {
                $unproven.Add([pscustomobject]@{
                    SourceId = [string]$row.SourceId
                    RelativePath = [string]$row.RelativePath
                    Length = [long]$row.Length
                    Status = [string]$row.Status
                    ErrorType = if ($row.ErrorType) { [string]$row.ErrorType } else { $null }
                    ErrorMessage = if ($row.ErrorMessage) { [string]$row.ErrorMessage } else { $null }
                })
                continue
            }
            $key = '{0}|{1}' -f ([long]$row.Length), ([string]$row.Sha256)
            if (-not $groups.ContainsKey($key)) {
                $groups[$key] = [Collections.Generic.List[object]]::new()
            }
            $groups[$key].Add([pscustomobject]@{
                SourceId = [string]$row.SourceId
                RelativePath = [string]$row.RelativePath
                Length = [long]$row.Length
                LastWriteTimeUtc = [string]$row.LastWriteTimeUtc
            })
        }
    }

    $exact = [Collections.Generic.List[object]]::new()
    $sourcePairs = @{}
    $duplicateFiles = [long]0
    $redundantCopies = [long]0
    $reclaimBytes = [long]0
    $crossSource = [long]0
    $managedRepo = [long]0
    foreach ($key in @($groups.Keys | Sort-Object)) {
        $members = @($groups[$key])
        if ($members.Count -lt 2) { continue }
        $length = [long]$members[0].Length
        $sources = @($members | Select-Object -ExpandProperty SourceId -Unique | Sort-Object)
        $isCrossSource = $sources.Count -gt 1
        $hasManagedRepo = @($members | Where-Object SourceId -eq 'c-dev').Count -gt 0
        if ($isCrossSource) { $crossSource++ }
        if ($hasManagedRepo) { $managedRepo++ }
        $duplicateFiles += $members.Count
        $redundantCopies += $members.Count - 1
        $reclaim = [long](($members.Count - 1) * $length)
        $reclaimBytes += $reclaim

        for ($a = 0; $a -lt $sources.Count; $a++) {
            for ($b = $a + 1; $b -lt $sources.Count; $b++) {
                $pairKey = '{0}|{1}' -f $sources[$a], $sources[$b]
                if (-not $sourcePairs.ContainsKey($pairKey)) {
                    $sourcePairs[$pairKey] = [ordered]@{ Groups=[long]0; BytesPerOneCopy=[long]0 }
                }
                $sourcePairs[$pairKey].Groups++
                $sourcePairs[$pairKey].BytesPerOneCopy += $length
            }
        }

        $exact.Add([pscustomobject]@{
            Sha256 = $key.Substring($key.IndexOf('|') + 1)
            Length = $length
            MemberCount = $members.Count
            SourceCount = $sources.Count
            CrossSource = $isCrossSource
            ContainsManagedRepo = $hasManagedRepo
            TheoreticalReclaimBytes = $reclaim
            Members = $members
        })
    }

    $pairRows = @($sourcePairs.Keys | ForEach-Object {
        $parts = $_ -split '\|', 2
        [pscustomobject]@{
            SourceA = $parts[0]
            SourceB = $parts[1]
            Groups = [long]$sourcePairs[$_].Groups
            BytesPerOneCopy = [long]$sourcePairs[$_].BytesPerOneCopy
        }
    } | Sort-Object BytesPerOneCopy -Descending)

    $result = [pscustomobject]@{
        SchemaVersion = 1
        RunId = $InventoryRunId
        WholeHashSummarySha256 = Get-FaSha256 $summaryPath
        IdentityAlgorithm = if ($summary.PSObject.Properties.Name -contains 'Algorithm') {
            [string]$summary.Algorithm
        } else { 'sha256-whole-file-v1' }
        ExactDuplicateGroups = $exact.Count
        FilesInExactDuplicateGroups = $duplicateFiles
        RedundantCopies = $redundantCopies
        TheoreticalMaximumReclaimBytes = $reclaimBytes
        CrossSourceGroups = $crossSource
        SameSourceGroups = [long]$exact.Count - $crossSource
        GroupsTouchingManagedRepos = $managedRepo
        SignatureUnprovenRows = $signatureUnprovenRows
        WholeHashUnprovenRows = $unproven.Count
        TotalUnprovenRows = $signatureUnprovenRows + $unproven.Count
        SignatureUnprovenBySource = @($signatureUnprovenGroups.Values |
            Sort-Object Files -Descending)
        SourcePairOverlap = $pairRows
        Groups = @($exact | Sort-Object TheoreticalReclaimBytes -Descending)
        Unproven = @($unproven)
        Policy = [pscustomobject]@{
            IdentityRule = 'same length plus whole-file SHA-256'
            ReclaimRule = 'no member is a deletion target until a separate survivor policy and action-time revalidation exist'
            ManagedRepoRule = 'individual files inside c-dev are never standalone deletion targets'
        }
        CreatedAt = [DateTimeOffset]::Now.ToString('o')
    }
    $outputPath = Join-Path $dedupeRoot 'duplicate-evidence.json'
    Write-FaAtomicJson -Path $outputPath -Value $result -Depth 20
    return $result
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RunId) { throw '-RunId is required' }
    Invoke-FaDuplicateAnalysis -WorkspacePath $ConfigPath -InventoryRunId $RunId |
        ConvertTo-Json -Depth 20
}
