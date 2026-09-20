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
| `chains/chain_survey.ps1` | the survey, supervised and resumable: proves at least one source is mounted before walking terabytes, re-derives the newest row against the disk at every checkpoint, and refuses to call a run that wrote nothing a success |

## Tests
- none yet - the first tool written here must arrive with one

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 7 | an absent root stops the survey rather than reporting zero | prose-only |
| 11 | a survey reports what is THERE, and narrowing to what MATTERS is a separate, arguable step | prose-only |
