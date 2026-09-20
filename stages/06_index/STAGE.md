# 06 index

Make the archive searchable by its own contents.

## Inputs
- the inventory and the documents

## Outputs
- a full-text index over document text, and the metadata beside it

## Invariants
- the index is derived and disposable; it is never the source of truth
- a rebuild reads the disk, not another derived record

## Code
| file | role |
|---|---|
| `stages/06_index/build_index.py` | full-text search over extracted document text |

## Tests
- none yet

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| - | none claimed yet | - |
