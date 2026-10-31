# Done log

## 2026-10-31 — M22 · S4

Completed `m22/s4-chat-description`: `stage_playlist` records Jon's request and the chat's description verbatim, and the playlist view distinguishes attributed requests from older unattributed ones. The M22 brief is archived at `docs/milestones/archive/M22-playlist-progress.md`.


## 2026-10-31 — M22 · S3 — The archive

- Branch: `m22/s3-archive`
- Result: derived archive status from the authorized Music library read and the 24-hour grace period. Added Active/Archived segments with counts, selection clearing, archived detail copy, and the empty Archived message. Reused the successful library read for playlist progress.
- Verification: VinylFeverNotes (53 tests), VinylFeverListening (51), VinylFeverCore (302), iPhone Simulator (55), Mac app (94), generic iOS Simulator build, generic iOS device build, and `check-handoff` passed.
- Jon's S3 delete-and-refresh and newly staged playlist device gates remain owed with the prior device gates.

## 2026-10-31 — M22 · S2 — Heard, kept, and passed

- Branch: `m22/s2-heard-kept-passed`
- Result: moved the Foundation-only listening log models, codec, reader, and artist identity into `VinylFeverNotes`; added a shared Mac/mobile song key and indexed playlist progress; builds the evidence index off the main actor and updates it incrementally after keeps and notes. Missing listening-log folders now hide statuses until the data is available.
- Verification: VinylFeverNotes (46 tests, including the 50 ms progress-index performance gate), VinylFeverListening (51 tests and its performance suite), VinylFeverCore (302 tests), Mac app (94 tests), iOS Simulator (51 tests), generic iOS device build, and `check-handoff` passed.
- Jon's M22 S2 iPhone and iPad gate remains owed with the prior device gates.

## 2026-10-31 — M22 · S1 — Room for the actions, and Jon's words in his own type

- Branch: `m22/s1-room-actions`
- Result: gave playlist songs a dedicated row of labeled capsule actions and styled Jon's request and notes in serif italic with a leading rule.
- Verification: Listening, Notes, Core, Mac app, iOS Simulator, and generic iOS device builds passed.

## 2026-10-30 — M21 · S4: Notes from the playlist

- Branch: `m21/s4-playlist-notes`.
- Added a playlist note sheet available for every song row, saving `source: playlist` v1 notes through coordinated folder access. Playlist detail now reads notes from all `notes*.jsonl` files, matches title and artist with the shared song matcher, sorts newest first, and shows saved notes immediately. Added package, app, and `vf-mcp` coverage. Made the existing playlist append request encoder use sorted JSON keys so its byte-level golden test is deterministic.
- VinylFeverNotes (31 tests), Listening (55), Core (300), Mac app (94), and iOS Simulator (46) passed. Generic iOS Simulator and device builds passed. Jon's four-step M21 S4 device gate remains owed, along with the prior device gates.

## 2026-10-30 — M21 · S3: Keep a song in Jon's playlists

- Branch: `m21/s3-keep-file-song`.
- Moved playlist roles, the roles codec, playlist song references, and the Apple Music request encoder into Foundation-only `VinylFeverNotes`. Added pure keep-target selection, including the roles-file fallback and date-year handling. The iPhone app now lists editable keeper playlists, marks songs already present, and adds the resolved catalog or library song to selected playlists through paged Apple Music API calls. Each successful row shows where it was kept; failed playlists remain visible with the API reason.
- VinylFeverNotes (29 tests), Listening (55), Core (299), Mac app (94), and iOS Simulator (40) passed. Generic iOS device build and `check-handoff` passed. The opt-in Core performance run still exceeds the one-second threshold for `recommendationOutcomesAtJonsScale`; this slice does not touch that code. Jon's M21 S3 real-keep gate remains owed with the M21 device checks.

## 2026-10-30 — M21 · S2: Artwork and playback

- Branch: `m21/s2-artwork-playback`.
- Added injectable MusicKit library, catalog, and system-player clients. Playlist rows resolve on demand as they become visible, preferring the uniquely named staged playlist before library and catalog matches; results stay cached for the app session. Resolved songs and the staged playlist show artwork, song rows show current playback, and Play, Play All, “Sounds like”, and Play Next drive `SystemMusicPlayer`. Music access remains optional, with reasons visible when access is unavailable.
- VinylFeverNotes (24 tests), Listening (55), Core (299), Mac app (94), and iOS Simulator (18) passed. Generic iOS Simulator and device builds passed; `check-handoff` passed. Jon's six-step M21 S2 device gate remains owed.

