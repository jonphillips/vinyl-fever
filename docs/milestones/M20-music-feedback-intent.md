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
stale, and writes the same note format to a file of its own, so nothing on the Mac changes. S2
adds "Why this song?": it identifies the song the same way and speaks the reason the chat gave
when it staged it, read from the recommendation ledger. Three slices, after M18 S8. They don't
change `vf-mcp`.

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
- **The Mac app's App ID, `com.jonphillips.vinylfever`, already has MusicKit,** and the Mac app
  is authorized against it.

## S0 results (architect, 2026-10-29)

From #154 and #155, and 11 probe lines in `Vinyl Fever/Probes/` (iPad 5, iPhone 6), with
Jon's account of each run.

- **The player is the source to trust.** `SystemMusicPlayer.shared` named the song Jon was
  hearing in 9 of 11 lines: library songs, a live upload, and New Music first hearings at 3 to
  10 seconds in. It never returned a missing or blank entry. The other two lines are the stuck
  case and a paused iPhone, both below.
- **The stuck case happened once, and recently played caught it.** At 16:53:00 (iPhone, started
  from Shortcuts) Jon heard the Rolling Stones' "Who You Callin' Crazy". The player said June
  Rest's "Safe Is A Lie" at 206.6 s, and recently played listed the Stones song first with June
  Rest second. The stuck song was already in recently played, below a newer song. Jon couldn't
  reproduce it on purpose; it came up unprompted.
- **Recently played lags and is shared across devices.** A song that has just started is
  sometimes at the top ("Lullaby" at 6.6 s) and sometimes missing ("7" at 29.7 s, "Pyro" at
  5.8 s). The iPhone's list included Clairo's "Amoeba", which was playing on the iPad. At
  16:19:36 the iPhone's player was paused on an old Sky Ferreira song while Jon listened on the
  iPad.
- **IDs aren't stable.** The same song is a catalog ID in one line and a library ID (`i.…`) two
  minutes later. A live upload has only a library ID. Match songs by title and artist.
- **The intent can't tell how it was started.** `startedFrom` was empty in every line. Siri, the
  Action button, and Shortcuts all ran it. The start from Shortcuts kept the music playing.
- **Control Center has no Vinyl Fever control.** It lists only apps that ship a control widget.
  Its Shortcut control can run a one-action shortcut that runs the intent; Jon ran the probe
  that way.
- **The folder bookmark works locked.** The locked Action button run wrote its line. #155 fixed
  a refresh that lost access on the second run. **CarPlay wasn't probed;** S1's gate step 5
  covers it.

