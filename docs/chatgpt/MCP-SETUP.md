# Vinyl Fever MCP setup

Vinyl Fever bundles the `vf-mcp` stdio helper at:

```text
<VinylFever.app>/Contents/Helpers/vf-mcp
```

Use the resolved path shown in **Settings → Chat Access (MCP)** if the app is installed elsewhere.
The helper reads `~/Library/Application Support/VinylFever/LibrarySnapshot/library-snapshot.json`
and stages playlist proposals in `~/Library/Application Support/VinylFever/PlaylistInbox/`. It reads
listening history from `iCloud Drive/Vinyl Fever/Listening/` when polling has been set up.
Only Create in Vinyl Fever writes a playlist to Apple Music.

For ChatGPT, connect the Secure MCP Tunnel and install the `Vinyl Fever` plugin. The tunnel ID and the per-Mac steps for a new or replacement Mac are in [Setting up a Mac](../setup/README.md#chat-host). The
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
- `recent_listening`
- `stage_playlist`

`top_artists` and `top_tracks` accept `period: 7d`, `30d`, or `90d` for log-backed counts;
omit `period` or use `all_time` for Mac library counts. Log-backed responses include coverage.
Ask `recent_listening` before claiming what Jon is into lately. A logged play means a song started;
skips and brief autoplay count, so don't present it as a full listen.

For Claude Code and Codex, use a dedicated `~/music-chat` folder. The maintained files are in
[`music-chat/`](music-chat/): `AGENTS.md`, `CLAUDE.md`, and `.mcp.json`. Copy them there, then add
the `[mcp_servers.vinyl-fever]` entry to Codex configuration if it is missing. `scripts/setup-mac
--role chat --apply` does these local steps idempotently. Settings can copy each client
configuration with the installed helper path filled in. The tools, contract, and shared client
safety guidance are described in jon-platform's MCP access guide.
