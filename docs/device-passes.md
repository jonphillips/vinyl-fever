# Device passes

**Status:** Jon's list of owed real-device gates and held setup steps (jon-platform ADR-0005 D1).
**Summary:** Everything Jon owes before a slice counts as verified, in one place. `NEXT_UP.md`'s
**Owed** line points here, and `jon-platform/scripts/outstanding` lists the sections.

The executor never reads this file. A gate's full steps live in its milestone's slice section,
and this list names it and says where. When a gate passes, its line is deleted here and the pass
goes in `DONE-LOG.md`.

## Device gates owed

- **Listening settings: the two-Mac check.**
- **M17 S2:** two mini-saved weeks, then Jon checks a finished week
  ([M17](milestones/archive/M17-taste-intelligence.md)).
- **M17 S3:** a Music Feedback note in the car, read back word for word, then a playlist note.
  M18's prerequisites carry it too ([M18](milestones/M18-taste-outcomes.md)).
- **M18 S2:** for two New Music weeks, chat picks before listening, then read `taste_baselines`
  after 14 days, or once Jon finishes the week in chat
  ([finish-new-music-week](efforts/archive/finish-new-music-week.md)). Staging passed 2026-10-28
  ([M18](milestones/M18-taste-outcomes.md)).
- **M18 S7:** create an inbox playlist, confirm it's pending immediately, then confirm its Music
  ID is adopted after sync and refresh.
- **M18 S8:** replaces S6's steps 2–4. It needs two open questions. The soft-vocal pair was
  answered 2026-10-29, so it waits for the chat to record new ones.
- **M20 S1:** six steps, after install on the iPad and iPhone. Step 5 covers S0's unprobed
  CarPlay write ([M20](milestones/M20-music-feedback-intent.md)).
- **M20 S2:** seven steps, after install on iPhone or iPad: the two why-with-reason songs, the
  without-reason song, the unrecommended song, one locked/CarPlay run, the repeated-Cancel
  check, and an unpicked New Music song.

