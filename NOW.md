---
repo: krishanraja/filearchives
product: filearchives
as_of: 2026-11-14
head: 719bb3e
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

## Where it is right now (as of 2026-11-14)

<!-- north-star-state {"week_of":"2026-11-09","week_target":0,"current":0,"current_as_of":"2026-11-09","current_source":"docs/folder-checkin/LOG.jsonl","urgency":1,"urgency_reason":"at 100% of this week's target"} --> **North Star number: U1, on pace.** Folders moved or removed without Krish's OK, per week: 0, against 0 this week, on the way to 0 by 26 October 2026. Steady, and one proposal a week that would raise the ceiling.

Lifecycle: live. The status is in `README.md`; the commands to run and the live folder rules are in `RESUME.md`.

- **Built, with a recorded result:** the folder-consent guard (`guards/folder_consent.ps1`, proof test `tests/test_new_folder_survives.ps1`) and the weekly check-in. It has run three Mondays (2026-10-26, 2026-11-02, 2026-11-09) and each recorded 0 folders gone without his OK. The 2026-11-09 run listed 96 new folders and checked 23 answered folders (`docs/folder-checkin/LOG.jsonl`, `docs/folder-checkin/LATEST.md`). The figures are read from the log.
- **Built, running each Monday, no move has run (W3.4, D-035):** the read-only dev sprawl report (`stages/05_classify/report_dev_sprawl.ps1`, writing `docs/folder-checkin/SPRAWL.md`), the repo-to-venture map (`policy/repo-ventures.json`), the dev watch depth at 2, and the consent-row flow for dev moves (`chains/chain_dev_consolidation.ps1`), proven on a synthetic dev folder by `tests/test_dev_sprawl.ps1`. The 2026-11-09 report found 100 working trees (19 clones, 81 linked worktrees, 103.8 GB) and 2 Make Your Mind Up clones outside `dev\makeyourmindup` (`dev\mindmake\content-engine` and `dev\mindmake\growth-makeyourmindup`, both with linked worktrees); `move-requests.json` holds 0 requests.
- **Built (W3.3):** the filtered chat backstop, a SessionEnd hook (`.claude/hooks/taste_backstop.py`, test `tests/test_taste_backstop.py`). It keeps only Krish's typed corrections, scrubbed, in the ignored `.scratch/taste/backstop.jsonl` and sends nothing.
- **Checks:** CI (`.github/workflows/ci.yml`) runs the stage contracts, the backstop test, the stage conveyor, `test_new_folder_survives.ps1`, `test_dev_sprawl.ps1` and ten other portable engine tests on each pull request and each push to main. The tests that need a C: drive run on his PC only.
- **Planned, no code:** `stages/03_dating` and `stages/06_index` hold a `STAGE.md` and nothing else, and `stages/05_classify` has estate and repository analysis but no document-kind classifier.
- **Closed:** the 2026-10-04 estate consolidation and its approved cleanup (closed 2026-10-11, `docs/RUN-2026-10-11.md`). Any further cleanup starts a new dated run.
- **Not checkable from the repository:** what is physically in `H:\My Drive`, `G:\My Drive` and `C:\Users\krish\dev`, and whether the Monday task is still scheduled on his PC. `policy/folder-preferences.json` is the last record of the folders.

## What changed recently

- 2026-11-09 **The third weekly check-in recorded 0 folders gone without his OK**, 96 new folders listed (most of them inside `C:\Users\krish\dev` clones, which the depth-2 dev watch now sees) and 23 answered folders checked. The dev sprawl report ran with it.
- 2026-11-02 **The second weekly check-in, the first with the dev sprawl report**, recorded 0 folders gone without his OK, 64 new folders listed and 14 answered folders checked.
- 2026-10-29 **The filtered chat backstop landed (W3.3).** A SessionEnd hook keeps only Krish's typed corrections in an ignored local file; nothing is sent from a session (Krish: "Local file, runner posts").
- 2026-10-29 **Dev sprawl gets a weekly report, and dev moves a consent-row flow, with no move run** (D-035, Wave 3 W3.4). Every Monday the check-in now also writes `docs/folder-checkin/SPRAWL.md`: each clone and worktree under `C:\Users\krish\dev`, its venture, uncommitted and unpushed work, sizes, duplicates, and the number of Make Your Mind Up clones outside `dev\makeyourmindup`. It writes one consent row per proposed move to `move-requests.json`; nothing moves until Krish says yes for that exact folder, and then every dirty repository is snapshotted first and Growth's `.scratch` is carried byte for byte. The dev watch depth went from 1 to 2, so the next check-in will list the folders one level inside `dev\krishanraja` and `dev\mindmake` as new, waiting on him.
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

- Next run: the Monday 2026-11-16 09:00 check-in (scheduled task `filearchives-weekly-folder-checkin` on his PC, or `CHECK-MY-NEW-FOLDERS.cmd`). It writes the new reading to `docs/folder-checkin/LOG.jsonl` and the state line above.
- Known for that run: `H:\My Drive\Ventures\Active Ventures\makeyourmindup\00_Brand-Assets` is in the record as `known` and went to the Drive bin on 2026-11-11 at Krish's request (growth-makeyourmindup `docs/BRAND-KIT.md`). `policy/folder-preferences.json` holds no consent row for it, so the check-in will count it as removed without his OK unless a row with his words is recorded first.
- North Star check (2026-11-14): holds.
