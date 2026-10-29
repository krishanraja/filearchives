# Decision log

Append-only record of consequential decisions for the filearchives engine and
the current consolidation. Operational progress stays in `RESUME.md`.

Entries are never deleted. Where a later decision changed a folder name or
replaced an entry, the older entry carries an `Amended by` line or a changed
Status, and its original words stand. Where things live now: D-031 to D-034
and `policy/folder-preferences.json`.

## D-001: ContentLibrary is outside the session

- Date: 2026-10-03
- Status: locked
- Decision: `ContentLibrary` is a hard exclusion boundary. The engine must not
  enumerate, index, hash, compare, move, rename or delete content below a
  configured protected root.
- Reason: Krish explicitly excluded it from the entire session.
- Revisit trigger: only a new explicit instruction from Krish naming the exact
  root and newly authorised operation.
- Amended by D-032 (2026-10-23): the folder is now named
  `H:\My Drive\FamilyContentLibrary`; the old name stays excluded.

## D-002: destructive work is manifest-gated

- Date: 2026-10-03
- Status: locked
- Decision: discovery and proposals may run autonomously. Moves, dedupe actions
  and deletions require a frozen manifest, current-state revalidation and exact
  action-time approval. Deletion remains a separate approval even when a file
  is proven byte-identical or appears to be generated garbage.
- Reason: this estate contains irreplaceable personal records, active work and
  intermittently available sources.
- Revisit trigger: none for deletion. A future explicit decision may authorise
  a named non-destructive move batch after its manifest is reviewed.

## D-003: mm-ctrl is unique current work until independently preserved

- Date: 2026-10-03
- Status: locked
- Decision: treat
  `C:\Users\krish\dev\krishanraja\mm-ctrl` as protected unique work. Do not
  clean, relocate or deduplicate it until a separate destination has been
  verified from content and Git state.
- Evidence: the working tree is on branch `codex/g20-context-exchange-proof`
  at `1afe495208876b09f2f9e34dfa79ac20aaf3fbdc` with approximately 315
  modified or untracked entries at discovery time.
- Revisit trigger: a verified independent snapshot or committed and remotely
  retrievable state that covers every intended working-tree item.

## D-004: Windows-only runtime

- Date: 2026-10-03
- Status: locked
- Decision: target Windows machines and use PowerShell 7 as the zero-install
  runtime for new engine stages.
- Reason: both machines are Windows, PowerShell 7 is available on the active
  machine, and Python is not. Cross-platform machinery would add a dependency
  without serving the current estate.
- Revisit trigger: a real macOS or Linux operating requirement.

## D-005: E ContentLibrary is in scope; H ContentLibrary is not

- Date: 2026-10-03
- Status: locked
- Decision: `E:\ContentLibrary` may be inventoried and later considered in
  reviewed cleanup manifests. `H:\My Drive\ContentLibrary` remains completely
  excluded from enumeration, hashing, comparison and mutation.
- Reason: Krish believes the E tree is empty or garbage and explicitly
  authorised its inventory. The H tree was explicitly excluded from the full
  session.
- Revisit trigger: none for H without a new exact instruction from Krish.
- Amended by D-032 (2026-10-23): the H folder is now named
  `H:\My Drive\FamilyContentLibrary`; the old name stays excluded.

## D-006: classify before designing the destination structure

- Date: 2026-10-03
- Status: locked
- Decision: inventory the full estate, assess content and age, and classify
  each item before choosing the canonical current-work and archive schema.
- Classes: important and recent; important and old; unimportant but worth
  archiving; duplicate; delete completely.
- Reason: a preselected folder tree would encode guesses about an estate that
  has not yet been measured or understood.
- Revisit trigger: completion of the evidence-backed inventory and
  classification proposal.

## D-007: useful discovered media routes to CONTENT-EXTRA

- Date: 2026-10-03
- Status: locked destination, pending classification and move manifest
- Decision: worthwhile photographs and videos found outside the excluded H
  ContentLibrary are destined for `H:\My Drive\CONTENT-EXTRA`. Screenshots,
  memes, caches, duplicates and ambiguous media are classified before action.
- Reason: Krish explicitly named the destination and excluded low-value media.
- Revisit trigger: evidence that an item belongs to a current-work project or
  another user-owned category where moving it would break that work.
