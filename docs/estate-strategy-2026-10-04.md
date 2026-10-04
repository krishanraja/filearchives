# Estate analysis and target structure

Status: evidence-backed recommendation, before mutation
Inventory run: `estate-20261003-v1`
Analysis date: 2026-10-04

## Executive decision

Use four deliberate roots in `H:\My Drive`:

1. `CURRENT` for canonical active business documents and deliverables.
2. `ARCHIVE` for the one canonical business archive.
3. `CONTENT-EXTRA` for useful photographs and videos discovered outside the
   excluded library, except media that must remain inside an active project.
4. `ContentLibrary`, unchanged and completely outside this programme.

Keep personal, family, wealth and private legal material in
`G:\My Drive\Personal`, consistent with the machine routing policy. Do not put
live Git repositories inside Google Drive. The canonical committed source is
its private remote; each Windows machine uses the same local clone convention:
`C:\Users\krish\dev\<remote-owner>\<repo>` or
`L:\Users\krish\dev\<remote-owner>\<repo>`.

This is a consolidation, not a bulk copy. Generated trees, cache data and exact
duplicates do not enter the archive. Unique old work and personal records do.

## Scope and trust

- 12 available source roots were inventoried and structurally verified.
- All eight L-machine roots are absent in this execution context. There is no
  L mapping in `Get-PSDrive`, `net use`, the SMB mapping table or the current
  user's `HKCU:\Network\L`; `LORIMER` resolves to `192.168.0.242`, but TCP 445
  is unreachable and the configured share cannot be opened. L remains
  unproven, never empty, regardless of whether another interactive session
  still displays a remembered mapping.
- `H:\My Drive\ContentLibrary` was met once at its boundary and skipped. No
  descendant was enumerated, hashed or compared.
- `C:\Users\krish\Documents` is partial only because 14 generated Python
  package directories denied access after three attempts. They are under old
  Codex scratch dependency trees, not user-authored document folders.
- Every other present source passed sealed-segment, unique-path and
  protected-boundary verification.

## Measured estate

| Measure | Result |
|---|---:|
| Files | 890,609 |
| Directories | 99,554 |
| Bytes | 169.20 GB |
| Empty directories | 5,645 |
| Generated or Git-internal files | 731,199 |
| Generated or Git-internal bytes | 17.52 GB |
| Zero-byte files | 18,229 |
| Media files | 39,993 |
| Media bytes | 88.19 GB |
| Sensitive-name hints, contents not read | 298 |

Item count is misleading here. 82.1% of files are generated dependencies,
build output, caches or Git internals, but they are only 10.4% of bytes. Media
and historical backup sets drive storage; toolchain material drives clutter.

Timestamps are also not sufficient evidence. Recent clones and restored trees
make old content appear new. Git state, path context, uniqueness, document type
and backup-set identity must qualify age.

## Classification decisions

### 1. Important and recent

- `C:\Users\krish\dev\krishanraja\mm-ctrl` is the highest priority item. It
  is on `codex/g20-context-exchange-proof`, contains 50 tracked changes and 627
  untracked entries at the latest observation, and is not independently
  preserved. No cleanup may touch it before a verified snapshot and remote
  coverage exist.
- The active source estate contains 17 Git repositories. Only `mm-ctrl` and
  this `filearchives` engine are dirty. Clean branch worktrees may still be
  important, but can be recreated once their commits are proven remote.
- Active venture deliverables in OneDrive `Documents\0 Ventures`, G Drive
  `Ventures\Active`, and H Drive work roots need project-level reconciliation.
  Their copied timestamps cannot select a winner.
- H Drive `Active Operations`, `Legal & Finance`, current identity material and
  current Mindmaker work are current canonical candidates.

### 2. Important and old

- Personal and family records in H `Personal`, E device backups, G `Personal`,
  old computer folders and identity/legal records are preservation candidates
  regardless of age.
- `E:\ContentLibrary` is not empty garbage. It contains 945 files and 3.17 GB,
  including 508 images, 22 videos, 26 audio files, 212 PDFs, WhatsApp database
  backups and application packages. It also contains 1,049 directories, of
  which 717 are empty. Its files require dedupe and classification; only the
  proven empty directory skeleton is a straightforward removal candidate.
- Historical work backups from 2016, 2017, 2020 and 2022 may contain unique
  contracts, decks and source material. Preserve unique content, not the
  device-shaped folder layout.

### 3. Unimportant but worth archiving

- Unique obsolete work deliverables, exports and device backups should enter
  `ARCHIVE` by venture or provenance and year after duplicate removal.
