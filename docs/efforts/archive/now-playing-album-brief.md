# Now-playing album brief and queueing

**Status:** Designed, parked 2026-10-30 (ADR-0005 D10). Restore it to `docs/efforts/` in the plan PR that schedules it.
**Summary:** Ask the chat about the song that's playing and get a brief against Jon's own evidence, then queue tracks without a playlist. Its first intent shipped as M20; the brief tool and queueing aren't planned.

Moved from `open-questions.md` as written (D14).

**Now-playing album brief, and the iPhone companion** (Jon and the architect,
2026-10-27). Jon wants to be on a song in Music on his iPhone, ask ChatGPT "tell me about this
album and artist," and get more than a bio: where the artist sits against his own evidence,
and particular tracks to try. Then he wants those tracks queued without making a playlist.
**The iPhone companion is decided. The features aren't planned yet; the probes come first.**
**Planned 2026-10-29:** Music Feedback, the first intent, is
[M20](../../milestones/M20-music-feedback-intent.md). The app runs on iPhone and iPad (M20 Decision 3),
and it identifies the song without ShazamKit (M20 Decision 2), because Siri pauses the music
for dictation. The rest of this entry is still unplanned.
- **The brief.** A new read-only vf-mcp tool, working name `album_brief(artist, album,
  track?)`, returns everything in one call so the phone isn't waiting on several round trips:
  - **From the Apple Music catalog:** a search that resolves the title, artist, and album to
    catalog IDs; the album's tracklist and editorial notes; the artist's top songs
    (`view/top-songs`, which is Apple's popularity and is labeled as such); other albums, the
    latest release, and similar artists.
  - **From Jon's evidence,** for each album track and top song: in the library, playlist
    roles, heard in the listening log, recommended before and the outcome, passed in New
    Music. Plus his taste notes about the artist and the `artist_profile` stats. Most of this
    is `check_tracks` and `artist_profile` today; the new tool runs them across a tracklist.

  The chat writes the bio from its own knowledge or web search and does all the evaluation, as
  in M17. A recipe in vf-mcp's server instructions sets the shape: a short bio; where the
  artist sits against named keepers, never judged by genre; and three to five tracks, each
  labeled already Jon's, the hit, or a deep cut likely for him. The suggested tracks go to the
  recommendation ledger as a new source, so M18's outcomes measure them.
- **Queueing without a playlist.** The Apple Music web API has no playback or queue
  endpoints. From a server, a playlist is the only thing it can build, and it can't remove
  tracks from one. Up Next can only be changed on the device, through MusicKit
  (`SystemMusicPlayer.shared.queue.insert(_:position: .afterCurrentEntry)`). So a
  `queue_tracks` vf-mcp tool resolves catalog IDs, logs the picks to the ledger, and writes a
  disposable queue request to iCloud Drive (the PlaylistInbox pattern); an iPhone intent then
  inserts the songs.
- **Why this song, and auditioning picks** (Jon, 2026-10-29). *"Why this song?" is planned as
  [M20 S2](../../milestones/M20-music-feedback-intent.md) (2026-10-30); the audition view comes after it.* Two miles into a walk, a
  recommended song comes on and Jon wants to know why the chat picked it. The answer is
  already on iCloud Drive: since M18 S2, each staged song's ledger line carries the chat's
  `why`, up to three `like` songs it was explained against (with `found`), and the batch's
  `request` and `playlist`. On 2026-10-29 the laptop's ledger had 40 songs: 25 with a `why`
  and 15 with `like`. The songs without one came from the batch staged before S2, or had no
  reason-songs to cite. So the companion needs no chat round trip and no new vf-mcp tool. It
  reads `Taste Intelligence/recommendations/*.jsonl`, every host's file.
  - **A "Why this song?" intent.** It identifies the song as Music Feedback does, finds its
    latest ledger entry, and *speaks* the answer through the intent's dialog: the `why`, the
    `like` songs, and which playlist and request it came from. It has to work hands-free, on
    a walk or through CarPlay. It doesn't depend on the chat route (probe 1), so it can come
    before the album brief. When there's no entry, it says so: "Vinyl Fever didn't recommend
    this one."
  - **An audition view in the app.** Recent batches, each song with its `why` and `like`.
    Tapping a song plays it, and tapping a `like` song plays that next, for comparison.
    Feedback from this view goes through the Music Feedback path to the same notes file, so
    M18's outcomes don't get a second judgment channel. The view never writes the ledger.
  - **Limits:**
    - Only staged songs have a reason. A longer explanation in the chat isn't kept, and
      `why` is one sentence (at most 300 characters), which is the right length to speak.
    - The ledger has no catalog IDs, only artist, title, album, and year. Matching is on
      normalized title and artist, so live versions and remasters can miss. This joins
      probes 2 and 5: if the now-playing entry carries a catalog ID, consider recording
      catalog IDs on new ledger lines (an optional field; the ledger stays v1).
    - Optimize Mac Storage already evicts the iCloud taste files on the laptop, and iOS
      evicts too. The reader requests the download and reads through file coordination;
      it never assumes the file is local. A file it can't read means "no answer yet", not
      "not recommended".
- **A Vinyl Fever iPhone target with App Intents.** This is the first iPhone version of
  Vinyl Fever, not a separate helper app, and not part of Cockpit or jon-platform:
  - Intents run in the app that owns the domain and the MusicKit entitlement.
  - Cockpit's `ARCHITECTURE.md` keeps music integrations app-local (§15) and rules out a
    shared queue (§13).
  - Jon's other apps are already iPhone apps and get their own intents. A shared phone host
    is worth asking about only if a second Mac-only app needs a phone presence (jon-platform:
    "first use establishes a requirement").

  Intents are more dependable than hand-built shortcuts here: the logic is typed, tested Swift
  in git, and they get MusicKit and ShazamKit, which a shortcut can't use directly. Shortcuts
  stays the trigger: `AppShortcutsProvider` exposes the intents to Siri (including CarPlay),
  the Action button, and Control Center. The target shares Vinyl Fever's packages and starts
  with three intents:
  1. **Music Feedback** replaces the shortcut, as [taste-intelligence.md](../../taste-intelligence.md)
     *Architecture* planned. It writes the same JSON line to `Taste Intelligence/notes.jsonl`,
     so nothing on the Mac changes. It identifies the song from `SystemMusicPlayer`'s
     now-playing entry, then ShazamKit in the app, then the time only, with the same
     `now-playing`, `shazam`, and `time-only` labels. It goes first because it already has a
     format, a log, and daily use.
  2. **Album brief** identifies the song the same way and opens the chat with the prompt.
  3. **Play Next from Vinyl Fever** reads the queue request and inserts the songs into Up Next.
- **Decided (Jon, 2026-10-27): the iPhone companion with App Intents is approved.** File
  and shell work stays on the Mac. `AGENTS.md`, *Platform Stance* in
  [product-requirements.md](../../product-requirements.md), and
  [technical-architecture.md](../../technical-architecture.md) now say so. The target touches no
  files on disk: it reads and writes the iCloud logs and drives Music's queue. Its plan owes
  the setup: an App ID, a profile, and TestFlight builds (jon-platform
  `docs/ios/testflight.md`).
- **Probes (S0-sized):**
  1. **The chat route.** Can a chat started from an intent or a shortcut open in the right
     ChatGPT project with the vf-mcp connector usable? Voice mode probably can't call tools.
     If no route works, the fallback is copying the prompt and opening the ChatGPT app.
  2. **First hearing.** On a first hearing `Get Current Song` is blank (taste-intelligence
     *Evidence*). Does `SystemMusicPlayer`'s now-playing entry carry a title and catalog ID
     when it is? If not, ShazamKit is the first-hearing path.
  3. **The queue.** Can an intent insert catalog songs into Up Next without bringing the app
     forward? And do Shortcuts' own Add to Playing Next and Playing Last actions accept
     catalog songs that aren't in the library? If they do, the queue intent may not be needed.
  4. **Who calls the catalog.** vf-mcp makes no Apple Music API calls today. The app and
     `VinylFeverListening` do. Decide whether vf-mcp calls the catalog for the brief, or the
     iPhone resolves catalog IDs and passes them in the prompt.
  5. **Matching and speed.** How often does the album name from Music or Shazam match a
     catalog search cleanly? Is the round trip quick enough to be pleasant on the phone?
