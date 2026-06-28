# Milestone 2 — Apply the plan: Working copies, ALAC conversion, file-level verify

*Build order for Codex. Architect/editor-in-chief: this doc is the contract; the
strategic arc is in [../implementation-plan.md](../implementation-plan.md)
(Phase 1.5 / Phase 4–5), the rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md`. Where this doc and those conflict, stop
and flag it — don't silently diverge.*

## The milestone in one sentence

Turn the read-only [M1](M1-live-show-plan-preview.md) `ShowPlan` into real output:
locate the audio tools, copy the originals into `Working/`, rename + tag + embed
cover from the plan, convert FLAC→ALAC into `Output/`, and **verify the produced
files** — **without ever mutating an original and without touching Music.app.**

## Why this is M2 (and where it stops)

M1 proved the *plan* is correct with zero writes. M2 is the **first mutation**: it
executes that plan. It is deliberately the "produce the files" half of the
Scan/Preview/**Run**/**Verify** discipline, and it stops at the edge of Music.app:

- **It writes, but only to derived locations.** Originals stay byte-for-byte
  untouched; everything lands in `Working/` (tagged copies) and `Output/`
  (converted, import-ready files), both siblings created under the show root.
- **It stands up the execution substrate** every later milestone needs: external
  **tool-path discovery**, a narrowed **`ScriptClient`**, the **`FileOperationClient`**,
  the **`AudioMetadataClient`** read side, and the **run log** in SQLiteData.
- **It verifies what it produced**, at the *file* level — count, tags read back,
  audio stream present. The other half of verification (does the album show up in
  the Apple Music library) is M3, because it needs ScriptingBridge.
- **It is still offline and tool-bounded.** No network, no model key, no Music.app.
  The only new outside dependencies are three locatable Homebrew CLIs
  (`metaflac`, `ffmpeg`, `ffprobe`).

The clean seam at the end: `Output/` holds correct, tagged, ALAC/derived files
ready for a human (or M3) to import; `Working/` is retained for that import step
and is **not** deleted in M2.

## Definition of done

A reviewer can, in the running macOS app, starting from an M1 plan that is
*ready to import*:

1. See, in **Settings**, that `metaflac`, `ffmpeg`, and `ffprobe` were located
   (path + version), or a clear "not found — install with Homebrew / set path"
   state with a working manual override.
2. See the M1 preview enriched with **current** file tags/durations (read from the
   originals) alongside the **proposed** tags — the "current vs proposed" M1
   deferred.
3. Press **Apply** and watch the plan execute into `Working/`: originals copied
   (not moved), renamed to `NN - Title.ext`, tagged per the plan, cover embedded.
   A **run record** is written capturing the command(s), inputs, outputs, and
   result.
4. For a FLAC show, press **Convert** and get ALAC `.m4a` files in `Output/`, cover
   preserved, tags carried, recorded in the same run.
5. See a **verification result**: `Output/` track count equals the plan, each
   file's read-back tags match the proposed tags, every file has an audio stream
   of non-zero duration — with concrete per-file pass/fail.
6. Confirm in Finder that **every original is unchanged** (same bytes, same names)
   and nothing was deleted.

Invariants that must hold at merge:

- `swift build` and `swift test` are green; the new pure logic (tag-output
  parsing, command construction, plan→operation translation, verification) is
  covered by tests, with tool-touching paths driven through mockable
  `@Dependency` clients.
- **No code path writes outside `Working/` and `Output/` under the chosen show
  root.** Originals are never moved, renamed, retagged, trashed, or overwritten.
  (Grep-able: the only mutating `FileManager`/tool calls target `Working/` or
  `Output/`.)
- **No silent overwrite and no permanent delete.** An existing destination is a
  surfaced conflict, never a clobber; `Working/` is never auto-deleted.
- House stack honored: no TCA, no SwiftData, value-type records, `@Observable`
  feature models, `@Dependency` clients (`ToolPathClient`, `ScriptClient`,
  `FileOperationClient`, `AudioMetadataClient`), swift-navigation `Destination`,
  SQLiteData run log with observed reads.
- Non-sandboxed (Developer ID + hardened runtime) — required to spawn Homebrew
  tools and read/write arbitrary folders.

## In scope

- **Tool-path discovery + Settings override** for `metaflac` / `ffmpeg` /
  `ffprobe` (`ToolPathClient`).
- **`ScriptClient`** narrowed to those three tools: run with args/env, stream and
  capture stdout/stderr, return exit code.
- **`AudioMetadataClient`** (read): tags, duration, embedded-artwork presence, via
  `metaflac`/`ffprobe`. Feeds "current vs proposed" and verification read-back.
- **`FileOperationClient`**: copy (never overwrite), exists/inspect, reveal in
  Finder. No move/trash of originals in M2.
- **Apply engine** (pure plan→operations + executed effects): copy originals →
  `Working/`, rename to `NN - Title.ext`, write tags (metaflac for FLAC, ffmpeg
  for MP3/M4A), embed cover.
- **FLAC→ALAC conversion** → `Output/` (ffmpeg `-c:a alac`, cover preserved).
- **Run log** in SQLiteData: a `Run` plus per-file outcomes; a minimal run-history
  read surface.
- **File-level verification** of `Output/`: count, tag read-back vs proposed,
  audio-stream/duration presence.
- Preview/confirm UI for apply + convert; the M1 **Apply** control becomes live.

## Out of scope — with destinations

| Deferred | Goes to | Why not now |
|---|---|---|
| Import into Music.app + **library** verify (ScriptingBridge) | **M3** | The keystone read surface; file→library mapping is its own spike |
| Deleting `Working/` after a successful import | **M3** | Per Phase 5, delete only *after* import+verify — which is M3 |
| Multi-disc / multi-set consolidation across subfolders | **M-later** | M1 fixes `discNumber = 1`; multi-disc scan + plan is its own change |
| LLM setlist normalization | **M-later** | Needs the `ModelKit` extraction (jon-platform ADR-0001) |
| Source-tag mutation / in-place metadata repair | **Phase 6+** | M2 only writes derived copies; source mutation is opt-in, later |
| MusicBrainz lookup, artwork policy, Collection Policy | **Phase 6** | Separate product area; not on the live-show import path |
| MP3/M4A *conversion* (e.g. OPUS→AAC) | **M-later** | M2 converts FLAC→ALAC only; MP3/M4A are tagged-in-place, not converted (matches the pipeline) |
| Archive folder for replaced files | **deferred** | No replacement happens in M2; revisit with source mutation (open question) |

## Relationship to `music_pipeline.sh` (the evidence)

[`../../scripts/shell/music_pipeline.sh`](../../scripts/shell/music_pipeline.sh)
is the source of truth for *what the operations are*, not *how the app is
structured*. Per the Script Reassessment rule in
[../technical-architecture.md](../technical-architecture.md), M2 **reimplements**
its durable intent in Swift-first logic and keeps only the audio-tool calls
outside Swift. Mapping:

- **Steps 0 / 4 (copy to `Working/`, rename, tag, embed cover)** → the Apply
  engine (Slice 3). The script's strict "titles must equal files" and
  "destination exists ⇒ die" become plan issues + surfaced conflicts.
- **Step 5 (interactive ALBUM source suffix)** → **already done in M1**: the
  source is chosen from the `SourceLabel` vocabulary and baked into
  `proposedTags.album`. No interactive suffix prompt is reimplemented.
- **Step 6 (FLAC→ALAC, output outside `Working/`)** → conversion (Slice 4); the
  script's `./ALAC` becomes `Output/` (the docs' name).
- **Steps 1–2 (consolidate subfolders, normalize `TrackNN`)** → **out of scope**
  (multi-disc deferred); M2 acts on the single ordered file list M1 already scans.
- **Step 3 (interactive paste setlist)** → **already done in M1** (paste/`.txt` +
  parser).

The tagging command shapes (metaflac `--set-tag`, ffmpeg `-c:a copy`/`-c:a alac`,
cover via `--import-picture-from` / mapped mjpeg `attached_pic`) are the verified
recipes; reuse them rather than inventing flags. They are pinned in the constants
register.

## Architecture & module layout

```
VinylFeverCore/Sources/VinylFeverCore/
├── Model/        # + RunRecord, RunFileOutcome, AppliedTrack, VerificationResult,
│                 #   AudioTags (read model), ToolStatus  — all value types
├── Planning/     # + ApplyPlan builder: ShowPlan → ordered FileOperation list
│                 #   (pure); VerificationPlan (pure)
├── Clients/      # + ToolPathClient, ScriptClient, FileOperationClient,
│                 #   AudioMetadataClient — struct-of-closures + DependencyKey,
│                 #   live values in the app target, generated test values
├── Database/     # + Run / RunFileOutcome tables + migration
└── Tagging/      # pure: metaflac/ffmpeg/ffprobe command construction + output
                  #   parsing (no process spawning here)
