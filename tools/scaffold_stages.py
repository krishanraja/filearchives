r"""Create the conveyor: nine stages and guards/, each with its STAGE.md.

    python tools/scaffold_stages.py

Run once at the start of the engine's life. Every STAGE.md it writes carries the
six sections tests/test_stage_contracts.py requires, and between them the ten
files claim all 14 learnings - so the build passes the moment the conveyor
exists, and fails again the instant a learning is added without an owner.

Written as a generator rather than ten hand-made files because the shape is
identical and the differences are the content. It refuses to overwrite: once a
STAGE.md has been edited by a human it is theirs, not this script's.
"""
from __future__ import annotations

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STAGES = [
    ("01_sources", "01 sources",
     "Find every tree that holds documents, and record what was seen.",
     ["the drives on this machine, and any mount that is attached"],
     ["a survey per root: counts and bytes by type, written down",
      "`SOURCES.csv` - one row per tree, with what it appears to hold"],
     ["a survey acts on nothing: it counts, it does not move or delete",
      "an absent or unmounted root STOPS the survey, never reads as empty",
      "a figure from a syncing mount carries its timestamp and is re-measured"],
     [("`stages/01_sources/survey_roots.py`",
       "walk a tree and count documents by extension, size band and folder - "
       "metadata only, so a cloud placeholder is measured without being "
       "downloaded")],
     ["none yet - the first tool written here must arrive with one"],
     [(7, "an absent root stops the survey rather than reporting zero",
       "prose-only"),
      (11, "a survey reports what is THERE, and narrowing to what MATTERS is a "
           "separate, arguable step", "prose-only")]),

    ("02_ingest", "02 ingest",
     "Bring a document into the archive once, deduplicated by content.",
     ["a tree chosen by 01 sources", "the archive and its hash index"],
     ["files placed in the archive, hardlinked where the volume allows",
      "a journal of what was added and what was refused as a duplicate"],
     ["a duplicate is declared only on a whole-file hash, never a name",
      "an unreadable candidate is UNPROVEN and is never admitted as new",
      "a VERSION is not a duplicate and is never collapsed without a human"],
     [("`filearchives/dedupe.py`",
       "three tiers - size rules out for free, a head+tail signature clears "
       "most collisions, and only a whole-file hash may declare a duplicate")],
     ["none yet"],
     [(2, "size rules a candidate out; only a hash rules one in",
       "`code:filearchives/dedupe.py:def is_duplicate_of`"),
      (3, "equal size is not equal content, and the name is never consulted",
       "`code:filearchives/dedupe.py:Filename is never part of the decision`"),
      (8, "an unreadable file is unproven, never 'not a duplicate'",
       "`code:filearchives/dedupe.py:treated as UNPROVEN`"),
      (12, "a version is refused rather than collapsed",
       "`code:filearchives/safety.py:def looks_like_a_version`")]),

    ("03_dating", "03 dating",
     "Give every document a date, from the best signal available.",
     ["the inventory, and the documents themselves"],
     ["a date per file, with the SOURCE of that date recorded beside it"],
     ["the source of a date is always recorded; a guess is never silent",
      "filename, then folder, then document text - in that order of trust",
      "an undated file stays undated rather than receiving an invented date"],
     [("`stages/03_dating/date_from_signals.py`",
       "filename patterns, then the folder name, then the document's own text")],
     ["none yet"],
     [(13, "no EXIF exists, so the folder name is the date of last resort and "
           "is recorded as such", "prose-only")]),

    ("04_inventory", "04 inventory",
     "One row per document, carrying every signal about it.",
     ["the archive on disk"],
     ["`INVENTORY.csv` - path, size, hash, dates, type, origin tree"],
     ["the disk is the truth; the inventory is a claim about it",
      "a record keyed on PATH is stale the moment anything moves",
      "long work writes as it goes and resumes; it never holds results in RAM"],
     [("`stages/04_inventory/build_inventory.py`",
       "one row per file with every signal, written incrementally")],
     ["none yet"],
     [(9, "the inventory is built in resumable slices that flush as they go",
       "prose-only")]),

    ("05_classify", "05 classify",
     "Decide what KIND of document each file is.",
     ["the inventory, and the documents' own text"],
     ["a type per file: statement, contract, scan, receipt, export, other"],
     ["a classification is evidence for a human, never an instruction to move",
      "a type that cannot be determined is 'unknown', never a best guess"],
     [("`stages/05_classify/classify_documents.py`",
       "type from extension, filename and the document's own first page")],
     ["none yet"],
     []),

    ("06_index", "06 index",
     "Make the archive searchable by its own contents.",
     ["the inventory and the documents"],
     ["a full-text index over document text, and the metadata beside it"],
     ["the index is derived and disposable; it is never the source of truth",
      "a rebuild reads the disk, not another derived record"],
     [("`stages/06_index/build_index.py`",
       "full-text search over extracted document text")],
     ["none yet"],
     []),

    ("07_structure", "07 structure",
     "The canonical folder tree, and the proposal that maps files into it.",
     ["the inventory, the types from 05, the dates from 03"],
     ["`STRUCTURE-PROPOSAL.csv` - every file, and where it would go"],
     ["a proposal is REVIEWED before anything moves; never an automatic move",
      "the proposal reports exactly what it will do, over the same set it acts on",
      "a destination map is proven injective before a single file is moved"],
     [("`stages/07_structure/propose_layout.py`",
       "map every file to its place in the canonical tree, as a reviewable list")],
     ["none yet"],
     [(10, "the proposal a person approves is computed over the same set the "
           "move will act on", "prose-only")]),

    ("08_reclaim", "08 reclaim",
     "Free space by removing bytes that provably exist elsewhere - and nothing else.",
     ["the archive, the hash index, and evidence of surviving copies"],
     ["deletions, each journalled with its evidence BEFORE the unlink"],
     ["deletion goes through the allowlist guard; garbage is a closed list",
      "a duplicate needs identical content AND a distinct inode",
      "the journal row is fsynced before the file is removed",
      "the survivor is re-hashed at the moment of deletion"],
     [("`filearchives/safety.py`", "the deletion allowlist, and the version "
                                   "detector that makes a tool refuse"),
      ("`guards/guarded_delete.py`",
       "the only sanctioned delete: proven survivor, different inode, "
       "re-hashed now, journalled first")],
     ["none yet"],
     [(1, "a path is never grounds to delete",
       "`code:filearchives/safety.py:class Guard`"),
      (4, "a surviving copy must be a different inode",
       "`code:guards/guarded_delete.py:same inode`"),
      (5, "the filesystem at the instant of the unlink is the only evidence",
       "`code:guards/guarded_delete.py:Re-verified NOW`"),
      (6, "the journal is fsynced before the file goes",
       "`code:guards/guarded_delete.py:def _journal`")]),

    ("09_mirror", "09 mirror",
     "The same structure, identically, on every drive.",
     ["the canonical archive"],
     ["an identical tree on each target drive, verified"],
     ["a copy is verified by re-derivation, never by reading back what was written",
      "a mirror that only ADDS diverges silently; removal is explicit machinery"],
     [("`stages/09_mirror/mirror_tree.py`",
       "copy the canonical tree to a target drive and prove it arrived")],
     ["none yet"],
     []),
]

