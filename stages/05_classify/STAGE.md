# 05 classify

Decide what KIND of document each file is.

## Inputs
- the inventory, and the documents' own text

## Outputs
- a type per file: statement, contract, scan, receipt, export, other

## Invariants
- a classification is evidence for a human, never an instruction to move
- a type that cannot be determined is 'unknown', never a best guess

## Code
| file | role |
|---|---|
| `stages/05_classify/classify_documents.py` | type from extension, filename and the document's own first page |

## Tests
- none yet

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| - | none claimed yet | - |
