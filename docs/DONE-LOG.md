# Done log

History, newest first. The PR that completes a dispatch adds an entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

# 2026-10-15 — M11 · Dispatch 2 playlist creation (`m11/s1-apple-music-playlists`)

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
