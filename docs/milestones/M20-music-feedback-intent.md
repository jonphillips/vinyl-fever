# Milestone 20 — Music Feedback in the Vinyl Fever app (iPhone and iPad)

*Replace the Music Feedback shortcut with an App Intent in a Vinyl Fever app for iPhone and iPad,
so a note lands on the song Jon is actually hearing. This is the first slice of the iPhone
companion approved on 2026-10-27 ([open-questions.md](../open-questions.md), *Now-playing album
brief, and the iPhone companion*). Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply. Where this doc and those conflict, stop and flag
it.*

Summary: The Music Feedback shortcut puts notes on the wrong song. Get Current Song can stay
stuck on an earlier song until Jon restarts Music, and the Shazam fallback hears nothing because
Siri pauses the music for dictation. S0 adds the app target and probes on Jon's devices what
MusicKit and recently played report when the shortcut is wrong. S1 builds the Music Feedback
intent. It identifies the song without listening, offers a short pick list when the answer looks
stale, and writes the same note format to a file of its own, so nothing on the Mac changes. Two
slices, after M18 S8. They don't touch `vf-mcp`.

## The milestone in one sentence

Jon says "Music Feedback", talks, and the note is saved word for word against the song he's
hearing, or against one he picks from his last few songs, without restarting Music and without
Shazam.

## What's true today (architect, read-only, 2026-10-29)

- **The shortcut's notes go on the wrong song.**
  - On 2026-10-28 the iPad saved three notes in a row on Pixey's "Million Dollar Baby" (09:47,
    09:48 and 10:08 EDT).
  - The listening log's 10:02 fetch shows six other songs played in that window: Middle Kids,
    2nd Grade, joan, The Linda Lindas, COIN and Bad Moves. The 09:48 note ("I guess Power
    Pop…") and the 10:08 note almost certainly belong to two of them.
  - On 2026-10-29 it stuck again after Clairo's "Bags". Skipping forward and back didn't clear
    it, and Jon expects only restarting Music to.
  - The shortcut already speaks the song's name, so Jon can see when it's wrong. It just can't
    correct it.
- **A related gap, already recorded.** On a first hearing, Get Current Song is blank or wrong
  until the queue moves past the song ([taste-intelligence.md](../taste-intelligence.md),
  *Evidence*). The likely cause is that iOS writes a streamed song's full record only when it
  enters recently played. The stuck notes were on New Music auditions, which are first hearings.
  The stuck song may well be the same cause.
- **Shazam can't be the fallback.** Siri pauses the music for dictation, so Recognize Music, and
  ShazamKit in an app, have nothing to hear.
- **Jon's feedback device is the iPad.** All recent Music Feedback notes say `device: iPad 2025`.
  The approved plan said "iPhone first, iPad later".
- **Nothing on the Mac needs to change for a new notes file.** `taste_notes` and `check_tracks`
  read every `notes*.jsonl` in `Taste Intelligence/` through file coordination (since M17). The
  chat already writes `notes-chat-<host>.jsonl` beside the shortcut's `notes.jsonl`.
- **The packages are macOS-only today.** `VinylFeverCore` declares `.macOS(.v26)`, and
  `VinylFeverListening` `.macOS(.v15)`. `TasteNotesCodec` is in Core, which imports neither
  AppKit nor ScriptingBridge. There's no iOS target in `project.yml`.
- **The notes folder isn't in an app container.** `Vinyl Fever/Taste Intelligence/` is in the
  root of Jon's iCloud Drive. A sandboxed iOS app can write there only with access Jon grants
  once, through the folder picker, kept as a security-scoped bookmark.
- **The Mac app's App ID, `com.jonphillips.VinylFever`, already has MusicKit,** and the Mac app
  is authorized against it.

## Shared rules (every slice)

- **Nothing on the Mac changes.** No `vf-mcp`, app, or format change. A note from the intent is a
  `vf-taste-note` v1 line that today's reader already accepts.
- **The intent never writes the shortcut's `notes.jsonl`.** It appends to its own per-device
  file, so two writers never append to one file (Decision 1).
- **Read the player, don't drive it.** M20 never changes playback, the queue, or the library.
- **Hands-free first.** Every step must work by voice, through Siri on a locked iPhone or iPad
  and through CarPlay. Screens are for setup only.
- **Tests never touch live paths.** The folder, the player, recently played, and the clock are
  injected. Tests use temp folders and fixtures.

## Slices

**Dispatch 1: S0** (new iOS target + probe; Jon's device runs). **Dispatch 2: S1** (the intent;
Jon's device gate). M18 S8's completing PR advances `NEXT_UP.md` to S0. The architect records
S0's results in this doc, including S1's staleness rule. That plan PR advances `NEXT_UP.md` to
S1.

- [ ] **S0 — The app target and the device probes.**
  - **The target.** Add `VinylFeverMobile` to `project.yml`. It's a SwiftUI app for iPhone and
    iPad (iOS and iPadOS 27), with the bundle ID `com.jonphillips.VinylFever` (Decision 4) and the
    MusicKit capability. It starts with one setup screen:
    - **Grant folder access…** opens the folder picker. Jon picks `iCloud Drive/Vinyl Fever`, and
      the app keeps a security-scoped bookmark to it.
    - It shows the MusicKit authorization status, with a button to request it.
  - **The probe intent,** "Vinyl Fever Probe", is exposed through `AppShortcutsProvider`. Each
    run appends one JSON line to `Vinyl Fever/Probes/m20-s0-<device>.jsonl` through the bookmark,
    with file coordination. The file name doesn't start with `notes`, so nothing reads it as a
    note. Each line records:
    - the time, the device, and how the intent was started, where the intent can tell;
    - `SystemMusicPlayer.shared` at the intent's first line: the playback status, the playback
      time, and the queue's current entry (title, artist, album, and catalog ID, or that the
      entry or its item is missing);
    - the newest 5 songs from `MusicRecentlyPlayedRequest<Song>`, with their catalog IDs;
    - whether the folder write succeeded, and if not, the error.
  - **Packages.** Add `.iOS(.v27)` to `VinylFeverCore`'s platforms. Wrap any code that doesn't
    build for iOS in `#if os(macOS)`. Don't copy the code into the target. If Core can't build
    for iOS without wide changes, stop and report what blocks it. `VinylFeverListening` stays
    macOS-only.
  - **Jon's device runs.** On the iPad, then the iPhone, run the probe from Siri by voice, the
    Action button, and Control Center. Record whether the music was playing when the intent
    started.
    1. A song Jon knows, in his library.
    2. A New Music song on its first hearing.
    3. The stuck case: leave a note with the old shortcut, move to the next song, and when the
       shortcut shows the old song, run the probe.
    4. On the iPhone with the screen locked, and through CarPlay. Did the folder write work?

  **DoD:**
  - **Builds:** the app builds for the iOS Simulator and for a device. The Mac app and Core
    tests pass unchanged, and the Mac target's behavior doesn't change.
  - **Tests:** the probe line's encoding (golden JSON, with the player, the recently played
    list, and the clock injected); the bookmark store saves and resolves (temp folder); the
    probe file name doesn't start with `notes`.
  - **Verification:** add the iOS Simulator build command to
    [../verification.md](../verification.md).
  - **Handoff:** list the device runs as owed. The executor runs the Simulator build. The
    simulator has no Music queue, so its probe lines don't count.
  - **Architect after Jon's runs:** read the probe files and record the S0 results here: what to
    trust, how to detect a stale answer, and whether the locked and CarPlay writes work. That
    plan PR sets S1's staleness rule and dispatches S1.

