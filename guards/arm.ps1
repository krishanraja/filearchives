<#
    Run a chain so that it OUTLIVES the session that started it.

        pwsh -NoProfile -File guards\arm.ps1 -Chain chains\chain_survey.ps1
        pwsh -NoProfile -File guards\arm.ps1 -Chain chains\chain_survey.ps1 -TaskName filearchives-survey
        pwsh -NoProfile -File guards\arm.ps1 -Status
        pwsh -NoProfile -File guards\arm.ps1 -Stop -TaskName filearchives-survey

    WHY NOT Start-Process -WindowStyle Hidden

    Because it does not detach. In contentarchives a classifier and both chains
    waiting on it were launched that way and all three died in the same second
    the agent session ended - 26,000 files short, after four hours of paid work.
    Hidden only hides a window. The process stays in the caller's tree and dies
    with it.

    A scheduled task is owned by the Task Scheduler service, so it survives the
    session ending, the terminal closing, and logging out. It does not survive a
    reboot by design: -Stop, or a reboot, are the two ways this stops.

    Detachment alone was not enough: a properly detached chain was still killed
    two hours in, so the task registers with RestartCount and every chain is
    written to resume. Everything under chains\ is safe to re-run, so a death
    costs only the work in flight.

    WHAT IS DIFFERENT FROM contentarchives' VERSION

    -TaskName is a real parameter with a per-chain default, instead of one
    fixed name for the whole repo. That single fixed slot is why a fortnightly
    ingest could not be armed while a mirror was running: two unrelated jobs
    were forced to take turns for no reason other than sharing a string. Here,
    chains that touch different trees can run side by side, and chains that
    touch the SAME tree must still be given the same name on purpose.

    -Status is worth trusting over intuition. schtasks prints "Ready" for a task
    that is not currently running, which reads like "fine"; the state that means
    running is "Running".
#>
[CmdletBinding()]
param(
    [string] $Chain,
    [string] $ChainArgs = '',
    [string] $TaskName = '',
    [switch] $Status,
    [switch] $Stop
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

# Every python entry point a chain may launch. Stopping the TASK kills its pwsh,
# but the python it started keeps running as an orphan - and an orphan goes on
# writing to the same records the next run will claim, so the same work is done
# twice and the journals interleave. Seen for real in contentarchives: a re-arm
# left a classifier running with a dead parent while its replacement started.
#
# THIS LIST MUST NAME EVERY SCRIPT A CHAIN LAUNCHES. It was once incomplete
# there, and re-arming left three shards orphaned while three new ones started
# on the same files, writing the same temporary paths.
$workers = @(
    'survey_roots',
    'build_inventory',
    'date_from_signals',
    'classify_documents',
    'build_index',
    'propose_layout',
    'dedupe_archive',
    'mirror_tree'
)
$workerPattern = ($workers | ForEach-Object { [regex]::Escape($_) }) -join '|'

function Stop-ChainWorkers {
    $ours = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match $workerPattern }
    foreach ($w in $ours) {
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($w.ParentProcessId)" -ErrorAction SilentlyContinue
        if (-not $parent) {
            $what = $workers | Where-Object { $w.CommandLine -match $_ } | Select-Object -First 1
            Write-Host ("  orphan {0} ({1}) - stopping" -f $w.ProcessId, $what)
            Stop-Process -Id $w.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-TaskName([string] $chain, [string] $given) {
    if ($given) { return $given }
    if ($chain) {
        $leaf = [IO.Path]::GetFileNameWithoutExtension($chain) -replace '^chain_', ''
        return "filearchives-$leaf"
    }
    return 'filearchives-chain'
}

if ($Status) {
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
             Where-Object { $_.TaskName -like 'filearchives-*' }
    if (-not $tasks) { Write-Host 'no filearchives tasks registered'; exit 0 }
    foreach ($t in $tasks) {
        $i = Get-ScheduledTaskInfo -TaskName $t.TaskName -ErrorAction SilentlyContinue
        # "Ready" means NOT RUNNING. Only "Running" means running.
        Write-Host ("{0,-34} {1,-9} last result {2}  last run {3}" -f `
                    $t.TaskName, $t.State, $i.LastTaskResult, $i.LastRunTime)
    }
    $py = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match $workerPattern })
    Write-Host ("  worker processes alive: {0}" -f $py.Count)
    exit 0
}

if ($Stop) {
    $name = Resolve-TaskName $Chain $TaskName
    Stop-ChainWorkers
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "stopped and unregistered '$name'"
    Write-Host 'NOTE: python children are not killed by unregistering. Checked above.'
    exit 0
}

if (-not $Chain) { throw 'give -Chain, -Status or -Stop' }

$chainPath = if ([IO.Path]::IsPathRooted($Chain)) { $Chain } else { Join-Path $repo $Chain }
if (-not (Test-Path $chainPath)) { throw "no such chain: $chainPath" }

# PARSE IT BEFORE ARMING IT. A chain that will not parse skips every step it was
# supposed to run and exits 0, which reads as a clean success. Found in
# contentarchives only because someone happened to look at the log.
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile($chainPath, [ref]$null, [ref]$errs) | Out-Null
if ($errs.Count) {
    Write-Host "REFUSING to arm: $chainPath does not parse"
    $errs | ForEach-Object { Write-Host ("  " + $_.Message) }
    exit 1
}

$name = Resolve-TaskName $Chain $TaskName
Stop-ChainWorkers
Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue

$pwsh = (Get-Command pwsh).Source
$argline = "-NoProfile -ExecutionPolicy Bypass -File `"$chainPath`""
if ($ChainArgs) { $argline += " $ChainArgs" }

$action   = New-ScheduledTaskAction -Execute $pwsh -Argument $argline -WorkingDirectory $repo
$trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                         -DontStopIfGoingOnBatteries `
                                         -StartWhenAvailable `
                                         -RestartCount 99 `
                                         -RestartInterval (New-TimeSpan -Minutes 1) `
                                         -ExecutionTimeLimit (New-TimeSpan -Seconds 0)

Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger `
                       -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $name

Start-Sleep -Seconds 3
$t = Get-ScheduledTask -TaskName $name
$i = Get-ScheduledTaskInfo -TaskName $name
Write-Host "armed $Chain as scheduled task '$name'"
Write-Host ("  state   : {0}" -f $t.State)
Write-Host ("  started : {0}" -f $i.LastRunTime)
Write-Host ("  action  : {0} {1}" -f $pwsh, $argline)
