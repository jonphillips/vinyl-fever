# Milestone 13 — Listening History (Apple's recently-played feed)

*Record what Jon actually listens to on every device, and let the chat ask about it. Rules in
[../technical-architecture.md](../technical-architecture.md), `/Users/jon/code/jon-platform/AGENTS.md`,
and jon-platform [ADR-0007](/Users/jon/code/jon-platform/docs/adr/0007-app-data-over-local-mcp.md)
apply. Where this doc and those conflict, stop and flag it.*

Summary: a small **poller** asks Apple Music, once an hour, which songs Jon played recently. Apple
gives no timestamps and lists each song only once, so the poller compares each answer with the
previous one, works out what was played in between, and appends that to a **listening log** in
iCloud Drive. The poller runs on Jon's always-on **Intel Mac mini** as a separate small app,
because the main app targets macOS 27 and the mini stops at macOS 15 Sequoia. Vinyl Fever can run the
**same poller code** itself, for the laptop as a backup today and for an Apple-silicon mini
later; a lease makes sure only one Mac polls at a time. `vf-mcp` reads the log, so ChatGPT,
Claude Code, and Codex can answer "what have I been into lately?". Six slices in six dispatches (S4 and S5 added 2026-10-22). All six are done; only S2's iPad gate is still owed.
No schema.

## The milestone in one sentence

M12 gave the chat Jon's library, but the library's play counts only see the Mac. Jon mostly
listens on his iPhone, iPad, and in the car. M13 records that listening from Apple's own feed, so
"what have I had on repeat this month?" has a true answer.

## Why this shape

- **Apple's recently-played feed is the only source that sees every device** (probed
  2026-10-17; see *Evidence*). Mac play counts miss device plays, and Last.fm only sees Marvis.
  M12 Decision 1 dropped Last.fm for this.
- **The feed has no history and no timestamps,** so it has to be polled from now on. Polling
  can't start until a poller exists, which is why the poller (S1) comes before the chat tools
  (S2): the log starts filling while S2 is built.
- **The always-on mini is the right host.** The laptop travels and sleeps. The feed is a web
  API, not the local library, so any Mac signed in to Jon's Apple ID can poll.
- **One poller engine, two hosts.** The mini is a 2018 Intel model, and its last macOS is 15
  Sequoia. A separate poller app targeting macOS 15 runs there now. The same engine also runs inside Vinyl
  Fever (S3), so moving to an Apple-silicon mini later is a Settings toggle, not a rewrite. The
  poller app is then retired.

## Evidence (probe, 2026-10-17)

- `GET /v1/me/recent/played/tracks?types=songs,library-songs` returns one merged,
  newest-first list of catalog songs and library songs (including uploaded ones), from every
  device. The default (`songs` only) hides library plays, which were most of Jon's listening.
- Each request returns at most 30 items, paged with `offset`. The songs-only list ran out at 74
  items. The merged list's depth, measured at the S1 gate's baseline (2026-10-20), was 171 items
  (6 pages).
- There are no timestamps. The list is de-duplicated: a song appears once, at its most recent
  play.
- The probe was a signed build of the app, run the way a login agent would run it, and MusicKit
  authorized it.

## The spine

```
Intel Mac mini (macOS 15)                             laptop (macOS 27)
  VF Listening Poller.app, hourly login agent           vf-mcp (in VinylFever.app)
    MusicDataRequest: recent/played/tracks ─┐             ListeningLog.read → plays
    ListeningDiff (Core, pure) ◀── last list (local)      tools: recent_listening,
    append ──▶ iCloud Drive/Vinyl Fever/Listening/ ──sync──▶ top_* period
                 fetches/<poller>/<YYYY-MM>.jsonl        Settings → Listening History (status)
                 lease.json  (which Mac polls)
                                 ▲
  VinylFever.app --poll-listening (S3; the laptop now, an Apple-silicon mini later)
```

## Listening log (formats v1 and v2)

The folder is `~/Library/Mobile Documents/com~apple~CloudDocs/Vinyl Fever/Listening/`, which
Finder shows as iCloud Drive → Vinyl Fever → Listening. Neither app is sandboxed, so both
reach it directly. Writes go through `NSFileCoordinator`.

- **`lease.json`**: `{"format":"vf-listening-lease","version":1,"poller":"<uuid>","host":"Jon's
  Mac mini","takenAt":"…"}`. Only an explicit takeover writes it (S3). A poller that isn't the
  leaseholder writes nothing and exits. Before S3, the S1 poller writes the lease on its first
  run if none exists.
- **`fetches/<poller-uuid>/<YYYY-MM>.jsonl`**: one JSON object per line, one line per hourly
  fetch. Each poller has its own folder, so two Macs never append to the same file and iCloud
  never makes conflict copies of the log.

```json
{"format":"vf-listening-fetch","version":1,"poller":"6F1C…","host":"Jon's Mac mini",
 "fetchedAt":"2026-10-20T15:00:04Z","outcome":"plays","newCount":3,"pagesRead":1,
 "items":[{"kind":"library-song","id":"i.abc…","title":"Starry Eyes","artist":"The Records",
   "album":"The Records","durationSeconds":161.2}, …]}
```

