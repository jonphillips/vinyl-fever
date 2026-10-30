# Effort — one true import folder

**Status:** Done → done-log
**Summary:** Put every import-ready track in `Output/`, including passthrough MP3 and M4A files.
**Related:** [Efforts index](../README.md); [M6 live-show import UI refactor](../../milestones/archive/M6-live-show-import-ui-refactor.md)

Ungated, standalone, no milestone. Dispatched 2026-10-14.

**Problem.** Passthrough mp3/m4a stay in `Working/`, while transcoded FLAC goes to `Output/`, so a
finished set is split across two folders
([ConversionPlan.swift](../../../VinylFeverCore/Sources/VinylFeverCore/Model/ConversionPlan.swift),
[ConversionExecutor.swift](../../../VinylFeverCore/Sources/VinylFeverCore/Apply/ConversionExecutor.swift)).

**Done when:** every import-ready track lands in **one** folder. Passthrough mp3/m4a get a plain copy
(no re-encode) into `Output/`, every track's `verificationFile` points there, and `Working/` becomes
pure scratch. Deterministic and fixture-testable; no device check.
