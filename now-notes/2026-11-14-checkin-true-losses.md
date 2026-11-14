# 2026-11-14: the weekly check-in counts only true losses

Status: `stages/07_structure/weekly_folder_checkin.ps1` now (a) lets a consent row for a folder cover the recorded folders beneath it, (b) records a folder whose Drive id sits at a new path, per content-engine's `drive-paths.json`, as moved with where it went instead of gone plus new (a move without Krish's OK still counts), (c) records a folder that comes back as restored, and (d) lists in LATEST.md each folder an unattended run could not decide. Proof: `tests/test_checkin_true_losses.ps1`, in CI; `tests/test_new_folder_survives.ps1` still passes. No consent row was written; the guard is unchanged.

Next: the record gains Drive ids only once `drive-paths.json` exists on his PC (content-engine's sync writes it). Until then matching stays by path.

North Star check (2026-11-14): holds.
