# filearchives

**The same engine as `contentarchives`, pointed at documents instead of memories.**

`contentarchives` consolidated 82,000 photographs and videos into one verified
library and reclaimed 1,114 GB doing it. The machinery that made that safe is
not about photographs. It is about **not losing things while moving a large
number of files you cannot replace**, and that problem is identical for twenty
years of documents.

This repo is that machinery, adapted. Content stays in `contentarchives`.
Documents, scans, statements, contracts, exports and the rest live here.

---

## What this is for

Krish, 2026-09-20: *"sort all of my old non-content documents, dedupe them, and
create the same folder structure in every drive that I have as fresh."*

Three jobs, in this order, because each depends on the one before it:

1. **Find every document** across every drive, and know what is a copy of what.
2. **Classify and dedupe by content**, never by name, while preserving versions
   and recording anything that cannot be proven.
3. **Consolidate into one current-work authority and one archive**, with one
   machine-local repo convention that remains usable while another machine or
   the network is offline.

---

## What is inherited, and why none of it is rewritten

Every rule below was paid for in `contentarchives`, most of them by something
going wrong. They are copied deliberately, not reinvented:

| Inherited | What it stops |
|---|---|
| **Deletion is allowlist-only** | A path-substring rule once destroyed 45 irreplaceable files. Nothing decides a deletion from what a path *looks like*. |
| **Only a whole-file hash declares a duplicate** | Two different files sharing a name and an exact byte count are rare and real. Size and signature RULE OUT; only the hash rules in. |
| **Re-verify at the instant of deletion** | A report is never evidence. The filesystem when the unlink happens is the only evidence. |
| **A surviving copy must be a different inode** | Two names for one set of bytes free nothing when one is deleted - and the caller who believed it had two copies now has none. |
| **Journal before destroying** | Every deletion carries its evidence, fsynced, before the file goes. |
| **Absent input stops the run** | A missing file is never read as an empty one. |
| **Long work is resumable and slice-able** | This machine kills long jobs under memory pressure. Work that holds results in memory loses them. |
| **Every learning has an owner in code or a test** | Fifty written rules did not stop eleven being broken in one afternoon. The build fails when a stage stops claiming its lessons. |

**Documents differ from photographs in three ways that matter**, and the stages
below exist because of them:

- **There is no EXIF.** A photograph carries its own date; a PDF usually does
  not. Dating comes from the filename, the folder, and the document's own text.
- **Versions are the normal case.** `contract_v2_FINAL_signed.pdf` is not junk
  to be deduped away - it is a version, and the *near*-duplicate question is the
  hard one. Byte-identical dedupe is only the first pass.
- **The content is readable.** A photograph needs a vision model to say what it
  is. A document mostly says so itself, in its own text, for free.

---

## The conveyor

Same shape as `contentarchives`: each stage owns its inputs, outputs,
invariants, code, tests and the lessons it enforces, in its own `STAGE.md`.

The executable estate flow is deliberately narrower than the numbered folder
names inherited from the original scaffold:

```text
source survey
  -> immutable inventory + independent verification
  -> estate/repository classification
  -> same-size shortlist
  -> head+tail signature shortlist
  -> whole-file SHA-256 proof
  -> exact-duplicate evidence
  -> survivor + structure manifests
  -> copy/verify/retire
  -> destination re-inventory
```

Every arrow is a sealed artifact boundary. A failed or interrupted stage
resumes from committed segments; it does not make the following stage guess.
Filesystem mutation is downstream of analysis and requires a frozen manifest,
action-time revalidation and a durable journal.

| Stage | Does |
|---|---|
| `01_sources` | Find the drives and trees that hold documents; record what was seen, never act on it |
| `02_ingest` | Bring files in once, content-deduplicated, hardlinked where the volume allows |
| `03_dating` | Date from filename, folder, and document text - in that order of trust |
| `04_inventory` | One row per file with every signal about it |
| `05_classify` | What KIND of document: statement, contract, scan, export, receipt |
| `06_index` | Full-text search over the documents themselves |
| `07_structure` | The canonical folder tree, and the proposal that maps files into it |
| `08_reclaim` | Free space - the only stage that destroys, and the most guarded |
| `09_mirror` | The same structure, identically, on every drive |

`guards/` sits beside them: the runners, the deletion guard, the atomic writes,
the verifier contract.

---

## Status

**Active estate analysis, 2026-10-04. No source mutation has occurred.**

The sealed `estate-20261003-v1` run inventories 890,609 files (169.20 GB)
across every currently available configured root. `H:\My Drive\ContentLibrary`
is an absolute exclusion and has not been traversed. The L machine is recorded
as unavailable, never as empty. Duplicate proofing is in progress through the
three content-identity tiers above. The current evidence-backed structure
recommendation is in `docs/estate-strategy-2026-10-04.md`.

Start at `RESUME.md`.
