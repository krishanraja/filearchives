[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $CopyReceiptPath,
    [Parameter(Mandatory)][string] $QuarantineRoot,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $CopyManifestPath,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$receipt = Get-Content -LiteralPath $CopyReceiptPath -Raw | ConvertFrom-Json -Depth 32
if ($receipt.Status -ne 'complete' -or $receipt.SourceRetained -ne $true) {
    throw 'copy receipt is not a complete source-retaining receipt'
}
$copyRows = @()
$retirementSourceRoot = $null
if ($receipt.Kind -eq 'live-file-copy-receipt-v1') {
    $copyRows = @($receipt.Copies)
    if ($copyRows.Count -gt 0) { $retirementSourceRoot = Split-Path -Parent ([string]$copyRows[0].Source) }
} elseif ($receipt.Kind -eq 'verified-folder-copy-receipt-v1') {
    if (-not $CopyManifestPath) {
        $CopyManifestPath = Join-Path (Split-Path -Parent $CopyReceiptPath) 'manifest.json'
    }
    $copyManifest = Get-Content -LiteralPath $CopyManifestPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
    if ($copyManifest.Kind -ne 'verified-folder-copy-v1' -or
        (Get-FaSha256 -Path $CopyManifestPath) -ne [string]$receipt.ManifestSha256) {
        throw 'verified-folder copy manifest does not match the complete receipt'
    }
    $copyRows = @($copyManifest.Files | ForEach-Object {
        [pscustomobject]@{
            Source = Join-Path ([string]$copyManifest.Source) ([string]$_.RelativePath)
            Destination = Join-Path ([string]$copyManifest.Destination) ([string]$_.RelativePath)
            Sha256 = [string]$_.Sha256
        }
    })
    $retirementSourceRoot = ConvertTo-FaCanonicalPath ([string]$copyManifest.Source)
} else {
    throw "unsupported copy receipt kind: $($receipt.Kind)"
}
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$quarantine = ConvertTo-FaCanonicalPath $QuarantineRoot
Assert-FaNotProtected -Path $quarantine -Workspace $workspace -Operation 'copy retirement quarantine'
$moves = [Collections.Generic.List[object]]::new()
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($copy in $copyRows) {
    if ((Get-FaSha256 -Path ([string]$copy.Destination)) -ne [string]$copy.Sha256) {
        throw "destination no longer proves the source copy: $($copy.Destination)"
    }
    $sourceItem = Get-Item -LiteralPath ([string]$copy.Source) -Force -ErrorAction Stop
    # Preserve the source-relative layout. Flattening a folder copy into one
    # quarantine directory makes ordinary repeated names (config.xml,
    # desktop.ini, etc.) collide and loses provenance.
    $relative = [IO.Path]::GetRelativePath($retirementSourceRoot, $sourceItem.FullName)
    if ($relative -eq '..' -or $relative.StartsWith('..\') -or [IO.Path]::IsPathRooted($relative)) {
        throw "copy retirement source escapes its verified source root: $($sourceItem.FullName)"
    }
    $destination = Join-Path $quarantine $relative
    if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($sourceItem.Name)
        $destination = Join-Path (Split-Path -Parent $destination) `
            ("{0}__{1}{2}" -f $stem, ([string]$copy.Sha256).Substring(0, 12), $sourceItem.Extension)
        if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
            throw "copy retirement destination collision: $destination"
        }
    }
    $moves.Add([pscustomobject]@{
        Source = ConvertTo-FaCanonicalPath $sourceItem.FullName
        Destination = ConvertTo-FaCanonicalPath $destination
        Length = [long]$sourceItem.Length
        LastWriteTimeUtc = ([DateTimeOffset]$sourceItem.LastWriteTimeUtc).ToString('o')
        Sha256 = [string]$copy.Sha256
        VerificationMode = 'sha256-and-metadata'
        Category = 'verified-copy-source-retirement'
        Disposition = 'quarantine'
        RuleId = 'verified-copy-receipt'
    })
}
if ($moves.Count -eq 0) {
    throw 'copy receipt contains no source files to retire'
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-v1'
    SourceRoot = $retirementSourceRoot
    SourceId = 'verified-copy-retirement'
    Moves = @($moves)
    MoveCount = [long]$moves.Count
    Skipped = @()
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("copy retirement manifest: moves={0}" -f $moves.Count)
