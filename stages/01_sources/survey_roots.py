r"""What documents are out there, and where? Count them. Decide nothing.

    python survey_roots.py --root "E:\" --root "G:\My Drive"
    python survey_roots.py --all-drives
    python survey_roots.py --root "E:\" --report

The first stage exists because every estimate made without measuring in
contentarchives was wrong - usually by a factor of ten, once by a hundredfold,
and that last one got published to Krish as a fact before anyone re-checked it.

So this walks, counts, and writes down. It moves nothing, deletes nothing,
proposes nothing, and opens no file: `os.path.getsize` is metadata, so a cloud
placeholder is measured without being downloaded. A tree that would cost 40 GB
of hydration to survey costs nothing here.

WHAT IT REFUSES TO DO

  It does not decide what a document IS. `.pdf` in a `node_modules` folder and
  `.pdf` in `Scans 2011` are counted separately by folder and left that way,
  because a classification made during a survey becomes a fact nobody revisits.

  It does not read a missing root as an empty one. An unmounted drive that
  reports zero files looks exactly like a drive with nothing on it, and the
  second is a fine answer while the first is a bug that will be believed
  (learning 7).

  It does not hide what it could not see. `os.walk` swallows directory errors
  by default - which, on a cloud mount, silently skips whole trees and then
  reports success. Errors are counted and printed.

EVERY FIGURE CARRIES ITS TIMESTAMP (learning 11's neighbour). A count taken from
a syncing mount describes a filesystem that may not exist by the time anyone
reads it, so the row records when it was taken.
"""

from __future__ import annotations

import argparse
import collections
import csv
import datetime as dt
import io
import os
import string
import sys

_d = os.path.dirname(os.path.abspath(__file__))
while _d != os.path.dirname(_d) and not os.path.exists(
        os.path.join(_d, "stagepath.py")):
    _d = os.path.dirname(_d)
sys.path.insert(0, _d)

import stagepath  # noqa: E402,F401
from files import MissingInput  # noqa: E402
from paths import workspace, roots as configured_roots, NotConfigured  # noqa: E402

# WHERE RECORDS GO IS A PROPERTY OF THE MACHINE, NOT OF THIS FILE.
#
# This used to read `os.environ.get("FILEARCHIVES_SOURCES", r"D:\_FileAudit\...")`
# - a default that works on exactly one machine and is silently wrong on every
# other one, which is the failure this engine exists to prevent. A path that
# does not exist does not raise; it reads as empty, and empty reads as
# "nothing to do".
#
# The resolver stops with instructions when a machine is unconfigured.

# Documents. Deliberately NOT media - photographs and video belong to
# contentarchives, and the two engines must not fight over the same trees.
DOCS = {
    ".pdf", ".doc", ".docx", ".rtf", ".odt", ".txt", ".md",
    ".xls", ".xlsx", ".csv", ".ods", ".numbers",
    ".ppt", ".pptx", ".key", ".odp",
    ".eml", ".msg", ".vcf", ".ics",
    ".epub", ".mobi", ".djvu",
    ".pages", ".tex", ".xml", ".json", ".html", ".htm",
}
# Counted separately: they may be scans of documents, or they may be
# photographs that belong to the other engine. The survey does not guess.
MAYBE_SCANS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".heic"}

SKIP_DIRS = {"$recycle.bin", "system volume information", "__pycache__",
             ".git", "node_modules", "found.000", "windows",
             "program files", "program files (x86)", "$windows.~ws"}

BANDS = [(0, "0-10 KB", 10 * 1024), (1, "10-100 KB", 100 * 1024),
         (2, "100 KB-1 MB", 1 << 20), (3, "1-10 MB", 10 << 20),
         (4, "10-100 MB", 100 << 20), (5, "over 100 MB", 1 << 62)]


def band(size: int) -> str:
    for _, name, ceiling in BANDS:
        if size < ceiling:
            return name
    return "over 100 MB"


def drives() -> list[str]:
    out = []
    for letter in string.ascii_uppercase:
        root = letter + ":" + os.sep
        if os.path.isdir(root):
            out.append(root)
    return out


