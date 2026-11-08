# Milestone 24 — The phone finishes what the chat starts

*Give the iPhone and iPad app a player strip and a Noted state, then let Jon create a staged
playlist in Music from the phone, with the Mac's matching and the Mac kept in step. Rules in
[../technical-architecture.md](../technical-architecture.md), jon-platform `AGENTS.md`, and
jon-platform `docs/ios/ui-and-platforms.md` (§ Controls) apply. Where this doc and those
conflict, stop and flag it.*

Status: Designed
Summary: S1 adds a Music-style player strip to the phone app and S2 marks songs that already have a note; S3 moves the Mac's song matching and Apple Music calls into a shared package and has the stage tool record what the phone can't know; S4 adds a creation record that every creator writes and the Mac files its inbox from; S5 lets Jon create a staged playlist in Music from the phone.

Jon asked for this on 2026-11-08:
1. Simple player buttons in the phone app (previous, play/pause, next) on a strip at the
   bottom, like the Music app.
2. A way to finish a staged playlist on the phone. In his words, Vinyl Fever "started off as Mac
   only because its primary function was to manage the hard drive library attached to my Mac",
   and it has become "Jon's music HQ". He wants to ask ChatGPT for a playlist on the go and
   "finalize it in the mobile app without have to remote into the desktop". The Mac "does need to
   stay fully synced and clearly manage many things".
3. The note button should show whether a song already has a note.

## The milestone in one sentence

Jon asks the chat for a playlist while he's out, opens Vinyl Fever on his phone, creates it in
Music with the same matching the Mac uses, and plays it from a strip at the bottom of the screen.
When he's back at the Mac, its inbox already shows the playlist as created on the iPhone.

## What's true today (architect research, 2026-11-08)

**The phone already has every staged playlist.** `stage_playlist` writes the `.vfplaylist` to the
Mac-only inbox (`~/Library/Application Support/VinylFever/PlaylistInbox`) and appends the batch,
with every song's title, artist, album, and year, to the iCloud recommendation ledger. The phone
lists staged playlists from that ledger. The inbox file's timestamp is the batch's `recordedAt`,
so an inbox item and its ledger batch pair exactly (with the batch's `host`).

**The phone already writes to the library.** Keep appends songs through
`/v1/me/library/playlists/{id}/tracks` with `MusicDataRequest`, and
`AppleMusicPlaylistRequestEncoder`, in `VinylFeverNotes`, already builds the create body the
Mac sends.

**The Mac labels the playlist without help.** At every snapshot load,
`PlaylistRoleAutoLabeling.applyVinylFeverRole` labels any library playlist whose name is in the
ledger `vinyl-fever` (`PlaylistRoleBannerModel.recommendationPlaylistNames`). So a playlist the
phone creates gets its role on the Mac's next snapshot, and the phone never writes
`playlist-roles.json`.

**What the phone is missing:**
- **The Mac's matching.** `CatalogMatchScorer`, `CatalogMatchResolver`, and
  `LibraryUploadMatcher` live in `VinylFeverCore`, which the phone doesn't link. They only need
  `ListeningTextNormalizer` and `ArtistIdentity`, which are already in `VinylFeverNotes`; the
  `VinylFeverListening` import is just its re-export. `TrackRequest` sits in
  `PlaylistContract.swift`, which imports `LLMHandoffKit`, so it has to be split out. The live
  client (`VinylFever/Clients/AppleMusicCatalogClient+Live.swift`, 252 lines of MusicKit and
  `MusicDataRequest`) is in the Mac app target, but every call it makes also exists on iOS.
- **Two Mac-only inputs.** The library snapshot decides which songs take the upload route
  (`LibraryIndex.shouldUseLibraryRoute`), and the artist aliases build `ArtistIdentity`. Both
  live in `~/Library/Application Support/VinylFever/LibrarySnapshot/`, which doesn't sync. The
  snapshot is far too big to send to the phone, and the stage tool already has both when it
  stages.
- **A difference between "not created" and "deleted".** `PlaylistArchive` archives a staged
  playlist that has been missing from the library for 24 hours. Today that means Jon deleted it.
  Once the phone can create playlists, a playlist he hasn't created yet would be archived too.

**The phone's player.** `PlaylistMusicClient` already drives `SystemMusicPlayer` (play a
playlist, play songs, insert, play) and streams the current entry for the waveform marker. It has
no transport controls and doesn't read the playback state.

