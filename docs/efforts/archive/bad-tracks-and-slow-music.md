# Effort — One bad track or a stalled Music doesn't stop Vinyl Fever

Status: Dispatched
Summary: One badly tagged song in *Undeniable* has no artist, so the phone's Keep sheet failed and its progress silently stopped updating. A stall in Music has also kept the Mac's library snapshot at 5 days old. Skip tracks that won't decode, say when progress can't refresh, put dates on backup warnings and drop the resolved ones, and retry a stale snapshot every hour.

Related: [M21](../../milestones/archive/M21-playlists-view.md) · [M22](../../milestones/archive/M22-playlist-progress.md) ·
[M19](../../milestones/archive/M19-backups.md) · [Efforts index](../README.md)

Branch `effort/bad-tracks-and-slow-music`, from a fresh `main`. One PR. No schema change, no sync
change, and no iCloud file changes format.

## Why

On 2026-11-11 Jon created two chat playlists on the phone and played from them. Three things went
wrong. The architect investigated each one against the real data.

**1. One track breaks Keep and progress on the phone.** Keep on *Club To Your Arms* showed
"Apple Music returned HTTP 200: Apple Music returned an unreadable playlist tracks response: The
data couldn't be read because it is missing." with an empty "Keep in" list. Songs Jon had played
didn't show as played.

A read-only probe of the Apple Music API read the tracks of all 11 keepers playlists. Ten decoded
cleanly. *Undeniable* (113 tracks) has one item with no `artistName`:

```json
{"id":"i.0YJRXHkvem9","type":"library-songs","href":"/v1/me/library/songs/i.0YJRXHkvem9",
 "attributes":{"name":"Jeffrey Osborne - On The Wings Of Lo 1","trackNumber":0,"genreNames":[""],
 "durationInMillis":243069,"discNumber":0,"hasLyrics":true,
 "playParams":{"catalogId":"1434921727","id":"i.0YJRXHkvem9","kind":"song","isLibrary":true,
   "reporting":true,"reportingId":"1434921727"}}}
```

In Music it's a 2010 file with blank artist, album, and genre. Apple leaves out an empty
`artistName` rather than sending `""`. `TrackPage.Track.Attributes.artistName` in
`VinylFeverMobile/KeepLibraryClient.swift` is a non-optional `String`, so that one item fails the
whole page. That failure then breaks two features:

- **Keep** (`PlaylistKeepModel.prepare`) reads every keepers playlist's tracks before it shows
  anything, so the sheet shows only the error.
- **Progress** (`PlaylistProgressModel.refresh`) reads the same tracks before it reads any plays.
  Its `catch` is empty, so the phone keeps its last cache, and new playlists never get progress.

The plays themselves are fine. The mini's poller logged *Club To Your Arms* at 12:09. *Undeniable*
has had the keepers role in every backup back to 2026-11-04, so the break predates these playlists.

**2. A stale warning in Settings.** Backups shows "unreadable: iCloud/Taste
Intelligence/exposure/Jon_s_Mac_mini__2_.jsonl". Only the 2026-11-03 set has that warning. That
night the backup fell back to the previous day's copy, as designed. Every set since then has read
the file. `DailyBackup.recentWarnings` returns every warning from 30 days of sets with no date, so a
resolved one-off looks current.

**3. The Mac's library snapshot has been stuck since 2026-11-06 13:14.** The Playlists screen shows
"Music did not respond in time." The architect timed the app's own `readLibrarySnapshot` twice:

| Run | Result |
|---|---|
| First | 13 properties at about 1 s each, then `dateAdded` never answered. Killed at 200 s. |
| Second, minutes later | All 87,378 tracks and 157 playlists in **22 s** |

So the snapshot isn't too large. Music sometimes leaves an Apple Event unanswered, and the whole
read shares one 120 s budget. The app checks staleness only at launch
(`loadSnapshotAndRefreshIfStale`). It launched 2026-11-08 19:11, and that launch's refresh failed.
Nothing tried again, and the app logs nothing, so the only evidence was the on-screen message.

