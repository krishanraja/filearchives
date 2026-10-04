[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ReceiptPath,
    [Parameter(Mandatory)][switch] $Execute,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
if (-not $Execute) { throw 'execution requires the explicit -Execute switch' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 24 -DateKind String
if ($manifest.SchemaVersion -ne 1 -or $manifest.Kind -ne 'empty-directory-removal-v1') {
    throw 'unsupported empty-directory manifest'
}
if ($manifest.Approved -ne $true -or [string]::IsNullOrWhiteSpace([string]$manifest.ApprovalReason)) {
    throw 'empty-directory manifest is not approved'
}
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$root = ConvertTo-FaCanonicalPath ([string]$manifest.SourceRoot)
Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'empty-directory execution root'
$removed = [Collections.Generic.List[string]]::new()
$changed = [Collections.Generic.List[object]]::new()
foreach ($target in @($manifest.Targets | Sort-Object Depth -Descending)) {
    $path = ConvertTo-FaCanonicalPath ([string]$target.Path)
    Assert-FaNotProtected -Path $path -Workspace $workspace -Operation 'empty-directory removal'
    $isRoot = $path.Equals($root, [StringComparison]::OrdinalIgnoreCase)
    if ((-not $isRoot -and -not (Test-FaPathWithin -Path $path -Root $root)) -or
        ($isRoot -and $manifest.IncludeRoot -ne $true)) {
        throw "empty-directory target escapes root: $path"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
    $child = Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop | Select-Object -First 1
    if ($null -ne $child) {
        $changed.Add([pscustomobject]@{ Path = $path; Reason = 'not-empty-at-action-time' })
        continue
    }
    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
    if (Test-Path -LiteralPath $path) { throw "empty directory still exists after removal: $path" }
    $removed.Add($path)
}
$receipt = [ordered]@{
    SchemaVersion = 1
    Kind = 'empty-directory-removal-receipt-v1'
    Status = 'complete'
    SourceRoot = $root
    Removed = @($removed)
    RemovedCount = [long]$removed.Count
    ChangedSinceManifest = @($changed)
    ManifestPath = ConvertTo-FaCanonicalPath $ManifestPath
    CompletedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReceiptPath -Value $receipt -Depth 12
Write-Host ("empty-directory removal complete: removed={0} changed={1}" -f $removed.Count, $changed.Count)
