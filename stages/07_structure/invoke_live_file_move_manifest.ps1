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
if ($manifest.SchemaVersion -ne 1 -or $manifest.Kind -ne 'live-file-move-v1') {
    throw 'unsupported live file move manifest'
}
if ($manifest.Approved -ne $true) { throw 'live file move manifest is not approved' }
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$completed = [Collections.Generic.List[object]]::new()
foreach ($move in @($manifest.Moves)) {
    if ($SkipRuleId -contains [string]$move.RuleId) { continue }
    $source = ConvertTo-FaCanonicalPath ([string]$move.Source)
    $destination = ConvertTo-FaCanonicalPath ([string]$move.Destination)
    Assert-FaNotProtected -Path $source -Workspace $workspace -Operation 'live file move source'
    Assert-FaNotProtected -Path $destination -Workspace $workspace -Operation 'live file move destination'
    if (-not (Test-FaPathWithin -Path $source -Root ([string]$manifest.SourceRoot))) {
        throw "move source escapes frozen root: $source"
    }
    if (-not ([IO.Path]::GetPathRoot($source)).Equals([IO.Path]::GetPathRoot($destination),
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "cross-volume move is refused: $source"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            throw "move source and destination are both absent: $source"
        }
        $existing = Get-Item -LiteralPath $destination -Force
        if ([long]$existing.Length -ne [long]$move.Length -or
            ($move.Sha256 -and (Get-FaSha256 -Path $destination) -ne [string]$move.Sha256)) {
            throw "existing move destination does not prove the absent source: $destination"
        }
        $completed.Add([pscustomobject]@{
            Source = $source
            Destination = $destination
            Length = [long]$move.Length
            VerificationMode = [string]$move.VerificationMode
            Status = 'already-verified'
        })
        continue
    }
    if (Test-Path -LiteralPath $destination) {
        throw "move destination appeared after manifest freeze: $destination"
    }
    $sourceItem = Get-Item -LiteralPath $source -Force
    if ([long]$sourceItem.Length -ne [long]$move.Length -or
        ([DateTimeOffset]$sourceItem.LastWriteTimeUtc).UtcTicks -ne
            [DateTimeOffset]::Parse([string]$move.LastWriteTimeUtc).UtcTicks) {
        throw "move source metadata changed: $source"
    }
    if ($move.Sha256) {
        if ((Get-FaSha256 -Path $source) -ne [string]$move.Sha256) {
            throw "move source hash changed: $source"
        }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
    if (Test-Path -LiteralPath $source) { throw "move source remains: $source" }
    $destinationItem = Get-Item -LiteralPath $destination -Force -ErrorAction Stop
    if ([long]$destinationItem.Length -ne [long]$move.Length) {
        throw "move destination length mismatch: $destination"
    }
    if ($move.Sha256 -and (Get-FaSha256 -Path $destination) -ne [string]$move.Sha256) {
        throw "move destination hash mismatch: $destination"
    }
    $completed.Add([pscustomobject]@{
        Source = $source
        Destination = $destination
        Length = [long]$move.Length
        VerificationMode = [string]$move.VerificationMode
        Status = 'verified'
    })
}
$receipt = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-receipt-v1'
    Status = 'complete'
    ManifestSha256 = Get-FaSha256 -Path $ManifestPath
    MoveCount = [long]$completed.Count
    Moves = @($completed)
    CompletedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReceiptPath -Value $receipt -Depth 12
Write-Host ("live file moves verified: {0}" -f $completed.Count)
Write-Host "receipt: $ReceiptPath"
