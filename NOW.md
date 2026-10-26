---
repo: krishanraja/filearchives
product: filearchives
as_of: 2026-10-26
head: dc9af63
lifecycle: live
production_url: none
state_doc: README.md
history_log: docs/history/LOG.md
truth_files: [docs/NORTH_STAR.md]
authority_order: [docs/NORTH_STAR.md, README.md]
steward: https://github.com/krishanraja/ai-harness/blob/main/docs/steward/RUNBOOK.md
---

# filearchives: where it is right now

## What it is

The engine that keeps Krish's documents in one verified library without losing anything, and keeps them where he wants them.

## Who it is for and why it matters for Mindmake

Krish himself.

## Where it is right now (as of 2026-10-26)

<!-- north-star-state {"week_of":"2026-10-26","week_target":0,"current":0,"current_as_of":"2026-10-26","current_source":"docs/folder-checkin/LOG.jsonl","urgency":4,"urgency_reason":"Krish saw a folder he made disappear this week; the fix session is running"} --> **North Star number: U4, far behind.** Folders moved or removed without Krish's OK, per week: Krish saw a folder he made disappear this week; the fix session is running. A bold swing every day; work that does not move the number waits.

Lifecycle: live. The detail is in `README.md`.

## What changed recently

- 2026-10-26 **His network exports moved out of --ARCHIVE into `Ventures\Network & Contacts`, one dated folder each** (D-034): `LinkedIn Export - Feb 2026`, `LinkedIn Export - Aug 2026`, `Instagram Export - Jul 2026` and `LinkedIn Export - Mar 2025`, each dated from the export itself. His yes for each folder was recorded before the move, so the next check-in counts them as moved with his OK. No Facebook export is in his Drive. Nothing else needed a change: Control Center reads the exports by Drive file ID, which a move keeps. Ruling (Krish, 2026-10-26): network exports live in Network & Contacts, one folder per export, named with its date.
- 2026-10-24 **The top of his Drive is recorded, with an inbox for what an AI cannot place** (D-033). `Ventures` holds everything (Active Ventures, Inspiration, Bugs & Issues, _Archive); `Inbox from My AI` at the top replaces CURRENT/00_INBOX; FamilyContentLibrary and KeePass never move. His answers for the two new folders are in `docs/folder-checkin/answers.json`, so the next check-in records them rather than asking. The Drive map the OS reads (hunter `drivemap.py`) follows.
- 2026-10-23 **Krish's folder record landed (864 folders on H, G and C dev) and is now the authority for where things live.** `FamilyContentLibrary`, the renamed ContentLibrary, is never entered by any run, whatever the machine config says. The policy, the canonical audit and the docs now match the drive as it is (D-032).
- 2026-10-23 **filearchives no longer moves or removes a folder Krish made without his yes.** Every folder move, rename, merge or removal inside H:\My Drive, G:\My Drive and C:\Users\krish\dev now needs his consent for that folder; a new folder is recorded as waiting on him and left where he put it; a weekly check-in asks what goes in it and counts any folder gone without his OK. Proven by `tests/test_new_folder_survives.ps1`. Ruling (Krish, 2026-10-23): filearchives never moves a folder Krish made without asking first.
- 2026-10-23 **The North Star now has a number, a weekly ladder and an urgency rating.** Ruling (Krish, 2026-10-23): every repository chases one aggressive number on a weekly ladder, and urgency U1 to U5 sets how hard it pushes. The number is in `docs/NORTH_STAR.md`; contract: ai-harness `contract/north-star-metric.md`.

## What is next and what is waiting on Krish

- Done 2026-10-23: Krish pressed `RECORD-MY-FOLDERS.cmd`; the record and the Monday check-in are in place. Nothing is waiting on him until the first check-in asks about new folders.
- The North Star number is measured from the first weekly check-in after that (`docs/folder-checkin/LOG.jsonl`), which also writes it into the line above. Until then it is unmeasured.
- Done 2026-10-26: the consent rows for the network export moves are in main (krishanraja/filearchives#2), so Monday's check-in counts them as moved with his OK. The Instagram follower lists built from the export now sit in its folder too. The emptied `My Contacts` folder is in Drive Trash, with his delete consent in the record.
- When the Facebook export turns up, it goes in `Network & Contacts` as `Facebook Export - <Mon YYYY>`.
- North Star check (2026-10-26): holds. Five folder moves and six loose export files filed this week, all with his yes recorded first.

## Read next

- `docs/NORTH_STAR.md`: the North Star, its number and its weekly ladder.
- `README.md`: what this repository is and how it runs.

## Do not trust

Nothing at the moment.
