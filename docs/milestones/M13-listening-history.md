# Milestone 13 — Listening History (Apple's recently-played feed)

*Record what Jon actually listens to on every device, and let the chat ask about it. Rules in
[../technical-architecture.md](../technical-architecture.md), `/Users/jon/code/jon-platform/AGENTS.md`,
and jon-platform [ADR-0007](/Users/jon/code/jon-platform/docs/adr/0007-app-data-over-local-mcp.md)
apply. Where this doc and those conflict, stop and flag it.*

Summary: a small **poller** asks Apple Music, once an hour, which songs Jon played recently. Apple
gives no timestamps and lists each song only once, so the poller compares each answer with the
previous one, works out what was played in between, and appends that to a **listening log** in
iCloud Drive. The poller runs on Jon's always-on **Intel Mac mini** as a separate small app,
because the main app targets macOS 27 and the mini stops at macOS 26. Vinyl Fever can run the
**same poller code** itself, for the laptop as a backup today and for an Apple-silicon mini
later; a lease makes sure only one Mac polls at a time. `vf-mcp` reads the log, so ChatGPT,
Claude Code, and Codex can answer "what have I been into lately?". Four slices in four dispatches.
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
- **One poller engine, two hosts.** The mini is Intel and can't run macOS 27. A separate
  poller app targeting macOS 26 runs there now. The same Core engine also runs inside Vinyl
  Fever (S3), so moving to an Apple-silicon mini later is a Settings toggle, not a rewrite. The
  poller app is then retired.

## Evidence (probe, 2026-10-17)

- `GET /v1/me/recent/played/tracks?types=songs,library-songs` returns one merged,
  newest-first list of catalog songs and library songs (including uploaded ones), from every
  device. The default (`songs` only) hides library plays, which were most of Jon's listening.
- Each request returns at most 30 items, paged with `offset`. The songs-only list ran out at 74
  items; the merged list's depth is **unmeasured**.
- There are no timestamps. The list is de-duplicated: a song appears once, at its most recent
  play.
- The probe was a signed build of the app, run the way a login agent would run it, and MusicKit
  authorized it.

## The spine

```
Intel Mac mini (macOS 26)                             laptop (macOS 27)
  VF Listening Poller.app, hourly login agent           vf-mcp (in VinylFever.app)
    MusicDataRequest: recent/played/tracks ─┐             ListeningLog.read → plays
    ListeningDiff (Core, pure) ◀── last list (local)      tools: recent_listening,
    append ──▶ iCloud Drive/Vinyl Fever/Listening/ ──sync──▶ top_* period
                 fetches/<poller>/<YYYY-MM>.jsonl        Settings → Listening History (status)
                 lease.json  (which Mac polls)
                                 ▲
  VinylFever.app --poll-listening (S3; the laptop now, an Apple-silicon mini later)
```

## Listening log (format v1)

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
- **Versioning:** the reader rejects a newer `version` loudly, like the snapshot. It ignores a
  trailing partial line, since iCloud may sync a file mid-append.
- **What's in the log:** song identity and text only. No library file locations, no account
  data, and no Apple Music user token.
- **Fidelity** (jon-platform `semantic-fidelity.md`):
  - feed → log is **lossless** for what the feed says: the new prefix and its evidence are kept
    as fetched.
  - log → plays is **intentionally lossy**: plays are dated to their hour window, and repeats
    inside one window count once.
  - Gaps and failures are **loud**: every tool result reports its coverage and gaps.
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

**Reading the log (S2):**
- Each `plays` line gives `newCount` plays, dated to the window (previous successful fetch,
  this fetch].
- Songs are keyed by `SongTextNormalizer` artist + title, the same key as `check_tracks`, so a
  catalog play and a library play of the same song count together.
- Streams from different pollers are merged by time. If two streams' windows overlap (a lease
  race), plays of the same song in overlapping windows count once, and the result says how
  many were collapsed.

## Tool surface (S2, added to `vf-mcp`)

The M12 rules still apply: compact JSON, no file paths and no IDs, results capped, read-only
tools.

| Tool | Input | Returns |
| --- | --- | --- |
| `recent_listening` | `period` (`24h` \| `7d` \| `30d` \| `90d`), `limit` | plays, newest first: artist, title, album, window start and end, in library (yes/no); plus `coverage` |
| `top_artists`, `top_tracks` | new `period`: `all_time` (default) \| `7d` \| `30d` \| `90d` | `all_time` keeps today's library play counts. Other periods count plays in the log, and only `by: plays` is allowed with them (anything else gives `isError`). |

- **`coverage`** goes on every log-backed result: the log's first fetch, the last fetch and its
  age, which Mac polls, and the gaps in the period.
- **Descriptions** say plainly that `all_time` is Mac library counts, which miss device
  plays, and that periods come from the listening log since the date polling started.