**S1's staleness rule (Decision 8).** The player's entry is stale when any of these is true:
it's missing or its title is blank; the player isn't playing; or its song is in recently played
below a newer song. The rule fits all 11 lines: it flags 16:53:00 and 16:19:36 and nothing
else. It rests on one stuck sample, so S1's gate keeps the stuck case.

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
S1. **Dispatch 3: S2** ("Why this song?"; Jon's device gate). Jon moved it ahead of S1's gate on
2026-10-30 (Decision 10); its plan PR advances `NEXT_UP.md` to S2.

- [x] **S0 — The app target and the device probes.** *Done in #154 and #155; results above.*
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
    macOS-only. *Withdrawn in #154's review: Core is the Mac console's package, so the app
    doesn't link it (Decision 7).*
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

- [x] **S1 — The Music Feedback intent.** *Implemented in `m20/s1-music-feedback-intent`; Jon's six-step iPhone and iPad gate remains owed.*
  - **The intent.** Name it "Music Feedback" and expose it through `AppShortcutsProvider`. Siri,
    CarPlay, the Action button, and Control Center can all start it.
    1. **Identify first, before any dialog.** Read `SystemMusicPlayer`'s current entry and the
       newest recently played songs.
    2. **Decide whether to trust it,** using S0's rule (Decision 8). The entry is stale when
       any of these is true:
       - it's missing, or its title is blank;
       - the player's playback status isn't `playing`;
       - its song is in recently played below a newer song.

       Songs match by title and artist (Constants), never by ID.
    3. **When it can be trusted,** ask "What do you think of <title> by <artist>?" and take
       Jon's dictation as the intent's `note` parameter.
    4. **When it's stale,** ask "Which song?" with up to 4 choices (Constants), then "None of
       these":
       - the entry first, unless it's stale because a newer song is above it in recently played;
       - then recently played, newest first;
       - no duplicates.

       "None of these" saves a time-only note. Siri reads the choices aloud, so this works in
       CarPlay. Recently played is shared across Jon's devices, so a song from the other device
       can be a choice. That's wanted: he may be listening there.
    5. **Empty or "Cancel" writes nothing,** and Siri says so. This is the guard Decision 16
       asked the shortcut for, built in.
    6. **Keep the evidence.** After each run that writes a note, append the run's snapshot to
       `Vinyl Fever/Probes/feedback-<device>.jsonl`: S0's probe line, plus the stale reason (or
       none), the choices offered, and the song saved. The file name doesn't start with
       `notes`. If the rule misjudges a song, this file shows what the player and recently
       played said.
  - **Starting it.** Siri, the Action button, and CarPlay start the intent directly. Control
    Center starts it through its Shortcut control, running a one-action shortcut that runs the
    intent (Decision 9). No control widget.
  - **The shared note format (Decision 7).** Add a package, `VinylFeverNotes`, for macOS 26 and
    iOS 27, using only Foundation. Move `TasteNote`, `TasteNotesReadResult`, and
    `TasteNotesCodec` (`encode`, `readFiles`, `openQuestions`, and the coordinated append behind
    `appendChatNote`) out of Core's `TasteNotes.swift`. Add `catalogID: String?` to `TasteNote`;
    nil is omitted on encode, so existing lines are unchanged. `TasteNotePeriod` and
    `TasteNoteCandidates` stay in Core, because the candidates need `ListeningLog`. Core
    depends on the package and re-exports it, so no Mac or `vf-mcp` call site changes. The app
    links only `VinylFeverNotes`. Core stays macOS-only.
  - **The probe stays** through S1's gate, in case the stuck case needs another look. S2
    removes it. *(S2 now comes before S1's gate, so the first slice after the gate removes it;
    Decision 10.)*
  - **The line.** A `vf-taste-note` v1 line through `TasteNotesCodec`:
    - The keys are the shortcut's: `format`, `version`, `notedAt`, `title`, `artist`, `album`,
      `playCount`, `releaseDate`, `duration`, `note`, `source`, `device`. `TasteNotesCodec.encode`
      writes them; keys the player can't supply are omitted.
    - `catalogID` is added when the entry has one. It's an optional key, and v1 readers ignore
      it.
    - `source` is `now-playing`, `picked`, or `time-only`.
    - `note` is Jon's dictation, word for word.
  - **The file.** Append to `Taste Intelligence/notes-feedback-<device>.jsonl` through the
    bookmark, with `NSFileCoordinator` `.forMerging`. Sanitize the device name the way
    `appendChatNote` sanitizes the host, through the package's shared append. Reuse S0's
    `ProbeBookmarkStore.withFolder`. If the folder isn't granted or access is refused, say "Open
    Vinyl Fever to grant folder access" and write nothing.
  - **The setup screen** gains the last note this device wrote (song, time, source) and a test
    button that runs the identification step without saving anything.

  **DoD:**
  - **Tests:**
    - golden JSON for each `source`, with the shortcut's key set, plus `catalogID` when present;
    - the staleness rule's cases, with the player and recently played injected, taken from S0's
      lines: the stuck song below a newer one (16:53:00, stale); paused on another device's old
      song (16:19:36, stale); a new song not yet in recently played (16:36:32, trusted); the
      song at the top of recently played (16:34:54, trusted); a missing entry; a blank title;
      and title and artist matching across a catalog ID and a library ID;
    - the pick list: the entry first or not, per step 4; no duplicates; at most 4; and "None of
      these" saves a time-only note;
    - the evidence line's golden JSON;
    - empty and "Cancel" write nothing;
    - device-name sanitizing;
    - appending to a temp folder through coordination;
    - a missing bookmark writes nothing and returns the message.
  - **Package tests:** `TasteNotesCodec`'s existing Core tests move with it unchanged, and pass
    on macOS. A `catalogID` round trip, and a line without it encodes byte-identically to today.
  - **Core test:** `TasteNotesCodec.readFiles` reads a `notes-feedback-iPad.jsonl` fixture,
    `catalogID` included, with nothing skipped. **`vf-mcp` test:** `taste_notes` over a folder
    holding that file returns its note.
  - **Builds:** iOS Simulator and device. Mac and Core suites pass.
  - **Jon's gate (after install on the iPad and iPhone, owed until done):**
    1. A known song, by voice. The note has the right song and `source: now-playing`.
    2. A New Music first hearing. Either the right song, or a pick list that contains it.
       Once by voice, once from the Action button, and once from Control Center's Shortcut
       control.
    3. The stuck case: leave a note, move to the next song, and leave another. The second note
       goes on the new song, or the pick list offers it. Music isn't restarted.
    4. "Cancel" writes nothing.
    5. On the iPhone, locked, and through CarPlay, a note is saved.
    6. In a new chat, `taste_notes` shows these notes word for word, on the right songs.

