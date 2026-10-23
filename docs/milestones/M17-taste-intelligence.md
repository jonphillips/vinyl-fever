# Milestone 17 — Taste Intelligence (playlists, exposure, and Jon's reasons)

*Turn the evidence Jon already produces into something the chat can reason from: his playlists
with their roles, what Apple's New Music put in front of him each week and what he kept, and
his own words about songs. The design, its evidence, and S0's probe results are in
[../taste-intelligence.md](../taste-intelligence.md); this doc is the build order. Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply. Where this doc and those conflict, stop and flag
it.*

Summary: Three slices, one dispatch each. S1 puts every playlist into the library snapshot (v2),
adds `playlist-roles.json` with a Settings editor, applies the 2018 rule, and gives `vf-mcp`
`list_playlists`, `playlist_tracks`, and a `check_tracks` that reports playlist evidence by role.
Its gate is the north-star question asked for the first time. S2 starts the two logs that can't
be rebuilt later: the poller saves each week's New Music, and each snapshot refresh records what
changed in Jon's playlists. Then `kept_and_passed` and the baselines read them. S3 reads the VF
Note file Jon's shortcut is already writing, and adds `taste_notes` and `record_taste_note`.
Vinyl Fever makes no model calls and stores no scores: the chat is the interpreter.

## The milestone in one sentence

The chat can ask "what does Jon keep?" and get his Selections, his Replay ranks, his New Music
keeps and passes, and his own reasons, all as evidence with dates. It never gets a score.

## What S0 settled (2026-10-22 and 2026-10-23)

Details are in the design doc's *S0 results*. The facts this plan depends on:

- **Playlists are cheap to read.** Persistent IDs of every member of 65 user and 77
  subscription playlists (about 20,090 entries) come back from AppleScript in 2 s.
- **Jon's library today (read-only AppleScript, 2026-10-23):**
  - 65 regular user playlists, 7 smart playlists, and 76 subscription playlists.
  - The Library playlist is the smart playlist "Music" with special kind `Music`, and it has
    87,042 tracks.
  - The only folder is "aJon Selections". It holds "2020: Jon's Selections" (empty) through
    "2026: Jon's Selections" (79, 77, 77, 59, 130, 101 songs from 2021 to 2026).
  - Replay 2015 through Replay 2026 and Replay All Time are subscription playlists.
  - "New Music" (25 songs) and "New Music Daily" (103) are both subscription playlists, and
    only the first is Jon's personal mix.
- **Most members outside Selections aren't library tracks.** New Music has 0 of 25 in the
  library, Replay 2018 has 61 of 98, and 2025 Selections has 130 of 130. So the snapshot keeps
  title, artist, and album text for members it can't find among library tracks.
- **New Music's catalog form** (`pl.pm-…`, `playlistType: personal-mix`) carries the real
  weekly `lastModifiedDate` and all 25 songs with catalog IDs. The library form's ID
  (`p.5pvKi0GQXD`) is stable, but its own `lastModifiedDate` never changes.
- **A kept New Music song is a separate library copy.** The catalog ID links the two, and so
  does the song key (`ArtistIdentity` + `SongTextNormalizer`). "White Knight" (Cats in Space)
  matched both ways.
- **VF Note works end to end** (Jon, 2026-10-22 and 2026-10-23). It runs from CarPlay through
  Siri by name, from the Action button while the phone is locked, and from Siri's "add this to my
  2026 Selections" on a first hearing. Recognize Music works on normal playlists. Jon's notes
  are already accumulating in `iCloud Drive/Vinyl Fever/Taste Intelligence/notes.jsonl`, in
  format `vf-taste-note` v1.
- **On Discovery Station, Current Song stays blank** until Jon skips forward and back. That's
  his habit now, and nothing in this milestone works around it.

## Shared rules (every slice)

- **The unit of taste is the song**, keyed the way `check_tracks` and the listening log already
  key it: `ArtistIdentity.key(artist)` + `SongTextNormalizer.libraryTitle(title)`. A recording
  (a persistent ID or a catalog ID) is evidence for a song. Evidence is grouped by song.
- **Evidence is reported by role, never by counting playlists.** Three curated playlists holding
  a song are one `curated` fact listing three names, not a score of 3.
- **Never store an interpretation.** Jon's words are kept verbatim. The tools return evidence;
  the chat writes the synthesis.
