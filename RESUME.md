# RESUME FILEARCHIVES

**The document engine. Start here.**

```bash
cd C:\Users\krish\dev\filearchives
python tests/test_stage_contracts.py     # the conveyor is intact
```

---

## What this is

`contentarchives` consolidated 82,000 photographs into one verified library and
reclaimed 1,114 GB. This is the same machinery pointed at **documents**: the
twenty years of scans, statements, contracts, exports and downloads scattered
across every drive.

Krish, 2026-09-20: *"sort all of my old non-content documents, dedupe them, and
create the same folder structure in every drive that I have as fresh."*

**Content stays in `contentarchives`. Documents live here.** If a file is a
photograph or a video it belongs in the other engine, and the two must not
fight over the same trees.

---

## RIGHT NOW: scaffolded, nothing ingested (2026-09-20)

Built so far, carried from `contentarchives` because each piece was paid for
there:

| Piece | What it is |
|---|---|
| `stagepath.py` | one definition of where every stage lives |
| `filearchives/dedupe.py` | size -> signature -> whole-file hash, never the name |
| `filearchives/safety.py` | the deletion allowlist; garbage is a CLOSED list |
| `guards/guarded_delete.py` | the only sanctioned delete: proven survivor, different inode, re-hashed at the unlink, journalled first |
| `guards/files.py` | atomic writes, absent-input stops, whole lines only |
| `docs/LEARNINGS.md` | 14 rules, each owned by a stage or the build fails |

**Nothing has been scanned, ingested, deduped or deleted.**

---

## The order to build it in, and why

Do NOT start by writing an importer. The first job is to find out what is
actually out there, because every estimate made without measuring in the other
engine was wrong - often by a factor of ten, once by a factor of a hundred.

1. **`01_sources` - survey only.** Walk every drive, count documents by type,
   size and tree. Write it down. Delete nothing, move nothing, decide nothing.
   Expect the answer to surprise you: the photograph library's "OneDrive holds
   140 GB" turned out to be 1.1 GB.
2. **`04_inventory` - one row per file** with every signal: path, size, hash,
   dates from three sources, extension, origin tree.
3. **`02_ingest` - bring them in once**, content-deduplicated, hardlinked where
   the volume allows so a second copy costs no bytes.
4. **`03_dating`** - filename, then folder, then the document's own text.
5. **`05_classify`** - what KIND: statement, contract, scan, receipt, export.
6. **`06_index`** - full-text search over the documents themselves. Unlike
   photographs, they mostly say what they are, for free.
7. **`07_structure`** - the canonical tree, and a REVIEWABLE PROPOSAL mapping
   files into it. Never an automatic move.
8. **`08_reclaim`** - free the space. The only stage that destroys.
9. **`09_mirror`** - the same structure, identically, on every drive.

---

## The three traps that will bite first

These are not hypothetical; each one cost hours in the other engine.

**Versions are not duplicates.** `contract_v2_FINAL_signed.pdf` next to
`contract_v2_FINAL.pdf` is the normal case for documents and has no equivalent
in a camera roll. Byte-identical dedupe is safe; anything cleverer must ask a
human. `safety.looks_like_a_version()` exists to make a tool refuse rather than
guess.

**There is no EXIF.** Nearly every document will land undated unless the folder
it came from is named with a year. Name the folders BEFORE ingesting - it is
minutes of work and the only cheap date you will ever get.

**A derived record goes stale the moment the disk changes.** In the other engine
an index was rebuilt from three CSVs that nobody had updated, and it confidently
reported 82,104 files after 581 had demonstrably been added. Any record keyed on
PATH is a claim about the disk, not the disk.

---

## Rules inherited without argument

Read `docs/LEARNINGS.md` before changing any deletion, dedupe or classification
rule. The short version:

- a path is never grounds to delete
- only a whole-file hash may declare a duplicate
- a surviving copy must be a different inode
- re-verify at the instant of deletion; a report is never evidence
- journal before destroying, and fsync it
- an absent input stops the run
- an unreadable file is unproven, not innocent
- long work is resumable and writes as it goes
