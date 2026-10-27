# AGENTS.md

<!-- north-star:start -->
## North Star: read it first, every session

This repository's North Star is [`docs/NORTH_STAR.md`](docs/NORTH_STAR.md): an ambition Krish set that is not reached yet.

- Read it before any work, every session.
- Before you start, say which part of it the task moves. If it moves nothing, say so first and let Krish decide.
- Prefer the work that moves it furthest, and close by noting what moved.
- Check the North Star number and its urgency (U1 to U5) on the first line under "Where it is right now" in `NOW.md`, and push at the intensity [the harness contract](https://github.com/krishanraja/ai-harness/blob/main/contract/north-star-metric.md) sets for that level. Update it whenever you can measure it; a number nobody measures is U4.
- Only Krish changes it.
<!-- north-star:end -->

## Krish's folders

Ruling (Krish, 2026-10-23): filearchives never moves a folder Krish made without asking first.

- Never move, rename, merge or delete a folder inside `H:\My Drive`, `G:\My Drive` or `C:\Users\krish\dev`, by the engine or by hand, without a consent row from Krish for that exact folder in `policy/folder-preferences.json`. Only Krish gives one; record his words with it.
- A folder the record does not know is new, waiting on Krish. Leave it where it is and let the weekly check-in ask him.
- `tests/test_new_folder_survives.ps1` must pass before any change to a mover, planner or the consent guard is committed.

## Where to start

Read `NOW.md` first (where the repository is right now), then `RESUME.md` (what to run and the live folder rules). `docs/DECISIONS.md` records why, `policy/folder-preferences.json` is the record of Krish's folders and consents, and `docs/LEARNINGS.md` holds the rules each stage enforces. The code is a conveyor of stages (`stages/01_sources` to `stages/09_mirror`, plus `guards/`): read a stage's `STAGE.md` before changing it, and run `python tests/test_stage_contracts.py` to check that every code file has a stage and every learning has an owner. The tests are PowerShell for Windows.
