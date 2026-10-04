[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ReceiptPath,
    [Parameter(Mandatory)][switch] $Execute,
    [string[]] $SkipRuleId = @(),
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
if (-not $Execute) { throw 'execution requires the explicit -Execute switch' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
if ($manifest.SchemaVersion -ne 1 -or $manifest.Kind -ne 'live-file-copy-v1') {
    throw 'unsupported live file copy manifest'
}
if ($manifest.Approved -ne $true) { throw 'live file copy manifest is not approved' }
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$completed = [Collections.Generic.List[object]]::new()
function Get-FaReadbackHash {
    param([string] $Path, [int] $Attempts = 80)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try { return Get-FaSha256 -Path $Path } catch {
            if ($attempt -eq $Attempts) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
}
foreach ($copy in @($manifest.Copies)) {
    if ($SkipRuleId -contains [string]$copy.RuleId) { continue }
    $source = ConvertTo-FaCanonicalPath ([string]$copy.Source)
    $destination = ConvertTo-FaCanonicalPath ([string]$copy.Destination)
    Assert-FaNotProtected -Path $source -Workspace $workspace -Operation 'live file copy source'
    Assert-FaNotProtected -Path $destination -Workspace $workspace -Operation 'live file copy destination'
    if (-not (Test-FaPathWithin -Path $source -Root ([string]$manifest.SourceRoot))) {
        throw "copy source escapes frozen root: $source"
    }
    $sourceItem = Get-Item -LiteralPath $source -Force -ErrorAction Stop
    if ([long]$sourceItem.Length -ne [long]$copy.Length -or
        ([DateTimeOffset]$sourceItem.LastWriteTimeUtc).UtcTicks -ne
            [DateTimeOffset]::Parse([string]$copy.LastWriteTimeUtc).UtcTicks -or
        (Get-FaSha256 -Path $source) -ne [string]$copy.Sha256) {
        throw "copy source changed after manifest freeze: $source"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    $temp = $destination + '.fa-copying'
    if (Test-Path -LiteralPath $temp -PathType Leaf) {
        if ((Get-FaSha256 -Path $temp) -ne [string]$copy.Sha256) {
            throw "stale temporary copy has unexpected content: $temp"
        }
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            if ((Get-FaReadbackHash -Path $destination) -ne [string]$copy.Sha256) {
                throw "destination conflicts with a valid temporary copy: $destination"
            }
            Remove-Item -LiteralPath $temp -Force
            $completed.Add([pscustomobject]@{
                Source = $source; Destination = $destination; Length = [long]$copy.Length
                Sha256 = [string]$copy.Sha256; Status = 'already-verified'
            })
            continue
        }
        try {
            [IO.File]::Move($temp, $destination)
        } catch {
            if ((Get-FaReadbackHash -Path $destination) -ne [string]$copy.Sha256) {
                throw
            }
            if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force }
        }
        if ((Get-FaReadbackHash -Path $destination) -ne [string]$copy.Sha256) {
            throw "recovered temporary copy failed readback: $destination"
        }
        $completed.Add([pscustomobject]@{
            Source = $source; Destination = $destination; Length = [long]$copy.Length
            Sha256 = [string]$copy.Sha256; Status = 'recovered-temporary-copy'
        })
        continue
    }
    if (Test-Path -LiteralPath $destination) {
        if ((Get-FaReadbackHash -Path $destination) -ne [string]$copy.Sha256) {
            throw "copy destination appeared with different content after manifest freeze: $destination"
        }
        $completed.Add([pscustomobject]@{
            Source = $source; Destination = $destination; Length = [long]$copy.Length
            Sha256 = [string]$copy.Sha256; Status = 'already-verified'
        })
        continue
    }
    [IO.File]::Copy($source, $temp, $false)
    if ((Get-FaSha256 -Path $temp) -ne [string]$copy.Sha256) {
        Remove-Item -LiteralPath $temp -Force
        throw "temporary copy failed content verification: $destination"
    }
    [IO.File]::SetLastWriteTimeUtc($temp, ([DateTimeOffset]::Parse([string]$copy.LastWriteTimeUtc)).UtcDateTime)
    try {
        [IO.File]::Move($temp, $destination)
    } catch {
        if ((Get-FaReadbackHash -Path $destination) -ne [string]$copy.Sha256) {
            throw
        }
        if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force }
    }
    if ((Get-FaReadbackHash -Path $destination) -ne [string]$copy.Sha256) {
        throw "copy destination failed readback: $destination"
    }
    $completed.Add([pscustomobject]@{
        Source = $source
        Destination = $destination
        Length = [long]$copy.Length
        Sha256 = [string]$copy.Sha256
        Status = 'verified'
    })
}
$receipt = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-copy-receipt-v1'
    Status = 'complete'
    ManifestSha256 = Get-FaSha256 -Path $ManifestPath
    CopyCount = [long]$completed.Count
    Copies = @($completed)
    SourceRetained = $true
    CompletedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReceiptPath -Value $receipt -Depth 12
Write-Host ("live file copies verified: {0}" -f $completed.Count)