```

Boundary rule (unchanged from M1, restated because M2 is where it bites): the
**core package is pure and domain-focused**. Command *strings/argument arrays* and
*output parsers* are pure and live in `Tagging/`; **actual process spawning**
(`Process`, `NSOpenPanel`, Finder reveal, real PATH probing) lives in the app
target behind the `@Dependency` clients declared in the core. This is what lets
the apply/convert/verify logic be unit-tested offline with a mock `ScriptClient`.

## Domain model (shape, not final — refine in code, flag big changes)

Value types, enums for impossible states, `UUID` IDs. Sketches:

```swift
// External tools -----------------------------------------------------
enum AudioTool: String, CaseIterable { case metaflac, ffmpeg, ffprobe }
struct ToolStatus: Identifiable {           // one per AudioTool
  let id: AudioTool
  var resolvedPath: String?                 // nil = not found
  var version: String?                      // parsed from `--version`
  var source: Source                        // .discovered(dir) | .userOverride
}

// Read model (current tags) -----------------------------------------
struct AudioTags: Equatable {               // read from an existing file
  var title, artist, album, albumArtist: String?
  var trackNumber, trackTotal, discNumber: Int?
  var durationSeconds: Double?
  var hasEmbeddedArtwork: Bool
}

// Apply (the first mutation) ----------------------------------------
enum FileOperation {                         // pure, ordered, reviewable
  case copy(from: URL, to: URL)              // never overwrites
  case writeTags(file: URL, tags: ProposedTags, cover: URL?)
  case convertToALAC(from: URL, to: URL, cover: URL?)
}
struct AppliedTrack: Identifiable {
  let id: UUID                               // == TrackPlan.id (reconcile by identity)
  var workingFile: URL?                      // populated after copy+tag
  var outputFile: URL?                       // populated after convert
  var outcome: Outcome                       // .pending | .succeeded | .failed(String)
}