- **`outcome`**:
  - `baseline`: the stream's first fetch. `items` is the whole list fetched, and nothing counts
    as a play.
  - `plays`: `items` holds the `newCount` newly played songs, newest first, followed by up to
    10 items of **overlap evidence** (the start of the previous list).
  - `none`: no new plays. A short heartbeat line with no `items`.
  - `gap`: no overlap with the previous list within the page cap. `items` is everything
    fetched, and they're logged as played at some point since the previous fetch.
  - `failed`: carries `error` (authorization, network, HTTP status). The next good fetch's
    window starts at the last good fetch.
- **Versioning:** ordinary records use `version: 1`. Handover recovery records carry
  `"since":{"poller":"<old uuid>","fetchedAt":"…"}` and use `version: 2`; readers accept
  versions 1 and 2, and reject a newer version loudly, like the snapshot. `since` names the
  newest successful fetch known when the recovery starts, even when the recovered `items` come
  from an earlier line. A baseline with `since`
  means the old stream could not be recovered, so coverage reports a handover gap. The reader
  ignores a trailing partial line, since iCloud may sync a file mid-append.
- **What's in the log:** song identity and text only. No library file locations, no account
  data, and no Apple Music user token.
- **Fidelity** (jon-platform `semantic-fidelity.md`):
  - feed → log is **lossless** for what the feed says: the new prefix and its evidence are kept
    as fetched.
  - log → plays is **intentionally lossy**: plays are dated to their hour window, and repeats
    inside one window count once.
  - Gaps and failures are **loud**: every tool result reports its coverage and gaps.
  - **A play is a start, not a listen.** The feed adds a song when it starts playing. That
    means:
    - skips count;
    - so does the next track that autoplay starts before Jon stops it, even after 2 seconds;
    - Marvis plays count too, since Marvis uses the system player.

    The feed has no timestamps or listened durations to filter on. This was measured at the S1
    gate on 2026-10-20: Jon's five plays all appeared, including a 10-second skip and a Marvis
    play, plus three autoplayed next tracks of about 2 seconds each.

    Filtering short plays is parked (`open-questions.md`, *Listening analytics*). Jon's call,
    2026-10-20: no faster polling, and counts are good enough until there's an analytical
    strategy.
- **Size:** about 24 lines a day, mostly heartbeats. Well under 100 KB a day.

## The diff (Core, pure)

The poller keeps the previous fetch's full list in its own local state
(`~/Library/Application Support/VinylFever/Listening/last-list.json`). That file is never synced,
and the log doesn't need it.

Given the previous full list `P` and the current list `C`, both newest first, find the smallest
`k` where `C[k...]`, compared over up to 10 items, equals `P` with `C[0..<k]` removed. Then
`C[0..<k]` are the new plays. Identity is `(kind, id)`.

- If the overlap isn't found in the pages read so far, read another page, up to the page cap.
- If it still isn't found, the outcome is `gap`.
- A song played again moves to the front and leaves its old position; removing `C[0..<k]` from
  `P` handles that.
- `k == 0` with a match is `none`.

**Reading the log (S2; reader guard added in S5):**
- Each `plays` line gives `newCount` plays, dated to the window (previous successful fetch,
  this fetch].
- Songs are keyed by `SongTextNormalizer` artist + title, the same key as `check_tracks`, so a
  catalog play and a library play of the same song count together.
- Streams are merged by time. If two different fetch lines have windows that strictly overlap,
  plays of the same song count once, whatever the poller. Windows that only touch still count as
  separate plays. A collapsed play does not extend its line's overlap window for later
  comparisons, so it cannot swallow a later genuine replay. The result says how many overlapping
  plays were collapsed.

## Tool surface (S2, added to `vf-mcp`)

The M12 rules still apply: compact JSON, no file paths and no IDs, results capped, read-only
tools.

| Tool | Input | Returns |
| --- | --- | --- |
| `recent_listening` | `period` (`24h` \| `7d` \| `30d` \| `90d`), `limit` | plays, newest first: artist, title, album, window start and end, in library (yes/no); plus `coverage` |
| `top_artists`, `top_tracks` | new `period`: `all_time` (default) \| `7d` \| `30d` \| `90d` | `all_time` keeps today's library play counts. Other periods count plays in the log, and only `by: plays` is allowed with them (anything else gives `isError`). |

- **`coverage`** goes on every log-backed result: the log's first fetch, the last fetch and its
  age, which Mac polls, and the gaps in the period.
- **Descriptions** say plainly:
  - that `all_time` is Mac library counts, which miss device plays;
  - that periods come from the listening log since the date polling started;
  - that a log play is a song *started*, so skips and brief autoplay count. The chat must not
    present a play as a full listen.
- The instructions head is already at 500 of its 512 characters, so tool descriptions carry
  this. The head is unchanged.
- **No log yet:** log-backed calls return `isError` with "Listening history isn't set up yet.
  See Vinyl Fever → Settings → Listening History."

## Slices

**Dispatch 1: S0** (pure Core, no prerequisites). **Dispatch 2: S1**, after Jon's
prerequisites. It owes a gate on the mini. **Dispatch 3: S2.** **Dispatch 4: S3.** The log
starts filling at the S1 gate, so S2 has real data by the time it lands.
[M14](M14-live-tracks-in-playlists.md) (live tracks in playlists) interleaves: **M14 S0 runs
between S1 and S2**, and **M14 S1 between S2 and S3** (M14 Decision 3, amended 2026-10-20).
[M15](M15-artist-identity.md) S0 and S1 also run between S2 and S3, around M14 S1. So
the dispatch after S1 is M14 S0, not S2. That gives S2's iPad gate ("what have I been listening
to this week?") a week of log to answer from.

