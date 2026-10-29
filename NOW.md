---
repo: krishanraja/filearchives
product: filearchives
as_of: 2026-10-29
head: 85ac535
lifecycle: live
production_url: none
state_doc: README.md
history_log: docs/history/LOG.md
truth_files: [docs/NORTH_STAR.md, policy/folder-preferences.json]
authority_order: [docs/NORTH_STAR.md, README.md]
steward: https://github.com/krishanraja/ai-harness/blob/main/docs/steward/RUNBOOK.md
---

# filearchives: where it is right now

## What it is

The engine that keeps Krish's documents in one verified library without losing anything, and keeps them where he wants them.

## Who it is for and why it matters for Mindmake

Krish himself.

## Where it is right now (as of 2026-10-29)

<!-- north-star-state {"week_of":"2026-10-26","week_target":0,"current":0,"current_as_of":"2026-10-26","current_source":"docs/folder-checkin/LOG.jsonl","urgency":1,"urgency_reason":"at 100% of this week's target"} --> **North Star number: U1, on pace.** Folders moved or removed without Krish's OK, per week: 0, against 0 this week, on the way to 0 by 26 October 2026. Steady, and one proposal a week that would raise the ceiling.

Lifecycle: live. The status is in `README.md`; the commands to run and the live folder rules are in `RESUME.md`.

- **Built, with a recorded result:** the folder-consent guard (`guards/folder_consent.ps1`, proof test `tests/test_new_folder_survives.ps1`) and the weekly check-in, whose last run (2026-10-26) recorded 0 new folders waiting and 0 folders gone without his OK (`docs/folder-checkin/LOG.jsonl`, `docs/folder-checkin/LATEST.md`). The tests are PowerShell for Windows and were not re-run for this update; the figures are read from the log.
- **Planned, no code:** `stages/03_dating` and `stages/06_index` hold a `STAGE.md` and nothing else, and `stages/05_classify` has estate and repository analysis but no document-kind classifier.
- **Closed:** the 2026-10-04 estate consolidation and its approved cleanup (closed 2026-10-11, `docs/RUN-2026-10-11.md`). Any further cleanup starts a new dated run.
- **Not checkable from the repository:** what is physically in `H:\My Drive`, `G:\My Drive` and `C:\Users\krish\dev`, and whether the Monday task is still scheduled on his PC. `policy/folder-preferences.json` is the last record of the folders.

## What changed recently

