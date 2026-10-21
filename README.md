# Vinyl Fever

Mac-first personal operations console for managing live-show imports, collection
definitions, and metadata repair before and after Apple Music import. It also gives chat
(ChatGPT, Claude Code, Codex) read access to the music library and listening history, and
stages playlists from chat for review.

**Status: in daily use.** Active work is in [docs/NEXT_UP.md](docs/NEXT_UP.md), and finished
work is in [docs/DONE-LOG.md](docs/DONE-LOG.md).

## Set up a Mac

[docs/setup/README.md](docs/setup/README.md) covers a new Mac in any role: the Build Mac, the
chat host (ChatGPT through the Secure MCP Tunnel), and the Mac that polls listening history.

## What's here

| Path | What it is |
| --- | --- |
| `VinylFever/` | The macOS app (SwiftUI): Live Shows, Collections, Policies, Normalizer, Playlists, Settings |
| `VinylFeverCore/` | Core package: models, clients, SQLiteData schema, and the `vf-mcp` stdio helper bundled into the app |
| `VinylFeverListening/` | Listening-history engine shared by the app, `vf-mcp`, and the poller |
| `VinylFeverListeningPoller/` | VF Listening Poller, the hourly poller for the Intel Mac mini (macOS 15) |
| `docs/` | Product and architecture brief, milestones, setup and ops guides. Start with [docs/README.md](docs/README.md) |
| `scripts/` | `build-listening-poller`, plus the legacy Python and shell tools. See [scripts/README.md](scripts/README.md) |

`project.yml` is the source of truth for the Xcode project. Run `xcodegen generate` after
changing it. Tests are in [docs/verification.md](docs/verification.md).

## Guides

- [Setting up a Mac](docs/setup/README.md)
- [Chat access (MCP)](docs/chatgpt/MCP-SETUP.md) and the [playlist contract](docs/chatgpt/PLAYLIST-CONTRACT.md)
- [Listening poller setup](docs/listening/POLLER-SETUP.md)

## House stack

Built to Jon's house conventions in [jon-platform](../jon-platform/AGENTS.md): SwiftUI,
Point-Free libraries without TCA, SQLiteData for app state, `@Observable` feature models, and
dependency-backed clients. No SwiftData, no server, no auth. Agents start at [AGENTS.md](AGENTS.md).