- Amended by D-032 (2026-10-23): the destination is now
  `H:\My Drive\--ARCHIVE\CONTENT-EXTRA`.

## D-008: autonomous analysis, manifest-gated mutation

- Date: 2026-10-04
- Status: locked
- Decision: run discovery, verification, classification and reversible engine
  development without routine questions. Batch privilege requests where the
  runtime requires them. Irreversible deletion remains governed by D-002.
- Reason: Krish explicitly requested autonomous completion and fewer prompts.
- Revisit trigger: an external access block or a material policy conflict that
  cannot be resolved from existing evidence.

## D-009: Git state outranks copied timestamps for source work

- Date: 2026-10-04
- Status: locked
- Decision: repository identity, dirty state, branch and remote coverage decide
  source-work recency. Filesystem modified dates are supporting evidence only.
- Reason: clones and restored directories make historical content look recent.
- Revisit trigger: none.

## D-010: proposed canonical roots

- Date: 2026-10-04
- Status: superseded by D-031 (CURRENT dissolved into `Ventures`) and D-032
  (the archive is `--ARCHIVE`, CONTENT-EXTRA sits inside it, `G:\My Drive\Personal`
  retired); was proposed until the first move manifest is frozen
- Decision: use `H:\My Drive\CURRENT`, `H:\My Drive\ARCHIVE` and
  `H:\My Drive\CONTENT-EXTRA`, while leaving the protected ContentLibrary
  unchanged and retaining personal material under `G:\My Drive\Personal`.
- Reason: this yields one business current tree, one business archive, a named
  media intake and a clear privacy boundary.
- Revisit trigger: move-manifest review or conflict with the active machine
  routing policy.

## D-011: generated does not mean immediately deletable

- Date: 2026-10-04
- Status: locked
- Decision: generated-tree evidence creates a cleanup candidate only. Deletion
  still requires rebuild proof, an exact manifest and action-time validation.
- Reason: generated directories can contain unique configuration or accidental
  user work despite their conventional names.
- Revisit trigger: none.

## D-012: the engine is a sealed stage conveyor

- Date: 2026-10-04
- Status: locked
- Decision: each capability owns one bounded task and hands a sealed artifact
  to the next stage. Survey, inventory, verification, classification, size
  filtering, edge signatures, whole hashes, duplicate evidence, structure,
  reclaim and destination QA remain separate concerns.
- Reason: interruption, partial access or a defect in one stage must not make a
  later stage guess or silently broaden its authority.
- Revisit trigger: none; new capabilities join through an explicit stage or
  declared extension of one existing owner.

## D-013: recommend H CURRENT as business authority

- Date: 2026-10-04
- Status: superseded by D-031 (CURRENT no longer exists); was proposed until
  routing policy is reconciled
- Decision: recommend revising the machine routing rule for single-venture
  deliverables from `G:\My Drive\Ventures\Active` to
  `H:\My Drive\CURRENT\10_VENTURES`, making G personal-only and H the one
  business-current authority requested for this consolidation.
- Reason: two canonical current-work roots defeat the stated end state and make
  autonomous routing ambiguous.
- Revisit trigger: acceptance or rejection at the first structure manifest.

## D-014: cloud metadata does not establish content identity

- Date: 2026-10-04
- Status: locked
- Decision: retain G, H and OneDrive rows in the inventory when metadata is
  readable, but exclude provider-refused content from duplicate and uniqueness
  conclusions. Carry those rows as a source-specific retry queue.
- Evidence: this run inventoried the mounts but could not read content for all
  8,176 G candidates, all 6,270 H candidates and 1,025 OneDrive placeholders.
- Revisit trigger: provider access returns and the retry pass produces sealed
  content evidence.

## D-015: accepted shallow information architecture

- Date: 2026-10-04
- Status: locked
- Decision: H is the business-current and business-archive authority; G
  `Personal` is the private-record authority. Both use a single shallow
  category layer. Current business categories are Mind/make, mindmakeOS,
  Fractionl, Full-time, Legibility, makeyourmindup, DoThinkDo, business theory
  and corpuses, Cold Ideas and Inspo, and business administration. Labs is not
  active and receives no current-work folder.
- Reason: Krish accepted every recommended default, marked Labs unimportant,
  and confirmed that historical Mindmaker names normalize to Mind/make while
  Mindmake-OS/mm-ctrl/control-center normalize to mindmakeOS.