## 2026-10-30 — M21 · S1: The playlists and their reasons

- Branch: `m21/s1-playlists-view`.
- Replaced the mobile setup landing screen with a Playlists `NavigationSplitView`; moved the M20 setup form and its tests into a Setup sheet. Added Foundation-only shelf projections for staged playlist batches, song familiarity and reasons, counts, and the shared staged-date formatter. Added injected ledger-folder and date dependencies, partial-download and folder-access states, pull-to-refresh, and shelf model coverage.
- VinylFeverNotes (24 tests), Listening (55), Core (299), Mac app (94), and iOS Simulator (18) passed. Generic iOS Simulator and device builds passed; `check-handoff` passed. Jon's iPad and iPhone S1 gate remains to run with the M21 device checks.

## 2026-10-30 — M20 · S2: Why This Song

- Branch: `m20/s2-why-this-song`.
- Moved recommendation ledger records and codec into `VinylFeverNotes`, added Foundation-only answer selection and spoken text, and exposed the “Why This Song” App Intent and setup preview. The intent shares S1 song identification, reads coordinated recommendation files including iCloud placeholders with an eight-second deadline, and appends per-device evidence under `Probes/why-<device>.jsonl`. Music Feedback now rejects notes made only of repeated “cancel” words.
- VinylFeverNotes (23 tests), Core (299), Listening (55), Mac app (94), and iOS Simulator (14) passed; iOS Simulator and generic iOS device builds passed. `check-handoff` passes. Jon's seven-step post-install iPhone/iPad gate remains owed. The next dispatch awaits the architect's plan PR.

## 2026-10-29 — M20 · S1: Music Feedback intent

- Branch: `m20/s1-music-feedback-intent`.
- Added the `VinylFeverNotes` Foundation package, moved the shared taste-note codec into it, and extended v1 notes with optional `catalogID`. Added Music Feedback identification with the S0 staleness rule, a Siri/App Shortcut intent with a short pick list and dictated note, coordinated per-device note and probe writes, and setup-screen last-note and identification-test surfaces.
- Added package/MCP/mobile coverage and the package verification command. Package, Listening, Core (including `vf-mcp`), Mac app, iOS Simulator, and generic iOS device checks pass. Jon's six-step iPhone and iPad gate remains owed.

## 2026-10-29 — M20 · S0: The app target and the device probes

- Branch: `m20/s0-mobile-probe`.
- Added the iOS 27 `VinylFeverMobile` app (bundle ID `com.jonphillips.vinylfever`): a setup screen for folder access and MusicKit authorization, and the "Vinyl Fever Probe" App Intent. Each run appends one line to `Vinyl Fever/Probes/m20-s0-<device>.jsonl` through the folder bookmark, with file coordination. The line holds the player snapshot, the newest 5 recently played songs, any recently played error, and the previous failed write's time and error.
- `VinylFeverCore` is unchanged and stays macOS-only; the app doesn't link it. S1 adds a small cross-platform package for the note format.
- The iOS Simulator build and 4 mobile tests, Core, Listening, and macOS app tests passed. A signed device build passed. Jon's device runs on the iPad and iPhone remain owed, along with the gates listed in `NEXT_UP.md`. `NEXT_UP.md` stays on S0 until the architect records the probe results.
- Fix (`m20/s0-bookmark-scope`): the first iPad device run lost folder access on the second probe. The stale-bookmark refresh saved a copy outside the folder's access, which carries no access. The refresh now happens inside the access, and the setup screen opens access before saving the bookmark it picked. Device check: three probes in a row on the iPad, with no re-grant.

## 2026-10-29 — M18 · S8: The tools enforce the year and carry the questions

- Branch: `m18/s8-enforce-year-questions`.
- `stage_playlist` requires a `year` key on every track and rejects missing years before writing. `check_tracks` returns the same unresolved `openQuestions` projection as `list_playlists`.
- Core and Listening package tests, macOS app tests, and `check-handoff` passed. The opt-in Core performance suite exceeded timing thresholds in full-suite runs; its isolated Taste Intelligence suite passed.
- The laptop check used temporary copies of the live snapshot and note files. Jon had answered the soft-vocal pair on 2026-10-29; the copies contained no unresolved questions (4 questions, 4 answers), so `check_tracks` omitted `openQuestions`. S8's Jon gate carries the open-question interaction check forward.