## Changes

### Phone: a track that won't decode is skipped

- **A lossy page decode** (`KeepLibraryClient.swift`). `PlaylistPage` and `TrackPage` decode `data`
  one item at a time. An item that fails to decode, such as missing `attributes`, `name`, or
  `artistName`, or a wrong type, is skipped. The rest of the page and `next` decode as before. A
  page with no `data` array, or a body that isn't JSON, still throws the existing error.
  - Move the page decoding into an internal function the tests can call, for example
    `KeepLibraryPages.decodeTracks(_ data: Data) throws -> (tracks: [KeepLibraryTrack], next: String?, skipped: [String])`,
    plus the matching playlists function. `skipped` holds each skipped item's `id`, when it has
    one.
  - `NSLog` each skip as `Vinyl Fever skipped an unreadable track <id> in playlist <playlistID>`.
    Nothing more is shown to Jon.
- **The Keep sheet names the playlist.** If `tracks(id)` still throws for a reason other than a bad
  item, `errorMessage` begins with that playlist's name, as in `Undeniable: Apple Music returned
  HTTP 404: …`. The sheet still loads all or nothing, as today.

### Phone: progress says when it can't refresh

- `PlaylistProgressModel` gains `private(set) var refreshFailure: String?`. `refresh` clears it at
  the start and sets it in the catch, which keeps the cache as today. The message says which read
  failed:
  - the playlist read: `Couldn't read <name> from Apple Music: <error>`;
  - the notes read: `Some notes are still downloading from iCloud.`;
  - the listening log: unchanged, because `hasUnreadableListeningLog` already covers it, so
    `refreshFailure` stays `nil`;
  - anything else: the error's `localizedDescription`.
- **Shown** in the shelf's top section, under the iCloud caption and in the same caption style:
  `Progress couldn't refresh: <refreshFailure>. Showing the last saved progress.`. It isn't shown
  in the detail view.

### Mac: backup warnings carry their day, and resolved ones drop off

- `DailyBackup.recentWarnings` returns `[DailyBackupDatedWarning]`, where
  `DailyBackupDatedWarning` holds the set's `day` (`yyyy-MM-dd`) and the `warning`, newest first.
  The manifest format doesn't change.
- **An `unreadable` or `missing` warning is resolved**, and left out, when a later set in the window
  lists that path in `files` with no `unreadable` or `missing` warning of its own. A fallback copy is
  still listed in `files`, so the warning check matters. `shrank` warnings are never resolved.
- **Settings text**, using the day's medium date with no time:
  - `unreadable`: `Nov 3: couldn't read <path>; kept the day before's copy`
  - `missing`: `Nov 3: <path> was missing`
  - `shrank`: `Nov 3: <path> has fewer lines than the day before`

### Mac: a stale snapshot is retried, and failures say where

- **An hourly staleness check.** `runSnapshotLifecycle` also runs a loop on `clock`: every hour,
  if the snapshot file is at least `snapshotStaleInterval` (6 h) old, it calls
  `refreshSnapshot(requestingPermission: false)`. It runs beside the request loop and ends when the
  lifecycle's task is cancelled. The existing guard stops a second refresh while one is running.
  A success clears `librarySnapshotError`, as it does today.
