# 09 canonical audit

Prove that the finished estate exposes one shallow authority for business,
personal and local repository work. This stage checks navigation and boundaries;
it does not mirror cloud content onto intermittently connected machines.

## Code

| file | role |
|---|---|
| `stages/09_mirror/reconcile_drive_tree.ps1` | the cloud half (fleet integration I-25): reconcile Control Center's daily Drive tree export (`drive-tree-export/1`, opaque keys, never a Drive id or a name) by key into `policy/drive-ids.json` and one `docs/folder-checkin/DRIVE-LOG.jsonl` row; a rename or move is one event, a binned parent one event with its descendants, a restore recorded; run daily by `.github/workflows/steward.yml` |
| `stages/09_mirror/test_canonical_state.ps1` | check the top of every watched drive against Krish's folder record: recorded folders and never-enter boundaries present, no loose root files, the critical worktree present, and unknown folders reported as waiting on him, without traversing protected boundaries |

## Inputs
- workspace configuration
- accepted user policy
- verified structure receipts

## Outputs
- an independently derived canonical-state report
- `policy/drive-ids.json` and `docs/folder-checkin/DRIVE-LOG.jsonl`: the cloud record by opaque key, and one row of counts a day

## Invariants
- protected roots are checked only at their boundary
- expected and unexpected top-level navigation roots are explicit
- a top-level folder outside the layout is Krish's, reported as waiting on him, never an issue to fix
- a missing or disconnected source is unavailable, never empty
- a partial Drive export is unknown: one row says so and the cloud record is left as it was; nothing is counted or called gone from it
- no Drive id and no folder name is written to this public repository: only opaque keys and counts

## Tests
- canonical-state audit in the completed estate run
- `tests/test_reconcile_drive_tree.ps1` (CI): baseline, rename, move, binned parent with child, restore, missing and return, a repeated read, a partial export

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 07 | absent is not empty | `tests/test_powershell_guards.ps1` |
| 09 | long work is resumable | canonical-state report is replaceable and atomic |