- **M21 S1:** four steps on the iPad and the iPhone: the list, *2023 Selections*, *Rolling Stone's 200…*, and Setup still working. It can run with S2 and S3's gates ([M21](milestones/archive/M21-playlists-view.md)).
- **M21 S2:** six steps on the iPad or iPhone: artwork, starting playback from a tapped song, and switching between two playlists on iPad; playing a “Sounds like” song then resuming the playlist; Lock Screen continuation; scroll performance and unavailable songs; renamed staged playlist fallback; and confirming plays appear in `recent_listening` after the next hourly poll ([M21](milestones/archive/M21-playlists-view.md)).
- **M21 S3:** five steps on the iPad or iPhone: Keep a 2020+ song and confirm Vinyl Fever Keepers and its year's Selections in Music; Keep a pre-2020 song and confirm only Vinyl Fever Keepers; open Keep again and confirm “Already there”; confirm subscription and Apple playlists never appear; refresh the laptop snapshot and confirm `kept_and_passed` lists both songs as kept in a new chat ([M21](milestones/archive/M21-playlists-view.md)).
- **M21 S4:** four steps on the iPad or iPhone: leave typed and dictated notes on two songs in *2023 Selections* and confirm both appear under their songs; confirm `taste_notes` returns both word for word on the right songs in a new chat; confirm an earlier Music Feedback note appears under its song; confirm “Cancel” saves nothing ([M21](milestones/archive/M21-playlists-view.md)).
- **M22 S1:** on iPhone and iPad in *2023 Selections*, confirm the title has full width and Play, Keep, and Note fit as labeled capsules on their own row; keep a song and confirm Keep reads Kept in green; confirm a song note is serif italic beside a rule while `why` stays in the body font. “You asked” in serif italic is checked by S4 step 1 on a newly staged playlist ([M22](milestones/archive/M22-playlist-progress.md)).
- **M22 S2:** on iPhone and iPad, confirm *2023 Selections*' bar matches what you've heard and kept; verify a song kept directly in Music shows Kept with all keeper playlist names, a played unkept song shows Passed, and an unheard song shows Not heard yet; after the hourly poll, pull to refresh and confirm a newly played song is Passed and the bar grows; check recent kept songs against `kept_and_passed` in a new chat ([M22](milestones/archive/M22-playlist-progress.md)).
- **M22 S3:** on iPhone and iPad, delete a staged playlist you're done with in Music, pull to refresh, and confirm it's under Archived with “No longer in your Music library.” and its songs still play; have the chat stage a new playlist and confirm it's under Active straight away; confirm Active opens by default and both segment counts are right ([M22](milestones/archive/M22-playlist-progress.md)).
- **M22 S4:** install the Mac build, start a new chat so it refreshes the tool list, stage a playlist, and confirm the app shows the exact request under “You asked” with the chat description in plain type above it; confirm *Sam Fender — Manchester 2027 Catch-Up* shows its older request under “Request” in plain type ([M22](milestones/archive/M22-playlist-progress.md)).
- **M23 S1:** failed 2026-11-02: the Work chat saved Jon's two statements only after he asked about the rule. Re-run as part of [review-keeps-from-phone](efforts/archive/review-keeps-from-phone.md)'s gate.
- **review-keeps-from-phone:** Phone outcomes: on iPhone, keep a staged song, tap Done listening without opening Mac Vinyl Fever, and confirm the monitor review counts the keep. On Pop with Bite, tap Not done then Done listening, confirm the new review counts keeps, save Your reaction, and find it via taste_notes. ([brief](efforts/archive/review-keeps-from-phone.md))
- **review-keeps-from-phone:** Unprompted taste notes: after install, quit and reopen ChatGPT, then make two unprompted taste statements in a new Work chat. Verify both strings arrive word for word in notes-chat-<host>.jsonl and each reply confirms it is saved. ([brief](efforts/archive/review-keeps-from-phone.md))
- **evicted-icloud-writes:** After installation, evict the recommendations JSONL file; ask chat to record New Music picks and confirm recorded: true plus the batch in recommendation_outcomes. ([brief](efforts/archive/evicted-icloud-writes.md))
- **finish-new-music-week:** After installing on the Mac, finish a live New Music week in a new chat; confirm the snapshot updates without touching the Mac, then confirm a keep synced from the phone appears in the review outcomes. ([brief](efforts/archive/finish-new-music-week.md))
- **M24 S1, M24 S2:** On iPhone and iPad, start 2023 Selections and confirm artwork, previous/play-pause/next, Lock Screen pause tracking, playback started in Music, queue-clear hiding, and no overlap with the last song. On iPhone, confirm a Siri note reads Noted, a newly saved note updates immediately, and an unnoted song still reads Note. Jon takes one screenshot on each device. ([M24](milestones/archive/M24-phone-finishes-playlists.md))
- **M24 S3, M24 S4:** Install and start a new chat; stage a playlist with one live upload; confirm only that track has upload: true and the artist-alias mirror exists in iCloud; create it on the Mac and confirm the created line; stage and dismiss a second playlist and confirm its dismissed line. ([M24](milestones/archive/M24-phone-finishes-playlists.md))
- **M24 S5:** Away from the Mac, with the laptop awake: ask ChatGPT on iPhone to stage a short playlist with one live upload; refresh and create it in Music, choose or skip ambiguous songs, confirm the upload match and playback/player strip; back at Mac confirm the inbox is filed and the playlist role appears; the next day delete the playlist in Music and confirm it moves to Archived. ([M24](milestones/archive/M24-phone-finishes-playlists.md))
- **phone-remembers-shelf:** After install, force-quit and relaunch to confirm the shelf, Active/Archived counts, and progress appear immediately; keep a song and relaunch to confirm it remains kept; delete a finished playlist in Music and confirm it moves from Active to Archived after refresh. ([brief](efforts/archive/phone-remembers-shelf.md))
## Setup steps held for Jon

- **Before M20 S1's gate:** the one-action "VF Music Feedback" shortcut, picked in Control
  Center on both devices; and TestFlight for the iPhone companion (M20 *Prerequisites*).
- **After M20 S1's gate:** point Siri's "Music Feedback" at the intent, and Control Center at
  "Music Feedback" (M20 *Prerequisites*).
- **Stop Music Feedback writing empty lines** (M18 Decision 16): in the shortcut, stop without
  writing when the dictation is empty or "Cancel" (M18 *Prerequisites*).
- **Fix the laptop's Time Machine:** the SMB share on `PhillipsWest` doesn't mount
  ([M19](milestones/archive/M19-backups.md), its one unticked box). Delete this line if it's
  already fixed.
