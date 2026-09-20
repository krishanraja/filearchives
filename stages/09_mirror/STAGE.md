# 09 mirror

The same structure, identically, on every drive.

## Inputs
- the canonical archive

## Outputs
- an identical tree on each target drive, verified

## Invariants
- a copy is verified by re-derivation, never by reading back what was written
- a mirror that only ADDS diverges silently; removal is explicit machinery

## Code
| file | role |
|---|---|
| `stages/09_mirror/mirror_tree.py` | copy the canonical tree to a target drive and prove it arrived |

## Tests
- none yet

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| - | none claimed yet | - |
