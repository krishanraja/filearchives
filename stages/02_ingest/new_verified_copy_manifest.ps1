[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Source,
    [Parameter(Mandatory)][string] $Destination,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string[]] $IncludeExtension = @(),
    [string[]] $ExcludeExtension = @(),
    [string] $ExcludePathRegex,
    [switch] $AllowUnproven,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourcePath = ConvertTo-FaCanonicalPath $Source
$destinationPath = ConvertTo-FaCanonicalPath $Destination
Assert-FaNotProtected -Path $sourcePath -Workspace $workspace -Operation 'verified copy source access'
Assert-FaNotProtected -Path $destinationPath -Workspace $workspace -Operation 'verified copy destination access'
if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
    throw "copy source folder is absent: $sourcePath"
}
if (Test-Path -LiteralPath $destinationPath) {
    throw "copy destination already exists at manifest freeze: $destinationPath"
}
foreach ($configuredSource in $workspace.Sources) {
    if ($sourcePath.Equals($configuredSource.Path, [StringComparison]::OrdinalIgnoreCase) -and
        $IncludeExtension.Count -eq 0 -and -not $ExcludePathRegex) {
        throw "copying an entire configured source root is refused: $sourcePath"
    }
}

$prefix = $sourcePath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$files = [Collections.Generic.List[object]]::new()
$unproven = [Collections.Generic.List[object]]::new()
$directories = [Collections.Generic.List[string]]::new()
$excluded = [Collections.Generic.List[object]]::new()
[long]$bytes = 0
foreach ($item in @(Get-ChildItem -LiteralPath $sourcePath -Recurse -Force -ErrorAction Stop |
    Sort-Object FullName)) {
    $relative = $item.FullName.Substring($prefix.Length).Replace('/', '\')
    if ($item.PSIsContainer) {
        continue
    }
    $extension = $item.Extension.ToLowerInvariant()
    if ($IncludeExtension.Count -gt 0 -and $IncludeExtension -notcontains $extension) {
        $excluded.Add([pscustomobject]@{
            RelativePath = $relative
            Length = [long]$item.Length
            Reason = 'extension-not-included-by-manifest-policy'
        })
        continue
    }
    if ($ExcludeExtension -contains $extension) {
        $excluded.Add([pscustomobject]@{
            RelativePath = $relative
            Length = [long]$item.Length
            Reason = 'extension-excluded-by-manifest-policy'
        })
        continue
    }
    if ($ExcludePathRegex -and $relative -match $ExcludePathRegex) {
        $excluded.Add([pscustomobject]@{
            RelativePath = $relative
            Length = [long]$item.Length
            Reason = 'path-excluded-by-manifest-policy'
        })
        continue
    }
    try {
        $hash = Get-FaSha256 -Path $item.FullName
        $files.Add([pscustomobject]@{
            RelativePath = $relative
            Length = [long]$item.Length
            LastWriteTimeUtc = ([DateTimeOffset]$item.LastWriteTimeUtc).ToString('o')
            Sha256 = $hash
        })
        $bytes += [long]$item.Length
    } catch {
        $unproven.Add([pscustomobject]@{
            RelativePath = $relative
            Length = [long]$item.Length
            ErrorType = $_.Exception.GetType().Name
        })
    }
}
$requiredDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in $files) {
    $parent = Split-Path -Parent ([string]$file.RelativePath)
    while ($parent) {
        $null = $requiredDirectories.Add($parent)
        $next = Split-Path -Parent $parent
        if ($next -eq $parent) { break }
        $parent = $next
    }
}
foreach ($directory in @($requiredDirectories | Sort-Object)) { $directories.Add($directory) }
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'verified-folder-copy-v1'
    Source = $sourcePath
    Destination = $destinationPath
    Status = if ($unproven.Count -eq 0) { 'ready' } elseif ($AllowUnproven) { 'ready-partial' } else { 'blocked-unreadable' }
    Files = @($files)
    Directories = @($directories)
    FileCount = [long]$files.Count
    DirectoryCount = [long]$directories.Count
    Bytes = $bytes
    Unproven = @($unproven)
    AllowUnproven = [bool]$AllowUnproven
    Excluded = @($excluded)
    Approved = $true
    ApprovalReason = $ApprovalReason
    VerificationClaim = 'every copied file must match its source whole-file SHA-256; source remains intact'
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("copy manifest: {0} status={1} files={2} dirs={3} bytes={4} unproven={5} excluded={6}" -f
    $ManifestPath, $manifest.Status, $files.Count, $directories.Count, $bytes, $unproven.Count, $excluded.Count)
if ($unproven.Count -gt 0 -and -not $AllowUnproven) { exit 3 }
