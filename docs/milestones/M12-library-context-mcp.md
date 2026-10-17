# Milestone 12 — Library Context for Chat (MCP)

*Give the chat that builds playlists real knowledge of Jon's library and listening, through a
local MCP server, and show the same knowledge in the playlist preview. Dispatch 3 (S2) is the
current `NEXT_UP.md`. Rules in [../technical-architecture.md](../technical-architecture.md),
`/Users/jon/code/jon-platform/AGENTS.md`, and jon-platform
[ADR-0007](/Users/jon/code/jon-platform/docs/adr/0007-app-data-over-local-mcp.md) apply. Where this
doc and those conflict, stop and flag it.*

Summary: Vinyl Fever writes a derived **library snapshot** (tracks, play counts, favorites, dates)
from Music.app. A small **stdio MCP server** shipped inside the app reads it and answers
read-only questions from ChatGPT (via OpenAI's Secure MCP Tunnel), Claude Code, and Codex. One
write tool, `stage_playlist`, drops a `VF-PLAYLIST: v1` playlist into an inbox that the Playlists
area shows for review, so the human Create in Vinyl Fever stays the only write to Apple Music. The
preview also annotates every matched row with library stats. The protocol plumbing, the
staging inbox, and the tunnel ops script are domain-free, so they're built once in jon-platform by
the [mcp-server-kit](../efforts/mcp-server-kit.md) effort; Vinyl Fever owns only its snapshot and
tools. Four slices plus that effort, in four dispatches. No schema.

## The milestone in one sentence

M11 lets Jon paste a playlist that a chat model suggested. M12 lets that model **look things up
in Jon's library while it suggests**: "have I played this to death?", "which of these do I already
own?", "what have I loved but not played in years?". It also lets the model **hand the finished
list to Vinyl Fever without a paste**, from any device, while Jon still reviews and creates it at
the Mac.

## Why this shape

- **Tools beat a pasted profile.** A taste summary in Project instructions is lossy and goes
  stale. A 30k-row library export dumped into a chat is worse: retrieval over it is unreliable,
  and the model will confidently claim Jon owns things he doesn't. With MCP tools the model asks
  exact questions and gets exact answers, sized to the question.
- **Proven end to end before planning (2026-10-15).** A hello-world stdio MCP server on Jon's Mac
  was called from **normal ChatGPT chat on desktop and on iPad** through OpenAI's Secure MCP
  Tunnel. `tunnel-client` runs the stdio command itself, so one binary serves ChatGPT, Claude
  Code, and Codex. Claude Code (Remote Control) and Codex (Codex Remote) both drive sessions on
  the Mac from a phone, and those sessions see local MCP servers. No HTTP transport is needed.
- **The server reads a snapshot, not Music.app.** A binary launched by `tunnel-client`, Claude
  Code, or Codex would need its own macOS Automation permission to script Music.app, and a full
  ScriptingBridge read is too slow to run per question. The app already holds the Automation
  grant (`com.apple.security.automation.apple-events`), so it writes the snapshot and the server
  only reads a file. That leaves the server with no secrets, no network access, and no
  permissions, and makes it trivially testable against fixtures.
- **A derived file, not SQLiteData.** The snapshot is a cache that can be rebuilt at any time.
  It is never authoritative, never synced, and never edited. Keeping it out of the app database
  keeps M12 clear of the schema escalation trigger (jon-platform ADR-0005 D9), as M11 did.
- **Propose, never write, still holds.** `stage_playlist` writes only into Vinyl Fever's inbox.
  ChatGPT asks Jon to confirm every call to a tool that lacks `readOnlyHint`, which gives a
  second checkpoint. Apple Music changes only when Jon presses Create in the preview, exactly as
  in M11. The staged payload *is* the `VF-PLAYLIST: v1` contract, decoded by the same
  `PlaylistContract.decode`, so there's no second format and no second parser.
- **The contract travels with the server.** MCP's server `instructions` field carries the
  playlist rules, so no assistant needs Project instructions to use the tools. The M11
  paste-the-block flow stays the fallback for chats without the tools (mobile without the
  tunnel, a different assistant).
- **Shared plumbing lives in jon-platform from day one** (ADR-0007 D1, D3, D4, D7). Yes Chef
  is a likely second consumer, so building the JSON-RPC loop, the inbox, and the tunnel recipe
  inside Vinyl Fever and lifting them later would mean writing them twice. Vinyl Fever's
  server is `MCPServerKit` plus Vinyl Fever's tools. Its inbox is `LLMHandoffKit.HandoffInbox`.
  Its setup doc covers only what is specific to Vinyl Fever.
- **Annotations go in the preview.** The model can be wrong about what Jon owns; the preview is
  where Vinyl Fever has the final say. M11's preview already holds every matched row, and a
  play-count badge plus a "remove heavily played" action cost little there.

## The spine

```
Music.app ──ScriptingBridge bulk read (app, has Automation grant)──▶ LibrarySnapshot (JSON, derived)
                                                                          │
              ┌───────────────────────────────────────────────────────────┤
              ▼                                                           ▼
   vf-mcp (stdio, in app bundle, on MCPServerKit)            PlaylistBuilderModel preview
   LibraryIndex queries (core, pure)                         LibraryIndex.annotate(row) → badge
     read tools: overview / top / search /                    "Remove N played ≥ 20×"
       artist_profile / check_tracks
     write tool: stage_playlist ──PlaylistContract.decode──▶ HandoffInbox: PlaylistInbox/*.vfplaylist
              ▲                                                           │
   tunnel-client (ChatGPT, any device)                                    ▼
   Claude Code / Codex (Mac, or driven remotely)            Playlists area: "From chat (1)"
                                                             → same resolve → preview → Create (M11)
```

## Library snapshot (format v1)

One JSON file, written atomically (temp file + rename) to
`~/Library/Application Support/VinylFever/LibrarySnapshot/library-snapshot.json`. The app is not
sandboxed, so the helper reads the same path.

```json
{"format":"vf-library-snapshot","version":1,"generatedAt":"2026-10-15T21:40:00Z",
 "trackCount":28431,
 "tracks":[{"persistentID":"8F3A…","name":"Starry Eyes","artist":"The Records",
   "albumArtist":"The Records","album":"The Records","genre":"Power Pop","year":1979,
   "durationSeconds":161.2,"playCount":43,"skipCount":2,"favorited":true,"rating":80,
   "dateAdded":"2014-03-02T…","lastPlayed":"2024-03-11T…","availability":"subscription"}],
 "lastfm":null}
```

- `availability` maps Music's `cloud status` to `subscription | purchased | matched | uploaded |
  other`. `uploaded` means library-only, such as live shows from the drives: the catalog
  matcher can't find those, so the tools flag them and the model knows not to put them in a
  playlist. `uploaded` also covers Music's `not uploaded` and `ineligible` cloud statuses: all
  three are library-only files with no catalog counterpart.
- **Never in the file:** file locations, comments, lyrics, and anything else not listed above.
- **Version handling:** the reader rejects a newer `version` with a typed error (fail loudly
  rather than lose data silently). An older version is rebuilt on the next refresh.
- `lastfm` stays `null` until S3.

## Tool surface (server)

Every tool returns compact JSON text and never file paths or `persistentID`s. Results are capped
(see *Constants register*). Read tools carry `readOnlyHint: true` and `openWorldHint: false`.

| Tool | Input | Returns |
| --- | --- | --- |
| `library_overview` | none | snapshot age, track/artist/album counts, genre and decade mix, top 10 artists by plays |
| `top_artists` | `by` (`plays` \| `favorites` \| `recently_added`), `limit` | artists with plays, favorites, track count, last played |
| `top_tracks` | `by` (`plays` \| `favorites` \| `recently_added` \| `recently_played`), `limit` | tracks with stats |
| `search_library` | any of `artist`, `title`, `album`, `genre`, `year_from`/`year_to`, `min_plays`/`max_plays`, `favorited`, `availability`; `sort`; `limit` | matching tracks with stats |
| `artist_profile` | `artist` | albums owned, track count, total plays, favorites, first added, last played, most-played tracks, library-only count |
| `check_tracks` | `tracks: [{artist, title}]` (≤ 200) | per track: `owned` / `not_owned`, plays (summed across versions), version count, favorited, last played, availability |
| `stage_playlist` | the contract object: `name`, `description?`, `tracks[{artist,title,album?,year?}]` | `{staged, name, trackCount, dropped[]}` plus "Jon reviews and creates it in Vinyl Fever; nothing is in Apple Music yet" |

`stage_playlist` carries `readOnlyHint: false`, `destructiveHint: false`. It serializes its
input to the contract's wire text (marker line plus one object) and runs `PlaylistContract.decode`
on it. Only if that succeeds does it write the inbox file. Otherwise it returns `isError: true`
with the decoder's message, so the model can fix the input and try again.

Server `instructions`; the first 512 characters must make sense on their own:

> Vinyl Fever exposes Jon's Apple Music library and listening stats. Use these tools for any
> claim about what Jon owns, has played, or has loved — never guess. Before proposing a final
> list, call check_tracks on it. Tracks with availability "uploaded" are library-only and can't
> be added to a catalog playlist; leave them out. When Jon asks for the playlist, call
> stage_playlist with the final list instead of printing it; Jon reviews and creates it in
> Vinyl Fever. Snapshot age is in library_overview.

The remaining playlist rules (no invented tracks, versions in titles only when they're the
point) follow, generated from the same Core text as `PlaylistContract.projectInstructions` so
the two can't drift.

## Slices

**Dispatch 1: S0 + S1.** They share the snapshot types and are valuable on their own: the
preview annotations work with no MCP at all. **Dispatch 2: effort
[mcp-server-kit](../efforts/mcp-server-kit.md)**, a single PR in **jon-platform**.
**Dispatch 3: S2**, which builds on that effort. **Dispatch 4: S3**, only if Jon approves
Last.fm (see *Decisions*). Dispatches 1, 2, and 3 each owe a device gate on Jon's Mac.

- [x] **Effort — mcp-server-kit (jon-platform).** See the [brief](../efforts/mcp-server-kit.md).
  It builds `MCPServerKit`, `LLMHandoffKit.HandoffInbox`, and `scripts/mcp-tunnel`. Merged as
  jon-platform#74 (squash `b6f48d6`) on 2026-10-17, after Jon passed the `mcp-hello` iPad gate.

- [x] **S0 — Snapshot model + library index (core, pure, no ScriptingBridge, no UI).**
  - `LibrarySnapshot` and `LibraryTrack` value types, plus a versioned codec for format v1 (see
    above). A newer version is a typed error; dates are ISO 8601.
  - Pull the scorer's private normalizers (`normalizeArtist/Title/Album/Text`) into an internal
    `SongTextNormalizer`. This is a pure refactor: `CatalogMatchScorer` behavior and its tests
    are unchanged.
  - `LibraryIndex`, built once from a snapshot. It keys tracks by normalized artist + title and
    implements one pure function for each read tool (`overview`, `topArtists`, `topTracks`,
    `search`, `artistProfile`, `checkTracks`), all returning plain value results with the caps
    applied.
  - `checkTracks` treats several library tracks with the same normalized artist + title as
    versions of one song. It sums their plays and reports `versionCount`.
  - `LibraryAnnotation` for a resolved row: `.inLibrary(plays:lastPlayed:favorited:versionCount)`,
    `.notInLibrary`, or `.snapshotUnavailable`. It matches the request's artist + title (and the
    picked candidate's when they differ) through the same normalizer.

  **DoD:**
  - `swift test` is green.
  - A codec round-trip test, and a test that a newer version gives a typed error.
  - Index tests over a hand-built fixture snapshot (~30 tracks):
    - each query's sort order and caps;
    - `search` filter combinations;
    - `checkTracks`: owned, not owned, multi-version summing, a featuring credit in the
      library title, diacritics;
    - `artistProfile` counting library-only (`uploaded`) tracks;
    - annotations for owned, not owned, and no snapshot.
  - The existing scorer tests pass unchanged after the normalizer extraction.

- [x] **S1 — Snapshot writer + preview annotations (app).** Device gate passed 2026-10-17.
  - `MusicAppClient.readLibrarySnapshot()` is the new endpoint; the live implementation stays
    in `MusicAppClient+Live.swift`. It does a **bulk property read**: one KVC
    `value(forKey:)` per property on the library playlist's `tracks` `SBElementArray`, so each
    property costs one Apple event rather than one per track. It zips the arrays into
    `LibraryTrack`s.
  - `LibrarySnapshotStore` is a dependency client with read, write, and `modifiedAt`. The live
    implementation writes atomically to the path above; the test implementation is in-memory.
  - **Refresh:** in the background at launch when the snapshot is older than the stale
    threshold, plus a **Refresh Library Snapshot** button in the Playlists area. A status line
    shows "Library snapshot: 28,431 tracks · 2 h ago", or the error. A refresh never blocks the
    UI, and a failed refresh keeps the previous file.
  - **Preview:** each matched row, and the picked candidate of each ambiguous row, shows a
    badge: "In library · 43 plays · last Mar 2024 · ♥" or "New to you". A **Remove N tracks
    played ≥ 20 times** action appears when N > 0. It removes rows the same way the per-row
    remove does; it is not a hidden-filter state.

  **DoD:**
  - Model tests with a stubbed store:
    - badges match the annotation for each row state;
    - the bulk remove takes out exactly the rows over the threshold and leaves Create's ID
      list in order;
    - with no snapshot, rows have no badges and nothing fails;
    - refresh-on-launch runs only past the stale threshold;
    - a failed refresh keeps the old snapshot and shows the error.
  - The live ScriptingBridge read is **unverified** in the PR.
  - **Device gate (passed 2026-10-17, no longer owed):** on Jon's Mac:
    - time a full refresh, against the read-budget constant (21 s or less at 87,100 tracks);
    - spot-check three tracks' play counts and favorites against Music.app (3 of 3);
    - confirm a live show from the drives shows `availability: uploaded` (it does);
    - resolve an M11 paste and check the badges (correct).
    - **If the refresh exceeds the budget, stop and flag it** rather than optimizing blind.

- [ ] **S2 — `vf-mcp` stdio server + playlist inbox (core executable + app).** Device gate
  owed. Requires the mcp-server-kit effort to have merged.
  - Add the new executable target `VinylFeverMCP` (product `vf-mcp`) to the `VinylFeverCore`
    package. It depends on `VinylFeverCore` and `MCPServerKit`, a path dependency mirroring the
    `LLMClientKit` entry. `project.yml` copies the built binary into the app bundle at
    `Contents/Helpers/vf-mcp`, so it installs and updates with the app.
  - **Protocol comes from `MCPServerKit`** (ADR-0007 D7). `vf-mcp` is an `MCPServer` built from
    the tool table above and the `instructions` text, with no JSON-RPC code of its own. Each
    tool's handler decodes its input, calls the matching `LibraryIndex` function, and encodes
    the result.
  - **The kit as shipped** (jon-platform#74): handlers are `async throws`, and a thrown error
    becomes an `isError` result. `MCPToolResult.json(_:)` already encodes dates as ISO 8601 with
    sorted keys, so `vf-mcp` needs no encoder of its own. The `MCPServerKit` package also
    declares `LLMHandoffKit` (for its `mcp-hello` sample), which `VinylFeverCore` already
    depends on at the same path.
  - **Build the app's `LibraryIndex` off the main actor** (from the #72 review). Today
    `PlaylistBuilderModel.librarySnapshot`'s `didSet` builds it on the main actor, about 1.8 s
    at 87k tracks in a release build. Build it in a detached task and assign the result on the
    main actor; a newer snapshot that lands mid-build wins. Rows show no badges until the index
    is ready, as with no snapshot.
  - It loads the snapshot lazily, reloads when the file's `modifiedAt` changes, and builds the
    `LibraryIndex` once per load. With no snapshot, every read tool returns `isError: true`:
    "Open Vinyl Fever to build the library snapshot."
  - **Inbox:** `LLMHandoffKit.HandoffInbox(root: …/VinylFever/PlaylistInbox, fileExtension:
    "vfplaylist")`. The server stages there, and the app reads it through a thin
    `PlaylistInboxClient` dependency wrapper so model tests can stub it.
  - **App:** the Playlists area shows **From chat (N)**, listing staged playlists by name,
    track count, and age. Opening one loads its text into the existing paste → resolve path
    unchanged. After Create, or after **Discard**, the file moves to `PlaylistInbox/Processed/`
    and is never deleted. The app refreshes the list when the area appears and when the window
    becomes key; no file-watcher daemon.
  - **Settings → Chat Access (MCP):**
    - the helper's resolved path and the snapshot status;
    - copy buttons for a Claude Code `.mcp.json` entry, a Codex `config.toml` `[mcp_servers]`
      entry, and the `tunnel-client init … --mcp-command` line, each with the real path filled
      in.
  - **Docs:** `docs/chatgpt/MCP-SETUP.md` covers only what's specific to Vinyl Fever and
    links jon-platform `docs/ios/mcp-access.md` for everything shared (tunnel, key, clients,
    pitfalls):
    - the helper path;
    - `mcp-tunnel init vinyl-fever <tunnel_id> "<helper path>"` and
      `mcp-tunnel install-agent vinyl-fever`;
    - the plugin name **Vinyl Fever**;
    - the `~/music-chat` folder contents (an `AGENTS.md` in a music tone that carries the
      contract, plus the `.mcp.json` / Codex entries);
    - the tool list.

  **DoD:**
  - Tool tests through `MCPServer.handle(line:)` (the kit owns the protocol tests):
    - `tools/list` includes every tool with its input schema, with `readOnlyHint` on every
      read tool and absent on `stage_playlist`;
    - each read tool against the S0 fixture snapshot;
    - with no snapshot, read tools return `isError`.
  - `stage_playlist` tests:
    - a valid payload writes one file that `PlaylistContract.decode` reads back to the same
      `PlaylistRequest`;
    - an empty-name or zero-track payload gives `isError` with the decoder's message and writes
      nothing;
    - dropped blank tracks are reported.
  - Inbox model tests: the list order; opening a staged item resolves exactly as pasting its
    text does; Create and Discard move the file to `Processed/`.
  - A test pins the server `instructions` text: the first 512 characters are the standalone
    paragraph above, `MCPServer.instructionsHeadStandsAlone` returns `true`, and the rest is
    generated from the Core contract text.
  - A model test: setting a snapshot doesn't build the index on the main actor, and the newest
    snapshot's index wins when two land back to back.
  - **Owed device gate:**
    - **ChatGPT:** from the **iPad**, through the tunnel, ask for a playlist. The model calls
      `check_tracks` and then `stage_playlist`; Jon confirms. At the Mac, the staged playlist
      appears under From chat; resolve, create, and confirm it in Music.app.
    - **Claude Code:** one session in `~/music-chat` calls `library_overview` through the same
      binary.
    - Time the first `library_overview` call after the helper starts, against Jon's 87,100-track
      snapshot (it loads the file and builds the index). Flag it if it takes over 10 s.

- [ ] **S3 — Last.fm listening history (app + core). Only if Decision 1 is yes.**
  - Settings gets a Last.fm username and API key; the key is stored in the Keychain
    (`keychain-access-groups` is already entitled). The app fetches during snapshot refresh,
    never the server:
    - `user.getTopArtists` and `user.getTopTracks` for `7day | 1month | 3month | 12month |
      overall` (limit 50 each);
    - `user.getLovedTracks` (≤ 500);
    - `user.getRecentTracks` (last 200).
  - These fill the snapshot's `lastfm` section. A Last.fm failure leaves `lastfm` stale with
    its own `fetchedAt` and never fails the library refresh.
  - `top_artists` and `top_tracks` gain `source` (`library` | `lastfm`) and `period`. A new
    read tool, `recent_listening`, returns recent scrobbles and loved tracks.
  - Tool descriptions say that Last.fm reflects **Marvis listening only**; Music.app on the Mac
    doesn't scrobble.

  **DoD:**
  - Decoding tests against recorded Last.fm JSON fixtures;
  - a test that a failed Last.fm fetch leaves the library snapshot written;
  - tool tests for each period and source.
  - The live fetch is unverified in the PR; Jon checks one period against last.fm.

## Prerequisites (Jon, not the executor's)

- [x] Secure MCP Tunnel and a restricted runtime key exist and are proven with a hello-world
  server (2026-10-15). The `vinyl-fever` profile replaces the `hello` profile in S2's gate.
- [x] ADR-0007 (jon-platform) merged before Dispatch 2 (jon-platform#73, still **Proposed**).
  The effort's PR landed before S2 (jon-platform#74).
- [ ] Before S2's gate: a `Vinyl Fever` tunnel on the Platform Tunnels page, linked to the
  ChatGPT account (jon-platform `docs/ios/mcp-access.md` step 1; ADR-0007 starts with one tunnel
  per app). The runtime key is already in the Keychain.
- [x] M11's owed device gate (Jon passed it 2026-10-17). Dispatch 1 builds on the M11 preview,
  so it should land on a verified M11.
- [ ] For S3 only: a Last.fm API account (free) and confirmation that Marvis scrobbles are
  arriving.

## Constants register (starting values)

| Constant | Value | Rationale |
| --- | --- | --- |
| Snapshot format | `vf-library-snapshot` v1 | Versioned, so the reader can reject a newer file loudly. |
| Stale threshold | 6 h | Refresh on launch past this. Play counts move slowly; `generatedAt` is visible in `library_overview`. |
| Read budget | ≤ 30 s full refresh | Bulk KVC should be seconds for ~30k tracks. Past 30 s, the S1 gate stops and flags. Measured at the S1 gate: 21–25 s for Jon's 87,100-track library (see `open-questions.md`). |
| Tool row cap | 50 default, 200 max | Keeps every tool result small: tunnel envelopes cap at 10 MiB, and the conversation pays for every byte. |
| `check_tracks` max | 200 tracks | Twice a typical M11 list. |
| Heavily played | ≥ 20 plays | Threshold for "Remove N played ≥ 20 times". Tune after the gate. |
| MCP protocol versions | per `MCPServerKit` (`2025-06-18`, `2025-11-25`) | Owned by the kit (ADR-0007 D7), not this milestone. |
| Instructions head | 512 characters, standalone | OpenAI guidance for MCP server `instructions`. |
| Inbox | `Application Support/VinylFever/PlaylistInbox/` | Items move to `Processed/`, never deleted (preserve originals). |

## Out of scope — with destinations

- **HTTP/SSE transport.** `tunnel-client`, Claude Code, and Codex all run stdio. → Only if a
  client ever needs a URL.
- **Any publicly reachable endpoint** (ChatGPT Sites hosting, public plugin submission, ngrok).
  → Never for personal library data (ADR-0007 D4).
- **The server creating or editing Apple Music playlists directly.** → No. Staging plus the
  in-app Create is the design (propose, never write).
- **Apple Music API listening data** (heavy rotation, recent plays). → Revisit if library play
  counts plus Last.fm feel thin after the S2 gate.
- **Reading the hard drives.** The library already covers what was imported. → Not planned.
- **Library-only tracks in playlists.** M11's out-of-scope item stands; the tools flag them so
  the model leaves them out.
- **A taste-profile export for Project files.** It's the fallback if MCP is unavailable. → Build
  only if Jon misses it.
- **Last.fm's similarity graph** (`artist.getSimilar`). → After S3, if suggestions lack novelty.
- **Vinyl Fever managing `tunnel-client`** (installing a LaunchAgent, holding the key). → Ops
  stays shared in jon-platform: `docs/ios/mcp-access.md` and `scripts/mcp-tunnel`.
- **Other writes** (ratings, favorites, play counts). → No.

## Decisions

Resolved (Jon, 2026-10-15):

- Lead with a **stdio, read-only VF MCP server** covering library and play stats, reached via
  Secure MCP Tunnel (ChatGPT), Claude Code, and Codex.
- `stage_playlist` is the **one confirmed write**, and it only stages.
- Library annotations in the preview.
- The cross-app pattern goes to jon-platform as **ADR-0007** (proposed alongside this plan).
- **Shared versus Vinyl Fever-only split:**
  - `MCPServerKit`, `HandoffInbox`, and the tunnel ops doc and script are built once in
    jon-platform (the effort);
  - Vinyl Fever owns only its snapshot, tools, inbox UI, and setup specifics;
  - ADR-0007 D2 allows a live read-only database (Yes Chef) or an app-written export (Vinyl
    Fever).

Open — the architect's recommendation is listed first:

1. **Last.fm (S3):** build it last, or not at all? It reflects only Marvis listening and adds a
   second credential. *Recommendation:* keep S3 parked until the S2 gate shows whether library
   stats alone feel thin. Merging this plan does **not** dispatch S3 (Dispatch 4).
2. **MCP protocol:** *moved to jon-platform ADR-0007 D7* (hand-roll it in `MCPServerKit`
   rather than depend on the pre-1.0 official SDK). It's a platform decision now, so it gets
   decided there.
3. **The snapshot as a derived JSON file outside SQLiteData** (stated here so Jon can object
   before Dispatch 1). Dispatch 1 shipped it this way; merging the S2 dispatch plan PR confirms
   it.
4. **Ship the helper inside the app bundle** (`Contents/Helpers/vf-mcp`) rather than a `~/bin`
   install, so the binary can't drift from the app's Core version. S2 builds it this way, so
   merging the S2 dispatch plan PR approves it.
