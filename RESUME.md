# RESUME FILEARCHIVES

**The document engine. Start here.**

```powershell
cd C:\Users\krish\dev\krishanraja\filearchives
.\tests\test_powershell_guards.ps1
.\tests\test_inventory_resume.ps1
.\tests\test_hash_plan.ps1
.\tests\test_layout_classifier.ps1
.\tests\test_verified_copy.ps1
.\tests\test_layout_copy_manifest.ps1
.\tests\test_repository_snapshot.ps1
.\tests\test_empty_directory_cleanup.ps1
.\tests\test_extension_move.ps1
.\tests\test_filtered_copy_manifest.ps1
.\tests\test_verified_copy_sharding.ps1
.\tests\test_atomic_tree_relocation.ps1
.\tests\test_ingress_duplicate_quarantine.ps1
.\tests\test_sensitive_name_quarantine.ps1
.\tests\test_temporary_family_consolidation.ps1
.\tests\test_path_regex_quarantine.ps1
.\tests\test_new_folder_survives.ps1
.\tests\test_streaming_folder_copy.ps1
.\tests\test_windows_profile_coverage.ps1
node C:\Users\krish\.codex\skills\krish-build\scripts\check-stage-conveyor.mjs `
  --root . --manifest pipeline\stage-conveyor.json