GUARDS = ("guards", "guards",
          "The lessons as code, and the machinery that runs long work safely.",
          ["none of its own; imported by every stage"],
          ["exit codes and STOPPING messages that halt work before it "
           "produces wrong output"],
          ["an absent input stops the run; it never reads as empty",
           "a reader never sees a partially written file",
           "nothing is deleted without proof, at the moment of deletion"],
          [("`guards/files.py`", "atomic writes, absent-input stops, whole lines"),
           ("`guards/guarded_delete.py`", "the only sanctioned delete"),
           ("`stagepath.py`",
            "where every stage lives, so no file hardcodes a relative depth"),
           ("`tools/scaffold_stages.py`",
            "wrote this conveyor once, and refuses to overwrite a STAGE.md a "
            "human has since edited")],
          ["`tests/test_stage_contracts.py`"],
          [(14, "every learning is owned, and a claim whose enforcement has "
                "been deleted fails the build",
            "`test:tests/test_stage_contracts.py:has no owner - a stage must claim it`"),
           (7, "an absent input raises rather than returning empty",
            "`code:guards/files.py:class MissingInput`")])


def render(slug, title, purpose, inputs, outputs, invariants, code, tests,
           lessons) -> str:
    L = ["# {}".format(title), "", purpose, "", "## Inputs"]
    L += ["- " + i for i in inputs]
    L += ["", "## Outputs"] + ["- " + o for o in outputs]
    L += ["", "## Invariants"] + ["- " + v for v in invariants]
    L += ["", "## Code", "| file | role |", "|---|---|"]
    L += ["| {} | {} |".format(f, r) for f, r in code]
    L += ["", "## Tests"] + ["- " + t for t in tests]
    L += ["", "## Lessons", "| # | what this stage does about it | enforced by |",
          "|---|---|---|"]
    for num, what, how in lessons:
        L.append("| {} | {} | {} |".format(num, what, how))
    if not lessons:
        L.append("| - | none claimed yet | - |")
    L.append("")
    return "\n".join(L)


def main() -> int:
    made = skipped = 0
    for entry in STAGES:
        slug = entry[0]
        d = os.path.join(ROOT, "stages", slug)
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, "STAGE.md")
        if os.path.exists(p):
            skipped += 1
            continue
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(render(*entry))
        made += 1

    p = os.path.join(ROOT, "guards", "STAGE.md")
    if os.path.exists(p):
        skipped += 1
    else:
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write(render(*GUARDS))
        made += 1

    print("  STAGE.md written : {}".format(made))
    print("  already present  : {} (left alone - a human owns them now)".format(
        skipped))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
