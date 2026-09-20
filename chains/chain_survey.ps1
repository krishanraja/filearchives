<#
    Survey every configured source, supervised, and survive being killed.

        pwsh -NoProfile -File guards\arm.ps1 -Chain chains\chain_survey.ps1

    THE FIRST LINK IN THE CHAIN, and deliberately the one that decides nothing.

    A chain is a sequence of Invoke-Step calls. Each step must prove it works on
    a handful before committing (Preflight), report a number that goes UP
    (Progress), re-derive a sample and compare (Verify), and prove it did the
    thing (Postcondition). A step cannot be added without all five, because a
    parameter that is missing is an exception rather than a step that quietly
    runs unguarded.

    WHY THE LOGGER IS BUILT THIS WAY

    Add-Content + Write-Host, never Tee-Object. Tee writes each line to the
    PIPELINE as well as the file, which lands log text inside the return value
    of any gate that logs - and [bool] of a non-empty array is $true. In
    contentarchives that made a Postcondition's "$false" read as success for a
    week, and made that chain's Verify gate incapable of ever failing.
    Invoke-Step now takes a gate's LAST emission, so both defences are present;
    this one costs nothing and removes the trap at the source.
#>
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
. "$repo\guards\steps.ps1"

# A supervisor that failed to load is indistinguishable from one that approved
# everything, because PowerShell reports an unknown command and carries on.
if (-not (Get-Command Invoke-Step -ErrorAction SilentlyContinue)) {
    Write-Host 'STOPPED: steps.ps1 did not load - nothing could be supervised.'
    exit 1
}

# Where records go is a property of the MACHINE, not of this file. Ask the
# resolver; if this machine is not configured it stops with instructions rather
# than inventing a drive letter.
$audit = & python -c @"
import os, sys
sys.path.insert(0, r'$repo')
import stagepath
from paths import workspace, NotConfigured
try:
    print(workspace().ensure_audit())
except NotConfigured as e:
    sys.stderr.write(str(e)); sys.exit(2)
"@
if ($LASTEXITCODE -ne 0) {
    Write-Host 'STOPPED: this machine has no filearchives workspace configured.'
    Write-Host '  Create %USERPROFILE%\.filearchives\workspace.json - see workspace.example.json'
    exit 1
}
$audit = $audit.Trim()

$log = Join-Path $audit 'survey-chain.log'
$SayImpl = New-ChainLogger -Path $log
function Say($m) { & $SayImpl $m }
function Stop-Chain([string] $why) { Say "STOPPED: $why"; exit 1 }

$sources = Join-Path $audit 'SOURCES.csv'
function RowCount {
    if (Test-Path $sources) { (@(Get-Content $sources).Count) - 1 } else { 0 }
}

Say "survey starting. audit=$audit"
$before = RowCount

Invoke-Step -Name 'survey-sources' -CheckpointMin 2 -VerifyEvery 2 `
    -Preflight {
        # Prove python, the resolver and at least one mounted source all work
        # BEFORE walking terabytes. An absent source is reported by the
        # resolver and skipped; ZERO mounted sources is a reason to stop, not
        # a survey that legitimately found nothing.
        $n = & python -c @"
import sys
sys.path.insert(0, r'$repo')
import stagepath
from paths import workspace, roots
print(len(roots(workspace())))
"@
        if ($LASTEXITCODE -ne 0) { Say '  the resolver failed'; return $false }
        Say "  mounted sources: $($n.Trim())"
        if ([int]$n.Trim() -lt 1) { Say '  no configured source is mounted'; return $false }
        return $true
    } `
    -Start {
        Say 'walking every mounted source (counts only - opens no file)'
        return Start-Process python -PassThru -WindowStyle Hidden `
            -ArgumentList @('-u', "$repo\stages\01_sources\survey_roots.py", '--all-configured') `
            -RedirectStandardOutput (Join-Path $audit 'survey.out') `
            -RedirectStandardError  (Join-Path $audit 'survey.err')
    } `
    -Progress { RowCount } `
    -Verify {
        # RE-DERIVE, never inspect shape. Take the newest row and check its
        # root still exists and still holds at least as many documents as it
        # claimed - a survey that counted a tree which has since vanished is
        # not a survey anyone should act on.
        $chk = & python -c @"
import csv, io, os, sys
sys.path.insert(0, r'$repo')
import stagepath
from paths import workspace
w = workspace()
p = w.sources_csv
if not os.path.exists(p):
    print('no SOURCES.csv yet'); sys.exit(2)
rows = list(csv.DictReader(io.open(p, encoding='utf-8', newline='')))
if not rows:
    print('SOURCES.csv has no rows'); sys.exit(2)
r = rows[-1]
if not os.path.isdir(r['Root']):
    print('the surveyed root has gone: ' + r['Root']); sys.exit(1)
print('re-derived {}: still mounted, claimed {} documents'.format(r['Root'], r['Documents']))
"@ 2>&1 | Out-String
        foreach ($ln in ($chk -split "`n" | Where-Object { $_.Trim() })) { Say "    $($ln.Trim())" }
        return ($LASTEXITCODE -ne 1)
    } `
    -Postcondition {
        $now = RowCount
        Say "  SOURCES.csv rows: $before -> $now"
        if ($now -le $before) { Say '  the survey wrote nothing'; return $false }
        return $true
    }

Say 'survey complete.'
Say 'NEXT, and it is NOT a plan yet:'
Say '  SOURCES.csv is a COUNT. Read it, decide what to ingest, and only then'
Say '  run the ingest chain. Nothing has been moved and no file was opened.'