- **Taste files live in `iCloud Drive/Vinyl Fever/Taste Intelligence/`**, the folder VF Note
  already writes to, next to `Listening/` (Decision 1). Readers use `NSFileCoordinator`, as the
  listening log reader does. Writers append whole lines, or replace a file atomically.
- **M12's tool rules hold:** compact JSON, no persistent IDs and no file paths in results,
  capped lists, `readOnlyHint` on reads. Log-backed results carry coverage.
- **Never judge a source or a song by genre** in tool text, instructions, or tests. Jon's taste
  is broad. What he kept and passed is the judge.

## Slices

**Dispatch 1: S1** (Core + `vf-mcp` + app; Jon's gate). **Dispatch 2: S2** (Listening + Core +
`vf-mcp` + both apps; the poller and the laptop). **Dispatch 3: S3** (Core + `vf-mcp` +
`setup-mac`; Jon's gate). Each slice is a dispatch of its own, because each gate can redirect the
next. S2 and S3 both edit `vf-mcp`, so they can't run side by side.

- [ ] **S1 — Playlists in the snapshot, with roles (Core + `vf-mcp` + app).**
  - **Snapshot v2** (`LibrarySnapshot.currentVersion = 2`):
    - `LibraryTrack` gains `disliked: Bool`, read in bulk like `favorited`
      (`LibraryBulkProperty` `pHat`, boolean). A v1 file decodes with `disliked` false.
    - `playlists: [LibraryPlaylist]`, in Music's order. Each one has:
      - `persistentID` and `name`;
      - `folder`: the parent folder's name, or nil;
      - `kind`: `user`, `smart`, or `subscription`;
      - `members`: ordered persistent IDs, duplicates kept. The order is Replay's rank.
    - `outsideTracks: [String: LibraryOutsideTrack]`, keyed by persistent ID, for members that
      aren't among `tracks`. Each one has `name`, `artist`, `album`, and optionally `year` and
      `durationSeconds`. Nothing else: the M12 "never in the file" rule still applies.
    - Read every `user playlist` and every `subscription playlist`. Leave out folders (their
      name becomes `folder`) and any playlist whose `special kind` isn't `none` (the Library
      playlist "Music", Purchased, and so on).
    - Read members in bulk per playlist, with raw Apple events like `readEveryTrackProperty`:
      the persistent IDs of every track, then, only for playlists with members outside the
      library, their name, artist, album, year, and duration. Zip the columns the same way, and
      handle `missing value` the same way.
    - A v1 file decodes with no playlists. The reader still rejects a newer version. The app and
      `vf-mcp` ship in one bundle, so they always agree on the version.
    - **Read budget:** measure the playlist read on Jon's library and report it in the PR.
      M12's track read measured 21–25 s. The playlist read should add about 5 s or less. If it
      adds more than 10 s, stop and flag it before optimizing.
  - **`playlist-roles.json`** (`Taste Intelligence/playlist-roles.json`; Jon-authored through
    the editor):
    ```json
    {"format":"vf-playlist-roles","version":1,"updatedAt":"2026-10-23T14:00:00Z",
     "playlists":[{"persistentID":"8F3A…","name":"2025: Jon's Selections","role":"keepers"}]}
    ```
    - The roles are the design's eleven: `keepers`, `replay`, `curated`, `situational`,
      `auditioned`, `discovery-inbox`, `followed`, `apple-mix`, `collection`, `vinyl-fever`,
      and `ignore`. They're a Core enum. An unknown role in the file fails loudly with a typed
      error naming it.
    - **Matching an entry to a playlist:** match by persistent ID first. If no playlist has that
      ID, match by exact name, but only when exactly one playlist has that name. A new Mac or a
      rebuilt library changes persistent IDs, and names survive that (Decision 2). An entry
      that matches nothing is kept in the file and shown as missing. It's never deleted
      silently.
    - A playlist with no entry is **unlabeled**. It's listed, but it isn't evidence.
    - A `PlaylistRolesStore` dependency client reads and writes the file, with `liveValue`
      (iCloud, coordinated, atomic write) and an in-memory `testValue`.
  - **Suggestions** (pure Core function: playlist name, kind, folder → suggested role or nil):
    - `^\d{4}: Jon's Selections$` → `keepers`;
    - `^Replay (\d{4})$` → `replay` when the year is 2018 or later, otherwise `ignore`;
      `Replay All Time` → `ignore`;
    - a subscription playlist named exactly `New Music` → `auditioned` (**not** "New Music
      Daily");
    - `My Shazam Tracks` → `discovery-inbox`;
    - `^Collection: ` → `collection`;
    - a name matching a playlist Vinyl Fever created (an archived `PlaylistInbox/Processed`
      request's `name`) → `vinyl-fever`.
    - Everything else gets no suggestion. Suggestions never judge by genre.
  - **The 2018 rule** (Core constant `sharedAccountCutoff`, 2018-01-01 local time):
    - A `replay` playlist whose name's year is before 2018 is treated as `ignore`, whatever the
      file says, and the editor won't offer `replay` for it.
    - A song is **shared-account era** when every library recording of it was added before
      the cutoff and the song isn't in a `keepers`, `curated`, `situational`, or 2018-or-later
      `replay` playlist. Its Mac play count and date added were shared with the family.
      Results flag it as `sharedAccountEra: true`, and the play stats are still returned.
  - **Settings → Taste** (a new section after Chat Access):
    - A summary line: "148 playlists · 6 unlabeled · roles saved 2 days ago", the roles file
      path, and any read or decode error. "Unlabeled" is how the app asks about a new
      playlist.
    - **Playlist Roles…** opens a sheet with a table of name, folder, kind, song count, and a role
      picker. It filters by All, Unlabeled, Missing, or one role. **Use Suggestions** fills in
      only unlabeled rows. **Save** writes the file. Missing entries are listed with **Remove**.
    - An `@Observable` feature model holds the editor's state, with dependencies for the
      snapshot store and the roles store. There's no new SQLite table: the file is the record
      (Decision 6).
  - **`PlaylistIndex`** (Core; built from the snapshot, the roles, and `ArtistIdentity`, and
    cached by `vf-mcp` next to `LibraryIndex`, invalidated when either file's modification date
    changes). It maps each song key to its playlist memberships: playlist, role, and position.
  - **`vf-mcp` tools:**

    | Tool | Input | Returns |
    | --- | --- | --- |
    | `list_playlists` | `role?` (a role or `unlabeled`), `limit` | playlists with name, role (or null), folder, kind, song count, and in-library count; `unlabeledCount`; snapshot age. With no `role`, `ignore` playlists are left out. |
    | `playlist_tracks` | `name` (exact, then case-insensitive), `limit` (default 100, max 200) | songs in order with `position`, artist, title, album, year, and the song's evidence (below). Replay's position is its rank. |
    | `check_tracks` (extended) | unchanged | each result also carries the song's evidence |

    **Song evidence** (one Core type, shared by both tools):
    - `playlists`: role → playlist names. Leave out `ignore` and `followed` (following a list
      isn't choosing its songs). Each role lists at most 10 names, plus a count.
    - `disliked` (any recording);
    - `heard`: the number of distinct local days the song was started in the listening log, and
      the last one. Leave it out, with no error, when the log isn't set up;
    - `sharedAccountEra`;
    - the existing library fields: owned, plays, favorited, last played, availability.

    Results carry `unlabeledPlaylistCount`, so the chat knows how much evidence it can't see.
  - **Instructions:** after the existing `instructionHead`, add a taste paragraph. The first 512
    characters must still stand alone. It says:
    - For taste questions, start from `list_playlists`. `keepers` (Jon's yearly Selections) are
      the strongest evidence, and `replay` positions are ranks.
    - Report evidence by role, not by counting playlists. Don't infer taste from genre.
    - `sharedAccountEra` play counts aren't Jon's alone.
    - Before proposing songs Jon "probably doesn't know", call `check_tracks` and drop anything
      owned, heard, or in a playlist.

    Update the instructions snapshot test. Jon re-copies the ChatGPT Project instructions from
    Settings after S1 merges (see *Prerequisites*).

  **DoD:**
  - **Core tests:**
    - v1 snapshots decode (no playlists, `disliked` false), v2 round-trips, and a newer version
      throws;
    - members outside the library resolve through `outsideTracks`, and duplicates keep their
      order;
    - role matching works by ID, then by a unique name. A duplicate name doesn't match, and
      unmatched entries survive a save. An unknown role throws;
    - every suggestion rule, including that "New Music Daily" gets no suggestion and that
      Replay 2017 → `ignore`;
    - the shared-account era: added before 2018 with no choosing playlist → flagged; added
      before 2018 but in 2025 Selections → not flagged; in Replay 2017 only → flagged;
    - song evidence groups by role, leaves out `ignore` and `followed`, caps names, and merges
      recordings of one song;
    - `list_playlists`, `playlist_tracks`, and `check_tracks` JSON golden tests, with no persistent
      IDs in any result.
  - **Perf** (`VF_PERF_TESTS=1`): building the `PlaylistIndex` at Jon's scale (87k tracks, 150
    playlists, 20k members) takes under 1 s.
  - **App test:** the editor model applies suggestions only to unlabeled rows and writes through
    the store.
  - **Executor's laptop checks (read-only against Jon's library), reported in the PR:**
    - the time to read the playlists;
    - the counts against *What S0 settled*: about 72 user, 76 subscription, the 7 Selections
      sizes, and New Music's 25 songs, all outside the library;
    - Replay 2025's order matches Music.app;
    - `scripts/install-vinyl-fever` and the smoke test pass;
    - `playlist_tracks` for "2025: Jon's Selections" through the installed helper returns 130
      songs.
  - **Jon's gate (laptop and ChatGPT), owed after merge:**
    1. Refresh the snapshot. Open **Settings → Taste → Playlist Roles…**, choose **Use
       Suggestions**, label the rest (about 10 minutes), and save.
    2. Re-copy the Project instructions into ChatGPT.
    3. Ask: "Find me 15 songs I probably don't know but am unusually likely to love, in the spirit
       of my 2025 Selections. Explain each against songs in it." The chat should call
       `playlist_tracks` and `check_tracks`, and its explanations should name real Selections
       songs.
    4. Jon judges the 15 and records the result here: how many he didn't know, how many he'd
       keep, and anything that redirects S2 or S3.

- [ ] **S2 — Exposure and curation logs, kept and passed, baselines (Listening + Core + `vf-mcp` +
  both apps).** *It goes before feedback (Decision 3): a New Music week that isn't saved is gone,
  and VF Note notes are already accumulating without code.*
  - **Exposure log: the poller saves New Music** (`VinylFeverListening`, so the mini's VF
    Listening Poller and Vinyl Fever's built-in poller share it):
    - After a successful poll by the lease holder, at most once every 6 hours, fetch New Music's
      catalog playlist with its tracks. If its `lastModifiedDate` isn't recorded yet, append one
      line to `Taste Intelligence/exposure/<host>.jsonl`:
      ```json
      {"format":"vf-new-music-week","version":1,"lastModifiedDate":"2026-10-16T10:04:00Z","fetchedAt":"…","host":"…","tracks":[{"catalogID":"6815778888","title":"White Knight","artist":"Cats in Space","album":"White Knight - Single","releaseDate":"2026-10-16","durationSeconds":282}]}
      ```
    - **Finding the catalog ID:** first, probe how the library playlist "New Music" leads to
      its `pl.pm-…` catalog ID (for example `playParams.globalId`, or a catalog relationship).
      Resolve it at run time and cache it. If it can't be resolved, record an `exposure` gap
      line and keep polling: an exposure failure never fails a listening poll. S0's IDs are the
      test fixtures, never constants in code.
    - The reader reads every `exposure/*.jsonl` and de-duplicates on `lastModifiedDate`. It
      tolerates the same things as the listening log: blank lines, a partial last line, and no
      final newline.
  - **Curation log: what changed between snapshots** (app, at snapshot refresh):
    - Before writing a new v2 snapshot, diff it against the previous one. For each playlist
      present in both, record the songs added and removed (by text: artist, title, album) and
      record favorited and disliked changes on library tracks. Record playlists that appeared or
      disappeared.
    - Append one `vf-curation-change` v1 line per refresh with changes to
      `Taste Intelligence/curation/<host>.jsonl`, carrying `observedAt` and
      `previousSnapshotAt`. The first v2 snapshot writes a baseline line with no changes.
    - A song added and removed between refreshes is missed, and that's accepted
      (design, *Architecture*).
  - **`kept_and_passed`** (`vf-mcp`; input `weeks`, default 8):
    - Each week lists every New Music song, classified as:
      - **kept:** the song key is in a `keepers` playlist in the current snapshot;
      - **passed:** the listening log has a start of the song between the week's
        `lastModifiedDate` and 14 days later, it's not kept, and the snapshot is newer than the
        end of that window;
      - **unheard:** no start in the window;
      - **pending:** the window or the snapshot isn't late enough to say.
    - Kept songs come first, then passed, then unheard and pending, with counts. Coverage
      covers exposure gaps, listening log coverage, and the snapshot's age.
    - Matching is by song key (Decision 4).
  - **`taste_baselines`** (`vf-mcp`, no input):
    - **Apple's yield:** kept ÷ (kept + passed), per week and overall, from `kept_and_passed`.
    - **Jon's stick rate:** for each year N from 2021, the share of N's Selections songs that are
      in Replay N or Replay N+1, from the snapshot alone.

    Both come with counts, never only a percentage.

  **DoD:**
  - **Listening tests:** saves only on a new `lastModifiedDate`, at most once per 6 h, and
    only by the lease holder; a failed fetch records a gap and the poll still succeeds;
    the reader de-duplicates and tolerates bad lines.
  - **Core tests:** the snapshot diff (adds, removes, reorders that aren't changes, playlists that
    appear and disappear, favorites and dislikes); every `kept_and_passed` class, including
    pending when the snapshot is too old; the stick rate on a fixture with known answers.
  - **The macOS 15 poller builds** (`scripts/build-listening-poller`).
  - **Executor's laptop check:** one real New Music week is saved (it can be this week's), and
    `kept_and_passed` shows it as pending or classified.
  - **Jon's gate, owed until two weeks are saved:** the mini saves a week without the laptop
    open. Jon reads `kept_and_passed` for a finished week and confirms the keeps and passes match
    what he did.

- [ ] **S3 — Jon's reasons: VF Note and chat notes (Core + `vf-mcp` + `setup-mac`).**
  - **Reader** (Core, pure): reads every `Taste Intelligence/notes*.jsonl`, in format
    `vf-taste-note` v1, with the rules in the design's *S0 results: VF Note*:
    - it skips blank lines and a partial last line, and tolerates no final newline;
    - it handles UTF-8, such as the curly apostrophe in `Jon’s`;
    - it reads iCloud conflict copies (`notes 2.jsonl`) and de-duplicates on
      (`notedAt`, `title`, `artist`);
    - a line with a newer version or an unknown format is counted as skipped in coverage, never
      dropped silently;
    - a note with an empty title is **time-only**.
  - **`record_taste_note`** (`vf-mcp`, write; `destructiveHint: false`): input `note` (Jon's
    words verbatim), and either a song (`artist`, `title`, `album?`) or a `playlist` name. It
    appends a v1 line with `source: "chat"` (and `playlist` when given) to
    `notes-chat-<host>.jsonl`. It never writes `notes.jsonl`, which the shortcut appends to
    through iCloud. The tool's description says to pass Jon's words, not a paraphrase.
  - **`taste_notes`** (`vf-mcp`, read): filter by `artist`, `title`, `playlist`, or `period`;
    newest first; capped. Each note has the song, `notedAt`, the note text, `source`, and
    `firstHearing` (`playCount` 0). A time-only note also carries its candidates: the songs the
    listening log shows playing within 10 minutes of `notedAt`. The chat asks Jon which one he
    meant (Decision 5).
  - **`check_tracks` and `playlist_tracks` evidence** gain `notes`: the count, and the newest
    note's text and date.
  - **`setup-mac`, chat role:** checks that `Taste Intelligence/notes.jsonl` exists, and
    `--apply` creates it empty when it's missing. Shortcuts can't create a `.jsonl` file (design,
    *S0 results*).
  - **`docs/setup/vf-note.md`:** the VF Note recipe as setup steps, taken from the design doc,
    with Recognize Music as the fallback when Current Song is blank. The README links it.

  **DoD:**
  - **Core tests:** Jon's real line shapes (the White Knight and Shack examples), conflict copies,
    duplicates, a partial last line, a newer version counted as skipped, and time-only candidates
    from a fixture log.
  - **`vf-mcp` tests:** `record_taste_note` round-trips through `taste_notes` verbatim, and never
    touches `notes.jsonl`.
  - **`setup-mac`:** `shellcheck` passes, and running `--apply` twice changes nothing the second
    time.
  - **Jon's gate:** in the car, VF Note on a New Music song. At home, ask the chat "what have I
    said about songs this week?" The note comes back word for word. Then tell the chat a reason
    about a playlist, and see it in `taste_notes`.

## Prerequisites (Jon, not the executor's)

- [x] VF Note built and writing `notes.jsonl` (2026-10-22). CarPlay, Siri, and the Action button
  confirmed (2026-10-23).
- [x] Replay playlists added to the library (2026-10-20).
- [ ] After S1: label the playlist roles, and re-copy the ChatGPT Project instructions from
  Settings.
- [ ] Keep adding to Selections, and use Favorite and Suggest Less. They feed S2.

## Constants register (starting values)

| Constant | Value | Rationale |
| --- | --- | --- |
| Taste folder | `iCloud Drive/Vinyl Fever/Taste Intelligence/` | Where VF Note already writes; one folder for every taste file. |
| Shared-account cutoff | 2018-01-01, local time | Before 2018 the family shared one Apple Music account. |
| Playlist names shown per evidence role | 10, plus a count | Enough to explain a song; capped like every M12 result. |
| `playlist_tracks` limit | 100 by default, 200 at most | 2025 Selections is 130; M12's `maximumLimit` is 200. |
| Playlist read budget | +5 s expected; flag past +10 s | S0 read every member in 2 s; text for outside members costs more. |
| New Music fetch interval | at most every 6 h | It changes weekly. Four tries a day survive a sleeping or busy Mac. |
| Pass window | 14 days after the week's `lastModifiedDate` | Jon hears New Music within the week; two weeks absorb late listens. |
| Time-only note match window | ±10 minutes | A note follows the song closely; the log's windows are coarse. |

## Out of scope — with destinations

- **The outcomes milestone:** the recommendation ledger's familiarity field, discovery yield,
  Apple's recommendations and similar artists as candidate sources, `taste_evidence`,
  `neglected_keepers`, and reading ratings through the API. → Next milestone, once S2's logs
  have a few weeks in them.
- **"Recommended before" in `check_tracks`.** → The outcomes milestone, with the ledger.
- **Matching kept and passed by catalog ID.** → Only if `kept_and_passed` shows song-key misses
  (Decision 4).
- **The 2018 rule in `top_tracks`, `top_artists`, and `search_library`.** → After S1's gate, if
  the chat leans on all-time Mac plays.
- **A Mac screen for confirming time-only notes.** → Only if the chat's candidates prove
  unworkable (Decision 5).
- **An iOS app, scores, embeddings, audio analysis, a stored taste profile.** → As the design's
  *Out of scope* says.

## Decisions

Open — the architect's recommendation is listed first. Merging this plan approves them and sets
`NEXT_UP.md` to Dispatch 1.

1. **Every taste file lives in `Taste Intelligence/`** inside the iCloud Drive Vinyl Fever
   folder. That includes the roles file, which the design put at the folder's root (design
   Decision 4). VF Note already writes there, and one folder keeps the taste data together.
2. **Roles match by persistent ID, then by a unique name.** IDs survive renames. Names survive a
   new Mac or a rebuilt library, which change every persistent ID. An entry that matches nothing
   is kept and shown, so a relabel is never forced by accident.
3. **Exposure and curation (S2) come before feedback (S3).** That reverses the design's order.
   A missed New Music week can never be recovered, while notes are already being written by the
   shortcut and wait safely in iCloud. S1 still goes first, because its gate is the first real
   test of the whole approach.
4. **Kept and passed match by song key, not catalog ID.** The snapshot comes from AppleScript,
   which has no catalog IDs. The song is the unit of taste anyway. A remastered or alternate
   release of a kept song still counts as kept.
5. **The chat resolves time-only notes.** `taste_notes` returns the candidate songs, and the chat
   asks Jon. With Current Song working (and Jon's skip habit on Discovery Station) and Recognize
   Music as the fallback, time-only notes should be rare, and a Mac screen for them isn't worth
   building yet. This replaces the design's Mac confirmation.
6. **No SQLite schema change in this milestone.** The roles file is the record, edited in
   Settings and read by `vf-mcp` without the app. Snapshot v2 is a rebuildable derived file, and
   the logs are append-only JSONL, as for listening (M13 Decision 1).
