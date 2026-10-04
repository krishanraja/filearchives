[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)][string[]] $Source,
    [Parameter(Mandatory)][string[]] $Destination,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $Category = 'explicit-routing',
    [string] $Disposition = 'move',
    [string] $RuleId = 'explicit-reviewed-route',
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
if ($Source.Count -ne $Destination.Count) { throw 'Source and Destination counts must match' }
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$root = ConvertTo-FaCanonicalPath $SourceRoot
Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'explicit move root'
$moves = [Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt $Source.Count; $index++) {
    $sourcePath = ConvertTo-FaCanonicalPath $Source[$index]
    $destinationPath = ConvertTo-FaCanonicalPath $Destination[$index]
    Assert-FaNotProtected -Path $sourcePath -Workspace $workspace -Operation 'explicit move source'
    Assert-FaNotProtected -Path $destinationPath -Workspace $workspace -Operation 'explicit move destination'
    if (-not (Test-FaPathWithin -Path $sourcePath -Root $root)) { throw "source escapes explicit root: $sourcePath" }
    if (-not ([IO.Path]::GetPathRoot($sourcePath)).Equals([IO.Path]::GetPathRoot($destinationPath), [StringComparison]::OrdinalIgnoreCase)) {
        throw "explicit move must stay on one volume: $sourcePath"
    }
    $item = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
    $hash = try { Get-FaSha256 -Path $sourcePath } catch { $null }
    if (Test-Path -LiteralPath $destinationPath) { throw "explicit destination already exists: $destinationPath" }
    $moves.Add([pscustomobject]@{
        Source = $sourcePath
        Destination = $destinationPath
        Length = [long]$item.Length
        LastWriteTimeUtc = ([DateTimeOffset]$item.LastWriteTimeUtc).ToString('o')
        Sha256 = $hash
        VerificationMode = if ($hash) { 'sha256-and-metadata' } else { 'metadata-only-cloud-native' }
        Category = $Category
        Disposition = $Disposition
        RuleId = $RuleId
    })
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-v1'
    SourceRoot = $root
    SourceId = 'explicit-reviewed-route'
    Moves = @($moves)
    MoveCount = [long]$moves.Count
    Skipped = @()
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("explicit file move manifest: moves={0}" -f $moves.Count)