**Dispatch 5: S4** (added 2026-10-22 from the S3 gate). It touches `VinylFeverListening`, the
poller app, and both takeover paths, but not `vf-mcp`'s tool surface. So it doesn't collide with
Taste Intelligence S1 and S2, and Jon picks the order.

**Dispatch 6: S5** (added 2026-10-22 from the S4 gate). It fixes a double count S4's recovery
can produce on handback, and adds **Poll now**. Same files as S4, so it goes next.

- [x] **S0 — Listening engine (Core, pure; no MusicKit calls, no UI).**
  - A new library target, `VinylFeverListening`, in the `VinylFeverCore` package, so the poller
    app links it without SQLiteData or the MCP kit. `VinylFeverCore` depends on it.
  - It holds:
    - the value types: `ListeningItem`, `ListeningFetch`, `ListeningLease`, `ListeningPlay`;
    - the JSONL codec for format v1;
    - `ListeningDiff`;
    - `ListeningLog`, which reads and merges streams into plays, with coverage and gaps;
    - the period queries `recentPlays` and `topArtists`/`topTracks(period:)`;
    - the lease rules.
  - `RecentlyPlayedClient` is a dependency client with one endpoint: fetch a page by
    `offset`. Its live value (MusicKit `MusicDataRequest`) is written here but unverified until
    S1. Tests use canned pages.
  - The package's platform floor stays macOS 26 (see Decision 2).

  **DoD:**
  - Codec round-trip; a newer version is a typed error; a trailing partial line is ignored.
  - Diff tests:
    - new plays at the front;
    - a replayed older song moving to the front;
    - no change;
    - more than 30 new plays across pages;
    - a gap past the page cap;
    - the baseline fetch;
    - an empty feed;
    - the same song as both `song` and `library-song`.
  - Log tests:
    - windows taken from the previous *successful* fetch;
    - `failed` and `gap` lines surface in `coverage`;
    - two overlapping streams collapse duplicate plays and report the count;
    - period queries' order and caps.
  - Lease tests: a non-holder writes nothing.

