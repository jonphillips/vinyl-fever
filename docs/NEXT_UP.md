# Next Up — M13 · Dispatch 1: S0 listening engine

**Slices:** M13 · S0 (branch `m13/s0-listening-engine`)
**Briefs:** docs/milestones/M13-listening-history.md § S0, plus *Listening log (format v1)* and *The diff*
**Done when:** S0's DoD; core tests green; PR opened in `jonphillips/vinyl-fever`.
**Owed:** nothing.
**Notes:** Pure Core: a new `VinylFeverListening` library target in the `VinylFeverCore` package, at the package's existing macOS 26 floor (M13 Decision 2), with no SQLiteData or MCP kit dependency. Write `RecentlyPlayedClient`'s live MusicKit value but leave it unverified; tests use canned pages. Don't start S1: it needs Jon's developer-portal profile first.