- 2026-10-26 **His network exports moved out of --ARCHIVE into `Ventures\Network & Contacts`, one dated folder each** (D-034): `LinkedIn Export - Feb 2026`, `LinkedIn Export - Aug 2026`, `Instagram Export - Jul 2026` and `LinkedIn Export - Mar 2025`, each dated from the export itself. His yes for each folder was recorded before the move (krishanraja/filearchives#2), so the next check-in counts them as moved with his OK. The Instagram follower lists built from the export now sit in its folder (Krish: "yes follower lists moved in"), and the emptied `My Contacts` folder went to Drive Trash with his delete consent recorded first. No Facebook export is in his Drive. Nothing else needed a change: Control Center reads the exports by Drive file ID, which a move keeps. Ruling (Krish, 2026-10-26): network exports live in Network & Contacts, one folder per export, named with its date.
- 2026-10-26 **The first weekly check-in ran and found nothing wrong.** 0 folders moved or removed without his OK, 0 new folders waiting, 4 answered folders checked (`docs/folder-checkin/LOG.jsonl`). It ran before that day's export moves, which have their consent rows and count at the next check-in.
- 2026-10-24 **The top of his Drive is recorded, with an inbox for what an AI cannot place** (D-033). `Ventures` holds everything (Active Ventures, Inspiration, Bugs & Issues, _Archive); `Inbox from My AI` at the top replaces CURRENT/00_INBOX; FamilyContentLibrary and KeePass never move. His answers for the two new folders are in `docs/folder-checkin/answers.json`, so the next check-in records them rather than asking. The Drive map the OS reads (hunter `drivemap.py`) follows.
- 2026-10-23 **Krish's folder record landed (864 folders on H, G and C dev) and is now the authority for where things live.** `FamilyContentLibrary`, the renamed ContentLibrary, is never entered by any run, whatever the machine config says. The policy, the canonical audit and the docs now match the drive as it is (D-032).
- 2026-10-23 **filearchives no longer moves or removes a folder Krish made without his yes.** A folder he made on H was gone the next day: the engine treated every unexpected top-level folder as an issue and removed any empty folder under the root it was given. Now every folder move, rename, merge or removal inside H:\My Drive, G:\My Drive and C:\Users\krish\dev needs his consent for that folder; a new folder is recorded as waiting on him and left where he put it; a weekly check-in asks what goes in it and counts any folder gone without his OK. Proven by `tests/test_new_folder_survives.ps1`. Ruling (Krish, 2026-10-23): filearchives never moves a folder Krish made without asking first.
- 2026-10-23 **The North Star now has a number, a weekly ladder and an urgency rating.** Ruling (Krish, 2026-10-23): every repository chases one aggressive number on a weekly ladder, and urgency U1 to U5 sets how hard it pushes. The number is in `docs/NORTH_STAR.md`; contract: ai-harness `contract/north-star-metric.md` (https://github.com/krishanraja/ai-harness/blob/main/contract/north-star-metric.md).
- 2026-10-22 **H `CURRENT` and `PERSONAL-SYSTEMS` were dissolved into `Ventures` and `Family Admin\Krish`** (D-031), because Krish wanted one venture-shaped home with nothing stale in the line of sight. Exact duplicates went to Drive Trash with a verified surviving copy, and the policy's `business_current` was set to a non-path sentinel so a later run stops instead of recreating CURRENT.
- 2026-10-18 **The North Star was added and every session was told to read it first**, so each task names what it moves (`docs/NORTH_STAR.md`; Krish rewrote it on 2026-10-23).
- 2026-10-15 **A browser-driven pass on the Drive `Personal` folder ran outside the engine**, with no manifests or hash journal: it uploaded a tax ledger and binned eight emptied folders (recoverable). The duplicate-consolidation step was not done, because Drive's web UI shows no content hash and whole-file SHA-256 is the only duplicate proof (`docs/RUN-2026-10-15-drive-personal.md`).
- 2026-10-11 **The estate cleanup closed, and it is the only time anything was permanently deleted.** 1,223 quarantined G files (21,048,508,824 bytes) were deleted after being copied to H, and 2,434 verified pairs (1,029,225,206 bytes) from the business retirement manifest; 22,077,734,030 bytes in all, 63 refusals retained on G. The 30-day wait was waived only for that exact backed-up manifest (`docs/RUN-2026-10-11.md`).
- 2026-10-04 **The whole-estate consolidation was built and executed up to quarantine.** Sealed run `estate-20261003-v1`: 1,308,625 files, 199.16 GB across 20 roots, 18,256 exact-duplicate groups proved by whole-file SHA-256. Nothing was permanently deleted that day; sources went to dated quarantine (`docs/RUN-2026-10-04.md`).

## What is next and what is waiting on Krish

- Nothing is waiting on Krish. The 2026-10-26 check-in listed no new folder waiting, and his answers for `Inbox from My AI`, `Ventures\Inspiration` and `Ventures\Network & Contacts` are in `docs/folder-checkin/answers.json`.
- Next step: Wave 3 item W3.4, local sprawl and consents (content-engine `docs/plans/2026-11-14-wave-3.md`, due 14 November): `policy/repo-ventures.json` mapping owner/repo to a venture; the dev watch depth raised to 2, so it sees sessions' folders under `C:\Users\krish\dev\mindmake`; a read-only dev sprawl report (worktrees, dirty and unpushed work, sizes and duplicates) that feeds his Monday check-in; moves only with his consent row for that exact folder, after a snapshot of every dirty repo, with Growth's `.scratch` kept. `tests/test_new_folder_survives.ps1` must pass before any change to a mover, planner or the consent guard. Done when, after his consents, the report shows 0 Make Your Mind Up clones outside `dev\makeyourmindup`.
- Meanwhile: the Monday 2026-11-02 09:00 check-in (scheduled task `filearchives-weekly-folder-checkin` on his PC, or `CHECK-MY-NEW-FOLDERS.cmd`). It should count the moved export folders and the trashed `My Contacts` folder as moved or removed with his OK (consent rows in `policy/folder-preferences.json`), and write the new reading to `docs/folder-checkin/LOG.jsonl` and the line above.
- When the Facebook export turns up, it goes in `Network & Contacts` as `Facebook Export - <Mon YYYY>`.
- North Star check (2026-10-29): holds.

## Read next

- `docs/NORTH_STAR.md`: the North Star, its number and its weekly ladder.
- `README.md`: what this repository is, the stage conveyor and which stages are built.
- `RESUME.md`: what to run, the live folder rules, and the closed 2026-10-04 mission.
- `docs/DECISIONS.md`: D-001 to D-034; the current layout is D-031 to D-034.
- `policy/folder-preferences.json`: the folder record and Krish's per-folder consents; the authority for where things live.
- `docs/folder-checkin/LATEST.md`: the latest weekly check-in.

## Do not trust

- `docs/estate-strategy-2026-10-04.md`: its target structure (H `CURRENT`, `ARCHIVE`, G `Personal`) was superseded 2026-10-22 to 2026-10-24, and its "no permanent deletion" ended 2026-10-11. Now: `docs/DECISIONS.md` D-031 to D-034, `policy/folder-preferences.json`, `docs/RUN-2026-10-11.md`.
- `docs/RUN-2026-10-04.md` (its Authorities list): same layout, same supersession. Now: `docs/DECISIONS.md` D-031 to D-034.
- `docs/RUN-2026-10-11.md`: the path name `ARCHIVE` is now `--ARCHIVE` (D-032). Now: `policy/folder-preferences.json`.
- `docs/RUN-2026-10-15-drive-personal.md`: its next step is closed. `G:\My Drive\Personal` no longer exists (D-032) and any folder move needs his consent (D-030). Now: `docs/DECISIONS.md`.
- `docs/DECISIONS.md` D-010 and D-013 (superseded by D-031 and D-032), and the folder names in D-001, D-005, D-007, D-015, D-016, D-018 and D-019 (changed by D-031 and D-032). Each of those entries now says which decision changed it.
