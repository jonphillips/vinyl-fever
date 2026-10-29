# Open Questions

The architect's and Jon's scratch pad: candidates, parked work, and decisions for Jon's review.
**The executor never reads this file** (jon-platform ADR-0005). Work becomes dispatchable only when a
plan PR moves it into a milestone or effort and sets `docs/NEXT_UP.md`.

## Candidates & parked work (moved from `CURRENT_HANDOFF.md`, 2026-09-29)

- **M4 Reconcile fast-follow** — re-point the registry entry when identity drift is found, and sharpen
  same-title/different-owner duplicate detection
  ([ledger](milestones/M4-compilation-album-append.md)). **Evidence-gated by design:** build it only when
  a real append spawns a `Great Covers 2` drift. None observed in daily use yet.
- **Pending Jon decision — M4 identity-drift (#2/#3).** Decide identity-match forgiveness and no-match
  behavior *when* a real append mangles a title. Parked until the evidence appears.
- **LLM song list → Apple Music playlist** — [M11](milestones/M11-song-list-playlist.md) shipped
  in #66 (S0) and #67 (S1 + S2, merged 2026-10-15). Jon passed the on-device gate on
  2026-10-17. Settled in the feasibility pass: hand-roll the Apple
  Music API create call rather than depend on MusadoraKit; catalog-only for v1; input is a
  pinned ChatGPT Project contract (`VF-PLAYLIST: v1`, Yes Chef/Galavant pattern), not free-text
  parsing.
- **Library context for the playlist chat** — [M12](milestones/M12-library-context-mcp.md)
  **closed 2026-10-18.** The shared `MCPServerKit` effort (jon-platform#74), S0 + S1 (#72), and
  S2 (#76, `vf-mcp` and the playlist inbox) shipped with their device gates passed, and the
  close-out PR folded in the gate's fixes. Decision 1 is **no**: Last.fm (S3) is dropped in
  favor of Apple's recently-played feed ([M13](milestones/M13-listening-history.md)). A Yes
  Chef MCP server, reading its synced database read-only, is the likely second `MCPServerKit`
  consumer and starts by spiking app-group container access (ADR-0007 *Open*). Galavant waits.
- **Listening history** — planned as [M13](milestones/M13-listening-history.md) (2026-10-18):
  an hourly poller of Apple's recently-played feed. It runs as a separate macOS 26 app on the
  Intel Mac mini, with the same engine inside Vinyl Fever for the laptop now and an
  Apple-silicon mini later. The log lives in iCloud Drive, and `vf-mcp` gains
  `recent_listening` and periods. Merging that plan PR approves its Decisions 1–5 and
  dispatches S0. S0 landed in #83 (2026-10-18). Dispatch 2 (S1) needed only the developer-portal
  App ID and profile, which are done. Owed by Jon before the S1 gate: the mini's macOS 26
  check, Optimize Mac Storage off, and adding the mini to the profile (M13 *Prerequisites*).
  The mini is on the profile as of 2026-10-19. The mini's last macOS turned out to be 15
  Sequoia, not 26, so Decision 2 was amended the same day. The poller and
  `VinylFeverListening` (now its own package) target macOS 15. The probe evidence moved into the milestone.
- **Listening analytics: what the log is for** (Jon, 2026-10-20). The M13 log is gathering
  data before there's an analytical strategy, and Jon is fine with that. Directions he named:
  - **Varying his listening:** what he's been on, and how to steer him away from ruts.
  - **Heard, then chosen:** which recently played songs he then added to a playlist. That's a
    much stronger signal than a play, and Vinyl Fever sees the playlist side (M11, M14).

  **Parked: filtering short plays.** The feed counts starts (M13 *Fidelity*). Polling every
  couple of minutes could estimate listened time from the gap between one song's appearance
  and the next. It can't size the last song of a session, and Jon didn't want the request rate
  or the precision before a use exists. Revisit when an analysis needs listens rather than
  starts.

  The analytical strategy is now *Taste Intelligence*, planned as
  [M17](milestones/M17-taste-intelligence.md) (2026-10-23).
- **Taste Intelligence** — **planned as [M17](milestones/M17-taste-intelligence.md)
  (2026-10-23)** from the v1 design in [taste-intelligence.md](taste-intelligence.md)
  (Jon and the architect, 2026-10-20, from a Codex brief). Vinyl Fever learns Jon's taste from
  evidence he already produces and lets the chat do the reasoning, aiming at "15 songs I
  probably don't know but will love, explained, and learn which stick." Key findings:
  - Explicit signals are nearly unused: 19 favorites, 4 dislikes, 70 ratings in 87,114 tracks.
  - **Jon's Selections** (2021–2026, 512 songs) is the strongest signal: songs from the current
    year he adds as he hears them.
  - **Replay** 2018–2026 is in the library now, ranked; pre-2018 data is a shared family
    account and is excluded.
  - **New Music** is graded in full every week, so kept vs passed is a real contrast, and its
    keep rate is Apple's discovery yield, the baseline to beat.
  - Keep is Jon's native add to Selections, and Pass is inferred from New Music heard and not
    added, so neither needs a tap. One shortcut, **VF Note** (renamed **Music Feedback** on
    2026-10-25), captures his spoken reasons from
    CarPlay, Siri, or the Action button, with no iOS app. `Get Current Song` is blank on a first
    hearing (it fills in only after the queue moves on), so the shortcut falls back to Shazam's
    `Recognize Music`, then to the time alone.

  S0's probes finished 2026-10-23. M17: S1 playlists in the snapshot with roles, S2 exposure
  and curation logs, S3 feedback (VF Note and chat notes); then an outcomes milestone.
  S1 merged in #125 (Jon's gate passed 2026-10-24: all 15 new, 11 kept), S2 in #126, and S3 in
  #129 (both 2026-10-25, gates owed). M17's code is done.

  **Outcomes planned as [M18](milestones/M18-taste-outcomes.md) (2026-10-25).** Jon noted that
  "beat New Music" isn't a fair contest: the chat's first batch spanned 2006–2024, New Music is
  this month's, and a chat model knows least about new releases. M18 logs every staged
  recommendation with per-song familiarity (S1), then reports outcomes by source within
  release-age bands and tests the chat on New Music's own weeks with blind picks (S2). Apple's
  candidates for new releases (S3) wait on that result. **S1 merged as #132 (2026-10-25); Jon's
  stage/check gate is owed.** **The chat's questions, from the never-merged plan PR #127,
  were added as M18 S4 after S2 (2026-10-25); #127 is closed as superseded.**
- **Now-playing album brief, and the iPhone companion** (Jon and the architect,
  2026-10-27). Jon wants to be on a song in Music on his iPhone, ask ChatGPT "tell me about this
  album and artist," and get more than a bio: where the artist sits against his own evidence,
  and particular tracks to try. Then he wants those tracks queued without making a playlist.
  **The iPhone companion is decided. The features aren't planned yet; the probes come first.**
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
  - **Why this song, and auditioning picks** (Jon, 2026-10-29). Two miles into a walk, a
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
    1. **Music Feedback** replaces the shortcut, as [taste-intelligence.md](taste-intelligence.md)
       *Architecture* planned. It writes the same JSON line to `Taste Intelligence/notes.jsonl`,
       so nothing on the Mac changes. It identifies the song from `SystemMusicPlayer`'s
       now-playing entry, then ShazamKit in the app, then the time only, with the same
       `now-playing`, `shazam`, and `time-only` labels. It goes first because it already has a
       format, a log, and daily use.
    2. **Album brief** identifies the song the same way and opens the chat with the prompt.
    3. **Play Next from Vinyl Fever** reads the queue request and inserts the songs into Up Next.
  - **Decided (Jon, 2026-10-27): the iPhone companion with App Intents is approved.** File
    and shell work stays on the Mac. `AGENTS.md`, *Platform Stance* in
    [product-requirements.md](product-requirements.md), and
    [technical-architecture.md](technical-architecture.md) now say so. The target touches no
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
- **Familiarity when evidence can't be read** (from the #132 review, 2026-10-25). At staging,
  M18 S1 treats an unreadable listening log or notes file as empty, so the ledger records those
  songs as unfamiliar, permanently. **Recommendation, for S2's plan:** each ledger batch records
  which evidence it could read (for example `coverage: {"listening": false}`), and S2's outcomes
  leave out batches recorded without listening evidence, or mark them. Decide before S2 is
  dispatched. **Decided 2026-10-25:** added to M18 S2 as Decision 12 (coverage on every batch,
  and an uncovered batch is listed but not scored).
- **Backups** — planned as [M19](milestones/M19-backups.md) (2026-10-25). Jon asked about data
  loss. The logs live only in iCloud Drive, the database only on the laptop, and the laptop's
  Time Machine last finished on 2026-02-15 (its SMB destination doesn't mount). S1 makes a
  daily set from the hourly agent: the iCloud logs go to local disk, the database goes to local
  disk and iCloud, and a log that shrinks raises a warning. It runs before M18 S2. Jon owes the
  Time Machine fix.
- **The executor posted as Jon** (from the #126 review, 2026-10-24). One of Codex's PR comments
  was posted as `jonphillips`, not `jon-codex-bot`, so at least one of Codex's shells reaches
  Jon's `gh` keyring login. Later comments came from the bot. **For Jon:** check which shell or
  tool Codex used for that comment, and make sure only the bot's token is available to it. The
  split between the two identities is what makes native reviews work.
- **Live tracks in playlists** — planned as [M14](milestones/M14-live-tracks-in-playlists.md)
  (2026-10-18). It interleaves with M13: S0 after M13 S1, S1 after M15 S0 (order amended
  2026-10-20, M14 Decision 3). Probes on 2026-10-18 showed:
  - One API create call mixes catalog songs with Jon's uploaded live tracks, in order, and they
    play on his iPhone (Jon checked).
  - Library song search stops at 100 results per term, but searching his library's albums by
    the show's name and then reading the album's tracks reaches every upload. The two routes
    together found 40 of 40 sampled uploads.
  - Jon's library: 54,166 uploaded, 26,977 matched, 5 ineligible, and none waiting to upload.
    Uploaded plus matched is about 81,000, against iCloud Music Library's 100,000-song limit.
  - The full evidence is in the milestone. Merging that plan PR approves its Decisions 1–4.
    M13 S1's completing PR (#85) dispatches M14 S0.
  - **S0 merged as #89 and its device gate passed (2026-10-20).** The review added Decision 5:
    on the library route, artists match by whole-word prefix, because most of Jon's uploads
    carry variants such as `… & The E Street Band (Live)`. S1's `uploadedAlbums` uses the same
    rule.
  - **Decision 5 is superseded by [M15](milestones/M15-artist-identity.md)** (2026-10-20), which
    gives every artist comparison one `ArtistIdentity`.
  - **S1 merged as #97, and its device gate passed (2026-10-20). M14 is complete.** The gate's
    Tunnel of Love mix led to the library duplicates report below.
- **Artist identity** — planned as [M15](milestones/M15-artist-identity.md) (2026-10-20), after
  Jon asked why artist matching kept coming back. A probe of his 87,115-track library found
  three kinds of mismatch: band and live suffixes (34,909 tracks across 293 keys), spelling
  noise ("The" and apostrophes), and true aliases (44 overlap candidates, about half real). S0
  is one rule with duet credits. S1 is an alias list Jon approves in Settings. The order is
  M13 S2 → M15 S0 → M14 S1 → M15 S1 → M13 S3, so M13 S2's completing PR (#93) dispatches
  M15 S0.
  - **S1 (#101) went back for changes (2026-10-20).** On the real snapshot its finder returned
    2,958 candidates, because the joined-words rule had become a prefix rule. A Different click
    could also delete an accepted alias. Jon approved the schema fix: one row per
    (variant, canonical) pair, with one accepted alias per variant. The milestone now adds an
    inserted-word shape and expects about 100 candidates at the gate.
  - **S1 merged as #101, and its device gate passed (2026-10-21). M15 is complete.** Jon worked
    through all 100 candidates (73 accepted, 10 rejected).
- **Artist Aliases sheet follow-ups** (from the #101 review and M15 S1's gate, 2026-10-20/21).
  - **Adding an alias by hand.** The finder can't propose an alias without evidence in the
    library. `john cougar` (4 remixes) shares no titles with `john mellencamp`, and
    `on a friday` (Radiohead's early name) shares 3 titles, one short of the threshold. Both are
    real aliases that Jon would have to type himself.
    - **Candidate:** an **Add alias…** button in the sheet. Jon types two spellings, and the
      decision goes through the same store rules as an accepted candidate: base keys, no
      chains, re-pointing.
    - **Jon to decide, now that the gate has passed.** If these two are the only misses, a
      one-off decision row is simpler than new UI.
  - **The direction choice is invisible and doesn't need to exist.** Jon didn't know the two
    **Same artist** buttons pick the canonical spelling, so 49 of his 73 accepted aliases point
    at the smaller key (`bruce springsteen` → `bruce springsteen band`). It doesn't change
    behavior: matching and grouping compare keys, and display names come from track tags. The
    Accepted list is the only place it shows, and it reads backwards. The swap was the
    architect's brief, and it gives Jon a choice that has no effect.
    - **Candidate:** one **Same artist** button, with the key that has more tracks always
      canonical. A one-time migration re-points Jon's 49 rows the same way, and the Accepted
      list shows display spellings instead of keys. Small, cosmetic, and it can ride along with
      Add alias if that's built.
- **Library duplicates report** (Jon, 2026-10-20, from the M14 S1 device gate). Jon asked for a 1988
  Tunnel of Love mix. Two rows went to the picker: Roulette and Chimes of Freedom. ChatGPT had
  sent the exact album, `1988‐07‐03: Stockholms Stadion, Stockholm, Sweden`, with U+2010 hyphens.
  But Jon's library holds that show twice: that copy, plus `1988-07-03 - Stockholms Stadion -
  Stockholm, Sweden`, with 35 tracks each. A third copy is tagged `Summer Night - Cd1 (Stockholm -
  July,3,1988)`. Under `SongTextNormalizer.album` the first two names are identical, so the
  matcher returns ambiguous. Jon would rather see these duplicates than have Vinyl Fever hide them.
  - **Rough size (architect's probe of the snapshot):**
    - 72 uploaded album names (1,237 tracks) collide once case and punctuation are ignored. Some
      are real splits, such as `Moanin' & Howlin'` / `Moanin' And Howlin'` and
      `2019-12-20 Harrisburg, PA` / `2019/12/20 Harrisburg, PA`. Some are different artists'
      albums with the same title, such as `Greatest Hits`.
    - 129 artist-and-date pairs have differently named albums. This count is crude: a date
      regex and a rough artist key.
  - **Candidate:** a read-only report, built from the snapshot, that groups likely duplicate
    uploads by `ArtistIdentity` key with either the normalized album or the show date. Jon fixes
    them in Music.app. Possible surfaces: a Settings sheet like M15 S1's alias review, or a
    `vf-mcp` tool ("what's duplicated in my Springsteen shows?").
    - It needs a decision on scope: duplicates only, or also near-duplicate album splits such as
      case-only differences.
  - **Decided (Jon, 2026-10-20): no exact-album tiebreak in the matcher.** Preferring the
    upload whose raw album equals the hint would resolve these rows silently and hide the
    duplicates. The picker stays as it is.
- **M11: Create can lose the playlist it just made when a later batch fails** (from the #67
  review, 2026-10-15). `createLibraryPlaylist` sends the first 100 IDs with the create call,
  then appends the rest in batches of 100. If a later batch throws, the error drops the
  `CreatedPlaylistRef`. The model then shows no playlist, and Create again makes a second one.
  This only affects playlists over 100 songs. Candidate fix: throw a typed partial-create error
  that carries the ref and the unsent IDs, so the model enters the post-Create state with those
  rows left over. Low priority until Jon builds a playlist that long.
- **App-target test failing on `main`: `CollectionInboxAppendTests`** (found in the #67 review,
  2026-10-15). `resumingInboxRebuildsFromStagedFilesAndClearsDerivedFolders` hits an
  unimplemented `@Dependency(\.uuid)` (reached through `FileSystemClient`) and fails. It most
  likely dates from #60/#65. It went unnoticed because the executor's host runs macOS 26.6,
  which only compiles the app test bundle; the architect's macOS 27 host is the only place it
  runs. Candidate fix: a one-line `$0.uuid = .incrementing` override in that test. It's small
  enough to fold into the next dispatch that touches the Inbox, or to send as its own small
  effort.
- **Folder-picked compilation appends leave derived folders behind** (from the #65 review,
  2026-10-14). A compilation append builds `Working/` and `Output/` *inside* the user's picked
  folder, and after #65 `Output/` holds a copy of every track. Nothing cleans either one up after
  certify (Inbox appends are drained; live shows have `cleanUpProducedFolders`). Candidate effort:
  offer the same certify-gated cleanup for folder-picked appends, or build them under an
  app-owned scratch root instead of the user's folder.
- **M12: is the 30 s read budget still right for an 87k-track library?** (from the #72 review,
  2026-10-17). **Recommendation: keep the budget and watch it;** revisit if a refresh fails or the
  library grows. M12 assumed about 30k tracks; Jon's library is 87,100, and a full snapshot
  refresh measured 21–25 s at the S1 gate. That leaves about 5 s of headroom.
- **M12: should the launch refresh skip when Music.app isn't running?** (from the #72 review,
  2026-10-17). **Recommendation: yes;** launch refreshes only when Music is already running, and
  the manual **Refresh Library Snapshot** button stays the way to launch it. Today a snapshot
  older than 6 h makes Vinyl Fever launch Music.app at its own launch. Pending Jon.
- **M12: what to do with `LibrarySnapshot.lastfm` now that S3 is dropped** (from the #72
  review, 2026-10-17; updated 2026-10-18). It's typed `Data?`, which would encode as base64, and
  it's always `null`. **Recommendation:** leave it. Drop the field at the next snapshot format
  bump; nothing reads it.
- **M12: sign `vf-mcp` for a distributed build** (from the #76 review, 2026-10-17). The app
  bundles the helper at `Contents/Helpers/vf-mcp` from a post-build `swift build`, and the
  linker only ad-hoc signs it. That's fine for local builds: the app's
  `codesign --verify --deep --strict` passes. An archived or notarized build would need the
  helper signed with the team identity and the hardened runtime before the app is signed.
  **Recommendation:** nothing until Vinyl Fever is archived for anyone but Jon. Then the build
  phase runs `codesign --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime` on the helper.
- **M12: a release build of `vf-mcp` takes about 5 minutes** (from the #76 review, 2026-10-17).
  The Release post-build phase does a full `swift build -c release` of the helper and its
  dependencies in its own scratch path. Debug builds take about 30 s. That only costs Release
  builds and archives today. **Recommendation:** watch it. If archives get frequent, cache the
  scratch path across builds, or build the helper as an Xcode target in the same build graph.

- **Machine ops** — planned as [M16](milestones/M16-machine-ops.md) (2026-10-21). The app's
  database is SQLiteData's default `~/Library/Application Support/SQLiteData.db`, and Debug
  builds erase it on any unknown migration, so opening an older Debug build wipes Jon's aliases.
  S0 moves the database to `VinylFever/VinylFever.sqlite`, refuses instead of erasing, and backs
  up before migrating. It goes right after M13 S3. S1 adds `scripts/install-vinyl-fever` and S2
  adds `scripts/setup-mac`. A manual backup is at `VinylFever/Backups/SQLiteData-2026-10-21.db`.
  **S0 merged as #108, and its laptop gate passed (2026-10-21).** Jon moved the empty
  post-gate `SQLiteData.db` to the Trash and kept `SQLiteData.db.moved-to-VinylFever` for now.
  There's no new Mac mini on order, so S2's gate is the laptop plus the Intel mini.
  **S1 (#110) and S2 (#111) merged 2026-10-21, and their laptop gates passed.** M16 closes when
  Jon's Intel mini poll-role gate passes.
- **The chat ran on an old connector for two days** (2026-10-25). #125's playlist tools merged
  on 10-24, but nothing installed the build, and ChatGPT.app's Codex kept an old `vf-mcp`
  running with a cached list of 7 tools. M17 S1's gate ran without the tools it was testing.
  The fix is planned as [M16](milestones/M16-machine-ops.md) S4 (a build stamp the chat can
  report, and an installer warning about old helpers), plus a rule that every chat gate starts
  with an install and a tool refresh. Telling Jon to "re-copy the Project instructions" was
  also wrong: that text is only the paste fallback (corrected in M18 and the feedback guide).
- **`setup-mac`'s Time Machine check stops at the first destination without snapshots** (from
  the #135 review, 2026-10-26). The loop reads `Destinations.$i.SnapshotDates` for i = 0, 1, …,
  and stops at the first one that's missing. So if Jon adds a second destination and the first
  has no snapshots, the newer one is never read. It errs toward a warning ("no completed
  snapshot found"), never toward a silent pass. **Recommendation:** read the destination count
  first (`plutil -extract Destinations raw`), and skip destinations that have no dates. A
  fixture with an empty first destination and a recent second one gives no warning. Do it with
  the next `setup-mac` change; it isn't worth its own dispatch.
- **The installer's System Events gap and the flaky timing tests** are dispatched as M16 S3
  (2026-10-22). The two entries below stay for history until S3 merges.
- **The installer assumes nothing is running when System Events access is denied** (from the
  #110 review, 2026-10-21). `install-vinyl-fever` asks System Events how many Vinyl Fever
  processes are running. If Automation access to System Events is denied (a fresh Mac's first
  run, with the prompt declined), `osascript` prints nothing, `[[ "" -gt 0 ]]` is false, and the
  install proceeds as if nothing were running. It then swaps out an open app's bundle and deletes
  it. **Recommendation:** have the installer treat non-numeric output as an error ("allow
  Automation for System Events, or quit Vinyl Fever first"), and have `setup-mac` report the
  grant. A small fix for the next dispatch that touches `scripts/`.
- **Listening handover hole** (from the #105 review, 2026-10-21). On a lease handover, plays
  between the old holder's last fetch and the new holder's baseline are absorbed by the baseline.
  `coverage` doesn't report that window as a gap, which conflicts with M13's "gaps and failures
  are loud". **Measured at the M13 S3 gate (2026-10-22):** the mini → laptop hole was 40 minutes
  and absorbed 19 real plays (Jon was listening and skipping); `coverage` showed no gap. The
  laptop → mini hole was 80 minutes with no plays lost. The poller app doesn't fetch when it
  takes the lease; it waits for its next hourly run. So a hole can approach two poll intervals,
  not one. **Recommendation:** have the new holder diff its first fetch against the old holder's
  last list, and log what it finds as plays. That's exact and recovers all 19; reporting the
  window as a gap would only flag the loss. Fetching right at takeover would shorten the hole
  too, but it doesn't close it. **Planned as M13 S4** (handover recovery), which does both, with
  the gap report as the fallback when the old list can't be read. **Done:** M13 S4 (#119) and S5 (#121). S5's gate
  passed on 2026-10-22, recovering exactly the songs played inside the handover.
- **An idle listening agent can't be stopped on its own** (from the #105 review). While another
  Mac holds the lease, Settings shows this Mac's toggle as off, so the only way to unregister its
  idle agent is to take the lease and then turn polling off. The idle agent's hourly run skips
  and writes nothing. **Recommendation:** a "Stop this Mac's idle agent" button, if an idle agent
  ever matters in practice.
- **Wall-clock tests flake under load** (from the #108 review). Two tests assert absolute timings:
  the M15 index-build ratio (`LibrarySnapshotTests`, "within 1.25x") and Listening's "a year of
  JSONL log files loads quickly" (under 2 s). Both failed with this Mac at load average 60–116
  from system daemons, and both passed when re-run and on `main`. **Recommendation:** move them
  behind an opt-in perf tag, or measure with a generous ratio against an in-run baseline, so
  `swift test` stays a correctness signal.

## V1 Scope

- Which existing script is most important after `music_pipeline.sh`?
- Which remaining steps truly need shell/Python rather than Swift?

## Live Show Prep

- Are the default live-show album title rules in `setlist-formatting-rules.md`
  complete?
- Are the source labels in `setlist-formatting-rules.md` complete, or should
  additional defaults such as `WEB`, `MTX`, or others be added?
- Resolved: see "Verified" in [App Areas](app-areas.md) and Source Of Truth And
  Storage Ownership in [Metadata Policy Model](metadata-policy-model.md). A show
  is verified when its album appears in the Apple Music scan with a matching
  album title and a track count equal to the setlist, with an optional duration
  spot check.
- What Apple Music fields/data should identify an imported album as a live show
  for the chronological artist view?
- What should the local-model live-show label audit flag as "probably mislabeled"?
- Resolved (2026-07-03 review): see *Automation Implications* in
  [Setlist Formatting Rules](setlist-formatting-rules.md). The Normalizer is a
  sandwich — deterministic pre-segment (clean + region hints, no decisions) ->
  frontier LLM via `ModelClient` (all semantic judgment, emits structured JSON)
  -> deterministic validate (tags, ALBUM/DATE shape, controlled source vocab, no
  invented source, track-count sanity) -> mandatory human preview. Source of
  truth is what's on the media, not a reconstructed show. Buildable now,
  independent of the M3 beta-3 pause.
- Resolved: the interactive review session ran 2026-07-03 against a 18-file raw
  corpus; outcomes folded into *Automation Implications*. The rules body remains
  open to revision, but the automation boundary is settled.

## Collection Policies

- What are the first Collection Policies to model?
- Should a policy target an Apple Music playlist, a Smart Playlist rule, or both?
- Is ` | ` the final delimiter for multiple Grouping tokens?
- What should happen when imported files already have Grouping values?
- What should the first folder-application workflow do when a folder contains
  mixed artists or already-tagged songs?
- Which fields can a policy change automatically?
- Which fields always require review?

### Compilation-Album (Append) Policy

- Resolved direction: see *Compilation-Album (Append) Policy* in
  [Metadata Policy Model](metadata-policy-model.md). VF appends tracks to
  curated albums that already exist in Apple Music; it never creates albums or
  the silent cover-carrier track. A small SQLiteData registry (~10–20 entries),
  seeded by folder-drop / parent-folder discovery, is the workspace — not a
  library mirror. Album Artist is the owner identity; track/disc strip defaults
  on (per-album toggle); Compilation flag defaults off (per-album override);
  artwork keeps original embedded art and falls back to the collection cover
  only when a song has none.
- Identity drift is the main open risk: the merge key (`Album` / `Album Artist`)
  is read from file tags, but Apple Music may have mutated it on import, which
  silently spawns a duplicate album instead of merging. First-append
  certification checks the exact album exists and its track count went up. Open:
  how forgiving should the match be — exact string only, or trim/normalize
  whitespace and leading articles before comparing? And what should VF offer when
  the check finds no matching album (block, warn-and-proceed, or open a
  reconcile step to re-point the entry at the real album)?
- Open: when seeding an entry from a folder whose files disagree on `Album` or
  `Album Artist`, which value wins — most common, first, or prompt?

## Metadata Management

- What exactly belongs in Metadata Management versus Collection Management?
- Is Apple Music remediation part of Metadata Management, or should it become its
  own app area later?
- Which first metadata-repair workflow would make this area concrete?

## MusicBrainz and Artwork

- For song-level lookup, what release types should be preferred by default?
- How strongly should various-artist compilations be penalized?
- Are there cases where VA compilation artwork is desired?
- Should cover art be fetched only from MusicBrainz-linked sources, or can the app
  use other sources later?
- Should lookup decisions be cached permanently?

## Apple Music Remediation

- Resolved direction: the read/verification surface is decided early, not later.
  Default to AppleScript/ScriptingBridge as the primary read surface with
  `Library.xml` as a fallback; see Verification Surface in
  [Technical Architecture](technical-architecture.md).
- Should the app ever automate deletion from Music.app, or only prepare manual
  reimport packages?
- What fields does Music.app most often fail to refresh?
- What is the safest manual reimport checklist?

## File Safety

- Should every source file get SHA-256 checksummed before a run?
- Should checksums be required only for destructive or source-mutating workflows?
- Should the app maintain an archive folder for replaced files?
- For failed or unapproved live-show runs, how long should generated `Working/`
  folders be kept before cleanup?

## iPad Companion

- The iPhone companion comes first (approved 2026-10-27; see *Now-playing album brief, and the
  iPhone companion* above). Its packages would serve an iPad later.
- Which screens would be useful away from the Mac?
- Should work queues and metadata policies sync through CloudKit eventually?

## Shared Components

- Extraction trigger: when Vinyl Fever starts consuming model access (Phase 5),
  lift Galavant's `GalavantAI` into a neutrally-named shared package both apps
  depend on, per `jon-platform/docs/adr/0001-extract-model-layer.md`. Confirm the
  path: depend on the extracted shared package (intended), copy/vendor for now, or
  defer AI until after extraction. Recommendation: rename-and-move at Phase 5; do
  not pre-extract and do not copy.
- Resolved (2026-07-03 review): setlist normalization targets the frontier /
  BYO-key tier. The prose-inference, dirty-OCR, and multi-line-jam cases in the
  raw corpus lean on reasoning quality the on-device/Apple-cloud tier cannot yet
  be assumed to reach, so the feature is BYO-required. See *Automation
  Implications* in [Setlist Formatting Rules](setlist-formatting-rules.md). A
  tiered on-device-then-escalate approach remains a possible later optimization.
- Does AcoustID fingerprint lookup ever enter scope? If so, it is the only
  non-model credential; decide whether it reuses the shared Keychain key store.
