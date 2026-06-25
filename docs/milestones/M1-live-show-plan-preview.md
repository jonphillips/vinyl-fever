# Milestone 1 — Walking skeleton + read-only Live-Show Plan Preview

*Build order for Codex. Architect/editor-in-chief: this doc is the contract;
the strategic arc is in [../implementation-plan.md](../implementation-plan.md),
the rules in [../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md`. Where this doc and those conflict, stop
and flag it — don't silently diverge.*

## The milestone in one sentence

Pick a live-show folder, ingest a setlist (deterministic parse plus manual edit),
and render the fully-mapped file / title / tag **plan** with readiness checks —
**with zero file writes and zero external tools.**

## Why this is M1 (and not the full vertical slice)

The full Phase 1.5 vertical slice (apply → convert → import → verify) is the right
*shape* but too fat for a first milestone: it drags in ffmpeg/metaflac, Music.app
reading, and the AI layer all at once. M1 is the **Scan + Preview** half of the
Scan/Preview/Run/Verify discipline, applied to the live-show flow. It is:

- **Safe.** No mutation of anything, so it can't hurt a real library while the
  patterns are still settling.
- **Fully testable offline.** Pure Swift + FileManager + SQLiteData. No network,
  no subprocess, no Music.app, no model key. Deterministic — ideal for Codex to
  drive with tests.
- **Foundational.** It stands up the entire house-stack skeleton and the two value
  cores everything else depends on: the **Plan** model and the **setlist parser**.
- **Cleanly extensible.** Every deferral below has a named destination milestone
  and a clean seam, not a rewrite.

## Definition of done

A reviewer can, in the running macOS app:

1. Open a real live-show folder; see its audio files (correctly ordered), the
   detected setlist file, and cover-art candidates.
2. Load a setlist by paste **or** `.txt`, and see it parsed into show tags +
   ordered tracks, editable inline.
3. Pick/confirm a source label (e.g. `SBD`) from a persisted, user-editable
   vocabulary; see the canonical album title compute live.
4. See the full **plan**: each source file mapped to a track, its proposed
   `NN - Title.ext` filename and proposed tags, plus a readiness checklist with
   concrete issues (e.g. "19 files, 18 tracks").
5. Observe that **nothing on disk changed** and the "Apply" affordance is visibly
   deferred to M2.

Invariants that must hold at merge:

- `swift build` and `swift test` are green; the core logic (scan, parse, album
  string, plan) is covered by tests over fixtures.
- No code path writes, moves, trashes, or renames a file. (Grep-able: no
  `FileManager` mutation APIs in the live target.)
- House stack honored: no TCA, no SwiftData, value-type records, `@Observable`
  feature models, `@Dependency` clients, swift-navigation enum `Destination`,
  SQLiteData with observed reads.

## In scope

- macOS SwiftUI app + local SPM core package skeleton, in house style.
- Read-only folder scan (FileManager only).
- Deterministic setlist parser for the **well-structured** cases.
- Source-label vocabulary persisted in SQLiteData (first table).
- Canonical album-title / show-metadata computation.
- The typed `ShowPlan` (mapping, proposed filenames + tags, issues, readiness).
- A preview UI surfacing all of the above.

## Out of scope — with destinations

| Deferred | Goes to | Why not now |
|---|---|---|
| Reading existing file tags & durations | **M2** | Needs `AudioMetadataClient` + tool-path discovery; M1 stays tool-free |
| Applying the plan (write to `Working/` → `Output/`) | **M2** | First mutation; needs the run-log + safety machinery |
| FLAC→ALAC / format conversion | **M2** | ffmpeg orchestration |
| Import into Music.app + **verify** (ScriptingBridge) | **M3** | The keystone read surface; spike it there |
| LLM setlist normalization | **M-later** | Needs the `ModelKit` extraction (jon-platform ADR-0001) |
| Imported-shows library view (by artist, chronological) | **M-later** | Depends on the M3 Music.app read |
| Collection Management, Metadata Management | later areas | Separate product areas |
| CloudKit sync | when useful | Local SQLite is the source of truth; M1 stays local |

M1's setlist parser handles the **structured** inputs (canonical `setlist.txt`,
numbered/plain track lists, disc/set/encore header stripping). Prose-heavy,
footnote-semantic, spelling-fix cases are **manual-edit-now, LLM-later** — the UI
must let the user fix anything the parser gets wrong. Do not attempt to make the
deterministic parser smart; per
[../setlist-formatting-rules.md](../setlist-formatting-rules.md) the normalizer is
ultimately LLM-first with the deterministic layer as validator.

## Architecture & module layout

```
VinylFever/                      # Xcode project
├── VinylFever/                  # macOS app target: SwiftUI views, pickers,
│   │                           #   composition root, the SQLiteData bootstrap
│   └── App.swift, AppModel.swift, Features/…
└── VinylFeverCore/              # local SPM package — domain & logic, fully tested
    └── Sources/VinylFeverCore/
        ├── Model/               # value types: ScannedShowFolder, SetlistDraft,
        │                       #   ShowMetadata, ShowPlan, PlanIssue, SourceLabel
        ├── Parsing/             # SetlistParser (pure)
        ├── Planning/            # ShowMetadata + ShowPlan builders (pure)
        ├── Clients/             # FileSystemClient (protocol + live + test)
        └── Database/            # SQLiteData schema + migration for SourceLabel
    └── Tests/VinylFeverCoreTests/
```

Boundary rule (from [../technical-architecture.md](../technical-architecture.md)):
the **core package is pure and domain-focused** — no AppKit file dialogs, no
`Process`. Anything OS-surface (NSOpenPanel, future `Process`, future Music.app)
lives in the app target behind a `@Dependency` protocol declared in the core.

### House-stack scaffolding (Slice 0)

- **Toolchain:** build with the Xcode beta via
  `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (do not
  `xcode-select -s`); deployment target **macOS 27** — bleeding edge, the newest
  major (per jon-platform `docs/ios/toolchain.md`). Not one behind.
- **Non-sandboxed** (Developer ID + hardened runtime) — household app; this is what
  lets later milestones spawn Homebrew tools and read arbitrary folders. No
  security-scoped bookmarks needed in M1; store the picked path as a string.
- **No version suffixes anywhere** in the namespace (project/target/module/bundle
  id) — plain `VinylFever` (jon-platform persistence law).
- **Dependencies:** swift-dependencies, SQLiteData, swift-navigation,
  swift-issue-reporting, swift-testing. Point-Free libraries, **no TCA**. Each new
  dependency needs a reason.
- **SQLiteData bootstrap:** a `defaultDatabase` dependency + a migrations registry;
  reads via `@FetchAll`/`@FetchOne`, never a hand-pulled `database.read` in a
  `.task` (jon-platform persistence-and-sync.md — that's a bug, not a style
  choice). Sync stays **off** (no CloudKit container) this milestone.

## Domain model (shape, not final — refine in code, flag big changes)

Value types, enums for impossible states. IDs are `UUID`. Sketches:

```swift
// Scan ----------------------------------------------------------------
struct ScannedShowFolder {
  let root: URL
  var audioFiles: [ScannedAudioFile]        // sorted, natural order
  var setlistCandidates: [URL]              // setlist.txt first, then *.txt
  var coverCandidates: [URL]                // front.*, image.*
}
struct ScannedAudioFile: Identifiable {
  let id: UUID
  let url: URL
  let format: AudioFormat                   // enum: flac, mp3, m4a
  let sortKey: String                       // natural-sort key (TrackNN aware)
}

// Setlist (deterministic parse) --------------------------------------
struct SetlistDraft {
  var tags: ShowTags
  var tracks: [SetlistTrack]                // ordered; carry stable IDs so a
}                                           //   later persisted edit reconciles
                                            //   by identity, never delete-all
struct SetlistTrack: Identifiable {
  let id: UUID
  var title: String                         // may include "(notes)" and >|/ segues
}
struct ShowTags {                           // unknowns are explicit, not ""
  var artist: Field; var albumArtist: Field
  var date: DateField                       // .iso(YMD) | .unknown
  var venue: Field; var location: Field
}
enum Field { case value(String); case unknown }

// Show metadata + album title ----------------------------------------
struct ShowMetadata {
  var tags: ShowTags
  var source: SourceLabel?                  // chosen from the vocabulary
  // computed: "YYYY-MM-DD: City, ST - Venue (Source)" per setlist rules;
  // sortAlbum = same string (minimal-intervention; see apple_music strategy)
  var albumTitle: String { … }
  var sortAlbum: String { … }
}

// Plan (the heart of M1) ---------------------------------------------
struct ShowPlan {
  var metadata: ShowMetadata
  var tracks: [TrackPlan]
  var issues: [PlanIssue]
  var isReadyToImport: Bool { issues.allSatisfy(\.isBlocking == false) }
}
struct TrackPlan: Identifiable {
  let id: UUID
  let sourceFile: ScannedAudioFile
  let track: SetlistTrack
  var proposedFilename: String              // "NN - Title.ext"
  var proposedTags: ProposedTags            // title, album, artist, albumArtist,
}                                           //   trackNumber, discNumber
enum PlanIssue {
  case noAudioFiles
  case emptySetlist
  case fileCountMismatch(files: Int, tracks: Int)
  case missingTitle(trackIndex: Int)
  // var isBlocking: Bool { … }
}

// First SQLiteData table ---------------------------------------------
@Table struct SourceLabel: Identifiable {   // UUID PK (law 1)
  let id: UUID
  var token: String                         // "SBD", "AUD", "FM", …
  var isBuiltIn: Bool
}
```

`AudioFormat`, `Field`/`DateField`, `PlanIssue` are **persisted/typed enums**, not
strings — "make impossible states unrepresentable" reaches the schema.

## The slices (each is one PR into `main`)

`main` is protected — every slice is a branch + PR. Keep slices small enough to
review in one sitting; each ends green (build + tests).

**Slice status (ledger).** Per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`, the executor ticks the
box in the slice PR that completes it. GitHub PR state is canonical; this is the
at-a-glance summary.

- [ ] Slice 0 — Skeleton
- [ ] Slice 1 — Folder scan
- [ ] Slice 2 — Setlist parser
- [ ] Slice 3 — Source vocabulary + album title
- [ ] Slice 4 — `ShowPlan` + Preview screen

### Slice 0 — Skeleton

Stand up the Xcode project + `VinylFeverCore` package + dependencies + SQLiteData
bootstrap + an empty app window driven by an `@Observable AppModel`.
**Done when:** app launches to an empty shell; `swift build`/`swift test` green; a
trivial core test runs; `KNOWN-ISSUES.md` created if any beta breakage shows up.

### Slice 1 — Folder scan (read-only)

`FileSystemClient` (protocol + live FileManager impl + test impl) and the
`ScannedShowFolder` builder. App: an "Open Show Folder" command (NSOpenPanel in the
app target) → renders the scan. **Tests:** fixture folders → expected files in
expected order; non-audio ignored; cover and setlist detection. **Done when:** pick
a folder, see its classified contents.

### Slice 2 — Deterministic setlist parser

`SetlistParser` (pure) → `SetlistDraft` for the structured cases: canonical
`setlist.txt`; header (ARTIST/ALBUM/…) extraction; numbered & plain track lists;
strip unnumbered disc/set/encore headers; keep numbered intros/banter; preserve
`>` and `/` segues without splitting/joining. App: a paste box + `.txt` loader
showing the parsed draft with inline editing. **Tests:** a fixture table built from
[../setlist-formatting-rules.md](../setlist-formatting-rules.md) (numbered-track
rule, segue non-split/non-join, header removal, unknown-field fallbacks). **Done
when:** parser passes the suite; draft is visible and editable.

### Slice 3 — Source vocabulary (first SQLiteData table) + album title

`SourceLabel` table + migration, seeded with the defaults from the setlist rules
(`SBD`, `AUD`, `FM`, `ALD`, `Matrix`, …). A small vocab editor (`@FetchAll`,
add/remove user labels; built-ins protected). `ShowMetadata` album-title /
sort-album computation (pure). **Tests:** album-string formatting incl. unknown
date/venue/location fallbacks and the partial-set/compilation variants from the
rules doc; vocab persists across launches. **Done when:** changing source/tags
updates the album title live; vocabulary survives relaunch.

### Slice 4 — `ShowPlan` + the Preview screen

`ShowPlan` builder: zip sorted files with setlist tracks; compute
`NN - Title.ext` (zero-pad width derived from track count) and `ProposedTags`;
collect `PlanIssue`s; compute readiness. The Preview screen surfaces the relevant
subset of the Preview Requirements in
[../metadata-policy-model.md](../metadata-policy-model.md): proposed
title/album/artist/albumArtist/filename, the issue list, readiness. **Apply is a
disabled control labeled "M2."** **Tests:** plan over fixtures; count-mismatch
issue; filename formatting (incl. ≥100 tracks); readiness logic. **Done when:** the
full end-to-end flow works in-app with zero writes.

## Constants register (pre-justified — jon-platform "constants need a rationale")

Every literal below is derived from the existing pipeline (the source of truth),
not guessed. Codex must not introduce new bare constants without the same
treatment.

- **Supported audio extensions = {flac, mp3, m4a}.** Exactly the formats
  `scripts/shell/music_pipeline.sh` handles (`EXT=flac|mp3|m4a`); `.m4a` is the
  ALAC/AAC container. Add others only when a real file demands it.
- **Filename zero-pad width = max(2, digits(trackCount)).** The pipeline defaults
  to 2-digit `TrackNN`; widen only past 99 tracks so lexical order stays correct.
  Derived from the data, not fixed.
- **Cover candidates = `front.*`, `image.*` (case-insensitive).** Exactly
  `copy_cover_candidates` in the pipeline.
- **Setlist detection = `setlist.txt`, then any `*.txt`.** The pipeline writes
  `Working/setlist.txt`.

## Decisions for Jon to confirm (not Codex's to make alone)

1. **Toolchain target:** confirmed — build with Xcode beta + deployment target
   **macOS 27** (bleeding edge, per toolchain.md). Not one OS behind.
2. **Bundle id / namespace:** `VinylFever`, bundle id e.g.
   `com.jonphillips.VinylFever` — confirm the prefix.
3. **Defer existing-tag/duration reading to M2?** I recommend yes (keeps M1
   tool-free). If you want "current vs proposed" in the preview now, that pulls
   `AudioMetadataClient` + tool-path discovery forward into M1.
4. **Sandbox = off** (Developer ID, no App Sandbox). Confirm.

## Working agreement

- Each slice: branch → PR → merge (main is protected; 0 approvals required, you
  self-merge). Commit messages end with the Co-Authored-By trailer; PR bodies end
  with the Claude Code trailer.
- Tests with swift-testing; control time/uuid/db via `@Dependency`.
- New OS-26/27 APIs are past the model's training cutoff — prefer the installed
  `swiftui-*` skills + SDK headers over memory (toolchain.md).
- Surface any new constant in the PR description; flag, don't bury.
