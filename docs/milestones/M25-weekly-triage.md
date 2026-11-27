# Milestone 25 — Weekly triage on the phone

*Staged playlists create themselves on the mini, and the phone gains two standing playlists: New
Music Weekly, which holds Apple's New Music plus five songs the chat adds, and Playlist Catchup,
which holds the unheard songs from Apple editorial playlists Jon follows. Rules in
[../technical-architecture.md](../technical-architecture.md), jon-platform `AGENTS.md`, and
jon-platform `docs/ios/ui-and-platforms.md` (§ Controls) apply. Where this doc and those conflict,
stop and flag it.*

*Amended 2026-11-27, after PR #214 asked where the helper runs: "the listening helper" is Vinyl
Fever's own windowless `--poll-listening` run on the M6 mini, not the retired VF Listening Poller
app. S1 gains the rule that a `created` or `dismissed` line outranks `needs-review`, a playlist-level
`error` field, and a library-name check before creating.*

Status: Designed
Summary: S1 has the mini's listening helper create every staged playlist whose songs all match, and S2 alerts Jon by iMessage when one doesn't; S3 saves the contents of playlists labeled `tracked` and S4 shows their unheard songs on the phone as Playlist Catchup; S5 gives the chat one tool for a New Music week (hidden picks, optional notes, and five extras) that a Codex automation on the mini calls every Friday, and S6 shows the result on the phone as New Music Weekly.

Jon asked for this on 2026-11-27. Vinyl Fever mobile is becoming his music triage app:
1. Every Friday, ChatGPT predicts which New Music songs he'll keep and suggests five more that
   Apple didn't pick. He sees New Music with the chat's commentary and the five extras in the
   mobile app, as one playlist.
2. Apple editorial playlists he follows (Antidote, ALT-CTRL, Breaking Alternative, Pop Deluxe,
   and AltPop), with only the songs he hasn't heard, in one list that names each song's source.
3. A playlist staged in the Mac app is processed automatically: if every song is found, it goes
   straight to Apple Music. Otherwise he gets an alert.

## The milestone in one sentence

On Friday, Jon opens Vinyl Fever on his phone and finds New Music Weekly, with Apple's 25 songs,
whatever the chat had to say about them, and the chat's five extras, already in Music. Below it is
Playlist Catchup, with every song from his five editorial lists that he hasn't heard yet. Any
playlist the chat stages reaches Music without him, unless a song needs his choice, and then
his phone tells him.

## What's true today (architect, read-only, 2026-11-27)