- [ ] **S1 — The Music Feedback intent.** *Its staleness rule comes from S0's results.*
  - **The intent.** Name it "Music Feedback" and expose it through `AppShortcutsProvider`. Siri,
    CarPlay, the Action button, and Control Center can all start it.
    1. **Identify first, before any dialog.** Read `SystemMusicPlayer`'s current entry and the
       newest recently played songs.
    2. **Decide whether to trust it,** using S0's rule. The default, until S0 replaces it: the
       entry is stale if it's missing or blank, or if it's the same song as this device's last
       note and that note is older than the song's duration.
    3. **When it can be trusted,** ask "What do you think of <title> by <artist>?" and take
       Jon's dictation as the intent's `note` parameter.
    4. **When it's stale,** ask "Which song?" with up to 4 choices (Constants): the entry, if it
       has one, then recently played songs, newest first, without duplicates, then "None of
       these". "None of these" saves a time-only note. Siri reads the choices aloud, so this
       works in CarPlay.
    5. **Empty or "Cancel" writes nothing,** and Siri says so. This is the guard Decision 16
       asked the shortcut for, built in.
  - **The line.** A `vf-taste-note` v1 line through `TasteNotesCodec`:
    - The keys are the shortcut's: `format`, `version`, `notedAt` (ISO 8601 with offset),
      `title`, `artist`, `album`, `playCount`, `releaseDate`, `duration`, `note`, `source`,
      `device`.
    - `catalogID` is added when the entry has one. It's an optional key, and v1 readers ignore
      it.
    - `source` is `now-playing`, `picked`, or `time-only`.
    - `note` is Jon's dictation, word for word.
  - **The file.** Append to `Taste Intelligence/notes-feedback-<device>.jsonl` through the
    bookmark, with `NSFileCoordinator` `.forMerging`. Sanitize the device name the way
    `appendChatNote` sanitizes the host. If the bookmark is missing or stale, say "Open Vinyl
    Fever to grant folder access" and write nothing.
  - **The setup screen** gains the last note this device wrote (song, time, source) and a test
    button that runs the identification step without saving anything.

  **DoD:**
  - **Tests:**
    - golden JSON for each `source`, with the shortcut's key set, plus `catalogID` when present;
    - the staleness rule's cases, with the player, recently played, the last note, and the clock
      injected;
    - the pick list: the order, no duplicates, at most 4, and "None of these" saves a time-only
      note;
    - empty and "Cancel" write nothing;
    - device-name sanitizing;
    - appending to a temp folder through coordination;
    - a missing bookmark writes nothing and returns the message.
  - **Core test:** `TasteNotesCodec.readFiles` reads a `notes-feedback-iPad.jsonl` fixture,
    `catalogID` included, with nothing skipped. **`vf-mcp` test:** `taste_notes` over a folder
    holding that file returns its note.
  - **Builds:** iOS Simulator and device. Mac and Core suites pass.
  - **Jon's gate (after install on the iPad and iPhone, owed until done):**
    1. A known song, by voice. The note has the right song and `source: now-playing`.
    2. A New Music first hearing. Either the right song, or a pick list that contains it.
    3. The stuck case: leave a note, move to the next song, and leave another. The second note
       goes on the new song, or the pick list offers it. Music isn't restarted.
    4. "Cancel" writes nothing.
    5. On the iPhone, locked, and through CarPlay, a note is saved.
    6. In a new chat, `taste_notes` shows these notes word for word, on the right songs.

