<#
    The one button. RECORD-MY-FOLDERS.cmd runs this on Krish's PC after it has
    pulled the latest filearchives.

    After Krish says yes on screen, it:
      1. pauses every other filearchives scheduled job on this PC;
      2. records every folder in the watched drives as where he wants it
         (folder names only; no file is opened, moved or deleted);
      3. sets up the weekly check-in (Monday 09:00, or at next logon if the
         PC was off), which asks him about each new folder;
      4. saves the record to the filearchives repository on GitHub.
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'guards' 'workspace.ps1')
. (Join-Path $repo 'guards' 'atomic.ps1')
. (Join-Path $repo 'guards' 'folder_consent.ps1')
Add-Type -AssemblyName System.Windows.Forms
$title = 'filearchives: record my folders'
$weeklyTask = 'filearchives-weekly-folder-checkin'

$roots = (Import-FaFolderPreferences).WatchRoots.Path -join "`n   "
$go = [Windows.Forms.MessageBox]::Show(
    "This will:`n`n" +
    "1. Pause any other filearchives job scheduled on this PC.`n" +
    "2. Record every folder in`n   $roots`n   as where you want it. Folder names only; no file is opened.`n" +
    "3. Ask you about each new folder every Monday at 09:00.`n" +
    "4. Save the record to the filearchives repository on GitHub.`n`n" +
    "Nothing on your drives is moved, renamed or deleted. Go ahead?",
    $title, 'YesNo', 'Question')
if ($go -ne 'Yes') { Write-Host 'Stopped. Nothing was changed.'; exit 0 }

$paused = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -like 'filearchives-*' -and $_.TaskName -ne $weeklyTask -and $_.State -ne 'Disabled'
})
$notPaused = [Collections.Generic.List[string]]::new()
foreach ($t in $paused) {
    try { Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop | Out-Null }
    catch { $notPaused.Add($t.TaskName) }
}

# Strict mode: $LASTEXITCODE is unset until something sets it, and the
# step only sets it when it stops.
$global:LASTEXITCODE = 0
& (Join-Path $repo 'stages' '07_structure' 'record_folder_preferences.ps1')
if ($LASTEXITCODE -eq 3) {
    [Windows.Forms.MessageBox]::Show("None of the drives is connected, so nothing was recorded.`n`nConnect Google Drive and press the button again.",
        $title, 'OK', 'Warning') | Out-Null
    exit 1
}

$pwsh = (Get-Command pwsh).Source
$chain = Join-Path $repo 'chains' 'chain_weekly_folder_checkin.ps1'
$action = New-ScheduledTaskAction -Execute $pwsh -WorkingDirectory $repo `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$chain`""
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '09:00'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
# Interactive, so the questions appear on Krish's screen rather than nowhere.
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $weeklyTask -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Force | Out-Null

$saved = Save-FaFolderRecordToGitHub -Repo $repo -Paths @('policy/folder-preferences.json') `
    -Message "record Krish's folders as his preference for where everything goes"
$count = @((Import-FaFolderPreferences).Data.folders).Count
$pausedLine = if ($paused.Count) { "Paused: $(@($paused.TaskName | Where-Object { $notPaused -notcontains $_ }) -join ', ')." } else { 'No other filearchives job was scheduled.' }
if ($notPaused.Count) {
    $pausedLine += "`nCOULD NOT PAUSE (needs admin): $($notPaused -join ', '). Open Task Scheduler, right-click each, Disable."
}
[Windows.Forms.MessageBox]::Show(
    "Done. $count folders recorded as where you want them.`n`n$pausedLine`n" +
    "Weekly check-in: every Monday at 09:00.`n$saved`n`nNothing on your drives was moved, renamed or deleted.",
    $title, 'OK', 'Information') | Out-Null
