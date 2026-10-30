# Milestone 21 — The Vinyl Fever playlists, in the iPhone and iPad app

*Give the Vinyl Fever app a home screen: every playlist the chat staged, each song with the
chat's reason and the songs it compared it with, playable from the app, with a note one tap
away. It's "the audition view" that [M20](M20-music-feedback-intent.md) parked for after S2.
M20's shared rules still apply except where Decision 1 replaces one. Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply, and the screens follow jon-platform
`docs/ios/ui-and-platforms.md`. Where this doc and those conflict, stop and flag it.*

Status: Dispatched
Summary: S1 lists the staged playlists with their reasons, S2 plays them from the app, and S3 adds notes; Jon's gates can run together after S3.

M20 made the app a voice surface: "Why this song?" answers in the car, with the screen off.
This milestone adds the surface for sitting down with a playlist. Jon opens Vinyl Fever and
sees what the chat staged, what he asked for, and why each song is there. He taps a song to
play the playlist from it, or taps a "sounds like" song to hear the comparison. When a song
misses, he leaves a note from that row. The data is already on iCloud Drive, and the app
already reads it (M20 S2). Three slices. They don't change `vf-mcp`, the Mac app, or any file
format.

## The milestone in one sentence

Jon opens Vinyl Fever on the iPad, picks a playlist the chat made, reads why each song is there,
plays it from any song, and leaves a note on the one that missed, without opening the chat.

## What's true today (architect, read-only, 2026-10-30)

- **The ledger has five staged playlists and one New Music week.**
  `Taste Intelligence/recommendations/Jon_MBP.jsonl` holds 6 batches:
  - *2023 Selections: 15 New Discoveries* (2026-10-28): 15 songs. Every song has a `why`, two
    `like` songs, an album, and a year. The `request` is 203 characters.
  - *Sam Fender — Manchester 2027 Catch-Up* (10) and *Soft Vocals: Where's the Edge?* (12):
    every song has a `why`. Neither has `like` songs. *Soft Vocals* has no albums or years.
  - *Rolling Stone's 200 Best Rock Songs of the 21st Century* (200): no `why`. 66 songs are
    `familiar`.
  - *2024 Selections: 15 New Discoveries* (2026-10-26, staged before M18 S2): no `why`, no
    `request`, no album.
  - One `new-music-picks` batch (2026-10-30): 25 songs, 9 `picked`, no `playlist`, no `why`.
  - Every `why` runs 96 to 167 characters. All 30 `like` songs are `found: library`.
- **Familiar songs say why.** `reasons` holds `owned`, `heard`, `noted`, `recommended`, and
  `playlist:<role>` (in the file: `owned` 77, `playlist:curated` 10, `playlist:collection` 9,
  `playlist:replay` 8, `playlist:keepers` 6, …). `familiar: false` means new to Jon when it
  was staged.
- **The playlists are still in the library.** `playlist-roles.json` labels 7 playlists
  `vinyl-fever`, including all five staged names. The feedback guide tells Jon he may delete a
  playlist when he's done with it, so one can disappear.
- **Ledger lines carry no IDs.** S0 showed catalog and library IDs swap for the same song, so
  M20 matches on title and artist (`MusicFeedback.matches`).
- **New Music picks are blind.** The chat records its picks before Jon listens, and he asks it
  not to tell him until the week is over (M18 Decision 1, the feedback guide).
- **The app today** is one setup `Form` (`VinylFeverMobileApp.swift`). It has the folder
  bookmark (`ProbeBookmarkStore`), the coordinated ledger reader with its 8-second deadline
  (`RecommendationLedgerFolderReader`), and the note writer for
  `notes-feedback-<device>.jsonl` (`FeedbackNoteSaver`, `TasteNotesCodec.appendFeedbackNote`).
  Its code uses static enums with closures passed in. `swift-dependencies` is already a package
  in `project.yml` (the Mac app uses it), but the mobile target doesn't link it.
- **Note sources are free text.** `taste_notes` and `check_tracks` read any `source`, so a new
  value needs no Mac change.

## Shared rules (every slice)

- **Nothing on the Mac changes.** No `vf-mcp`, Mac app, or format change. The ledger is read
  only; nothing on the phone writes it.
- **The library doesn't change.** The view never adds, removes, or edits a song or a playlist.
  From S2 on, it drives the player (Decision 1).
- **New Music picks aren't listed** (Decision 4). Only `staged-playlist` batches appear.
- **M20's intents don't change.** Music Feedback and Why This Song behave exactly as they do
  today. The probe intent stays until M20 S1's gate passes (M20 Decision 10).
