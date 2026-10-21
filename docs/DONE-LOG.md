# Done log

History, newest first. The PR that completes a dispatch adds an entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

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
passes. The M13 S1 Intel mini, S2 iPad, and S3 laptop↔mini device gates remain owed.

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
`docs/NEXT_UP.md` (M6 · S2 remainder), `docs/efforts/one-true-import-folder.md`, and the
parked/pending items in `docs/open-questions.md`; added `docs/verification.md`.