- **The timeout names the step.** The snapshot read records the step it's on before each event:
  the bulk property key, such as `dateAdded`, then `playlists`. `MusicAppLiveError.timedOut` gains
  an optional step. The snapshot's message becomes `Music did not respond in time (reading
  dateAdded). It may be busy or blocked on a dialog; Vinyl Fever will try again within the hour.`
  Other timeouts keep today's text. Use a small lock-protected box shared by the detached read and
  the timeout task.
- **Log refresh failures.** Use an `os.Logger` (subsystem `com.jonphillips.vinylfever`, category
  `library-snapshot`). Log each failed refresh at `.error` with whether it was a launch, hourly,
  requested, or manual refresh, the elapsed seconds, and the message. Log successes at `.info`
  with the track count and seconds.

## Decisions

1. **Skip, don't default.** Treating a missing `artistName` as `""` would fix only today's item.
   Skipping covers any item Apple sends that doesn't decode. A skipped track can't count as already
   there or as kept, and for a song with no artist that match was unreliable anyway.
2. **Keep stays all-or-nothing.** Once bad items are skipped, what's left is network or
   authorization failure, which hits every playlist at once. Showing a row it couldn't check would
   risk a duplicate append. Naming the playlist is enough to diagnose.
3. **No retry inside the snapshot read.** The stalled event may still be pending in Music, so an
   immediate second read could hit the same stall. The second probe run, minutes later,
   recovered. The 120 s budget stays.
4. **Resolution is read from later sets, not stored.** The manifest records what happened that
   night. Whether it still matters is worked out when Settings reads it, so no format changes.
5. **No change to the bad track.** Jon's library is his. The app has to cope with songs like this
   one.

## Done when

- **Mobile tests** (`VinylFeverMobileTests`):
  - the track decoder, fed a page with a good item, the *Undeniable* item above, and an item with
    no `attributes`, returns one track, two skipped ids, and the page's `next`;
  - a page with no `data` key still throws;
  - the playlists decoder skips an item with no `name`;
  - `PlaylistKeepModel`: when `tracks` throws for one playlist, `errorMessage` begins with that
    playlist's name;
  - `PlaylistProgressModel`: when `tracks` throws, `refreshFailure` names the playlist, and the cached
    results stay. A later successful refresh clears it. A listening-log failure sets
    `hasUnreadableListeningLog`, and `refreshFailure` stays `nil`.
- **Core tests** (`DailyBackupTests`, temporary folders):
  - three sets: day 1 has `unreadable` for a path, and days 2 and 3 list it cleanly. Nothing is
    returned;
  - the same with day 3 still `unreadable`. Day 3's warning comes back with its day, and day 1's
    doesn't;
  - a `shrank` warning followed by clean sets is still returned;
  - results are newest first.
- **App tests** (`PlaylistBuilderModelTests`, test clock):
  - a snapshot 7 h old at launch refreshes once. Advancing an hour with the store reporting a
    fresh file doesn't refresh again;
  - a launch refresh that throws `timedOut` sets `librarySnapshotError`. Advancing an hour with a
    working client refreshes, writes the snapshot, and clears the error;
  - cancelling the lifecycle task stops the hourly loop.
- The full set in `docs/verification.md` passes.
- Closeout (ADR-0005 D16) records the gate below.

**What tests can't show:** a real Music stall, and Apple's real response. The decoder test uses
Apple's item copied above. Name both in the PR.

**The architect's review probe:** run the merged decoder against live Apple Music in a scratch
build, over all 11 keepers playlists, and confirm 113 − 1 tracks for *Undeniable* with one skip.

**The gate.** Keep the Jeffrey Osborne track in *Undeniable* as it is until this passes. After
the Mac and iPhone installs:

1. On the iPhone, open a staged playlist and tap Keep on a song. The sheet lists the keepers
   playlists, *Undeniable* included, with no error.
2. Pull to refresh the shelf. The two 2026-11-11 playlists show progress, and songs Jon has played
   since the last hourly poll show as Passed or Kept.
3. Mac Settings → Backups shows "No warnings in the last 30 days". The 2026-11-03 warning is
   resolved.
4. Leave the Mac app running for over an hour. The Playlists screen shows a fresh library snapshot
   date. If it doesn't, run
   `log show --last 2h --predicate 'subsystem == "com.jonphillips.vinylfever" AND category == "library-snapshot"'`
   and paste the output into the PR.

## Out of scope

- **Fixing the Jeffrey Osborne file's tags.** That's Jon's call, after the gate.
- **Why Music stalls.** Music had been running for 5 days. The log from step 4 is the evidence
  if it recurs.
