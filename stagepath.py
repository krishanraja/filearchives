r"""Put every stage, guards/ and the package root on sys.path. Import me first.

    import stagepath                      # from a stage script
    stagepath.script("build_index.py")    # -> the path it lives at now

Carried across from contentarchives unchanged in intent, because the reason it
exists has nothing to do with photographs:

Before this, each script reached its neighbours with its own path hack -

    sys.path.insert(0, os.path.join(HERE, "..", "stages", "05_enrich"))

which encodes the depth of the file that wrote it. Move that file one directory
deeper and it silently resolves to a directory that does not exist, so the
import fails at run time rather than at review time. Or worse, it finds a stale
copy and succeeds.

So: one definition of where things are. A stage script needs two lines, and they
do not care where the file sits:

    sys.path.insert(0, <repo root>)       # found by walking up to stagepath.py
    import stagepath                      # noqa: F401  - extends sys.path

Directories are asserted to exist, because an absent input is not an empty one:
a mistyped stage name fails here, loudly, and not as a puzzling ImportError
three files away.
"""

from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))

_DIRS = ["guards", "filearchives"]
_STAGES = os.path.join(ROOT, "stages")
if os.path.isdir(_STAGES):
    _DIRS += [os.path.join("stages", d) for d in sorted(os.listdir(_STAGES))
              if os.path.isdir(os.path.join(_STAGES, d))]
_DIRS += ["tools"]


def _add(rel: str) -> str | None:
    p = os.path.join(ROOT, rel)
    if not os.path.isdir(p):
        return None
    if p not in sys.path:
        sys.path.insert(0, p)
    return p


_ADDED = [p for p in (_add(d) for d in _DIRS) if p]

if ROOT not in sys.path:
    sys.path.insert(0, ROOT)


def script(name: str) -> str:
    """Where a named script lives NOW.

    Some steps launch others as subprocesses. Resolving by name means a move
    does not have to be chased through every caller - and a name that resolves
    to nothing raises here rather than failing as a subprocess that did nothing
    and returned 0. tools/refresh.py in contentarchives called a script by bare
    name after it moved, failed silently, and left generated state two days
    stale before anyone noticed.
    """
    for d in _ADDED + [ROOT]:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    raise FileNotFoundError(
        "no script named {!r} anywhere in the conveyor".format(name))
