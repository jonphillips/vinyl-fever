# Next Up — M6 · S2 remainder: live-show import content polish

**Slices:** M6 · S2 (remainder only; #50 already landed the `TrackPlanRow` / `LibraryTrackResolutionRow` condensing)
**Briefs:** `docs/milestones/M6-live-show-import-ui-refactor.md` § Slices, S2
**Done when:** `PlanActionBar` is extracted from `PlanReadinessSummary`; the run-status views live in
the **Output** tab (S1 left it a placeholder), which collapses once the run is terminal; the Source
picker sits in the header. UX only, with no pipeline logic change. Verification per `docs/verification.md`.
The completing PR ticks S2 in the M6 ledger.
**Owed:** none
**Notes:** Ungated, no device check. M6 is then complete. Next in plan order: M11 · Dispatch 1
(S0, `docs/milestones/M11-song-list-playlist.md`), then the one-true-import-folder effort.
