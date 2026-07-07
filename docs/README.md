# Vinyl Fever Docs

This folder is the refined product and architecture brief for Vinyl Fever.
It supersedes the older single-file handoff as the working source of truth.

Read in this order:

1. [Product Requirements](product-requirements.md)
2. [App Areas](app-areas.md)
3. [Metadata Policy Model](metadata-policy-model.md)
4. [Setlist Formatting Rules](setlist-formatting-rules.md)
5. [Technical Architecture](technical-architecture.md)
6. [Implementation Plan](implementation-plan.md)
7. [Open Questions](open-questions.md)

Related source material:

- [reference/MusicWorkbench_Codex_Handoff.md](reference/MusicWorkbench_Codex_Handoff.md)
- [reference/apple_music_library_strategy.md](reference/apple_music_library_strategy.md)
- [reference/duplicate-detection-strategy.md](reference/duplicate-detection-strategy.md)
- [../scripts/shell/music_pipeline.sh](../scripts/shell/music_pipeline.sh)
- `/Users/jon/code/jon-platform/AGENTS.md`

Core product sentence:

Vinyl Fever is a Mac-first personal operations console for managing live-show
imports, collection definitions, and metadata repair before and after Apple Music
import.

Core architecture sentence:

SwiftUI is the cockpit, SQLiteData is the app state store, existing scripts are
evidence to reassess before UI is certified, and every file operation must be
previewable, logged, and biased toward preserving originals.