- Revisit trigger: an explicit change to a venture or customer lifecycle.
- Amended by D-031 and D-032: the business-current categories and
  `G:\My Drive\Personal` it names no longer exist (D-031 dissolved CURRENT into
  `Ventures`; D-032 retired `Personal`).

## D-016: 31 days controls line of sight, not preservation

- Date: 2026-10-04
- Status: locked
- Decision: ordinary venture deliverables older than 31 days route out of
  CURRENT. Identity, immigration, finance, medical, property, completed forms,
  life admin, canonical systems, business theory, corpuses, critical source
  work and active-customer material are evergreen. Age alone never authorises
  deletion.
- Reason: Krish wants a two-second current view without losing scarce records
  or foundational theory.
- Revisit trigger: explicit retention-policy change.
- Amended by D-031: CURRENT no longer exists. In the `Ventures` layout each
  venture's `_Archive` takes anything older than 30 days, while
  `policy/estate-policy-v1.json` still has `visibility_days: 31`.

## D-017: permanent deletion waits for verified external backup

- Date: 2026-10-04
- Status: locked
- Decision: before the consolidated estate has a verified external backup,
  deletion candidates may only enter a dated quarantine. Permanent purge is a
  separate maintenance action after the accepted 30-day retention period.
- Reason: Krish accepted the recommended deletion defaults and intends to back
  up the single archive externally.
- Revisit trigger: verified external-backup receipt plus expiry of quarantine.
- Applied 2026-10-11: an explicit action-time instruction waived the 30-day
  wait for one backed-up, revalidated manifest only (`docs/RUN-2026-10-11.md`).
  The rule above is unchanged for any later quarantine.

## D-018: family admin preserves Google ownership

- Date: 2026-10-04
- Status: locked
- Decision: Maa and Loz are family administration. Their Google-native
  originals remain in the owning H account under `FAMILY-ADMIN`; G Personal
  contains the canonical personal index and shortcuts. `Lozatron Briefings`
  is inside Loz. Maa and Loz are never deletion candidates.
- Evidence: Windows cross-account move failed without changing either source;
  Drive metadata moves then preserved both folder IDs and verified their new
  parent.
- Revisit trigger: a verified ownership transfer to the personal account.
- Amended by D-031 and D-032: the folder is now `H:\My Drive\Family Admin`
  (`Krish`, `Loz`, `Maa`), and the policy preserves `Family Admin\Maa` and
  `Family Admin\Loz`.

## D-019: G business-native ownership is an explicit noncanonical exception

- Date: 2026-10-04
- Status: locked
- Decision: business files owned by the personal Google account move under
  `G:\My Drive\_BUSINESS-NATIVE-OWNERSHIP`. Readable binaries are copied to
  the appropriate H category; Google-native originals remain in G so their
  IDs, sharing and revision history survive. New business work belongs in H.
- Reason: a cross-account filesystem move cannot safely transfer native Google
  ownership, while leaving the files loose in G creates a second apparent
  business authority.
- Revisit trigger: a verified native ownership transfer to the H account.
- Amended by the 2026-10-23 folder record: `G:\My Drive\_BUSINESS-NATIVE-OWNERSHIP`
  is not among the folders recorded on G, and a folder of that name is recorded
  under
  `H:\My Drive\--ARCHIVE\04_DEVICE-AND-SERVICE-EXPORTS\G-Business-Retirement-20261011`.
  The repository does not say whether the Google-native originals moved with it.

## D-020: source cleanup means recoverable retirement before backup

- Date: 2026-10-04
- Status: locked
- Decision: after a cross-volume destination is SHA-256 verified, the source
  may move into a dated quarantine. Massive generated trees may use a
  same-volume atomic directory relocation with a shallow seal because that
  operation retains all child bytes and makes no content-identity claim.
- Reason: the visible estate can be made usable now without pretending the
  external-backup and 30-day destruction gates have been met.
- Revisit trigger: verified external backup plus quarantine expiry.

## D-021: recursive proposals execute through a separate copy boundary

- Date: 2026-10-04
- Status: locked
- Decision: recursive classification output never mutates the estate directly.
  A separate module admits only explicitly allowed dispositions and confidence
  levels, revalidates source metadata, hashes readable content, preserves
  source-relative provenance beneath a named cohort, and emits the existing
  verified-copy contract.
