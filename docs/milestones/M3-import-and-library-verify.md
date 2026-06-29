# Milestone 3 — Import into Apple Music + library-level verify

*Build order for Codex. Architect/editor-in-chief: this doc is the contract; the
strategic arc is in [../implementation-plan.md](../implementation-plan.md)
(Phase 5), the rules in [../technical-architecture.md](../technical-architecture.md)
(see **Music.app Integration** + **Verification Surface**) and
`/Users/jon/code/jon-platform/AGENTS.md`. Where this doc and those conflict, stop
and flag it — don't silently diverge.*

## The milestone in one sentence

Take the [M2](M2-live-show-apply-convert.md) `Output/` (and the tagged `Working/`
files for non-FLAC shows), **import them into Apple Music** via an explicit,
app-driven ScriptingBridge import, **verify the album landed in the library**
(present, track count + titles match the plan), and only then — on an explicit
confirm — **delete `Working/`** — standing up the keystone Music.app read surface
**without ever mutating an original.**

## Why this is M3 (and where it stops)

M1 proved the *plan*; M2 produced and *file-verified* the output. M3 is the first
time the app touches **Music.app**, and it closes the
Scan/Preview/Run/**Verify** loop at the *library* level:

- **It imports, explicitly.** The user presses **Import**; the app adds the
  produced files to Apple Music via ScriptingBridge. Per the architecture's
  Music.app implementation levels, automation of import/deletion stays
  **explicit** — no background or implicit library mutation.
- **It stands up the gating read surface** every later milestone (Phase 6/7
  remediation) needs: `MusicAppClient` — read library items (album, track count,
  titles, persistent IDs, file location) **and** add files. Per the architecture,
  this file→library-item mapping is the hardest part of the whole product and is
  **spiked first** (Slice 0).
- **It verifies at the library level**, the half M2 deferred: the album appears in
  Apple Music with matching title + track count (optional duration spot-check),
  with concrete per-track pass/fail.
- **It performs the one deletion M2 forbade** — removing `Working/` — but only
  **after** import+library-verify is green **and** on an explicit user confirm.
  Nothing auto-deletes a good `Working/`.

The clean seam at the end: a show goes plan → `Working/` → `Output/` → **Apple
Music** → green library-verify → optional `Working/` cleanup, with originals
byte-for-byte untouched throughout. What's left for later is *browsing* the
imported library and *remediating* already-imported items.

## Definition of done

A reviewer can, in the running macOS app, starting from an M2 show that is applied,
converted, and **file-level verified**:

1. Grant Apple Music automation access on first import (clear prompt + a recovery
   path if denied), then press **Import** and watch `Output/` files (ALAC `.m4a`
   for FLAC shows; the tagged `Working/` files for MP3/M4A shows) added to Apple
   Music. A **run record** (`kind: .importLibrary`) captures the imported items.
2. See a **library verification result**: the album is present in Apple Music, its
   track count equals the plan, each track's title matches the proposed title
   (normalized the same way the writer wrote it), with concrete per-track
   pass/fail mapping each produced file to its library item — recorded in a
   `kind: .verifyLibrary` run.
3. On a green verify, get a **surfaced "Delete Working" confirm**; declining keeps
   `Working/` intact; nothing is deleted without that confirm. After confirming,
   `Working/` is gone and `Output/` + the library item remain.
4. Confirm in Finder that **every original is unchanged** and that nothing outside
   `Working/`/`Output/` was mutated — the only deletion is the explicit,
   post-verify `Working/` cleanup.

Invariants that must hold at merge:

- `swift build` and `swift test` are green; the new pure logic (file→library-item
  matching, library-verify comparison, import-result reduction) is covered by
  tests driven through a **mockable `MusicAppClient`**; ScriptingBridge / Apple
  Events spawning lives in the app target behind the `@Dependency` client.
- **No code path deletes `Working/` except the explicit, post-green-verify,
  user-confirmed cleanup.** Originals are never moved, renamed, retagged, trashed,
  or overwritten. Import into Music.app is **additive** (no library deletions in
  M3). (Grep-able: the only `removeItem`/trash call targets `Working/` and is
  reached only behind the confirm + verify gate.)
- House stack honored: no TCA, no SwiftData, value-type records, `@Observable`
  feature models, `@Dependency` clients (`MusicAppClient` joins `ToolPathClient`,
  `ScriptClient`, `FileOperationClient`, `AudioMetadataClient`), swift-navigation
  `Destination`, SQLiteData run log with observed reads.
- Non-sandboxed (Developer ID + hardened runtime) **plus** the Apple Events
  automation entitlement + usage string — required to drive Music.app.

## In scope

- **`MusicAppClient`** (`@Dependency`, struct of `@Sendable` closures; live impl
  uses ScriptingBridge in the app target): **add** local files to the library;
  **read** an album's tracks (title, album, track number, persistent ID, file
  location) for verification.
- **File→library-item mapping** (pure where possible): match each produced file to
  the library track it became. The architecture flags this as the hard part —
  spike it in Slice 0 before any UI.
- **`LibraryVerificationResult`**: album presence, actual vs expected track count,
  per-track title match (+ optional duration spot-check), single
  verified/not-verified state.
- **Run log**: `RunRecord(kind: .importLibrary)` and `(kind: .verifyLibrary)` with
  per-track outcomes; reuse the M2 `RunLogClient`.
- **`Working/` cleanup**: delete on an explicit confirm, gated behind a green
  library-verify; plus **per-run partial-output cleanup on failure** (folded
  carry-over from the M2 Slice 4 review — see Slice 3).
- **UI**: an **Import** control (enabled only after a green M2 file-verify), the
  library-verify panel, and the delete-`Working/` confirm.

## Out of scope — with destinations

| Deferred | Goes to | Why not now |
|---|---|---|
| Imported-shows **library browse** view (by artist, date order) + rescan | **M-later** | Depends on this read surface but is its own UI; prove import+verify first |
| Remediation of **already-imported** items (compare/correct/reimport) | **Phase 7** | Needs the policy model; M3 only imports *this* show |
| Collection Policy / Grouping metadata, MusicBrainz, artwork policy | **Phase 6** | Separate product area, not on the live-show import path |
| **Deleting items from Apple Music** (vs from disk) | **later / explicit** | M3 import is additive; library deletion is a separate, explicit feature |
| `Library.xml` as the **primary** read surface | **fallback only** | ScriptingBridge is primary (arch default); XML export is manual + goes stale |
| LLM setlist normalization | **M-later** | Needs the `ModelKit` extraction (jon-platform ADR-0001) |
| Source-tag mutation / in-place metadata repair | **Phase 6+** | M3 still only writes derived copies + imports them |
| Multi-disc / multi-set consolidation | **M-later** | M1 fixes `discNumber = 1`; unchanged here |

## Relationship to `music_pipeline.sh` (the evidence)

The script stops at producing files; **import + verify was the manual/Finder step**
a human did after it ran. M3 reimplements that durable intent app-native: the
"drag `ALAC/` into Music, then eyeball that the album showed up" step becomes the
explicit **Import** + **library-verify** loop, and the script's post-import manual
`Working/` cleanup becomes the surfaced, verify-gated delete. No new audio-tool
recipes are introduced; the only new outside surface is Music.app via Apple Events.

## Architecture & module layout

```
VinylFeverCore/Sources/VinylFeverCore/
├── Model/        # + ImportedTrackRef, ImportResult, LibraryVerificationResult,
│                 #   LibraryTrackCheck  — all value types
├── Library/      # + pure file→library-item matching + library-verify comparison
│                 #   (no ScriptingBridge here)
├── Clients/      # + MusicAppClient — struct-of-closures + DependencyKey;
│                 #   live (ScriptingBridge) in the app target, mock testValue
└── Database/     # + RunRecord.Kind .importLibrary / .verifyLibrary
```

Boundary rule (restated because M3 is where Apple Events bites): the **core
package is pure and domain-focused**. The *matching* and *verify comparison* logic
is pure and lives in `Library/`; **the actual ScriptingBridge / Apple Events
calls** (and the permission prompt) live in the app target behind the
`MusicAppClient` `@Dependency` declared in the core. This is what lets the
import/verify logic be unit-tested offline against a mock library snapshot.

## Domain model (shape, not final — refine in code, flag big changes)

Value types, enums for impossible states, `UUID`/persistent-ID identities.
Sketches:

```swift
// Library read model -------------------------------------------------
struct ImportedTrackRef: Identifiable, Equatable {
  let id: String                 // Music.app persistent ID (stable library key)
  var title: String?
  var album: String?
  var trackNumber: Int?
  var durationSeconds: Double?
  var location: URL?             // local file path, when Music exposes it
}

// Import (the Music.app mutation) ------------------------------------
enum MusicImportStatus { case imported, alreadyPresent, failed(String) }
struct ImportedTrack: Identifiable {
  let id: ConversionTrackPlan.ID // reconcile by plan identity
  var sourceURL: URL             // the Output/ (or Working/) file we imported
  var libraryRef: ImportedTrackRef?
  var status: MusicImportStatus
}
struct ImportResult {
  var run: RunRecord             // kind: .importLibrary
  var tracks: [ImportedTrack]
  var didSucceed: Bool { … }
}

// Library-level verification (the M2-deferred half) ------------------
struct LibraryVerificationResult {
  var run: RunRecord             // kind: .verifyLibrary
  var albumFound: Bool
  var expectedTrackCount, actualTrackCount: Int
  var perTrack: [LibraryTrackCheck]   // title match, (optional) duration
  var isVerified: Bool { albumFound && countMatch && perTrack.allPass }
}
struct LibraryTrackCheck: Identifiable {
  let id: ConversionTrackPlan.ID
  var libraryRef: ImportedTrackRef?
  var mismatches: [LibraryMismatch]   // .notFound | .title | .durationDrift
}
```

`MusicImportStatus`, `LibraryMismatch`, and the new `RunRecord.Kind` cases are
**typed enums**, not strings — "make impossible states unrepresentable" reaches
the library surface too.

## The slices (each is one PR into `main`)

`main` is protected — every slice is a branch + PR, small enough to review in one
sitting, each ending green (build + tests).

**Slice status (ledger).** Per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`, the executor ticks the
box in the slice PR that completes it. GitHub PR state is canonical.

- [ ] Slice 0 — Music.app read-surface spike + Apple Events permission
- [ ] Slice 1 — Import `Output/` into Apple Music (explicit)
- [ ] Slice 2 — Library-level verification
- [ ] Slice 3 — `Working/` cleanup (confirmed) + partial-output recovery

### Slice 0 — Music.app read-surface spike + Apple Events permission

The gating spike, per the architecture (*decide the verification surface early*).
`MusicAppClient` read side (struct of `@Sendable` closures behind a
`DependencyKey`): via ScriptingBridge, read a library album's tracks
(title, album, track number, persistent ID, **file location**). Add the hardened-
runtime **Apple Events automation entitlement** + `NSAppleEventsUsageDescription`,
and a first-run permission flow with a clear denied/recovery state. Prove the
**file→library-item mapping** against a real, already-imported album on this Mac
(by file location primarily; album+track as fallback). **Tests:** matching logic
over a mock library snapshot (exact-location match, fallback match, ambiguous →
unresolved); read-model parsing. **Done when:** the app can read a known album's
tracks + locations and resolve each `Output/` file to its library item. *(No file
mutation; reads Music.app only.)*

### Slice 1 — Import `Output/` into Apple Music (explicit)

`MusicAppClient.add(urls:)` (live: ScriptingBridge `add`). An **Import** control,
enabled **only after a green M2 file-verify** (disabled with reason otherwise),
imports the produced files (ALAC `Output/` for FLAC shows; tagged `Working/` for
MP3/M4A), wrapped in `RunRecord(kind: .importLibrary)` with per-track outcomes.
**Safety:** import is **additive** — no library deletions; a file already present
is surfaced (`.alreadyPresent`), not duplicated blindly; a failed add marks that
track `.failed` and is recorded without touching originals. **Tests:** a mock
`MusicAppClient` import records the right per-track outcomes and run summary;
already-present and failed paths. **Done when:** pressing Import adds the show to
Apple Music and writes the run.

### Slice 2 — Library-level verification

`LibraryVerificationResult` over the imported album: album presence, actual vs
expected track count, per-track **title match** (normalized the same way the M2
writer normalizes — reuse that comparison), optional **duration spot-check** within
tolerance, mapping each produced file to its library track. Surface a per-track
pass/fail panel and a single verified/not-verified state, recorded as
`RunRecord(kind: .verifyLibrary)`. **Tests:** verify logic over mock library
snapshots (missing album, count mismatch, title mismatch, duration drift →
not verified; clean → verified); mapping reuses Slice 0. **Done when:** an imported
show shows green library-verify end to end.

### Slice 3 — `Working/` cleanup (confirmed) + partial-output recovery

The one deletion M2 forbade. A **"Delete Working"** affordance, enabled **only
after a green library-verify**, deletes `Working/` behind an **explicit confirm**
(never automatic). **Plus the folded M2 Slice 4 carry-over:** on a failed/cancelled
**convert** (and **apply**), clean up **only the files that run produced**, so a
retry starts clean — staying within "never auto-delete a *good* `Working/`/
`Output/`" (we remove only this run's own partials, never a prior good result).
**Safety, tested:** the confirmed cleanup removes only `Working/` and only behind
the verify+confirm gate; declining leaves it intact; partial-output cleanup is
scoped to the failing run's outputs. **Tests:** cleanup deletes only the intended
paths; decline leaves everything; partial-cleanup scope over fixtures; the
confirmed delete is unreachable before a green verify. **Done when:** after a green
library-verify the user can delete `Working/` on confirm, and a failed
apply/convert self-heals its own partial outputs.

## Constants register (pre-justified — jon-platform "constants need a rationale")

Codex must not introduce new bare constants without the same treatment.

- **Library read surface = ScriptingBridge.** The architecture's resolved default
  for a household Mac app: ScriptingBridge exposes persistent IDs, album, track
  count, and file location and can write. **M3 builds the ScriptingBridge path
  only** (decision 4); the `Library.xml` fallback is deferred and revisited only if
  the Slice 0 spike proves ScriptingBridge unreliable. Do not design around
  MusicKit where file-path mapping is required.
- **Apple Events entitlement = `com.apple.security.automation.apple-events`** +
  **`NSAppleEventsUsageDescription`** usage string. Required under the hardened
  runtime to send Apple Events to Music.app; without it the import/read calls are
  blocked. (The only new entitlement this milestone.)
- **New run kinds = `.importLibrary`, `.verifyLibrary`.** Keep import and library-
  verify as distinct typed `RunRecord.Kind` cases (mirrors M2's `.convert` /
  `.verify` split) so the run history stays legible.
- **File→library mapping key = file `location` path (primary), `album` +
  `trackNumber` + `title` (fallback).** Location is the exact identity of the
  imported file; the tag triple is the recovery path when Music doesn't expose a
  location. Ambiguous matches are surfaced as unresolved, never guessed.
- **Title/track-count match normalization = reuse the M2 `AudioTagVerifier`
  normalization** (trim, empty→nil). Do not introduce a second normalization.
- **Duration spot-check tolerance** (if enabled per the decision below): needs a
  rationale before use (lossless re-encode should be near-exact; a small ± window
  absorbs container rounding). Flag the chosen value in the PR; do not guess inline.

Inherited unchanged from M1/M2: supported extensions `{flac, mp3, m4a}`, derived
dirs `Working/`/`Output/`, `discNumber = 1`.

## Decisions for Jon to confirm (not Codex's to make alone)

1. **Import = automated + explicit button** (ScriptingBridge `add` on an explicit
   Import action, enabled only after a green file-verify). **Decided (Jon):** yes.
2. **`Working/` deletion = surfaced confirm after a green library-verify**, never
   automatic. **Decided (Jon):** yes.
3. **Imported-shows library browse view = deferred to M-later.** **Decided (Jon):**
   yes — M3 is the import→verify→cleanup loop only.
4. **Read surface = ScriptingBridge primary, `Library.xml` fallback** (arch
   default). **Decided (Jon):** skip the XML fallback in M3 — ScriptingBridge only.
   Revisit only if the Slice 0 mapping spike proves it unreliable (flag it then).
5. **Duration spot-check in library verify.** **Decided (Jon):** title + track
   count is the resolved verification definition; duration is an **optional,
   tolerant spot-check, off by default** (a lossless re-encode should be near-exact;
   pin a small ± window with a rationale when it's switched on).
6. **Already-present handling on import.** **Decided (Jon):** surface as
   `.alreadyPresent` and continue to verify (idempotent re-runs) — do not block
   re-import.

## Working agreement

- Each slice: branch → PR → merge (main protected; 0 approvals required, you
  self-merge after the architect's `approve`). Commit messages end with the
  `Co-Authored-By` trailer; PR bodies end with the tool trailer.
- Tests with swift-testing; control time/uuid/db/Music via `@Dependency`. The
  import/verify/cleanup logic must be testable offline against a **mock
  `MusicAppClient`**; any real-Music integration check is guarded on availability
  and is never the only coverage.
- New OS-26/27 + ScriptingBridge APIs are past the model's training cutoff — prefer
  the installed `swiftui-*` skills + SDK headers over memory (toolchain.md).
- Surface any new constant/entitlement in the PR description; flag, don't bury. If
  Music.app can't be driven with the chosen read surface, stop and flag it rather
  than inventing a workaround.
