[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)][string] $SourceId,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string[]] $AllowedDisposition = @('current', 'archive'),
    [string[]] $AllowedConfidence = @('high'),
    [string] $ConfigPath,
    [string] $PolicyPath,
    [datetimeoffset] $AsOf = [DateTimeOffset]::Now
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$requestedConfigPath = $ConfigPath
$requestedPolicyPath = $PolicyPath
$requestedSourceId = $SourceId
$requestedAsOf = $AsOf
. (Join-Path $PSScriptRoot 'propose_layout.ps1') `
    -ConfigPath $requestedConfigPath -PolicyPath $requestedPolicyPath
$ConfigPath = $requestedConfigPath
$PolicyPath = $requestedPolicyPath
$SourceId = $requestedSourceId
$AsOf = $requestedAsOf
if (-not $ConfigPath) { $ConfigPath = Get-FaDefaultWorkspacePath }
if (-not $PolicyPath) { $PolicyPath = Join-Path $repo 'policy\estate-policy-v1.json' }
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json -Depth 64
$root = ConvertTo-FaCanonicalPath $SourceRoot
Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'live file move manifest source access'
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "source root is absent: $root" }

function Get-FaTextDigest {
    param([string] $Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
    } finally { $sha.Dispose() }
}

$rows = [Collections.Generic.List[object]]::new()
$skipped = [Collections.Generic.List[object]]::new()
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Force -ErrorAction Stop | Sort-Object Name)) {
    $item = [pscustomobject]@{
        RelativePath = $file.Name
        Extension = $file.Extension
        LastWriteTimeUtc = ([DateTimeOffset]$file.LastWriteTimeUtc).ToString('o')
        GeneratedHint = $null
    }
    $classification = Get-FaLayoutClassification -Item $item -ItemSourceId $SourceId `
        -Policy $policy -AnalysisDate $AsOf
    if ($AllowedConfidence -notcontains $classification.Confidence -or
        $AllowedDisposition -notcontains $classification.Disposition -or
        -not $classification.DestinationRoot -or -not $classification.DestinationFolder) {
        $skipped.Add([pscustomobject]@{
            Source = $file.FullName
            Disposition = $classification.Disposition
            Confidence = $classification.Confidence
            RuleId = $classification.RuleId
        })
        continue
    }
    $destinationDirectory = ConvertTo-FaCanonicalPath (Join-Path `
        ([string]$classification.DestinationRoot) ([string]$classification.DestinationFolder))
    if (-not ([IO.Path]::GetPathRoot($root)).Equals(
            [IO.Path]::GetPathRoot($destinationDirectory),
            [StringComparison]::OrdinalIgnoreCase)) {
        $skipped.Add([pscustomobject]@{
            Source = $file.FullName
            Disposition = $classification.Disposition
            Confidence = $classification.Confidence
            RuleId = 'cross-volume-requires-copy'
        })
        continue
    }
    Assert-FaNotProtected -Path $destinationDirectory -Workspace $workspace -Operation 'live file move destination'
    $destination = Join-Path $destinationDirectory $file.Name
    if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $suffix = Get-FaTextDigest -Text $file.FullName.ToLowerInvariant()
        $destination = Join-Path $destinationDirectory ("{0}__{1}{2}" -f $stem, $suffix.Substring(0, 12), $file.Extension)
        if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
            throw "could not establish an injective destination for $($file.FullName)"
        }
    }
    $contentHash = try { Get-FaSha256 -Path $file.FullName } catch { $null }
    $rows.Add([pscustomobject]@{
        Source = ConvertTo-FaCanonicalPath $file.FullName
        Destination = ConvertTo-FaCanonicalPath $destination
        Length = [long]$file.Length
        LastWriteTimeUtc = ([DateTimeOffset]$file.LastWriteTimeUtc).ToString('o')
        Sha256 = $contentHash
        VerificationMode = if ($contentHash) { 'sha256-and-metadata' } else { 'metadata-only-cloud-native' }
        Category = $classification.Category
        Disposition = $classification.Disposition
        RuleId = $classification.RuleId
    })
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-v1'
    SourceRoot = $root
    SourceId = $SourceId
    PolicyId = [string]$policy.policy_id
    PolicySha256 = Get-FaSha256 -Path $PolicyPath
    AsOf = $AsOf.ToString('o')
    Moves = @($rows)
    MoveCount = [long]$rows.Count
    Skipped = @($skipped)
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("live file move manifest: moves={0} skipped={1} path={2}" -f
    $rows.Count, $skipped.Count, $ManifestPath)
