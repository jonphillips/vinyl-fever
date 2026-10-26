# Next Up — M19 · S1: The daily backup set

**Slices:** M19 · S1 (branch `m19/s1-daily-backup`)
**Briefs:** docs/milestones/M19-backups.md §S1, plus its *Shared rules*
**Done when:** S1's DoD; Core and macOS app tests pass, run from a clean checkout of the pushed head; `shellcheck scripts/setup-mac` passes; PR opened in `jonphillips/vinyl-fever`. The completing PR advances this file to M16 · S4.
**Owed:** M13 S2's iPad device gate; the listening-settings two-Mac check; M17 S2's gate (two mini-saved weeks, then Jon checks a finished week); M17 S3's gate (a Music Feedback note in the car, read back word for word, then a playlist note); M18 S1's stage/check gate.
**Notes:** Never touch the live database, `Backups/`, the iCloud `Vinyl Fever/` folder, or the inboxes from tests or dev runs: inject temp roots. A backup starts only in the `.live` context, never in the app-test host. Open the live database read-only for the copy. S1 doesn't touch `vf-mcp`. Post PR comments as `jon-codex-bot`.