- **The mini is the chat host and the listening host** (#207). `vf-mcp` runs there through the
  tunnel, so the playlist inbox (`~/Library/Application Support/VinylFever/PlaylistInbox`) fills
  on the mini. The listening helper runs there hourly: `VinylFeverListeningAgent.plist`
  (`StartInterval`), registered from Settings → Listening History, starts Vinyl Fever with
  `--poll-listening` (`VinylFeverApp.swift`), which polls once and exits with no window. In this
  doc, "the helper" means that run. It's the macOS 27 app, so it links `VinylFeverCore` and
  `VinylFeverAppleMusic`. The separate VF Listening Poller app (`VinylFeverListeningPoller`, macOS
  15) was for the Intel mini, which is retired (#207). It gets no M25 work and keeps its target.
- **The helper can already read and write Apple Music.** It reads recently played, and it saves
  New Music (`NewMusicExposure.swift`). It finds New Music's catalog ID through the library
  playlists relationship, caches it, and fetches the catalog playlist. Any followed catalog
  playlist can be found the same way.
- **Creating a playlist is shared code since M24.** `CatalogMatchResolver` and the live client
  are in `VinylFeverAppleMusic` / `VinylFeverAppleMusicLive`. The stage tool records the upload
  route per track (M24 S3), and the aliases are mirrored to iCloud. So creating a playlist needs
  neither the library snapshot nor the Mac app. The phone already does it (M24 S5).
- **Every creator writes one log.** `vf-playlist-creation` (`PlaylistCreations.swift`) has
  `created` and `dismissed` lines. The Mac files its inbox from that log, and labels the playlist
  `vinyl-fever` from the ledger at its next snapshot.
- **New Music picks are recorded blind.** `record_new_music_picks` checks every song against the
  latest saved week, and a week keeps its first picks (`recorded: false` after that). The phone
  doesn't list picks (M21 Decision 4).
- **Playlist roles are in iCloud** (`Taste Intelligence/playlist-roles.json`), keyed by persistent
  ID and name. `PlaylistRole` is a `String` enum with eleven cases. `followed` means following the
  playlist is the signal and its tracks aren't.
- **The mini doesn't have its Messages Apple ID yet.** ADR-0010 D3's sender (an Apple ID only for
  the mini, signed in to Messages and nothing else) is held setup for the TestFlight renewal, and
  Jon will make it soon. Messages to his own Apple ID wouldn't alert his phone.
- **Codex runs inside the ChatGPT app** on Jon's Macs, with `vinyl-fever` in
  `~/.codex/config.toml` pointing at the installed `vf-mcp`. There's no `codex` on the laptop's
  `PATH`. The architect hasn't verified whether a Codex automation can call MCP write tools
  without someone there to approve them. That's the Decision 3 gate.

## Shared rules (every slice)

- **Vinyl Fever stays deterministic.** No model calls in the app, the helper, or `vf-mcp`. The
  model work is the chat's, through `vf-mcp`, whether Jon or the Friday automation is asking
  (Decision 3).
- **The chat chooses; the apps only build** (M24 Decision 11). Auto-create matches songs and never
  curates.
- **New logs follow the notes pattern:** append-only JSON lines in the iCloud `Taste Intelligence`
  folder, one file per writer (`<device-or-host>.jsonl`), with `format` and `version` on every
  line. Readers skip and count lines they can't read, and never rewrite a file. Appends go through
  the shared JSONL append from `evicted-icloud-writes`.
- **Older readers keep working.** Every new field is optional. A new `PlaylistRole` case must not
  make an older build fail to read `playlist-roles.json`. If today's decoder throws on an unknown
  role, make it tolerant in the same slice, and say so in the PR.
- **Shared logic lives in packages,** tested on macOS and compiled for iOS. House stack as in
  M21–M24: `@Observable` models, dependency clients, an injected folder and clock. Tests never
  touch live paths, Apple Music, or Messages.
- **Instruction changes ship in `LibraryMCPServer.instructions`.** Verify with `scripts/mcp-smoke`
  against the built helper.

## Slices

**Dispatch 1: S1 + S2** (auto-create and alerts). **Dispatch 2: S3 + S4** (Playlist Catchup).
**Dispatch 3: S5 + S6** (New Music Weekly). Each completing PR advances `NEXT_UP.md`. None waits on
Jon's gates. Dispatches 2 and 3 add a role and ledger fields. Merging this plan approves them, so
the architect escalates them only if they deviate from it (ADR-0005 D9).

- [ ] **S1 — Staged playlists create themselves (helper + Core).**
  - **Where it runs.** In the listening helper, on any Mac whose inbox holds an item, whether or
    not that Mac holds the polling lease: each Mac has its own inbox, so two Macs can't race over
    one item. Add `WatchPaths` on the inbox folder to `VinylFeverListeningAgent.plist`, so an
    item is processed within a minute of staging. The hourly run picks up anything missed. If the
    helper is sandboxed and can't read the inbox, stop and flag it.
  - **One process per database.** The `--poll-listening` run must not open the synced SQLiteData
    database or start a `SyncEngine`, because the windowed app may be open at the same time
    (jon-platform `docs/always-on-mac.md`). It reads the inbox files, the iCloud aliases and the
    creation log, and writes only to Music and the log. If S1 seems to need a row, stop and flag
    it.
  - **What it does with each new item** (no `created` or `dismissed` line, and not yet attempted):
    1. Resolve every track with `CatalogMatchResolver`, the same way as the phone's Create (M24
       S5), including the upload route the stage tool recorded.
    2. **Every track matched:** first read the creation log again, and look in the Music library
       for a playlist with the staged name, the same check the phone uses to hide Create. If
       either shows it's already made, write nothing and move on. iCloud can lag by minutes, and
       `WatchPaths` acts within a minute of staging, which is when Jon might tap Create on the
       phone, so the log alone isn't enough. Otherwise create the playlist in Music under its
       staged name and description, and append a `created` line to the creation log with this host
       as the creator. The Mac files the inbox from that line, as it does for the phone.
    3. **Any track ambiguous or not found:** create nothing (M24 Decision 7 stands). Append one
       `needs-review` line to the creation log listing each unresolved song in `skipped` with its
       `reason`, `ambiguous` or `not-found`. The playlist stays staged for the phone's or the Mac's
       Create.
    4. **Apple Music refuses or errors** for a song (after the existing retries): that song goes in
       `skipped` with `reason: "error"`. **For the whole playlist** (no subscription, auth, 5xx on
       the create call): append a `needs-review` line with the message in its `error` field and
       whatever songs were unresolved in `skipped`, which may be empty. `reason` never holds free
       text.
  - **One attempt per item.** An item with a `needs-review` line isn't retried automatically.
    Jon finishes it on the phone or the Mac, and their Create writes `created` as today.
  - **Format:** `needs-review` is a new `kind` on `vf-playlist-creation` v1, with `skipped` (each
    song's identity and a `reason` of `ambiguous`, `not-found`, or `error`) and an optional `error`
    string for the whole playlist. A `needs-review` line is valid only if `skipped` isn't empty or
    `error` is set. Older readers must skip it, not fail on it. Check `PlaylistCreations`' decoder,
    and the Mac's inbox filing, which must not treat it as created.
  - **`created` and `dismissed` outrank `needs-review`.** A `needs-review` line counts only when
    the batch has no `created` or `dismissed` line, whatever their `at`. Between `created` and
    `dismissed`, the latest still wins, as today. This holds everywhere a batch's state is read:
    the phone's shelf and its "Already created" check, the Mac's inbox filing and its row, and
    the archive. A `needs-review` batch archives on the same 14-day grace period as a batch with
    no line.
  - **The phone:** a staged playlist whose state is `needs-review` shows **Needs you** in place of
    "Not in Music yet": with the count when `skipped` isn't empty ("2 songs need you"), and
    otherwise "Apple Music error". Create shows only when it would today (Keep access authorized,
    no library playlist with that name). Create opens the existing sheet, where those songs ask for
    a choice.
  - **The Mac app:** the inbox row shows the same state. Its own Create still works.
  - **DoD:**
    - Core tests: all matched → `created`; one ambiguous → `needs-review` and nothing created; a
      song's API error → `skipped` with `reason: "error"`; a playlist-level API error →
      `needs-review` with `error` set; a `needs-review` line with neither `skipped` nor `error` is
      skipped as unreadable; a `needs-review` later than a `created` leaves the batch created; a
      name already in the library → nothing written; an item already created, dismissed, or
      reviewed is skipped; older lines and an unknown `kind` read unchanged;
    - the phone's shelf state from fixture logs: Not in Music yet, Needs you (a count, and the
      error), Active;
    - the helper builds, and `VinylFeverListeningAgent.plist` carries `WatchPaths`;
    - closeout records the gate: install on the mini; from the phone's ChatGPT, stage a short
      playlist that's easy to match and confirm it's in Music within two minutes without touching
      a device, and the phone shows it Active; stage one with a song that can't be found and
      confirm the phone shows Needs you, then finish it there.

- [ ] **S2 — Alerts by iMessage (helper).**
  - **When:** each `needs-review` line from S1, and (from S5) a missed Friday. One message per
    event, never repeated.
  - **What it says**, in one or two lines: the playlist name, *N of M songs found*, the first
    two unresolved songs, and "Finish it in Vinyl Fever on your phone." For a line with `error`
    set, the error message takes the place of the song count.
  - **How:** Messages through AppleScript, as ADR-0010 D3's renewal job does. The handle is Jon's
    number, set once in Vinyl Fever's **Settings → Listening History** and stored only in Vinyl
    Fever's defaults on that Mac, never in a repo or in iCloud. That section gains **Send test
    message**.
  - **No sender yet:** with no handle set, or when Messages fails, the helper logs the alert
    and carries on. The phone's Needs you is the fallback, so nothing is lost before the mini's
    Apple ID exists.
  - **Permission:** Automation → Messages, held by the helper. The first send asks for it.
  - **DoD:**
    - tests with a fake sender: one message per `needs-review`, none repeated across runs, the
      text above, and no send and no failure with no handle set;
    - closeout records the gate, held until the mini's Messages Apple ID exists: set the handle,
      send the test message, and confirm it alerts the phone; then repeat S1's unfound-song
      staging and confirm the message arrives.

- [ ] **S3 — Tracked playlists are saved (helper + Notes package + Mac Settings).**
  - **A new role, `tracked`:** an Apple playlist Jon follows for its new songs. Unlike `followed`,
    its tracks are candidates. It goes in **Settings → Taste → Playlist Roles…** like every other
    role. Add it to the role table in `taste-intelligence.md`.
  - **What the helper saves:** once a day, for each playlist labeled `tracked`, find its catalog
    playlist the way New Music is found (the library playlists relationship, cached by name), and
    fetch it. When its `lastModifiedDate` has changed since the last saved line, append a
    `vf-tracked-playlist` v1 line to `Taste Intelligence/tracked/<host>.jsonl` with the
    playlist's name, its catalog ID, `lastModifiedDate`, `fetchedAt`, and its tracks (catalog ID,
    title, artist, album, release date, and the date added when the API gives one).
    - Two library playlists with one name: save neither, and log it.
    - A tracked playlist the API can't find: log a gap line, as New Music does, and carry on with
      the others.
  - **The lease:** only the lease holder saves, as with New Music, so two Macs don't double the
    log.
  - **DoD:**
    - tests: a changed `lastModifiedDate` appends and an unchanged one doesn't; the duplicate-name
      and not-found cases; the role reads, and older role files read unchanged;
    - `vf-mcp`'s `list_playlists` reports `tracked` like any role;
    - closeout records the gate: Jon follows the five lists and labels them `tracked`; the next
      day, the log has one line for each.

