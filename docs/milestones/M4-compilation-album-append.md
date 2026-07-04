# Milestone 4 — Compilation-Album append (first Collection Policy)

*Build order for Codex. Architect/editor-in-chief: this doc is the contract; the
strategic arc is in [../implementation-plan.md](../implementation-plan.md)
(Phase 6, Collection Policy Metadata Prep), the policy in
[../metadata-policy-model.md](../metadata-policy-model.md) (see **Compilation-Album
(Append) Policy**), and `/Users/jon/code/jon-platform/AGENTS.md`. Where this doc
and those conflict, stop and flag it — don't silently diverge.*

## Sequencing note (architect → Jon)

This is the **first Phase 6 milestone** and a different product area from the
live-show import path (M1–M3). It does **not** depend on M3's remaining slices
(Slice 2 library-verify, Slice 3 cleanup), but it **reuses** M3's `MusicAppClient`
read surface + `MusicLibraryMatcher` for its certification step, so it reads best
*after* M3 Slice 0/1 have landed (they have). Whether M4 preempts finishing M3 or
follows it is **Jon's call** — the architect will not reorder the queue
unilaterally. Nothing here blocks M3.

## The milestone in one sentence

Stand up a small **registry** of the curated "compilation albums" Jon already
maintains in Apple Music (seeded by dropping folders, never by browsing the
library), and give each one a one-gesture **append** flow — point at a folder of
new songs, stamp them with that album's exact identity + a fixed policy ruleset
(Album Artist as owner, strip track/disc, keep-else-fallback artwork), import the
derived copies, and **certify they merged into the existing album** rather than
spawning a duplicate — all **without ever mutating an original**.

## Why this is M4 (and where it stops)

M1–M3 built the live-show *import* path. M4 opens **Collection Policy** with its
most concrete, self-contained instance: the append-to-an-existing-compilation
workflow from the policy doc. It is deliberately narrow.

- **It manufactures nothing.** The albums, their cover art, and the 2-second
  silent "carrier" track (the album's *only numbered track*, Jon's Apple Music
  cover-art hack) **already exist and stay Jon's manual concern.** M4 only ever
  touches the folder of *new songs* being added, so the carrier track and its
  number are never at risk.
- **It avoids the library entirely for discovery.** Jon's library is out of
  control; browsing it is the pain this feature exists to remove. The registry is
  a small (~10–20 entry) SQLiteData set, **seeded from folders**, not a mirror of
  Music.app. M4 touches Music.app only at the certification step.
- **It reuses the proven write→import→verify spine.** Producing safe derived
  copies (`Working/`), tagging them, optional FLAC→ALAC, importing via
  `MusicAppClient`, and reading the library back all exist from M2/M3. The new
  work is *policy stamping* and *identity-drift certification*, not new plumbing.
- **Identity-match is the whole ballgame.** Because the merge key (`Album` /
  `Album Artist`) is read from **file tags** but Apple Music may have mutated it on
  a prior import, an append can silently create `Great Covers 2` instead of
  merging. Certification exists to catch exactly that, loudly.

The clean seam at the end: a curated album is a registry entry; a folder of new
songs goes stamped → `Working/` → (optional ALAC) → **Apple Music** → green
"merged, count went up, still one album," originals byte-for-byte untouched. What
is left for later is the broader Collection Policy surface (Grouping smart
playlists, MusicBrainz, general folder-token application) and any in-place source
retagging.

## Definition of done

A reviewer can, in the running macOS app:

1. **Seed the registry from folders.** Drop one album's folder → the app reads the
   contained files' tags, proposes an entry (Album, Album Artist, a thumbnail
   lifted from the folder's embedded art), and Jon confirms. Drop a **parent**
   folder of album subfolders → the app discovers each subfolder and shows a
   checkable list; checking a subset persists those entries. Entries appear in a
   workspace list showing image + title.
