[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ReceiptPath,
    [string] $ProgressPath,
    [string] $SkipRelativePathRegex = '(?i)(^|\\)(desktop\.ini|thumbs\.db)$',
    [Parameter(Mandatory)][switch] $Execute,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')

if (-not $Execute) { throw 'execution requires the explicit -Execute switch' }
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "copy manifest is absent: $ManifestPath"
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
if ($manifest.SchemaVersion -ne 1 -or $manifest.Kind -ne 'verified-folder-copy-v1') {
    throw 'unsupported verified-copy manifest'
}
if ($manifest.Status -notin @('ready', 'ready-partial') -or
    ($manifest.Status -eq 'ready' -and @($manifest.Unproven).Count -ne 0) -or
    ($manifest.Status -eq 'ready-partial' -and $manifest.AllowUnproven -ne $true)) {
    throw 'copy manifest contains unreadable or unproven files'
}
if ($manifest.Approved -ne $true -or [string]::IsNullOrWhiteSpace([string]$manifest.ApprovalReason)) {
    throw 'copy manifest is not approved'
}
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourceRoot = ConvertTo-FaCanonicalPath ([string]$manifest.Source)
$destinationRoot = ConvertTo-FaCanonicalPath ([string]$manifest.Destination)
Assert-FaNotProtected -Path $sourceRoot -Workspace $workspace -Operation 'verified copy source access'
Assert-FaNotProtected -Path $destinationRoot -Workspace $workspace -Operation 'verified copy destination access'
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "copy source disappeared: $sourceRoot"
}
if (-not $ProgressPath) { $ProgressPath = $ReceiptPath + '.progress.jsonl' }
New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
foreach ($directory in @($manifest.Directories)) {
    $targetDirectory = ConvertTo-FaCanonicalPath (Join-Path $destinationRoot ([string]$directory))
    if (-not (Test-FaPathWithin -Path $targetDirectory -Root $destinationRoot)) {
        throw "manifest directory escapes destination: $directory"
    }
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
}

$completed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $ProgressPath -PathType Leaf) {
    foreach ($line in Get-Content -LiteralPath $ProgressPath) {
        if (-not $line) { continue }
        $row = $line | ConvertFrom-Json -Depth 8
        if ($row.Status -eq 'verified') { $null = $completed.Add([string]$row.RelativePath) }
    }
}
$progressDirectory = Split-Path -Parent $ProgressPath
New-Item -ItemType Directory -Path $progressDirectory -Force | Out-Null
$progressStream = [IO.FileStream]::new($ProgressPath, [IO.FileMode]::Append,
    [IO.FileAccess]::Write, [IO.FileShare]::Read)