**Notes on songs.** `PlaylistTasteNotesModel.notes(for:)` already matches every note to its song
by title and artist, including Music Feedback notes from Siri and the shortcut, and the detail
shows them under the song. The Note button doesn't use that.

**On the go means the laptop is awake.** The chat reaches `vf-mcp` through the laptop, the chat
host (`docs/setup/README.md` § Roles). The always-on Intel mini runs macOS 15, and Vinyl Fever
and `vf-mcp` need macOS 26 or later, so it can't take the role. Jon can stage from anywhere while
the laptop is awake, at home on power for example, without touching it. This milestone doesn't
change that (see *Out of scope*).

## Shared rules (every slice)

- **Vinyl Fever stays deterministic.** No model calls in the app or the helper.
- **The Mac stays the record keeper (Decision 1).** The phone never writes the recommendation
  ledger or `playlist-roles.json`. New shared state is an append-only log that every writer
  shares.
- **New logs follow the notes pattern:** append-only JSON lines in the iCloud
  `Taste Intelligence` folder, one file per writer (`<device-or-host>.jsonl`), `format` and
  `version` on every line. Readers skip and count lines they can't read, and never rewrite a
  file. Appends go through the shared JSONL append from `evicted-icloud-writes`.
- **Shared logic lives in packages** (Decision 3), tested on macOS and compiled for iOS.
- **House stack, as M21–M23:** `@Observable` models, dependency clients, an injected folder and
  clock. Tests never touch live paths or Apple Music.
- **Instruction changes ship in `LibraryMCPServer.instructions`,** never in Settings' copy.
  Verify with `scripts/mcp-smoke` against the built helper.

## Slices

**Dispatch 1: S1 + S2** (the phone, no shared data changes). **Dispatch 2: S3 + S4** (shared
matching, the stage tool's hints, the creation record, and the Mac's side). **Dispatch 3: S5**
(Create in Music on the phone). Each completing PR advances `NEXT_UP.md`. None waits on Jon's
gates. Dispatch 2 adds a ledger field and a new log, so the architect escalates it to Jon
(ADR-0005 D9).

- [ ] **S1 — A player strip at the bottom.**
  - **The strip.** A bar pinned to the bottom of the app (`.safeAreaInset(edge: .bottom)` on the
    split view), so it stays put across the list and the detail on iPhone and spans both columns
    on iPad. It uses the system's glass material. From the leading edge:
    - the current song's artwork (40 pt, rounded), with a placeholder when there's none;
    - title, then artist in secondary, one line each, truncating;
    - **previous**, **play/pause**, and **next** buttons, icon-only, each at least 44 pt, with
      accessibility labels ("Previous", "Pause", "Play", "Next").
  - **What it controls.** `SystemMusicPlayer`, whatever is playing, not only Vinyl Fever songs
    (Decision 8).
    - Play/pause follows the player's state, including changes made from the Lock Screen,
      Control Center, or Music.
    - Previous restarts the song when more than 3 seconds have played, and otherwise goes to the
      previous entry, as Music does.
    - The strip is hidden when Apple Music access isn't granted or the queue has no current
      entry.
    - A failed command shows its error in the strip's place for a few seconds, then the strip
      returns.
  - **The code.** A `NowPlayingModel` of its own; `PlaylistPlaybackModel` stays playlist-scoped.
    `PlaylistMusicClient` gains a now-playing stream (title, artist, artwork, playing or not) and
    the three transport calls. The existing current-entry stream can be folded into it.
  - **DoD:**
    - model tests with a fake client: hidden without access or a current entry; play/pause
      toggles and follows outside state changes; previous restarts after 3 s and steps back
      before; an error clears itself;
    - the iOS test target and the iOS build pass;
    - closeout (ADR-0005 D16) records the gate: on the iPhone and the iPad, start *2023
      Selections* and confirm the strip shows the song and artwork; use all three buttons;
      pause from the Lock Screen and confirm the strip follows; play something from Music
      itself and confirm the strip shows it; stop and clear the queue and confirm the strip
      hides; confirm it doesn't cover the last song in a long playlist. Jon takes one screenshot
      on each device.

