r"""Where everything lives ON THIS MACHINE - resolved, never hardcoded.

    from paths import workspace, roots, targets
    w = workspace()          # raises if this machine is not configured
    w.audit                  # where records go
    w.archive                # the canonical document archive

WHY THIS IS NOT contentarchives/guards/paths.py

That file opens with `ROOT = r"D:\ContentLibrary"`, and it was right to: one
machine, one library, and 85 hardcoded copies of that string had already caused
a dedup index to cover 12% of the library while reporting success.

But Krish, 2026-09-20: *"so it is flexible and I can use it across all my drives
and machines"*. A hardcoded drive letter makes that impossible on the second
machine and quietly wrong on the first one the day a drive is re-lettered - and
"quietly wrong" is the failure mode this whole project exists to prevent. A path
that no longer exists does not raise; it reads as empty, and empty reads as
"nothing to do".

So the layout is still defined in exactly one place. What changes is that the
ROOTS come from the machine, and a machine that has not been configured STOPS.

RESOLUTION ORDER, and there is no default

    1. $FILEARCHIVES_WORKSPACE            - a path to the JSON, for CI or a
                                            one-off run against another drive
    2. %USERPROFILE%\.filearchives\workspace.json

If neither exists, `workspace()` raises `NotConfigured` with the file it wants
and the shape it wants. It does NOT invent `D:\` and carry on. An absent
configuration is an absent input (learning 7), and the entire point of failing
here is that the alternative is a tool writing records into a directory nobody
will think to look in.

THE CONFIG IS NEVER COMMITTED. It describes one person's drives. `workspace.example.json`
carries the shape with no real paths.
"""

from __future__ import annotations

import json
import os

__all__ = ["Workspace", "workspace", "roots", "targets", "NotConfigured",
           "CONFIG_ENV", "default_config_path"]

CONFIG_ENV = "FILEARCHIVES_WORKSPACE"


class NotConfigured(RuntimeError):
    """This machine has no workspace configuration. Never caught to guess one."""


def default_config_path() -> str:
    return os.path.join(os.path.expanduser("~"), ".filearchives",
                        "workspace.json")


class Workspace:
    """The resolved layout for this machine.

    Every directory the engine writes to hangs off `audit`; everything it
    curates hangs off `archive`. Sources are read-only inputs and may live
    anywhere, including on drives that come and go.
    """

    def __init__(self, data: dict, origin: str) -> None:
        self.origin = origin
        try:
            self.archive = os.path.normpath(data["archive"])
            self.audit = os.path.normpath(data["audit"])
        except KeyError as e:
            raise NotConfigured(
                "{} is missing the required key {}".format(origin, e))
        self.staging = os.path.normpath(
            data.get("staging") or os.path.join(self.audit, "_staging"))
        self._sources = [os.path.normpath(p) for p in data.get("sources", [])]
        self._targets = [os.path.normpath(p) for p in data.get("targets", [])]

    # --- records the engine writes -------------------------------------
    @property
    def sources_csv(self) -> str:
        return os.path.join(self.audit, "SOURCES.csv")

    @property
    def inventory_csv(self) -> str:
        return os.path.join(self.audit, "INVENTORY.csv")

    @property
    def proposal_csv(self) -> str:
        return os.path.join(self.audit, "STRUCTURE-PROPOSAL.csv")

    @property
    def deletions_csv(self) -> str:
        return os.path.join(self.audit, "deletions.csv")

    def record(self, name: str) -> str:
        """Any other record, so a new tool does not invent its own directory."""
        return os.path.join(self.audit, name)

    def ensure_audit(self) -> str:
        os.makedirs(self.audit, exist_ok=True)
        return self.audit

    def __repr__(self) -> str:
        return "Workspace(archive={!r}, audit={!r}, {} sources, {} targets)".format(
            self.archive, self.audit, len(self._sources), len(self._targets))


_CACHE: Workspace | None = None


def workspace(path: str | None = None) -> Workspace:
    """The configured workspace, or a loud failure explaining how to make one."""
    global _CACHE
    if _CACHE is not None and path is None:
        return _CACHE

    candidates = []
    if path:
        candidates.append(path)
    else:
        env = os.environ.get(CONFIG_ENV)
        if env:
            candidates.append(env)
        candidates.append(default_config_path())

    for c in candidates:
        if c and os.path.exists(c):
            try:
                with open(c, encoding="utf-8") as fh:
                    data = json.load(fh)
            except ValueError as e:
                raise NotConfigured("{} is not valid JSON: {}".format(c, e))
            w = Workspace(data, c)
            if path is None:
                _CACHE = w
            return w

    raise NotConfigured(
        "this machine has no filearchives workspace.\n"
        "  Looked for: {}\n"
        "  Create it, or set {} to point at one. Shape:\n"
        "      {{\n"
        '        "archive": "D:\\\\DocumentArchive",\n'
        '        "audit":   "D:\\\\_FileAudit",\n'
        '        "sources": ["E:\\\\", "G:\\\\My Drive"],\n'
        '        "targets": ["H:\\\\My Drive\\\\DocumentArchive"]\n'
        "      }}\n"
        "  See workspace.example.json. It is never committed: it describes "
        "one person's drives.".format(", ".join(str(c) for c in candidates),
                                      CONFIG_ENV))


def roots(w: Workspace | None = None) -> list[str]:
    """Source trees that EXIST right now.

    A configured source that is not mounted is reported, never silently
    dropped: a drive that is absent and a drive that is empty must not look
    the same (learning 7).
    """
    w = w or workspace()
    present, missing = [], []
    for p in w._sources:
        (present if os.path.isdir(p) else missing).append(p)
    if missing:
        # !r, not the bare path. A Windows path interpolated raw into a message
        # gets its backslashes read as escapes - `Z:\not-mounted` printed with a
        # line break through the middle of it during the first smoke test. The
        # same trap in the other direction cost seven round trips today.
        print("  configured sources NOT mounted, skipped: {}".format(
            ", ".join(repr(m) for m in missing)))
    return present


def targets(w: Workspace | None = None) -> list[str]:
    """Mirror destinations that exist right now, reported the same way."""
    w = w or workspace()
    present, missing = [], []
    for p in w._targets:
        (present if os.path.isdir(os.path.splitdrive(p)[0] + os.sep)
         else missing).append(p)
    if missing:
        print("  configured targets NOT mounted, skipped: {}".format(
            ", ".join(repr(m) for m in missing)))
    return present
