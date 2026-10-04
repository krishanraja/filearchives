[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Source,
    [Parameter(Mandatory)][string] $Destination,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

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

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourcePath = ConvertTo-FaCanonicalPath $Source
$destinationPath = ConvertTo-FaCanonicalPath $Destination
Assert-FaNotProtected -Path $sourcePath -Workspace $workspace -Operation 'atomic tree relocation source'
Assert-FaNotProtected -Path $destinationPath -Workspace $workspace -Operation 'atomic tree relocation destination'
if (-not ([IO.Path]::GetPathRoot($sourcePath)).Equals([IO.Path]::GetPathRoot($destinationPath), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'atomic tree relocation must remain on one volume'
}
if (Test-Path -LiteralPath $destinationPath) { throw "destination already exists: $destinationPath" }
$seal = Get-FaShallowTreeSeal -Path $sourcePath
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'atomic-tree-relocation-v1'
    Source = $sourcePath
    Destination = $destinationPath
    TopLevelItems = $seal.TopLevelItems
    ShallowSeal = $seal.ShallowSeal
    VerificationClaim = 'same-volume directory rename with source absence, destination presence and shallow entry seal; child bytes retained, not individually hashed'
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 8
Write-Host ("atomic tree relocation manifest: top-items={0} path={1}" -f $seal.TopLevelItems, $ManifestPath)