- [ ] **S2 — The Note button says when a song has a note.**
  - A song with at least one note shows **Noted** with `text.bubble.fill`; without one it stays
    **Note** with `pencil`. Tapping either opens the same sheet, so Jon can add another.
  - It counts every note `notes(for:)` matches: the phone's own, Music Feedback's, the chat's,
    and one saved earlier in this session. It updates as soon as a note saves.
  - No new color (Decision 9). In the icon-only layout the filled glyph carries the state.
  - Accessibility: "Note on <title> by <artist>" without notes; "Add a note on <title> by
    <artist>, 2 notes saved" with them.
  - **DoD:**
    - model tests: no notes; a Music Feedback note matched by title and artist; a note saved
      this session; a playlist reaction (`title == nil`) never counts for a song;
    - closeout (ADR-0005 D16) records the gate: on the iPhone, open a playlist with a song Jon
      noted through Siri and confirm it reads Noted; leave a note on another song and confirm it
      switches straight away; confirm a song without notes still reads Note.

- [ ] **S3 — The Mac's matching, shared, and what only the Mac knows, recorded.**
  - **The package (Decision 3).** A new local package, `VinylFeverAppleMusic` (macOS 26,
    iOS 27), with two products:
    - `VinylFeverAppleMusic` (Foundation and swift-dependencies, no MusicKit): the
      `AppleMusicCatalogClient` interface; the candidate types (`CatalogSongCandidate`,
      `ScoredCandidate`, `MatchOutcome`, `LibraryAlbumCandidate`, `LibrarySongCandidate`,
      `AppleMusicSubscriptionStatus`, `CreatedPlaylistRef`, and the errors); `TrackRequest` and
      `PlaylistRequest`, split out of `PlaylistContract.swift`; `CatalogMatchScorer`;
      `CatalogMatchResolver` (with `ResolvedPlaylistRow`); and
      `LibraryUploadMatcher`. It depends on `VinylFeverNotes`.
    - `VinylFeverAppleMusicLive`: the live value, moved from the Mac app target as it is.
  - `VinylFeverCore` depends on the first product only and re-exports it, so `vf-mcp` never
    links MusicKit and Mac call sites don't change. The Mac app and the phone link both.
  - **No behavior change.** The existing scorer, resolver, upload-matcher, and builder tests
    move with the code or keep passing where they are.
  - **The stage tool records the upload route (Decision 4).** `stage_playlist` sets
    `upload: true` on each ledger track that `LibraryIndex.shouldUseLibraryRoute` sends to the
    library. The field is optional, so older readers ignore it and older batches lack it.
  - **The Mac mirrors the artist aliases (Decision 5).** Whenever Vinyl Fever saves
    `artist-aliases.json`, it also writes the same bytes to
    `Taste Intelligence/artist-aliases.json` in iCloud, and at launch it writes the mirror when
    it's missing or older than the local file. The Mac is the only writer, and nothing on the
    Mac reads the mirror.
  - **DoD:**
    - the package's tests pass on macOS, and both products compile for iOS
      (`xcodebuild … -destination 'generic/platform=iOS Simulator' build`);
    - `VinylFeverCore`, the Mac app, and the iOS tests pass, and `vf-mcp` builds;
    - an MCP test that a staged upload song gets `upload: true` and a catalog song doesn't;
    - a test that saving aliases writes the mirror, and that launch repairs a missing one;
    - closeout (ADR-0005 D16) records the gate, run with S4's.

