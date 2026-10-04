[CmdletBinding()]
param(
    [string] $ConfigPath,
    [string] $PolicyPath,
    [Parameter(Mandatory)][string] $ReceiptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
if (-not $ConfigPath) { $ConfigPath = Get-FaDefaultWorkspacePath }
if (-not $PolicyPath) { $PolicyPath = Join-Path $repo 'policy\estate-policy-v1.json' }

$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json -Depth 64
$created = [Collections.Generic.List[string]]::new()
$existing = [Collections.Generic.List[string]]::new()
foreach ($destinationKey in @('business_current', 'business_archive', 'content_extra', 'personal')) {
    $root = ConvertTo-FaCanonicalPath ([string]$policy.destinations.$destinationKey)
    Assert-FaNotProtected -Path $root -Workspace $workspace -Operation 'canonical structure creation'
    foreach ($folder in @($policy.structure.$destinationKey)) {
        $target = ConvertTo-FaCanonicalPath (Join-Path $root ([string]$folder))
        Assert-FaNotProtected -Path $target -Workspace $workspace -Operation 'canonical structure creation'
        if (Test-Path -LiteralPath $target -PathType Container) {
            $existing.Add($target)
        } elseif (Test-Path -LiteralPath $target) {
            throw "canonical folder target is occupied by a non-directory: $target"
        } else {
            New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop | Out-Null
            if (-not (Test-Path -LiteralPath $target -PathType Container)) {
                throw "canonical folder creation did not read back: $target"
            }
            $created.Add($target)
        }
    }
}
$receipt = [ordered]@{
    SchemaVersion = 1
    Kind = 'canonical-structure-receipt-v1'
    PolicyId = [string]$policy.policy_id
    PolicySha256 = Get-FaSha256 -Path $PolicyPath
    Created = @($created)
    AlreadyExisted = @($existing)
    ProtectedRoots = @($workspace.ProtectedRoots)
    CompletedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReceiptPath -Value $receipt -Depth 12
Write-Host ("canonical structure ready: created={0} existing={1}" -f $created.Count, $existing.Count)
Write-Host "receipt: $ReceiptPath"