- The instructions head is already at 500 of its 512 characters, so tool descriptions carry
  this. The head is unchanged.
- **No log yet:** log-backed calls return `isError` with "Listening history isn't set up yet.
  See Vinyl Fever → Settings → Listening History."

## Slices

**Dispatch 1: S0** (pure Core, no prerequisites). **Dispatch 2: S1**, after Jon's
prerequisites. It owes a gate on the mini. **Dispatch 3: S2.** **Dispatch 4: S3.** The log
starts filling at the S1 gate, so S2 has real data by the time it lands.
[M14](M14-live-tracks-in-playlists.md) (live tracks in playlists) runs between S2 and S3 (M14
Decision 3).

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

- [ ] **S1 — VF Listening Poller app (macOS 26, universal; runs on the Intel mini).** Device
  gate owed.
  - **The run-once poll lives in `VinylFeverListening`**, as `ListeningPoller.pollOnce()`, so S3
    calls the same code. It's a dependency-backed model over four clients:
    - `recentlyPlayedClient` (S0);
    - an authorization client reading `MusicAuthorization.currentStatus`, which never prompts;
    - a `ListeningStore` client for the iCloud folder and local state (below);
    - `date`.
  - **A new app target, `VinylFeverListeningPoller`** (product **VF Listening Poller**, bundle
    `com.jonphillips.vinylfever.listeningpoller`), is added in `project.yml`.
    - Deployment target **macOS 26.0**.
    - `ARCHS` is the standard architectures, and **`ONLY_ACTIVE_ARCH: NO` in every
      configuration**: Debug otherwise builds arm64 only, and the mini needs x86_64.
    - It depends only on the `VinylFeverListening` product.
    - Hardened runtime on, no App Sandbox. The Info.plist has `NSAppleMusicUsageDescription`.
    - It signs manually with the **VF Listening Poller Dev Profile** (explicit App ID with the
      MusicKit App Service; see *Prerequisites*), the #69 pattern. Copy the `VinylFever`
      target's signing block and its comment.
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
    - build on the laptop and copy the app to the mini's `/Applications`;
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
  - The built app has both slices, checked in the PR: `lipo -archs` on its executable prints
    `x86_64 arm64`, from a Debug build.
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

- [ ] **S2 — Listening in `vf-mcp` and Settings (core + app).**
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

- [ ] **S3 — The same poller inside Vinyl Fever (app; Apple silicon, macOS 27).**
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
    plays.

## Prerequisites (Jon, not the executor's)

- [ ] **The mini:**
  - Intel Mac mini (2018) on **macOS 26 Tahoe**, the last Intel release. Confirm the version.
  - Signed in to Jon's Apple ID with Apple Music and iCloud Drive on.
  - Set to stay awake and stay logged in. A login agent needs a user session; the mini's
    "always-on" role covers this.
  - **Optimize Mac Storage off** (System Settings → Apple Account → iCloud → Drive), so iCloud
    never offloads the stream files the poller appends to.
- [ ] **Developer portal, before Dispatch 2:**
  - Register the mini as a device (System Information → Hardware → Provisioning UDID).
  - Create the App ID `com.jonphillips.vinylfever.listeningpoller` with the **MusicKit** App
    Service.
  - Create the development profile **VF Listening Poller Dev Profile** for that App ID,
    covering the laptop and the mini, and install it on the laptop (and on Codex's build host).
- [x] Xcode 27 can build an x86_64 MusicKit binary targeting macOS 26 (checked 2026-10-18 with
  `swiftc -target x86_64-apple-macos26.0`). Running it is the S1 gate, since this Mac has no
  Rosetta.

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
     iCloud Drive keeps the cloud copy, and the laptop's Time Machine backs it up.
2. **Hold the poller app (and `VinylFeverListening`) at macOS 26.** The house rule is the
   newest OS, with exceptions only for a named device (jon-platform `toolchain.md`). The named
   device is the Intel Mac mini (2018), which can't run macOS 27. The hold is lifted, and the
   poller app deleted, when an Apple-silicon Mac takes the lease for good (S3 makes that a
   toggle). The `VinylFeverCore` package is already at macOS 26, so nothing moves.
3. **Build Vinyl Fever's own poller now (S3) rather than when the mini is replaced.** Jon leans
   yes (2026-10-18). It doubles as the laptop's backup poller when the mini is down, and it
   proves the takeover before it matters. It's last, so it doesn't delay S1–S2.
4. **Hourly windows; repeats within an hour count once.** That's enough for "lately". Going
   finer means polling more often, which only raises the heartbeat count.
5. **`all_time` stays the Mac library's play counts, labelled as such.** The log only starts
   at the S1 gate, so it can't answer all-time questions. Once the log has a year in it,
   revisit making `all_time` log-backed.