- Installer packages, APKs and compressed exports are archive candidates only
  when they preserve unavailable software or the sole recoverable export.
- The 47.73 GB audio cohort is outside the `CONTENT-EXTRA` instruction.
  Personal music belongs under `G:\My Drive\Personal\Media\Audio` under the
  active routing policy; business recordings belong in the relevant H current
  project or H archive. Do not mix either with photographs and video.

### 4. Duplicate candidates

- 121,981 non-generated, non-zero files entered the content pass because their
  sizes collided. Edge signatures ruled 25,009 readable files out. Whole-file
  SHA-256 then proved 18,256 exact-duplicate groups containing 81,482 files and
  63,226 redundant copies. Their theoretical maximum reclaim is 9.25 GB.
- 4,357 proven groups touch `C:\Users\krish\dev`; individual members of those
  groups are never file-level deletion targets. Excluding every repo-touching
  group leaves a conservative 8.88 GB theoretical maximum across 13,899
  groups, still subject to survivor selection and action-time revalidation.
- Duplicate coverage is intentionally partial: 15,486 signature rows and two
  whole-hash rows remain unproven. This includes every H candidate (6,270 files,
  23.46 GB) and every G candidate (8,176 files, 1.07 GB), whose mounted metadata
  was readable but whose Google Drive provider refused content reads, plus
  1,025 OneDrive placeholders (0.38 GB), seven live-file changes and seven
  document read/missing errors. The 9.25 GB result is therefore a proven lower
  bound, not an estimate of final estate-wide duplication.
- The largest proven reclaim cohorts are repeated Codex browser runtimes and
  four MindmakeVideoStudio runtime backups under C Documents. Cross-source
  overlap includes 181 OneDrive/E groups (127.93 MB per one-copy set), 68
  C-Music/E groups (59.87 MB), and 3,544 C-dev/C-documents groups whose repo
  membership makes them non-actionable at file level.
- Four Git remote identities have multiple local worktrees or clones:
  `filearchives`, `content-engine`, `control-center` and `ai-harness`. Different
  branches are not duplicates. The extra clean `filearchives` clone is the
  clearest removal candidate after the active engine changes are preserved.
- Obvious duplicate-looking H audio filenames and repeated runtime backups are
  priority hash cohorts, never name-based deletions.

### 5. Delete completely candidates

These are candidates, not an executed deletion list:

- 731,199 generated or Git-internal files totaling 17.52 GB, after each owning
  project proves that lockfiles and source are sufficient to rebuild them.
- 5,645 proven empty directories, including 717 under `E:\ContentLibrary`.
- `E:\_thumbs`: 15,794 derived images totaling about 0.38 GB.
- G `_QUARANTINE`: 21,787 files totaling only 0.14 GB, including 15,067
  zero-byte files and 8,121 generated-tree files. Its zero-byte semantics must
  be checked before removal.
- Old dependency/runtime copies under `Documents\Codex` and repeated
  `Documents\MindmakeVideoStudio\runtime.backup-*` trees after source and
  current runtime recovery are verified.
- Redundant installers, caches, Spotify cache data, partial downloads and exact
  hash duplicates after a survivor is revalidated.

No unique file becomes deletable solely because it is old, small, unnamed,
zero-byte or stored in a folder called trash, temp or quarantine.

## Media routing

| Cohort | Files | Bytes | Decision |
|---|---:|---:|---|
| Likely useful photos/videos | 9,353 | 38.35 GB | Route to `CONTENT-EXTRA`, except active project assets |
| Screenshot, thumbnail, meme or cache candidates | 18,961 | 2.04 GB | Review/delete cohort |
| Generated media fixtures | 8,972 | 0.08 GB | Rebuildable cleanup cohort |
| Audio | 2,707 | 47.73 GB | Split personal to G Personal and business to the relevant H project/archive; never `CONTENT-EXTRA` |

High-value media cohorts include E phone camera backups, C Downloads `Mems`, C
Documents `headshots`, G `Lozzy Mems`, H personal video and current work video.
Low-value cohorts include E `_thumbs`, OneDrive screenshots and generated test
assets. “Mems” is treated as memories, not automatically as memes.

## Target structure

