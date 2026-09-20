r"""The only sanctioned way to delete anything.

Carried from contentarchives. THE RULE: nothing is deleted unless, at the
moment of deletion, either

  (a) a SURVIVING COPY is proven to exist - a different inode, holding
      byte-identical content, re-hashed right now and readable; or
  (b) the file is GENUINE GARBAGE by a narrow, named category.

Everything else raises. There is no third path, no "probably fine", and no flag
to override it.

WHY IT IS BUILT THIS WAY

Every near-miss in contentarchives came from a deletion justified by something
that was true EARLIER:

  - a path-substring rule deleted 45 irreplaceable personal files
  - a zip looked redundant; 19 of its 20 videos were, and the 20th was the only
    full-quality copy of a file the library held as a truncation
  - a triage report listing 6,217 redundant files was written while an ingest
    was still running, so by the time it was acted on the library had moved

So a report is never evidence. An index is never evidence. Only the filesystem
as it is at the instant of the unlink is evidence, and this module re-reads it
every time even when the caller is certain.

THE INODE CHECK IS NOT OPTIONAL

Two paths can hold identical content because they are hardlinks - one set of
bytes wearing two names. Deleting one then frees nothing, and if the caller
believed it had two copies it now has none in the way that matters.

THE JOURNAL IS WRITTEN AND FSYNCED BEFORE THE FILE GOES

A deletion that is not recorded did not happen, as far as anyone auditing later
can tell - and the record has to survive the kill that interrupts the run.
"""

from __future__ import annotations

import csv
import datetime as dt
import hashlib
import io
import os
import sys

_d = os.path.dirname(os.path.abspath(__file__))
while _d != os.path.dirname(_d) and not os.path.exists(
        os.path.join(_d, "stagepath.py")):
    _d = os.path.dirname(_d)
sys.path.insert(0, _d)

import stagepath  # noqa: E402,F401
from safety import DeletionRefused, GARBAGE  # noqa: E402

__all__ = ["delete_with_surviving_copy", "delete_garbage", "DeletionRefused",
           "JOURNAL"]

JOURNAL = os.environ.get("FILEARCHIVES_JOURNAL",
                         r"D:\_FileAudit\deletions.csv")
CHUNK = 8 * 1024 * 1024


def _lp(p: str) -> str:
    return p if p.startswith("\\\\?\\") else "\\\\?\\" + p


def _hash(path: str) -> str:
    h = hashlib.blake2b(digest_size=32)
    with open(_lp(path), "rb", buffering=0) as f:
        while True:
            b = f.read(CHUNK)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def _journal(path: str, size: int, reason: str, evidence: str) -> None:
    os.makedirs(os.path.dirname(JOURNAL), exist_ok=True)
    fresh = not os.path.exists(JOURNAL)
    with io.open(JOURNAL, "a", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        if fresh:
            w.writerow(["When", "Path", "Bytes", "Reason", "Evidence"])
        w.writerow([dt.datetime.now().isoformat(timespec="seconds"),
                    path, size, reason, evidence])
        f.flush()
        os.fsync(f.fileno())


def delete_with_surviving_copy(victim: str, survivor: str, reason: str) -> int:
    """Delete `victim` only if `survivor` provably holds the same bytes.

    Re-verified NOW, from the filesystem, regardless of what the caller thinks
    it knows. Returns bytes freed. Raises DeletionRefused on any doubt.
    """
    if not os.path.exists(_lp(victim)):
        raise DeletionRefused("victim already gone: {}".format(victim))
    if not os.path.exists(_lp(survivor)):
        raise DeletionRefused("SURVIVOR MISSING - refusing: {}".format(survivor))

    vs = os.stat(_lp(victim))
    ss = os.stat(_lp(survivor))

    if (vs.st_dev, vs.st_ino) == (ss.st_dev, ss.st_ino):
        raise DeletionRefused(
            "same inode - these are hardlinks, not two copies: {}".format(victim))
    if vs.st_size != ss.st_size:
        raise DeletionRefused(
            "sizes differ ({} vs {}) - not a copy: {}".format(
                vs.st_size, ss.st_size, victim))
    if _hash(victim) != _hash(survivor):
        raise DeletionRefused(
            "content differs despite equal size: {}".format(victim))

    try:
        with open(_lp(survivor), "rb") as f:
            f.seek(max(0, ss.st_size - 4096))
            f.read()
    except OSError as e:
        raise DeletionRefused(
            "survivor unreadable ({}): {}".format(e, survivor))

    _journal(victim, vs.st_size, reason,
             "surviving copy {} verified at deletion: same blake2b-256, "
             "{:,} bytes, different inode".format(survivor, vs.st_size))
    os.remove(_lp(victim))
    return vs.st_size


def delete_garbage(path: str, category: str, reason: str) -> int:
    """Delete a file that cannot be the only copy of anything that matters."""
    if category not in GARBAGE:
        raise DeletionRefused(
            "unknown garbage category {!r}: {}".format(category, path))
    if not os.path.exists(_lp(path)):
        raise DeletionRefused("already gone: {}".format(path))
    st = os.stat(_lp(path))
    if category == "zero-byte" and st.st_size != 0:
        raise DeletionRefused(
            "{} is {} bytes, not zero - category does not apply".format(
                path, st.st_size))
    _journal(path, st.st_size, reason,
             "garbage category {!r}: {}".format(category, GARBAGE[category]))
    os.remove(_lp(path))
    return st.st_size
