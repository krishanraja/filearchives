[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $InputManifestPath,
    [Parameter(Mandatory)][string] $OutputManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $SkipRelativePathRegex = '(?i)(^|\\)(desktop\.ini|thumbs\.db|\.DS_Store)$',
    [string] $Category = 'verified-folder-copy-shard',
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$inputPath = ConvertTo-FaCanonicalPath $InputManifestPath
$input = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
if ($input.SchemaVersion -ne 1 -or $input.Kind -ne 'verified-folder-copy-v1' -or
    $input.Status -notin @('ready','ready-partial') -or $input.Approved -ne $true) {
    throw 'input must be an approved ready verified-folder-copy-v1 manifest'
}
$sourceRoot = ConvertTo-FaCanonicalPath ([string]$input.Source)
$destinationRoot = ConvertTo-FaCanonicalPath ([string]$input.Destination)
Assert-FaNotProtected -Path $sourceRoot -Workspace $workspace -Operation 'verified conversion source root'
Assert-FaNotProtected -Path $destinationRoot -Workspace $workspace -Operation 'verified conversion destination root'
$copies = [Collections.Generic.List[object]]::new()
$skipped = [Collections.Generic.List[object]]::new()
[long]$bytes = 0
foreach ($file in @($input.Files)) {
    $relative = [string]$file.RelativePath
    if ($SkipRelativePathRegex -and $relative -match $SkipRelativePathRegex) {
        $skipped.Add([pscustomobject]@{ RelativePath=$relative; Reason='explicit-system-metadata-skip' })
        continue
    }
    $source = ConvertTo-FaCanonicalPath (Join-Path $sourceRoot $relative)
    $destination = ConvertTo-FaCanonicalPath (Join-Path $destinationRoot $relative)
    if (-not (Test-FaPathWithin -Path $source -Root $sourceRoot) -or
        -not (Test-FaPathWithin -Path $destination -Root $destinationRoot)) {
        throw "verified folder row escapes its root: $relative"
    }
    $copies.Add([pscustomobject]@{
        Source = $source
        Destination = $destination
        Length = [long]$file.Length
        LastWriteTimeUtc = [string]$file.LastWriteTimeUtc
        Sha256 = ([string]$file.Sha256).ToLowerInvariant()
        Category = $Category
        RuleId = 'verified-folder-manifest-conversion'
    })
    $bytes += [long]$file.Length
}
if ($copies.Count + $skipped.Count -ne @($input.Files).Count) {
    throw 'converted and skipped rows do not reconcile to the verified parent'
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-copy-v1'
    SourceRoot = $sourceRoot
    SourceId = 'verified-folder-manifest-conversion'
    ParentManifest = $inputPath
    ParentManifestSha256 = Get-FaSha256 -Path $inputPath
    Copies = @($copies)
    CopyCount = [long]$copies.Count
    CopyBytes = $bytes
    Skipped = @($skipped)
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $OutputManifestPath -Value $manifest -Depth 24
Write-Host ("verified folder converted to live copy: copies={0} skipped={1}" -f $copies.Count,$skipped.Count)
