# Next Up — M13 · Dispatch 2: S1 VF Listening Poller

**Slices:** M13 · S1 (branch `m13/s1-listening-poller`)
**Briefs:** docs/milestones/M13-listening-history.md § S1, plus *Listening log (format v1)*
**Done when:** S1's DoD, except its device gate; core and app tests green; `scripts/build-listening-poller` output in the PR; PR opened in `jonphillips/vinyl-fever`.
**Owed:** S1's device gate on the Intel mini (Jon, about 24 h, after the PR is green and his *Before the S1 gate* prerequisites are done).
**Notes:** `pollOnce()` goes in `VinylFeverListening`, not the app, so S3 reuses it; the app target is a thin window plus the `--poll` entry point. The target is macOS 26.0. Only a `generic/platform=macOS` build is universal, so the slices come from the build script, not from Xcode's Run. It signs with the **VF Listening Poller Dev Profile**, which is installed on this Mac; if Xcode can't find it, stop and say so in the PR. A `failed` line never replaces `last-list.json`. This Mac has no Rosetta, so the x86_64 slice is checked with `lipo`, not run. Leave the live MusicKit call and `SMAppService` registration unverified.
