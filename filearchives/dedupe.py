"""Three-tier duplicate detection: cheap to rule out, expensive to confirm.

Carried from contentarchives, where it was paid for. See docs/LEARNINGS.md 2.

    1. size            - from the directory index, no I/O. A size that exists
                         nowhere in the archive CANNOT be a duplicate. This
                         clears most candidates for free.
    2. head+tail sig   - first and last 256 KB. Rules out most size collisions
                         after reading half a megabyte.
    3. whole-file hash - the ONLY thing permitted to *declare* a duplicate.

Filename is never part of the decision. Two different files sharing a name and
an exact byte count are rare but real, and the failure mode is silent data loss.

WHY THIS MATTERS MORE FOR DOCUMENTS THAN IT DID FOR PHOTOGRAPHS

A camera gives its files distinct names by construction. Documents do the
opposite: `invoice.pdf`, `scan.pdf`, `Document (1).pdf` and `untitled.docx`
recur across decades and across drives, describing completely different things.
Any dedupe that consults the name here is not a dedupe, it is a shredder.

The reverse trap is also stronger here. `contract_v2_FINAL_signed.pdf` and
`contract_v2_FINAL.pdf` are NOT duplicates - they are versions, and the second
is not junk. Byte-identical dedupe is the first pass, never the whole answer,
and near-duplicate detection is a separate and much more careful question that
this module deliberately does not attempt.
"""

from __future__ import annotations

import hashlib
import os
from collections import defaultdict

__all__ = ["Index", "file_signature", "file_hash", "SIG_BYTES"]

SIG_BYTES = 256 * 1024
CHUNK = 8 * 1024 * 1024


def _lp(p: str) -> str:
    return p if p.startswith("\\\\?\\") else "\\\\?\\" + p


def file_hash(path: str, chunk: int = CHUNK) -> str:
    """blake2b-256 of the whole file.

    Whole-file, not head+tail. A cheap signature is fine for building a
    shortlist and is not fine for identity.
    """
    h = hashlib.blake2b(digest_size=32)
    with open(_lp(path), "rb", buffering=0) as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def file_signature(path: str, size: int | None = None) -> str | None:
    """First and last 256 KB. Rules a candidate OUT; never rules one in."""
    try:
        if size is None:
            size = os.path.getsize(_lp(path))
        h = hashlib.blake2b(digest_size=16)
        with open(_lp(path), "rb", buffering=0) as f:
            h.update(f.read(SIG_BYTES))
            if size > SIG_BYTES * 2:
                f.seek(max(0, size - SIG_BYTES))
                h.update(f.read(SIG_BYTES))
        return h.hexdigest()
    except OSError:
        return None


class Index:
    """Sizes and hashes of what is already held, for ruling candidates out.

    `add` records a file. `is_duplicate_of` returns the held path holding
    identical content, or None - and it only ever says yes on a whole-file
    hash.

    An unreadable candidate returns None from `file_hash`'s caller and must be
    treated as UNPROVEN, never as "not a duplicate". In contentarchives that
    exact confusion admitted 222 GB of byte-identical duplicates: a candidate
    that would not open hashed to None, `None == other` was False, and every
    unreadable file silently became new.
    """

    def __init__(self) -> None:
        self.by_size: dict[int, list[str]] = defaultdict(list)
        self.by_hash: dict[str, str] = {}

    def add(self, path: str, size: int, digest: str | None = None) -> None:
        self.by_size[size].append(path)
        if digest:
            self.by_hash[digest.lower()] = path

    def size_is_novel(self, size: int) -> bool:
        """True when nothing held shares this size, so no I/O is needed."""
        return size not in self.by_size

    def is_duplicate_of(self, path: str, size: int) -> str | None:
        if self.size_is_novel(size):
            return None
        digest = file_hash(path)
        return self.by_hash.get(digest.lower())
