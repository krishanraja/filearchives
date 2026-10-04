[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)][string] $SourceId,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string[]] $AllowedDisposition = @('personal-authority'),
    [string] $RequiredConfidence = 'high',
    [string[]] $AllowedConfidence = @(),
    [string[]] $ExcludeRuleId = @(),
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
. (Join-Path $repo 'stages\07_structure\propose_layout.ps1') `
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
$effectiveConfidence = if ($AllowedConfidence.Count -gt 0) { $AllowedConfidence } else { @($RequiredConfidence) }
Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'live file copy source access'
$copies = [Collections.Generic.List[object]]::new()
$skipped = [Collections.Generic.List[object]]::new()
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Force | Sort-Object Name)) {
    $item = [pscustomobject]@{
        RelativePath = $file.Name
        Extension = $file.Extension
        LastWriteTimeUtc = ([DateTimeOffset]$file.LastWriteTimeUtc).ToString('o')
        GeneratedHint = $null
    }
    $classification = Get-FaLayoutClassification -Item $item -ItemSourceId $SourceId `
        -Policy $policy -AnalysisDate $AsOf
    if ($ExcludeRuleId -contains $classification.RuleId -or
        $effectiveConfidence -notcontains $classification.Confidence -or
        $AllowedDisposition -notcontains $classification.Disposition -or
        -not $classification.DestinationRoot -or -not $classification.DestinationFolder) {
        continue
    }
    $destinationDirectory = ConvertTo-FaCanonicalPath (Join-Path `
        ([string]$classification.DestinationRoot) ([string]$classification.DestinationFolder))
    Assert-FaNotProtected -Path $destinationDirectory -Workspace $workspace -Operation 'live file copy destination'
    $hash = try { Get-FaSha256 -Path $file.FullName } catch { $null }
    if (-not $hash) {
        $skipped.Add([pscustomobject]@{
            Source = $file.FullName
            RuleId = $classification.RuleId
            Reason = 'content-unreadable-or-cloud-native'
        })
        continue
    }
    $destination = Join-Path $destinationDirectory $file.Name
    if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $destination = Join-Path $destinationDirectory `
            ("{0}__{1}{2}" -f $stem, $hash.Substring(0, 12), $file.Extension)
        if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
            throw "could not establish an injective copy destination: $destination"
        }
    }
    $copies.Add([pscustomobject]@{
        Source = ConvertTo-FaCanonicalPath $file.FullName
        Destination = ConvertTo-FaCanonicalPath $destination
        Length = [long]$file.Length
        LastWriteTimeUtc = ([DateTimeOffset]$file.LastWriteTimeUtc).ToString('o')
        Sha256 = $hash
        Category = $classification.Category
        RuleId = $classification.RuleId
    })
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-copy-v1'
    SourceRoot = $root
    SourceId = $SourceId
    Copies = @($copies)
    CopyCount = [long]$copies.Count
    SkippedUnproven = @($skipped)
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("live file copy manifest: copies={0} unproven={1} path={2}" -f
    $copies.Count, $skipped.Count, $ManifestPath)