- Reason: analysis and mutation have different failure modes. Keeping the
  boundary explicit lets future autonomous runs improve classification without
  silently broadening what may be copied or retired.
- Revisit trigger: a new copy contract with equal or stronger independent
  verification.

## D-022: credential-like files are movable without content inspection

- Date: 2026-10-04
- Status: locked
- Decision: credential-classified rows never enter ordinary canonical copies.
  A direct credential-like file may move only to a same-volume secure local
  quarantine under a metadata-only manifest that does not open, hash or log
  its content.
- Reason: leaving secrets loose is unsafe, while hashing them still reads the
  secret material and is unnecessary for a same-volume recoverable move.
- Revisit trigger: an approved encrypted secret-store import with a receipt
  that exposes no secret content.

## D-023: layout proposals preserve inventory timestamps as strings

- Date: 2026-10-04
- Status: locked
- Decision: inventory JSON is deserialized with `-DateKind String` when a
  layout proposal is built, and the proposal-to-copy boundary compares the
  original round-trip timestamp at execution.
- Evidence: the first L proposal converted timestamps through the machine
  display culture; all 18 passport/family-image rows then correctly failed
  action-time metadata revalidation. No copy was admitted. The parser and a
  sub-second regression fixture now enforce the fix.
- Revisit trigger: never without an equally precise identity field.

## D-024: system metadata is excluded at every copy boundary

- Date: 2026-10-04
- Status: locked
- Decision: proposal classification may never override the copy boundary's
  explicit exclusion of `desktop.ini`, `Thumbs.db` and `.DS_Store`.
- Evidence: a temporary-family path rule classified a nested `desktop.ini`
  before the basename rule could see it. Google Drive did not materialize the
  copied metadata file, so destination readback correctly stopped the batch.
  The boundary now excludes these names independently of classification.
- Revisit trigger: never; these files are regenerated platform metadata.

## D-025: live-copy retirement inherits the frozen source root

- Date: 2026-10-04
- Status: locked
- Decision: a live-file copy receipt may produce a retirement manifest only
  when its exact copy manifest is supplied and hash-matches the receipt. Source
  provenance is calculated from that manifest's `SourceRoot`, never from the
  first copied file's parent.
- Reason: one recursive batch can span unrelated subfolders. Using the first
  file's parent falsely makes later verified sources appear to escape the
  retirement boundary.
- Revisit trigger: a receipt schema that embeds and authenticates SourceRoot.

## D-026: live-file copy progress is durable per file

- Date: 2026-10-04
- Status: locked
- Decision: the live-file copy executor appends one compact progress row after
  each destination readback succeeds. A restart still revalidates source and
  destination content rather than trusting that journal.
- Reason: a 2,753-file cloud copy produced no visibility until its final
  receipt even though its idempotent destination checks made it technically
  resumable. Durable progress is needed for autonomous operation and diagnosis.
- Revisit trigger: a transactional receipt store with the same per-file
  durability and independent readback semantics.

## D-027: dirty local work needs an off-machine recovery artifact

- Date: 2026-10-04
- Status: locked
- Decision: a local dirty-worktree snapshot is not independently preserved
  until an integrity-checked package has also been copied and SHA-256 read back
  from a non-local authority. The original worktree remains untouched.
- Reason: a second path on the same machine protects against an editing error,
  not machine loss or network disconnection. Git remotes do not contain
  uncommitted and untracked work.
- Revisit trigger: the exact dirty state is committed and proven on a durable
  remote, or another independently verified off-machine copy exists.

## D-028: parallel copy work is partitioned in frozen manifests

- Date: 2026-10-04
- Status: locked
- Decision: large small-file copy manifests may be parallelized only by a
  deterministic index partition whose shard counts and unique destinations
  reconcile exactly to the authenticated parent manifest.
- Reason: cloud per-file latency dominated 1 GB batches. Ad-hoc worker filters
  risk overlap, omission and conflicting writes; frozen shards retain the
  ordinary action-time validation and destination readback contract.
- Revisit trigger: a transactional work queue with equivalent exactly-once
  partition evidence.

## D-029: an absent copy source is satisfied only by its frozen destination hash

- Date: 2026-10-04
- Status: locked
- Decision: when a verified source was independently retired before an
  overlapping parent copy finished, a residual manifest may omit that row only
  if the destination exists and its current whole-file SHA-256 equals the
  frozen parent row. Otherwise the run stops.