- **House stack.** An `@Observable` model per screen, a `Destination` enum for sheets, and
  dependency clients (`@DependencyClient`) for the ledger folder, the library, the player, and
  the clock. Link `swift-dependencies` to the mobile target. No SwiftData, and nothing new is
  persisted.
- **Logic that needs no MusicKit lives in `VinylFeverNotes`,** Foundation only, so it's tested
  on macOS, as M20 S2's answer logic is.
- **Tests never touch live paths.** The folder, the library, the player, and the clock are
  injected. Tests use temp folders and fixtures.
- **Default system styling.** Lists, sections, and SF Symbols, with album artwork from S2. A
  Vinyl Fever look comes once the structure is proven (Decision 8).

## Slices

**Dispatch 1: S1** (the list and the reasons). **Dispatch 2: S2** (artwork and playback).
**Dispatch 3: S3** (notes). Each completing PR advances `NEXT_UP.md` to the next slice. They
don't wait on Jon's gates. The gates can run in one sitting after S3, or one at a time if Jon
wants to see S1 sooner.

- [x] **S1 — The playlists and their reasons.**
  - **The home screen.** The app opens on **Playlists**, in a `NavigationSplitView`: the
    playlists are the sidebar list, and the selected playlist is the detail. On iPhone it
    collapses to a stack. Today's setup `Form` moves, unchanged, into a **Setup** sheet opened
    from a toolbar button. Its M20 test buttons keep working.
  - **The list.** One row per `staged-playlist` batch, newest `recordedAt` first. A playlist
    staged twice is two rows. Each row shows:
    - the `playlist` name, or "Staged playlist" when it has none;
    - the date staged, as M20 S2 says it ("October 28", with the year only when it isn't this
      year), in the device's time zone;
    - the song count, and how many are new to Jon (`familiar: false`).
  - **The playlist.** A header, then the songs in ledger order.
    - **The header:** the name, the date, and the counts. Then the `request` in full, under
      "You asked", when there is one. M20 Decision 13 kept it out of Siri's answer and promised
      it here.
    - **Each song:** the title and artist; the album and year when present; one familiarity
      line (below); the `why` in full; and, when there are `like` songs, a "Sounds like"
      group listing each as title and artist.
    - **Familiarity line.** `familiar: false` reads "New to you". A familiar song reads its
      first reason by this order: `playlist:keepers` "You kept it", `owned` "In your library",
      `playlist:<role>` "In a <role> playlist" (`unlabeled` reads "In one of your playlists"),
      `heard` "You've heard it", `noted` "You left a note on it", `recommended` "Recommended
      before". A familiar song with no reasons reads "You knew it".
    - **No reasons.** A playlist where no song has a `why` ends its header with "No reasons
      were recorded for this playlist." Songs without a `why` show no reason line.
  - **Reading.** The model reads the ledger through the existing
    `RecommendationLedgerFolderReader` (same deadline) on appear and on pull to refresh, off
    the main actor.
    - Some files unreadable: the list shows what was read, with a banner: "Some
      recommendations are still downloading from iCloud. Pull to refresh."
    - No folder access: an empty state saying "Grant folder access in Setup", with a button
      that opens the Setup sheet.
    - Nothing staged: "No Vinyl Fever playlists yet. Ask the chat for some."
  - **The shared logic (`VinylFeverNotes`).** A `PlaylistShelf` (or similar) that turns a
    `RecommendationLedgerReadResult` into the list rows and playlist sections: filtering out
    `new-music-picks`, sorting, counts, the familiarity line, and the date. Move the date
    phrase out of `WhyThisSong` so both use one function; Why This Song's golden strings stay
    unchanged.

  **DoD:**
  - **Package tests:** a ledger fixture shaped like today's file (a batch with `why` and
    `like`, one with `why` and no `like`, one with neither, one with no `playlist` or
    `request`, and a `new-music-picks` batch). The list order, counts, and the picks batch
    left out. Each familiarity line, including the order when several reasons apply, an
    `unlabeled` playlist, and familiar with no reasons. The no-reasons header line. The date in
    this year and last year. Why This Song's existing tests pass unchanged.
  - **App tests:** the model with the ledger client stubbed: loaded, partly unreadable (the
    banner), no folder access (the empty state), and nothing staged. Pull to refresh reads
    again. The Setup sheet opens through the `Destination` enum.
  - **Builds:** iOS Simulator and device. The Mac app, Core, Listening, and `VinylFeverNotes`
    suites pass.
  - **Jon's gate (on the iPad and the iPhone):**
    1. The list shows the five staged playlists, newest first, and no New Music picks.
    2. *2023 Selections: 15 New Discoveries* shows "You asked" with the request, a `why` on
       every song, two "Sounds like" songs on each, and "New to you".
    3. *Rolling Stone's 200 Best Rock Songs…* shows familiarity lines such as "In your
       library", and "No reasons were recorded for this playlist."
    4. Setup opens from the toolbar, and Test Why This Song still answers.

