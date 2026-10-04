[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)][string[]] $Source,
    [Parameter(Mandatory)][string[]] $Destination,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [string] $Category = 'explicit-routing',
    [string] $RuleId = 'explicit-reviewed-route',
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
if ($Source.Count -ne $Destination.Count) { throw 'Source and Destination counts must match' }
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$root = ConvertTo-FaCanonicalPath $SourceRoot
Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'explicit copy root'
$copies = [Collections.Generic.List[object]]::new()
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
for ($index=0; $index -lt $Source.Count; $index++) {
    $sourcePath = ConvertTo-FaCanonicalPath $Source[$index]
    $destinationPath = ConvertTo-FaCanonicalPath $Destination[$index]
    Assert-FaNotProtected -Path $sourcePath -Workspace $workspace -Operation 'explicit copy source'
    Assert-FaNotProtected -Path $destinationPath -Workspace $workspace -Operation 'explicit copy destination'
    if (-not (Test-FaPathWithin -Path $sourcePath -Root $root)) { throw "source escapes explicit root: $sourcePath" }
    $item = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
    if ($item.PSIsContainer) { throw "explicit copy source must be a file: $sourcePath" }
    $hash = Get-FaSha256 -Path $sourcePath
    if ((Test-Path -LiteralPath $destinationPath) -and (Get-FaSha256 -Path $destinationPath) -ne $hash) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($destinationPath)
        $destinationPath = Join-Path (Split-Path -Parent $destinationPath) ("{0}__{1}{2}" -f $stem,$hash.Substring(0,12),$item.Extension)
    }
    if (-not $reserved.Add($destinationPath)) { throw "duplicate explicit destination: $destinationPath" }
    $copies.Add([pscustomobject]@{
        Source = $sourcePath
        Destination = $destinationPath
        Length = [long]$item.Length
        LastWriteTimeUtc = ([DateTimeOffset]$item.LastWriteTimeUtc).ToString('o')
        Sha256 = $hash
        Category = $Category
        RuleId = $RuleId
    })
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-copy-v1'
    SourceRoot = $root
    SourceId = 'explicit-reviewed-route'
    Copies = @($copies)
    CopyCount = [long]$copies.Count
    SkippedUnproven = @()
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("explicit file copy manifest: copies={0}" -f $copies.Count)
