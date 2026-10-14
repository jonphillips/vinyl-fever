# Next Up — M11 · Dispatch 1 (S0): playlist contract, decoder, and match scorer

**Slices:** M11 · S0
**Briefs:** `docs/milestones/M11-song-list-playlist.md` § The contract (v1), § The spine, § Slices S0, § Constants register
**Done when:** per the S0 brief. `PlaylistContract` (marker, instructions, strict decode) and
`CatalogMatchScorer` live in `VinylFeverCore` with the listed decoder and scorer tests;
`docs/chatgpt/PLAYLIST-CONTRACT.md` is checked in and pinned byte-equal by a test. Verification per
`docs/verification.md`. The completing PR ticks S0 in the M11 ledger.
**Owed:** none
**Notes:** Core only: no MusicKit, no UI, no schema. Adds `jon-platform/packages/LLMHandoffKit` as a
path dependency of `VinylFeverCore` (sibling checkout, like `LLMClientKit`). Dispatch 2 (S1 + S2)
waits on Jon's MusicKit App ID step and the three open decisions; the completing PR sets
`Nothing dispatched.`
