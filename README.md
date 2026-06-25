# Vinyl Fever

Mac-first personal operations console for managing live-show imports, collection
definitions, and metadata repair before and after Apple Music import.

**Status: planning.** No app code yet — this repo currently holds the product and
architecture brief plus the legacy scripts that serve as workflow evidence.

## Layout

- `docs/` — the product and architecture brief. Start with
  [docs/README.md](docs/README.md).
- `docs/reference/` — source material (Apple Music library strategy, the original
  handoff brief).
- `scripts/` — legacy Python and shell tools. Evidence to reassess and mostly
  reimplement in Swift, not the product interface. See
  [scripts/README.md](scripts/README.md).

## House stack

Built to Jon's house conventions in `/Users/jon/code/jon-platform/AGENTS.md`:
SwiftUI, Point-Free libraries without TCA, SQLiteData for app state, `@Observable`
feature models, dependency-backed clients. No SwiftData, no server, no auth.
