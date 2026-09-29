# AGENTS.md — Vinyl Fever

Entry point for any coding agent (Claude Code, Codex, …) working in this repo.
This is the **app-specific** layer; the general house layer lives in
`/Users/jon/code/jon-platform/AGENTS.md`.

## Working mode — what a bare "go" means (read first)

Two agents under the architect/executor protocol: Claude = architect, Codex = executor. The
bare-"go" routing is in jon-platform `AGENTS.md` (which you read first anyway) and the full
protocol in `/Users/jon/code/jon-platform/docs/agent-collaboration.md` — read it before acting if
you haven't this session. Jon is never the courier: orient from `gh`, not pasted status.

**Start here:** [`docs/NEXT_UP.md`](docs/NEXT_UP.md) is the one dispatch: the executor's only
planning input (empty → stop and ask). The architect also reads `docs/open-questions.md`
(candidates and parked decisions; the executor never reads it). GitHub PR state is the only
status. Verification: [`docs/verification.md`](docs/verification.md). Document shape:
jon-platform ADR-0005.

## Before proposing architecture or implementation

Read, in order:

1. `/Users/jon/code/jon-platform/AGENTS.md`
2. `docs/README.md`
3. The linked Vinyl Fever docs in the order listed there

Vinyl Fever is Mac-first. The raw-file and script-running workflows are macOS
execution flows. SwiftUI and shared Swift package boundaries should preserve the
option for a future iPad companion, but iPad is not a v1 execution surface.

Do not use SwiftData. Follow Jon's house stack from `jon-platform`: plain value
records, SQLiteData for app state, `@Observable` feature models, dependency-backed
clients, and no TCA.