// Run log (safety machinery) ----------------------------------------
@Table struct RunRecord: Identifiable {      // UUID PK (law 1)
  let id: UUID
  var showRootPath: String
  var kind: Kind                             // .apply | .convert | .verify
  var startedAt, finishedAt: Date?
  var command: String                        // exact command(s), joined
  var exitSummary: String                    // ok / first failing tool+code
}
@Table struct RunFileOutcome: Identifiable { // child rows, UUID PK
  let id: UUID
  var runID: RunRecord.ID
  var sourcePath, producedPath: String
  var status: Status                         // .created | .skipped | .failed
  var note: String
}

// Verification (file-level; library verify is M3) -------------------
struct VerificationResult {
  var expectedTrackCount, actualTrackCount: Int
  var perFile: [FileCheck]                   // tag-match, audioStreamPresent, duration>0
  var isVerified: Bool { … }                 // count match && all per-file pass
}
```

`AudioTool`, `Outcome`, `Status`, `Kind` are **typed enums**, not strings —
"make impossible states unrepresentable" reaches the run log too.

## The slices (each is one PR into `main`)

`main` is protected — every slice is a branch + PR, small enough to review in one
sitting, each ending green (build + tests). No file mutation appears before
Slice 3; Slices 0–2 are read-only/plumbing.

**Slice status (ledger).** Per
`/Users/jon/code/jon-platform/docs/agent-collaboration.md`, the executor ticks the
box in the slice PR that completes it. GitHub PR state is canonical.

- [x] Slice 0 — Tool discovery + Settings
- [x] Slice 1 — `ScriptClient` + `AudioMetadataClient` (read) + current-vs-proposed
- [x] Slice 2 — Run log (SQLiteData) + run history
- [ ] Slice 3 — Apply to `Working/` (copy + rename + tag + cover) — first mutation
- [ ] Slice 4 — FLAC→ALAC → `Output/` + file-level verification

### Slice 0 — Tool discovery + Settings

`ToolPathClient` (struct of `@Sendable` closures behind a `DependencyKey`):
resolve each `AudioTool` by probing `/opt/homebrew/bin`, then `/usr/local/bin`,
then `PATH`; read `--version`. Persist user overrides (SQLiteData `ToolOverride`
table **or** a typed app-settings record — choose one and justify; observed read).
A **Settings** screen lists each tool's `ToolStatus` with a path override field and
re-probe action. **Tests:** resolution over a fixture directory layout (found in
homebrew dir; found only via override; missing); version parsing from fixture
`--version` output. **Done when:** Settings shows real tool status on this Mac and
an override takes effect. *(No file mutation.)*

### Slice 1 — `ScriptClient` + `AudioMetadataClient` (read) + current-vs-proposed

`ScriptClient`: run a resolved tool with an argument array + environment, capture
stdout/stderr separately, return exit code (live impl uses `Process` in the app
target; `testValue` is mockable). `AudioMetadataClient.read(url:)` → `AudioTags`,
built on **pure** command construction + output parsers in `Tagging/` (`metaflac
--export-tags-to`/`--show-*` for FLAC; `ffprobe -show_format -show_streams -of
json` for MP3/M4A). Wire the read into the M1 preview as **current vs proposed**
columns. **Tests:** parse fixture `metaflac` and `ffprobe` outputs into `AudioTags`
(incl. missing tags, no-artwork, multi-value); command-construction asserts the
exact argv; `ScriptClient` interaction via a mock. **Done when:** the preview shows
real current tags/durations for a scanned show. *(No file mutation — read-only
tools.)*

**Carry-over from the Slice 1 review (fold into Slice 2):**

- **Don't re-resolve tools inside the read path.** `refreshCurrentMetadata`
  re-runs `toolPathClient.resolveTools` and overwrites `toolStatuses` on every
  folder/settings change, re-spawning `--version` for all three tools and racing
  the Settings screen's own resolution. Read the already-resolved `toolStatuses`
  (or cache the `AudioToolPaths`) instead.
- **Stop deriving FLAC `hasAudioStream` from duration.** It's currently
  `durationSeconds != nil`, so a parse hiccup reads as "no audio stream" and
  there's no real stream check. The verification work (DoD #5) should assert
  duration explicitly rather than trust this flag.
- **FLAC duration parsing is line-order-dependent and silent on edge cases.**
  `parseDuration` assumes line 0 = total-samples, line 1 = sample-rate from the
  arg order; add a comment tying them together, and note that a FLAC reporting 0
  total samples yields `durationSeconds: 0.0` + `hasAudioStream: true`.
- **`combinedOutputText` joins stdout+stderr with no separator**, so the last
  stdout line can merge into the first stderr line. Join with `\n` if it's ever
  surfaced verbatim.

### Slice 2 — Run log (SQLiteData) + run history

`RunRecord` + `RunFileOutcome` tables + migration (UUID PKs, no unique indexes;
follow the M1 persistence-law guardrails). A small `RunLogClient` or model method
to open a run, append file outcomes, and close it with an exit summary; a minimal
**run history** view (`@FetchAll`, newest first, expandable to per-file outcomes).
Log the **Slice 1 read invocations** so the table has real content before any
mutation exists. **Tests:** open→append→close round-trips; observed read returns
runs newest-first; child outcomes join correctly. **Done when:** read operations
appear in a run history that survives relaunch. *(No file mutation.)*

**Carry-over from the Slice 2 review (fold into Slice 3):**

- **De-dupe `metadataRead` runs.** Every folder open currently writes a fresh
  `metadataRead` run (open → per-file outcome → close) with no collapsing, so
  reopening a show N times yields N identical runs that will bury the real
  apply/convert runs. **Decided fix:** skip logging a read run when the prior
  read for the same `showRootPath` produced identical outcomes (same files, same
  statuses/notes). Compare against the most recent `metadataRead` run for that
  root before opening a new one.
- **Bail before recording a cancelled read run.** A refresh cancelled mid-flight
  still opens/closes a run of all-`skipped` outcomes. Skip
  `closeMetadataReadRun` (and ideally the open) when `Task.isCancelled` — a
  second source of the noise above.
- **Cap the run-history read.** `RunHistoryRequest` fetches both tables in full
  and groups in memory with no `LIMIT`; add a limit on runs (and fetch only the
  outcomes for those runs) when the history view gets pagination.
- **Cosmetics.** Drop the redundant explicit raw value on
  `RunRecord.Kind.metadataRead`; revisit `RunFileOutcome` history ordering
  (currently by `sourcePath`) once `producedPath` ordering matters in apply.

### Slice 3 — Apply to `Working/` (copy + rename + tag + cover) — first mutation

The heart of M2. `FileOperationClient` (copy that **refuses to overwrite**,
exists-check, reveal). A **pure** `ApplyPlan` builder: `ShowPlan` → ordered
`[FileOperation]` (`copy` each source into `Working/` under its `NN - Title.ext`
name, then `writeTags` per `ProposedTags`, embedding the detected cover). The app
executes the operations through `ScriptClient`/`FileOperationClient`, wraps the
whole thing in a `RunRecord`, and updates `AppliedTrack` outcomes. Tagging uses
**metaflac** for FLAC and **ffmpeg stream-copy** for MP3/M4A (pinned recipes).
**Safety, enforced and tested:** originals are *copied* never moved; an existing
`Working/` destination is a surfaced conflict (no clobber); a tool failure marks
that file `.failed` and is recorded, without corrupting originals. Preview the
operation list, confirm, then apply. **Tests:** `ApplyPlan` over fixtures emits the
expected ordered operations incl. filename sanitization carried from M1; a
mock-`ScriptClient` apply records the right argv per file and the right
`RunFileOutcome`s; conflict path returns a conflict, not an overwrite; an
integration test guarded on real tool availability copies+tags a generated FLAC
fixture and reads the tags back. **Done when:** Apply produces a correctly named,
tagged, cover-embedded `Working/` from a real show, originals untouched, run
recorded.

### Slice 4 — FLAC→ALAC → `Output/` + file-level verification

Convert each `Working/` FLAC to ALAC `.m4a` in `Output/` (sibling of `Working/`)
via ffmpeg `-c:a alac`, preserving cover (folder-level, else embedded), recorded in
a `RunRecord(kind: .convert)`. Then `VerificationResult` over `Output/`: actual
file count vs plan; per-file **tag read-back** (via `AudioMetadataClient`) equals
`ProposedTags`; audio stream present with duration > 0. Surface a per-file
pass/fail panel and a single "verified / not verified" state; the M1 **Apply**
control is now the live entry point and gains a **Convert** follow-on (enabled only
when the apply run succeeded; disabled with reason otherwise). MP3/M4A shows skip
conversion and verify the tagged `Working/` files directly (no ALAC step), matching
the pipeline. **Tests:** convert command argv; verification logic over fixture
`AudioTags` (count mismatch, tag mismatch, zero-duration → not verified);
tag-match comparison normalizes the same way the writer does. **Done when:** a FLAC
show goes plan → `Working/` → `Output/` → green verification end to end with zero
writes outside `Working/`+`Output/`.

## Constants register (pre-justified — jon-platform "constants need a rationale")

Derived from the existing pipeline and toolchain doc, not guessed. Codex must not
introduce new bare constants without the same treatment.

- **Tool search dirs = `/opt/homebrew/bin`, then `/usr/local/bin`, then `PATH`.**
  Apple-silicon and Intel Homebrew prefixes; a Finder-launched `.app` doesn't
  inherit the shell `PATH` (toolchain.md), so explicit dirs come first.
- **Required tools = `metaflac`, `ffmpeg`, `ffprobe`.** Exactly what
  `music_pipeline.sh` requires: `metaflac` (FLAC Vorbis tags + embedded picture),
  `ffmpeg` (MP3/M4A tagging, FLAC→ALAC), `ffprobe` (stream/duration inspection).
- **Derived directory names = `Working/`, `Output/`**, both created under the show
  root. `Working/` is the script's name; `Output/` is the docs' name for the
  promoted location (the script used `./ALAC`). Both are siblings; originals live
  above them.
- **ALAC encode = `ffmpeg -c:a alac` into `.m4a` with `-movflags +faststart`;
  cover via mapped `mjpeg` `-disposition:v:0 attached_pic`.** The verified recipe
  from the pipeline's `flac_to_alac_parallel`.
- **FLAC tag write = `metaflac --remove-tag=K --set-tag=K=V` per field; cover via
  `--remove --block-type=PICTURE` then `--import-picture-from`.** From the
  pipeline's `apply_setlist` FLAC branch.
- **MP3/M4A tag write = `ffmpeg -c:a copy` stream-copy with `-metadata` atoms**
  (`-id3v2_version 3` for MP3; `-f ipod -movflags +faststart` for M4A). From the
  pipeline's `tag_audio_in_place`.
- **Cover detection = `front.*` then `image.*` (case-insensitive)**, the M1
  constant, reused for embedding.
- **Filename illegal-char set + replacement** = the M1 `FilenameSanitizer`
  constants; reuse, do not redefine.

Inherited unchanged from M1: supported extensions `{flac, mp3, m4a}`, zero-pad
width `max(2, digits(trackCount))`, `discNumber = 1`.

## Decisions for Jon to confirm (not Codex's to make alone)

1. **`Output/` as the promoted-location name** (vs the script's `ALAC/`),
   sibling of `Working/` under the show root. I recommend `Output/` to match the
   docs; confirm.
2. **`Working/` retained through M2** (deleted only after M3 import+verify, per
   Phase 5). Confirm M2 never deletes it — replacing an existing `Working/` is an
   explicit, surfaced choice, defaulting to *reuse* or *abort*, never auto-delete.
3. **Checksums on the copy step (open question "File Safety").** Recommendation:
   SHA-256 each source and verify the `Working/` copy matches *before* tagging it
   — cheap, and it's the first mutation, so prove the copy is faithful. A
   `ChecksumClient` lands in Slice 3 if you agree; otherwise copy trusts
   `FileManager`.
4. **Tool-override storage:** a dedicated SQLiteData `ToolOverride` table vs a
   typed app-settings record. I lean settings-record (one row, tiny); confirm.
5. **Verification depth in M2:** count + tag read-back + audio-stream/duration
   presence (file-level). The library-scan half (album appears in Apple Music with
   matching title + track count, optional duration spot check — the *resolved*
   definition in open-questions) is **M3**. Confirm M2 stops at file-level.

## Working agreement

- Each slice: branch → PR → merge (main protected; 0 approvals required, you
  self-merge after the architect's `approve`). Commit messages end with the
  `Co-Authored-By` trailer; PR bodies end with the tool trailer.
- Tests with swift-testing; control time/uuid/db/process via `@Dependency`. The
  apply/convert/verify logic must be testable offline against a **mock
  `ScriptClient`**; real-tool integration tests are guarded on tool availability
  and must not be the only coverage.
- New OS-26/27 APIs are past the model's training cutoff — prefer the installed
  `swiftui-*` skills + SDK headers over memory (toolchain.md).
- Surface any new constant in the PR description; flag, don't bury. If an operation
  the pipeline performs isn't reproducible with the pinned recipe, stop and flag
  it rather than inventing flags.
