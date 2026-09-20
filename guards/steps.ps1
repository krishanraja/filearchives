<#
    Invoke-Step: the only sanctioned way to run long work in a chain.

    Dot-source it, then every step goes through it:

        . "$PSScriptRoot\steps.ps1"

        Invoke-Step -Name 'survey' `
            -Preflight     { ... prove it works on a handful; $true / $false } `
            -Start         { ... launch and RETURN the process(es) } `
            -Progress      { ... a number that must go UP while it works } `
            -Verify        { ... RE-DERIVE a sample and compare } `
            -Postcondition { ... prove it actually did the thing } `
            -ExpectedUnits 9164

    Carried from contentarchives, where it was written after three pieces of work
    ran confidently and did the wrong thing in one afternoon. None crashed. None
    overspent. Every guard the project had was aimed at crashes and money:

      an inventory ran 33 minutes over 12,988 files and wrote no duration at all,
      because a missing binary returned an empty dict instead of raising;
      a re-judge was about to reprocess 19,684 files sixty times, because its
      "outstanding" count was a constant rather than a countdown;
      a step took 3h19m against a 20-minute estimate and said nothing until it
      finished.

    The first needed a PREFLIGHT, the second a LOOP INVARIANT, the third a
    CHECKPOINT that recalibrates out loud. This runner makes all three mandatory,
    so they apply to work nobody has written yet.

    WHAT IS FIXED HERE FROM DAY ONE

    contentarchives' version cast a gate's result with [bool] applied to the
    whole output stream. Every chain logs inside its gates, and a logger that
    writes to the OUTPUT stream (Tee-Object does) puts its own text into the
    return value - and [bool] of a non-empty array is $true. A Postcondition
    that returned $false was read as success: a 172 GB upload reported itself
    finished, and the -Verify gate in that chain had never been able to fail at
    all, from the day it was written.

    So a gate's answer is its LAST emission, and a gate that emits nothing is a
    no. See Gate below. Chains here log with Add-Content + Write-Host, never
    Tee-Object, and both defences exist because one of them was enough to be
    believed for a week.
#>

# NO Set-StrictMode here. This file is dot-sourced, so a strict mode set at the
# top would land in the CALLING chain's scope and change how every line of it
# behaves - including chains written before the rule existed, mid-run, at night.
# A safety helper must not alter the semantics of the thing it is helping.

function script:Gate([scriptblock] $block) {
    <#  A gate's answer is the LAST thing it emits, never the whole stream.
        A block that logs before returning cannot accidentally report success,
        and a block that answers nothing is a refusal rather than an approval. #>
    $out = @(& $block)
    if ($out.Count -eq 0) { return $false }
    return [bool]($out[-1])
}