$progressWriter = [IO.StreamWriter]::new($progressStream, [Text.UTF8Encoding]::new($false))
$started = [DateTimeOffset]::Now
[long]$verifiedFiles = 0
[long]$verifiedBytes = 0
$skippedRelativePaths = [Collections.Generic.List[string]]::new()
function Get-FaReadbackHash {
    param([string] $Path, [int] $Attempts = 80)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try { return Get-FaSha256 -Path $Path } catch {
            if ($attempt -eq $Attempts) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
}
try {
    foreach ($file in @($manifest.Files)) {
        $relative = [string]$file.RelativePath
        if ($SkipRelativePathRegex -and $relative -match $SkipRelativePathRegex) {
            $skippedRelativePaths.Add($relative)
            continue
        }
        $source = ConvertTo-FaCanonicalPath (Join-Path $sourceRoot $relative)
        $destination = ConvertTo-FaCanonicalPath (Join-Path $destinationRoot $relative)
        if (-not (Test-FaPathWithin -Path $source -Root $sourceRoot) -or
            -not (Test-FaPathWithin -Path $destination -Root $destinationRoot)) {
            throw "manifest file escapes its root: $relative"
        }
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "copy source file disappeared: $source"
        }
        $sourceItem = Get-Item -LiteralPath $source -Force
        if ([long]$sourceItem.Length -ne [long]$file.Length -or
            [DateTimeOffset]::Parse([string]$file.LastWriteTimeUtc).UtcTicks -ne
                ([DateTimeOffset]$sourceItem.LastWriteTimeUtc).UtcTicks) {
            throw "copy source metadata changed after manifest freeze: $source"
        }
        $sourceHash = Get-FaSha256 -Path $source
        if ($sourceHash -ne [string]$file.Sha256) {
            throw "copy source hash changed after manifest freeze: $source"
        }
        $destinationDirectory = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $destinationHash = Get-FaSha256 -Path $destination
            if ($destinationHash -ne $sourceHash) {
                throw "destination collision with different content: $destination"
            }
        } elseif (Test-Path -LiteralPath $destination) {
            throw "destination path is occupied by a non-file: $destination"
        } else {
            $temp = $destination + '.fa-copying'
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
            [IO.File]::Copy($source, $temp, $false)
            $tempHash = Get-FaSha256 -Path $temp
            if ($tempHash -ne $sourceHash) {
                Remove-Item -LiteralPath $temp -Force
                throw "copied bytes failed SHA-256 verification: $destination"
            }
            [IO.File]::SetLastWriteTimeUtc($temp, ([DateTimeOffset]::Parse([string]$file.LastWriteTimeUtc)).UtcDateTime)
            try {
                [IO.File]::Move($temp, $destination)
            } catch {
                if ((Get-FaReadbackHash -Path $destination) -ne $sourceHash) { throw }
                if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force }
            }
        }
        $finalHash = Get-FaReadbackHash -Path $destination
        if ($finalHash -ne $sourceHash) { throw "destination readback failed: $destination" }
        $verifiedFiles++
        $verifiedBytes += [long]$file.Length
        if (-not $completed.Contains($relative)) {
            $progressWriter.WriteLine(([ordered]@{
                RelativePath = $relative
                Length = [long]$file.Length
                Sha256 = $sourceHash
                Status = 'verified'
                VerifiedAt = [DateTimeOffset]::Now.ToString('o')
            } | ConvertTo-Json -Compress))
            $progressWriter.Flush()
            $progressStream.Flush($true)
            $null = $completed.Add($relative)
        }
    }
} finally {
    $progressWriter.Dispose()
    $progressStream.Dispose()
}
$expectedFiles = [long]$manifest.FileCount - [long]$skippedRelativePaths.Count
[long]$skippedBytes = 0
foreach ($candidate in @($manifest.Files)) {
    if ($SkipRelativePathRegex -and ([string]$candidate.RelativePath -match $SkipRelativePathRegex)) {
        $skippedBytes += [long]$candidate.Length
    }
}
$expectedBytes = [long]$manifest.Bytes - $skippedBytes
if ($verifiedFiles -ne $expectedFiles -or $verifiedBytes -ne $expectedBytes) {
    throw 'verified copy totals do not reconcile to the manifest'
}
$receipt = [ordered]@{
    SchemaVersion = 1
    Kind = 'verified-folder-copy-receipt-v1'
    Status = 'complete'
    Coverage = if ($skippedRelativePaths.Count -gt 0) { 'included-readable-files-minus-explicit-skip' } `
        elseif ($manifest.Status -eq 'ready-partial') { 'included-readable-files-only' } else { 'all-non-excluded-files' }
    ManifestSha256 = Get-FaSha256 -Path $ManifestPath
    Source = $sourceRoot
    Destination = $destinationRoot
    Files = $verifiedFiles
    Directories = [long]$manifest.DirectoryCount
    Bytes = $verifiedBytes
    SourceRetained = $true
    UnprovenRetained = [long](@($manifest.Unproven).Count)
    SkippedRelativePaths = @($skippedRelativePaths)
    VerificationClaim = [string]$manifest.VerificationClaim
    StartedAt = $started.ToString('o')
    CompletedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReceiptPath -Value $receipt -Depth 12
Write-Host ("verified copy complete: files={0} bytes={1}" -f $verifiedFiles, $verifiedBytes)
Write-Host "receipt: $ReceiptPath"
