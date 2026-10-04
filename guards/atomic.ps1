Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-FaAtomicUtf8 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Content
    )

    $directory = Split-Path -Parent $Path
    if (-not $directory) { throw "target has no parent directory: $Path" }
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temp = $Path + '.writing'
    $encoding = [Text.UTF8Encoding]::new($false)
    $stream = [IO.FileStream]::new(
        $temp,
        [IO.FileMode]::Create,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None)
    try {
        $writer = [IO.StreamWriter]::new($stream, $encoding)
        try {
            $writer.Write($Content)
            $writer.Flush()
            $stream.Flush($true)
        } finally {
            $writer.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
    [IO.File]::Move($temp, $Path, $true)
}

function Write-FaAtomicJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)] $Value,
        [int] $Depth = 16
    )
    $json = $Value | ConvertTo-Json -Depth $Depth
    Write-FaAtomicUtf8 -Path $Path -Content ($json + [Environment]::NewLine)
}

function Get-FaSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "cannot hash absent file: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