- Reason: source absence alone is never success, while re-copying a source that
  has already moved to quarantine is impossible and unnecessary when the exact
  destination objective is independently re-derived.
- Revisit trigger: a unified receipt graph that records the same relationship.

## D-030: Krish's folders move only with his yes, folder by folder

- Date: 2026-10-23
- Status: locked
- Decision: inside a watched root (`H:\My Drive`, `G:\My Drive`,
  `C:\Users\krish\dev`) no folder is moved, renamed, merged or removed
  without a consent row in `policy/folder-preferences.json` naming that folder
  and action, approved by Krish. A folder the record does not know is new,
  waiting on Krish, and nothing inside it moves. The folder tree as Krish
  recorded it is his preference and outranks the older routing rules in
  `policy/estate-policy-v1.json`. A weekly check-in asks him about every new
  folder and counts any recorded folder gone without his OK.
- Reason: Krish, 2026-10-23: a folder he made on H was gone the next day. The
  engine called every unexpected top-level folder an issue and removed any
  empty folder under the root it was pointed at.
- Ruling (Krish, 2026-10-23): filearchives never moves a folder Krish made
  without asking first.
- Revisit trigger: only Krish.

## D-031: H CURRENT and PERSONAL-SYSTEMS are dissolved into Ventures

- Date: 2026-10-22
- Status: locked
- Decision: `H:\My Drive\CURRENT` and `H:\My Drive\Family Admin\PERSONAL-SYSTEMS`
  no longer exist. Business work lives in `H:\My Drive\Ventures` (one folder per
  active venture, `_Archive` inside each for anything older than 30 days, and
  `Ventures\_Archive` for retired ventures). Personal material lives in
  `H:\My Drive\Family Admin\Krish`. Exact duplicates were sent to Drive Trash
  with a verified surviving copy. This supersedes D-010 and D-013 for the
  business current tree. The policy's `business_current` destination is set
  to a non-path sentinel so any future run stops instead of recreating CURRENT.
- Reason: Krish asked for one venture-shaped home with nothing stale in the
  line of sight. The engine's shallow-folder rule cannot express nested
  venture paths without a redesign.
