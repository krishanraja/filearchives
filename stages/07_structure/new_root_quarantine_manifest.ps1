[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)][string] $QuarantineRoot,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string[]] $ExcludeName = @(),
    [string] $IncludeNameRegex,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourceRoot = ConvertTo-FaCanonicalPath $SourceRoot
$quarantine = ConvertTo-FaCanonicalPath $QuarantineRoot
Assert-FaNotProtected -Path $sourceRoot -Workspace $workspace -Operation 'root quarantine source'
Assert-FaNotProtected -Path $quarantine -Workspace $workspace -Operation 'root quarantine destination'
if (-not ([IO.Path]::GetPathRoot($sourceRoot)).Equals([IO.Path]::GetPathRoot($quarantine), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'root quarantine must remain on the source volume'
}
function Get-FaTextDigest {
    param([string] $Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}
$moves = [Collections.Generic.List[object]]::new()
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -File -Force | Sort-Object Name)) {
    if ($ExcludeName -contains $file.Name -or ($IncludeNameRegex -and $file.Name -notmatch $IncludeNameRegex)) { continue }
    $hash = try { Get-FaSha256 -Path $file.FullName } catch { $null }
    $destination = Join-Path $quarantine $file.Name
    if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $suffix = if ($hash) { $hash.Substring(0, 12) } else { (Get-FaTextDigest -Text $file.FullName).Substring(0, 12) }
        $destination = Join-Path $quarantine ("{0}__{1}{2}" -f $stem, $suffix, $file.Extension)
        if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) { throw "quarantine collision: $destination" }
    }
    $moves.Add([pscustomobject]@{
        Source = ConvertTo-FaCanonicalPath $file.FullName
        Destination = ConvertTo-FaCanonicalPath $destination
        Length = [long]$file.Length
        LastWriteTimeUtc = ([DateTimeOffset]$file.LastWriteTimeUtc).ToString('o')
        Sha256 = $hash
        VerificationMode = if ($hash) { 'sha256-and-metadata' } else { 'metadata-only-cloud-native' }
        Category = 'root-quarantine'
        Disposition = 'quarantine'
        RuleId = 'explicit-root-cleanup'
    })
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-v1'
    SourceRoot = $sourceRoot
    SourceId = 'root-quarantine'
    Moves = @($moves)
    MoveCount = [long]$moves.Count
    Skipped = @()
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("root quarantine manifest: moves={0}" -f $moves.Count)
