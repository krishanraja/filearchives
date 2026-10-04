[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $InputManifestPath,
    [Parameter(Mandatory)][string] $OutputManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$inputPath = ConvertTo-FaCanonicalPath $InputManifestPath
$input = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
if ($input.SchemaVersion -ne 1 -or $input.Kind -ne 'live-file-copy-v1' -or $input.Approved -ne $true) {
    throw 'input must be an approved live-file-copy-v1 manifest'
}
$pending = [Collections.Generic.List[object]]::new()
$satisfied = [Collections.Generic.List[object]]::new()
foreach ($copy in @($input.Copies)) {
    $source = ConvertTo-FaCanonicalPath ([string]$copy.Source)
    $destination = ConvertTo-FaCanonicalPath ([string]$copy.Destination)
    Assert-FaNotProtected -Path $source -Workspace $workspace -Operation 'residual copy source'
    Assert-FaNotProtected -Path $destination -Workspace $workspace -Operation 'residual copy destination'
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $pending.Add($copy)
        continue
    }
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or
        (Get-FaSha256 -Path $destination) -ne [string]$copy.Sha256) {
        throw "copy source is absent without an exact verified destination: $source"
    }
    $satisfied.Add([pscustomobject]@{
        Source = $source
        Destination = $destination
        Length = [long]$copy.Length
        Sha256 = [string]$copy.Sha256
        Evidence = 'source-absent; destination whole-file SHA-256 matches frozen parent row'
    })
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-copy-v1'
    SourceRoot = ConvertTo-FaCanonicalPath ([string]$input.SourceRoot)
    SourceId = [string]$input.SourceId
    ParentManifest = $inputPath
    ParentManifestSha256 = Get-FaSha256 -Path $inputPath
    Copies = @($pending)
    CopyCount = [long]$pending.Count
    AlreadySatisfied = @($satisfied)
    AlreadySatisfiedCount = [long]$satisfied.Count
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $OutputManifestPath -Value $manifest -Depth 24
Write-Host ("residual copy manifest: pending={0} already-satisfied={1}" -f $pending.Count,$satisfied.Count)
