# Vinyl Fever MCP setup

Vinyl Fever bundles the `vf-mcp` stdio helper at:

```text
<Vinyl Fever.app>/Contents/Helpers/vf-mcp
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
- `search_tracks`
- `artist_profile`
- `check_tracks`
- `stage_playlist`

For Claude Code and Codex, use a dedicated `~/music-chat` folder containing an `AGENTS.md` with
the music conversation tone and playlist contract, a `.mcp.json` for Claude Code, and the
corresponding `[mcp_servers.vinyl-fever]` entry in Codex configuration. Settings can copy each
client configuration with the installed helper path filled in. The tools, contract, and shared
client safety guidance are described in jon-platform's MCP access guide.