```

`python tests\test_stage_contracts.py` also checks the conveyor: every stage has
a `STAGE.md`, every learning has an owner, every code file belongs to a stage.
It needs Python, which D-004 recorded as absent on the active Windows machine.
On 2026-10-27 it passed on Linux: 10 stages, 36 learnings, 63 code files, none
unowned.

---

## LIVE: Krish's folders stay where he puts them (from 2026-10-23)

Ruling (Krish, 2026-10-23): filearchives never moves a folder Krish made
without asking first. D-030 and learning 36 hold the detail.

- `policy/folder-preferences.json` is the record of where Krish wants things.
  `RECORD-MY-FOLDERS.cmd` (double-click, on his PC) fills it from the drives as
  they stand, starts the weekly check-in and saves the record to GitHub.
- `guards/folder_consent.ps1` refuses every folder move, rename, merge or
  removal inside a watched root without his per-folder consent row, and
  refuses to empty a folder that is waiting on him.
- The weekly check-in (Monday 09:00, scheduled task
  `filearchives-weekly-folder-checkin`, or `CHECK-MY-NEW-FOLDERS.cmd`) asks two
  questions per new folder, counts recorded folders gone without his OK (the
  North Star number), and writes `docs/folder-checkin/LATEST.md` and
  `LOG.jsonl`. It never moves anything.
- Current layout, as Krish recorded it on 2026-10-23 (D-032) and changed on
  2026-10-24 and 2026-10-26 (D-033, D-034): H holds `--ARCHIVE` (the old
  ARCHIVE categories plus `CONTENT-EXTRA`), `Family Admin` (`Krish`, `Loz`,
  `Maa`), `FamilyContentLibrary` (never entered), `KeePass`, `Inbox from My AI`
  (where an AI session files what it cannot place) and `Ventures` (`Active
  Ventures`, `Inspiration`, `Bugs & Issues`, `Network & Contacts`, `_Archive`).
  G holds `App Issues`, `Family`, `Immigration`, `Legal`, `Music Production`
  and `Tax Return History`; the old `G:\My Drive\Personal` categories no longer
  exist. The record, not the estate policy's category lists, is the authority.
- Krish can answer in writing in `docs/folder-checkin/answers.json`. A consent
  to move or remove a folder is a row in `consents` with
  `approved_by: "Krish"`, the exact path, the action, the destination for a
  move, and his words; only he gives one.

## CLOSED MISSION: whole-estate consolidation (2026-10-04 to 2026-10-11)

### Outcome the mission aimed for

- one canonical current-work tree in `H:\My Drive`
- one canonical archive tree in `H:\My Drive`
- one deterministic local repository policy for both local machines
- a reusable engine that can survey, propose, verify and execute the same
  cleanup safely on a future machine

### State at closeout (2026-10-11)

Folder names have changed since (D-031 to D-034); the layout in the LIVE
section above is current.

- canonical local clone: `C:\Users\krish\dev\krishanraja\filearchives`;
  the completed engine is pushed to `origin/main`
- sealed run `estate-20261003-v1` covers all 20 configured roots on C, E, G, H
  and mounted L: 1,308,625 files, 149,768 directories and 199,161,374,424 bytes
- 2026-10-22 (D-031): H `CURRENT` and `PERSONAL-SYSTEMS` were dissolved into
  `Ventures` and `Family Admin\Krish`; `business_current` is retired in policy
- at closeout, H business current/archive, CONTENT-EXTRA and FAMILY-ADMIN
  existed in the accepted shallow taxonomy and G contained the accepted ten
  personal categories; D-031 and D-032 have since dissolved or renamed them
- final canonical-state audit passes with zero issues; C/L Windows known-folder
  coverage passes with zero uncovered paths
- both `C:\Users\krish\Downloads` and `L:\Users\krish\Downloads` are empty;
  late L arrivals were re-ingested before this final assertion
- E contains only `_FILEARCHIVES_QUARANTINE`, `$RECYCLE.BIN` and
  `System Volume Information`; all retired source trees remain recoverable
- L's eight dirty repositories have verified C recovery snapshots and H
  off-machine recovery; L's visible dev tree is retired except for a locked
  empty Git refs shell
- `C:\Users\krish\dev\krishanraja\mm-ctrl` remains untouched at HEAD
  `1afe495208876b09f2f9e34dfa79ac20aaf3fbdc`; fresh C and H snapshots each
  reconcile the full index, file set, content and all 770 status entries
- two historical C Codex task trees were archived to H with authenticated
  four-shard receipts, and their complete originals moved to C quarantine;
  one fileless `2026-09-04\read` shell remains locked by another process
- H exact-ingress dedupe quarantined 997 proven redundant files (3.19 GB); G
  personal-history/media dedupe quarantined 1,264 files (21.57 GB)
- 282 explicitly named screenshot/thumbnail/meme/cache/temp media files were
  quarantined; two temporary document families kept their newest member and
  quarantined superseded members
- 856 cloud-category empty descendants and 3,685 local empty descendants were
  removed; provider-changed and locked shells were retained and recorded
- the approved 1,223-file G quarantine purge was backed up to H, revalidated
  at unlink and completed with zero refusals, removing 21,048,508,824
  live-tree bytes
- the 3,997-row business retirement manifest deleted 2,434 current verified
  pairs and removed 1,029,225,206 live-tree bytes; 1,500 victims were already absent and
  63 substantive refusals remain intact on G
- the closeout removed 22,077,734,030 live-tree bytes from G in total; all 41 quarantine
  exceptions remain, and Google Photos, WhatsApp, generated `node_modules` and
  H `ContentLibrary` were not touched

### Locked constraints

- do not enumerate, hash, compare, move, rename or delete anything inside a
  configured `ContentLibrary` protected root
- every move, dedupe and deletion is first emitted as a reviewable manifest
- permanent deletion requires a verified external survivor, a frozen manifest,
  current-state revalidation and exact action-time approval; the 30-day wait
  was waived only for the exact 2026-10-11 backed-up quarantine manifest
- cloud and peer-machine sources may disappear; absence is never interpreted
  as an empty tree
- credentials are reported only by category and location, never read into
  logs or copied into the archive without an approved secure destination

### Authority during the mission (closed 2026-10-11)

Since 2026-10-23 (D-030) any folder move, rename, merge or removal in a watched
root, including the same-account Google metadata moves below, also needs
Krish's yes for that folder. The list below is what the mission was given, not
what an engine run may do today.

- authorised during the mission: autonomous analysis, accepted high-confidence H/G filing,
  source-preserving verified copies, same-account Google metadata moves,
  pre-backup quarantine, repository preservation and engine development
- not authorised by the accepted policy: permanent purge before backup,
  credential-content reads, deleting unproven files, or touching H
  `ContentLibrary`

### Pass signals

- a protected-root traversal attempt fails before enumeration
- a disconnected source is recorded as unavailable and never as empty
- every proposed mutation has source identity, destination, evidence,
  collision handling, rollback and current-state revalidation
- the final current-work and archive trees can be independently re-inventoried
  with no unexplained loss, duplicate canonical identity or source residue

### Current gate

Closed. The consolidation and its approved cleanup are complete. H
`ContentLibrary` remained completely excluded, the 41 quarantine exceptions
and 63 substantive business refusals remain retained, and there is no remaining
authorized deletion queue.

### Next action

None for this run. Any future cleanup starts a new dated run with a fresh
manifest, survivor proof, current-state verification and action-time approval.
See `docs/RUN-2026-10-11.md` for the closeout evidence.

---

## What this is

`contentarchives` consolidated 82,000 photographs into one verified library and
reclaimed 1,114 GB. This is the same machinery pointed at **documents**: the
twenty years of scans, statements, contracts, exports and downloads scattered
across every drive.

Krish, 2026-09-20: *"sort all of my old non-content documents, dedupe them, and
create the same folder structure in every drive that I have as fresh."*

`H:\My Drive\FamilyContentLibrary` (renamed from `ContentLibrary`) stays
completely outside this engine. Useful photographs and videos discovered
elsewhere are classified for `H:\My Drive\--ARCHIVE\CONTENT-EXTRA`; the engines
must never traverse the same protected tree.

---

## WHAT IS BUILT: the engine carried from contentarchives

The first pieces, carried from `contentarchives` on 2026-09-20 because each was
paid for there (the PowerShell stages, the folder record and the weekly check-in
came later; see the conveyor table in `README.md`):

| Piece | What it is |
|---|---|
| `stagepath.py` | one definition of where every stage lives |
| `filearchives/dedupe.py` | size -> signature -> whole-file hash, never the name |
| `filearchives/safety.py` | the deletion allowlist; garbage is a CLOSED list |
| `guards/guarded_delete.py` | the only sanctioned delete: proven survivor, different inode, re-hashed at the unlink, journalled first |
| `guards/files.py` | atomic writes, absent-input stops, whole lines only |
| `docs/LEARNINGS.md` | 36 learnings (14 when it was carried over), each owned by a stage or the build fails |

The estate was surveyed, inventoried and analysed in the 2026-10-04 run, verified
filing and the approved guarded cleanup ran, and the run closed on 2026-10-11.
Permanent deletion happened only under the approved manifests recorded in
`docs/RUN-2026-10-11.md`; any further deletion needs a new dated run.

---

## It runs on any machine, and the machine says where things are

**The engine's own paths are not hardcoded to a drive letter.** contentarchives
opened its path file with `ROOT = r"D:\ContentLibrary"`, which was right for one
machine and is impossible for a second - and quietly wrong on the first one the
day a drive is re-lettered, because a path that no longer exists does not raise.
It reads as empty, and empty reads as "nothing to do". (Krish's own Drive roots,
`H:\My Drive`, `G:\My Drive` and `C:\Users\krish\dev`, are named in
`policy/folder-preferences.json` and a few script defaults since the folder
record of 2026-10-23; they are his folders, not the machine's.)

So each machine carries its own config, and there is **no default**:

    %USERPROFILE%\.filearchives\workspace.json      (default location)
    FILEARCHIVES_WORKSPACE=<path>                   (override, for a one-off
                                                     run against another drive)

Copy `workspace.example.json`, edit it, done. An unconfigured machine STOPS with
instructions rather than inventing `D:\`. A configured source that is not
mounted is **reported and skipped**, never silently treated as empty - a drive
that is absent and a drive that is empty must not look the same.

## Chains: modular, supervised, and they outlive the session

Each stage is a step; a chain is a sequence of them. Run one with:

    pwsh -NoProfile -File guards\arm.ps1 -Chain chains\chain_survey.ps1
    pwsh -NoProfile -File guards\arm.ps1 -Status
    pwsh -NoProfile -File guards\arm.ps1 -Stop -TaskName filearchives-survey

`arm.ps1` registers a scheduled task, so the work survives the terminal closing
and the session ending - `Start-Process -WindowStyle Hidden` does NOT detach,
and in contentarchives three jobs died in the same second an agent session
ended, four hours in. The task restarts on a kill, and every chain is written to
resume, so a death costs only the work in flight.

**`-TaskName` is per-chain**, so chains touching different trees run side by
side. contentarchives had one fixed task name, which is why a fortnightly ingest
could not be armed while a mirror was running.

**Every step must declare five blocks** - Preflight, Start, Progress, Verify,
Postcondition - and a missing one is an exception, not a step that quietly runs
unguarded. `Verify` must RE-DERIVE a sample from source and compare, never
inspect the output's shape: over there a progress counter climbed beautifully
for five hours while every record written was attached to the wrong file.

**Chains log with `Add-Content` + `Write-Host`, never `Tee-Object`**, and
`Invoke-Step` takes a gate's LAST emission. Both defences guard the same trap:
Tee writes to the pipeline as well as the file, so a gate that logs returns a
non-empty array, and `[bool]` of that is `$true`. A Postcondition returning
`$false` read as success for a week.

## The order to build it in, and why

Do NOT start by writing an importer. The first job is to find out what is
actually out there, because every estimate made without measuring in the other
engine was wrong - often by a factor of ten, once by a factor of a hundred.

Built so far: `01_sources`, `02_ingest`, `04_inventory`, `07_structure`,
`08_reclaim`, `09_mirror`, and the analysis half of `05_classify`. Not built
(a `STAGE.md` and no code): `03_dating`, `06_index`, and the document-kind
classifier in `05_classify`. The list below is the order they were planned in.

1. **`01_sources` - survey only.** Walk every drive, count documents by type,
   size and tree. Write it down. Delete nothing, move nothing, decide nothing.
   Expect the answer to surprise you: the photograph library's "OneDrive holds
   140 GB" turned out to be 1.1 GB.
2. **`04_inventory` - one metadata row per item** with path, size, dates,
   extension, origin and classification hints; never claim identity here.
3. **`02_ingest` - prove content identity**, using size, then an edge signature,
   then a whole-file hash. Only after structure manifests exist may files move.
4. **`03_dating`** - filename, then folder, then the document's own text.
5. **`05_classify`** - what KIND: statement, contract, scan, receipt, export.
6. **`06_index`** - full-text search over the documents themselves. Unlike
   photographs, they mostly say what they are, for free.
7. **`07_structure`** - the canonical tree, and a REVIEWABLE PROPOSAL mapping
   files into it. Never an automatic move.
8. **`08_reclaim`** - free the space. The only stage that destroys.
9. **`09_mirror`** - as built, a canonical-state audit: check the top of every
   watched drive against Krish's folder record, without entering a protected
   boundary. It does not verify a backup or mirror content.

---

## The three traps that will bite first

These are not hypothetical; each one cost hours in the other engine.

**Versions are not duplicates.** `contract_v2_FINAL_signed.pdf` next to
`contract_v2_FINAL.pdf` is the normal case for documents and has no equivalent
in a camera roll. Byte-identical dedupe is safe; anything cleverer must ask a
human. `safety.looks_like_a_version()` exists to make a tool refuse rather than
guess.

**There is no EXIF.** Nearly every document will land undated unless the folder
it came from is named with a year. Name the folders BEFORE ingesting - it is
minutes of work and the only cheap date you will ever get.

**A derived record goes stale the moment the disk changes.** In the other engine
an index was rebuilt from three CSVs that nobody had updated, and it confidently
reported 82,104 files after 581 had demonstrably been added. Any record keyed on
PATH is a claim about the disk, not the disk.

---

## Rules inherited without argument

Read `docs/LEARNINGS.md` before changing any deletion, dedupe or classification
rule. The short version:

- a path is never grounds to delete
- only a whole-file hash may declare a duplicate
- a surviving copy must be a different inode
- re-verify at the instant of deletion; a report is never evidence
- journal before destroying, and fsync it
- an absent input stops the run
- an unreadable file is unproven, not innocent
- long work is resumable and writes as it goes
