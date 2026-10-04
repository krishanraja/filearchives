[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)][string] $DestinationRoot,
    [Parameter(Mandatory)][string[]] $Extension,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $Category = 'extension-routed',
    [switch] $MetadataOnly,
    [switch] $IncludeExtensionless,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourceBase = ConvertTo-FaCanonicalPath $SourceRoot
$destinationBase = ConvertTo-FaCanonicalPath $DestinationRoot
Assert-FaNotProtected -Path $sourceBase -Workspace $workspace -Operation 'extension move source access'
Assert-FaNotProtected -Path $destinationBase -Workspace $workspace -Operation 'extension move destination access'
if (-not ([IO.Path]::GetPathRoot($sourceBase)).Equals([IO.Path]::GetPathRoot($destinationBase),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'extension move must remain on one volume'
}
if (-not (Test-Path -LiteralPath $sourceBase -PathType Container)) {
    throw "extension move source is absent: $sourceBase"
}
$extensions = @($Extension | ForEach-Object { ([string]$_).ToLowerInvariant() })
$prefix = $sourceBase.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$moves = [Collections.Generic.List[object]]::new()
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in @(Get-ChildItem -LiteralPath $sourceBase -Recurse -Force -File | Sort-Object FullName)) {
    $fileExtension = $file.Extension.ToLowerInvariant()
    if ($extensions -notcontains $fileExtension -and -not ($IncludeExtensionless -and -not $fileExtension)) { continue }
    $relative = $file.FullName.Substring($prefix.Length).Replace('/', '\')
    $destination = ConvertTo-FaCanonicalPath (Join-Path $destinationBase $relative)
    if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
        throw "extension move destination collision: $destination"
    }
    $hash = if ($MetadataOnly) { $null } else { Get-FaSha256 -Path $file.FullName }
    $moves.Add([pscustomobject]@{
        Source = ConvertTo-FaCanonicalPath $file.FullName
        Destination = $destination
        Length = [long]$file.Length
        LastWriteTimeUtc = ([DateTimeOffset]$file.LastWriteTimeUtc).ToString('o')
        Sha256 = $hash
        VerificationMode = if ($MetadataOnly) { 'metadata-only-same-volume-relocation' } else { 'sha256-and-metadata' }
        Category = $Category
        Disposition = 'move'
        RuleId = 'extension-routing'
    })
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-v1'
    SourceRoot = $sourceBase
    SourceId = 'live-extension-routing'
    Moves = @($moves)
    MoveCount = [long]$moves.Count
    Skipped = @()
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("extension move manifest: moves={0} path={1}" -f $moves.Count, $ManifestPath)
