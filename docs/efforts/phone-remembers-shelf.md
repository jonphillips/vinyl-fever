# Effort — The phone remembers its shelf

Status: Ready
Summary: The phone app starts empty every launch and waits on iCloud and Music before it shows a single playlist. It gets its first SQLiteData database, keeps what the shelf last knew (playlists, what's archived, what's in Music, each song's kept/heard state), shows that at once, and refreshes behind it exactly as today.

Related: M24 (the phone shelf) · [Technical architecture](../technical-architecture.md) ·
[Efforts index](README.md)

Branch `effort/phone-remembers-shelf`, from a fresh `main` **after #192 (M24 S5) merges**: both
touch `PlaylistShelfModel` and the home view. One PR. No iCloud format change, no Mac change.

## Why

Jon, 2026-11-08: "It's a little frustrating the mobile app maintains no 'state' and has to load
the current state from Apple Music and refigure out what's an archive, what's been kept."

**What every launch does today (architect reading, 2026-11-08).** `PlaylistHomeView`'s `.task`
runs, in order, before the shelf shows anything (`PlaylistShelfModel.playlists` starts `[]`, so
the view shows "Loading playlists…"):

1. `PlaylistShelfModel.refresh`: every ledger file and every creation-record file from the iCloud
   folder (`RecommendationLedgerFolderReader`, up to an 8 s download deadline), then MusicKit's
   library playlist list (up to 1,000).
2. `PlaylistTasteNotesModel.refresh`: the notes folder.
3. `PlaylistProgressModel.refresh`: MusicKit's library list again (passed in, so usually not),
   `playlist-roles.json`, the tracks of **every Keepers playlist, one MusicKit call each**, the
   notes folder again, the listening log back to the oldest batch, then a full
   `PlaylistProgressIndex` build.
4. `PlaylistReviewsModel.refresh`.

All of it is thrown away on quit. Keeps made on the phone (`PlaylistKeepModel.keptPlaylistsBySong`)
live only in memory, so they're re-derived from the Keepers playlists on the next launch.

**What can't change.** Music is the truth for what's in the library (a playlist Jon deletes in
Music archives), and the Mac and the chat write the ledger and creation record. So the phone
still refreshes every launch. What changes is that it stops *waiting* for the refresh.

## Changes

- **The phone's first database.** Add `SQLiteData` to the `VinylFeverMobile` target in
  `project.yml` (the same `sqlite-data` package the Mac uses), and regenerate the project.
  - New `VinylFeverMobile/Database/MobileDatabase.swift`: `MobileDatabase.open(path:)` modeled on
    the Mac's `VinylFeverDatabase.open` (`VinylFeverCore/…/Database/Schema.swift`), but with none
    of its legacy adoption.
    - Live path: `Application Support/VinylFever/VinylFeverMobile.sqlite` in the app's container.
      Device-local, never in the iCloud folder.
    - Outside `.live`, no path: tests get their own database through the same migrations.
    - One `DatabaseMigrator`, migration `"v1 shelf cache"`, creating the four tables below.
      Merged migrations are immutable, as on the Mac.
    - **If the file can't be opened or migrated, or a migration has been superseded by a newer
      build, delete the file and open a fresh one.** If that fails too, fall back to an in-memory
      database so the app behaves as it does today. Log the error. See Decision 4.
  - `VinylFeverMobileApp.init` sets `$0.defaultDatabase` in its existing `prepareDependencies`.
    Confirm the `@State` models created before `init`'s body see it, the same way they already see
    `appleMusicCatalogClient`.
- **Four cache tables** (`VinylFeverMobile/Database/ShelfCache.swift`, `@Table` value types):

  | Table | Primary key | Columns | Written by |
  |---|---|---|---|
  | `cachedBatch` | `key`: `PlaylistCreationsCodec.batchKey(host:recordedAt:)` | the `RecommendationBatch`, as JSON | shelf refresh |
  | `cachedCreationEvent` | `key`: the batch key | the latest `PlaylistCreationEvent` for that batch, as JSON | shelf refresh |
  | `cachedLibraryPlaylist` | Music's playlist `id` | `name` | shelf refresh |
  | `cachedSongProgress` | (`playlistID`, `songID`) | `status` (`kept`, `passedWithFeedback`, `passedWithoutFeedback`, `notHeard`), `keptIn` (JSON `[String]`, empty unless kept) | progress model |

  JSON columns use SQLiteData's JSON representation of the existing `Codable` types; don't
  flatten `RecommendationBatch` into columns. Make `PlaylistSongProgress` round-trip through
  `status` + `keptIn` with a small mapping in `ShelfCache`, not by adding `Codable` to
  `VinylFeverNotes`.
- **The shelf shows what it last knew.** `PlaylistShelfModel`:
  - Before its first `client.read()` of the launch, it loads the cache and fills `playlists`
    (from cached batches through the existing `PlaylistShelf.make`, with today's `now`),
    `creationEvents`, and `libraryPlaylists` (only when `keepClient.isAuthorized()`; otherwise
    `nil`, as today). Archived, Active, and "not in Music yet" then come out of the existing code
    unchanged.
  - The cache is shown only until a read succeeds. A successful refresh replaces the in-memory
    state as today, and then writes the cache:
    - **A clean ledger read** (no unreadable files, no skipped lines) replaces `cachedBatch` and
      `cachedCreationEvent` wholesale.
    - **A partial read** (iCloud still downloading a file) upserts: batches it read are written,
      cached batches it didn't read stay, and a creation event replaces a cached one only if its
      `at` is later. The shelf shows that merged set, not just the partial read. Decision 3.
    - **A successful library read** replaces `cachedLibraryPlaylist`. A failed one leaves it.
  - **Errors.** A folder-access error (`folderNotSelected`, `accessRefused`) behaves as today:
    setup prompt, empty shelf. Any other read error keeps the cached shelf on screen and sets
    `hasUnreadableFiles`, so the existing "still downloading from iCloud" banner shows.
  - "Loading playlists…" shows only while there's nothing to show: no cache and no read yet.
    No other UI change.
- **Progress shows what it last knew.** `PlaylistProgressModel`:
  - Before its first refresh, it loads `cachedSongProgress` into `results` (counts recounted from
    the rows; add a `PlaylistProgressResult(songs:)` initializer in `VinylFeverNotes` that counts,
    and use it in `PlaylistProgressIndex.result(for:)` too), and sets `isAvailable` when MusicKit
    is authorized and there are rows.
  - After every successful refresh, and after `updateSavedNotes` and `updateSavedKeeps`
    recompute, it replaces `cachedSongProgress`. That's what makes a keep on the phone survive a
    relaunch.
  - A failed refresh keeps the cached results instead of clearing them. An unauthorized MusicKit
    still clears `results` on screen, as today, but leaves the rows.
- **Docs.** Add to `technical-architecture.md` → Persistence: the phone has its own SQLiteData
  database, today holding only rebuildable caches of the shelf, and Decision 4's rule.

## Decisions

1. **SQLiteData now, not a JSON file** (Jon, 2026-11-08). A single snapshot file would do for
   this effort. The database costs a little more today and gives the phone the house stack's
   home for state it owns later, with migrations and tests already in place.
2. **Cache the inputs that depend on the date, and the output that's expensive.** The shelf's
   playlists, archive, and "not in Music yet" all read `now` (the 14-day rule, staged dates), so
   the cache keeps their inputs and the existing code derives them fresh. Progress doesn't read
   `now`, and its inputs (every Keepers playlist's tracks, the listening log, the notes) are the
   slow part, so its result is cached instead.
3. **Partial reads merge; clean reads replace.** The ledger and creation record are append-only,
   so a batch missing from a partial read is still downloading, not gone. Only a clean read may
   drop a cached batch.
4. **A cache-only database may be thrown away.** Every row is rebuilt by the next refresh, so
   deleting the file is the right answer to any open or migration failure, including an older
   build. **This rule ends with the first table that isn't a cache.** That effort adopts the Mac's
   older-build error and backup-before-migrate behavior instead.
5. **Music and iCloud stay the truth.** The cache never writes to iCloud or Music and never
   decides anything alone. For a few seconds after launch the shelf can be out of date (a
   playlist deleted in Music shows Active until the refresh lands). That's the trade, and the
   refresh still runs every launch, on pull, and after Create.
6. **Each device keeps its own.** The database isn't synced, so the iPhone and iPad each fill
   their own on first launch.

## Done when

- **`VinylFeverMobileTests`**, each with its own test database (no live path):
  - **Shown before the read.** With a saved cache and a `playlistShelfClient.read` that suspends
    until the test releases it: the shelf has the cached playlists, the archived one is in
    Archived, and the "not in Music yet" playlist is flagged. Progress has its cached counts.
    Then release the read and the shelf shows the fresh result.
  - **Round trip.** A refresh with a clean read writes the cache. A new `PlaylistShelfModel` and
    `PlaylistProgressModel` on the same database show the same playlists, segments, and progress
    before their reads return.
  - **Clean read replaces.** A batch cached earlier and absent from a clean read is gone from the
    shelf and the table.
  - **Partial read merges.** A cached batch absent from a partial read stays on the shelf and in
    the table. A batch only in the partial read is added. An older creation event doesn't replace
    a newer cached one.
  - **Errors.** A generic read error keeps the cached shelf and sets `hasUnreadableFiles`. A
    folder-access error shows setup with an empty shelf. A failed progress refresh keeps cached
    results.
  - **Not authorized.** With MusicKit unauthorized, cached library playlists aren't used
    (`libraryPlaylists` is `nil`) and progress isn't shown.
  - **A keep survives.** `updateSavedKeeps` writes `cachedSongProgress`. A new progress model
    shows that song `kept(in:)` the playlist before its refresh returns.
  - **The database recovers.** A file of garbage at the database path, and a database whose
    migrator has an identifier the build doesn't know: `MobileDatabase.open` replaces each with a
    working empty database.
- The `VinylFeverNotes` tests pass with the new `PlaylistProgressResult(songs:)` initializer.
- `xcodebuild -scheme VinylFeverMobile … test` passes (per `verification.md`), and the Mac app
  builds.
- Closeout (ADR-0005 D16) adds the gate below to `device-passes.md`.

**What tests can't show:** how much faster a real launch feels, and that MusicKit's live library
list agrees with the cache after Jon deletes a playlist in Music.

**The gate** (after install on the iPhone):

1. Open Vinyl Fever and let the shelf finish loading, with progress showing. Force-quit it.
2. Relaunch. The shelf, the Active and Archived counts, and progress appear at once, with no
   "Loading playlists…".
3. Keep a song from the phone. Force-quit and relaunch. The song shows kept straight away.
4. In Music, delete a Vinyl Fever playlist Jon is finished with. Relaunch Vinyl Fever. It may show
   in Active for a moment, then moves to Archived without a pull to refresh.

## Out of scope

- **Re-reading only what changed** (ledger files by modification date, Keepers playlists by
  `lastModifiedDate`): a candidate in `open-questions.md`, if refreshes still feel slow.
- **Caching notes and reviews.** Noted marks and reviews still appear when their reads finish, as
  today.
- **State the phone owns** (anything not rebuilt from iCloud or Music). It belongs in this
  database when it comes, under Decision 4's ending.
- **The Mac.** It already has its own database and is unchanged.