def survey(root: str) -> dict:
    if not os.path.isdir(root):
        raise MissingInput(
            "root is absent or not mounted: {} - refusing to report it as "
            "empty".format(root))

    errors: list = []
    docs = collections.Counter()
    doc_bytes = collections.Counter()
    scans = 0
    scan_bytes = 0
    other = 0
    by_folder = collections.Counter()
    folder_bytes = collections.Counter()
    bands = collections.Counter()

    for dp, dns, fns in os.walk(root, onerror=errors.append):
        dns[:] = [d for d in dns if d.lower() not in SKIP_DIRS]
        top = os.path.relpath(dp, root).split(os.sep)[0]
        for fn in fns:
            ext = os.path.splitext(fn)[1].lower()
            try:
                size = os.path.getsize(os.path.join(dp, fn))
            except OSError:
                continue
            if ext in DOCS:
                docs[ext] += 1
                doc_bytes[ext] += size
                by_folder[top] += 1
                folder_bytes[top] += size
                bands[band(size)] += 1
            elif ext in MAYBE_SCANS:
                scans += 1
                scan_bytes += size
            else:
                other += 1

    return dict(root=root, docs=docs, doc_bytes=doc_bytes, scans=scans,
                scan_bytes=scan_bytes, other=other, by_folder=by_folder,
                folder_bytes=folder_bytes, bands=bands, errors=len(errors))


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", action="append", default=[])
    ap.add_argument("--all-drives", action="store_true",
                    help="every mounted drive letter, configured or not")
    ap.add_argument("--all-configured", action="store_true",
                    help="the sources named in this machine's workspace")
    ap.add_argument("--report", action="store_true",
                    help="print what was already surveyed and stop")
    a = ap.parse_args()

    # The workspace decides where records live. A machine that has not been
    # configured stops here with instructions, rather than defaulting to a
    # drive letter that is right on one machine and silently wrong elsewhere.
    try:
        w = workspace()
    except NotConfigured as e:
        print(e)
        return 2
    OUT = w.sources_csv

    if a.report:
        if not os.path.exists(OUT):
            print("nothing surveyed yet")
            return 1
        for r in csv.DictReader(io.open(OUT, encoding="utf-8", newline="")):
            print("  {:<22} {:>9,} docs  {:>9.2f} GB   taken {}".format(
                r["Root"][:22], int(r["Documents"]),
                int(r["DocumentBytes"]) / (1 << 30), r["When"]))
        return 0

    if a.all_configured:
        roots = configured_roots(w)
        if not roots:
            print("no configured source is mounted - nothing to survey.")
            print("  This is NOT the same as 'the sources are empty'.")
            return 1
    else:
        roots = a.root or (drives() if a.all_drives else [])
    if not roots:
        print("name a --root, --all-configured, or --all-drives")
        return 1

    rows = []
    for root in roots:
        try:
            s = survey(root)
        except MissingInput as e:
            print("  STOPPED: {}".format(e))
            return 1

        n = sum(s["docs"].values())
        b = sum(s["doc_bytes"].values())
        print()
        print("{}".format(root))
        print("  documents        : {:>9,}   {:>8.2f} GB".format(
            n, b / (1 << 30)))
        print("  images (may be scans, may belong to contentarchives): "
              "{:,}   {:.2f} GB".format(s["scans"], s["scan_bytes"] / (1 << 30)))
        print("  everything else  : {:>9,}".format(s["other"]))
        if s["errors"]:
            print("  DIRECTORIES THAT COULD NOT BE READ: {} - this survey is "
                  "a LOWER BOUND".format(s["errors"]))
        if n:
            print("  commonest types  : {}".format(
                ", ".join("{} {:,}".format(e, c)
                          for e, c in s["docs"].most_common(6))))
            print("  by size          : {}".format(
                ", ".join("{} {:,}".format(k, v)
                          for k, v in s["bands"].most_common())))
            print("  biggest trees    :")
            for folder, cnt in s["by_folder"].most_common(6):
                print("      {:>8.2f} GB  {:>7,} docs  {}".format(
                    s["folder_bytes"][folder] / (1 << 30), cnt, folder[:48]))

        rows.append([root, n, b, s["scans"], s["scan_bytes"], s["other"],
                     s["errors"],
                     dt.datetime.now().isoformat(timespec="seconds")])

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    fresh = not os.path.exists(OUT)
    with io.open(OUT, "a", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        if fresh:
            w.writerow(["Root", "Documents", "DocumentBytes", "Images",
                        "ImageBytes", "Other", "UnreadableDirs", "When"])
        w.writerows(rows)
        fh.flush()
        os.fsync(fh.fileno())

    print()
    print("written: {}".format(OUT))
    print()
    print("This is a COUNT, not a plan. Nothing has been moved, and no file has")
    print("been opened. Decide what to ingest from it; do not act on it blind.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
