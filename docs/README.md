# Vinyl Fever Docs

This folder is the refined product and architecture brief for Vinyl Fever.
It supersedes the older single-file handoff as the working source of truth.

Read in this order:

1. [Product Requirements](product-requirements.md)
2. [Technical Architecture](technical-architecture.md)
3. [Implementation Plan](implementation-plan.md)
4. [Open Questions](open-questions.md)

Finished design specs, reviews, and one-off docs are in [archive/](archive/) (ADR-0005 D13). The
setlist and collection-recipe specs moved there because the code now owns them: the prompts are
compiled into `VinylFeverCore` (`Normalizing/`, `Recipes/`).

Setup and operations:

- [Device passes](device-passes.md): Jon's owed device gates and held setup steps
- [Setting up a Mac](setup/README.md)
- [Feedback guide: New Music, Vinyl Fever playlists, and Music Feedback](feedback-guide.md)

Related source material:

- [Milestones](milestones/): live build orders only; shipped ones are in
  [milestones/archive/](milestones/archive/) (ADR-0005 D10)
- [Efforts](efforts/README.md): live briefs only; finished ones are in [efforts/archive/](efforts/archive/)
- [Listening](listening/README.md)
- [ChatGPT playlist contract (`VF-PLAYLIST: v1`)](chatgpt/PLAYLIST-CONTRACT.md)
- [Taste Intelligence (design; built in M17, outcomes in M18)](taste-intelligence.md)
- [Music Feedback in the iPhone and iPad app (M20)](milestones/M20-music-feedback-intent.md)
- [The Vinyl Fever playlists in the iPhone and iPad app (M21)](milestones/archive/M21-playlists-view.md)
- [Where each playlist stands: heard, kept, and archived (M22)](milestones/M22-playlist-progress.md)
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