- [ ] **S4 — Playlist Catchup on the phone (Notes package + phone).**
  - **What's in it:** every song in the latest saved line of each tracked playlist, deduplicated
    by catalog ID and then by `ArtistIdentity` and title, minus the songs Jon has heard (anything
    in the listening log), has kept (in a `keepers` playlist), or that are in the current New
    Music Weekly (from S6). A song that leaves every tracked playlist leaves Catchup (Decision 6).
  - **Where:** pinned at the top of the shelf, under New Music Weekly once S6 ships, with the
    count of unheard songs. It's never Archived.
  - **Each row:** the usual title, artist, Play, Keep, and Note, plus its sources as small labels
    ("Antidote", "ALT-CTRL · AltPop"), in the secondary style, with no new color. Newest first, by
    date added where the API gave it, and by release date otherwise. A filter menu shows one
    source at a time.
  - **Playing:** Play All queues the list in the system player, as the staged playlists do. There's
    no playlist in Music (Decision 6). A song played from here leaves the list once the next hourly
    poll records it. Pull to refresh re-reads.
  - **DoD:**
    - model tests from fixture logs: dedup across sources with both labels, heard and kept songs
      removed, a song gone from every source removed, ordering, and the source filter;
    - the iOS build and tests pass;
    - closeout records the gate: on the iPhone, Catchup lists the five lists' songs with sources;
      play one and confirm it's gone after the next poll; keep one and confirm it's gone after
      refresh.