- [ ] **S2 — "Why this song?"** *(Jon, 2026-10-30, from the candidate in
  [open-questions.md](../open-questions.md), recorded in #147.)*

  A recommended song comes on during a walk, and Jon asks why the chat picked it. The answer is
  already on iCloud Drive: since M18 S2, each staged song's ledger line carries the chat's `why`
  and up to three `like` songs. The intent reads it and speaks it. No chat round trip, no new
  `vf-mcp` tool, and nothing is written except the evidence line.

  **What S2 starts from (architect, read-only, 2026-10-30).** The laptop's ledger,
  `recommendations/Jon_MBP.jsonl`, has 5 batches and 252 songs, no song in two batches:
  - *2023 Selections: 15 New Discoveries* (2026-10-28): 15 songs, each with a `why` and two
    `like` songs, all `found: library`.
  - *Sam Fender — Manchester 2027 Catch-Up* (10) and *Soft Vocals: Where's the Edge?* (12):
    every song has a `why`, none has `like`.
  - *Rolling Stone's 200 Best Rock Songs of the 21st Century* (200) and *2024 Selections: 15
    New Discoveries* (15, staged before M18 S2): no `why`.
  - The longest `why` is 167 characters. Every `request` is about 200 characters.
  - The iPhone's two Music Feedback notes on 2026-10-29 both identified the song as
    `now-playing`, and the evidence file agrees. The second note's text is "Cancel cancel": S1's
    guard catches "Cancel" but not a repeat, so the note was saved. It stays in the file (M18
    Decision 16); S2 fixes the guard.

  - **The intent.** Name it "Why This Song" and expose it through `AppShortcutsProvider`, with
    phrases such as "Why this song in Vinyl Fever" and "Why did Vinyl Fever pick this". Siri,
    CarPlay, and the Action button start it; Control Center through its Shortcut control
    (Decision 9).
    1. **Identify the song as S1 does:** `MusicFeedback.identify` with the same player, recently
       played, and staleness rule (Decision 8). No new identification code.
    2. **When it's trusted,** look up the entry. **When it's stale,** ask "Which song?" with S1's
       choices. "None of these" answers "No song picked." and stops.
    3. **Read the ledger.** Every `*.jsonl` in `Taste Intelligence/recommendations/`, through
       S0's `ProbeBookmarkStore.withFolder`, each with a coordinated read. Before reading, ask
       iCloud to download each file. Include evicted files that show only as a
       `.<name>.icloud` placeholder. Stop waiting at the read deadline (Constants). Decode with
       `RecommendationLedgerCodec.readFiles`.
    4. **Find the song.** Match title and artist with `MusicFeedback.matches`, never IDs, across
       all batches. Use the newest batch whose line has a `why`; if none has one, the newest
       batch.
    5. **Speak the answer** as the intent's dialog. The texts are fixed (golden tests):
       - **With a reason:** "*Title* by *Artist* was in *playlist*, staged *October 28*.
         *why*" and, when there are `like` songs, "The chat compared it with *Heaven or Not* by
         *White Reaper* and *Something We Are Overcoming* by *DMA'S*." Join two with "and",
         three with commas and "and".
       - **Staged without a reason:** "*Title* by *Artist* was in *playlist*, staged *October
         29*, without a reason."
       - A batch with no `playlist` says "in a staged batch".
       - **Not in the ledger, and every file was read:** "Vinyl Fever didn't recommend *Title*
         by *Artist*."
       - **Not found, and a file couldn't be read in time:** "I can't read the recommendations
         yet. Try again in a minute." Never "didn't recommend" (Decision 12).
       - **No folder access:** S1's "Open Vinyl Fever to grant folder access".

       The `request` isn't spoken (Decision 13). The date is in the device's time zone, with the
       year only when it isn't this year.
    6. **Keep the evidence.** After each run that reaches an answer, append one line to
       `Vinyl Fever/Probes/why-<device>.jsonl`: S0's probe line, plus the stale reason (or none),
       the choices offered, the song asked about, the answer's kind, the batch's `recordedAt`
       and `playlist` when found, and how many ledger files were read and unreadable. The file
       name doesn't start with `notes`. If a live version or a remaster misses, this file shows
       what the player said.
  - **The ledger format moves to `VinylFeverNotes` (Decision 11).** Move `RecommendationTrack`,
    `RecommendationLike`, `RecommendationBatch`, `RecommendationCoverage`,
    `RecommendationLedgerReadResult`, and `RecommendationLedgerCodec` out of Core's
    `RecommendationLedger.swift`, as S1 moved the note format. `RecommendationEvidence` and
    `RecommendationLedgerEvidenceIndex` stay in Core, because the index needs `ArtistIdentity`.
    Core already re-exports the package, so no Mac or `vf-mcp` call site changes. No format
    change: the ledger stays `vf-recommendation-batch` v1, and nothing on the phone writes it.
  - **The answer logic lives in the package,** Foundation only, so it's tested on macOS: a
    lookup from a song and a read result (with an unreadable-file count) to an answer, and the
    spoken text from the answer, with the clock, calendar, and time zone injected. The app does
    the reading and the dialog.
  - **The Cancel guard.** `MusicFeedback.makeNote` writes nothing when every word of the note,
    with punctuation stripped, is "cancel": "Cancel cancel" and "Cancel. Cancel." included. A
    note that only starts with "cancel" is still saved.
  - **The setup screen** gains a "Test Why This Song" button that runs steps 1 to 5 and shows
    the text it would speak. It writes nothing, not even the evidence line.
  - **The probe intent stays** until S1's gate passes (Decision 10).

  **DoD:**
  - **Package tests (`VinylFeverNotes`):**
    - the moved ledger tests pass unchanged, and an encoded batch is byte-identical to before
      the move;
    - the lookup: a song with a `why`; a song only in a batch without a `why`; a newer batch
      without a `why` and an older one with it (the older one answers); not in the ledger; not
      found with an unreadable file (the "can't read" answer, never "didn't recommend"); found
      even when another file is unreadable; title and artist matching across case and
      diacritics;
    - the spoken text's golden strings: zero, one, two, and three `like` songs; no `playlist`;
      a date in this year and one in last year; a date near midnight UTC in a US time zone;
    - the Cancel guard: "Cancel cancel" and "cancel, cancel." write nothing; "Cancel culture is a
      bad name for a band" is still saved.
  - **App tests (`VinylFeverMobileTests`):** reading a temp folder with two ledger files, one
    named as a `.icloud` placeholder; a file that can't be read before the deadline (injected)
    counts as unreadable; a missing bookmark returns the folder message; the evidence line's
    golden JSON; the evidence file name doesn't start with `notes`.
  - **Core and `vf-mcp`:** the suites pass unchanged. `recommendationLedger()` reads a fixture
    folder through the moved codec with the same result.
  - **Builds:** iOS Simulator and device. The Mac app, Core, Listening, and `VinylFeverNotes`
    suites pass.
  - **Jon's gate (after install on the iPhone or iPad, owed until done):**
    1. A song from *2023 Selections: 15 New Discoveries*, by voice: Siri speaks the playlist,
       the date, the `why`, and both `like` songs.
    2. A song from *Soft Vocals: Where's the Edge?*: the `why`, and no "compared it with".
    3. A song from *Rolling Stone's 200 Best Rock Songs…*: "without a reason".
    4. A library song the chat never staged: "Vinyl Fever didn't recommend…".
    5. Once from the locked iPhone or through CarPlay.
    6. Music Feedback, saying "Cancel cancel": no note is saved. This also rechecks S1's gate
       step 4.

## Prerequisites (Jon, not the executor's)

- [x] **Before S0's device runs:** add the iOS platform to the App ID
  `com.jonphillips.vinylfever` (Decision 4), confirm MusicKit is on, register the iPad and the
  iPhone, and install a development profile. Done 2026-10-29: automatic signing made the iOS
  profile, and both devices ran the probe.
- [ ] **Before S1's gate:** make a one-action shortcut, "VF Music Feedback", that runs the
  intent, and pick it in Control Center's Shortcut control on both devices. It's the gate's
  Control Center start, and it leaves the old shortcut alone until the gate passes.
- [ ] **Before S1's gate:** TestFlight, so updates reach both devices without a cable. Follow
  jon-platform `docs/ios/testflight.md`: an App Store Connect app record and the app's
  `testflight.conf`. The Team API key is shared with Galavant and Yes Chef.
- [ ] **After S1's gate:** point Siri's "Music Feedback" at the intent. Either edit the
  shortcut so its only action is the intent, which keeps the phrase, or delete the shortcut and
  use the intent's own phrase. The shortcut's `notes.jsonl` stays: the reader keeps reading it,
  and it isn't edited (M18 Decision 16). Point Control Center's Shortcut control at
  "Music Feedback" and remove "VF Music Feedback".

## Constants register (starting values)

| Constant | Value | Why |
| --- | --- | --- |
| Pick-list choices | 4, plus "None of these" | Short enough for Siri to read aloud in a car |
| Recently played read | newest 5 | One more than the pick list, for deduplication |
| Staleness rule | missing or blank, not playing, or below a newer song in recently played | S0's 11 lines (Decision 8) |
| Song match | title and artist, trimmed, case- and diacritic-insensitive | IDs switch between catalog and library (S0) |
| Ledger read deadline (S2) | 8 seconds, all files together | Siri waits on the intent; past this, "can't read yet" beats silence |
| Which ledger line answers (S2) | newest batch whose line has a `why`, else newest batch | A later restaging without a reason shouldn't hide the reason |
| Spoken `like` songs (S2) | all of them (the ledger keeps at most 3) | Two names read aloud in about five seconds |
| Spoken `request` (S2) | never | About 200 characters each; the playlist name carries it (Decision 13) |

## Out of scope — with destinations

- **Leaving a note right after the answer** (one run: "why", then "what do you think?"). →
  After S2's gate, if Jon wants it. Today he says "Music Feedback" next, and the same
  identification finds the same song.
- **Catalog IDs on new ledger lines** (fewer misses on live versions and remasters). → Only if
  S2's evidence file shows misses. It's an optional field in `vf-mcp`; the ledger stays v1.
- **The audition view** (recent batches with each song's `why`, `like`, and `request`; Vinyl
  Fever plays the picks and pairs, so it knows the song). → After S2. It needs no
  identification at all, and its feedback goes through Music Feedback's notes file.
- **Removing the probe intent.** → The first slice after S1's gate (Decision 10).
- **Album brief and Play Next.** → Their probes in open-questions.md (the chat route, the queue,
  and who calls the catalog) come first.
- **ShazamKit.** → Only if S0 shows a start that keeps the music playing and a case that the
  player and recently played both miss.
- **A native iPad layout.** → The setup screen is the only UI. It needs no iPad design.
- **A Control Center control widget.** → Only if the Shortcut control fails S1's gate
  (Decision 9).

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
4. **The iOS target uses the Mac app's bundle ID, `com.jonphillips.vinylfever`.** The App ID
   already has MusicKit, and one app on two platforms is the usual shape. The alternative is a
   separate iOS ID with MusicKit added. Jon chose the shared ID when merging #154. (This plan
   first wrote it `com.jonphillips.VinylFever`; the registered ID is lowercase.)
