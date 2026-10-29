# 05 classify

Decide what KIND of document each file is.

## Inputs
- the inventory, and the documents' own text

## Outputs
- built: estate analysis JSON and repository analysis JSON, reconciled to the verified inventory totals (`pipeline/stage-conveyor.json`)
- built: the dev sprawl report, `docs/folder-checkin/SPRAWL.md` and `sprawl.json` (Wave 3 W3.4), read by Monday's check-in
- planned, not built: a type per file (statement, contract, scan, receipt, export, other)

## Invariants
- a classification is evidence for a human, never an instruction to move
- a type that cannot be determined is 'unknown', never a best guess
- the dev sprawl report only reads: Git runs with `--no-optional-locks`, it never fetches, and it names folders and counts, never a file inside a repository
- a repository not in `policy/repo-ventures.json` is 'unplaced', never guessed into a venture

## Code
| file | role |
|---|---|
| `stages/05_classify/analyze_inventory.ps1` | Windows-first estate analysis by source, age, media, generated tree, empty directory, extension and same-size hash-candidate cohort |
| `stages/05_classify/analyze_repositories.ps1` | inventories Git identity, branch, commit recency and dirty state so copied timestamps never decide whether source work is current |
| `stages/05_classify/report_dev_sprawl.ps1` | read-only dev sprawl report: every clone and linked worktree under dev, its venture, dirty and unpushed work, stashes, size, duplicates, and clones outside their venture's home with a proposed destination |

The per-document classifier (type from extension, filename and the document's
own first page) was named `classify_documents.py` in the 2026-09-20 scaffold
(`tools/scaffold_stages.py`) and was never written.

## Tests
- `tests/test_dev_sprawl.ps1`

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 38 | a report that reads Git leaves every byte under .git as it was | `code:stages/05_classify/report_dev_sprawl.ps1:--no-optional-locks -C $Tree` |
