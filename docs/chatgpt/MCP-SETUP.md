# Vinyl Fever MCP setup

Vinyl Fever bundles the `vf-mcp` stdio helper at:

```text
<VinylFever.app>/Contents/Helpers/vf-mcp
```

Use the resolved path shown in **Settings → Chat Access (MCP)** if the app is installed elsewhere.
The helper reads `~/Library/Application Support/VinylFever/LibrarySnapshot/library-snapshot.json`
and stages playlist proposals in `~/Library/Application Support/VinylFever/PlaylistInbox/`.
Only Create in Vinyl Fever writes a playlist to Apple Music.

For ChatGPT, create a `vinyl-fever` Secure MCP Tunnel and install the `Vinyl Fever` plugin. The
shared tunnel, key, client, and troubleshooting steps are in
[jon-platform `docs/ios/mcp-access.md`](../../../jon-platform/docs/ios/mcp-access.md). Configure
the local helper with:

```sh
mcp-tunnel init vinyl-fever <tunnel_id> "<resolved helper path>"
mcp-tunnel install-agent vinyl-fever
```

The helper exposes these tools:

- `library_overview`
- `top_artists`
- `top_tracks`
- `search_library`
- `artist_profile`
- `check_tracks`
- `stage_playlist`

For Claude Code and Codex, use a dedicated `~/music-chat` folder. Save this as
`~/music-chat/AGENTS.md`:

```markdown
Keep music conversations warm, curious, and grounded in Jon's library. Ask before making
assumptions about taste. Use the Vinyl Fever tools for library claims, and check tracks before
proposing a final list.

The JSON object must have a non-empty name and at least one track. Each track needs artist and
title; album and year are optional hints, and year means the original release year.
Omit any track you are not confident exists as a released recording by that artist; do not
substitute another song. Include a specific version in the title only when that version is the
point, such as "Song (Live at the Fillmore)". Do not include IDs, ISRCs, URLs, or commentary fields.

When Jon asks for a playlist, stage it with `stage_playlist`; don't print the playlist. Jon reviews
and creates it in Vinyl Fever. Staging does not change Apple Music.

The description appears in Apple Music: one sentence about the music, with no library stats,
availability notes, or snapshot dates.
```

Add a `.mcp.json` for Claude Code and the corresponding `[mcp_servers.vinyl-fever]` entry in Codex
configuration. Settings can copy each client configuration with the installed helper path filled
in. The tools, contract, and shared client safety guidance are described in jon-platform's MCP
access guide.