- [ ] **S4 — The creation record, and the Mac keeps up.**
  - **The log (Decision 2).** `Taste Intelligence/playlist-creations/<device-or-host>.jsonl`,
    `format: "vf-playlist-creation"`, `version: 1`. Every line names its batch by the ledger's
    `host` and `recordedAt`, plus `playlist` (the name) for people, `at`, and `device` or `host`
    for the writer. Kinds:
    - `created`: `musicID` (the library playlist's ID from the create response), `songs` (how
      many went in), and `skipped`, a list of `{title, artist, reason}` with `reason` one of
      `not-found`, `skipped`, or `duplicate`.
    - `dismissed` (the Mac's **Dismiss**): no other fields.
    - A batch's latest line wins. The codec and that rule live in `VinylFeverNotes`.
  - **The Mac writes it.** **Create** on an opened inbox item appends `created`, and
    **Dismiss** appends `dismissed`. Creating from pasted text has no batch and writes nothing.
  - **The Mac files what another device created.** When the Mac lists its inbox, any item whose
    batch (this host, `recordedAt` to the second) has a `created` line from another device is
    moved to `Processed/`, and the Playlists view shows one line for each: "Created on
    <device> · <date>: <name>". If the item is already open in the builder, **Create** reads the
    log once more just before creating and stops with "Already created on <device>" when a line
    has arrived.
  - **A partial create keeps its playlist.** `createLibraryPlaylist` sends the first 100 songs
    with the create call and appends the rest in batches. If a later batch fails, it now throws
    a typed partial-create error that carries the `CreatedPlaylistRef` and the songs that
    weren't added. The Mac treats the playlist as created (post-Create state, a `created` line
    with the missing songs under `skipped`, reason `not-found`) and says how many songs didn't
    make it. This retires the M11 open question for both apps.
  - **The chat's instructions** say Jon creates a staged playlist in Vinyl Fever on the Mac or
    the iPhone, in place of "Jon reviews and creates it in Vinyl Fever".
  - **DoD:**
    - package tests: the codec round trip for both kinds; latest line wins; unreadable lines
      skipped and counted; pairing a batch to the second;
    - Mac model tests: Create and Dismiss append their lines; an inbox item created elsewhere is
      filed and announced, and one created on this Mac isn't announced; an open item whose
      `created` line arrives refuses Create; a partial create ends in
      the post-Create state with the right `skipped`;
    - `scripts/mcp-smoke` shows the new instruction;
    - closeout (ADR-0005 D16) records the gate for S3 and S4: install, start a new chat, and
      stage a playlist with one live upload; confirm its ledger line has `upload: true` on that
      song only; confirm `Taste Intelligence/artist-aliases.json` exists in iCloud; create it on
      the Mac and confirm the `created` line; stage and dismiss a second and confirm the
      `dismissed` line.

- [ ] **S5 — Create in Music, on the phone.**
  - **Where.** On a staged playlist's detail, when Apple Music access is granted, the batch has a
    name, no library playlist has that exact name, and the batch has no `created` line:
    - the header reads "Not in Music yet" under the date line;
    - a **Create in Music** button (`.borderedProminent`) leads; Play All becomes `.bordered`;
    - the list row's metadata line ends "· Not in Music yet".
  - **The gates,** before anything resolves: Apple Music access, a subscription that can play the
    catalog, and Sync Library on, with the Mac's `PlaylistGate` wording adapted for iOS
    (Settings → Music → Sync Library).
  - **The sheet.** Title "Create in Music", the playlist's name (not editable, Decision 6) and
    description. It resolves every song with the shared matching, four at a time:
    - a track with `upload: true` takes `LibraryUploadMatcher` with its album;
    - any other track takes the catalog route (`CatalogMatchResolver` and the scorer);
    - on a batch from before S3 (no track has the field), a track the catalog can't find and
      that has an album tries the upload route next;
    - `ArtistIdentity` comes from the iCloud alias mirror, or `.empty` when it's missing.
  - **Rows,** in playlist order:
    - **Matched:** artwork, title, artist, album.
    - **Choose:** an ambiguous match lists its candidates (artwork, title, artist, album, year).
      Jon taps one, or **Skip**.
    - **Not found:** the reason in secondary text. Skipped.
    - **Duplicate:** a later row resolving to a song already in the list says "Same as #n".
      Skipped.
  - **Create.** The button reads **Create Playlist · 23 songs**. While any Choose row is
    undecided it's disabled, and the footer reads "Choose or skip 2 songs" (Decision 7).
    - It creates through the shared live client, then appends the `created` line.
    - It's guarded against a double tap. Just before creating, it checks the library once more,
      and if a playlist with that name now exists it stops with "Already in Music".
    - On success the sheet closes, the detail shows the new playlist (artwork, Play All plays
      from it), and a line reads "Created “<name>” with 23 songs. 2 skipped." The skipped songs
      are listed under it until the next refresh.
    - A partial create (S4) reads "Created “<name>” with 21 of 23 songs" and records the rest.
    - If the playlist is created but the line doesn't save: "Created in Music, but the record
      didn't save: <reason>. The Mac will still list it in its inbox." The detail still finds the
      playlist by name.
  - **Archiving (Decision 10).** `PlaylistArchive` takes the creation lines:
    - a batch whose latest line is `created` is archived once its name is missing from the
      library, with no grace period;
    - a batch whose latest line is `dismissed` is archived;
    - a batch with neither stays Active for 14 days after staging, then is archived as today.
  - **DoD:**
    - package tests for the archive rule's three cases and the 14-day edge;
    - phone model tests with a fake Apple Music client and an injected folder: the gates; upload
      and catalog routing, including the fallback for an old batch; Choose blocks Create until
      decided; duplicates skipped; "Already in Music" stops before creating; success appends the
      right `created` line; a partial create; a record that fails to save;
    - the iOS test target and the iOS build pass;
    - closeout (ADR-0005 D16) records the gate, run away from the Mac with the laptop awake:
      1. In ChatGPT on the iPhone, ask for a short playlist that includes one live upload.
      2. Pull to refresh in Vinyl Fever. The playlist shows "Not in Music yet".
      3. Create it. Choose or skip any ambiguous songs, and confirm the live upload matched
         Jon's own copy.
      4. Confirm the playlist is in Music on the iPhone, and Play All plays it with the strip
         showing.
      5. Back at the Mac, confirm the inbox no longer lists it and the Playlists view says it was
         created on the iPhone; after the next snapshot, confirm Playlist Roles lists it as
         `vinyl-fever`.
      6. The next day, confirm it's still under Active. Delete it in Music, pull to refresh, and
         confirm it moves to Archived.

