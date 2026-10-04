[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Source,
    [Parameter(Mandatory)][string] $Destination,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string[]] $IncludeExtension = @(),
    [string] $ExcludePathRegex = '(?i)(^|\\)(desktop\.ini|thumbs\.db|\.DS_Store)$',
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourceRoot = ConvertTo-FaCanonicalPath $Source
$destinationRoot = ConvertTo-FaCanonicalPath $Destination
Assert-FaNotProtected -Path $sourceRoot -Workspace $workspace -Operation 'streaming folder copy source'
Assert-FaNotProtected -Path $destinationRoot -Workspace $workspace -Operation 'streaming folder copy destination'
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "streaming copy source folder is absent: $sourceRoot"
}
if (Test-Path -LiteralPath $destinationRoot) {
    throw "streaming copy destination already exists at manifest freeze: $destinationRoot"
}
foreach ($configuredSource in $workspace.Sources) {
    if ($sourceRoot.Equals($configuredSource.Path, [StringComparison]::OrdinalIgnoreCase)) {
        throw "copying an entire configured source root is refused: $sourceRoot"
    }
}

$prefix = $sourceRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$files = [Collections.Generic.List[object]]::new()
$skipped = [Collections.Generic.List[object]]::new()
[long]$bytes = 0
foreach ($item in @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force -File -ErrorAction Stop |
    Sort-Object FullName)) {
    $relative = $item.FullName.Substring($prefix.Length).Replace('/', '\')
    $extension = $item.Extension.ToLowerInvariant()
    if ($IncludeExtension.Count -gt 0 -and $IncludeExtension -notcontains $extension) {
        $skipped.Add([pscustomobject]@{ RelativePath=$relative; Length=[long]$item.Length; Reason='extension-not-included' })
        continue
    }
    if ($ExcludePathRegex -and $relative -match $ExcludePathRegex) {
        $skipped.Add([pscustomobject]@{ RelativePath=$relative; Length=[long]$item.Length; Reason='explicit-skip' })
        continue
    }
    $destinationPath = ConvertTo-FaCanonicalPath (Join-Path $destinationRoot $relative)
    if (-not (Test-FaPathWithin -Path $destinationPath -Root $destinationRoot)) {
        throw "streaming copy destination escapes its root: $relative"
    }
    $files.Add([pscustomobject]@{
        RelativePath = $relative
        Source = ConvertTo-FaCanonicalPath $item.FullName
        Destination = $destinationPath
        Length = [long]$item.Length
        LastWriteTimeUtc = ([DateTimeOffset]$item.LastWriteTimeUtc).ToString('o')
    })
    $bytes += [long]$item.Length
}
if ($files.Count -eq 0) { throw 'streaming copy manifest contains no eligible files' }

$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'streaming-folder-copy-v1'
    SourceRoot = $sourceRoot
    DestinationRoot = $destinationRoot
    Files = @($files)
    FileCount = [long]$files.Count
    Bytes = $bytes
    Skipped = @($skipped)
    Approved = $true
    ApprovalReason = $ApprovalReason
    VerificationClaim = 'source metadata is frozen; execution hashes bytes while streaming to a destination-volume temporary file, then requires whole-file SHA-256 readback before in-place rename'
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 20
Write-Host ("streaming folder copy manifest: files={0} bytes={1} skipped={2} path={3}" -f
    $files.Count,$bytes,$skipped.Count,$ManifestPath)