```text
H:\My Drive\
├── ContentLibrary\                 # total exclusion, unchanged
├── CURRENT\
│   ├── 00_INDEX\
│   │   ├── WHERE-IS-EVERYTHING.md
│   │   ├── REPOSITORIES.json
│   │   └── MACHINE-POLICY.json
│   ├── 10_VENTURES\
│   │   ├── Mindmaker\
│   │   ├── Mindmaker-OS\
│   │   ├── Fractionl\
│   │   └── Labs\
│   ├── 20_OPERATIONS\
│   │   ├── Company\
│   │   ├── Finance\
│   │   ├── Legal\
│   │   └── People\
│   ├── 30_KNOWLEDGE\
│   │   ├── AI-Systems\
│   │   ├── Brand\
│   │   └── Research\
│   └── 90_INBOX\
├── ARCHIVE\
│   ├── Ventures\<venture>\<year>\
│   ├── Work-History\<organisation>\<year>\
│   ├── Devices-and-Exports\<device-or-service>\<date>\
│   └── Records\<category>\<year>\
└── CONTENT-EXTRA\
    ├── Photos\<year-or-event>\
    └── Video\<year-or-project>\
```

`G:\My Drive\Personal` remains the canonical personal tree. After migration,
G should otherwise contain only explicitly retained personal material and any
policy-required venture locations until that routing policy is revised.

## Source disposition recommendation

| Source | Recommended end state |
|---|---|
| `C:\Users\krish\dev` | Keep as the live repo area on this machine. Preserve dirty work first; remove only whole clean clones/worktrees after remote branch proof. Never delete individual duplicate files inside a repo. |
| C Desktop/Documents/Downloads | Extract current business deliverables to H `CURRENT`, historical unique work to H `ARCHIVE`, personal records/media to G `Personal`, and useful visual media to H `CONTENT-EXTRA`. Retire generated runtimes and installers only after proof. |
| C OneDrive/Dropbox | Treat as migration sources, not future canonical roots. Split business/current, business/archive and personal content by the same rules, then leave only provider state that is still intentionally used. |
| `E:` | Treat as a device-backup source. Preserve unique business history in H `ARCHIVE`, personal records in G `Personal`, useful photos/video in H `CONTENT-EXTRA`; retire the device-shaped copies only after destination verification. |
| `E:\ContentLibrary` | Classify its 3.17 GB normally. Preserve unique documents/media; remove only proven duplicates, disposable packages and the empty skeleton through a manifest. |
| `G:\My Drive` | Remains canonical for personal material. Reconcile non-personal venture material against the routing-policy decision below. |
| `H:\My Drive` excluding `ContentLibrary` | Consolidate business material into `CURRENT` and `ARCHIVE`, plus useful visual media into `CONTENT-EXTRA`; retire the old top-level taxonomy only after readback. |
| `L:\Users\krish\...` | Same local-repo convention as C once the execution context can see the mapping. It is currently unproven, not empty. |

There is one policy conflict, not an analytical ambiguity: the requested end
state says all current work should live under H `CURRENT`, while the supplied
machine routing policy currently sends single-venture deliverables to
`G:\My Drive\Ventures\Active`. My recommendation is to revise that rule so H
`CURRENT` becomes the business-current authority and G becomes personal-only.
Until that governance change is accepted, the engine will report both locations
but will not silently choose between contradictory canonical roots.

## Local repository policy

- Remote Git identity is canonical for committed code.
- Local paths are identical on both Windows machines:
  `<system-drive>:\Users\krish\dev\<remote-owner>\<repo>`.
- `node_modules`, build output, caches, runtime state and virtual environments
  are local and disposable after rebuild proof.
- Google Drive holds the current-work catalog, deliverables and verified
  disaster snapshots, not a synchronised live `.git` directory.
- Branch worktrees live under a machine-local `_worktrees` directory and are
  removed only after the branch commit is remote and the tree is clean.
- Every AI tool reads the generated index in `CURRENT\00_INDEX` plus a small
  machine-local copy, so tools work offline and reconcile when Drive returns.

## Execution order

1. Reconnect and inventory L. Merge it into this run without treating absence
   as empty.
2. Preserve `mm-ctrl` through a credential-aware, independently verified
   snapshot before any local cleanup.
3. Run signature then whole-file hashing over non-generated, non-zero files.
4. Produce a survivor-ranked duplicate manifest. Prefer canonical current
   paths, then canonical archive paths, then the best-preserved source.
5. Freeze `CURRENT`, `ARCHIVE` and `CONTENT-EXTRA` move manifests with collision
   handling and rollback paths.
6. Execute copy-first, verify destination, then retire sources in separate
   batches. Empty directories and generated trees come last.
7. Re-inventory every destination and every source. Completion requires zero
   unexplained unique residue and no protected-root access.

No destructive action has been executed by this report.
