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
  after 14 days. Staging passed 2026-10-28 ([M18](milestones/M18-taste-outcomes.md)).
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
- **M22 S1:** on iPhone and iPad in *2023 Selections*, confirm the title has full width and Play, Keep, and Note fit as labeled capsules on their own row; keep a song and confirm Keep reads Kept in green; confirm “You asked” and a song note are serif italic beside a rule while `why` stays in the body font ([M22](milestones/M22-playlist-progress.md)).
- **M22 S2:** on iPhone and iPad, confirm *2023 Selections*' bar matches what you've heard and kept; verify a song kept directly in Music shows Kept with all keeper playlist names, a played unkept song shows Passed, and an unheard song shows Not heard yet; after the hourly poll, pull to refresh and confirm a newly played song is Passed and the bar grows; check recent kept songs against `kept_and_passed` in a new chat ([M22](milestones/M22-playlist-progress.md)).
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
