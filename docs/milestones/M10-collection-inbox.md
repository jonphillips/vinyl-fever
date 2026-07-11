# Milestone 10 — Collection Inbox (drag-drop track append)

*Let Jon **drag one or more loose song files onto a compilation album** to append
them, without first organizing those files into a tracked source folder. Dropped
files land in a single app-owned **Inbox** staging area under Application Support;
each album's staged files feed the existing M8/M9 append rail unchanged, and drain
out of the Inbox once the append certifies. This is dogfooding feedback from real
use (2026-07-10): compilation albums exist to keep one-hit-wonders off the Artists
list, policies made appends "drop and don't look back," and the last friction is
having to marshal each one-off song into a folder to append it. Rules in
[../technical-architecture.md](../technical-architecture.md),
[../metadata-policy-model.md](../metadata-policy-model.md),
[../app-areas.md](../app-areas.md), and `/Users/jon/code/jon-platform/AGENTS.md`
apply; where this doc and those conflict, stop and flag it.*

## The milestone in one sentence

Dropping audio files onto a compilation album **copies** them into that album's
Inbox staging folder (`<AppSupport>/VinylFever/Inbox/<albumID>/`), points the
existing `buildCompilationAppendPlan(entry:sourceFolder:)` at that folder, and — on
a certified append — **trashes** the album's staged copies so the Inbox visibly
drains; a standing Inbox view gives the assurance that it emptied.

## Why now

M8 fused compilation stamping + policy recipes into one previewed/one-applied
append; M9 added the per-append Grouping/Comments escape hatch. The append engine is
now good enough that the *input* is the remaining friction. Today the only way in is
[`openAppendFolder`](../../VinylFever/Features/Collections/CollectionsView.swift:116)
→ an `NSOpenPanel` folder pick → `buildCompilationAppendPlan(entry:sourceFolder:)`.
For a one-hit-wonder pulled off a download, that means *making a folder just to
append one file*. Jon's ask, verbatim: drag-and-drop an individual song (or several)
onto a Collection to add it, managed from a **central "Working" location** so these
onesey-twosey adds don't have to be tracked inside the songs source folder.

The groundwork makes this a wire, not a build:

- **The append rail is already folder-shaped and format-agnostic.**
  `buildCompilationAppendPlan(entry:sourceFolder:)`
  ([AppModel.swift:757](../../VinylFever/Features/AppShell/AppModel.swift:757))
  scans a folder (`fileSystemClient.scanAudioFolder`), reads tags, runs the bound
  policy's recipes (M8), applies the ephemeral Grouping/Comments (M9), previews, and
  on apply converts + imports + certifies
  ([`appendCompilationToMusic`](../../VinylFever/Features/AppShell/AppModel.swift:989)).
  **If the Inbox album folder *is* the `sourceFolder`, none of that changes.** The
  drop is a new *input adapter* + a new *home*, not a new pipeline.
- **The clear-on-clean-append step already exists.** After a certified append the
  flow already nulls the plan and folder
  ([AppModel.swift:1054](../../VinylFever/Features/AppShell/AppModel.swift:1054)). The
  Inbox adds exactly one safe action there: trash the staged copies — safe *because
  the Inbox is app-owned*, unlike a user-picked source folder.
- **`FileSystemClient` is the template for the store.**
  ([FileSystemClient.swift](../../VinylFeverCore/Sources/VinylFeverCore/Clients/FileSystemClient.swift))
  — a `@DependencyClient` of pure filesystem ops, tested against temp dirs
  ([FileSystemClientTests.swift](../../VinylFeverCore/Tests/VinylFeverCoreTests/FileSystemClientTests.swift)).
  The Inbox store is a sibling.

## The spine (load-bearing shape)

**One app-owned root, one subfolder per album.**

```
<AppSupport>/VinylFever/Inbox/
  <albumID-A>/   ← files dropped onto album A live here until its append certifies
  <albumID-B>/
```

Dropping files onto album A **copies** them into `Inbox/<A>/` (originals untouched,
per the safety model). The append for album A then runs with
`sourceFolder = Inbox/<A>/` — the *exact* existing rail. When that append certifies,
`Inbox/<A>/` is drained to Trash and the album's queue is empty again.

Consequences that fall out of this shape, each a decision:

- **The filesystem is the source of truth for what's staged — no new table.** "What
  is pending for album A" is "list `Inbox/<A>/`." Keeps M10 off the schema (like M9),
  and makes the "did it empty?" question answerable by *looking at the folder*, which
  is exactly the assurance asked for.
- **Drain is Trash, never hard delete, and only ever inside the Inbox root.** A staged
  file may be the *only* copy of a download; it is trashed (recoverable) only *after*
  the append certifies into Apple Music — the same "never delete the source before
  verify" rule the live-show flow follows. A **folder-picked append (the existing
  `NSOpenPanel` path) never drains** — its source is the user's, not the app's. Guard
  drain on "path is under the Inbox root."