## Out of scope — with destinations

- **An always-on chat host.** Staging needs the laptop awake. A chat host that's always on
  needs an Apple silicon Mac on macOS 26 or later; none is planned
  ([open-questions.md](../open-questions.md)).
- **Re-searching a song by hand, and removing heavily played songs, on the phone:** stay on the
  Mac. A song the phone can't find is skipped and recorded, and Jon can add it from the Mac or
  with Keep.
- **Dismissing a staged playlist from the phone:** a candidate in
  [open-questions.md](../open-questions.md). The 14-day rule archives one Jon never creates.
- **Tapping the strip to jump to the song in its playlist:** a candidate in
  [open-questions.md](../open-questions.md).
- **A playlist staged without a ledger record** (`ledgerRecorded: false`): the phone can't see
  it, so it's created on the Mac as today.

## Decisions

1. **The phone creates; the Mac keeps the record (Jon and the architect, 2026-11-08).** Jon wants
   to finish playlists without the Mac, and wants the Mac fully synced. So the phone writes only
   to Music and to an append-only log every creator shares. The Mac files its inbox from that
   log, and labels the playlist from the ledger it already reads. Nothing has two writers of one
   file.
2. **One creation log, written by every creator (architect, 2026-11-08).** The Mac's inbox
   needs to know the phone created a playlist, and the phone needs to tell "not created" from
   "deleted". A library lookup by name can't do either reliably: the Mac's snapshot can be hours
   old, and a missing name means either. The log also keeps which songs were skipped, which
   nothing records today.
3. **The phone uses the Mac's matching, in a package (architect, 2026-11-08).** The phone's
   play-time matcher (title and artist, the top five catalog results) is fine for playing a song
   and too loose for a playlist Jon keeps. The live client moves with it, so both apps make the
   same calls. MusicKit stays out of the product `VinylFeverCore` links, so `vf-mcp` doesn't
   link it.
4. **The stage tool decides the upload route (architect, 2026-11-08).** Only the Mac has the
   snapshot that says a song is one of Jon's uploads, and the stage tool already holds it when
   it stages. One optional field on the ledger track is cheaper than sending the snapshot.
5. **Aliases are mirrored, with one writer (architect, 2026-11-08).** Moving
   `artist-aliases.json` into iCloud would change the Mac's paths and `vf-mcp`'s reads for no
   gain. The mirror is written only by the Mac and read only by the phone.
6. **The name can't be edited on the phone (architect, 2026-11-08).** The shelf, the Mac's
   auto-label, and the archive rule all find the playlist by its staged name. Renaming stays a
   Music or Mac job.
7. **Ambiguous songs block Create until Jon decides (architect, 2026-11-08).** A silent skip
   would drop the songs the chat most wanted Jon to hear, such as a specific live version. A
   decision is one tap.
8. **The strip controls whatever Music is playing (architect, 2026-11-08),** as Music's own
   strip does. Limiting it to Vinyl Fever songs would hide the controls exactly when Jon wants
   them.
9. **Noted uses no new color (architect, 2026-11-08).** Green already means Kept on that row.
   The label and the filled glyph tell Noted apart (`ui-and-platforms.md` § Color).
10. **An uncreated playlist stays Active for 14 days (architect, 2026-11-08).** It replaces
    M22's 24-hour grace period for batches without a creation line. A batch staged in the two
    weeks before S5 ships that Jon already deleted in Music will show "Not in Music yet" until
    it ages out; there are only a few.
