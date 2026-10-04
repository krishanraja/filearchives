[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ConfigPath,
    [Parameter(Mandatory)][string[]] $ProfileRoot,
    [Parameter(Mandatory)][string] $ReportPath,
    [string[]] $KnownRelativePath = @(
        'Desktop','Documents','Downloads','Music','Pictures','Videos',
        'OneDrive','Dropbox','dev'
    ),
    [switch] $FailOnUncovered
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourceRoots = @($workspace.sources | ForEach-Object {
    [pscustomobject]@{
        Id = [string]$_.id
        Path = ConvertTo-FaCanonicalPath ([string]$_.path)
    }
})
$profiles = [Collections.Generic.List[object]]::new()
$uncovered = [Collections.Generic.List[object]]::new()

foreach ($requestedProfile in $ProfileRoot) {
    $profile = ConvertTo-FaCanonicalPath $requestedProfile
    if (-not (Test-Path -LiteralPath $profile -PathType Container)) {
        $profiles.Add([pscustomobject]@{ Profile=$profile; Status='unavailable'; KnownFolders=@() })
        continue
    }
    $known = [Collections.Generic.List[object]]::new()
    foreach ($relative in $KnownRelativePath) {
        $target = ConvertTo-FaCanonicalPath (Join-Path $profile $relative)
        if (-not (Test-Path -LiteralPath $target -PathType Container)) { continue }
        $covering = @($sourceRoots | Where-Object { Test-FaPathWithin -Path $target -Root $_.Path })
        $row = [pscustomobject]@{
            RelativePath = $relative
            Path = $target
            Covered = [bool]($covering.Count -gt 0)
            SourceIds = @($covering | ForEach-Object Id)
        }
        $known.Add($row)
        if (-not $row.Covered) {
            $uncovered.Add([pscustomobject]@{ Profile=$profile; RelativePath=$relative; Path=$target })
        }
    }
    $profiles.Add([pscustomobject]@{
        Profile = $profile
        Status = if (@($known | Where-Object { -not $_.Covered }).Count) { 'uncovered' } else { 'covered' }
        KnownFolders = @($known)
    })
}

$report = [ordered]@{
    SchemaVersion = 1
    Kind = 'windows-profile-coverage-v1'
    Status = if ($uncovered.Count) { 'fail' } else { 'pass' }
    ConfigPath = ConvertTo-FaCanonicalPath $ConfigPath
    Profiles = @($profiles)
    Uncovered = @($uncovered)
    CheckedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReportPath -Value $report -Depth 16
Write-Host ("Windows profile coverage: status={0} uncovered={1}" -f $report.Status,$uncovered.Count)
if ($FailOnUncovered -and $uncovered.Count) {
    throw "workspace omits $($uncovered.Count) existing Windows known folder(s)"
}