- [ ] **S5 — One tool for a New Music week, and the Friday run (Core + `vf-mcp`).**
  - **`new_music_weekly_context`** (read): the latest saved week's 25 songs with familiarity and
    the release band; the Catchup pool (S4's unheard songs from tracked playlists, released in the
    last 90 days, not in the week, not owned, and not recommended before, from the snapshot); and
    whether this week's Weekly is already staged.
  - **`stage_new_music_weekly`** (write, `destructiveHint: false`):
    - `picks`: songs from the week (as `record_new_music_picks` checks them). They're hidden from
      the phone until Jon finishes the week (Decision 1).
    - `notes`: optional, on any of the week's songs, at most 300 characters each, and only where
      the chat has something to add (Decision 2).
    - `extras`: one to five songs not in the week, each with a `why`, `year`, and optional
      `like`, as `stage_playlist` takes them. They're checked the same way (`missingYear`,
      `unverifiedReferences`).
    - It writes one ledger batch, `kind: "new-music-weekly"`, keyed to the week's
      `lastModifiedDate`. Each song carries `source`: `apple-new-music` for the 25 and `chat` for
      the extras. It also writes one inbox item, **New Music Weekly — YYYY-MM-DD** (the week's
      date), with the 25 in New Music's order followed by the extras, which S1 then creates.
    - **One per week:** a second call returns `recorded: false` and writes nothing. If
      `record_new_music_picks` already recorded this week's picks, the tool keeps those picks and
      still stages the notes and extras.
    - **The latest week isn't this week yet** (saved more than six days ago): an error that says
      so, which the automation reports.
  - **Scoring:** the 25 are scored exactly as New Music weeks are today, with picked versus rest
    from `picks`. They're never counted as chat recommendations, and they aren't marked
    `recommended` for familiarity. The extras are a chat batch, banded by `year`. That makes them
    the first fair test of the chat against New Music within the `new` band (M18 Decision 1).
    `record_new_music_picks` stays for the manual path.
  - **Instructions:** for a New Music week, read `new_music_weekly_context`, pick, write notes
    only where you know something specific about the song or the artist, and never hint at the
    pick in a note ("you'll like this" is a pick). Choose the extras from the Catchup pool first;
    a song from anywhere else must pass `check_tracks`. Then call `stage_new_music_weekly`.
  - **A missed Friday:** if Saturday noon arrives with no `new-music-weekly` batch for the latest
    week, the helper sends S2's alert ("New Music Weekly didn't run this week").
  - **The Friday run** is a Codex automation on the mini that Jon sets up (Decision 3). Its whole
    prompt: "Do this week's New Music Weekly for Jon with the vinyl-fever tools." It runs Friday
    and Saturday mornings, and the one-per-week rule makes the second run a no-op. Put the prompt
    and the steps in `docs/setup/new-music-weekly.md`.
  - **DoD:**
    - Core tests: the context on a fixture week and pool; staging writes one batch and one inbox
      item; per-song `source`; the 25 not scored as chat and not marked recommended; the second
      call is a no-op; earlier picks are kept; the stale-week error; and the missed-Friday alert
      fires once;
    - `vf-mcp` golden JSON for both tools, with no IDs or paths; `mcp-smoke` passes;
    - closeout records the gate: Jon sets up the automation; on the next Friday, with nobody at the
      mini, New Music Weekly is in Music and on the phone by noon.

