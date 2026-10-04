[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $RunId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FaHashPlanScriptPath = $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

function Get-FaHashPlanSeal {
    param([Parameter(Mandatory)] $Workspace, [Parameter(Mandatory)][string] $InventoryRunId)
    $inventoryRoot = Join-Path $Workspace.Audit ("runs\{0}\inventory" -f $InventoryRunId)
    $parts = [Collections.Generic.List[string]]::new()
    $parts.Add('hash-plan-v1')
    $parts.Add((Get-FaSha256 $Workspace.Origin))
    $parts.Add((Get-FaSha256 $script:FaHashPlanScriptPath))
    foreach ($summary in @(Get-ChildItem -LiteralPath $inventoryRoot `
            -Filter 'inventory-summary.json' -File -Recurse | Sort-Object FullName)) {
        $parts.Add([IO.Path]::GetRelativePath($inventoryRoot, $summary.FullName))
        $parts.Add((Get-FaSha256 $summary.FullName))
        $verification = Join-Path $summary.Directory.FullName 'inventory-verification.json'
        if (Test-Path -LiteralPath $verification -PathType Leaf) {
            $parts.Add((Get-FaSha256 $verification))
        }
    }
    $text = $parts -join "`n"
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($sha.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($text)))).ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Test-FaGeneratedInventoryItem {
    param([Parameter(Mandatory)] $Item)
    if ($Item.GeneratedHint) { return $true }
    return ([string]$Item.RelativePath) -match '(?i)(^|[\\/])\.git([\\/]|$)'
}

function Invoke-FaHashPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $WorkspacePath,
        [Parameter(Mandatory)][string] $InventoryRunId
    )

    $workspace = Import-FaWorkspace -ConfigPath $WorkspacePath
    $inventoryRoot = Join-Path $workspace.Audit ("runs\{0}\inventory" -f $InventoryRunId)
    if (-not (Test-Path -LiteralPath $inventoryRoot -PathType Container)) {
        throw "inventory run is absent: $inventoryRoot"
    }
    $analysisRoot = Join-Path $workspace.Audit ("runs\{0}\dedupe" -f $InventoryRunId)
    New-Item -ItemType Directory -Path $analysisRoot -Force | Out-Null
    $seal = Get-FaHashPlanSeal -Workspace $workspace -InventoryRunId $InventoryRunId
    $sizeCounts = @{}
    $excludedGenerated = [long]0
    $excludedZero = [long]0
    $sourceSegments = @{}

    foreach ($source in $workspace.Sources) {
        $segmentsPath = Join-Path $inventoryRoot ("{0}\segments" -f $source.Id)
        if (-not (Test-Path -LiteralPath $segmentsPath -PathType Container)) { continue }
        $segments = @(Get-ChildItem -LiteralPath $segmentsPath -Filter 'segment-*.json' `
            -File | Sort-Object Name)
        $sourceSegments[$source.Id] = $segments
        Write-Host ("  hash plan pass 1: {0}" -f $source.Id)
        foreach ($file in $segments) {
            $segment = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 32
            foreach ($item in @($segment.Items)) {
                if ($item.Kind -ne 'file') { continue }
                if (Test-FaGeneratedInventoryItem $item) { $excludedGenerated++; continue }
                $length = [long]$item.Length
                if ($length -eq 0) { $excludedZero++; continue }
                $key = [string]$length
                if ($sizeCounts.ContainsKey($key)) {
                    $sizeCounts[$key] = [long]$sizeCounts[$key] + 1
                } else { $sizeCounts[$key] = [long]1 }
            }
        }
    }

    $candidatePath = Join-Path $analysisRoot 'hash-candidates.jsonl'
    $tempPath = $candidatePath + '.writing'
    $encoding = [Text.UTF8Encoding]::new($false)
    $stream = [IO.FileStream]::new($tempPath, [IO.FileMode]::Create,
        [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = [IO.StreamWriter]::new($stream, $encoding)
    $candidateFiles = [long]0
    $candidateBytes = [long]0
    $perSource = @{}
    try {
        foreach ($source in $workspace.Sources) {
            if (-not $sourceSegments.ContainsKey($source.Id)) { continue }
            Write-Host ("  hash plan pass 2: {0}" -f $source.Id)
            foreach ($file in @($sourceSegments[$source.Id])) {
                $segment = Get-Content -LiteralPath $file.FullName -Raw |
                    ConvertFrom-Json -Depth 32 -DateKind String
                foreach ($item in @($segment.Items)) {
                    if ($item.Kind -ne 'file' -or (Test-FaGeneratedInventoryItem $item)) { continue }
                    $length = [long]$item.Length
                    if ($length -eq 0 -or [long]$sizeCounts[[string]$length] -lt 2) { continue }
                    $row = [ordered]@{
                        SourceId = $source.Id
                        RelativePath = [string]$item.RelativePath
                        Length = $length
                        LastWriteTimeUtc = ([DateTimeOffset]::Parse(
                            [string]$item.LastWriteTimeUtc)).ToUniversalTime().ToString('o')
                        MediaKind = if ($item.MediaKind) { [string]$item.MediaKind } else { $null }
                        SensitiveNameHint = [bool]$item.SensitiveNameHint
                    }
                    $writer.WriteLine(($row | ConvertTo-Json -Compress))
                    $candidateFiles++
                    $candidateBytes += $length
                    if (-not $perSource.ContainsKey($source.Id)) {
                        $perSource[$source.Id] = [ordered]@{ Files = [long]0; Bytes = [long]0 }
                    }
                    $perSource[$source.Id].Files++
                    $perSource[$source.Id].Bytes += $length
                }
            }
        }
        $writer.Flush()
        $stream.Flush($true)
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
    [IO.File]::Move($tempPath, $candidatePath, $true)

    $summary = [pscustomobject]@{
        SchemaVersion = 1
        RunId = $InventoryRunId
        InputSeal = $seal
        CandidateArtifact = [pscustomobject]@{
            Path = $candidatePath
            Sha256 = Get-FaSha256 $candidatePath
            Bytes = (Get-Item -LiteralPath $candidatePath).Length
        }
        CandidateFiles = $candidateFiles
        CandidateBytes = $candidateBytes
        DistinctCandidateSizes = @($sizeCounts.GetEnumerator() |
            Where-Object { [long]$_.Value -gt 1 }).Count
        ExcludedGeneratedFiles = $excludedGenerated
        ExcludedZeroByteFiles = $excludedZero
        PerSource = @($perSource.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{
                SourceId = $_.Key
                Files = [long]$_.Value.Files
                Bytes = [long]$_.Value.Bytes
            }
        } | Sort-Object Bytes -Descending)
        CreatedAt = [DateTimeOffset]::Now.ToString('o')
    }
    Write-FaAtomicJson -Path (Join-Path $analysisRoot 'hash-plan-summary.json') `
        -Value $summary -Depth 12
    return $summary
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $RunId) { throw '-RunId is required' }
    Invoke-FaHashPlan -WorkspacePath $ConfigPath -InventoryRunId $RunId |
        ConvertTo-Json -Depth 12
}
