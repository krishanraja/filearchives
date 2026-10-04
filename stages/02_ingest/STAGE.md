# 02 ingest

Bring a document into the archive once, deduplicated by content.

## Inputs
- a tree chosen by 01 sources
- the archive and its hash index

## Outputs
- files placed in the archive, hardlinked where the volume allows
- a journal of what was added and what was refused as a duplicate
- cross-volume folder copies whose every destination file has been read back and SHA-256 verified

## Invariants
- a duplicate is declared only on a whole-file hash, never a name
- an unreadable candidate is UNPROVEN and is never admitted as new
- a VERSION is not a duplicate and is never collapsed without a human
- cross-volume consolidation is copy/verify/retire; copying never removes its source

## Code
| file | role |
|---|---|
| `filearchives/dedupe.py` | three tiers - size rules out for free, a head+tail signature clears most collisions, and only a whole-file hash may declare a duplicate |
| `stages/02_ingest/build_hash_plan.ps1` | Windows-first sealed plan of non-generated, non-zero files whose sizes collide and therefore require content signatures |
| `stages/02_ingest/compute_signatures.ps1` | resumable head-and-tail SHA-256 filtering over sealed plan rows, with metadata revalidation and an explicit read budget |
| `stages/02_ingest/build_whole_hash_plan.ps1` | verifies every signature segment seal and emits only signature-collision rows for whole-file hashing |
| `stages/02_ingest/compute_whole_hashes.ps1` | resumable whole-file SHA-256 proof with before/after metadata checks; this is the only stage that may establish content identity |
| `stages/02_ingest/analyze_duplicate_groups.ps1` | verifies all whole-hash seals, emits exact duplicate groups, cross-source overlap, unproven rows, and theoretical—not actionable—reclaim |
| `stages/02_ingest/new_verified_copy_manifest.ps1` | freeze a folder copy with one whole-file hash per readable source file and block on any unproven item |
| `stages/02_ingest/invoke_verified_copy_manifest.ps1` | resumably copy each manifest row through a temporary file, verify destination content, and retain the source |
| `stages/02_ingest/snapshot_dirty_repository.ps1` | clone a dirty repository locally, hash-reconcile every tracked and non-ignored file, preserve the exact index and HEAD, and report rather than hide latent status drift |
| `stages/02_ingest/new_live_file_copy_manifest.ps1` | classify direct loose files and freeze only high-confidence, content-readable cross-volume copy rows |
| `stages/02_ingest/new_layout_copy_manifest.ps1` | turn sealed recursive layout proposals into collision-safe, source-preserving copy manifests while excluding credentials and low-confidence rows by disposition |
| `stages/02_ingest/new_explicit_file_copy_manifest.ps1` | freeze a small reviewed cross-volume mapping with whole-file hashes and collision-safe destinations |
| `stages/02_ingest/invoke_live_file_copy_manifest.ps1` | revalidate and copy loose files through whole-file SHA-256 destination readback while retaining every source and journalling per-file progress |
| `stages/02_ingest/split_live_file_copy_manifest.ps1` | deterministically partition one approved live-file copy manifest into non-overlapping shards that reconcile exactly to their authenticated parent |
| `stages/02_ingest/new_residual_live_file_copy_manifest.ps1` | resume an interrupted parent manifest after an independently retired source by omitting only rows whose destination still matches the frozen whole-file hash |
| `stages/02_ingest/new_filtered_live_file_copy_manifest.ps1` | derive an authenticated child manifest that excludes explicit installer, cache, path, extension, or size cohorts before transfer while accounting for every parent row |
| `stages/02_ingest/new_live_file_copy_manifest_from_verified.ps1` | convert one expensive frozen folder-hash manifest into an authenticated live-copy manifest that can be split into exact parallel shards without redoing discovery |

## Tests
- `tests/test_hash_plan.ps1`
- `tests/test_verified_copy.ps1`
- `tests/test_layout_copy_manifest.ps1`
- `tests/test_filtered_copy_manifest.ps1`
- `tests/test_verified_copy_sharding.ps1`
- `tests/test_repository_snapshot.ps1`

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 2 | size rules a candidate out; only a hash rules one in | `code:filearchives/dedupe.py:def is_duplicate_of` |
| 3 | equal size is not equal content, and the name is never consulted | `code:filearchives/dedupe.py:Filename is never part of the decision` |
| 8 | an unreadable file is unproven, never 'not a duplicate' | `code:filearchives/dedupe.py:treated as UNPROVEN` |
| 12 | a version is refused rather than collapsed | `code:filearchives/safety.py:def looks_like_a_version` |
| 15 | JSON identity timestamps remain round-trip strings instead of culture-formatted DateTime values | `code:stages/02_ingest/build_hash_plan.ps1:ConvertFrom-Json -Depth 32 -DateKind String` |
| 16 | provider failures remain a per-source unproven cohort in final evidence | `code:stages/02_ingest/analyze_duplicate_groups.ps1:SignatureUnprovenBySource` |
| 21 | copy executors retry cloud readback and safely resume verified destinations or their own temporary files | `code:stages/02_ingest/invoke_live_file_copy_manifest.ps1:Get-FaReadbackHash` |
| 22 | system metadata is rejected at the copy boundary even when an earlier path rule classified it differently | `test:tests/test_layout_copy_manifest.ps1:system metadata must be excluded independently` |
| 24 | every verified live-file destination appends a durable progress row | `test:tests/test_layout_copy_manifest.ps1:did not journal per-file progress` |
| 25 | obvious installation media and cache cohorts are filtered before cross-volume transfer, not after | `test:tests/test_filtered_copy_manifest.ps1:explicit waste filters preserve useful copy rows and parent lineage` |
| 27 | an expensive verified folder freeze becomes the parent of exact copy shards instead of forcing another serial discovery pass | `test:tests/test_verified_copy_sharding.ps1:a frozen verified folder copy converts into exact parallel live-copy shards` |