## 2026-10-29 — M18 · Dispatch 7 S7 (`m18/s7-label-at-create`)

Playlists created from the inbox receive a pending `vinyl-fever` role immediately, keyed by name
until a unique name appears in a library snapshot. Snapshot adoption silently replaces the
temporary catalog ID with Music.app's ID. Playlist Roles shows pending entries as waiting for sync,
and a failed roles write leaves the created playlist intact with the fallback message.

Core (300 tests), Listening (55 tests), and macOS app (93 tests) passed; Core and Listening also
passed with `VF_PERF_TESTS=1`; `check-handoff` passed. Jon's S7 sync-and-adoption gate remains owed,
along with the listening-settings two-Mac check, M17 S2, M17 S3, M18 S2, and M18 S6 gates. Advanced
`NEXT_UP.md` to M18 · S8.

## 2026-10-29 — M18 · Dispatch 6 S6 (`m18/s6-open-questions`)

`list_playlists` now returns up to three unresolved taste questions from the existing notes, using
the `taste_notes` projection. It reads notes once and omits `openQuestions` when none remain or
the notes cannot be read. Updated the connector instructions to use those questions, show each
staged song's year and rationale, call out missing years or unverified references, and avoid
restaging a batch to fix a year.

Core (297 tests) and the `vf-mcp` build passed from a clean checkout. The read-only laptop check
against a copy of the live taste notes and snapshot returned no `openQuestions`. `check-handoff`
passed. Jon's S6 gate remains owed, as do the listening-settings two-Mac check, M17 S2, M17 S3,
M18 S2, and M18 S5 step 2 gates. Advanced `NEXT_UP.md` to M18 · S7.

## 2026-10-27 — M18 · Dispatch 4 S5 (`m18/s5-playlist-roles`)

The app now checks every loaded or refreshed library snapshot for unlabeled user, smart, and
subscription playlists. It shows a dismissible main-window banner, opens Playlist Roles filtered
to Unlabeled from Settings, and remembers dismissed playlist IDs per Mac. On the same check, it
labels playlists named by processed inbox requests or recommendation ledger batches as
`vinyl-fever`, without overwriting existing roles, and reports each automatic label once. Banner
names prioritize playlists not yet dismissed, then use snapshot order; "newest" isn't available
because the snapshot has no playlist creation dates.

Core (295 tests), Listening (55 tests), and the macOS app (90 tests) suites passed. `check-handoff` passed.
Jon's playlist-role gate remains owed, as do the two-Mac listening-settings check and M17 S2, M17
S3, M18 S2, and M18 S4 gates. Advanced `NEXT_UP.md` to M18 · S6.

## 2026-10-27 — M18 · Dispatch 3 S4 (`m18/s4-taste-questions`)

Added question and answer kinds to the existing taste-note format, UUID handles, cross-host
answer links, evidence context, and derived open-question state with expiry and a three-question
limit. `record_taste_note` validates known question IDs and records skipped answers; `taste_notes`
returns open questions before notes and attaches the newest answer to each answered question.
Question and answer lines stay out of song-note evidence. Legacy Music Feedback lines keep their
existing decoding and deduplication. Updated the MCP instructions and renamed the setup check to
Music Feedback.

Core (293 tests) passed and `vf-mcp` built. The read-only copy audit decoded 10 nonempty notes
from the two live note files, skipped the two intentionally blank shortcut records, and found no
open questions. The MCP smoke self-test passed; live smoke reached `library_overview` but
`recent_listening` could not open the local `2026-10.jsonl` listening log. Jon's post-install
question, answer, and skip gate remains owed. Advanced `NEXT_UP.md` to M18 · S5.

## 2026-10-26 — M18 · Dispatch 2 S2 (`m18/s2-recommendation-outcomes`)

Added shared outcome classification for New Music weeks and recommendation batches, release-age
bands, per-source baselines, the New Music blind-pick ledger, late Selections-add exclusions, and
request/reason/reference capture for staged discoveries. `recommendation_outcomes` reports each
batch with coverage and reasoning; `check_tracks` includes the latest recommendation outcome.
Reference checks use actual playlist membership, including unlabeled playlists. The five
architect fixes were preserved: reordered `RecommendationBatch` arguments, a single notes read in
staging, explicit closure intermediates, corrected playlist membership verification, and the
write-tool annotation for `record_new_music_picks`.

