[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $InputManifestPath,
    [Parameter(Mandatory)][string] $OutputManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $ExcludePathRegex,
    [string[]] $ExcludeExtension = @(),
    [long] $MaximumFileBytes = 0,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

if (-not $ExcludePathRegex -and $ExcludeExtension.Count -eq 0 -and $MaximumFileBytes -le 0) {
    throw 'at least one explicit copy exclusion is required'
}
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$inputPath = ConvertTo-FaCanonicalPath $InputManifestPath
$input = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
if ($input.SchemaVersion -ne 1 -or $input.Kind -ne 'live-file-copy-v1' -or $input.Approved -ne $true) {
    throw 'input must be an approved live-file-copy-v1 manifest'
}
$sourceRoot = ConvertTo-FaCanonicalPath ([string]$input.SourceRoot)
Assert-FaNotProtected -Path $sourceRoot -Workspace $workspace -Operation 'filtered copy source root'
$extensions = @($ExcludeExtension | ForEach-Object {
    $value = ([string]$_).ToLowerInvariant()
    if ($value.StartsWith('.')) { $value } else { '.' + $value }
})
$copies = [Collections.Generic.List[object]]::new()
$excluded = [Collections.Generic.List[object]]::new()
[long]$copyBytes = 0
[long]$excludedBytes = 0
foreach ($copy in @($input.Copies)) {
    $source = ConvertTo-FaCanonicalPath ([string]$copy.Source)
    $destination = ConvertTo-FaCanonicalPath ([string]$copy.Destination)
    Assert-FaNotProtected -Path $source -Workspace $workspace -Operation 'filtered copy source'
    Assert-FaNotProtected -Path $destination -Workspace $workspace -Operation 'filtered copy destination'
    if (-not (Test-FaPathWithin -Path $source -Root $sourceRoot)) {
        throw "copy source escapes frozen root: $source"
    }
    $reason = $null
    if ($ExcludePathRegex -and ($source -match $ExcludePathRegex -or $destination -match $ExcludePathRegex)) {
        $reason = 'path-regex-excluded'
    } elseif ($extensions -contains [IO.Path]::GetExtension($source).ToLowerInvariant()) {
        $reason = 'extension-excluded'
    } elseif ($MaximumFileBytes -gt 0 -and [long]$copy.Length -gt $MaximumFileBytes) {
        $reason = 'maximum-file-bytes-exceeded'
    }
    if ($reason) {
        $excluded.Add([pscustomobject]@{
            Source = $source
            Destination = $destination
            Length = [long]$copy.Length
            Sha256 = [string]$copy.Sha256
            Reason = $reason
        })
        $excludedBytes += [long]$copy.Length
        continue
    }
    $copies.Add($copy)
    $copyBytes += [long]$copy.Length
}
if ($copies.Count + $excluded.Count -ne @($input.Copies).Count) {
    throw 'filtered copy counts do not reconcile to the parent manifest'
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-copy-v1'
    SourceRoot = $sourceRoot
    SourceId = [string]$input.SourceId
    ParentManifest = $inputPath
    ParentManifestSha256 = Get-FaSha256 -Path $inputPath
    Copies = @($copies)
    CopyCount = [long]$copies.Count
    CopyBytes = $copyBytes
    Excluded = @($excluded)
    ExcludedCount = [long]$excluded.Count
    ExcludedBytes = $excludedBytes
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $OutputManifestPath -Value $manifest -Depth 24
Write-Host ("filtered copy manifest: copies={0} excluded={1} excluded-bytes={2}" -f
    $copies.Count, $excluded.Count, $excludedBytes)
