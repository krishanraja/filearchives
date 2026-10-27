# 04 inventory

One row per document, carrying every signal about it.

## Inputs
- the archive on disk

## Outputs
- a run directory under the workspace audit path holding immutable `segment-*.json` files and an `inventory-summary.json` (path, size, dates, extension, origin and classification hints per item; no hash, since identity is proved in `02_ingest`)
- the `INVENTORY.csv` named in the original scaffold is not written by any stage

## Invariants
- the disk is the truth; the inventory is a claim about it
- a record keyed on PATH is stale the moment anything moves
- long work writes as it goes and resumes; it never holds results in RAM

## Code
| file | role |
|---|---|
| `stages/04_inventory/build_inventory.ps1` | Windows-first item inventory in immutable atomic segments; resumes by replaying committed segments and records media, generated-tree and sensitive-name hints without reading content |
| `stages/04_inventory/verify_inventory.ps1` | independently verifies segment seals, unique and bounded paths, protected-root exclusion, and optionally reconciles every identity against the live source |

## Tests
- `tests/test_inventory_resume.ps1`

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 9 | immutable fsynced segments are the checkpoint; resume replays them without duplicate rows | `test:tests/test_inventory_resume.ps1:resume emits no duplicate item rows` |
| 5 | completion is independently re-derived from sealed segments and, when requested, the live filesystem | `test:tests/test_inventory_resume.ps1:independent live verification passes` |
