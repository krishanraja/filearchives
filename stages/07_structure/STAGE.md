# 07 structure

The canonical folder tree, and the proposal that maps files into it.

## Inputs
- the inventory, the types from 05, the dates from 03

## Outputs
- `STRUCTURE-PROPOSAL.csv` - every file, and where it would go

## Invariants
- a proposal is REVIEWED before anything moves; never an automatic move
- the proposal reports exactly what it will do, over the same set it acts on
- a destination map is proven injective before a single file is moved

## Code
| file | role |
|---|---|
| `stages/07_structure/propose_layout.py` | map every file to its place in the canonical tree, as a reviewable list |

## Tests
- none yet

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 10 | the proposal a person approves is computed over the same set the move will act on | prose-only |