2. **Append to a chosen album.** Pick an entry, point at a folder of new songs,
   and get a **preview diff** (current vs proposed tags per file, fields
   preserved, artwork keep-vs-fallback per song). On confirm, the app writes the
   stamped tags to **`Working/` copies** (originals untouched), converts FLAC→ALAC
   where applicable (reuse M2), and imports the produced files via `MusicAppClient`.
3. **See a certification result.** After import, a panel shows: an album with this
   exact `Album` / `Album Artist` exists, its track count **increased by the number
   of songs added**, and **no second album** with a near-identical title appeared.
   A drift/duplicate condition is surfaced as **not certified**, with the
   mismatch, not silently accepted.
4. **Confirm originals are unchanged** in Finder — the only writes are to
   `Working/`/`Output/`; nothing outside them is mutated; import is additive.

Invariants that must hold at merge:

- `swift build` / `swift test` green; new pure logic (registry seeding derivation,
  the compilation apply-plan, keep-else-fallback branching, certification
  comparison) is covered by tests driven through mockable `@Dependency` clients
  (`AudioMetadataClient`, `MusicAppClient`, DB). Live ScriptingBridge / tool
  spawning stays behind those clients.
- **Originals are never moved, renamed, retagged, trashed, or overwritten.** All
  tag writes target `Working/` copies (reuse the M2 apply/convert safety model).
  Import is additive — **no library deletions**. (Grep-able: no `removeItem`/trash
  outside the inherited `Working/` cleanup gate.)
- House stack honored: no TCA, no SwiftData; value-type records; `@Observable`
  feature models; `@Dependency` clients; swift-navigation `Destination`;
  SQLiteData for the registry + run log with observed reads.
