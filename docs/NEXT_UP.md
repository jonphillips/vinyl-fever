# Next Up — M14 · Dispatch 1: S0 library route

**Slices:** M14 · S0 (branch `m14/s0-library-route`)
**Briefs:** docs/milestones/M14-live-tracks-in-playlists.md § S0, plus *The resolve flow*
**Done when:** S0's DoD, except its device gate; listening, core, and app tests green; PR opened in `jonphillips/vinyl-fever`.
**Owed:** M13 S1's Intel mini gate (Jon, in progress); M14 S0's device gate (Jon: a mixed `VF-PLAYLIST` with three uploads previews with upload badges and plays on the iPhone in order).
**Notes:** M14 S0 runs before M13 S2 (M14 Decision 3, amended 2026-10-20). It must not touch `vf-mcp` or `LibraryMCPServer`; M13 S2 edits them next. The new library endpoints share the resolver's 429/5xx retry and backoff. `SongTextNormalizer` forwards to `VinylFeverListening`'s normalizer, so call it rather than copying its rules. Leave the live library API calls unverified.
