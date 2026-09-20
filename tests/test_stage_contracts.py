r"""The repo is a conveyor of stages. Fail the build when it stops being one.

    python tests\test_stage_contracts.py

Carried from contentarchives, where it exists because a session with all
forty-nine learnings in reach broke eleven of them in one afternoon. The lessons
lived in a long document and reached new machinery only through whoever
remembered them. This test moves that memory into the build:

  1. every stage has a STAGE.md with Inputs, Outputs, Invariants, Code, Tests
     and Lessons
  2. every learning in docs/LEARNINGS.md has an owner
  3. every enforcement a Lessons table names EXISTS - the file, and the literal
     text inside it - so a claim cannot outlive the code that backed it
  4. every code file belongs to a stage

Adding a learning without a stage claiming it fails this test, on purpose.

A detector with a hole is worse than none, because the green tick is believed.
So the checks run first against a deliberately broken fixture and must catch
every defect in it before they are trusted against the real repo.
"""

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REQUIRED = ["Inputs", "Outputs", "Invariants", "Code", "Tests", "Lessons"]
# Every tree that holds .py or .ps1 belongs here. contentarchives' version was
# missing `stages` when the conveyor's first stages moved into it, and 34 files
# silently became unowned without the test objecting - an ownership check can
# only see the trees it is told about, so a missing entry is a hole that reports
# success. `chains` is here from the start for that reason.
CODE_DIRS = ["stages", "guards", "filearchives", "tools", "chains"]
CODE_EXT = {".py", ".ps1"}

problems: list[str] = []


def stage_dirs() -> list[str]:
    out = []
    s = os.path.join(ROOT, "stages")
    if os.path.isdir(s):
        out += [os.path.join(s, d) for d in sorted(os.listdir(s))
                if os.path.isdir(os.path.join(s, d))]
    g = os.path.join(ROOT, "guards")
    if os.path.isdir(g):
        out.append(g)
    return out


def read(p: str) -> str:
    return io.open(p, encoding="utf-8", errors="replace").read()


def check_sections(stage: str) -> None:
    p = os.path.join(stage, "STAGE.md")
    if not os.path.exists(p):
        problems.append("{} has no STAGE.md".format(os.path.basename(stage)))
        return
    text = read(p)
    for section in REQUIRED:
        if not re.search(r"^##\s+" + re.escape(section) + r"\s*$",
                         text, re.M):
            problems.append("{}/STAGE.md has no '## {}' section".format(
                os.path.basename(stage), section))


def claimed_learnings() -> dict:
    """learning number -> list of (stage, enforcement string)."""
    out: dict[int, list] = {}
    for stage in stage_dirs():
        p = os.path.join(stage, "STAGE.md")
        if not os.path.exists(p):
            continue
        for line in read(p).splitlines():
            m = re.match(r"^\|\s*(\d+)\s*\|(.+?)\|(.+?)\|\s*$", line)
            if m:
                out.setdefault(int(m.group(1)), []).append(
                    (os.path.basename(stage), m.group(3).strip()))
    return out


def defined_learnings() -> list[int]:
    p = os.path.join(ROOT, "docs", "LEARNINGS.md")
    if not os.path.exists(p):
        problems.append("docs/LEARNINGS.md is missing")
        return []
    return [int(m) for m in re.findall(r"^##\s+(\d+)\.", read(p), re.M)]


def check_enforcement(num: int, stage: str, spec: str) -> bool:
    """A claim names a file and literal text inside it. Both must exist."""
    real = False
    for ref in re.findall(r"`(code|test|guard):([^:]+):([^`]+)`", spec):
        kind, rel, needle = ref
        path = os.path.join(ROOT, rel.replace("/", os.sep))
        if not os.path.exists(path):
            problems.append(
                "learning {} in {} names {} which does not exist".format(
                    num, stage, rel))
            continue
        if needle not in read(path):
            problems.append(
                "learning {} in {} claims {!r} inside {}, which is not there"
                .format(num, stage, needle, rel))
            continue
        real = True
    return real


def owned_code_files() -> None:
    claimed = set()
    for stage in stage_dirs():
        p = os.path.join(stage, "STAGE.md")
        if os.path.exists(p):
            for m in re.findall(r"`([^`]+\.(?:py|ps1))`", read(p)):
                claimed.add(os.path.normcase(m.replace("/", os.sep)))

    total = unowned = 0
    for d in CODE_DIRS:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dp, dns, fns in os.walk(base):
            dns[:] = [x for x in dns if x != "__pycache__"]
            for fn in fns:
                if os.path.splitext(fn)[1].lower() not in CODE_EXT:
                    continue
                total += 1
                rel = os.path.relpath(os.path.join(dp, fn), ROOT)
                if os.path.normcase(rel) not in claimed:
                    unowned += 1
                    problems.append("code file has no stage: {}".format(rel))
    print("  code files: {} total, {} unowned".format(total, unowned))


def main() -> int:
    stages = stage_dirs()
    if not stages:
        problems.append("no stages found - the conveyor does not exist yet")
    for s in stages:
        check_sections(s)

    defined = defined_learnings()
    claims = claimed_learnings()
    prose = []
    for num in defined:
        if num not in claims:
            problems.append(
                "learning {} has no owner - a stage must claim it".format(num))
            continue
        if not any(check_enforcement(num, st, sp) for st, sp in claims[num]):
            prose.append(num)

    for num in claims:
        if num not in defined:
            problems.append(
                "a stage claims learning {}, which is not in LEARNINGS.md"
                .format(num))

    owned_code_files()

    print("  stages: {}   learnings: {}".format(len(stages), len(defined)))
    print("  enforced in code: {}".format(len(defined) - len(prose)))
    print("  prose-only (debt): {}  {}".format(len(prose), sorted(prose)))

    if problems:
        print()
        print("FAILED ({}):".format(len(problems)))
        for p in problems:
            print("  " + p)
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
