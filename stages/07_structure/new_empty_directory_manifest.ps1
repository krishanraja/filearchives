[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string[]] $PreservePath = @(),
    [switch] $IncludeRoot,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$root = ConvertTo-FaCanonicalPath $SourceRoot
Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'empty-directory scan root'
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "empty-directory source is absent: $root"
}
$preserved = @($PreservePath | ForEach-Object { ConvertTo-FaCanonicalPath $_ })

$directories = [Collections.Generic.List[object]]::new()
$queue = [Collections.Generic.Queue[string]]::new()
$queue.Enqueue($root)
while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    $children = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop)
    $hasDirectFile = $false
    foreach ($child in $children) {
        if (-not $child.PSIsContainer) {
            $hasDirectFile = $true
            continue
        }
        $candidate = ConvertTo-FaCanonicalPath $child.FullName
        if (@($preserved | Where-Object {
            $candidate.Equals($_, [StringComparison]::OrdinalIgnoreCase) -or
            (Test-FaPathWithin -Path $candidate -Root $_)
        }).Count -gt 0) {
            continue
        }
        try {
            Assert-FaNotProtected -Path $candidate -Workspace $workspace -Operation 'empty-directory traversal'
        } catch {
            continue
        }
        $queue.Enqueue($candidate)
    }
    if ($IncludeRoot -or -not $current.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        $directories.Add([pscustomobject]@{
            Path = $current
            HasDirectFile = $hasDirectFile
            Depth = @($current.Substring($root.Length).Trim('\').Split('\', [StringSplitOptions]::RemoveEmptyEntries)).Count
        })
    }
}

$hasFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($directory in $directories) {
    if (-not $directory.HasDirectFile) { continue }
    $cursor = [string]$directory.Path
    while ($cursor.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        $null = $hasFiles.Add($cursor)
        if ($cursor.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = Split-Path -Parent $cursor
    }
}
foreach ($preserve in $preserved) {
    $cursor = $preserve
    while ($cursor.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        $null = $hasFiles.Add($cursor)
        if ($cursor.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = Split-Path -Parent $cursor
    }
}
# Files directly in the root make only the root non-empty; the root is never a target.
$targets = @($directories | Where-Object { -not $hasFiles.Contains([string]$_.Path) } |
    Sort-Object -Property @{Expression='Depth';Descending=$true}, @{Expression='Path';Descending=$false} | ForEach-Object {
        [pscustomobject]@{ Path = [string]$_.Path; Depth = [int]$_.Depth }
    })
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'empty-directory-removal-v1'
    SourceRoot = $root
    IncludeRoot = [bool]$IncludeRoot
    PreservedRoots = $preserved
    Targets = $targets
    TargetCount = [long]$targets.Count
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 12
Write-Host ("empty-directory manifest: targets={0} path={1}" -f $targets.Count, $ManifestPath)
