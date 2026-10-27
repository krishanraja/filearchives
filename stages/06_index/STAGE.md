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
- none yet. This stage is planned, not built. The 2026-09-20 scaffold
  (`tools/scaffold_stages.py`) named a script `build_index.py` for full-text
  search over extracted document text; it was never written.

## Tests
- none yet

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| - | none claimed yet | - |
