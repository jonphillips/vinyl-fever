# Effort — one true import folder

*Ungated, standalone, no milestone. Moved from `CURRENT_HANDOFF.md` on 2026-09-29.*

**Problem.** Passthrough mp3/m4a still land `verifyWorkingOnly` in `Working/`, while transcoded FLAC
goes to `Output/`, so a finished set is split across two folders
([ConversionPlan.swift](../../VinylFeverCore/Sources/VinylFeverCore/Model/ConversionPlan.swift),
[ConversionExecutor.swift](../../VinylFeverCore/Sources/VinylFeverCore/Apply/ConversionExecutor.swift)).

**Done when:** every import-ready track lands in **one** folder. Passthrough mp3/m4a get a plain copy
(no re-encode) into `Output/`, every track's `verificationFile` points there, and `Working/` becomes
pure scratch. Deterministic and fixture-testable; no device check.
