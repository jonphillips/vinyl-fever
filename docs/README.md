# Vinyl Fever Docs

This folder is the refined product and architecture brief for Vinyl Fever.
It supersedes the older single-file handoff as the working source of truth.

Read in this order:

1. [Product Requirements](product-requirements.md)
2. [App Areas](archive/app-areas.md)
3. [Metadata Policy Model](archive/metadata-policy-model.md)
4. [Setlist Formatting Rules](archive/setlist-formatting-rules.md)
5. [Technical Architecture](technical-architecture.md)
6. [Implementation Plan](implementation-plan.md)
7. [Open Questions](open-questions.md)

Setup and operations:

- [Setting up a Mac](setup/README.md)
- [Feedback guide: New Music, Vinyl Fever playlists, and Music Feedback](feedback-guide.md)

Related source material:

- [Milestones](milestones/): live build orders only; shipped ones are in
  [milestones/archive/](milestones/archive/) (ADR-0005 D10)
- [Efforts](efforts/README.md): live briefs only; finished ones are in [efforts/archive/](efforts/archive/)
- [Listening](listening/README.md)
- [Collection Recipes (design; built in M7–M8)](archive/collection-recipes.md)
- [ChatGPT playlist contract (`VF-PLAYLIST: v1`)](chatgpt/PLAYLIST-CONTRACT.md)
- [Taste Intelligence (design; built in M17, outcomes in M18)](taste-intelligence.md)
- [Backups (M19)](milestones/archive/M19-backups.md)
- [Music Feedback in the iPhone and iPad app (M20)](milestones/M20-music-feedback-intent.md)
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