- **Per-album, not cross-album batch.** The append rail converts + imports + certifies
  against *one* album identity, so draining is per album: you clear album A's queue by
  running album A's append. The Inbox view shows every album's pending count so nothing
  waits invisibly, but a single "flush all albums" gesture is out of scope (the rail is
  one-identity-at-a-time). Honest framing: the Inbox is a *staging area with
  visibility*, not a background importer.

## Slices

- [x] **S0 — Collection Inbox store (core, no UI).** A `CollectionInboxClient`
  `@DependencyClient` owning the app-owned staging root and per-album subfolders:
  resolve `Inbox/<albumID>/` under Application Support (creating on demand), **copy**
  dropped source URLs in (preserve originals; collision-suffix, never overwrite), list
  an album's staged files, summarize per-album counts across the whole root, and
  **drain** an album (move its staged files to Trash). Root is dependency-injected so
  tests run against a temp directory. DoD: `swift test` green; staging copies leave the
  originals in place; a name collision yields a suffixed copy, not an overwrite; a
  non-audio drop is copied but harmlessly ignored by the later audio scan (or filtered
  — Codex's call, stated in the PR); `contents`/`summary` counts match the directory;
  `drain` moves an album's files to Trash and leaves the subfolder empty/absent; drain
  refuses any path not under the Inbox root.
- [ ] **S1 — Drop-to-append + Inbox drain wiring (app).** A drop target on the
  compilation-album surface stages dropped audio files via the S0 store and drives the
  existing append preview; a certified append drains the album's Inbox folder; an album
  with no bound policy shows a non-blocking nudge. DoD: dropping file(s) onto an album
  copies them into `Inbox/<albumID>/`, points `buildCompilationAppendPlan` at that
  folder, and previews exactly as a folder-pick would (recipes, Grouping/Comments,
  compilation stamping all intact); a second drop re-stages and rebuilds; a **clean
  certified append trashes** the album's staged copies and resets the section; a
  **folder-picked** append still never drains; an album with `collectionPolicyID == nil`
  shows the "no policy bound" nudge and the drop still stamps compilation identity.
- [ ] **S2 — Inbox visibility surface (app).** A standing Inbox panel on the Collections
  screen: per-album pending counts from `CollectionInboxClient.summary()`, an aggregate
  "N tracks staged across M albums" / "Inbox empty" state, and a manual per-album
  **Clear** (drain, with confirm) for abandoning a queue without appending. DoD: staging
  a drop increments the album's count; a certified append drops it to zero; the
  aggregate reads "empty" when the root is clear; manual Clear trashes that album's queue
  after confirm; staged files for a since-deleted album surface as orphaned and are
  clearable.

*Ungated — no device dependency for S0/S1's staging/drain (deterministic filesystem +
Trash). The append it feeds still reaches Music.app for import/certify exactly as
M8/M9's append does; M10 adds no new live-read.*

## S0 execution map

Everything lands in `VinylFeverCore`. `FileSystemClient` is the structural template.

| File | Change | Template / anchor |
| --- | --- | --- |
| `Clients/CollectionInboxClient.swift` *(new)* | `@DependencyClient` with `stagingDirectory(albumID:) -> URL`, `stage(files:albumID:) -> [URL]`, `contents(albumID:) -> [URL]`, `summary() -> [InboxAlbumSummary]`, `drain(albumID:)`; live value resolves the root via `FileManager.default.url(for: .applicationSupportDirectory, …)` + `VinylFever/Inbox`, with an injectable root for tests | [FileSystemClient.swift](../../VinylFeverCore/Sources/VinylFeverCore/Clients/FileSystemClient.swift) shape + `DependencyValues` accessor |
| same | `InboxAlbumSummary { albumID: CompilationAlbum.ID; fileCount: Int }` value type | — |
| copy op | `FileManager.default.copyItem`; on collision append ` (2)`, ` (3)`… deterministically; return staged URLs | the collision rule is the one easy-to-get-wrong bit — call it out in review |
| drain op | resolve album subfolder, assert it is under the Inbox root, `FileManager.default.trashItem` each entry (or the subfolder) | the "under-root only" guard is a safety assertion, tested |

Tests: `Tests/VinylFeverCoreTests/CollectionInboxClientTests.swift` against an injected
temp root — stage-preserves-original, collision-suffixes, contents/summary counts,
drain-trashes-and-empties, drain-refuses-outside-root, round-trip (stage → list →
drain → empty).

## S1 execution map

App layer only; flag any core reach in review. The compilation-append methods are the
end-to-end template.

Edits:

- **[CollectionsView.swift](../../VinylFever/Features/Collections/CollectionsView.swift)**
  — make the compilation-album a **drop destination** for audio file URLs. Primary
  gesture: dropping onto a `CompilationAlbumRow` in the list stages to *that* album and
  selects it (matches "drag a song onto one of the Collections"); at minimum, a drop
  zone inside the selection-gated `CompilationAppendSection` (`:35`). The drop handler
  copies via `collectionInboxClient.stage(files:albumID:)`, then calls the existing
  `model.buildCompilationAppendPlan(entry:sourceFolder: inboxDir)` — reuse
  `openAppendFolder`'s tail (`:116`), just sourced from the Inbox dir instead of the
  panel. Keep the `NSOpenPanel` "Append Folder" as an alternate input.
- **No-policy nudge:** when `selectedAlbum.collectionPolicyID == nil`, render an inline,
  non-blocking notice in the drop zone ("No policy bound — dropped tracks get
  compilation identity but no recipe cleanup. Bind a policy to auto-tag."). The drop
  still works (compilation stamping applies regardless).
- **[AppModel.swift](../../VinylFever/Features/AppShell/AppModel.swift)** — in the
  certified-append success branch of `appendCompilationToMusic`
  ([`:1054`](../../VinylFever/Features/AppShell/AppModel.swift:1054)), after
  `clearCompilationAppendScratch()`, if the just-appended `sourceFolder` is under the
  Inbox root, `collectionInboxClient.drain(albumID:)`. Guard on under-root so a
  folder-picked append is untouched. A drop entry-point may set the album/folder scratch
  the same way `openAppendFolder` does; keep the drain keyed off the folder location, not
  a separate "was this a drop" flag, so there is one truth.

Tests: `AppModel`-level coverage with an injected `collectionInboxClient` — a staged
drop reaches `buildCompilationAppendPlan` with the Inbox folder; a certified append
calls `drain` for that album; a folder-picked append does **not** call `drain`. Clone
the compilation-append test support. Pure-view/drop-plumbing code stays untested.

## S2 execution map

App layer only.

- **[CollectionsView.swift](../../VinylFever/Features/Collections/CollectionsView.swift)**
  — an `InboxSummarySection` near the top of the Collections screen driven by
  `collectionInboxClient.summary()` (refresh on append/drain and on appear). Rows: album
  title (resolve `albumID` → registry entry) + pending count, with a per-row **Clear**
  calling `drain(albumID:)` behind a confirmation. Aggregate line: total staged / "Inbox
  empty." Orphan handling: a `summary` entry whose `albumID` no longer resolves renders
  as "Unknown album" with a Clear.
- **[AppModel.swift](../../VinylFever/Features/AppShell/AppModel.swift)** — a
  `refreshInboxSummary()` that loads `summary()` into observable state; call it after
  stage, after certified-append drain, and on the Collections `.task`.

Tests: `AppModel`-level — summary reflects a staged drop, zeroes after drain, and an
orphan (no matching registry entry) is represented. Pure-view code untested.

## Out of scope

- **A cross-album "flush all" importer.** The append rail is one-album-identity per
  convert/import/certify; draining is per album by running that album's append. The
  Inbox *shows* everything pending but does not batch-import across albums.
- **Dropping onto anything but a compilation album** — no drop-to-live-show, no
  drop-onto-a-bare-policy. Compilation albums only, matching M8's surface boundary.
- **A grouping-only "playlist membership" add** that skips album identity. Jon's intent
  is explicitly album append (keep one-hit-wonders off the Artists list); the lightweight
  grouping-stamp path is not this milestone.
- **Persisting Inbox state in the DB.** The filesystem is the source of truth; no
  `inbox` table. If cross-launch metadata (drop time, intended album before selection)
  ever earns its place, that is a later, evidence-backed decision.
- **Any change to the append/write/convert/import/certify rail** beyond adding the
  Inbox-scoped drain call — M10 changes the *input* and the *cleanup*, not the engine.
- **Auto-suggesting which album a dropped file belongs to.** The user targets the album
  by where they drop; no content-based routing in v1.

## Decisions (open — resolve before/at S0 review)

- **Inbox root → `<AppSupport>/VinylFever/Inbox/`, fixed (not user-chosen)** (Jon,
  2026-07-10). Simplicity over configurability; the S2 view supplies the visibility that
  a fixed hidden location otherwise lacks.
- **Drain = Trash after certify, under-root-only** (Jon, 2026-07-10, "assurance it
  emptied"). Trash (recoverable), never hard delete; never a user-picked folder.
- **Non-audio drops** — copied-then-ignored vs filtered-at-stage. Default: copy through
  and let the append's audio scan ignore non-audio, matching how `scanAudioFolder`
  already filters; Codex may filter at stage instead if it reads cleaner. State the pick
  in the PR.
- **Primary drop target** — album *row* in the list (select + stage) vs the append
  section's drop zone. Prefer the row (closest to "drop a song onto a Collection"); the
  section zone is the acceptable floor if row-drop is fiddly. Codex's call, stated in the
  PR.
- **Collision suffix format** — ` (2)`, ` (3)`… Confirm at S0 review; deterministic and
  fixture-pinned either way.
