# 02 ingest

Bring a document into the archive once, deduplicated by content.

## Inputs
- a tree chosen by 01 sources
- the archive and its hash index

## Outputs
- files placed in the archive, hardlinked where the volume allows
- a journal of what was added and what was refused as a duplicate

## Invariants
- a duplicate is declared only on a whole-file hash, never a name
- an unreadable candidate is UNPROVEN and is never admitted as new
- a VERSION is not a duplicate and is never collapsed without a human

## Code
| file | role |
|---|---|
| `filearchives/dedupe.py` | three tiers - size rules out for free, a head+tail signature clears most collisions, and only a whole-file hash may declare a duplicate |

## Tests
- none yet

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 2 | size rules a candidate out; only a hash rules one in | `code:filearchives/dedupe.py:def is_duplicate_of` |
| 3 | equal size is not equal content, and the name is never consulted | `code:filearchives/dedupe.py:Filename is never part of the decision` |
| 8 | an unreadable file is unproven, never 'not a duplicate' | `code:filearchives/dedupe.py:treated as UNPROVEN` |
| 12 | a version is refused rather than collapsed | `code:filearchives/safety.py:def looks_like_a_version` |
