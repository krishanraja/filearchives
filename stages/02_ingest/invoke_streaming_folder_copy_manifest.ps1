[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][string] $ReceiptPath,
    [Parameter(Mandatory)][switch] $Execute,
    [ValidateRange(65536, 16777216)][int] $BufferBytes = 8388608,
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'guards\workspace.ps1')
. (Join-Path $repo 'guards\atomic.ps1')
if (-not $Execute) { throw 'execution requires the explicit -Execute switch' }

function Get-FaReadbackHash {
    param([Parameter(Mandatory)][string] $Path, [int] $Attempts = 80)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try { return Get-FaSha256 -Path $Path } catch {
            if ($attempt -eq $Attempts) { throw }
            Start-Sleep -Milliseconds 250
        }
    }
}

function Copy-FaStreamingHashed {
    param([Parameter(Mandatory)][string] $Source, [Parameter(Mandatory)][string] $Destination, [int] $BufferSize)
    $sourceStream = [IO.FileStream]::new($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read,
        $BufferSize,[IO.FileOptions]::SequentialScan)
    try {
        $destinationStream = [IO.FileStream]::new($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,
            [IO.FileShare]::None,$BufferSize,[IO.FileOptions]::SequentialScan)
        try {
            $hash = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
            try {
                $buffer = [byte[]]::new($BufferSize)
                while (($read = $sourceStream.Read($buffer,0,$buffer.Length)) -gt 0) {
                    $destinationStream.Write($buffer,0,$read)
                    $hash.AppendData($buffer,0,$read)
                }
                $destinationStream.Flush($true)
                return [Convert]::ToHexString($hash.GetHashAndReset()).ToLowerInvariant()
            } finally { $hash.Dispose() }
        } finally { $destinationStream.Dispose() }
    } finally { $sourceStream.Dispose() }
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 32 -DateKind String
if ($manifest.SchemaVersion -ne 1 -or $manifest.Kind -ne 'streaming-folder-copy-v1' -or $manifest.Approved -ne $true) {
    throw 'unsupported or unapproved streaming folder copy manifest'
}
$workspace = Import-FaWorkspace -ConfigPath $ConfigPath
$sourceRoot = ConvertTo-FaCanonicalPath ([string]$manifest.SourceRoot)
$destinationRoot = ConvertTo-FaCanonicalPath ([string]$manifest.DestinationRoot)
Assert-FaNotProtected -Path $sourceRoot -Workspace $workspace -Operation 'streaming copy source'
Assert-FaNotProtected -Path $destinationRoot -Workspace $workspace -Operation 'streaming copy destination'

$completed = [Collections.Generic.List[object]]::new()
$progressPath = $ReceiptPath + '.progress.jsonl'
New-Item -ItemType Directory -Path (Split-Path -Parent $progressPath) -Force | Out-Null
[IO.File]::WriteAllText($progressPath, '', [Text.UTF8Encoding]::new($false))
function Add-FaCompleted {
    param([Parameter(Mandatory)] $Row)
    $completed.Add($Row)
    [IO.File]::AppendAllText($progressPath,(($Row | ConvertTo-Json -Compress -Depth 8)+[Environment]::NewLine),
        [Text.UTF8Encoding]::new($false))
}

foreach ($file in @($manifest.Files)) {
    $source = ConvertTo-FaCanonicalPath ([string]$file.Source)
    $destination = ConvertTo-FaCanonicalPath ([string]$file.Destination)
    if (-not (Test-FaPathWithin -Path $source -Root $sourceRoot) -or
        -not (Test-FaPathWithin -Path $destination -Root $destinationRoot)) {
        throw "streaming copy row escapes its frozen roots: $source"
    }
    Assert-FaNotProtected -Path $source -Workspace $workspace -Operation 'streaming copy source file'
    Assert-FaNotProtected -Path $destination -Workspace $workspace -Operation 'streaming copy destination file'
    $sourceItem = Get-Item -LiteralPath $source -Force -ErrorAction Stop
    $frozenTicks = [DateTimeOffset]::Parse([string]$file.LastWriteTimeUtc).UtcTicks
    if ([long]$sourceItem.Length -ne [long]$file.Length -or
        ([DateTimeOffset]$sourceItem.LastWriteTimeUtc).UtcTicks -ne $frozenTicks) {
        throw "streaming copy source metadata changed after manifest freeze: $source"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    $temp = $destination + '.fa-streaming'
    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $sourceHash = Get-FaSha256 -Path $source
        $destinationHash = Get-FaReadbackHash -Path $destination
        if ($sourceHash -ne $destinationHash) { throw "existing destination differs from source: $destination" }
        Add-FaCompleted ([pscustomobject]@{Source=$source;Destination=$destination;Length=[long]$file.Length;Sha256=$sourceHash;Status='already-verified'})
        continue
    }
    if (Test-Path -LiteralPath $temp -PathType Leaf) {
        $sourceHash = Get-FaSha256 -Path $source
        $tempHash = Get-FaReadbackHash -Path $temp
        if ($sourceHash -ne $tempHash) { throw "stale streaming temporary file differs from source: $temp" }
    } else {
        $sourceHash = Copy-FaStreamingHashed -Source $source -Destination $temp -BufferSize $BufferBytes
        $after = Get-Item -LiteralPath $source -Force -ErrorAction Stop
        if ([long]$after.Length -ne [long]$file.Length -or
            ([DateTimeOffset]$after.LastWriteTimeUtc).UtcTicks -ne $frozenTicks) {
            [IO.File]::Delete($temp)
            throw "streaming copy source metadata changed during transfer: $source"
        }
        $tempHash = Get-FaReadbackHash -Path $temp
        if ($sourceHash -ne $tempHash) {
            [IO.File]::Delete($temp)
            throw "streaming destination-volume readback failed: $destination"
        }
    }
    [IO.File]::SetLastWriteTimeUtc($temp,([DateTimeOffset]::Parse([string]$file.LastWriteTimeUtc)).UtcDateTime)
    [IO.File]::Move($temp,$destination)
    Add-FaCompleted ([pscustomobject]@{Source=$source;Destination=$destination;Length=[long]$file.Length;Sha256=$sourceHash;Status='verified-stream-and-readback'})
}

$completedBytes = if ($completed.Count) {
    [long](($completed | Measure-Object Length -Sum).Sum)
} else { [long]0 }
$receipt = [ordered]@{
    SchemaVersion = 1
    Kind = 'streaming-folder-copy-receipt-v1'
    Status = 'complete'
    ManifestSha256 = Get-FaSha256 -Path $ManifestPath
    FileCount = [long]$completed.Count
    Bytes = $completedBytes
    Files = @($completed)
    SourceRetained = $true
    VerificationClaim = 'source stream SHA-256 equals destination-volume temporary-file readback SHA-256; verified temporary file renamed in place to final destination'
    CompletedAt = [DateTimeOffset]::Now.ToString('o')
}
Write-FaAtomicJson -Path $ReceiptPath -Value $receipt -Depth 16
Write-Host ("streaming folder copy verified: files={0} bytes={1}" -f $receipt.FileCount,$receipt.Bytes)
