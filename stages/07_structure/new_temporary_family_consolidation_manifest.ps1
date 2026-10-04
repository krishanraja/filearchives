[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]] $SearchRoot,
    [Parameter(Mandatory)][string] $ArchiveRoot,
    [Parameter(Mandatory)][string] $QuarantineRoot,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $ConfigPath,
    [string] $PolicyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
if (-not $PolicyPath) { $PolicyPath = Join-Path $repo 'policy\estate-policy-v1.json' }
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json -Depth 64
$archive = ConvertTo-FaCanonicalPath $ArchiveRoot
$quarantine = ConvertTo-FaCanonicalPath $QuarantineRoot
Assert-FaNotProtected -Path $archive -Workspace $workspace -Operation 'temporary family archive destination'
Assert-FaNotProtected -Path $quarantine -Workspace $workspace -Operation 'temporary family quarantine destination'
if (-not ([IO.Path]::GetPathRoot($archive)).Equals([IO.Path]::GetPathRoot($quarantine), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'temporary family archive and quarantine must share one volume'
}

function Get-FaTemporaryFamilyKey {
    param([Parameter(Mandatory)][IO.FileInfo] $File)
    $stem = [IO.Path]::GetFileNameWithoutExtension($File.Name).ToLowerInvariant()
    $stem = $stem -replace '^(copy of[ _-]*)+', ''
    $stem = $stem -replace '(?i)([ _.-]*(copy|draft|final|latest|old|new|revised|revision|rev)[ _.-]*\d*)+$', ''
    $stem = $stem -replace '(?i)[ _.-]*v\d+(\.\d+)*$', ''
    $stem = $stem -replace '(?i)[ _.-]*\(\d+\)$', ''
    $stem = ($stem -replace '[^a-z0-9]+', ' ').Trim()
    if ($stem.Length -lt 8) { return $null }
    return "$stem|$($File.Extension.ToLowerInvariant())"
}

$candidates = [Collections.Generic.List[object]]::new()
$roots = @($SearchRoot | ForEach-Object { ConvertTo-FaCanonicalPath $_ })
foreach ($root in $roots) {
    Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'temporary family scan'
    if (-not ([IO.Path]::GetPathRoot($root)).Equals([IO.Path]::GetPathRoot($archive), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'temporary family consolidation is a same-volume operation'
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction Stop)) {
        if ((Test-FaPathWithin -Path $file.FullName -Root $quarantine) -or
            $file.FullName -notmatch [string]$policy.temporary_document_regex -or
            $file.FullName -match [string]$policy.evergreen_knowledge_regex) { continue }
        $key = Get-FaTemporaryFamilyKey -File $file
        if (-not $key) { continue }
        $hash = try { Get-FaSha256 -Path $file.FullName } catch { $null }
        if (-not $hash) { continue }
        $candidates.Add([pscustomobject]@{ File=$file; Key=$key; Sha256=$hash })
    }
}

$moves = [Collections.Generic.List[object]]::new()
$families = [Collections.Generic.List[object]]::new()
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($group in @($candidates | Group-Object Key | Where-Object Count -gt 1 | Sort-Object Name)) {
    $ordered = @($group.Group | Sort-Object @{Expression={$_.File.LastWriteTimeUtc};Descending=$true}, @{Expression={$_.File.FullName};Descending=$false})
    $keeper = $ordered[0]
    $familySlug = (($group.Name.Split('|')[0] -replace '[^a-z0-9]+','-').Trim('-'))
    $familySlug = $familySlug.Substring(0, [Math]::Min(80, $familySlug.Length))
    for ($i=0; $i -lt $ordered.Count; $i++) {
        $entry = $ordered[$i]
        $keeperRoot = Join-Path $archive 'Temporary-Family-Keepers'
        if ($i -eq 0 -and (Test-FaPathWithin -Path $entry.File.FullName -Root $keeperRoot)) { continue }
        $base = if ($i -eq 0) { $keeperRoot } else { Join-Path $quarantine $familySlug }
        $destination = Join-Path $base $entry.File.Name
        if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
            $stem = [IO.Path]::GetFileNameWithoutExtension($entry.File.Name)
            $destination = Join-Path $base ("{0}__{1}{2}" -f $stem, $entry.Sha256.Substring(0,12), $entry.File.Extension)
            if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
                throw "temporary family destination collision: $destination"
            }
        }
        if ($entry.File.FullName.Equals($destination, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $moves.Add([pscustomobject]@{
            Source = ConvertTo-FaCanonicalPath $entry.File.FullName
            Destination = ConvertTo-FaCanonicalPath $destination
            Length = [long]$entry.File.Length
            LastWriteTimeUtc = ([DateTimeOffset]$entry.File.LastWriteTimeUtc).ToString('o')
            Sha256 = [string]$entry.Sha256
            VerificationMode = 'sha256-and-metadata'
            Category = 'temporary-document-family'
            Disposition = if ($i -eq 0) { 'archive-family-keeper' } else { 'quarantine-superseded-family-member' }
            RuleId = if ($i -eq 0) { 'temporary-family-newest-keeper' } else { 'temporary-family-superseded' }
        })
    }
    $families.Add([pscustomobject]@{ Family=$group.Name; Members=$ordered.Count; Keeper=$keeper.File.FullName })
}

$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-v1'
    SourceRoot = [IO.Path]::GetPathRoot($archive)
    SourceId = 'temporary-family-consolidation'
    Moves = @($moves)
    MoveCount = [long]$moves.Count
    Families = @($families)
    FamilyCount = [long]$families.Count
    Skipped = @()
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("temporary family manifest: families={0} moves={1}" -f $families.Count, $moves.Count)