Review follow-up keeps New Music pick batches out of staged recommendation evidence and latest
outcomes, chooses the first covered picks per week (so an uncovered attempt can be retried), rejects
empty picks, and memoizes latest outcomes until ledger, snapshot, listening, or role inputs reload.
The classifier builds its play-window index once; `check_tracks` and `playlist_tracks` skip outcome
work when no recommendation evidence is present. Added MCP goldens, uncovered/familiar and retry
tests, missing-year and latest-why checks, and cache-refresh coverage for ledger and snapshot changes.

Core (289 tests; full `VF_PERF_TESTS=1` suite passed), Listening (55), and macOS app (82) suites
passed; `scripts/mcp-smoke` passed with 16 tools and `check-handoff` passed.
The read-only laptop check found the S1 batch "2024 Selections: 15 New Discoveries" with 15 songs,
all pending, all in the unknown release band, and no reasoning recorded. Jon's two-week New Music
pick gate and discovery staging check remain owed. Advanced `NEXT_UP.md` to M18 · S4.

## 2026-10-26 — M16 · Dispatch 5 S4 (`m16/s4-connector-build`)

The app bundle now carries the commit, dirty state, and build time. `library_overview` returns that
stamp, Settings → Chat Access shows it, and the install smoke check verifies the helper reports
the installed commit. After smoke, the installer names pre-swap helpers by their owning app and
reminds ChatGPT and Codex sessions to refresh their tools. Updated the install guide.

Core (277 tests), Listening (55), and macOS app (82) suites passed; `vf-mcp` builds; both script
self-checks, shellcheck, code-signature verification, and `check-handoff` passed. The built helper
reported the same commit as its bundle and read recent listening coverage. Jon's post-install
connector and refresh gate remains owed. Advanced `NEXT_UP.md` to M18 · S2.

## 2026-10-25 — M19 · S1 daily backup set (`m19/s1-daily-backup`)

Added one daily backup set from both live app launch and listening-poller runs. The local set contains an online SQLite copy, coordinated iCloud files, processed inbox files, and a SHA-256 manifest; unchanged files use hard links. Shrink, missing, and unreadable logs are recorded, with unreadable files falling back to the prior copy. Local and iCloud retention, Settings status, setup warnings, and restore instructions are included.

Core (272 tests), Listening (55 tests), and macOS app (80 tests) suites passed; `shellcheck scripts/setup-mac` passed. The isolated setup check showed the expected Time Machine and daily-set warnings. Jon’s laptop backup gate remains owed. Advanced `NEXT_UP.md` to M18 · S2.

History, newest first. The PR that completes a dispatch adds an entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-10-25 — M18 · Dispatch 1 S1 (`m18/s1-recommendation-ledger`)

Added the coordinated per-host recommendation JSONL ledger, pure familiarity evidence, and
`recommended` evidence in `check_tracks` and `playlist_tracks`. `stage_playlist` now logs
surviving songs and reports ledger write failures without failing staging. Updated chat
instructions. Listening (55), Core (259), and macOS app (78) tests pass. The read-only laptop
check against the 2026-10-23 snapshot and the archived 15-song batch found all 15 unfamiliar;
five artists already had library tracks, and none had a listening start before staging. Jon's
stage/check gate remains owed.

## 2026-10-25 — M17 · Dispatch 3 S3 (`m17/s3-taste-notes`)

Added the Core reader for shortcut and chat taste notes, conflict-copy deduplication, coverage,
time-only listening candidates, and the `taste_notes` / `record_taste_note` MCP tools. Song
checks and playlist tracks now include note evidence. `setup-mac` creates the empty VF Note file
and links the shortcut recipe. The shared live-client guard now has a direct test used by both
the app and poller. Core (254), Listening (55), and macOS app (78) tests pass; the mutation check
fails when the guard returns true; the Listening Poller build and shellcheck pass. An isolated
setup-mac apply twice left the notes file unchanged on the second run. Jon's CarPlay and chat gate
remains owed.

## 2026-10-24 — M17 · Dispatch 2 S2 (`m17/s2-exposure-curation`)

