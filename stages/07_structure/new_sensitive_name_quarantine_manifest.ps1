[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $SourceRoot,
    [Parameter(Mandatory)][string] $QuarantineRoot,
    [Parameter(Mandatory)][string] $NameRegex,
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ApprovalReason,
    [switch] $Recurse,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$root = ConvertTo-FaCanonicalPath $SourceRoot
$quarantine = ConvertTo-FaCanonicalPath $QuarantineRoot
Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'sensitive-name quarantine source'
Assert-FaNotProtected -Path $quarantine -Workspace $workspace -Operation 'sensitive-name quarantine destination'
if (-not ([IO.Path]::GetPathRoot($root)).Equals([IO.Path]::GetPathRoot($quarantine), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'sensitive-name quarantine must remain on the source volume'
}
$moves = [Collections.Generic.List[object]]::new()
$rootPrefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$getArgs = @{ LiteralPath=$root; File=$true; Force=$true }
if ($Recurse) { $getArgs.Recurse = $true }
foreach ($file in @(Get-ChildItem @getArgs | Sort-Object FullName)) {
    if ($file.Name -notmatch $NameRegex) { continue }
    $relative = if ($Recurse) { $file.FullName.Substring($rootPrefix.Length) } else { $file.Name }
    $destination = Join-Path $quarantine $relative
    if (Test-Path -LiteralPath $destination) { throw "sensitive quarantine destination already exists: $destination" }
    $moves.Add([pscustomobject]@{
        Source = ConvertTo-FaCanonicalPath $file.FullName
        Destination = ConvertTo-FaCanonicalPath $destination
        Length = [long]$file.Length
        LastWriteTimeUtc = ([DateTimeOffset]$file.LastWriteTimeUtc).ToString('o')
        Sha256 = $null
        VerificationMode = 'metadata-only-sensitive-no-content-read'
        Category = 'credentials-secrets'
        Disposition = 'secure-local-quarantine'
        RuleId = 'sensitive-name-no-content-read'
    })
}
$manifest = [ordered]@{
    SchemaVersion = 1
    Kind = 'live-file-move-v1'
    SourceRoot = $root
    SourceId = 'sensitive-name-quarantine'
    Moves = @($moves)
    MoveCount = [long]$moves.Count
    Skipped = @()
    ContentRead = $false
    Approved = $true
    ApprovalReason = $ApprovalReason
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ManifestPath -Value $manifest -Depth 16
Write-Host ("sensitive-name quarantine manifest: moves={0}; content-read=false" -f $moves.Count)
