<#
    The weekly folder check-in, as the scheduled task and CHECK-MY-NEW-FOLDERS.cmd
    run it on Krish's PC: get the latest record, look, ask, and save the result
    to GitHub only after Krish says yes. Nothing on his drives moves.
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'guards' 'workspace.ps1')
. (Join-Path $repo 'guards' 'atomic.ps1')
. (Join-Path $repo 'guards' 'folder_consent.ps1')
Add-Type -AssemblyName System.Windows.Forms
$title = 'filearchives weekly folder check-in'

# Best effort: answers Krish wrote on GitHub arrive this way. Offline is fine.
& git -C $repo pull --ff-only origin main 2>&1 | Out-Null

# Strict mode: $LASTEXITCODE is unset until something sets it, and the
# step only sets it when it stops.
$global:LASTEXITCODE = 0
& (Join-Path $repo 'stages' '07_structure' 'weekly_folder_checkin.ps1') -Interactive
if ($LASTEXITCODE -eq 3) {
    [Windows.Forms.MessageBox]::Show("Your folders have not been recorded yet.`n`nPress RECORD-MY-FOLDERS.cmd in the filearchives folder first.",
        $title, 'OK', 'Warning') | Out-Null
    exit 1
}

# The dev sprawl report and its move requests ride along (W3.4). Plan only:
# without -Execute nothing moves. If it cannot run, the check-in still stands.
$sprawlNote = ''
try {
    & (Join-Path $repo 'chains' 'chain_dev_consolidation.ps1') | Out-Host
    $sprawlNote = "`nThe dev sprawl report is $(Join-Path $repo 'docs' 'folder-checkin' 'SPRAWL.md')"
} catch {
    $sprawlNote = "`nThe dev sprawl report could not run this week: $($_.Exception.Message)"
}

$latest = Join-Path $repo 'docs' 'folder-checkin' 'LATEST.md'
$save = [Windows.Forms.MessageBox]::Show(
    "This week's check-in is done. Nothing was moved, renamed or deleted.`n`n" +
    "Save it to the filearchives repository on GitHub?`n(The report is $latest)$sprawlNote",
    $title, 'YesNo', 'Question')
if ($save -eq 'Yes') {
    $saved = Save-FaFolderRecordToGitHub -Repo $repo `
        -Paths @('policy/folder-preferences.json', 'docs/folder-checkin', 'NOW.md') `
        -Message ('weekly folder check-in {0}' -f (Get-Date -Format 'yyyy-MM-dd'))
    [Windows.Forms.MessageBox]::Show($saved, $title, 'OK', 'Information') | Out-Null
}