- [x] **S1 — VF Listening Poller app (macOS 15, universal; runs on the Intel mini).**
  Implementation complete; the Intel mini device gate passed (closed 2026-10-21; see below).
  - **Amended 2026-10-19 (Decision 2):** the 2018 mini can't run macOS 26, so the poller
    targets **macOS 15**. Lowering `VinylFeverCore` isn't possible, because its jon-platform
    dependencies (MCPServerKit, LLMClientKit, LLMHandoffKit) require macOS 26. So
    `VinylFeverListening` moves out into **its own package**:
    - **Location:** a new package at `VinylFeverListening/` in the repo root, beside
      `VinylFeverCore/`, with `platforms: [.macOS(.v15)]`.
    - **Contents:** the `VinylFeverListening` library and a `VinylFeverListeningTests` test
      target. It depends only on swift-dependencies.
    - **What moves:** the target's sources, as they are (no API changes). The listening engine
      and poller tests move into `VinylFeverListeningTests`. The test that checks
      `ListeningTextNormalizer.trackKey` equals `LibraryIndex`'s key stays in
      `VinylFeverCoreTests`, because it needs Core.
    - **Dependents:** `VinylFeverCore` depends on the new package by path
      (`../VinylFeverListening`) and keeps its macOS 26 floor. `project.yml` adds the package,
      and the poller target links its product.
    - **Verification:** `docs/verification.md` adds
      `$qr swift test --package-path VinylFeverListening`.
    - **Build script:** `scripts/build-listening-poller` also fails unless
      `vtool -show-build` reports `minos 15.0` for every slice of every Mach-O in
      `Contents/MacOS`.
  - **The run-once poll lives in `VinylFeverListening`**, as `ListeningPoller.pollOnce()`, so S3
    calls the same code. It's a dependency-backed model over four clients:
    - `recentlyPlayedClient` (S0);
    - an authorization client reading `MusicAuthorization.currentStatus`, which never prompts;
    - a `ListeningStore` client for the iCloud folder and local state (below);
    - `date`.
  - **A new app target, `VinylFeverListeningPoller`** (product **VF Listening Poller**, bundle
    `com.jonphillips.vinylfever.listeningpoller`), is added in `project.yml`.
    - Deployment target **macOS 15.0** (amended from 26.0; see the amendment above).
    - `ARCHS` stays the standard architectures (`arm64 x86_64` under Xcode 27). **The build
      destination decides the slices, not the settings.** A build for a concrete Mac (Xcode's
      "My Mac", or `-destination 'platform=macOS'`) is arm64 only, even with
      `ONLY_ACTIVE_ARCH: NO`. Only `-destination 'generic/platform=macOS'` (Xcode's "Any Mac")
      builds both slices. This was checked on 2026-10-18 with a throwaway app signed with the
      poller profile.
    - It depends only on the `VinylFeverListening` product.
    - Hardened runtime on, no App Sandbox. The Info.plist has `NSAppleMusicUsageDescription`.
    - It signs manually with the **VF Listening Poller Dev Profile** (explicit App ID with the
      MusicKit App Service; see *Prerequisites*), the #69 pattern. Copy the `VinylFever`
      target's signing block and its comment.
  - **`scripts/build-listening-poller`** builds the poller for the mini:
    - It builds with `-destination 'generic/platform=macOS'` into a fixed derived-data folder.
    - It checks `lipo -archs` on every Mach-O in `Contents/MacOS` (a Debug build's code is in
      `VF Listening Poller.debug.dylib`) and fails unless each lists both slices.
    - It checks `codesign --verify`, then prints the `.app` path.
    POLLER-SETUP and the gate use it, never an Xcode Run.
  - **Entry point:** a custom `@main` checks `CommandLine.arguments` for `--poll` *before*
    starting the SwiftUI app. With `--poll` it runs `pollOnce()` and exits, so it never creates
    a window or a Dock icon. S3 reuses this pattern.
  - **Local state (per Mac, never synced)** is in `~/Library/Application Support/VinylFever/Listening/`:
    - `poller.json`: `{"poller":"<uuid>"}`, created on the first run. The identity belongs to
      the Mac, not the app, so in S3 Vinyl Fever on the same Mac is the same poller.
    - `last-list.json`: the previous full list. It's written atomically (temporary file, then
      rename).
  - **iCloud writes:**
    - `ListeningStore` creates the `Listening/` and `fetches/<poller-uuid>/` folders as
      needed.
    - It appends one line to `<YYYY-MM>.jsonl`, where the month comes from `fetchedAt` in
      **UTC**, through `NSFileCoordinator` (coordinated write, then append at the end of the
      file).
    - The lease is read and written with coordinated access too.
    - `host` is the computer name from System Settings → General → Sharing
      (`SCDynamicStoreCopyComputerName`).
  - **`pollOnce()`**, in order:
    1. Read the lease. Act on the S0 lease rule: `skip` writes nothing and returns.
       `claimIfEmpty` writes the lease, then continues.
    2. If authorization isn't `.authorized`, append a `failed` line ("Apple Music isn't
       authorized on this Mac.") and return without making a request.
    3. Run `ListeningDiff().fetch(previous:)` with `last-list.json`; a missing file means a
       baseline.
    4. Append exactly one line for the result. A thrown error becomes a `failed` line carrying
       the error's description, and so does a `failed` diff result (S0's empty-feed rule),
       which carries its `error`.
    5. Write `last-list.json` from `currentList`, **except after any `failed` line**, which
       leaves the saved list untouched (the S0 contract on `ListeningDiffResult`).
    6. Return.
    If the iCloud folder can't be written (iCloud Drive off), log through `os.Logger` and exit
    non-zero. The window shows this state.
  - **Window** (opened by launching the app normally), one screen:
    - Apple Music authorization status, with an **Authorize** button
      (`MusicAuthorization.request()`);
    - **Poll every hour on this Mac** (a toggle). If `SMAppService` reports
      `.requiresApproval`, the screen says so, with a button that opens Login Items
      (`SMAppService.openSystemSettingsLoginItems()`);
    - the last fetch's time and outcome, and plays logged today;
    - the iCloud folder path, and whether this Mac holds the lease.
  - **Headless run:** the toggle registers a login agent through
    `SMAppService.agent(plistName:)`.
    - The plist ships in `Contents/Library/LaunchAgents/`, and its label is the bundle ID plus
      `.agent`.
    - Its `BundleProgram` is the app's executable, and `ProgramArguments` passes `--poll`.
    - `StartInterval` is 3600, with `RunAtLoad` true, so turning the toggle on polls at once
      (the baseline).
    - The agent never opens a window and never prompts.
  - **Docs:** `docs/listening/POLLER-SETUP.md`:
    - build with `scripts/build-listening-poller` on the laptop and copy the app to the mini's
      `/Applications`;
    - the first launch and the Authorize prompt;
    - turn on the toggle, and approve it in Login Items if asked;
    - confirm the first line appears on the laptop;
    - keep the mini logged in and awake, with Optimize Mac Storage off.

  **DoD:**
  - Model tests for `pollOnce()` with stubbed clients and a temporary folder:
    - a first run claims the lease and writes one `baseline` line;
    - a later run writes exactly one line and replaces `last-list.json`;
    - a non-leaseholder writes nothing to iCloud;
    - missing authorization writes `failed` and makes no request;
    - a thrown fetch error and an empty-feed result each write `failed` and leave
      `last-list.json` unchanged;
    - the stream file is named for the UTC month (a fetch at 2026-10-31T23:30-05:00 lands in
      `2026-11.jsonl`).
  - The built app has both slices, checked in the PR: paste `scripts/build-listening-poller`'s
    output, where every Mach-O in `Contents/MacOS` lists `x86_64 arm64`.
  - The live MusicKit call and `SMAppService` registration are **unverified** in the PR.
  - **Owed device gate (on the mini, over about 24 h):**
    - Launch, Authorize, and turn the toggle on. The first line, `baseline`, appears in iCloud
      Drive on the laptop. Its `pagesRead` is the merged list's depth: note it.
    - Play three songs on the iPhone, one in Marvis and one skipped after about 10 s. Within
      about an hour, a `plays` line lists them. Note whether the Marvis play and the skipped
      play count.
    - After 24 h, the agent has written about 24 lines with no gaps. Note the largest
      `pagesRead` on any later line; it's usually 1, since the diff stops once it finds the
      overlap.
    - **If the agent doesn't run headless on the mini, or MusicKit refuses it there, stop and
      flag it** rather than working around it.
  - **Gate result (2026-10-20 → 21):**
    - The agent ran headless and MusicKit authorized it. The first line was a `failed` HTTP 401;
      the baseline followed 12 minutes later, which fits the setup guide's re-toggle fix.
    - The baseline read 171 items (6 pages). The plays, Marvis, and skip checks passed on
      2026-10-20 (see the format section's *Fidelity*).
    - Over 26 hours: 26 hourly lines with no gaps (7 `plays`, 19 `none`), and every line after
      the baseline read 1 page.

- [x] **S2 — Listening in `vf-mcp` and Settings (core + app).** Device gate owed.
  - Implement the tool surface above in `LibraryMCPServer`. The log is read lazily and reloaded
    when any stream file's `modifiedAt` changes, like the snapshot. Reads are coordinated
    (`NSFileCoordinator`), so a stream file iCloud has offloaded downloads first.
  - The log-backed calls join `LibraryIndex.checkTracks` for "in library".
  - **Settings → Listening History:** which Mac polls; the last fetch and its age; coverage
    since; gaps in the last 30 days; the iCloud folder; and a link to `POLLER-SETUP.md`. With
    no log, it shows the setup pointer.
  - Update `docs/chatgpt/MCP-SETUP.md` (the tool list) and the `~/music-chat` template ("ask
    `recent_listening` before claiming what Jon's into lately").

  **DoD:**
  - Tool tests through `MCPServer.handle(line:)` against a fixture log:
    - each period;
    - `coverage` with a gap;
    - `by: favorites` with `period: 7d` gives `isError`;
    - no log gives the setup error;
    - no IDs in any output.
  - `tools/list` pins the new property names and enums.
  - A model test for the Settings status line.
  - **Device gate:** ChatGPT on the iPad answers "what have I been listening to this week?" and
    Jon agrees it's right.

- [x] **S3 — The same poller inside Vinyl Fever (app; Apple silicon, macOS 27).** Implementation complete; the laptop↔mini device gate passed 2026-10-22, and it measured
  a real handover hole (see below).
  - `VinylFever --poll-listening` runs the S1 headless path. A small custom entry point checks
    the argument before starting the SwiftUI app.
  - The app bundles its own agent plist and registers it with `SMAppService`, as in S1. It uses
    the existing **Vinyl Fever Dev Profile**, which already has MusicKit.
  - **Settings → Listening History** gains **Poll listening on this Mac**. Turning it on while
    another Mac holds the lease asks first ("The Mac mini is polling now. Make this Mac the
    poller?"), then writes the lease and registers the agent. Turning it off unregisters the
    agent; the lease stays until another Mac takes it.
  - The poller app gains the same takeover toggle, so the mini can take the lease back.
  - A new leaseholder's first fetch is a `baseline` in its own stream, so a takeover never
    double-counts.

  **DoD:**
  - Model tests: takeover writes the lease and its first fetch is a baseline; the previous
    holder's next run writes nothing; turning off keeps the lease.
  - **Device gate:** take over from the laptop for a few hours, then hand back from the mini.
    `recent_listening` shows continuous coverage across both handovers, with no duplicate
    plays. Note how long each handover's hole was (`open-questions.md`, *Listening handover
    hole*).
  - **Gate result (2026-10-22; times ET):**
    - **Mini → laptop.** The mini's last fetch was 10:35 am. The laptop took over and fetched its
      `baseline` at 11:15 am (173 items, 6 pages), then `none` at 12:15 pm. Hole: 40 minutes.
      Jon was playing (and skipping) through it, so 19 plays sat above the mini's last-seen
      song, and the baseline absorbed all of them. Seven were songs the log had never seen.
    - **Laptop → mini.** The mini took the lease back at 12:43 pm but didn't fetch until its next
      hourly run, a `baseline` at 1:35 pm. Hole: 80 minutes, from the laptop's last fetch. No
      plays were lost: the mini's baseline started with the same song as the laptop's.
    - `recent_listening` afterward: polling Mac "Jon’s Mac mini (2)", `gaps` empty, no duplicate
      plays, and the newest play is the mini's 10:35 am one. Coverage reads continuous, as the DoD
      asks, but that's the problem: it hides the 19 lost plays.
    - The previous holder wrote nothing while it didn't hold the lease, in both directions.

- [x] **S4 — Handover recovery (`VinylFeverListening` + both apps).** *Added 2026-10-22 from the
  S3 gate.* Today a takeover clears the new holder's last list, so its first fetch is a
  `baseline` that absorbs every play since the old holder's last fetch. Nothing reports the loss.
  The mini → laptop handover lost 19 plays that way. Also, a takeover on a Mac whose agent is
  already registered (the mini's poller app) waits for the next hourly run, so the hole stretched
  to 80 minutes. S4 recovers those plays and shortens the wait. It stays at macOS 15, like the
  rest of the package (Decision 2).
  - **Remember who held the lease.** `ListeningLeaseRules.takeOver` still clears `last-list.json`.
    It also saves the previous lease's `poller` locally, next to it, as a one-time handover
    marker. The marker is local state, never synced.
  - **Diff against the old holder's newest list.** On the first fetch after a takeover, read the
    previous holder's stream (`fetches/<old poller>/`, the current month, then the one before).
    Take its newest line that carries `items` (`baseline`, `plays`, or `gap`). Those items are
    the head of the old holder's list when it last fetched: the full list for a `baseline`, and
    the new plays plus up to 10 items of overlap evidence for `plays`. Run the existing
    `ListeningDiff` with that head as `P`. Comparing over up to 10 items is all the diff needs.
    - Overlap found: write a `plays` line (or `none` when `k == 0`) carrying
      `"since":{"poller":"<old uuid>","fetchedAt":"<that line's fetchedAt>"}`. Its plays are
      dated to the window (`since.fetchedAt`, `fetchedAt`].
    - No overlap within the page cap: a `gap` line with `since`, as for any other `gap`.
    - No usable old line (no stream, unreadable, or no `items` line in two months): a `baseline`,
      as today. `coverage` reports the window from the old holder's last fetch to this baseline
      as a gap, so the loss is loud.
    - Either way, the full list fetched becomes the new `last-list.json`, and the marker is
      deleted.
    - If iCloud hasn't synced the old holder's newest line yet, the diff starts from an older
      one. Its window then overlaps the old holder's, and the reader's existing collapse rule
      counts those plays once.
  - **Format:** `since` is new. A line that carries it has `"version":2`; every other line stays
    at 1, so an older reader keeps working until a handover happens. Readers accept 1 and 2.
    Update the format section above in the same PR.
  - **Fetch right after a takeover.** Both takeover paths (Vinyl Fever's Settings toggle and
    the poller app's) run one poll right after writing the lease, rather than waiting for the
    agent's next run. The executor chooses how: the in-process `pollOnce()` or a
    `launchctl kickstart` of the agent.

  **DoD:**
  - Model tests, with fixtures shaped like the 2026-10-22 gate but using synthetic songs:
    - an 11-item `plays` head (1 new + 10 evidence) and a 173-item current list, with 19 songs
      above the old head, 12 of them replays from deeper in the list → 19 plays, dated from the
      old line's `fetchedAt`;
    - an old `baseline` head equal to the current list → `none` with `since`;
    - the old holder's newest line is `none` → walk back to its last `items` line;
    - no old stream → `baseline` and a reported gap;
    - a stale old head (the newest old line not yet synced) → the overlap collapses and nothing
      counts twice;
    - the marker is used once and cleared; a v2 line round-trips; a version 3 line is still rejected loudly.
  - A takeover test shows a poll runs right after the lease is written, in both apps' models.
  - Replaying the diff against the real 2026-10-22 streams gave 19 and then 0 (architect,
    2026-10-22). The executor reruns that against Jon's log, read-only, and reports the counts.
  - **Device gate (Jon):** install Vinyl Fever first, then rebuild the poller with
    `scripts/build-listening-poller` and copy it to the mini, so the reader understands v2
    before the mini writes it. Then take over on the laptop with a few songs played since the
    mini's last fetch, and hand back with a few more. On both Macs, a fetch line appears within a
    minute of the toggle. `recent_listening` shows every song played in both holes, dated to the
    handover window, with no duplicates and no gap.
  - **Gate, first half (2026-10-22; times ET).** Merged as #119.
    - **Mini → laptop.** Jon installed the merged app at 6:42 pm and took over at 6:43:40 pm.
      The laptop's first fetch landed 0.2 s later. It was `none`, `version` 2, with `since` at the
      mini's 5:35 pm `plays` line. It walked back past the mini's 6:35 pm `none` correctly. No
      plays were in this hole. `recent_listening` showed the mini's 33 Discover Station plays from
      4:35–5:35 pm once each, with no gaps.
    - **A defect, found before the handback.** At that point the laptop's only line in its own
      tenure was that `none`, which carries no `items`. So the mini's handback would have walked
      back past it, to the laptop's 11:15 am `baseline` from its *previous* tenure. Replaying the
      merged poller on copies of Jon's streams, with 4 songs played after the switch, gave
      `plays` with `newCount` 37. That's the 4 new songs plus all 33 Discover Station plays again.
      The mini had already logged those 33, and the reader only collapses across pollers, so the
      log would have counted 66. Fixed in S5.
    - The architect kickstarted the laptop's agent at 7:27 pm. It logged Jon's 4 Tom Petty plays
      as an ordinary `plays` line. That gives the laptop an `items` line in its own tenure.
      **Device gate folded into S5's.**

- [x] **S5 — Recover from the right list, and Poll now (`VinylFeverListening` + both apps).**
  *Added 2026-10-22 from the S4 gate.* S4 takes `P` from the old holder's newest line that
  carries `items`. That's only right if the line is in the old holder's *current* tenure. A
  recovery that came out `none` writes no `items`. So does a holder that never fetched
  successfully before handing back. In both cases the walk crosses into an older tenure, and
  the recovery recounts plays that another line already logged.
  - **Resolve the last known list.** On the first successful fetch after a takeover (the marker
    is unchanged from S4):
    1. Take the newest non-`failed` line in **any** stream, current month and the one before.
       Normally that's the old holder's. One Mac holds the lease at a time, so that line is the
       newest known state of the feed. Its `poller` and `fetchedAt` become `since`.
    2. Walk back through that line's stream, starting at the line itself:
       - a line with `items` gives `P`;
       - a line with `since` and no `items` (a recovery that came out `none`) continues the walk
         in `fetches/<since.poller>/`, at `since.fetchedAt`;
       - `none` without `since`, and `failed`, are skipped.

       A tenure always starts with a `baseline` or a line carrying `since`, so the walk never
       crosses into an older tenure. Follow at most 4 hops.
    3. No `P` (no lines at all, a missing or unreadable target, or more than 4 hops) gives a
       `baseline` with `since`, as in S4. Its gap starts at `since.fetchedAt`. When there are no
       lines at all, it starts at the marker's `fallbackSince`.
    - So `since.fetchedAt` is now the old holder's **newest successful fetch**, not the time of
      its `items` line. Trailing `none` lines mean the list didn't change. The tighter window
      also stops a replay just after a handover from colliding with the old holder's earlier
      window. The format is unchanged: same fields, still `version` 2. Update S4's bullet and the
      format section to say what `since` means now.
  - **Reader guard.** Two plays of the same song collapse when they come from **different lines**
    and their windows **strictly overlap**: one starts before the other ends. That applies
    whatever the poller. Windows that only touch, like a stream's consecutive fetches, don't
    collapse. A collapsed play doesn't extend the overlap window for later comparisons. That
    keeps a song replayed in back-to-back windows at two plays. This catches any future same-Mac
    overlap, such as a recovery window or a stray double poll, and today's log has none to repair.
    Update *Reading the log* above.
  - **Poll now** (Jon, 2026-10-22). It's a button in Settings → Listening History in Vinyl Fever,
    and in the poller app, shown when this Mac holds the lease and its agent is enabled.
    - It kickstarts the agent with the existing `ListeningLaunchAgentKickstarter`, never an
      in-process `pollOnce()`. launchd won't start a second copy of a running job. The
      architect probed this on 2026-10-22: `kickstart` without `-k` exits 0 and starts nothing
      new while the job runs. So Poll now can't race the hourly run or a takeover's kickstart.
    - After the kickstart, refresh the status line when a new fetch line appears, or after 30
      seconds, whichever is first.
    - A kickstart failure goes to the existing error line.

  **DoD:**
  - Poller tests, with synthetic songs shaped like the 2026-10-22 gate:
    - **Tonight's shape:** the old stream has an 11-item `plays` line, then `none`. The new
      holder takes over, and its recovery is `none` with `since`. The first Mac takes back with
      4 songs played since. That gives `plays` with `newCount` 4. `since` is the `none` recovery
      line, and `ListeningLog` counts the old plays once.
    - The old holder never fetched in its tenure. `P` comes from the newest line overall, here
      the new holder's own pre-takeover line, and nothing counts twice.
    - A two-hop chain of `none` recoveries resolves to the right `P`. A missing target gives a
      `baseline` and a gap that starts at `since.fetchedAt`.
    - `since.fetchedAt` is the old holder's newest successful line when its `items` line is
      older (the mini → laptop shape: `plays`, then `none`).
  - Reader tests:
    - two lines from one poller with strictly overlapping windows count a song once and report
      it as collapsed;
    - a song in two consecutive windows of one stream still counts twice;
    - the existing collapse tests pass unchanged. If one relied on touching windows collapsing,
      the PR says so.
  - A Vinyl Fever model test: Poll now shows only while this Mac holds the lease, and calls
    `kickstart` once per press. The poller app's button is checked at the device gate, since that
    app has no test target.
  - Replay, read-only, against Jon's streams cut off before the laptop's 7:27 pm `plays` line
    (23:27:29Z): a mini takeover with 4 synthetic songs above the laptop's list gives 4 plays,
    and the 33 Discover Station plays count once. The PR reports the counts.
  - **Device gate (Jon):** install Vinyl Fever, then rebuild and copy the poller to the mini.
    1. Take over on the laptop with nothing played, so the recovery is `none`.
    2. Play 2–3 songs, then hand back to the mini.
    3. The mini's first fetch is `plays` with just those songs, and `recent_listening` shows no
       duplicates.
    4. Press **Poll now** on each Mac while it holds the lease. A fetch line appears within a
       minute.
  - **Gate result (2026-10-22, evening; times ET). Passed** on the merged #121 build: Vinyl
    Fever installed at 8:42 pm, and the poller rebuilt and copied to the mini.
    - **Laptop → mini, nothing played.** The mini took over at 8:51:38 pm and fetched 65 ms later:
      `none`, `version` 2, with `since` at the laptop's 7:27 pm `plays` line.
    - **Mini → laptop, nothing played.** The laptop took over at 8:52:53 pm and fetched 0.3 s
      later: `none`, with `since` at the mini's 8:52:37 pm Poll now line.
    - **Poll now on the laptop.** Two presses: `none` at 8:54:14 pm, then `plays` with exactly
      the 3 songs Jon had just played, at 8:57:25 pm.
    - **Laptop → mini, with 2 songs played after the laptop's last fetch.** The mini took over at
      8:59:52 pm. Its first fetch was `plays`, `newCount` 2, with exactly those 2 songs and
      `since` at the laptop's 8:57:25 pm line. This is S5's case: the laptop's tenure started
      with a `none` recovery.
    - **Poll now on the mini** wrote a fetch line at 8:52:37 pm.
    - `recent_listening` afterward showed 55 plays in 24 h, no gaps, no repeated songs, 0
      collapsed, and the mini as the polling Mac. Every Tom Petty play landed once, in its own
      window.
    - **Found at the gate, and dispatched as an effort**
      ([listening-settings-refresh](../efforts/listening-settings-refresh.md)):
      - Vinyl Fever's Settings kept saying "This Mac holds the lease" after the mini took over,
        even after closing and reopening Settings.
      - The laptop's hourly run at 8:27 pm (still the S4 build) failed with "The file couldn't be
        saved." It wrote no fetch line.

## Prerequisites (Jon, not the executor's)

**Before Dispatch 2 (done 2026-10-18):**

- [x] **Developer portal:** the App ID `com.jonphillips.vinylfever.listeningpoller` with the
  **MusicKit** App Service, and the development profile **VF Listening Poller Dev Profile**
  covering the laptop. It's installed on the laptop, which is also Codex's build host. A
  throwaway app signed with it built and verified, which proves the profile, not MusicKit.
- [x] Xcode 27 can build the poller universal for **macOS 15**. Checked 2026-10-19: the PR 85
  app, with its target set to 15.0, built with no availability errors, and every slice of every
  Mach-O reports `minos 15.0`. The `VinylFeverListening` sources also compile at macOS 15 on
  their own. Running it is the S1 gate, since this Mac has no Rosetta.

**Before the S1 gate (Jon; the dispatch doesn't wait for these):**

- [ ] **The mini:**
  - Intel Mac mini (2018) on **macOS 15 Sequoia**, the last release it supports. macOS Tahoe 26
    needs a 2020 or later Mac mini (Apple silicon). Confirm the version.
  - Signed in to Jon's Apple ID with Apple Music and iCloud Drive on.
  - Set to stay awake and stay logged in. A login agent needs a user session; the mini's
    "always-on" role covers this.
  - **Optimize Mac Storage off** (System Settings → Apple Account → iCloud → Drive), so iCloud
    never offloads the stream files the poller appends to.
- [ ] **Add the mini to the profile:**
  - Register the mini as a device (System Information → Hardware → Provisioning UDID).
  - Edit **VF Listening Poller Dev Profile** to include it, download it again, and install it
    on the laptop by opening the file. A downloaded profile isn't installed until it's opened;
    it then lands in `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`.
  - Rebuild with `scripts/build-listening-poller`. The app embeds the profile, so a build made
    before the mini was added won't launch there.

## Constants register (starting values)

| Constant | Value | Rationale |
| --- | --- | --- |
| Poll interval | 60 min | "Lately" questions need day-level precision, not minutes. Shorter intervals multiply heartbeats for little gain. |
| Page size | 30 | The API's maximum. |
| Page cap per fetch | 10 (300 items) | Hourly listening never gets near this; past it is a `gap`. Revisit after the S1 gate measures depth. |
| Overlap evidence | 10 items | Enough to match reliably, and it keeps lines small. |
| Log format | `vf-listening-fetch` v1, monthly JSONL per poller | Append-only; versioned like the snapshot. |
| Periods | `24h`, `7d`, `30d`, `90d` | `all_time` stays library play counts. |
| Tool caps | M12's: 50 default, 200 max | Same rules. |

## Out of scope — with destinations

- **History before polling starts.** The feed has none. → Never.
- **Last.fm.** → Dropped (M12 Decision 1).
- **Heavy rotation** (2 items in the probe). → No.
- **Writing listening back into Music.app** (play counts, ratings). → No: propose, never write.
- **Listening badges in the playlist preview** ("4 plays this month"). → A candidate after the
  S2 gate, if the chat answers prove useful.
- **An iPhone or iPad poller.** → No; a Mac polls.
- **Server-side polling.** → Never: no server (house rule).

## Decisions

Open — the architect's recommendation is listed first. Merging this plan approves the
recommendations and dispatches S0.

1. **Keep the log as files in iCloud Drive rather than SQLiteData + CloudKit.** The house
   default is SQLiteData with CloudKit sync, so here's the argument for files:
   - The writer is a headless agent, and the reader is `vf-mcp`, a command-line helper that
     runs while no app is open. A CloudKit sync engine needs a running app on both ends, so
     the helper would see stale data until Vinyl Fever was launched. iCloud Drive syncs files
     without either app running.
   - The log is append-only, single-writer per stream, and keeps the raw evidence, so a JSONL
     file is the simplest correct form.
   - This is still iCloud, with no server.
   - Unlike the M12 snapshot, the log is **not** derived; it's the only copy of the history.
     iCloud Drive keeps the cloud copy. (This said the laptop's Time Machine backs it up, but
     Time Machine last finished on 2026-02-15. Daily backups are [M19](M19-backups.md).)
2. **Hold the poller app and `VinylFeverListening` at macOS 15, in a package of their own.**
   - **Why there's an exception:** the house rule is the newest OS, with exceptions only for a
     named device (jon-platform `toolchain.md`). The named device is the Intel Mac mini (2018).
   - **Why macOS 15:** its last macOS is 15 Sequoia. macOS Tahoe 26 supports only the 2020 and
     later Mac mini.
   - **Corrected 2026-10-19:** this decision first said macOS 26, and Jon caught it while
     preparing the mini.
   - **Why a separate package:**
     - `VinylFeverCore` can't drop to 15, because the jon-platform packages it uses require
       macOS 26.
     - Holding Core back would constrain the main app anyway.
     - The hold now covers only the listening engine and the poller app. Core and the main app
       keep their floors.
   - **When it lifts:** when an Apple-silicon Mac takes the lease for good (S3 makes that a
     toggle). The poller app is then deleted, and `VinylFeverListening` can move up with the
     rest.
3. **Build Vinyl Fever's own poller now (S3) rather than when the mini is replaced.** Jon leans
   yes (2026-10-18). It doubles as the laptop's backup poller when the mini is down, and it
   proves the takeover before it matters. It's last, so it doesn't delay S1–S2.
4. **Hourly windows; repeats within an hour count once.** That's enough for "lately". Going
   finer means polling more often, which only raises the heartbeat count.
5. **`all_time` stays the Mac library's play counts, labelled as such.** The log only starts
   at the S1 gate, so it can't answer all-time questions. Once the log has a year in it,
   revisit making `all_time` log-backed.
