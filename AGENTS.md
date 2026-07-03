# AGENTS.md — Vinyl Fever

Entry point for any coding agent (Claude Code, Codex, …) working in this repo.
This is the **app-specific** layer; the general house layer lives in
`/Users/jon/code/jon-platform/AGENTS.md`.

## Working mode — what a bare "go" means (read first)

This repo is built by **two agents** under the architect/executor protocol.
`/Users/jon/code/jon-platform/docs/agent-collaboration.md` is canonical; the
summary below is so you can act on `go` without a second hop. Jon is **never the
courier** — orient from the repo (`gh`), not from a link or status he pastes.

**Start here:** [`CURRENT_HANDOFF.md`](CURRENT_HANDOFF.md) names the active
milestone, whose turn it is, and any pending decisions. It's a pointer at
canonical state (open PRs + each milestone's slice ledger), never a substitute for
it — if it disagrees with GitHub, GitHub wins.

- **Claude Code = architect / editor-in-chief.** Owns product/architecture docs,
  ADRs, and the milestone build orders; reviews the executor's slice PRs against
  their done-criteria. Does **not** write feature code or commit to a slice branch
  — input to a slice is a `gh pr review`, not a takeover.
- **Codex = executor.** Implements slices in order, one branch + PR each, keeps
  build and tests green, drives each PR to approval. Proposes plan changes, never
  performs them unilaterally.

On a bare **"go"**, before anything else, act as your role:

- **Architect (Claude):** run `gh pr status`. Review every ready, unreviewed
  executor slice PR against its milestone done-criteria (`gh pr review`); answer
  any `question-for-architect`. Queue clear → advance the plan (author/refine the
  next milestone, or unblock). Don't open slice branches or write feature code.
- **Executor (Codex):** run `gh pr status`. If a PR has changes requested, address
  it. Else open a **draft** PR for the next unchecked slice in the active milestone
  doc, get build + tests green, mark it ready. Blocked → write the question in the
  PR and label it `question-for-architect`.

If you have not read `agent-collaboration.md` this session, read it before acting.

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