Fixed Apple Music playlist paging and catalog requests, cached-ID recovery, and a persisted
six-hour local attempt throttle. Exposure reading now skips and counts malformed or newer lines,
deduplicates weeks across host files, and never blocks a listening poll. Snapshot curation writes
only non-empty changes, uses the injected date and listening host, and cannot prevent snapshot
refresh. `kept_and_passed` now precomputes play keys; baselines exclude pending weeks and share
artist identity normalization. Listening (54), Core (251), and macOS app (77) tests pass; Listening
and Core pass with `VF_PERF_TESTS=1`; the universal macOS 15 poller build passes. A scratch-only
live probe fetched the 2026-10-23 New Music week (25 tracks); `kept_and_passed` returned all 25 as
pending. The JSONL line and full tool response are in PR #126. No live taste exposure file or
lease was changed. Jon's mini-save gate remains owed until two weeks are saved there.

## 2026-10-23 — M17 · Dispatch 1 S1 (`m17/s1-playlists-snapshot`)

Snapshot v2 carries every user and subscription playlist with ordered members, outside-library
track text, and `disliked`. `playlist-roles.json` in iCloud Drive's Taste Intelligence folder holds
Jon's roles: the Settings → Taste editor writes it, with suggestions and the 2018 rule. `vf-mcp`
adds `list_playlists` and `playlist_tracks`, and `check_tracks` gains evidence by role, `heard`
days, and `unlabeledPlaylistCount`. Core (245) and Listening (44) pass with and without
`VF_PERF_TESTS=1`, and the macOS app's 73 tests pass. The read-only read of Jon's library took
15.2 s: 148 playlists and 8,220 outside-library tracks. Jon's gate (labeling roles, then the
15-song ask in ChatGPT) passed 2026-10-24. The architect added this bookkeeping at Jon's direction.

## 2026-10-22 — Effort: Listening settings refresh, and full poll errors (`effort/listening-settings-refresh`)

Both Settings windows refresh listening state when activated, and Vinyl Fever's Re-probe refreshes
the lease too. Poll failures now retain the Foundation domain, code, file path, and underlying
errors in saved error text and public logs. Listening (44) and Core (233) tests pass with and
without `VF_PERF_TESTS=1`; macOS app tests (71) and the `VF Listening Poller` build pass. Jon's
two-Mac device check remains owed in #123.

## 2026-10-22 — M13 · Dispatch 6 S5 (`m13/s5-handover-chain`)

Resolved the newest known listening list through up to four handover links, added strict
same-poller overlap collapse, and added **Poll now** to both Settings surfaces. Listening (41),
Core (233), and macOS app (70) tests pass; both performance suites and the macOS 15 poller build
pass. Read-only replay of Jon's streams counted the 33 Discover Station plays once with 4 synthetic
songs at the 7:27 pm cut, and once with 2 synthetic songs against the current streams. The S5
laptop ↔ mini handover and Poll now device gate remains owed to Jon.

## 2026-10-22 — M13 · Dispatch 5 S4 (`m13/s4-handover-recovery`)

Recover recent plays across poller handovers from the previous holder's stream, record handover
windows as v2, and show a coverage gap when the old stream cannot be recovered. Both takeover
surfaces now ask launchd to start the agent after registration, avoiding concurrent in-process
polls. Listening (35), Core (233), and macOS app (68) tests pass; both performance suites and the
macOS 15 poller build pass. A read-only replay of the saved 2026-10-22 streams resolves 19 plays
mini → laptop, then 0 laptop → mini. Jon's S4 device gate remains owed.

## 2026-10-22 — M16 · Dispatch 4 S3 (`m16/s3-hardening`)

Hardened install process detection and rollback/reopen behavior, moved fresh-Mac setup checks
after prerequisite installation, and made stale-build relaunch await the installed app launch.
Added focused stale-build bundle-date tests and kept timing checks opt-in. ShellCheck, Core and
Listening suites (normal and perf), macOS app tests, the full install/MCP smoke run, and
`build-listening-poller` passed. The generated-project checks passed with XcodeGen available;
the stripped-PATH run reached its final report and correctly reported missing prerequisites.
The stale-copy alert interactions (including with the installed copy already running) remain owed
to Jon on the laptop; LaunchServices would not open the temporary copied bundle (`-10827`). The
temporary test copy and process were removed. Existing M13 S2, M13 S3, and M16 S2 device gates also
remain owed. `NEXT_UP.md` has no queued dispatch. Jon passed the stale-copy alert check on the laptop
on 2026-10-22, on the merged #117 build, in all three cases.

