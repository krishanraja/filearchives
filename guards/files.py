r"""Atomic writes, absent-input stops, and whole lines.

Carried from contentarchives. Three rules, each from a real failure there:

  A READER NEVER SEES A PARTIAL FILE. Write to a temp file beside the target,
  fsync it, then os.replace. A half-written CSV that another tool reads mid-way
  is indistinguishable from a short one.

  AN ABSENT INPUT STOPS THE RUN. It is never read as empty. A mistyped path
  that yields "0 rows" looks exactly like a job that legitimately had nothing
  to do, and the second is a fine outcome while the first is a bug that will be
  believed.

  APPEND-ONLY WORK IS FLUSHED AS IT GOES. A long job that holds its results in
  memory and writes at the end loses everything when the machine kills it, and
  this machine kills long jobs. Flush on a cadence, and at every exit path.
"""

from __future__ import annotations

import contextlib
import io
import os
import sys

__all__ = ["atomic_writer", "require_file", "require_dir", "complete_lines",
           "MissingInput"]


class MissingInput(RuntimeError):
    """An input that must exist does not. Never caught to substitute a default."""


def require_file(path: str, why: str = "") -> str:
    if not os.path.exists(path):
        raise MissingInput(
            "required file is absent: {}{}".format(path, "  - " + why if why else ""))
    return path


def require_dir(path: str, why: str = "") -> str:
    if not os.path.isdir(path):
        raise MissingInput(
            "required directory is absent: {}{}".format(
                path, "  - " + why if why else ""))
    return path


@contextlib.contextmanager
def atomic_writer(path: str, encoding: str = "utf-8", newline: str = ""):
    """Write to a temp file beside `path`, fsync, then promote it."""
    tmp = path + ".writing"
    fh = io.open(tmp, "w", encoding=encoding, newline=newline)
    try:
        yield fh
        fh.flush()
        os.fsync(fh.fileno())
    finally:
        fh.close()
    os.replace(tmp, path)


def complete_lines(path: str):
    """Yield only whole lines, so a reader never acts on a torn final row.

    A file being appended to by another process can end mid-line. Yielding that
    fragment to a csv reader produces a row that looks real and is not.
    """
    if not os.path.exists(path):
        return
    with io.open(path, encoding="utf-8", errors="replace", newline="") as fh:
        for line in fh:
            if line.endswith("\n"):
                yield line
