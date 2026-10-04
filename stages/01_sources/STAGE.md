# 01 sources

Find every tree that holds documents, and record what was seen.

## Inputs
- the drives on this machine, and any mount that is attached

## Outputs
- a survey per root: counts and bytes by type, written down
- `SOURCES.csv` - one row per tree, with what it appears to hold

## Invariants
- a survey acts on nothing: it counts, it does not move or delete
- an absent or unmounted root STOPS the survey, never reads as empty
- a figure from a syncing mount carries its timestamp and is re-measured

## Code
| file | role |
|---|---|
| `stages/01_sources/survey_roots.py` | walk a tree and count documents by extension, size band and folder - metadata only, so a cloud placeholder is measured without being downloaded |
| `stages/01_sources/survey_roots.ps1` | Windows-first survey of all file types, directories and empty folders; refuses protected roots before traversal and records unavailable peers distinctly from empty trees |
| `stages/01_sources/test_windows_profile_coverage.ps1` | completion gate proving that every existing Windows known folder, including Downloads on peer profiles, is covered by a configured source root |
| `guards/workspace.ps1` | schema-v2 workspace validation, canonical path boundaries and protected-root enforcement |
| `chains/chain_survey.ps1` | the survey, supervised and resumable: proves at least one source is mounted before walking terabytes, re-derives the newest row against the disk at every checkpoint, and refuses to call a run that wrote nothing a success |

## Tests
- `tests/test_powershell_guards.ps1`
- `tests/test_windows_profile_coverage.ps1`

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 7 | an absent root is recorded as unavailable with null counts, never zero | `test:tests/test_powershell_guards.ps1:missing source is not reported as zero files` |
| 11 | a survey reports what is THERE, and narrowing to what MATTERS is a separate, arguable step | prose-only |
| 29 | a drive-level inventory is not proof that every local profile ingress was handled; every existing known folder must be named by a source boundary before completion | `test:tests/test_windows_profile_coverage.ps1` |
