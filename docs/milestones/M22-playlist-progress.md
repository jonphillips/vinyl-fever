# Milestone 22 — Where each playlist stands: heard, kept, and archived

*Show Jon, in the app's playlist view, how far he's got with each playlist and what happened to
each song, give the song actions room, and set his own words apart from the chat's. Playlists he
deletes in Music move to an archive. It builds on [M21](archive/M21-playlists-view.md), whose
Shared rules still apply except where Decision 3 adds a library read. Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply, and the screens follow jon-platform
`docs/ios/ui-and-platforms.md`. Where this doc and those conflict, stop and flag it.*

Status: Planned
Summary: S1 gives the song actions their own row and sets Jon's words in serif italic, S2 shows heard, kept, and passed on every song and a progress bar on every playlist, S3 moves playlists deleted in Music into an Archived segment, and S4 tells Jon's words from the chat's: the request is recorded word for word, and the chat's own description shows in its own type.

M21 built the audition view in default styling and parked "heard, kept, and passed on each song"
for after it. Jon used it and asked for four things (2026-10-31):
1. A bar on each playlist for how much he's listened to and how much he's reacted to.
2. A status on each song: kept, or heard and not kept.
3. More room for the action buttons, and a nicer treatment.
4. His own words in a different type from the chat's.

He picked from mockups: **1B** (one stacked bar), **2A** (a pill under the song), **3A**
(labeled capsule buttons on their own row), and **4A** (serif italic with a leading rule). He
then asked for playlists he deletes in Music to archive themselves, behind a segmented control.

## The milestone in one sentence

Jon opens Vinyl Fever and sees, for each playlist, a bar of what he's heard and what he kept, and
on each song whether he kept it, passed on it, or hasn't heard it. His own words read as his,
and the playlists he's deleted in Music wait under Archived.

## What's true today (architect, read-only, 2026-10-31)

- **The song row crowds its actions.** `PlaylistSongView` puts Note (a pencil), Play, and Keep
  on the title's line, at the trailing edge, as icon-only buttons except Keep.
- **"Kept in…" only knows this session.** `PlaylistKeepModel.keptPlaylistsBySong` is filled by
  `save()`. A song kept in Music, or kept in the app yesterday, shows nothing.
- **The phone can already reach the listening log.** The bookmark is the `Vinyl Fever` folder.
  `TasteFolderReader` appends `Taste Intelligence`, and the log sits beside it at
  `Listening/fetches/<poller>/<yyyy-MM>.jsonl`, 364 KB in all today. The code that turns fetches
  into plays (`ListeningLog`, `ListeningLogCodec`, `ListeningModels`, `ArtistIdentity`) is
  Foundation-only. It lives in `VinylFeverListening`, whose package is macOS 15 only.
- **The Mac's rule for kept and passed** (`TasteIntelligence.classify`, behind
  `kept_and_passed`): kept means in a playlist whose role is `keepers`. Passed means heard and
  not kept. The phone's Keep sheet already reads the roles and keepers' track lists
  (`KeepLibraryClient.readRoles`, `.tracks`).
- **A playlist is matched only when it's opened.** `PlaylistPlaybackModel` looks for exactly one
  library playlist with the batch's exact name, when the detail appears. The list doesn't know
  whether a playlist still exists.
- **Jon may delete a playlist when he's done.** The feedback guide says so ("Nothing depends on
  it after staging"). MusicKit has no call to delete a playlist, so deleting happens in Music.
- **A deleted playlist still lists.** The list comes from the ledger, so a deleted playlist keeps
  its row. Its songs still play through M21 S2's library and catalog fallback, but it has no
  artwork.
- **Jon's words today:** the `request` under "You asked", and his notes under a song (M21 S4),
  are set in the body font, like the chat's `why`.

## Shared rules (every slice)

- **Nothing on the Mac changes,** except in S4 (Decision 8). No `vf-mcp`, Mac app, or format
  change. Nothing new is written anywhere. Status and the archive are worked out on each load,
  never stored (Decision 3).
