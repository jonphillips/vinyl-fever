# AGENTS.md — Vinyl Fever

The app-specific layer. The house layer is `/Users/jon/code/jon-platform/AGENTS.md`.

## Working mode

Architect / executor, per jon-platform `AGENTS.md`.

## Read first

1. `/Users/jon/code/jon-platform/AGENTS.md`
2. [`docs/README.md`](docs/README.md)
3. The linked Vinyl Fever docs in the order listed there

## What's Vinyl Fever's own

Vinyl Fever is a Mac console with an iPhone companion (Jon, 2026-10-27). The
raw-file and script-running workflows are macOS execution flows and stay on the
Mac. The iPhone companion is an approved target: App Intents (Siri, the Action
button, Control Center, Shortcuts) and MusicKit for what happens away from the
Mac, such as Music Feedback, now-playing briefs, and queueing songs into Up Next.
Keep shared logic in Swift packages so the Mac app, the iPhone companion, and a
later iPad surface reuse it. See `docs/product-requirements.md` *Platform Stance*.
