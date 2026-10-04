[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $CopyManifestPath,
    [Parameter(Mandatory)][string] $RetentionRoot,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$copy = Get-Content -LiteralPath $CopyManifestPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
if ($copy.Kind -ne 'verified-folder-copy-v1' -or $copy.AllowUnproven -ne $true) {
    throw 'source must be a verified-folder manifest that explicitly retained unproven files'
}
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourceRoot = ConvertTo-FaCanonicalPath ([string]$copy.Source)
$retention = ConvertTo-FaCanonicalPath $RetentionRoot
Assert-FaNotProtected -Path $sourceRoot -Workspace $workspace -Operation 'unproven retention source'
Assert-FaNotProtected -Path $retention -Workspace $workspace -Operation 'unproven retention destination'
if (-not ([IO.Path]::GetPathRoot($sourceRoot)).Equals([IO.Path]::GetPathRoot($retention), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'unproven retention must stay on the source volume/account'
}
function Get-FaTextDigest {
    param([string] $Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}
$moves = [Collections.Generic.List[object]]::new()
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($row in @($copy.Unproven)) {
    $source = ConvertTo-FaCanonicalPath (Join-Path $sourceRoot ([string]$row.RelativePath))
    $destination = ConvertTo-FaCanonicalPath (Join-Path $retention ([string]$row.RelativePath))
    if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($destination)
        $suffix = (Get-FaTextDigest -Text ([string]$row.RelativePath)).Substring(0, 12)
        $destination = Join-Path (Split-Path -Parent $destination) ("{0}__{1}{2}" -f $stem, $suffix, [IO.Path]::GetExtension($destination))
        if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
            throw "unproven retention collision: $destination"
        }
    }
    $item = Get-Item -LiteralPath $source -Force -ErrorAction Stop
    $moves.Add([pscustomobject]@{
        Source = $source
        Destination = $destination
        Length = [long]$item.Length
        LastWriteTimeUtc = ([DateTimeOffset]$item.LastWriteTimeUtc).ToString('o')
        Sha256 = $null
        VerificationMode = 'metadata-only-unproven-retention'
        Category = 'ownership-bound-or-unreadable'
        Disposition = 'retention-exception'
        RuleId = 'unproven-stays-on-source-account'
    })
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-v1'
    SourceRoot = $sourceRoot
    SourceId = 'unproven-retention'
    Moves = @($moves)
    MoveCount = [long]$moves.Count
    Skipped = @()
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("unproven retention manifest: moves={0}" -f $moves.Count)