- The registry is the **only** new persisted state; it is app-owned metadata Apple
  Music cannot hold (per the policy doc's storage-ownership rule), not a shadow
  catalog of library presence.

## In scope

- **Registry**: a `CompilationAlbum` SQLiteData record (identity + display +
  ruleset + seed provenance) and its editor/list UI.
- **Folder seeding**: single-folder and parent-folder-discovery ingestion; derive
  identity + thumbnail from the contained files (`AudioMetadataClient`); tie-break
  when files disagree.
- **Policy stamping engine** (extends `AudioTaggingCommands`, pure plan):
  - Set `Album` / `Album Artist` from the entry (remove-then-set on the one
    canonical field — the pattern already used).
  - **Strip** track + disc tags (new: the engine currently always *writes* them).
  - Add `Grouping` token(s) (new tag).
  - Set/clear the `Compilation` flag (new tag; default clear).
  - **Keep-else-fallback artwork**: reuse the existing cover-embed path, but drive
    `coverURL` per-track off `AudioTags.hasEmbeddedArtwork` (present → preserve;
    absent → the entry's fallback image).
- **Append flow**: pick entry → scan new-songs folder → preview diff → apply to
  `Working/` → reuse M2 convert → import (M3 `MusicAppClient.add`).
- **Certification**: reuse `MusicAppClient` read + `MusicLibraryMatcher`; assert
  exact-identity album exists, count increased by the added-song count, and no
  duplicate-spawn; a `RunRecord` records the outcome.
- **Preview**: honor the policy doc's *Preview Requirements* — current vs proposed,
  fields preserved, artwork source per song, before any write.

## Out of scope — with destinations

| Deferred | Goes to | Why not now |
|---|---|---|
| Creating albums / generating the silent carrier track / managing album-level art | **manual (Jon)** | Explicitly Jon's hack; M4 appends to what exists |
| General Collection Policy editor, Grouping smart-playlist generation, artist-narrowed membership | **later Phase 6** | M4 is the compilation-append instance only |
| MusicBrainz lookup + ranking, canonical-artwork selection | **Phase 6** | Not needed to append to a hand-curated album |
| In-place **source** retagging (writing tags back onto originals) | **Phase 6+** | M4 writes derived copies only, like M2/M3 |
| Full album-artist-variant **enumeration/deletion** across formats | **certify-not-enumerate** | Write the one canonical field + certify; strip a variant only if certify shows Music is confused |
| Removing tracks from a compilation / editing already-imported members | **Phase 7** | M4 is additive append + verify |
| Batch-append across multiple registry entries in one run | **M-later** | Prove single-entry append first |
| Reconcile UI when identity drift is found (re-point entry at the real album) | **fast-follow** | M4 surfaces drift as not-certified + mismatch; auto-reconcile is its own slice |

## Relationship to the evidence

There is no `music_pipeline.sh` step for this — it is the manual Apple Music work
Jon does by hand today: build the album once (carrier track + art), then drag new
songs in and fix their tags so they file under the album instead of scattering the
real artists across the Artists list. M4 reimplements the *durable* half of that
(identity stamp + strip + import + "did it merge?") app-native, and leaves the
album-construction hack manual on purpose.

## Architecture & module layout

```
VinylFeverCore/Sources/VinylFeverCore/
├── Model/         # + CompilationAlbum, AlbumIdentity, CompilationRuleset,
│                  #   CompilationApplyPlan, AppendCertification — value types
├── Collection/    # + pure: registry seeding derivation (identity + tie-break),
│                  #   compilation apply-plan builder, keep-else-fallback decision,
│                  #   certification comparison (no ScriptingBridge, no tool spawn)
├── Tagging/       # AudioTaggingCommands extended: strip track/disc, GROUPING,
│                  #   COMPILATION, per-track coverURL from hasEmbeddedArtwork
├── Clients/       # reuse AudioMetadataClient, MusicAppClient, FileOperationClient,
│                  #   ScriptClient, RunLogClient — no new client expected
└── Database/      # + CompilationAlbum table; RunRecord.Kind case(s) below
```

Boundary rule (restated): the **core package stays pure**. Seeding derivation, the
apply-plan, the keep-else-fallback branch, and the certification comparison are all
pure and live in `Collection/`; the actual tag writes, tool spawning, and
ScriptingBridge calls stay behind the existing `@Dependency` clients so the whole
flow is unit-testable offline.

## Domain model (shape, not final — refine in code, flag big changes)

```swift
// Registry entry ------------------------------------------------------
struct AlbumIdentity: Equatable, Sendable {   // the merge key
  var album: String
  var albumArtist: String                     // the owner identity, e.g. "Jon Phillips"
}
struct CompilationRuleset: Equatable, Sendable {
  var stripTrackAndDisc: Bool = true          // default ON (per-album toggle)
  var setCompilationFlag: Bool = false        // default OFF (per-album override)
  var groupingTokens: [String] = []           // added to Grouping (` | ` delimited)
  // artwork policy is fixed for this milestone: keep original, else fallback image
}
struct CompilationAlbum: Identifiable, Equatable, Sendable {
  let id: UUID
  var name: String                            // workspace label
  var identity: AlbumIdentity
  var displayImage: Data?                      // workspace thumbnail (NOT embedded by VF)
  var fallbackArtwork: Data?                   // embedded ONLY into songs lacking art
  var ruleset: CompilationRuleset
  var seedFolderPath: String?                  // provenance
}

// Append ---------------------------------------------------------------
enum ArtworkDecision: Equatable { case keepExisting, applyFallback }
struct CompilationTrackPlan: Identifiable, Equatable {
  let id: UUID
  var sourceURL: URL
  var current: AudioTags
  var proposed: AudioTags                      // track/disc = nil when stripped
  var artwork: ArtworkDecision                 // from current.hasEmbeddedArtwork
}
struct CompilationApplyPlan: Equatable {
  var entry: CompilationAlbum
  var tracks: [CompilationTrackPlan]
}

// Certification (drift catch) -----------------------------------------
enum AppendVerdict: Equatable {
  case merged                                  // album found, count += added
  case albumNotFound
  case duplicateSpawned(otherTitle: String)    // a near-identical album appeared
  case countMismatch(expected: Int, actual: Int)
}
struct AppendCertification: Equatable {
  var run: RunRecord
  var verdict: AppendVerdict
  var isCertified: Bool { verdict == .merged }
}
```

`track/disc = nil` must be **representable and meaningful** (stripped), not a
sentinel — prefer optionals over `-1`. `AppendVerdict` is a typed enum so drift is
a first-class state, never a silent pass.

## The slices (each is one PR into `main`)

`main` is protected — each slice is a branch + PR, small enough to review in one
sitting, each ending green (build + tests).

**Slice status (ledger).** The executor ticks the box in the slice PR that
completes it; GitHub PR state is canonical.

- [x] Slice 0 — Registry model + folder seeding (read-only)
- [x] Slice 1 — Policy stamping engine + preview (writes to `Working/`, no import)
- [ ] Slice 2 — Append + import + drift certification

### Slice 0 — Registry model + folder seeding (read-only)

`CompilationAlbum` (+ `AlbumIdentity`, `CompilationRuleset`) as SQLiteData records.
Seeding: drop a **single album folder** → scan → read each file's tags
(`AudioMetadataClient`) → derive the entry (identity + a thumbnail from the folder's
embedded art) → confirm → persist. Drop a **parent folder** → discover subfolders,
present a checkable candidate list (each with derived identity + thumbnail), persist
the checked subset. A workspace list view shows image + title with observed reads.
**Tie-break:** when a folder's files disagree on `Album`/`Album Artist`, most-common
value wins and the disagreement is surfaced (never silently picked). **No audio
mutation — reads only.** **Tests:** discovery classification (subfolder = candidate),
identity derivation + tie-break over mixed fixtures, thumbnail extraction, registry
persistence + observed list read. **Done when:** Jon can drop a folder (or parent of
folders) and see the curated albums registered with the right identity + cover.

### Slice 1 — Policy stamping engine + preview (writes to `Working/`, no import)

Extend `AudioTaggingCommands` and add the pure `CompilationApplyPlan` builder:
- **Strip track/disc** when `ruleset.stripTrackAndDisc` — FLAC: emit
  `--remove-tag=TRACKNUMBER/TRACKTOTAL/DISCNUMBER` with **no** `--set-tag`; ffmpeg
  (mp3/m4a): do not emit `track`/`disc` metadata and clear any inherited value.
  (The engine currently *always writes* these — this is the core change.)
- **Set `Album`/`Album Artist`** from the entry (remove-then-set on the canonical
  field — the existing pattern; do not enumerate variant album-artist keys).
- **Grouping**: add token(s), ` | ` delimited (new tag across all three formats).
- **Compilation flag**: set when `ruleset.setCompilationFlag`, else ensure clear.
- **Keep-else-fallback artwork**: per track, `coverURL = nil` when
  `current.hasEmbeddedArtwork` (existing art preserved via the current `0:v:0?` /
  no-picture path), else `coverURL = entry.fallbackArtwork` (reuse the existing
  `--import-picture-from` / ffmpeg mjpeg embed).
Apply writes to **`Working/` copies** (reuse the M2 apply/convert safety + executor
shape); a **preview diff** (current vs proposed per file, fields preserved, artwork
decision) is shown before any write. **Stops before import.** **Tests:** plan
correctness per format (strip omits track/disc, grouping/compilation set/clear,
artwork branch flips on `hasEmbeddedArtwork`); diff content; originals-untouched
safety. **Done when:** Jon previews and applies a policy stamp to `Working/` copies
and the tags/art match the ruleset, originals intact.

### Slice 2 — Append + import + drift certification

Tie it together: pick a registry entry → point at a new-songs folder → build the
`CompilationApplyPlan` → preview → apply to `Working/` (Slice 1) → reuse M2
FLAC→ALAC convert where applicable → **import** via M3 `MusicAppClient.add`.
Then **certify** (pure comparison over a `MusicAppClient` read, reusing
`MusicLibraryMatcher`): capture the target album's pre-import track count, and after
import assert an album with the exact `AlbumIdentity` exists, its count rose by the
number of songs added, and **no near-identical second album** appeared — producing
an `AppendCertification` recorded in a `RunRecord`. Drift/duplicate → **not
certified**, surfaced with the `AppendVerdict`. **Tests:** certification over mock
library snapshots (clean merge; album-not-found; duplicate-spawn; count mismatch);
append reduction (per-track outcomes, run summary). **Done when:** Jon picks an
album, drops new songs, previews, "tags away," and sees them land in the existing
album with a green certified verdict — or a loud not-certified with the reason.

#### Slice 2 build order (executor)

*Drafted 2026-07-03 after S0+S1 landed (#26). The prose above is the intent; this
is the task list. Where the two disagree, the prose wins — flag it.*

**Pinned decisions (do not re-litigate — these ride the documented defaults so the
slice can run; the two genuinely-open ones are deferred *by design* until a real
append shows how Apple Music mangles the strings):**

- **#1 Identity match = exact `Album` + `Album Artist`** for this slice. Do **not**
  invent normalization yet. If a real run mis-certifies on a trailing space / article,
  that's the *evidence* that resolves decision #2 — surface it, don't pre-fold it in.
- **#3 No-match behavior = import proceeds, run is `not certified`**, verdict
  surfaced. No blocking, no auto-reconcile (that's the deferred fast-follow).
- **#6 `RunRecord.Kind`:** reuse `.importLibrary` for the add; add **one** new case
  `.compilationCertify` for the verdict. Surface the new case in the PR body.
- #4 (tie-break) and #5 (fallback = workspace image) already shipped in S0/S1 on
  their leans; nothing new here.

**Tasks:**

1. **Certification core (pure, `Collection/`).** Add `AppendVerdict` +
   `AppendCertification` (shapes already in *Domain model* above). Write the pure
   comparator: input = pre-import album snapshot + post-import library read +
   added-song count; output = `.merged` / `.albumNotFound` /
   `.duplicateSpawned` / `.countMismatch`. No ScriptingBridge, no tool spawn.
2. **Extend the read surface.** `MusicAlbumReadRequest` today carries only
   `albumTitle` — certification needs the full `AlbumIdentity` (album **+ album
   artist**) to assert exact identity, and needs to see **sibling albums with a
   near-identical title** to catch a `Great Covers 2` duplicate-spawn. Extend the
   request/response (and the live `readAlbumTracks` impl) to return enough to make
   both calls; keep the live read behind `MusicAppClient` so the comparator stays
   offline-testable. Reuse `MusicLibraryMatcher` for the per-track resolution.
3. **Append flow wiring (app).** Extend `AppModel.applyCompilationPlan`'s successor
   path: after the `Working/` apply + M2 FLAC→ALAC convert, capture the target
   album's **pre-import** track count via the read surface, `MusicAppClient.add`
   the produced files, re-read, run the comparator, record a `.compilationCertify`
   `RunRecord`, and drive a certification panel in `CollectionsView`.
4. **Fold the #26 carry-over nits:**
   - Preview shows track/disc as *cleared* even when `stripTrackAndDisc == false`
     (engine actually **preserves** them on that path). Fix
     `CompilationApplyPlan.diffs` so the off-strip preview reflects "kept," not
     "→ —". ([CompilationApplyPlan.swift](../../VinylFeverCore/Sources/VinylFeverCore/Collection/CompilationApplyPlan.swift))
   - Add a **real-tool** integration assertion that ffmpeg's `compilation=` /
     `track=` empty-value clearing on **m4a** (via `-map_metadata 0`) actually drops
     `cpil`/`trkn`, not writes an empty/zero atom.
   - Fallback-artwork temp file is hardcoded `.jpg` regardless of the stored image's
     real format — cosmetic, fix opportunistically (name off the sniffed bytes).

**Live-Music guard (blocker to check first).** This is the first M4 slice to touch
Music.app. The M3 Slice 0→1 review flagged that the **live ScriptingBridge read +
`location`-primary matching were never exercised against a real imported album**
(Music's "copy to Media folder" may point `location` at the copied path, not
`Output/`). M4 certification leans on that same live read. **Before the live leg is
trusted, run the read-back device check** (shared with M3 S2). The pure comparator +
its tests are buildable now regardless; if the live read is still blocked pending the
macOS-27 beta-3 spike, land the pure half + mock-snapshot tests and mark the live leg
`question-for-architect` rather than shipping an unverified certify.

**Tests:** comparator over mock library snapshots — clean merge; album-not-found;
duplicate-spawn (near-identical sibling); count mismatch (short and over). Append
reduction (per-track outcomes → run summary). The m4a real-tool clearing assertion
above. Every pure path offline via `@Dependency`; the live read guarded on
availability and never the only coverage.

## Constants register (pre-justified — jon-platform "constants need a rationale")

- **Track/disc when stripped = absent, not zero.** For a crate of unrelated
  one-off songs, inherited track/disc numbers make album display + playback
  chaotic; the correct state is *no number*, represented as removed tags / `nil`,
  never `0`/`1` sentinels.
- **`Compilation` flag default = off.** Album Artist is the grouping lever; the
  `Compilation` flag routes into Apple Music's Compilations bucket, which is not
  wanted by default. Per-album override only.
- **Grouping delimiter = ` | `** (inherited from the policy doc; do not reinvent).
- **Album-artist cleanup = certify-not-enumerate.** Write the one canonical field
  (remove-then-set, already the engine's pattern) and certify it reads back; strip
  a variant key only if certification shows Music is confused. No cross-format
  variant enumeration in M4.
- **Identity-match normalization for certification.** Needs a rationale before use:
  exact-string match is safest but brittle to a trailing space; if any
  normalization is applied (trim / article-fold), pin it in the PR with a rationale
  and **reuse the M2/M3 title normalization** rather than inventing a second one.
- **Registry size is small by design (~10–20).** Not a paginated library mirror;
  no full-library scan path is introduced.

Inherited unchanged from M1–M3: supported extensions `{flac, mp3, m4a}`, derived
dirs `Working/`/`Output/`, ScriptingBridge as the Music.app surface, the Apple
Events entitlement.

## Decisions for Jon to confirm (not Codex's to make alone)

1. **Registry seeded from folders, never from a library browse.** *(Recommended —
   it's the anti-duplication and anti-toil posture.)* Confirm folder-drop +
   parent-discovery is the only seeding path in M4.
2. **Identity-match forgiveness.** Exact `Album`/`Album Artist` string match, or
   trim/normalize (whitespace, leading articles) before comparing? *(Lean: reuse
   M2/M3 normalization; flag the exact rule in the PR.)*
3. **Behavior when certification finds no matching album.** Block, warn-and-keep
   the import, or open a reconcile step to re-point the entry? *(M4 default: import
   proceeds but the run is **not certified** with the verdict surfaced; auto-
   reconcile UI is a deferred fast-follow.)*
4. **Seed-folder tie-break** when files disagree on identity: most-common wins
   (surfaced), or always prompt? *(Lean: most-common, surfaced.)*
5. **Fallback artwork source.** The entry's designated `fallbackArtwork` image
   (the workspace image reused), or a separately chosen file? *(Lean: reuse the
   workspace image as the fallback, overridable.)*
6. **New `RunRecord.Kind`.** Add a distinct `.compilationAppend` (and/or reuse
   `.importLibrary` for the add) so the run history stays legible? *(Lean: reuse
   `.importLibrary` for the add; add one `.compilationCertify` for the verdict.)*

## Working agreement

- Each slice: branch → PR → merge (main protected; self-merge after the
  architect's `approve`). Commit messages end with the `Co-Authored-By` trailer;
  PR bodies end with the tool trailer.
- Tests with swift-testing; control time/uuid/db/tools/Music via `@Dependency`.
  Every new pure path is covered offline; any real-Music integration check is
  guarded on availability and never the only coverage.
- New OS-26/27 + ScriptingBridge APIs are past the model's training cutoff — prefer
  the installed `swiftui-*` skills + SDK headers over memory.
- Surface any new constant/tag/`RunRecord.Kind` in the PR description; flag, don't
  bury. If a curated album's identity can't be certified against Music.app, stop
  and flag it rather than shipping silent duplicate-album creation.
