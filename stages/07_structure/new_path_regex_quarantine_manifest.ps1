[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]] $SearchRoot,
    [Parameter(Mandatory)][string] $QuarantineRoot,
    [Parameter(Mandatory)][string] $IncludePathRegex,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string[]] $IncludeExtension = @(),
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$quarantine = ConvertTo-FaCanonicalPath $QuarantineRoot
Assert-FaNotProtected -Path $quarantine -Workspace $workspace -Operation 'path-regex quarantine destination'
$volume = [IO.Path]::GetPathRoot($quarantine)
$moves = [Collections.Generic.List[object]]::new()
$skipped = [Collections.Generic.List[object]]::new()
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($rawRoot in $SearchRoot) {
    $root = ConvertTo-FaCanonicalPath $rawRoot
    Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'path-regex quarantine scan'
    if (-not ([IO.Path]::GetPathRoot($root)).Equals($volume, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'path-regex quarantine must stay on one volume'
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    $cohort = ((Split-Path -Leaf $root) -replace '[^A-Za-z0-9._-]','_')
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction Stop)) {
        if (Test-FaPathWithin -Path $file.FullName -Root $quarantine) { continue }
        $relative = [IO.Path]::GetRelativePath($root, $file.FullName)
        if ($relative -notmatch $IncludePathRegex) { continue }
        if ($IncludeExtension.Count -gt 0 -and $IncludeExtension -notcontains $file.Extension.ToLowerInvariant()) { continue }
        $hash = try { Get-FaSha256 -Path $file.FullName } catch { $null }
        if (-not $hash) {
            $skipped.Add([pscustomobject]@{ Source=$file.FullName; Reason='content-unreadable' })
            continue
        }
        $destination = Join-Path (Join-Path $quarantine $cohort) $relative
        if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) {
            $stem = [IO.Path]::GetFileNameWithoutExtension($destination)
            $destination = Join-Path (Split-Path -Parent $destination) ("{0}__{1}{2}" -f $stem,$hash.Substring(0,12),$file.Extension)
            if ((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)) { throw "quarantine collision: $destination" }
        }
        $moves.Add([pscustomobject]@{
            Source = ConvertTo-FaCanonicalPath $file.FullName
            Destination = ConvertTo-FaCanonicalPath $destination
            Length = [long]$file.Length
            LastWriteTimeUtc = ([DateTimeOffset]$file.LastWriteTimeUtc).ToString('o')
            Sha256 = $hash
            VerificationMode = 'sha256-and-metadata'
            Category = 'path-regex-quarantine'
            Disposition = 'quarantine'
            RuleId = 'explicit-path-regex-quarantine'
        })
    }
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-v1'
    SourceRoot = $volume
    SourceId = 'path-regex-quarantine'
    Moves = @($moves)
    MoveCount = [long]$moves.Count
    Skipped = @($skipped)
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("path-regex quarantine manifest: moves={0} skipped={1}" -f $moves.Count,$skipped.Count)
