# Open Questions

The architect's and Jon's scratch pad: candidates, parked work, and decisions for Jon's review.
**The executor never reads this file** (jon-platform ADR-0005). Work becomes dispatchable only when a
plan PR moves it into a milestone or effort and sets `docs/NEXT_UP.md`.

## Candidates & parked work (moved from `CURRENT_HANDOFF.md`, 2026-09-29)

- **M4 Reconcile fast-follow** — re-point the registry entry when identity drift is found, and sharpen
  same-title/different-owner duplicate detection
  ([ledger](milestones/M4-compilation-album-append.md)). **Evidence-gated by design:** build it only when
  a real append spawns a `Great Covers 2` drift. None observed in daily use yet.
- **Pending Jon decision — M4 identity-drift (#2/#3).** Decide identity-match forgiveness and no-match
  behavior *when* a real append mangles a title. Parked until the evidence appears.
- **LLM song list → Apple Music playlist** — [M11](milestones/M11-song-list-playlist.md) shipped
  in #66 (S0) and #67 (S1 + S2, merged 2026-10-15). Jon passed the on-device gate on
  2026-10-17. Settled in the feasibility pass: hand-roll the Apple
  Music API create call rather than depend on MusadoraKit; catalog-only for v1; input is a
  pinned ChatGPT Project contract (`VF-PLAYLIST: v1`, Yes Chef/Galavant pattern), not free-text
  parsing.
- **Library context for the playlist chat** — planned as
  [M12](milestones/M12-library-context-mcp.md) (2026-10-15): a library snapshot, a stdio MCP
  server reached through Secure MCP Tunnel (ChatGPT), Claude Code, and Codex, plus a
  `stage_playlist` inbox and preview annotations. Dispatches 1 (#72) and 2 (jon-platform#74, the
  shared `MCPServerKit`, `HandoffInbox`, and `mcp-tunnel`) are merged with their device gates
  passed. Dispatch 3, S2 (`vf-mcp` and the playlist inbox), merged as #76 on 2026-10-17, and
  its device gate is owed. M12 Decisions 3 and 4 are approved, and jon-platform ADR-0007 is **Accepted** (jon-platform#75, 2026-10-17).
  **Pending Jon:** Decision 1 (Last.fm); see the listening-history entry below. A Yes Chef
  MCP server, reading its synced database read-only, is the likely second consumer and starts by
  spiking app-group container access (ADR-0007 *Open*). Galavant waits. Last.fm (S3) stays parked
  until the S2 device gate shows whether library stats alone feel thin.
- **M12 listening history: poll Apple's recently-played feed instead of Last.fm?** (probed
  2026-10-17). **Recommendation: yes, and drop Last.fm (Decision 1 → no, S3 not built).** Jon
  doesn't need older history, and Last.fm sees only Marvis plays. Build this after the S2 gate,
  as its own slice.
  - **What the probe found** (a throwaway build of the app, using `MusicDataRequest`):
    - **Mac play counts miss device listening.** "Love It When You Call" showed 0 plays on both
      library copies after days of plays on Jon's iPhone and iPad, and only 2 tracks had a
      played date in the last 3 days. Snapshot play-count deltas can't measure his listening.
    - **`GET /v1/me/recent/played/tracks?types=songs,library-songs` sees everything:** phone,
      iPad, and car plays, catalog songs that aren't in the library, and library songs,
      including uploaded ones. The default (`songs` only) hides library plays, which were most
      of Jon's recent listening.
    - **Limits:** at most 30 per request, paged with `next`. The songs-only list ran out at 74
      items; the merged list's depth wasn't measured. There are no timestamps, and the list is
      de-duplicated: a song appears once, at its most recent play. Heavy rotation returned 2
      items.
  - **Why polling still works:** each fetch is "songs played since the last fetch, newest
    first", followed by the previous list minus those songs. Comparing two fetches gives the
    songs played in between, dated to that window. A fetch with no overlap with the previous
    one records an explicit gap instead of missing plays silently.
  - **Shape:**
    - **The poller runs on Jon's always-on Mac mini** (circa 2021; Jon, 2026-10-17), not the
      laptop, which travels and sleeps. It reads Apple's servers, not a local library, so any
      Mac signed in to Jon's Apple ID works. If the mini is Intel, the full app (macOS 27)
      can't run there, so it's a small separate poller app with its own MusicKit App ID and
      profile (the #69 chore). If it's Apple silicon on macOS 27, the app binary with a flag
      works too. An hourly login agent runs it: fetch, compare, append, exit, with no window.
      The probe proved a signed app is authorized when run this way.
    - **The log lives in an iCloud Drive folder.** The mini is the only writer, so there are no
      sync conflicts; `vf-mcp` on the laptop only reads it.
    - The log is append-only and derived, outside SQLiteData like the snapshot (Decision 3).
      Snapshot format v1 is unchanged.
    - `top_artists` / `top_tracks` gain a `period` (7 days, 30 days), plus a `recent_listening`
      tool.
  - **Precision:** a song played several times within one hour counts once, but plays across
    hours and days each count, which is enough for "what have I been into lately".
  - **Open before a brief:**
    - whether Marvis plays appear (it uses the system player, so probably);
    - whether skipped or partial plays count;
    - the merged list's depth;
    - the feed's behavior is undocumented and could change, so the log keeps each fetch's
      ordered list (type, ID, artist, title, album) and the comparison can be re-run later.
- **M11: Create can lose the playlist it just made when a later batch fails** (from the #67
  review, 2026-10-15). `createLibraryPlaylist` sends the first 100 IDs with the create call,
  then appends the rest in batches of 100. If a later batch throws, the error drops the
  `CreatedPlaylistRef`. The model then shows no playlist, and Create again makes a second one.
  This only affects playlists over 100 songs. Candidate fix: throw a typed partial-create error
  that carries the ref and the unsent IDs, so the model enters the post-Create state with those
  rows left over. Low priority until Jon builds a playlist that long.
- **App-target test failing on `main`: `CollectionInboxAppendTests`** (found in the #67 review,
  2026-10-15). `resumingInboxRebuildsFromStagedFilesAndClearsDerivedFolders` hits an
  unimplemented `@Dependency(\.uuid)` (reached through `FileSystemClient`) and fails. It most
  likely dates from #60/#65. It went unnoticed because the executor's host runs macOS 26.6,
  which only compiles the app test bundle; the architect's macOS 27 host is the only place it
  runs. Candidate fix: a one-line `$0.uuid = .incrementing` override in that test. It's small
  enough to fold into the next dispatch that touches the Inbox, or to send as its own small
  effort.
- **Folder-picked compilation appends leave derived folders behind** (from the #65 review,
  2026-10-14). A compilation append builds `Working/` and `Output/` *inside* the user's picked
  folder, and after #65 `Output/` holds a copy of every track. Nothing cleans either one up after
  certify (Inbox appends are drained; live shows have `cleanUpProducedFolders`). Candidate effort:
  offer the same certify-gated cleanup for folder-picked appends, or build them under an
  app-owned scratch root instead of the user's folder.
- **M12: is the 30 s read budget still right for an 87k-track library?** (from the #72 review,
  2026-10-17). **Recommendation: keep the budget and watch it;** revisit if a refresh fails or the
  library grows. M12 assumed about 30k tracks; Jon's library is 87,100, and a full snapshot
  refresh measured 21–25 s at the S1 gate. That leaves about 5 s of headroom.
- **M12: should the launch refresh skip when Music.app isn't running?** (from the #72 review,
  2026-10-17). **Recommendation: yes;** launch refreshes only when Music is already running, and
  the manual **Refresh Library Snapshot** button stays the way to launch it. Today a snapshot
  older than 6 h makes Vinyl Fever launch Music.app at its own launch. Pending Jon.
- **M12: what JSON type should `LibrarySnapshot.lastfm` have?** (from the #72 review,
  2026-10-17). **Recommendation: S3's brief gives it a real JSON type** and decides whether that
  needs a snapshot version bump. It's typed `Data?` today, which encodes as base64. It's always
  `null` until S3, so nothing depends on the current encoding.
- **M12: sign `vf-mcp` for a distributed build** (from the #76 review, 2026-10-17). The app
  bundles the helper at `Contents/Helpers/vf-mcp` from a post-build `swift build`, and the
  linker only ad-hoc signs it. That's fine for local builds: the app's
  `codesign --verify --deep --strict` passes. An archived or notarized build would need the
  helper signed with the team identity and the hardened runtime before the app is signed.
  **Recommendation:** nothing until Vinyl Fever is archived for anyone but Jon. Then the build
  phase runs `codesign --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime` on the helper.
- **M12: a release build of `vf-mcp` takes about 5 minutes** (from the #76 review, 2026-10-17).
  The Release post-build phase does a full `swift build -c release` of the helper and its
  dependencies in its own scratch path. Debug builds take about 30 s. That only costs Release
  builds and archives today. **Recommendation:** watch it. If archives get frequent, cache the
  scratch path across builds, or build the helper as an Xcode target in the same build graph.
- **App tests: launch tasks in the test host read live dependencies** (from the #76 review,
  2026-10-17). One of three app-test runs recorded a `@Dependency(\.date)` "no test
  implementation" issue against «unknown». It came from `AppShellView`'s
  `.task { loadSnapshotAndRefreshIfStale() }` (S1), which runs when the host app launches. It
  depends on timing, and `xcodebuild` still reported success. It's the same family as the
  `CollectionInboxAppendTests` `\.uuid` entry above. **Candidate fix:** skip the app shell's launch
  tasks when running under tests (`@Dependency(\.context) == .test`), or have the test host
  launch an empty scene. It's small enough to fold into the next dispatch that touches the app
  shell.
- **M12: `libraryIndexArrivalIsObservable` doesn't test arrival** (from the #76 review,
  2026-10-17). The test starts observation tracking before setting the snapshot, so its
  `onChange` fires on the synchronous `libraryIndex = nil` reset in `didSet`, not when the
  off-main index lands. It still catches the original bug (an `@ObservationIgnored` index),
  but not a later regression that assigns the built index without notifying observers.
  **Candidate fix:** set the snapshot first, then start tracking, then
  `await waitForLibraryIndex()` and expect the change. Fold it into the next M12 slice.


## V1 Scope

- Which existing script is most important after `music_pipeline.sh`?
- Which remaining steps truly need shell/Python rather than Swift?

## Live Show Prep

- Are the default live-show album title rules in `setlist-formatting-rules.md`
  complete?
- Are the source labels in `setlist-formatting-rules.md` complete, or should
  additional defaults such as `WEB`, `MTX`, or others be added?
- Resolved: see "Verified" in [App Areas](app-areas.md) and Source Of Truth And
  Storage Ownership in [Metadata Policy Model](metadata-policy-model.md). A show
  is verified when its album appears in the Apple Music scan with a matching
  album title and a track count equal to the setlist, with an optional duration
  spot check.
- What Apple Music fields/data should identify an imported album as a live show
  for the chronological artist view?
- What should the local-model live-show label audit flag as "probably mislabeled"?
- Resolved (2026-07-03 review): see *Automation Implications* in
  [Setlist Formatting Rules](setlist-formatting-rules.md). The Normalizer is a
  sandwich — deterministic pre-segment (clean + region hints, no decisions) ->
  frontier LLM via `ModelClient` (all semantic judgment, emits structured JSON)
  -> deterministic validate (tags, ALBUM/DATE shape, controlled source vocab, no
  invented source, track-count sanity) -> mandatory human preview. Source of
  truth is what's on the media, not a reconstructed show. Buildable now,
  independent of the M3 beta-3 pause.
- Resolved: the interactive review session ran 2026-07-03 against a 18-file raw
  corpus; outcomes folded into *Automation Implications*. The rules body remains
  open to revision, but the automation boundary is settled.

## Collection Policies

- What are the first Collection Policies to model?
- Should a policy target an Apple Music playlist, a Smart Playlist rule, or both?
- Is ` | ` the final delimiter for multiple Grouping tokens?
- What should happen when imported files already have Grouping values?
- What should the first folder-application workflow do when a folder contains
  mixed artists or already-tagged songs?
- Which fields can a policy change automatically?
- Which fields always require review?

### Compilation-Album (Append) Policy

- Resolved direction: see *Compilation-Album (Append) Policy* in
  [Metadata Policy Model](metadata-policy-model.md). VF appends tracks to
  curated albums that already exist in Apple Music; it never creates albums or
  the silent cover-carrier track. A small SQLiteData registry (~10–20 entries),
  seeded by folder-drop / parent-folder discovery, is the workspace — not a
  library mirror. Album Artist is the owner identity; track/disc strip defaults
  on (per-album toggle); Compilation flag defaults off (per-album override);
  artwork keeps original embedded art and falls back to the collection cover
  only when a song has none.
- Identity drift is the main open risk: the merge key (`Album` / `Album Artist`)
  is read from file tags, but Apple Music may have mutated it on import, which
  silently spawns a duplicate album instead of merging. First-append
  certification checks the exact album exists and its track count went up. Open:
  how forgiving should the match be — exact string only, or trim/normalize
  whitespace and leading articles before comparing? And what should VF offer when
  the check finds no matching album (block, warn-and-proceed, or open a
  reconcile step to re-point the entry at the real album)?
- Open: when seeding an entry from a folder whose files disagree on `Album` or
  `Album Artist`, which value wins — most common, first, or prompt?

## Metadata Management

- What exactly belongs in Metadata Management versus Collection Management?
- Is Apple Music remediation part of Metadata Management, or should it become its
  own app area later?
- Which first metadata-repair workflow would make this area concrete?

## MusicBrainz and Artwork

- For song-level lookup, what release types should be preferred by default?
- How strongly should various-artist compilations be penalized?
- Are there cases where VA compilation artwork is desired?
- Should cover art be fetched only from MusicBrainz-linked sources, or can the app
  use other sources later?
- Should lookup decisions be cached permanently?

## Apple Music Remediation

- Resolved direction: the read/verification surface is decided early, not later.
  Default to AppleScript/ScriptingBridge as the primary read surface with
  `Library.xml` as a fallback; see Verification Surface in
  [Technical Architecture](technical-architecture.md).
- Should the app ever automate deletion from Music.app, or only prepare manual
  reimport packages?
- What fields does Music.app most often fail to refresh?
- What is the safest manual reimport checklist?

## File Safety

- Should every source file get SHA-256 checksummed before a run?
- Should checksums be required only for destructive or source-mutating workflows?
- Should the app maintain an archive folder for replaced files?
- For failed or unapproved live-show runs, how long should generated `Working/`
  folders be kept before cleanup?

## iPad Companion

- Which screens would be useful away from the Mac?
- Should work queues and metadata policies sync through CloudKit eventually?

## Shared Components

- Extraction trigger: when Vinyl Fever starts consuming model access (Phase 5),
  lift Galavant's `GalavantAI` into a neutrally-named shared package both apps
  depend on, per `jon-platform/docs/adr/0001-extract-model-layer.md`. Confirm the
  path: depend on the extracted shared package (intended), copy/vendor for now, or
  defer AI until after extraction. Recommendation: rename-and-move at Phase 5; do
  not pre-extract and do not copy.
- Resolved (2026-07-03 review): setlist normalization targets the frontier /
  BYO-key tier. The prose-inference, dirty-OCR, and multi-line-jam cases in the
  raw corpus lean on reasoning quality the on-device/Apple-cloud tier cannot yet
  be assumed to reach, so the feature is BYO-required. See *Automation
  Implications* in [Setlist Formatting Rules](setlist-formatting-rules.md). A
  tiered on-device-then-escalate approach remains a possible later optimization.
- Does AcoustID fingerprint lookup ever enter scope? If so, it is the only
  non-model credential; decide whether it reuses the shared Keychain key store.
