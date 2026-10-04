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
| `stages/02_ingest/build_hash_plan.ps1` | Windows-first sealed plan of non-generated, non-zero files whose sizes collide and therefore require content signatures |
| `stages/02_ingest/compute_signatures.ps1` | resumable head-and-tail SHA-256 filtering over sealed plan rows, with metadata revalidation and an explicit read budget |
| `stages/02_ingest/build_whole_hash_plan.ps1` | verifies every signature segment seal and emits only signature-collision rows for whole-file hashing |
| `stages/02_ingest/compute_whole_hashes.ps1` | resumable whole-file SHA-256 proof with before/after metadata checks; this is the only stage that may establish content identity |
| `stages/02_ingest/analyze_duplicate_groups.ps1` | verifies all whole-hash seals, emits exact duplicate groups, cross-source overlap, unproven rows, and theoretical—not actionable—reclaim |

## Tests
- `tests/test_hash_plan.ps1`

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 2 | size rules a candidate out; only a hash rules one in | `code:filearchives/dedupe.py:def is_duplicate_of` |
| 3 | equal size is not equal content, and the name is never consulted | `code:filearchives/dedupe.py:Filename is never part of the decision` |
| 8 | an unreadable file is unproven, never 'not a duplicate' | `code:filearchives/dedupe.py:treated as UNPROVEN` |
| 12 | a version is refused rather than collapsed | `code:filearchives/safety.py:def looks_like_a_version` |
| 15 | JSON identity timestamps remain round-trip strings instead of culture-formatted DateTime values | `code:stages/02_ingest/build_hash_plan.ps1:ConvertFrom-Json -Depth 32 -DateKind String` |
| 16 | provider failures remain a per-source unproven cohort in final evidence | `code:stages/02_ingest/analyze_duplicate_groups.ps1:SignatureUnprovenBySource` |
