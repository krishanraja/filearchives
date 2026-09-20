# 04 inventory

One row per document, carrying every signal about it.

## Inputs
- the archive on disk

## Outputs
- `INVENTORY.csv` - path, size, hash, dates, type, origin tree

## Invariants
- the disk is the truth; the inventory is a claim about it
- a record keyed on PATH is stale the moment anything moves
- long work writes as it goes and resumes; it never holds results in RAM

## Code
| file | role |
|---|---|
| `stages/04_inventory/build_inventory.py` | one row per file with every signal, written incrementally |

## Tests
- none yet

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 9 | the inventory is built in resumable slices that flush as they go | prose-only |