## 2026-10-21 — M16 · Dispatch 3 S2 (`m16/s2-setup-mac`)

Added the role-based `scripts/setup-mac` checker and idempotent repairs, centralized machine
constants, and extracted the `~/music-chat` files. ShellCheck passed. On the laptop, Build and Chat
reports had no failures; removing `xcodegen` and unloading the tunnel agent were detected and
repaired. Repeating Build and Chat `--apply` with the installed app and setup intact made no
changes. The music-chat scratch-home check preserved customized files and added only the missing
`CLAUDE.md`. Jon's Intel mini Poll-role gate remains owed after merge; its exact steps are in M16
S2. `NEXT_UP.md` has no queued dispatch. Jon passed the Intel mini Poll-role gate on 2026-10-22.
FileVault is on there, which blocks automatic login, so the mini needs a manual login after a restart.

## 2026-10-21 — M16 · Dispatch 2 S1 (`m16/s1-install-vinyl-fever`)

Added `scripts/install-vinyl-fever` to generate, build, verify signing and this Mac's
provisioning profile, install with rollback protection, restart the tunnel agent, and run the
MCP smoke probe. Added `scripts/mcp-smoke` for `initialize`, `tools/list`, `library_overview`, and
`recent_listening`. ShellCheck and the dry run passed, and the initial laptop install and forced
profile failure passed. Architect review found issues in app-process detection, fresh-Mac
listening coverage, rollback tunnel restart, and platform checkout lookup; all were fixed. The
self-test passed. The rerun passed with the app open, the forced profile failure stopped before
installation, and the forced smoke failure restored the prior app and restarted the tunnel.
`lsof` confirmed the running helper used the restored bundle's inode. `NEXT_UP.md` points to M16 S2.

## 2026-10-21 — M16 · Dispatch 1 S0 (`m16/s0-safe-database-home`)

