"""Deletion guard.

Carried from contentarchives, where this module exists because a path-substring
rule once permanently destroyed 45 irreplaceable personal files.

THE DESIGN PRINCIPLE: nothing in this toolkit may decide a deletion from what a
path *looks like*. Deletion is allowlist-only, and every allowed reason is a
narrow, explicit case a human has reasoned about.

WHY DOCUMENTS NEED THIS MORE, NOT LESS

Photographs announce themselves. A document archive is full of things that look
disposable and are not: `Document (1).pdf` that is the only signed copy,
`untitled.docx` that is a will, `scan0043.pdf` that is a birth certificate.
Every heuristic that felt safe on a camera roll - "it's small", "it's a
screenshot", "it's a temp file" - is a loaded gun here, because the naming
carries almost no signal about the value.

So GARBAGE IS A CLOSED LIST. Not "small files", not "looks like junk". A
category earns its place only if the file cannot carry irreplaceable content by
construction, and each one is named.
"""

from __future__ import annotations

import os
import re

__all__ = ["DeletionRefused", "Guard", "GARBAGE", "looks_like_a_version"]


class DeletionRefused(RuntimeError):
    """Raised whenever a deletion is not explicitly permitted.

    Never catch this to 'try something else'. It means the caller's reasoning
    was wrong, and the correct response is to stop, not to find another route
    to the same unlink.
    """


# Categories that cannot, by construction, be the only copy of anything that
# matters. Each is here because it was reasoned about once, in the open.
GARBAGE = {
    "zero-byte":        "a file of length 0 holds nothing",
    "thumbs-db":        "Windows thumbnail cache, regenerated on demand",
    "ds-store":         "macOS folder metadata, regenerated on demand",
    "desktop-ini":      "Windows folder view settings",
    "temp-office-lock": "~$ prefixed Office lock file, meaningless once closed",
}

# Versioned names. NOT garbage - the opposite. Recorded so that a dedupe which
# is about to collapse these can be stopped and made to explain itself.
_VERSION_RX = re.compile(
    r"(_v\d+|\bv\d+\b|[ _-]final\b|[ _-]draft\b|[ _-]signed\b|[ _-]copy\b|"
    r"\(\d+\)|[ _-]rev[ _-]?\d+)", re.I)


def looks_like_a_version(name: str) -> bool:
    """True when a filename suggests it is one of several deliberate versions.

    `contract_v2_FINAL_signed.pdf` and `contract_v2_FINAL.pdf` are not a file
    and its duplicate; they are two documents whose difference may be the whole
    point. This never authorises anything - it is a reason to REFUSE a
    near-duplicate collapse and ask a human.
    """
    return bool(_VERSION_RX.search(name))


class Guard:
    """Decides nothing on its own. Every method must be given its evidence."""

    def __init__(self, protected_roots: list[str] | None = None) -> None:
        # Trees that may never be deleted from, whatever the evidence.
        self.protected = [os.path.normcase(os.path.normpath(p))
                          for p in (protected_roots or [])]

    def _inside_protected(self, path: str) -> str | None:
        p = os.path.normcase(os.path.normpath(path))
        for root in self.protected:
            if p == root or p.startswith(root + os.sep):
                return root
        return None

    def check_deletable(self, path: str, reason: str) -> None:
        """Raise unless this specific path may be deleted for this reason."""
        if not reason:
            raise DeletionRefused("no reason given for deleting {}".format(path))
        root = self._inside_protected(path)
        if root:
            raise DeletionRefused(
                "{} is inside the protected tree {}".format(path, root))

    def check_garbage(self, path: str, category: str) -> None:
        if category not in GARBAGE:
            raise DeletionRefused(
                "unknown garbage category {!r} for {}".format(category, path))
        if category == "zero-byte":
            try:
                if os.path.getsize(path) != 0:
                    raise DeletionRefused(
                        "{} is not zero-byte, category does not apply".format(path))
            except OSError as e:
                raise DeletionRefused("cannot size {}: {}".format(path, e))
