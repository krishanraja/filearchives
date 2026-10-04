Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-FaCanonicalPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'path must not be blank'
    }

    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd([char[]]@('\', '/'))
    }
    return $full
}

function Test-FaPathWithin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Root
    )

    $candidate = ConvertTo-FaCanonicalPath $Path
    $boundary = ConvertTo-FaCanonicalPath $Root
    if ($candidate.Equals($boundary, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $prefix = if ($boundary.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $boundary
    } else {
        $boundary + [IO.Path]::DirectorySeparatorChar
    }
    return $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-FaProtectedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)] $Workspace
    )

    $candidate = ConvertTo-FaCanonicalPath $Path
    foreach ($root in @($Workspace.ProtectedRoots)) {
        if (Test-FaPathWithin -Path $candidate -Root $root) {
            return $true
        }
    }

    $segments = [regex]::Split($candidate, '[\\/]+')
    foreach ($protectedName in @($Workspace.ProtectedNames)) {
        if ($segments -contains $protectedName) {
            return $true
        }
    }
    return $false
}

function Assert-FaNotProtected {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)] $Workspace,
        [string] $Operation = 'access'
    )

    if (Test-FaProtectedPath -Path $Path -Workspace $Workspace) {
        throw "REFUSED: $Operation targets protected path $Path"
    }
}

function Get-FaDefaultWorkspacePath {
    if (-not $env:USERPROFILE) {
        throw 'USERPROFILE is unavailable; pass -ConfigPath explicitly'
    }
    return Join-Path $env:USERPROFILE '.filearchives\workspace.json'
}

function Import-FaWorkspace {
    [CmdletBinding()]
    param([string] $ConfigPath)

    if (-not $ConfigPath) {
        $ConfigPath = if ($env:FILEARCHIVES_WORKSPACE) {
            $env:FILEARCHIVES_WORKSPACE
        } else {
            Get-FaDefaultWorkspacePath
        }
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "workspace config is absent: $ConfigPath"
    }

    $data = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop |
        ConvertFrom-Json -Depth 32 -ErrorAction Stop
    if ($data.schema_version -ne 2) {
        throw "workspace schema_version must be 2: $ConfigPath"
    }
    foreach ($required in @('audit', 'sources', 'protected_roots')) {
        if ($data.PSObject.Properties.Name -notcontains $required) {
            throw "workspace is missing required key '$required': $ConfigPath"
        }
    }

    $protectedRoots = @($data.protected_roots | ForEach-Object {
        ConvertTo-FaCanonicalPath ([string]$_)
    })
    if ($protectedRoots.Count -eq 0) {
        throw 'workspace must declare at least one protected root'
    }
    $protectedNames = if ($data.PSObject.Properties.Name -contains 'protected_names') {
        @($data.protected_names | ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ })
    } else { @() }

    $ids = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $sources = @()
    foreach ($source in @($data.sources)) {
        if (-not $source.id -or -not $source.path) {
            throw 'each source requires id and path'
        }
        if (-not $ids.Add([string]$source.id)) {
            throw "duplicate source id: $($source.id)"
        }
        $kind = if ($source.PSObject.Properties.Name -contains 'kind' -and $source.kind) {
            [string]$source.kind
        } else { 'filesystem' }
        $follow = if ($source.PSObject.Properties.Name -contains 'follow_reparse_points') {
            [bool]$source.follow_reparse_points
        } else { $false }
        $sources += [pscustomobject]@{
            Id = [string]$source.id
            Path = ConvertTo-FaCanonicalPath ([string]$source.path)
            Kind = $kind
            FollowReparsePoints = $follow
        }
    }
    if ($sources.Count -eq 0) {
        throw 'workspace must declare at least one source'
    }

    $current = if ($data.PSObject.Properties.Name -contains 'current' -and $data.current) {
        ConvertTo-FaCanonicalPath ([string]$data.current)
    } else { $null }
    $archive = if ($data.PSObject.Properties.Name -contains 'archive' -and $data.archive) {
        ConvertTo-FaCanonicalPath ([string]$data.archive)
    } else { $null }
    $workspace = [pscustomobject]@{
        SchemaVersion = 2
        Origin = ConvertTo-FaCanonicalPath $ConfigPath
        Audit = ConvertTo-FaCanonicalPath ([string]$data.audit)
        Current = $current
        Archive = $archive
        Sources = $sources
        ProtectedRoots = $protectedRoots
        ProtectedNames = $protectedNames
    }

    Assert-FaNotProtected -Path $workspace.Audit -Workspace $workspace -Operation 'audit write'
    foreach ($source in $workspace.Sources) {
        if (Test-FaPathWithin -Path $workspace.Audit -Root $source.Path) {
            throw "audit path is inside source '$($source.Id)': $($workspace.Audit)"
        }
    }
    foreach ($destination in @($workspace.Current, $workspace.Archive) |
        Where-Object { $_ }) {
        Assert-FaNotProtected -Path $destination -Workspace $workspace -Operation 'destination write'
    }
    if ($workspace.Current -and $workspace.Archive) {
        if ((Test-FaPathWithin -Path $workspace.Current -Root $workspace.Archive) -or
            (Test-FaPathWithin -Path $workspace.Archive -Root $workspace.Current)) {
            throw 'current and archive destinations must not contain one another'
        }
    }

    return $workspace
}