- Evidence: `C:\Users\krish\.scratch\h-reorg-20261022\` (manifest.frozen.csv,
  receipts.jsonl, ventures_pre.tsv, verify.txt).
- Revisit trigger: the next engine run that needs a business current
  destination; remap `business_current` to venture paths first.

## D-032: the folder record is the authority; FamilyContentLibrary is never entered

- Date: 2026-10-23
- Status: locked
- Decision: `H:\My Drive\ContentLibrary` was renamed `FamilyContentLibrary`.
  It replaces ContentLibrary everywhere D-001 applied: no run enumerates,
  hashes, compares, moves or deletes inside it. The old name stays excluded in
  case it returns. The never-enter list in `policy/folder-preferences.json` is
  added to every workspace's protected roots, so a machine config that still
  names the old folder cannot let a run in. The 99 folder names the first
  snapshot recorded inside it were removed from the record.
- Decision: Krish's recorded folder tree is the authority for where things
  live. The canonical audit checks the drives against it instead of the
  2026-10-04 category lists. In the estate policy, `business_archive` is
  `H:\My Drive\--ARCHIVE`, `content_extra` is `--ARCHIVE\CONTENT-EXTRA`, the
  preserved family folders are `Family Admin\Maa` and `Family Admin\Loz`,
  and `personal` is retired like `business_current` (D-031): `G:\My Drive\Personal`
  no longer exists. Retired destinations are never recreated.
- Reason: Krish, 2026-10-23: "it's the renamed ContentLibrary, exclude it, and
  update everything to match current status."
- Revisit trigger: Krish reorganises a drive again; record it with
  RECORD-MY-FOLDERS.cmd.

## D-033: the top of his Drive, and where an AI files what it cannot place

- Date: 2026-10-24
- Status: locked
- Decision: the top of `H:\My Drive` is `Ventures`, `--ARCHIVE`,
  `Family Admin`, `FamilyContentLibrary`, `KeePass` and `Inbox from My AI`.
  `Ventures` is where everything now lives, in four parts: `Active Ventures`
  (every venture being worked on, one folder each, which mind/make OS, Control
  Center and the AI harness use and keep up to date alongside this record),
  `Inspiration` (things that inspire him: `Content Inspo`, `Production Inspo`),
  `Bugs & Issues` (bugs and issues he notices on his phone) and `_Archive`.
  `Inbox from My AI` replaces `CURRENT\00_INBOX` (gone with CURRENT, D-031) as
  the one place an AI session files something it cannot place; Krish files it
  from there. `FamilyContentLibrary` and `KeePass` never move.
- Reason: Krish, 2026-10-24: "just reinstate that in the root folder then",
  "Ventures is where everything now lives (their subfolders. If I notice bugs
  or issues while on my phone, I put them in Bugs and Issues, i put things that
  inspire me in Inspiration, and Active Ventures contains all the main ventures
  we are working on, and that the entire OS/control center/AI harness is
  expected to use and keep up to date alongside the filearchives repository)",
  and "KeePass and FamilyContentLibrary are immovable."
- Elsewhere: the Drive map other systems read (`system_config
  drive_destinations`, krishanraja/hunter `drivemap.py`) names these areas and
  `Inbox from My AI` by folder ID; Claude sessions' Drive guard
  (krishanraja/control-center `.claude/hooks/drive_guard.py`) points at it.
- Revisit trigger: Krish reorganises the top of his Drive again; record it with
  RECORD-MY-FOLDERS.cmd and update the Drive map.

## D-034: his network exports live in Ventures\Network & Contacts, one dated folder each

- Date: 2026-10-26
- Status: locked
- Decision: every network export (LinkedIn, Instagram, Facebook) lives in
  `H:\My Drive\Ventures\Network & Contacts` (Drive folder
  `1715WkXXj--sqDmOJL0K15F_6N1EHFeuh`), one folder per export, named
  `<Network> Export - <Mon YYYY>` for the month the export was taken. The date
  is read from the export itself (its newest connection, message or follow),
  not from when it reached the Drive. On 2026-10-26 they were moved out of
  `--ARCHIVE` by Drive API, which keeps every file and folder ID:
  - `LinkedIn Export - Feb 2026` (newest connection 16 Feb 2026) was
    `99_DELETE-QUARANTINE\H-Career-Binaries-20261004\Linkedin Complete Export`.
    Two copies of the same export sit inside it: `Google Sheets copies` (was
    `04_DEVICE-AND-SERVICE-EXPORTS\Google-Native-Ownership\Career\Linkedin Complete Export`)
    and `Connections copy from OneDrive` (was
    `90_UNCLASSIFIED-UNIQUE\L-OneDrive\Documents\Linkedin Profile Export`,
    the same Connections.csv: same size, same rows).
  - `LinkedIn Export - Aug 2026` (newest message 6 Aug 2026) was
    `90_UNCLASSIFIED-UNIQUE\L-Downloads-Unclassified\My Contacts\LinkedIn Connections - August 2026`.
  - `Instagram Export - Jul 2026` (newest follow 23 Jul 2026) was
    `...\My Contacts\Instagram`.
  - `LinkedIn Export - Mar 2025` (newest connection 4 Mar 2025, newest
    invitation 2 Mar 2025) is a new folder holding the six export files that
    were loose in
    `04_DEVICE-AND-SERVICE-EXPORTS\E-Drive\Surface Laptop Backup July 2025\AdFixus`
    (Connections, messages, Invitations, Positions, Email Addresses, Company
    Follows). The AdFixus outreach sheets built from it stayed where they were.
- No Facebook export is in his Drive (krish@mindmake.co). The only folder
  named Facebook is empty and sits inside FamilyContentLibrary, which is never
  entered. The Meta export Control Center imported on 2026-10-04 was not kept
  here; when he finds it, it goes in as `Facebook Export - <Mon YYYY>`.
- The Apify-enriched follower lists built from the Instagram export
  (`instagram_followers_full.csv`, `instagram_followers_enriched.json`) were
  loose in `90_UNCLASSIFIED-UNIQUE\L-Downloads-Unclassified`; they sit in
  `Instagram Export - Jul 2026` beside the export since 2026-10-26 (Krish:
  "yes follower lists moved in").
- `My Contacts`, empty once its two exports left, went to Drive Trash on
  2026-10-26 with a delete consent row recorded first (Krish: "delete My
  Contacts too"). Drive keeps it in Trash for 30 days.
- Left in place on purpose: the copy of the enriched list the engine already
  quarantined in
  `Exact-Duplicates-20261004\7e`, his `Career\Network\NYC Networking Tracker
  - 2026`, and the Instagram-named phone video folders.
- Consent: five move rows in `policy/folder-preferences.json` `consents`, one
  per moved folder, recorded before the move, and a sixth, a delete row for
  `My Contacts`, recorded before it went to Trash. Two folders the record
  already held left: `H-Career-Binaries-20261004\Linkedin Complete Export` and
  `My Contacts` (both depth 4). Each counts as moved or removed with his OK at
  the next check-in, not as gone. `Network & Contacts` is answered in
  `docs/folder-checkin/answers.json`.
- Elsewhere: nothing else needed a change, checked 2026-10-26. Control
  Center's LinkedIn importers (krishanraja/control-center `api/_driveFile.ts`) read Drive by file ID,
  which a move keeps. hunter's `bridges <dir>` and Control Center's
  `scripts/network/import-instagram.ts --dir` take a local folder each run and
  store no path. The Drive map (`system_config drive_destinations`) names the
  roots by ID, and Ventures is one. No repository, Supabase table or
  system_config row held the old paths or IDs.
- Reason: Krish, 2026-10-26: "can you move all my network exports (instagram,
  facebook, linkedin) from Archive in to [Network & Contacts] and update
  everywhere that relies on knowing where it currently is? Mark each folder
  with the date of the export (eg Linkedin is Feb 2026)".
- Revisit trigger: a new network export lands in his Drive, or the Facebook
  export is found.

## D-035: dev clones live in their venture's folder, moved only with his yes

- Date: 2026-10-29
- Status: built; no move has run
- Decision (Wave 3 W3.4, from the Make Your Mind Up brief of 28 October):
  - `policy/repo-ventures.json` maps each GitHub repository to a venture and
    names where a venture's clones live. Make Your Mind Up's home is
    `C:\Users\krish\dev\makeyourmindup`, with worktrees in its `.worktrees`,
    as the Wave 2 W2.11 layout set. Its repositories: makeyourmindup,
    growth-makeyourmindup, content-engine and content-watcher.
    inspirationhouse is `shared` and does not move (Krish, 2026-10-29: it "has
    a ledger for every venture, but in reality 99% of its work is for
    makeyourmindup right now though that may change"). sendlinks sits with
    Control Center (Krish: "a part of control center but standalone
    machinery"). hunter, krish-raja, kimon, dipti-health, lozatron,
    getaround.london, merciless, fractionl-homepage and conclusiv are
    `out_of_scope` and the report leaves them out (Krish: "standalone/personal
    projects you dont need to be across"). Any other repository not in the
    map is `unplaced`, never guessed.
  - The `C:\Users\krish\dev` watch depth is 2, so the record and the weekly
    check-in see each folder inside `dev\krishanraja` and `dev\mindmake`.
    Folders already there one level down are not in his record, so the next
    check-in lists them as new, waiting on him; nothing moves because of that.
  - `stages\05_classify\report_dev_sprawl.ps1` writes
    `docs/folder-checkin/SPRAWL.md` and `sprawl.json` every Monday with the
    check-in: clones and worktrees, dirty and unpushed work, stashes, sizes,
    duplicates, and the number of Make Your Mind Up clones outside its home.
    It only reads.
  - `chains\chain_dev_consolidation.ps1` writes one consent row per proposed
    move to `docs/folder-checkin/move-requests.json`. With `-Execute` it
    snapshots every dirty repository outside dev, then moves only the folders
    Krish said yes to, to the exact destination he named, through the guarded
    folder-move pair, and proves Growth's `.scratch` arrives byte for byte. A
    second clone of the same repository waits in `.duplicates` for his call;
    removing it is a separate delete consent. Worktrees move with
    `git worktree move`, never as folders.
- Proof: `tests/test_dev_sprawl.ps1` on a synthetic dev folder (report
  read-only to the byte, nothing moves without a yes, a yes for another
  destination releases nothing, snapshot before move, `.scratch` intact, the
  number reaches 0 after his consents); `tests/test_new_folder_survives.ps1`
  passes with the change.
- Ruling (Krish, 2026-10-23): filearchives never moves a folder Krish made
  without asking first.
- Revisit trigger: Krish places an unplaced repository, gives a venture a
  home, or answers for the dev folders the deeper watch finds.

