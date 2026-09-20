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
| `guards/guarded_delete.py` | the only sanctioned delete |
| `stagepath.py` | where every stage lives, so no file hardcodes a relative depth |
| `tools/scaffold_stages.py` | wrote this conveyor once, and refuses to overwrite a STAGE.md a human has since edited |

## Tests
- `tests/test_stage_contracts.py`

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 14 | every learning is owned, and a claim whose enforcement has been deleted fails the build | `test:tests/test_stage_contracts.py:has no owner - a stage must claim it` |
| 7 | an absent input raises rather than returning empty | `code:guards/files.py:class MissingInput` |
