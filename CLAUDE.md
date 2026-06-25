# Vinyl Fever Agent Entry Point

Before proposing architecture or implementation, read:

1. `/Users/jon/code/jon-platform/AGENTS.md`
2. `docs/README.md`
3. The linked Vinyl Fever docs in the order listed there

Vinyl Fever is Mac-first. The raw-file and script-running workflows are macOS
execution flows. SwiftUI and shared Swift package boundaries should preserve the
option for a future iPad companion, but iPad is not a v1 execution surface.

Do not use SwiftData. Follow Jon's house stack from `jon-platform`: plain value
records, SQLiteData for app state, `@Observable` feature models, dependency-backed
clients, and no TCA.
