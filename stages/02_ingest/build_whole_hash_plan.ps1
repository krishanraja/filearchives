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

function Invoke-FaWholeHashPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $InventoryRunId
    )

    $workspace = Import-FaWorkspace -ConfigPath $WorkspacePath
    $dedupeRoot = Join-Path $workspace.Audit ("runs\{0}\dedupe" -f $InventoryRunId)
    $signatureRoot = Join-Path $dedupeRoot 'signatures'
    $summaryPath = Join-Path $signatureRoot 'signature-summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        throw "signature summary is absent: $summaryPath"
    }
    $summary = Get-Content -LiteralPath $summaryPath -Raw |
        ConvertFrom-Json -Depth 32 -DateKind String
    $signatureAlgorithm = if ($summary.PSObject.Properties.Name -contains 'Algorithm') {
        [string]$summary.Algorithm
    } else { 'sha256-length-first65536-last65536-v1' }
    if ([long]$summary.CandidateRows -ne
        ([long]$summary.SignedRows + [long]$summary.UnprovenRows)) {
        throw 'signature summary row counts do not reconcile'
    }

    $segmentsPath = Join-Path $signatureRoot 'segments'
    $segments = @(Get-ChildItem -LiteralPath $segmentsPath -Filter 'segment-*.json' -File |
        Sort-Object Name)
    if ($segments.Count -ne @($summary.Segments).Count) {
        throw 'signature segment count differs from sealed summary'
    }
    for ($i = 0; $i -lt $segments.Count; $i++) {
        $expected = 'segment-{0:D8}.json' -f ($i + 1)
        if ($segments[$i].Name -ne $expected -or
            $summary.Segments[$i].Name -ne $expected -or
            (Get-FaSha256 $segments[$i].FullName) -ne $summary.Segments[$i].Sha256) {
            throw "signature segment seal failed at $expected"
        }
    }

    $counts = @{}
    $signedRows = [long]0
    foreach ($file in $segments) {
        $segment = Get-Content -LiteralPath $file.FullName -Raw |
            ConvertFrom-Json -Depth 32 -DateKind String
        foreach ($row in @($segment.Rows)) {
            if ($row.Status -ne 'signed') { continue }
            $key = '{0}|{1}' -f ([long]$row.Length), ([string]$row.Signature)
            if (-not $counts.ContainsKey($key)) { $counts[$key] = [long]0 }
            $counts[$key]++
            $signedRows++
        }
    }
    if ($signedRows -ne [long]$summary.SignedRows) {
        throw 'signed row count differs from sealed summary'
    }

    $planPath = Join-Path $dedupeRoot 'whole-hash-candidates.jsonl'
    $tempPath = $planPath + '.writing'
    $writer = [IO.StreamWriter]::new($tempPath, $false,
        [Text.UTF8Encoding]::new($false))
    $candidateRows = [long]0
    $candidateBytes = [long]0
    $groups = @{}
    try {
        foreach ($file in $segments) {
            $segment = Get-Content -LiteralPath $file.FullName -Raw |
                ConvertFrom-Json -Depth 32 -DateKind String
            foreach ($row in @($segment.Rows)) {
                if ($row.Status -ne 'signed') { continue }
                $key = '{0}|{1}' -f ([long]$row.Length), ([string]$row.Signature)
                if ([long]$counts[$key] -lt 2) { continue }
                $output = [ordered]@{
                    SignatureGroup = $key
                    SourceId = [string]$row.SourceId
                    RelativePath = [string]$row.RelativePath
                    Length = [long]$row.Length
                    LastWriteTimeUtc = [string]$row.LastWriteTimeUtc
                }
                $writer.WriteLine(($output | ConvertTo-Json -Compress))
                $candidateRows++
                $candidateBytes += [long]$row.Length
                $groups[$key] = $true
            }
        }
    } finally { $writer.Dispose() }
    [IO.File]::Move($tempPath, $planPath, $true)

    $result = [pscustomobject]@{
        SchemaVersion = 1
        RunId = $InventoryRunId
        SignatureSummarySha256 = Get-FaSha256 $summaryPath
        SignatureAlgorithm = $signatureAlgorithm
        CandidateArtifact = [pscustomobject]@{
            Path = $planPath
            Sha256 = Get-FaSha256 $planPath
            Bytes = (Get-Item -LiteralPath $planPath).Length
        }
        SignatureCollisionGroups = [long]$groups.Count
        CandidateRows = $candidateRows
        CandidateBytes = $candidateBytes
        SignedUniqueRows = [long]$summary.SignedRows - $candidateRows
        UnprovenRows = [long]$summary.UnprovenRows
        CreatedAt = [DateTimeOffset]::Now.ToString('o')
    }
    Write-FaAtomicJson -Path (Join-Path $dedupeRoot 'whole-hash-plan-summary.json') `
        -Value $result -Depth 12
    return $result
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RunId) { throw '-RunId is required' }
    Invoke-FaWholeHashPlan -WorkspacePath $ConfigPath -InventoryRunId $RunId |
        ConvertTo-Json -Depth 12
}