- [ ] **S6 — New Music Weekly on the phone.**
  - **Where:** pinned first on the shelf, showing this week only. Earlier weeks are ordinary
    staged playlists under Active or Archived, by the existing rules.
  - **Each row:** Apple's songs carry no label, and the extras carry **Chat's pick**, with their
    `why` as staged playlists show it today. A note, where there is one, shows under the song in
    the chat's plain style. Picks aren't shown anywhere.
  - **Done listening** finishes the week, with the same record and effect as the chat's
    `finish_new_music_week`. Read that record first. If the phone can't write it without a second
    writer on one file, stop and flag it. Then the row reveals the picks: a **Called it** mark on
    each picked song, and a summary line ("The chat picked 9; you kept 5 of them, and 2 it didn't
    pick").
  - **DoD:**
    - model tests from a fixture batch: ordering, labels, notes, no picks before Done listening
      and the picks after it, and the summary counts;
    - the iOS build and tests pass;
    - closeout records the gate: on the iPhone, Friday's Weekly shows the 25, the notes, and the
      five extras labeled; play an extra; tap Done listening and confirm the reveal matches
      `recommendation_outcomes` in a new chat.

## Out of scope — with destinations

- **Outcomes for tracked playlists** ("does Antidote earn its place?"). → After S4, once the log
  has a few weeks. It needs Catchup exposure counted as a source.
- **A Catchup playlist in Music.** → Not possible today: the API can't remove songs from a library
  playlist, so heard songs would never leave it (M21 S3). CarPlay plays Catchup from the phone's
  queue.
- **A notification from the phone app itself.** → It would need a push server. iMessage from the
  mini is the alert (Decision 5).
- **Retrying a `needs-review` item on its own** (Apple Music was down, say). → If it happens in
  practice. Jon's Create on the phone covers it.
- **The feedback guide's Friday section.** → The architect rewrites it after S6 merges.

## Decisions

Added 2026-11-27 with M25. Merging this plan PR approves them.

1. **Picks stay blind (Jon, 2026-11-27).** The chat's picks are hidden until Jon taps Done
   listening, so picked versus rest stays a fair test (M18 Decision 1, M21 Decision 4). The
   phone reveals them afterward.
2. **The chat notes only what it knows (Jon, 2026-11-27).** A model knows little about this
   month's releases, so a note on every song would be padding. Notes are optional per song, and
   they describe the song without predicting Jon's verdict.
3. **The Friday run is a Codex automation, not an API call (Jon, 2026-11-27).** It runs on Jon's
   ChatGPT plan with no per-token cost, and through the same `vf-mcp` tools the chat uses, so
   Vinyl Fever stays free of model calls. **Gate:** whether an unattended automation can call
   `vf-mcp`'s write tools without someone approving them. If it can't, the fallback is `codex
   exec` from a LaunchAgent on the mini, with the same prompt. Either way it runs in a folder with
   no repository, such as `~/music-chat`, and needs no shell or GitHub access.
4. **The extras come from Apple's own editors first (architect, 2026-11-27).** The tracked
   playlists are new releases that Apple's editors chose and his New Music didn't include. They're
   real catalog songs, and S4 already knows they're unheard. So the chat chooses from what's
   there rather than recalling new releases it barely knows. It may go outside that pool when a
   song passes `check_tracks`. This replaces M18 S3's similar-artists probe for now.
5. **Auto-create everything; ambiguity still waits (Jon and the architect, 2026-11-27).** Every
   staged playlist is created as soon as every song matches. One unresolved song holds the whole
   playlist for Jon's choice (M24 Decision 7), and an iMessage from the mini tells him.
6. **New Music Weekly is a playlist in Music; Catchup is a list on the phone (architect,
   2026-11-27).** The Weekly is a fixed 30 songs, so S1 creates it like any staged playlist, and
   it plays in CarPlay and Music. Catchup changes hourly as songs are heard, and the API can't
   remove songs from a playlist. A song leaves Catchup when it leaves every source, so the list
   follows the editors instead of growing without limit.
7. **Auto-create runs in the windowless `--poll-listening` run, not the open app (architect,
   2026-11-27; amended the same day).** It writes only to Music and to iCloud logs, never to
   SQLiteData rows, so it fits the helper shape in jon-platform `docs/always-on-mac.md` § What runs
   on the mini. That run is already on the mini with Music access, and launchd starts it, so the
   Vinyl Fever window doesn't have to stay open. It's the macOS 27 app, so it uses the M24 resolver
   and the inbox code as they are. Nothing moves into a macOS 15 package.
