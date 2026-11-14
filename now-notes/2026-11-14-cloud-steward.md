# The cloud steward: the Drive tree, reconciled by key

Status: stages/09_mirror/reconcile_drive_tree.ps1 reconciles Control Center's daily Drive tree export (opaque keys and counts, never a Drive id or a name, because this repository is public) into policy/drive-ids.json and one DRIVE-LOG.jsonl row a day; .github/workflows/steward.yml runs it daily and by hand, and does nothing until Krish sets the DRIVE_TREE_EXPORT_TOKEN secret. Folder questions (asks.json) are not built: whether a declared folder is known without asking, and whether his press counts as his answer, are his rulings to make first.
Next: Krish sets DRIVE_TREE_EXPORT_TOKEN in Control Center's Vercel and as this repository's Actions secret, then one run by hand should write the baseline row.
North Star check (2026-11-14): holds.
