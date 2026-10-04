[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $EvidenceRoot,
    [Parameter(Mandatory)][string] $VolumeRoot,
    [Parameter(Mandatory)][string] $QuarantineRoot,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string[]] $EligiblePathRegex = @(),
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$evidence = ConvertTo-FaCanonicalPath $EvidenceRoot
$volume = ConvertTo-FaCanonicalPath $VolumeRoot
$quarantine = ConvertTo-FaCanonicalPath $QuarantineRoot
Assert-FaNotProtected -Path $volume -Workspace $workspace -Operation 'ingress dedupe volume'
Assert-FaNotProtected -Path $quarantine -Workspace $workspace -Operation 'ingress dedupe quarantine'
if (-not ([IO.Path]::GetPathRoot($volume)).Equals([IO.Path]::GetPathRoot($quarantine), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ingress duplicate quarantine must remain on the selected volume'
}
if (-not (Test-Path -LiteralPath $evidence -PathType Container)) { throw "evidence root is absent: $evidence" }

function Test-EligiblePath {
    param([string] $Path)
    if (-not (Test-FaPathWithin -Path $Path -Root $volume)) { return $false }
    if (Test-FaPathWithin -Path $Path -Root $quarantine) { return $false }
    if ($EligiblePathRegex.Count -eq 0) { return $true }
    return @($EligiblePathRegex | Where-Object { $Path -match $_ }).Count -gt 0
}
function Get-PathDigest {
    param([string] $Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$candidates = @{}
foreach ($file in @(Get-ChildItem -LiteralPath $evidence -Recurse -Filter '*.json' -File -Force -ErrorAction Stop)) {
    $document = try { Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 48 -DateKind String } catch { continue }
    $rows = @()
    if ($document.Kind -eq 'verified-folder-copy-v1') {
        $rows = @($document.Files | ForEach-Object {
            [pscustomobject]@{ Path=(Join-Path ([string]$document.Destination) ([string]$_.RelativePath)); Length=[long]$_.Length; Sha256=[string]$_.Sha256 }
        })
    } elseif ($document.Kind -eq 'live-file-copy-v1') {
        $rows = @($document.Copies | ForEach-Object {
            [pscustomobject]@{ Path=[string]$_.Destination; Length=[long]$_.Length; Sha256=[string]$_.Sha256 }
        })
    } elseif ($document.Kind -eq 'live-file-move-v1') {
        $rows = @($document.Moves | Where-Object { $_.Sha256 } | ForEach-Object {
            [pscustomobject]@{ Path=[string]$_.Destination; Length=[long]$_.Length; Sha256=[string]$_.Sha256 }
        })
    }
    foreach ($row in $rows) {
        if (-not $row.Sha256) { continue }
        $path = ConvertTo-FaCanonicalPath $row.Path
        if (-not (Test-EligiblePath -Path $path) -or $candidates.ContainsKey($path)) { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ([long]$item.Length -ne [long]$row.Length) { continue }
        $candidates[$path] = [pscustomobject]@{ Path=$path; Length=[long]$row.Length; Sha256=([string]$row.Sha256).ToLowerInvariant() }
    }
}

$moves = [Collections.Generic.List[object]]::new()
$groups = @($candidates.Values | Group-Object { "$($_.Length)|$($_.Sha256)" } | Where-Object Count -gt 1)
foreach ($group in $groups) {
    $proven = @($group.Group | Where-Object {
        try { (Get-FaSha256 -Path $_.Path).Equals($_.Sha256, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
    } | Sort-Object @{Expression={$_.Path.Length}}, @{Expression={$_.Path}})
    if ($proven.Count -lt 2) { continue }
    $survivor = $proven[0]
    foreach ($redundant in @($proven | Select-Object -Skip 1)) {
        $item = Get-Item -LiteralPath $redundant.Path -Force
        $bucket = $redundant.Sha256.Substring(0, 2)
        $destination = Join-Path (Join-Path $quarantine $bucket) $item.Name
        if (Test-Path -LiteralPath $destination) {
            $stem = [IO.Path]::GetFileNameWithoutExtension($item.Name)
            $destination = Join-Path (Split-Path -Parent $destination) ("{0}__{1}{2}" -f $stem, (Get-PathDigest $redundant.Path).Substring(0, 12), $item.Extension)
        }
        $moves.Add([pscustomobject]@{
            Source = $redundant.Path
            Destination = ConvertTo-FaCanonicalPath $destination
            Length = [long]$redundant.Length
            LastWriteTimeUtc = ([DateTimeOffset]$item.LastWriteTimeUtc).ToString('o')
            Sha256 = $redundant.Sha256
            VerificationMode = 'sha256-and-metadata'
            Category = 'exact-ingress-duplicate'
            Disposition = 'quarantine'
            RuleId = 'same-authority-exact-ingress-duplicate'
            Survivor = $survivor.Path
        })
    }
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-v1'
    SourceRoot = $volume
    SourceId = 'ingress-duplicate-quarantine'
    Moves = @($moves)
    MoveCount = [long]$moves.Count
    DuplicateGroupCount = [long]$groups.Count
    CandidateCount = [long]$candidates.Count
    Skipped = @()
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("ingress duplicate quarantine manifest: candidates={0} groups={1} moves={2}" -f $candidates.Count, $groups.Count, $moves.Count)