- [ ] **S2 — Artwork and playback.**
  - **Find the songs (Decision 3).** When a playlist opens, resolve each ledger song to a
    MusicKit `Song`, in this order:
    1. **The staged playlist.** A library playlist whose name equals `playlist` exactly. If
       exactly one matches, load its tracks and match each ledger song by title and artist
       (`MusicFeedback.matches`). If none or several match, skip to step 2 for every song.
    2. **The library.** A library song request by title, then match the artist.
    3. **The catalog.** A catalog search for "title artist", songs only, the first results
       (Constants), then match title and artist.
    4. **Not found.** The row says "Not in Apple Music" and has no play button.

    Resolve on demand, not all 200 songs up front: the visible rows and the next screenful.
    Keep results in memory for the session.
  - **Artwork.** A resolved song shows its artwork beside the title. The header shows the
    playlist's artwork when step 1 found it.
  - **Play (Decision 2).** Through `SystemMusicPlayer`, so playback continues in Music, on the
    Lock Screen, and in CarPlay, and the plays reach recently played and the listening log.
    - **Tap a song:** when step 1 found the playlist, queue the playlist starting at that
      song. Otherwise queue the playlist's resolved songs in ledger order, starting at that
      song. Then play.
    - **Tap a "Sounds like" song:** resolve it (library, then catalog), insert it after the
      current entry, and skip to it. The playlist carries on after it. A long press offers
      **Play Next** instead, which inserts it without skipping.
    - **Play All** in the header: the same as tapping the first song.
  - **Now playing.** The row of the song the player is on shows a playing indicator, matched by
    title and artist. It updates as the queue moves.
  - **Music access.** If MusicKit isn't authorized, rows show no artwork or play buttons, and
    the header says "Allow Apple Music access in Setup". The reasons still show.

  **DoD:**
  - **App tests,** with the library, catalog, and player clients stubbed:
    - resolution order: found in the playlist; the playlist is missing; two playlists with the
      name (step 2 for all); found in the library only; catalog only; not found;
    - matching across case and diacritics, and a library ID against a catalog ID for the same
      song;
    - tapping a song with and without the playlist queues the right songs, starting at the
      right one;
    - a "Sounds like" tap inserts after the current entry and skips; Play Next doesn't skip;
    - the now-playing row follows the stubbed player's current entry;
    - not authorized: reasons still show, and no play button.
  - **Builds:** iOS Simulator and device. All suites pass.
  - **Jon's gate:**
    1. *2023 Selections* shows artwork on every song. Tap the fifth song: Music plays the
       playlist from it, and the row shows it's playing.
    2. Tap a "Sounds like" song: it plays now, then the playlist carries on.
    3. Lock the phone mid-song. The Lock Screen shows it, and the next song follows.
    4. *Rolling Stone's 200…* scrolls without stalling. Note any "Not in Apple Music" rows and
       what they are (the input to Decision 3's destination).
    5. Rename *Soft Vocals: Where's the Edge?* in Music and reopen it in Vinyl Fever: its songs
       still play, from the library or the catalog. Rename it back.
    6. After the next hourly poll, `recent_listening` in a new chat shows the songs played from
       the app.

- [ ] **S3 — Notes from the playlist.**
  - **Leave a note.** Each song row has a **Note** button. It opens a sheet with the song's
    title and artist and a text field. The keyboard's dictation works there. **Save** writes a
    `vf-taste-note` v1 line through `MusicFeedback.makeNote`, with `source: playlist`, to the
    device's existing `notes-feedback-<device>.jsonl` (Decision 6). Empty or "Cancel" saves
    nothing, by the same guard as Music Feedback. A "Sounds like" song can't take a note; the
    note goes on the playlist's song.
  - **The note's song.** Title, artist, and album from the ledger. The catalog ID, play count,
    release date, and duration from the resolved `Song` when S2 found one, else omitted.
  - **Your notes.** Under a song's `why`, show Jon's notes on it from every `notes*.jsonl` in
    `Taste Intelligence/` (the shortcut, Music Feedback, the chat), newest first, matched by
    title and artist: the date and the text, word for word. Read through the existing
    coordinated reader, with the same deadline and the same unreadable banner. A saved note
    appears without a refresh.
  - **No folder access** at save: "Open Vinyl Fever to grant folder access", as Music Feedback
    says it, and nothing is written.
  - **The evidence file isn't written.** The song is known, so there's nothing to diagnose.

  **DoD:**
  - **Package tests:** a note with `source: playlist` encodes with the shortcut's keys, plus
    `catalogID` when present; matching notes to songs across files, newest first, ignoring
    time-only notes.
  - **App tests:** save writes one line to a temp folder through coordination; empty and
    "Cancel cancel" write nothing; no bookmark returns the folder message; a saved note shows
    under its song; notes from two files merge newest first.
  - **Mac:** a `vf-mcp` test that `taste_notes` over a folder holding a `source: playlist` line
    returns it.
  - **Builds:** iOS Simulator and device. All suites pass.
  - **Jon's gate:**
    1. Leave a typed note and a dictated note on two songs in *2023 Selections*. Both show
       under their songs.
    2. In a new chat, `taste_notes` shows both word for word, on the right songs.
    3. A song Jon noted earlier through Music Feedback shows that note.
    4. "Cancel" saves nothing.

## Constants register (starting values)

| Constant | Value | Why |
| --- | --- | --- |
| Batches listed | every `staged-playlist` batch, newest first | Five today; no cap until it's a long list |
| Ledger read deadline | M20 S2's 8 seconds, then pull to refresh | One reader; a banner beats waiting |
| Song match | M20's: title and artist, trimmed, case- and diacritic-insensitive | The ledger has no IDs (S0) |
| Playlist match | exact name, exactly one | Two with the name can't be told apart without IDs |
| Catalog search results | first 5 | Enough for a remaster or a live version to sort below the original |
| Resolve ahead | the visible rows plus one screenful | 200 songs shouldn't mean 200 requests up front |
| Note `source` from the view | `playlist` | Tells a sit-down note from a voice note; any source is read |

## Out of scope — with destinations

- **A Keep button** (file the song into Vinyl Fever Keepers or its year's Selections). → A
  probe after S2's gate, if Jon wants it. Filing is the whole keep signal (feedback guide), so
  it would be the best button here. But it writes the library, and it isn't known whether
  MusicKit can add to a playlist the app didn't create.
- **Heard, kept, and passed on each song.** → After this milestone, if Jon wants it. It needs
  keepers membership and the listening log on the phone. M18's outcomes report it on the Mac
  today.
- **Past New Music weeks with the chat's picks.** → Only after each week's 14-day window, so
  it can't spoil the blind test (Decision 4). If Jon asks.
- **Catalog IDs on new ledger lines.** → If S2's gate step 4 finds misses (M20's parked item).
- **A note on a whole playlist** ("this one's too samey"). → If Jon wants it. It needs a
  `playlist` key on the note, which is a format change.
- **Opening the view from Why This Song,** at the song Siri named. → After S3, if wanted.
- **A Vinyl Fever look** (a mockup, then a theme and a visual slice). → After S3's gate
  (Decision 8).
- **Removing the probe intent.** → Still M20's: the first slice after M20 S1's gate.

## Decisions

Added 2026-10-30 with M21. Merging this plan PR approves them.

1. **The app gets a screen for sitting down; the intents stay hands-free (Jon, 2026-10-30).**
   M20's "screens are for setup only" and "read the player, don't drive it" were M20's scope,
   not the app's. They still hold for the intents. The view drives the player, as the Platform
   Stance allows ("drives Music's queue"). It doesn't touch the library.
2. **Play through the system player.** Plays from the app have to reach recently played,
   because that's how the listening log, and so M18's outcomes, see a song as heard. They should
   also carry on in Music, on the Lock Screen, and in CarPlay. The app's own player would keep
   its queue separate from Music's. S2's gate step 6 checks the log.
3. **Find songs through the staged playlist first.** The ledger has no IDs, and S0 showed IDs
   swap. The staged playlist holds the exact versions the chat chose, so its tracks are the best
   match. The library and the catalog cover a deleted or renamed playlist.
4. **New Music picks aren't listed.** The chat's picks are a blind test of its judgment on new
   releases (M18 Decision 1). A list would show every pick before Jon listens. Why This Song
   still answers about a picked song when Jon asks about that one song.
5. **No library writes yet.** Filing in Music stays the keep signal. A Keep button waits for a
   probe (Out of scope).
6. **Notes from the view go in the device's existing `notes-feedback-<device>.jsonl`.** One
   app on one device appends to it, with coordination, so M20 Decision 1's one writer per file
   still holds. `source: playlist` tells these notes from voice notes, and the Mac reads any
   source.
7. **S1 is dispatched now, before M20's gates.** The executor is idle, and S1 only reads. If
   the ledger reader fails on a device, M20 S2's gate finds it, and one fix serves both.
8. **Structure first, look later.** House process (`ui-and-platforms.md`, *Visual craft*):
   build the behavior in default styling, prove it on device, then make a mockup and a
   Vinyl Fever theme. Polishing a screen whose structure may still move is wasted.