5. **Jon grants folder access once.** Moving `Taste Intelligence/` into an app container would
   change every Mac reader and `vf-mcp`. A bookmark to the folder changes nothing on the Mac.
   If S0 shows the bookmark failing from a locked device or CarPlay, S1 stops for a decision.
6. **S0 probes before S1 builds.** The stuck song is only partly explained. S1's staleness rule
   is written from what the devices actually report.

Added 2026-10-29 with S0's results. Merging that plan PR approves them.

7. **The note format moves into a small cross-platform package; Core stays macOS-only.** Core
   holds the Mac console: Music.app clients, the schema, `vf-mcp`, and the macOS-only
   MCPServerKit. Making it build for iOS was the wide change S0 said to stop for (#154). The
   format code uses only Foundation, so it moves as is, and Core re-exports it.
8. **The staleness rule comes from S0's lines.** The player was right in 9 of 11 lines. The
   stuck answer was already in recently played, below the song Jon was hearing, and the other
   miss was a paused player. The first plan's default compared the entry with this device's
   last note. It can't catch a stuck song without a recent note, and it misses one when the
   note is younger than the song's duration. It is replaced.
9. **Control Center goes through its Shortcut control.** A Vinyl Fever control would need a
   widget extension. The Shortcut control runs a one-action shortcut instead: "VF Music
   Feedback" for the gate, then "Music Feedback" once it points at the intent. Jon ran the probe
   that way, and the music kept playing. S1's gate tests it.

Added 2026-10-30 with S2. Merging that plan PR approves them.

10. **S2 goes before S1's gate (Jon, 2026-10-30).** S2 only reads and speaks: if the
    identification misjudges a song, Jon hears a wrong answer, not a note filed on the wrong
    song. The iPhone's two notes on 2026-10-29 identified the song correctly. S2 fixes the
    Cancel guard that one of them got past, and its gate rechecks it. The probe stays until S1's
    gate passes.
11. **The ledger's model and codec move to `VinylFeverNotes`,** for the same reason as the note
    format (Decision 7): the phone needs them, they use only Foundation, and Core stays
    macOS-only. The evidence index stays in Core.
12. **An unreadable ledger is never "not recommended".** iCloud evicts the ledger on both the
    laptop and the phones. Telling Jon a recommended song wasn't recommended would be wrong in
    a way he can't see, so a song not found while any file is unread gets "can't read yet".
13. **The batch's `request` isn't spoken.** Requests run about 200 characters and read as
    instructions to the chat. The playlist name and the date place the batch, and the `why`
    carries the reason. The audition view will show the request.