## Prerequisites (Jon, not the executor's)

- [ ] **Before S0's device runs:** add the iOS platform to the App ID
  `com.jonphillips.VinylFever` (Decision 4), confirm MusicKit is on, register the iPad and the
  iPhone, and install a development profile. Xcode's automatic signing may do all of this.
  Both devices run iOS/iPadOS 27.
- [ ] **Before S1's gate:** TestFlight, so updates reach both devices without a cable. Follow
  jon-platform `docs/ios/testflight.md`: an App Store Connect app record and the app's
  `testflight.conf`. The Team API key is shared with Galavant and Yes Chef.
- [ ] **After S1's gate:** point Siri's "Music Feedback" at the intent. Either edit the
  shortcut so its only action is the intent, which keeps the phrase, or delete the shortcut and
  use the intent's own phrase. The shortcut's `notes.jsonl` stays: the reader keeps reading it,
  and it isn't edited (M18 Decision 16).

## Constants register (starting values)

| Constant | Value | Why |
| --- | --- | --- |
| Pick-list choices | 4, plus "None of these" | Short enough for Siri to read aloud in a car |
| Recently played read | newest 5 | One more than the pick list, for deduplication |
| Staleness default | same song as this device's last note, older than the song's duration | Replaced by S0's results |

## Out of scope — with destinations

- **"Why this song?"** (speaks the ledger's `why` and `like`). → M20 S2, planned after S1's gate.
  It reuses S1's identification.
- **The audition view** (Vinyl Fever plays the chat's picks and pairs, so it knows the song).
  → After S2. It needs no identification at all.
- **Album brief and Play Next.** → Their probes in open-questions.md (the chat route, the queue,
  and who calls the catalog) come first.
- **ShazamKit.** → Only if S0 shows a start that keeps the music playing and a case that the
  player and recently played both miss.
- **A native iPad layout.** → The setup screen is the only UI. It needs no iPad design.

## Decisions

Added 2026-10-29 with M20. Merging that plan PR approves them.

1. **The intent writes its own file, `notes-feedback-<device>.jsonl`.** The reader already
   reads every `notes*.jsonl`, so the Mac doesn't change. One writer per file avoids iCloud
   conflict copies between the iPad, the iPhone, and the shortcut. M18 Decision 16 still holds:
   no file is edited by hand.
2. **Identify the song without listening.** Siri pauses the music to take dictation, so
   anything that listens fails exactly when it's needed. The player's state and recently played
   need no audio. A short spoken pick list turns a wrong guess into one word.
3. **One app for iPhone and iPad from the start,** because the iPad is where Jon gives feedback.
   This supersedes "iPhone first, iPad later" for this target, though not for an iPad-specific
   design.
4. **The iOS target uses the Mac app's bundle ID, `com.jonphillips.VinylFever`.** The App ID
   already has MusicKit, and one app on two platforms is the usual shape. The alternative is a
   separate iOS ID with MusicKit added. Jon decides at merge.
5. **Jon grants folder access once.** Moving `Taste Intelligence/` into an app container would
   change every Mac reader and `vf-mcp`. A bookmark to the folder changes nothing on the Mac.
   If S0 shows the bookmark failing from a locked device or CarPlay, S1 stops for a decision.
6. **S0 probes before S1 builds.** The stuck song is only partly explained. S1's staleness rule
   is written from what the devices actually report.
