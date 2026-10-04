[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ProposalPath,
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)][string] $SourceId,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $CohortName,
    [string[]] $AllowedDisposition = @('current', 'archive', 'personal-authority'),
    [string[]] $AllowedConfidence = @('high'),
    [string[]] $ExcludeRuleId = @('system-metadata-quarantine'),
    [string] $ExcludeRelativePathRegex,
    [string[]] $IncludeExtension = @(),
    [string[]] $ExcludeExtension = @(),
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$root = ConvertTo-FaCanonicalPath $SourceRoot
Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'layout copy source access'
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "layout copy source folder is absent: $root"
}
if (-not (Test-Path -LiteralPath $ProposalPath -PathType Leaf)) {
    throw "layout proposal is absent: $ProposalPath"
}
if ($CohortName -and ($CohortName -match '[\\/]' -or $CohortName -in @('.', '..'))) {
    throw 'cohort name must be one safe path component'
}

$copies = [Collections.Generic.List[object]]::new()
$skipped = [Collections.Generic.List[object]]::new()
$reserved = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($line in [IO.File]::ReadLines($ProposalPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $row = $line | ConvertFrom-Json -Depth 16 -DateKind String
    if ([string]$row.SourceId -ne $SourceId) { continue }
    if ($AllowedDisposition -notcontains [string]$row.Disposition -or
        $AllowedConfidence -notcontains [string]$row.Confidence -or
        $ExcludeRuleId -contains [string]$row.RuleId -or
        -not $row.DestinationRoot -or -not $row.DestinationFolder) {
        continue
    }
    $relative = ([string]$row.RelativePath).Replace('/', '\').TrimStart('\')
    if ([IO.Path]::GetFileName($relative).ToLowerInvariant() -in @('desktop.ini','thumbs.db','.ds_store')) {
        $skipped.Add([pscustomobject]@{ RelativePath=$relative; RuleId=[string]$row.RuleId; Reason='system-metadata-excluded' })
        continue
    }
    if ($ExcludeRelativePathRegex -and $relative -match $ExcludeRelativePathRegex) { continue }
    $extension = [IO.Path]::GetExtension($relative).ToLowerInvariant()
    if ($IncludeExtension.Count -gt 0 -and $IncludeExtension -notcontains $extension) { continue }
    if ($ExcludeExtension -contains $extension) { continue }
    if ([IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith('..\')) {
        throw "proposal relative path escapes source root: $relative"
    }
    $source = ConvertTo-FaCanonicalPath (Join-Path $root $relative)
    if (-not (Test-FaPathWithin -Path $source -Root $root)) {
        throw "proposal source escapes selected root: $source"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        $skipped.Add([pscustomobject]@{ RelativePath=$relative; RuleId=[string]$row.RuleId; Reason='source-absent-after-proposal' })
        continue
    }
    $sourceItem = Get-Item -LiteralPath $source -Force
    if ([long]$sourceItem.Length -ne [long]$row.Length -or
        ([DateTimeOffset]$sourceItem.LastWriteTimeUtc).UtcTicks -ne
            [DateTimeOffset]::Parse([string]$row.LastWriteTimeUtc).UtcTicks) {
        $skipped.Add([pscustomobject]@{ RelativePath=$relative; RuleId=[string]$row.RuleId; Reason='source-metadata-changed-after-proposal' })
        continue
    }
    $hash = try { Get-FaSha256 -Path $source } catch { $null }
    if (-not $hash) {
        $skipped.Add([pscustomobject]@{ RelativePath=$relative; RuleId=[string]$row.RuleId; Reason='source-content-unreadable' })
        continue
    }
    $destinationBase = ConvertTo-FaCanonicalPath (Join-Path ([string]$row.DestinationRoot) ([string]$row.DestinationFolder))
    Assert-FaNotProtected -Path $destinationBase -Workspace $workspace -Operation 'layout copy destination'
    if ($CohortName) { $destinationBase = Join-Path $destinationBase $CohortName }
    $destination = ConvertTo-FaCanonicalPath (Join-Path $destinationBase $relative)
    Assert-FaNotProtected -Path $destination -Workspace $workspace -Operation 'layout copy destination'

    $collision = $reserved.ContainsKey($destination)
    if (-not $collision -and (Test-Path -LiteralPath $destination -PathType Leaf)) {
        $collision = (Get-FaSha256 -Path $destination) -ne $hash
    }
    if ($collision) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($destination)
        $destination = Join-Path (Split-Path -Parent $destination) ("{0}__{1}{2}" -f $stem, $hash.Substring(0, 12), $sourceItem.Extension)
    }
    if ($reserved.ContainsKey($destination) -and $reserved[$destination] -ne $hash) {
        throw "layout copy destination remains non-injective: $destination"
    }
    if ((Test-Path -LiteralPath $destination -PathType Leaf) -and (Get-FaSha256 -Path $destination) -ne $hash) {
        throw "layout copy destination collision remains after suffixing: $destination"
    }
    $reserved[$destination] = $hash
    $copies.Add([pscustomobject]@{
        Source = $source
        Destination = $destination
        Length = [long]$sourceItem.Length
        LastWriteTimeUtc = ([DateTimeOffset]$sourceItem.LastWriteTimeUtc).ToString('o')
        Sha256 = $hash
        Category = [string]$row.Category
        RuleId = [string]$row.RuleId
    })
}

$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-copy-v1'
    SourceRoot = $root
    SourceId = $SourceId
    ProposalPath = ConvertTo-FaCanonicalPath $ProposalPath
    ProposalSha256 = Get-FaSha256 -Path $ProposalPath
    CohortName = $CohortName
    Copies = @($copies)
    CopyCount = [long]$copies.Count
    Skipped = @($skipped)
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("layout copy manifest: copies={0} skipped={1} path={2}" -f $copies.Count, $skipped.Count, $ManifestPath)