- **The library changes only through Keep,** as in M21. Reading playlists, keepers' tracks, and
  the listening log is read-only.
- **Same matching as M21:** title and artist through `MusicFeedback.matches`.
- **Logic that needs no MusicKit lives in `VinylFeverNotes`,** Foundation only, tested on macOS.
- **House stack, as M21:** `@Observable` models, dependency clients, injected folder, library,
  and clock. Tests never touch live paths.
- **The mockups are the reference.** The four picked concepts are described in each slice. When
  a detail isn't covered, use system styling (`.bordered` buttons, semantic colors), not custom
  drawing.

## Slices

**Dispatch 1: S1** (the look). **Dispatch 2: S2** (heard, kept, and passed). **Dispatch 3: S3**
(the archive). **Dispatch 4: S4** (whose words; added by Jon 2026-10-31). Each completing PR
advances `NEXT_UP.md`. They don't wait on Jon's gates.

- [x] **S1 — Room for the actions, and Jon's words in his own type.** *(Mockups 3A and 4A.)*
  - **The action row (3A).** The title line holds only the title and the now-playing indicator.
    Below the album and year line, a row of capsule buttons with icon and label: **Play**
    (`play.fill`), **Keep** (`bookmark`), **Note** (`pencil`). Use `.buttonStyle(.bordered)`,
    `.buttonBorderShape(.capsule)`, 8 pt between buttons, and leave the row's top spacing
    larger than the lines above it. Use the default control size: `.large` needs 317 pt on an
    iPhone 18 Pro, where the row has 288 pt (architect's probe on #169). When the labeled row
    doesn't fit, as at larger text sizes, fall back to the same buttons icon-only (`ViewThatFits`).
    - **Kept:** when the song is kept (this session in S1, for real from S2), Keep reads
      **Kept** with `checkmark`, tinted green. It still opens the Keep sheet, so Jon can file the
      song into another keepers playlist.
    - **Finding:** while S2's resolution runs, Play and Keep are one small progress view, and
      Note is still there.
    - **Not in Apple Music:** the row shows that text in place of Play and Keep. Note stays.
    - **No Music access:** Note only, as today.
    - The accessibility labels stay as they are ("Play <title> by <artist>", and so on).
  - **Jon's words (4A).** The `request` under "You asked", and each of his notes under a song,
    use `.fontDesign(.serif)` and `.italic()`, with a 2 pt leading rule in the secondary style
    and 8 pt between the rule and the text. Labels ("You asked") and note dates stay in the
    body font. The chat's `why` and everything else stay in the body font, so the change of
    type is the change of speaker.

  **DoD:**
  - **App tests:** none required beyond the suites passing, unless the Keep button's kept state
    is moved into a model. Then a test that it reads Kept after a save.
  - **Builds:** iOS Simulator and device. All suites pass.
  - **Jon's gate (iPhone and iPad):**
    1. In *2023 Selections*, the title has the full width, and Play, Keep, and Note sit on their
       own row as labeled capsules.
    2. Keep a song: its button reads Kept, in green.
    3. "You asked" and a note read in serif italic beside a rule. The `why` doesn't.

- [x] **S2 — Heard, kept, and passed.** *(Mockups 2A and 1B.)*
  - **Each song's status (Decision 1, 2, 6).** Worked out per playlist, from the playlist's
    `recordedAt`:
    - **Kept:** the song is in a keepers playlist, whenever it got there. The keepers playlists
      are the `keepers` names in `playlist-roles.json`, matched by exact name to library
      playlists, editable or not. Without the roles file, Vinyl Fever Keepers and the
      Selections pattern, as M21 S3's fallback does.
    - **Passed:** not kept, and heard after `recordedAt`: a play in the listening log whose
      window ends at or after `recordedAt`, a note on the song dated at or after `recordedAt`,
      or both. A note counts as hearing it.
    - **Not heard yet:** neither.
    - **With feedback:** kept, or a note on the song dated at or after `recordedAt`.
  - **The pill (2A).** Under the artist line, a capsule with the status:
    - Kept: green, `checkmark`, "Kept · Vinyl Fever Keepers and 2023: Jon's Selections"
      (every keepers playlist holding it, by name). This replaces M21 S3's "Kept in…" line.
    - Passed: red tint, "Passed".
    - Not heard yet: an outline in the secondary style, "Not heard yet".
  - **The playlist bar (1B).** Under each list row's date and counts, one 8 pt capsule bar the
    width of the row, in four segments, left to right:
    1. kept (green);
    2. passed with feedback, so a note (red tint);
    3. passed with no feedback (secondary gray);
    4. not heard yet (the empty track).

    The filled length is how much he's heard, and the colored part is how much he's reacted
    to. Under it, one caption line: "12 of 15 heard · 10 with feedback". The same bar and line
    head the playlist's detail, under the counts. Accessibility: one label, "12 of 15 heard, 8
    kept, 10 with feedback".
  - **Reading.** On the list's load and pull to refresh, off the main actor, with the existing
    reads: the library playlists, the keepers' tracks (`KeepLibraryClient.tracks`), the notes
    (M21 S4's reader), and the listening log months from the oldest listed playlist's
    `recordedAt` to now. A Keep save or a saved note updates the song and its bar without a
    refresh.
  - **Missing evidence.** If the keepers or the log can't be read, or Music isn't authorized,
    show no pill and no bar. Don't show a partial status. The existing "still downloading from
    iCloud" banner covers an unreadable log file.
  - **The log reader moves to `VinylFeverNotes`** (Decision 4): `ListeningLog`,
    `ListeningLogCodec`, `ListeningModels`, and `ArtistIdentity`. `VinylFeverListening` then
    depends on `VinylFeverNotes` and re-exports it, as Core does, so no call site changes. If a
    moved type needs more than Foundation, or the move pulls in the poller, stop and report what
    blocks it.
  - **The rule lives in `VinylFeverNotes`:** a pure function from the playlist's songs and
    `recordedAt`, the keepers' track lists by name, the plays, and the notes, to each song's
    status and the playlist's four counts.

  **DoD:**
  - **Package tests:** a song in Vinyl Fever Keepers is kept, with that name; a song in two
    keepers playlists lists both; a play before `recordedAt` doesn't count as heard, and one
    after does; a note after `recordedAt` makes an unheard song passed with feedback; a note
    before `recordedAt` doesn't; a kept song with no play is kept; the four counts add up to
    the song count. The moved log reader's existing tests pass unchanged in their new home, and
    the Listening and Core suites pass.
  - **App tests,** with the clients stubbed: statuses and bar counts for a fixture playlist; a
    Keep save turns a song Kept and moves the bar; a saved note turns an unheard song Passed;
    no pill or bar when the log read fails, when the roles and keepers reads fail, and without
    authorization.
  - **Builds:** iOS Simulator and device. All suites pass.
  - **Jon's gate:**
    1. *2023 Selections*: the bar and its line match what Jon remembers hearing and keeping. A
       song he kept in Music, not in the app, reads Kept with its playlists.
    2. A song he played and didn't keep reads Passed. One he hasn't played reads Not heard yet.
    3. Play a new song from the app through to the end. After the next hourly poll, pull to
       refresh: it reads Passed, and the bar grew.
    4. In a new chat, `kept_and_passed`'s kept songs for a recent week agree with the app's
       Kept, where the same song is in both.

- [ ] **S3 — The archive.** *(Jon, 2026-10-31.)*
  - **Archived (Decision 3, 5).** A playlist is archived when all of these hold:
    - Music is authorized, and the library playlists were read;
    - the batch has a `playlist` name, and no library playlist has exactly that name;
    - it was staged more than the grace period ago (Constants).

    Anything else is active, including a batch with no name, a name two playlists share, and
    every playlist when the library read fails. Worked out on each load, with S2's library read.
  - **The segmented control.** Above the list, a `Picker` in `.segmented` style: **Active** and
    **Archived**, each with its count ("Archived 2"). Active is the default and is where the
    app opens. Switching clears a selection that isn't in the new segment. On iPad, the first
    playlist of the segment is selected, as today.
  - **Empty Archived:** "Playlists you delete in Music move here."
  - **An archived playlist** opens as any other, with one line under the header's counts: "No
    longer in your Music library." Its songs still play through M21 S2's library and catalog
    fallback, and Keep, Note, and S2's status work as they do on an active playlist.
  - **Coming back.** If Jon recreates the playlist with the same name, or renames one to it,
    the next load lists it as active again.

  **DoD:**
  - **Package tests** for the archive rule: name present, active; absent and past the grace,
    archived; absent and within the grace, active; two with the name, active; no name, active;
    library not read, all active.
  - **App tests:** the counts in each segment; switching segments clears a selection that isn't
    there; the archived header line; the empty Archived message.
  - **Builds:** iOS Simulator and device. All suites pass.
  - **Jon's gate:**
    1. Delete a staged playlist you're done with in Music. Pull to refresh: it's under
       Archived, with "No longer in your Music library", and its songs still play.
    2. Have the chat stage a new playlist. It's under Active straight away, even before iCloud
       brings it to the phone.
    3. Active opens by default, and the counts on the control are right.

- [ ] **S4 — Jon's words and the chat's, told apart.** *(Jon, 2026-10-31.)*
  - **Why.** S1 set the `request` under "You asked" in Jon's serif italic. On S1's review Jon
    saw the chat's words in his style. Of the four requests in the ledger, only *2023
    Selections* is his ("Find me 15 new discoveries…"). The other three are the chat's summary
    of its own plan, in the third person: "Find 10 Sam Fender songs Jon has not listened to yet
    …", "Cross-checked against … Blunt Magazine", "Build a diagnostic range …". The server
    instructions say "Jon's request as request", never word for word, and the `request` field
    has no description in `stage_playlist`'s schema.
  - **`vf-mcp` (Decision 8).**
    - `request`: the schema says "Jon's message asking for this playlist, word for word,
      including how he said it. Never a summary or your plan." The server instructions say
      "Jon's request word for word as request".
    - `description` becomes required, and the ledger line records it as `description`, beside
      `request`. It's already the chat's one sentence about the music, the one that becomes the
      playlist's description in Music (`stageDescriptionGuidance`). It's an added optional key,
      so the format version stays 1, and older readers ignore it.
    - A test that a staged batch's ledger line holds both, word for word.
  - **The app.**
    - **A line with `description`** (recorded by the new `vf-mcp`): "You asked" with the
      `request` in Jon's style, as in S1. Above it, under the name, the `description` in the
      chat's style: the body font, secondary, no rule and no italic, as the `why` is.
    - **A line without `description`** (older lines): the `request` shows under the label
      "Request", in the body font with no rule. Nothing says whose words they were, so nothing
      claims they were Jon's.
    - Notes stay in Jon's style. Every note is meant to be his words. The chat records them
      word for word by its instructions.
  - **The shared logic (`VinylFeverNotes`):** `RecommendationBatch` gains `description:
    String?`. A function decides which header the batch gets, so the rule is tested on macOS.

  **DoD:**
  - **Package tests:** a batch with `description` decodes it; a line without it still decodes;
    the header rule for both.
  - **Core tests:** `stage_playlist` without `description` is refused with a message saying
    it's required; with it, the ledger line holds `request` and `description` as sent.
  - **App:** the two header styles, with the S1 styling for Jon's words.
  - **Builds:** iOS Simulator and device, and the Mac app. All suites pass.
  - **Jon's gate:**
    1. Install the Mac build and start a new chat (it caches the tool list). Ask it for a
       playlist. In the app, "You asked" reads exactly what you typed, and the chat's sentence
       sits above it in plain type.
    2. *Sam Fender — Manchester 2027 Catch-Up* shows its request under "Request", in plain
       type.

## Constants register (starting values)

| Constant | Value | Why |
| --- | --- | --- |
| Heard | a log play whose window ends at or after `recordedAt` | The Mac's evidence (Decision 1); plays from before staging don't say anything about this playlist |
| Feedback | kept, or a note dated at or after `recordedAt` | Jon's definition: kept or commented |
| Keepers | the `keepers` names in `playlist-roles.json`; else Vinyl Fever Keepers and Selections | M21 S3's rule, and what the Mac counts as kept |
| Log months read | from the oldest listed playlist's `recordedAt` to now | 364 KB in all today; nothing older can count |
| Archive grace | 24 hours after `recordedAt` | iCloud can take a while to bring a new playlist to the phone (M18 S7) |
| Bar | 8 pt capsule; kept, passed with feedback, passed, not heard | Mockup 1B |

## Out of scope — with destinations

- **Archiving by hand, without deleting in Music.** → If Jon wants it. It needs a file of hidden
  playlists, which is new state (Decision 3).
- **Deleting a playlist from the app.** → Not possible: MusicKit can't delete a playlist.
- **"Pending" for New Music weeks.** → Not here. The Mac's 14-day window is for blind New Music
  tests, which this view doesn't list (M21 Decision 4).
- **Telling a skip from a listen.** → The log counts starts (M13 *Fidelity*). Parked in
  `open-questions.md` under listening analytics.
- **A Vinyl Fever theme** (color, type, and icon beyond these four picks). → Still M21
  Decision 8's, after these gates.

## Decisions

Added 2026-10-31 with M22. Merging this plan PR approves them.

1. **Heard means the listening log, as on the Mac.** The app could read `lastPlayedDate` from
   MusicKit instead, and it would update sooner. But it only exists for library songs, it isn't
   proven on playlist tracks, and it would disagree with `kept_and_passed`. One definition of
   heard on both devices is worth an hour's lag.
2. **Kept is read from the keepers playlists, not remembered.** S3 of M21 only knew this
   session's saves. A keep made in Music is the same keep, so the app reads the playlists.
3. **Status and the archive are worked out, never stored.** Everything they need is already on
   iCloud Drive or in the library. Deleting a playlist in Music is the archive gesture, so the
   app keeps no list of its own, and undoing it is recreating or renaming the playlist.
4. **The log reader moves to `VinylFeverNotes`,** as M21 S3 moved the roles codec. Its types are
   Foundation-only, and the alternative, building `VinylFeverListening` for iOS, would pull the
   poller and its Mac-only code along.
5. **A grace period before archiving.** A playlist the Mac just made may not be on the phone
   yet. Without the grace, a new playlist would land in Archived until iCloud caught up.
6. **"Passed", not "rejected" (architect, 2026-10-31).** Jon asked for "rejected (listened but
   not kept)". Passed is the Mac's word for the same thing, and it isn't final: an unkept song
   stays in the staged playlist and can still be kept.
7. **S1 is dispatched before M21's gates,** as M21 Decision 7 did. It changes layout only, and
   M21's gates can run on the new layout.
8. **S4 changes `vf-mcp` and adds a ledger key (Jon, 2026-10-31).** The app can't tell from the
   text whose words a request is. So the source records the difference: the request word for
   word, and the chat's own sentence as `description`. The key is optional and additive, so
   the ledger stays version 1, and M18's outcomes read the file unchanged.
9. **Older requests aren't attributed.** Sorting them by whether they name "Jon" would misplace
   the Rolling Stone line, whose wording could be either speaker's. So without `description`, a
   request shows plainly under "Request". The one real loss is *2023 Selections*, whose request
   was Jon's and now loses his style.
