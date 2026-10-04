# Decision log

Append-only record of consequential decisions for the filearchives engine and
the current consolidation. Operational progress stays in `RESUME.md`.

## D-001: ContentLibrary is outside the session

- Date: 2026-10-03
- Status: locked
- Decision: `ContentLibrary` is a hard exclusion boundary. The engine must not
  enumerate, index, hash, compare, move, rename or delete content below a
  configured protected root.
- Reason: Krish explicitly excluded it from the entire session.
- Revisit trigger: only a new explicit instruction from Krish naming the exact
  root and newly authorised operation.

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
- Status: proposed until the first move manifest is frozen
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
- Status: proposed until routing policy is reconciled
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

## D-017: permanent deletion waits for verified external backup

- Date: 2026-10-04
- Status: locked
- Decision: before the consolidated estate has a verified external backup,
  deletion candidates may only enter a dated quarantine. Permanent purge is a
  separate maintenance action after the accepted 30-day retention period.
- Reason: Krish accepted the recommended deletion defaults and intends to back
  up the single archive externally.
- Revisit trigger: verified external-backup receipt plus expiry of quarantine.

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
