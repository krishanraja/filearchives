# 07 structure

The canonical folder tree, and the proposal that maps files into it.

## Inputs
- sealed inventory segments, exact-duplicate evidence, and the accepted estate policy

## Outputs
- `layout-proposal.jsonl` - every file, its disposition, rule, confidence and shallow destination
- `layout-summary.json` - counts over exactly the proposal rows
- frozen folder-move manifests and independently read-back receipts

## Invariants
- a proposal is REVIEWED before anything moves; never an automatic move
- the proposal reports exactly what it will do, over the same set it acts on
- a destination map is proven injective before a single file is moved
- age controls visibility, never deletion eligibility
- protected families may be analysed and moved as a whole but never nominated for deletion
- an excluded boundary appearing in inventory is a fatal error, not a classification
- cross-account cloud-native files retain their owning account and stable IDs
- a folder move is same-volume only; cross-volume consolidation is copy/verify/retire

## Code
| file | role |
|---|---|
| `stages/07_structure/propose_layout.ps1` | map every inventoried file through the versioned policy without reading or mutating source content |
| `stages/07_structure/initialize_canonical_structure.ps1` | create and read back only the accepted shallow category folders |
| `stages/07_structure/new_folder_move_manifest.ps1` | freeze a collision-free folder move and its pre-action metadata seal |
| `stages/07_structure/invoke_verified_folder_move.ps1` | revalidate, move and independently read back one approved folder move |
| `stages/07_structure/new_live_file_move_manifest.ps1` | classify only direct loose files, freeze an injective same-volume destination map and skip every low-confidence or cross-volume row |
| `stages/07_structure/invoke_live_file_move_manifest.ps1` | revalidate and read back each exact loose-file move, using content hashes whenever the provider permits |
| `stages/07_structure/new_extension_move_manifest.ps1` | freeze recursive same-volume media routing by explicit extension with one content hash per item |
| `stages/07_structure/new_copy_retirement_manifest.ps1` | turn only a complete copy receipt into a separate pre-backup source-quarantine move manifest while preserving source-relative paths |
| `stages/07_structure/new_explicit_file_move_manifest.ps1` | freeze reviewed one-to-one file routing, including ownership-bound cloud-native metadata moves |
| `stages/07_structure/new_root_quarantine_manifest.ps1` | freeze recoverable routing of remaining loose root items after valuable cohorts have moved |
| `stages/07_structure/new_unproven_retention_manifest.ps1` | retain provider-unreadable rows explicitly instead of treating them as absent or disposable |
| `stages/07_structure/new_empty_directory_manifest.ps1` | identify only structurally empty, non-protected directories and freeze deepest-first removal targets |
| `stages/07_structure/invoke_empty_directory_manifest.ps1` | revalidate emptiness at action time, remove only still-empty targets and journal changed directories |
| `stages/07_structure/new_atomic_tree_relocation_manifest.ps1` | freeze a fast same-volume quarantine relocation for very large retained trees using a shallow entry seal |
| `stages/07_structure/invoke_atomic_tree_relocation_manifest.ps1` | revalidate and atomically rename a retained tree on one volume, proving source absence and destination shallow equivalence without claiming child hashes |

## Tests
- `tests/test_layout_classifier.ps1`
- `tests/test_atomic_tree_relocation.ps1`

## Lessons
| # | what this stage does about it | enforced by |
|---|---|---|
| 10 | the proposal a person approves is computed over the same set the move will act on | prose-only |
| 17 | old controls line-of-sight routing but is never sufficient reason to delete | `test:tests/test_layout_classifier.ps1:old theory remains evergreen` |
| 18 | protected families have a positive preserve rule rather than relying on a deletion exception | `test:tests/test_layout_classifier.ps1:family-admin` |
| 19 | temporary AI-document families remain review cohorts until a newest representative is proven | `test:tests/test_layout_classifier.ps1:temporary-family-review` |
| 20 | verified source retirement preserves paths relative to its sealed source root | `test:tests/test_verified_copy.ps1:retirement manifest flattened repeated leaf names` |
