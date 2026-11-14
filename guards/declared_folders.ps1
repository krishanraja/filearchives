# Folders a growth engine has declared as its own (fleet integration I-25).
#
# Ruling (Krish, 2026-11-14): a folder inside a folder an engine declares in its
# Drive map is known without asking (his words: "happy with your recommendations
# for 3 and 4").
#
# Each engine declares its roots in the map it already keeps, in one drive-map/1
# shape: drive_map: { schema: 'drive-map/1', roots: [{ path, id? }] }, the path
# from My Drive with '/' between names. A name may itself hold a slash (mind/make
# shows as "mind make" on the PC), so a declared path is turned into every local
# spelling and only one that matches a folder already in Krish's record counts:
# a path is never guessed into existence. A map that cannot be read declares
# nothing, so its folders are asked about as before. Nothing is moved.

function Get-FaDeclaredRoots {
    # Returns @( @{ engine; drive_path } ) from the engines' maps. $Texts, when given,
    # is a hashtable engine -> map text (tests); otherwise each map is read live.
    param([string] $MapsPath, [hashtable] $Texts)
    $out = [Collections.Generic.List[object]]::new()
    $maps = @()
    if ($Texts) {
        $maps = @($Texts.Keys | ForEach-Object { @{ engine = $_; text = $Texts[$_] } })
    } elseif ($MapsPath -and (Test-Path -LiteralPath $MapsPath -PathType Leaf)) {
        $list = Get-Content -LiteralPath $MapsPath -Raw | ConvertFrom-Json -Depth 8
        foreach ($m in @($list.maps)) {
            $text = $null
            try { $text = (Invoke-WebRequest -Uri ([string]$m.url) -UseBasicParsing -TimeoutSec 20).Content } catch { $text = $null }
            $maps += @{ engine = [string]$m.engine; text = $text }
        }
    }
    foreach ($m in $maps) {
        if (-not $m.text) { continue }
        try { $j = $m.text | ConvertFrom-Json -Depth 16 } catch { continue }
        $dm = $j.PSObject.Properties['drive_map']
        if (-not $dm -or [string]$dm.Value.schema -ne 'drive-map/1') { continue }
        foreach ($r in @($dm.Value.roots)) {
            $p = [string]$r.path
            if ($p -and $p.StartsWith('Ventures/')) { $out.Add(@{ engine = [string]$m.engine; drive_path = $p }) }
        }
    }
    return ,$out.ToArray()
}

function Get-FaLocalSpellings {
    # Every local spelling of a Drive path under one watched root: each '/' is either
    # a folder break or part of a name, which the PC shows as a space.
    param([string] $DrivePath, [string] $Root)
    $parts = $DrivePath -split '/'
    $spellings = @($parts[0])
    for ($i = 1; $i -lt $parts.Count; $i++) {
        $next = @()
        foreach ($s in $spellings) { $next += "$s\$($parts[$i])"; $next += "$s $($parts[$i])" }
        $spellings = $next
    }
    return @($spellings | ForEach-Object { Join-Path $Root $_ })
}

function Resolve-FaDeclaredFolders {
    # The declared roots that match a folder already in Krish's record, as canonical local paths with their engine.
    param($Roots, $Preferences)
    $out = [Collections.Generic.List[object]]::new()
    foreach ($r in @($Roots)) {
        foreach ($w in @($Preferences.WatchRoots)) {
            foreach ($cand in (Get-FaLocalSpellings -DrivePath $r.drive_path -Root $w.Path)) {
                $c = ConvertTo-FaCanonicalPath $cand
                if ($Preferences.ByPath.ContainsKey($c)) { $out.Add(@{ engine = $r.engine; path = $c; drive_path = $r.drive_path }) }
            }
        }
    }
    return ,$out.ToArray()
}
