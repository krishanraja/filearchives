[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ReceiptPath,
    [Parameter(Mandatory)][switch] $Execute,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
if (-not $Execute) { throw 'execution requires the explicit -Execute switch' }

function Get-FaShallowTreeSeal {
    param([Parameter(Mandatory)][string] $Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "atomic tree relocation requires a normal directory: $Path"
    }
    $rows = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop |
        Sort-Object Name | ForEach-Object {
            if ($_.PSIsContainer) { "D|$($_.Name)|$([int64]$_.LastWriteTimeUtc.Ticks)" }
            else { "F|$($_.Name)|$([int64]$_.Length)|$([int64]$_.LastWriteTimeUtc.Ticks)" }
        })
    $payload = [string]::Join("`n", $rows)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $seal = [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))).ToLowerInvariant() }
    finally { $sha.Dispose() }
    return [pscustomobject]@{ TopLevelItems=[long]$rows.Count; ShallowSeal=$seal }
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 12 -DateKind String
if ($manifest.SchemaVersion -ne 1 -or $manifest.Kind -ne 'atomic-tree-relocation-v1' -or $manifest.Approved -ne $true) {
    throw 'unsupported or unapproved atomic tree relocation manifest'
}
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$source = ConvertTo-FaCanonicalPath ([string]$manifest.Source)
$destination = ConvertTo-FaCanonicalPath ([string]$manifest.Destination)
Assert-FaNotProtected -Path $source -Workspace $workspace -Operation 'atomic tree relocation source'
Assert-FaNotProtected -Path $destination -Workspace $workspace -Operation 'atomic tree relocation destination'
if (Test-Path -LiteralPath $destination) { throw "destination appeared after manifest freeze: $destination" }
$before = Get-FaShallowTreeSeal -Path $source
if ($before.TopLevelItems -ne [long]$manifest.TopLevelItems -or $before.ShallowSeal -ne [string]$manifest.ShallowSeal) {
    throw 'source shallow seal changed after manifest freeze'
}
New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
[IO.Directory]::Move($source, $destination)
if (Test-Path -LiteralPath $source) { throw "source remains after atomic relocation: $source" }
$after = Get-FaShallowTreeSeal -Path $destination
if ($after.TopLevelItems -ne $before.TopLevelItems -or $after.ShallowSeal -ne $before.ShallowSeal) {
    throw 'destination shallow seal differs after atomic relocation'
}
$receipt = [ordered]@{
    SchemaVersion = 1
    Kind = 'atomic-tree-relocation-receipt-v1'
    Status = 'complete'
    Source = $source
    Destination = $destination
    TopLevelItems = $after.TopLevelItems
    ShallowSeal = $after.ShallowSeal
    ManifestSha256 = Get-FaSha256 -Path $ManifestPath
    VerificationClaim = [string]$manifest.VerificationClaim
    CompletedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReceiptPath -Value $receipt -Depth 8
Write-Host ("atomic tree relocation complete: {0} -> {1}" -f $source, $destination)