Moved the live database to `~/Library/Application Support/VinylFever/VinylFever.sqlite`, safely
adopted and preserved a verified Vinyl Fever database from SQLiteData's shared default path, and
replaced Debug schema erasure with typed refusal of newer data plus pre-migration backups. Added
the database path to Settings and updated the replacement-Mac guide. Listening and Core suites and
the macOS app tests pass. Plan #107 approved the database migration policy. After two fix rounds
(the adoption's staging WAL and a duplicate-copy guard, then limiting that guard to live launches),
it merged as #108. Jon passed the laptop device gate on 2026-10-21: the running pre-S0 copy was
refused, then adoption carried all 83 aliases, the recipe, the policy, and 75 run records, and a
pre-S0 build started on an empty `SQLiteData.db` without touching the new file.

## 2026-10-21 — M13 · Dispatch 4 S3 (`m13/s3-in-app-poller`)

Added Vinyl Fever's headless listening poller and hourly agent, with confirmed takeover in both
settings surfaces. A takeover clears the new holder's saved diff baseline so its first fetch is
`baseline`. Listening, Core, and macOS app tests pass; the poller app builds; `check-handoff`
passes. The M13 S1 Intel mini, S2 iPad, and S3 laptop↔mini device gates remain owed. Jon passed
the laptop↔mini gate on 2026-10-22: both handovers were clean, but the mini → laptop baseline
silently absorbed 19 plays from its 40-minute hole (see M13 S3 and `open-questions.md`).

## 2026-10-20 — M15 · Dispatch 2 S1 (`m15/s1-artist-aliases`)

Added a pure alias candidate finder, local `artistAliases` decisions in SQLiteData, the Settings
review sheet, atomic `artist-aliases.json` export, and alias-aware app and `vf-mcp` indexes.
Alias chains collapse to one canonical key and decisions can be undone. Listening, Core, and
macOS app tests pass; `check-handoff` passes. The schema change is escalated to Jon. After one
fix round (the finder's rules and a two-column primary key; Jon approved the schema), it merged
as #101. Jon passed the Settings/device gate on 2026-10-21, so M15 is complete.

## 2026-10-20 — M14 · Dispatch 2 S1 (`m14/s1-vf-mcp-uploaded-albums`)

`check_tracks` now returns `uploadedAlbums`: up to 5 named albums of Jon's uploads, most played
first, matched with `ArtistIdentity`. The shared upload-candidate clamp is lifted, and the picker
keeps 3. The `vf-mcp` instruction head, `PlaylistContract.trackRules`, `PLAYLIST-CONTRACT.md`,
and the `~/music-chat` template tell the model to use an upload's exact album as the hint. Core
and macOS app tests pass. Jon passed the iPad device gate the same day, so M14 is complete.
(#97 merged without this entry; the M15 S1 plan PR added it.)

## 2026-10-20 — M15 · Dispatch 1 S0 (`m15/s0-artist-identity`)

Added `ArtistIdentity` to `VinylFeverListening` and adopted it across library ownership and
grouping, upload routing, catalog scoring, and listening history. `vf-mcp` now builds its log
with the library identity when a snapshot is available. Listening and Core tests and the macOS
app tests pass; `check-handoff` passes. On an 87,000-track, 8,000-artist fixture with one third
suffix variants, the index build measured 3.46 s before and 3.64 s with `ArtistIdentity`.
Advanced `NEXT_UP.md` to M14 S1.

## 2026-10-20 — M13 · Dispatch 3 S2 (`m13/s2-listening-tools`)

Added the `recent_listening` MCP tool, period-based `top_artists` and `top_tracks` from the
listening log, coverage in log-backed results, coordinated lazy reads with modification-time
cache invalidation, and a Listening History status section in Settings. Updated MCP setup guidance
and the `~/music-chat` template. Core and macOS app tests pass; `check-handoff` passes. The ChatGPT
iPad device gate remains owed, as does M13 S1's Intel mini gate.

## 2026-10-20 — M14 · Dispatch 1 S0 (`m14/s0-library-route`)

Added the Apple Music library album and song search routes, exact upload matching with the
catalog resolver's retry/backoff, and mixed catalog/upload playlist create and append payloads.
Snapshot routing offers uploaded copies when catalog matching fails, and preview rows identify
uploads by album. Core, Listening, and macOS app tests pass; `check-handoff` passes. Live Apple
Music API calls and the iPhone playback gate remain unverified/owed.

## 2026-10-18 — M13 · Dispatch 2 S1 (`m13/s1-listening-poller`)

Added the `ListeningPoller` model and coordinated listening store, plus the universal VF Listening
Poller app with authorization, hourly `SMAppService` agent setup, and status window. Added the
poller setup guide and tests for baseline, subsequent fetches, lease skipping, authorization and
fetch failures, and UTC month naming. Core tests and the macOS app tests pass. The build script
verified arm64 and x86_64 slices and the app signature. The live MusicKit call and agent
registration remain unverified; Jon's Intel mini device gate is owed. The gate closed on
2026-10-21 from the log: 26 hourly fetches with no gaps after the baseline (171 items, 6 pages),
every later fetch reading 1 page. The plays half had passed on 2026-10-20.

## 2026-10-18 — M13 · Dispatch 1 S0 (`m13/s0-listening-engine`)

Added the pure `VinylFeverListening` package target with the versioned JSONL codec, paged
recently-played diff, log merge and period queries, coverage reporting, and lease rules. Core
tests and the macOS app test suite pass. The live MusicKit request remains unverified; S1 stays
gated on Jon's developer-portal profile and mini prerequisites.

## 2026-10-18 — M12 close-out (`m12/close-out`, architect)

Jon passed the S2 device gate (ChatGPT on the iPad through the `vinyl-fever` tunnel, Claude Code
in `~/music-chat`, an 8.9 s first call), and M12 is closed. The architect folded in the gate's
fixes: the inbox's icon-only Discard is now a labelled **Dismiss** (it files the item under
`Processed/`, never deletes it), `stage_playlist`'s `description` carries schema guidance so
process notes stay out of Apple Music, the index-arrival observation test now tests arrival, and
the app shell skips its launch snapshot refresh in the test host. Decision 1 is no: Last.fm (S3)
is dropped.

## 2026-10-17 — M12 · Dispatch 3 S2 (`m12/s2-vf-mcp`)

Added the `vf-mcp` executable on jon-platform's `MCPServerKit`, the library read tools and
playlist staging tool, and the app's reviewable playlist inbox. Settings now shows the helper and
snapshot paths and copyable Claude Code, Codex, and tunnel setup. Core and macOS app tests pass.
The ChatGPT iPad-through-tunnel and Claude Code device checks remain owed.

## 2026-10-17 — M12 · Dispatch 2 effort mcp-server-kit (jon-platform `effort/mcp-server-kit`)

jon-platform#74 merged (squash `b6f48d6`): `MCPServerKit` (the stdio JSON-RPC loop and tool registry, plus the `mcp-hello` sample), `LLMHandoffKit.HandoffInbox`, and `scripts/mcp-tunnel`. The architect's review fixed three gate blockers in the script (the real `tunnel-client` flag is `--health-listen-addr`, `init --force` replaces an existing profile, and the LaunchAgent gets a PATH that finds `tunnel-client`), plus line splitting on LF only, a non-trapping instructions check, and ISO 8601 dates in `.json(_:)`. Jon passed the `mcp-hello` iPad gate the same day.

## 2026-10-16 — M12 · Dispatch 1 (S0 + S1)

Branch: `m12/s0-library-snapshot`

Added the versioned library snapshot codec and pure index, wired Music.app bulk reads and atomic snapshot storage, and added library annotations and heavily played removal to playlist review. Core and macOS test suites passed. The live ScriptingBridge read and the Mac device checks remain unverified.

#72 merged 2026-10-17 (squash `6b96ae5`) with the architect's gate fixes: manual refresh requests Automation permission; bulk reads use raw Apple Events, because ScriptingBridge drops `missing value` items; dates use a `Date.ISO8601FormatStyle` codec. Jon passed the device gate the same day.

## 2026-10-15 — M11 catalog search retry (`fix/catalog-search-retry`)

Jon's first device run of M11 surfaced two failures. "Failed to request developer token" came from
the wildcard signing profile and is fixed in #69. HTTP 429 "API capacity exceeded" came during a
30-track resolve. Catalog searches now retry rate-limited and 5xx responses (3 attempts, 1 s then
2 s plus jitter, on the injected clock), search concurrency drops from 4 to 2, and the unreadable
429 body maps to a readable "try again" error. The Playlists area gains **Retry Failed Searches**.
Create and append never retry. The device gate is still owed.

## 2026-10-15 — M11 · Dispatch 2 playlist creation (`m11/s1-apple-music-playlists`)

Added the MusicKit catalog resolver and playlist create/append flow, the Playlists area, and
ChatGPT Project setup instructions. The S1 and S2 device gate remains owed on Jon's Mac. Core
tests pass and the app test bundle compiles. The architect's macOS 27 review run identified
model-test and duplicate-handling fixes, addressed in PR #67; a separate pre-existing
`CollectionInboxAppendTests` failure remains outside this dispatch. `check-handoff` passes.

## 2026-10-14 — M11 · S0 playlist contract and scorer (`m11/s0-playlist-contract`)

Added the `VF-PLAYLIST: v1` instructions and strict decoder, including marker warnings, formatting
recovery, and visible reporting for dropped tracks. Added the catalog match scorer with title-aware
feature cleanup, same-song album matching, version penalties, and hint/date tie-breaks; pinned the
Project instructions byte-for-byte in a test. Advanced `NEXT_UP.md` to M11 · Dispatch 2 (S1 + S2).
Core tests and the app build pass; the app test target
requires macOS 27 and could not run on this Mac's macOS 26.6.2. `check-handoff` passes.

## 2026-10-14 — One true import folder (`effort/one-true-import-folder`)

Passthrough MP3/M4A tracks are copied from `Working/` into `Output/`, and all import and verification
paths now use `Output/`. Reconciled M6 · S2 tracking: its Plan action bar and terminal Output
disclosure landed in #35; track-row condensation landed in #50. The next dispatch is M11 · Dispatch 1
(S0), set by #63.

History before 2026-09-29 lives in the milestone ledgers (`docs/milestones/`) and merged PRs:
M5 setlist normalizer (#30/#31), M7 collection recipes (#40–#44), M8 policy binding (#46/#48),
M9 manual append metadata (#51–#53), M10 collection inbox (#55/#56 and follow-ups #58–#60).

## 2026-09-29 — Adopt the ADR-0005 document shape (`chore/token-discipline`)

Retired `CURRENT_HANDOFF.md` (last touched 2026-07-10; its M10 front had since shipped). Split it into
`docs/NEXT_UP.md` (M6 · S2 remainder), `docs/efforts/archive/one-true-import-folder.md`, and the
parked/pending items in `docs/open-questions.md`; added `docs/verification.md`.
