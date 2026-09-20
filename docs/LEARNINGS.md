# Learnings

Rules this engine enforces, each one paid for. Most were paid for in
`contentarchives` while consolidating 82,000 photographs and reclaiming 1,114 GB;
they are carried here because the lessons are about **moving a large number of
irreplaceable files without losing any**, which is not a problem specific to
photographs.

`tests/test_stage_contracts.py` fails the build when a learning has no owner.
Adding one here without a stage claiming it is a build failure, on purpose.

---

## 1. A path is never grounds to delete

A path-substring rule once permanently destroyed 45 irreplaceable personal
files. Nothing in this toolkit may decide a deletion from what a path *looks
like*. Deletion is allowlist-only and every allowed reason is narrow, named, and
reasoned about by a human in advance.

This matters MORE for documents than it did for photographs. A camera roll
announces itself; a document archive is full of things that look disposable and
are not - `Document (1).pdf` that is the only signed copy, `untitled.docx` that
is a will, `scan0043.pdf` that is a birth certificate. Every heuristic that felt
safe on photographs - "it's small", "it's a temp file" - is a loaded gun here,
because the naming carries almost no signal about the value.

## 2. Size rules out, only a hash rules in

Three tiers, cheap to expensive: a size that exists nowhere in the archive
cannot be a duplicate and costs no I/O to dismiss; a head+tail signature clears
most size collisions after half a megabyte; and only a whole-file hash may
DECLARE a duplicate.

Used in the other direction it is the thing that makes a 100,000-file dedupe
finish at all: most candidates never get read.

## 3. Equal size is not equal content, and name plus size is not identity

Two different files sharing a name and an exact byte count are rare and real,
and the failure mode is silent data loss. For documents this is not an edge
case: `invoice.pdf`, `scan.pdf` and `Document (1).pdf` recur across decades and
across drives, describing completely different things.

## 4. Two names for one inode are not two copies

Deleting one hardlink frees nothing, and a caller who believed it had two copies
now has none in the way that matters. A surviving copy must be a DIFFERENT
inode, not merely a different path. Measured once in contentarchives: 322.5 GB
of one drive was hardlinked, and a size-based reading suggested 300 GB of
reclaim that did not exist.

## 5. A report is never evidence; the filesystem at the unlink is

Every near-miss came from a deletion justified by something true EARLIER. A
triage report listing 6,217 redundant files was written while an ingest was
still running, so by the time it was acted on the archive had moved. Re-read and
re-hash at the instant of deletion, even when the caller is certain.

## 6. The journal is written and fsynced BEFORE the file goes

A deletion that is not recorded did not happen, as far as anyone auditing later
can tell - and the record has to survive the kill that interrupts the run.

## 7. An absent input stops the run; it is never read as empty

A mistyped path that yields "0 rows" looks exactly like a job that legitimately
had nothing to do. The second is a fine outcome; the first is a bug that will be
believed.

## 8. An unreadable file is UNPROVEN, never "not a duplicate"

In contentarchives this exact confusion admitted 222 GB of byte-identical
duplicates: a candidate that would not open hashed to `None`, `None == other`
was False, and every unreadable file silently became new. A file that cannot be
read has not been cleared - it has not been examined.

## 9. Long work is resumable and writes as it goes

This machine kills long jobs under memory pressure - four died inside minutes in
one session. A job that holds its results in memory and writes at the end loses
everything. Flush on a cadence and at every exit path, and make a re-run skip
what is already recorded.

## 10. A summary a person approves must be computed over the set the action uses

A purge printed "117 tag rows" and removed fewer, because the COUNT was computed
over one set and the ACTION keyed on another. An overstating report is worse
than an understating one: the operator believes something was destroyed that
still exists.

## 11. "The archive lacks it" is not "someone would miss it"

6,350 files existed only outside the library; the number that actually mattered
was 581. The rest were screenshots, build output, caches, one downloaded film
that was 55% of the gigabytes, and the same file counted once per copy.
Narrowing is a step in its own right, and it belongs in separate tools with
separate, arguable rules rather than one clever filter.

## 12. A version is not a duplicate

`contract_v2_FINAL_signed.pdf` and `contract_v2_FINAL.pdf` are not a file and
its copy - they are two documents whose difference may be the entire point.
Byte-identical dedupe is the first pass and never the whole answer.
Near-duplicate collapse is a separate question that must ask a human.

This has no equivalent in the photograph library, and it is the single largest
way this engine differs from the one it was carried from.

## 13. Documents carry no EXIF, so the folder name is the date of last resort

A photograph records its own moment. A PDF usually does not. Dating falls back
through filename, then folder, then the document's own text - and a folder
somebody already named with a year is the cheapest reliable date available.
Naming the folders BEFORE ingesting costs minutes and is the difference between
a dated archive and an undated pile.

## 14. Every learning has an owner, or the build fails

Fifty written rules did not stop eleven of them being broken in one afternoon,
because the rules lived in a document and reached new machinery only through
whoever remembered them. A learning here is claimed by a stage, and the claim
names the function or test that enforces it. A claim whose enforcement has been
deleted fails the build.