function Invoke-Step {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]      $Name,

        # Prove the mechanism works on a tiny sample BEFORE committing hours to
        # it. It is cheaper to find a missing binary in five seconds than in 33
        # minutes.
        [Parameter(Mandatory = $true)][scriptblock] $Preflight,

        # Launch the real work and RETURN the process or processes. The runner
        # owns the waiting so it can checkpoint while they run - a step that
        # blocks internally cannot be supervised.
        [Parameter(Mandatory = $true)][scriptblock] $Start,

        # A number that must increase while the work runs. The runner uses it to
        # detect a step that is alive but achieving nothing.
        [Parameter(Mandatory = $true)][scriptblock] $Progress,

        # Prove the work is CORRECT, repeatedly, while it runs. -Progress
        # answers "is it moving?", and in contentarchives the answer was yes,
        # beautifully, for five hours, while every record written was attached
        # to the wrong file. A row count climbing is not evidence of anything
        # except a row count climbing.
        #
        # A -Verify block must RE-DERIVE a sample from its source and compare,
        # never inspect the output's shape. Every cheap shape check passed on
        # that corrupt run: well-formed rows, plausible counts. Validity is not
        # correctness, and only recomputing the answer tells them apart.
        [Parameter(Mandatory = $true)][scriptblock] $Verify,

        # Prove the work actually happened. A step that exits 0 having written
        # nothing must not be allowed to look like success.
        [Parameter(Mandatory = $true)][scriptblock] $Postcondition,

        [double] $ExpectedUnits = 0,
        [double] $CheckpointMin = 10,
        [int]    $StallStrikes  = 3,
        [int]    $VerifyEvery   = 4
    )

    if (-not (Get-Command Say -ErrorAction SilentlyContinue)) {
        throw "Invoke-Step needs a Say function from the calling chain"
    }
    if (-not (Get-Command Stop-Chain -ErrorAction SilentlyContinue)) {
        throw "Invoke-Step needs a Stop-Chain function from the calling chain"
    }

    # ---- 1. preflight -------------------------------------------------------
    Say "[$Name] preflight"
    $ok = $false
    try { $ok = Gate $Preflight }
    catch { Stop-Chain "[$Name] preflight threw: $_" }
    if (-not $ok) { Stop-Chain "[$Name] preflight failed - not committing to the full run" }
    Say "[$Name] preflight OK"

    # ---- 2. start, and take a baseline before anything runs -----------------
    $p0 = 0.0
    try { $p0 = [double](& $Progress | Select-Object -Last 1) } catch { $p0 = 0.0 }
    $t0 = Get-Date
    Say ("[$Name] starting (progress baseline {0:N0}{1})" -f $p0,
         $(if ($ExpectedUnits -gt 0) { ", expecting ~{0:N0} units" -f $ExpectedUnits } else { "" }))

    $procs = @(& $Start) | Where-Object { $_ -is [System.Diagnostics.Process] }
    if (-not $procs) { Stop-Chain "[$Name] -Start returned no process to supervise" }

    # ---- 3. supervise -------------------------------------------------------
    $last = $p0
    $strikes = 0
    $ticks = 0
    $nextCheck = (Get-Date).AddMinutes($CheckpointMin)
    while ($procs | Where-Object { -not $_.HasExited }) {
        Start-Sleep -Seconds 15
        if ((Get-Date) -lt $nextCheck) { continue }
        $nextCheck = (Get-Date).AddMinutes($CheckpointMin)
        $ticks++

        if ($ticks -eq 1 -or ($ticks % $VerifyEvery) -eq 0) {
            $good = $false
            try { $good = Gate $Verify }
            catch { Stop-Chain "[$Name] verify threw at checkpoint ${ticks}: $_" }
            if (-not $good) {
                foreach ($p in $procs) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
                Stop-Chain "[$Name] VERIFY FAILED at checkpoint $ticks - the output is being written INCORRECTLY. Stopped rather than produce more of it."
            }
            Say "[$Name] verify OK (checkpoint $ticks)"
        }

        $now = $last
        try { $now = [double](& $Progress | Select-Object -Last 1) } catch { }
        $mins = ((Get-Date) - $t0).TotalMinutes
        $done = $now - $p0
        $rate = if ($mins -gt 0) { $done / $mins } else { 0 }

        if ($now -le $last) {
            $strikes++
            Say ("[$Name] CHECKPOINT: no progress in {0} min (strike {1}/{2}), still at {3:N0}" -f `
                 $CheckpointMin, $strikes, $StallStrikes, $now)
            if ($strikes -ge $StallStrikes) {
                foreach ($p in $procs) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
                Stop-Chain ("[$Name] stalled: {0} consecutive checkpoints with no progress over {1} minutes. Alive is not the same as working." -f $strikes, ($strikes * $CheckpointMin))
            }
        } else {
            $strikes = 0
            $msg = "[$Name] CHECKPOINT: {0:N0} done in {1:N0} min ({2:N1}/min)" -f $done, $mins, $rate
            # RECALIBRATION. An estimate that is wrong is fine; an estimate that
            # is wrong in silence is what wastes a night. ExpectedUnits must be
            # what THIS RUN will do, not the size of the whole corpus - a
            # resumed run in contentarchives reported an ETA of five and a half
            # months because it measured remaining work against the total.
            if ($ExpectedUnits -gt 0 -and $rate -gt 0) {
                $etaMin = [math]::Max(0, ($ExpectedUnits - $done) / $rate)
                $msg += ", ETA {0:N0} min" -f $etaMin
                if ($done -gt $ExpectedUnits * 1.5) {
                    $msg += " -- RECALIBRATE: already {0:N0} against an expected {1:N0}" -f $done, $ExpectedUnits
                }
            }
            Say $msg
            $last = $now
        }
    }

    # ---- 4. verify once more at the end, then the postcondition -------------
    # The last stretch of work has never been verified by a checkpoint, because
    # the process exited before the next one was due.
    $codes = ($procs | ForEach-Object { $_.ExitCode }) -join ','
    $good = $false
    try { $good = Gate $Verify }
    catch { Stop-Chain "[$Name] final verify threw: $_" }
    if (-not $good) {
        Stop-Chain "[$Name] FINAL VERIFY FAILED (exit codes: $codes) - the step finished, and what it produced is wrong."
    }
    Say "[$Name] final verify OK"

    $ok = $false
    try { $ok = Gate $Postcondition }
    catch { Stop-Chain "[$Name] postcondition threw: $_" }
    if (-not $ok) {
        Stop-Chain "[$Name] postcondition FAILED (exit codes: $codes). The step finished without doing what it claims to do."
    }

    $final = $last
    try { $final = [double](& $Progress | Select-Object -Last 1) } catch { }
    Say ("[$Name] done in {0:N0} min, progress {1:N0} -> {2:N0}, exit {3}" -f `
         ((Get-Date) - $t0).TotalMinutes, $p0, $final, $codes)
    return $true
}

function New-ChainLogger {
    <#  The logger every chain should use.

        $Say = New-ChainLogger -Path $log
        function Say($m) { & $Say $m }

        Add-Content + Write-Host, NEVER Tee-Object. Tee writes the line to the
        pipeline as well as the file, which puts log text inside the return
        value of any gate that logs - and that read as success for a week. #>
    param([Parameter(Mandatory = $true)][string] $Path)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    return {
        param($m)
        $line = "$((Get-Date).ToString('HH:mm:ss'))  $m"
        Add-Content -Path $Path -Value $line
        Write-Host $line
    }.GetNewClosure()
}
