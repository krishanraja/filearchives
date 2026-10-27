# 05 classify

Decide what KIND of document each file is.

## Inputs
- the inventory, and the documents' own text

## Outputs
- built: estate analysis JSON and repository analysis JSON, reconciled to the verified inventory totals (`pipeline/stage-conveyor.json`)
- planned, not built: a type per file (statement, contract, scan, receipt, export, other)

## Invariants
- a classification is evidence for a human, never an instruction to move
- a type that cannot be determined is 'unknown', never a best guess

## Code
| file | role |
|---|---|
| `stages/05_classify/analyze_inventory.ps1` | Windows-first estate analysis by source, age, media, generated tree, empty directory, extension and same-size hash-candidate cohort |
| `stages/05_classify/analyze_repositories.ps1` | inventories Git identity, branch, commit recency and dirty state so copied timestamps never decide whether source work is current |

The per-document classifier (type from extension, filename and the document's
own first page) was named `classify_documents.py` in the 2026-09-20 scaffold
(`tools/scaffold_stages.py`) and was never written.

## Tests
- none yet

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| - | none claimed yet | - |
