# guards

The lessons as code, and the machinery that runs long work safely.

## Inputs
- none of its own; imported by every stage

## Outputs
- exit codes and STOPPING messages that halt work before it produces wrong output

## Invariants
- an absent input stops the run; it never reads as empty
- a reader never sees a partially written file
- nothing is deleted without proof, at the moment of deletion

## Code
| file | role |
|---|---|
| `guards/files.py` | atomic writes, absent-input stops, whole lines |
| `guards/paths.py` | where everything lives ON THIS MACHINE, resolved from per-machine config and never hardcoded. contentarchives opened its equivalent with a literal drive letter, which is correct for one machine and impossible for a second - and quietly wrong on the first one the day a drive is re-lettered. There is deliberately no default: an unconfigured machine STOPS with instructions rather than writing records somewhere nobody will look |
| `guards/workspace.ps1` | Windows-first schema-v2 workspace resolver; validates path boundaries and refuses protected roots before traversal or writes |
| `guards/atomic.ps1` | atomic UTF-8 and JSON writes with flush-to-disk before promotion, plus artifact hashing |
| `guards/steps.ps1` | `Invoke-Step`: preflight, progress, verify, postcondition, all mandatory. A gate's answer is its LAST emission, fixed here from day one - contentarchives cast the whole output stream, so a chain that logged inside a gate returned a non-empty array, `[bool]` read it as `$true`, and a Postcondition's `$false` was believed as success for a week |
| `guards/arm.ps1` | run a chain as a scheduled task so it outlives the session; reaps orphaned workers first. `-TaskName` is a real parameter with a per-chain default, unlike contentarchives' single fixed slot, which forced unrelated jobs to take turns for no reason but a shared string |
| `guards/guarded_delete.py` | the only sanctioned delete |
| `stagepath.py` | where every stage lives, so no file hardcodes a relative depth |
| `tools/scaffold_stages.py` | wrote this conveyor once, and refuses to overwrite a STAGE.md a human has since edited |

## Tests
- `tests/test_stage_contracts.py`
- `tests/test_powershell_guards.ps1`

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 14 | every learning is owned, and a claim whose enforcement has been deleted fails the build | `test:tests/test_stage_contracts.py:has no owner - a stage must claim it` |
| 7 | an absent input raises rather than returning empty | `code:guards/files.py:class MissingInput` |
