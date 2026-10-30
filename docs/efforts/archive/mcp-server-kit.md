# Effort — Shared MCP server kit, staging inbox, and tunnel script (jon-platform)

**Status:** Done 2026-10-17: jon-platform#74 (squash `b6f48d6`), after Jon passed the `mcp-hello`
iPad gate. Ran as **M12 · Dispatch 2**: after Dispatch 1 (snapshot and preview badges), before S2
(`vf-mcp`).
**Summary:** Build the domain-free pieces every app's MCP server needs, once, in jon-platform:
`MCPServerKit` (the stdio JSON-RPC loop and tool registry), `LLMHandoffKit.HandoffInbox` (stage
handoff contracts for review in the app), and `scripts/mcp-tunnel` (the Secure MCP Tunnel ops
recipe). One jon-platform PR. Vinyl Fever M12 · S2 is the first consumer; Yes Chef is the likely
second.
**Related:** jon-platform [ADR-0007](/Users/jon/code/jon-platform/docs/adr/0007-app-data-over-local-mcp.md)
(the decision; D1, D3, D4, D7) · jon-platform `docs/ios/mcp-access.md` (the manual recipe this
script automates) · [M12](../../milestones/archive/M12-library-context-mcp.md) · [Efforts index](../README.md)

Branch `effort/mcp-server-kit` **in jon-platform**, starting from a fresh `main`. It adds a
package and a script, with no schema and no sync. ADR-0007 must be merged before this starts.

## Slice 1 — jon-platform (one PR)

### `packages/MCPServerKit` (new path package)

**No package dependencies.** `.macOS(.v26)`, Swift 6 language mode. It defines its own small
`MCPValue` JSON enum (Codable, Sendable, Equatable) and doesn't depend on `LLMClientKit` just
for `JSONValue`. That keeps the kit leaf-level.

- **Tool definition.** `MCPTool`: `name`, optional `title`, `description`, `inputSchema: MCPValue`
  (a JSON-Schema object), `annotations: MCPToolAnnotations` (`readOnly`, `destructive`,
  `idempotent`, `openWorld`; all optional, encoded as the MCP `*Hint` keys), and
  `handler: @Sendable (MCPValue) async -> MCPToolResult`.
- **Results.** `MCPToolResult` holds text content and `isError`. It has helpers `.json(_:)`
  (compact encoding), `.text(_:)`, and `.error(_:)`.
- **The server.** `MCPServer(name:version:instructions:tools:limits:)`.
  - `run(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) async` reads
    newline-delimited JSON-RPC 2.0 and writes one response line per request.
  - **stdout carries protocol messages only.** The kit logs through an injected closure that
    defaults to stderr.
  - A pure `handle(line: String) async -> String?` does all the work, so tests drive it with
    no I/O. It returns `nil` for notifications.
- **Methods.**
  - `initialize`: echoes the client's `protocolVersion` if it is in
    `["2025-06-18", "2025-11-25"]`, otherwise answers with the latest. Advertises
    `capabilities.tools` and `serverInfo`, plus `instructions` when set.
  - `notifications/initialized`: no response.
  - `ping`: answers with `{}`.
  - `tools/list`: no pagination.
  - `tools/call`: looks up the tool by name and runs its handler. An unknown tool is a result
    with `isError: true`, not a protocol error. A handler that throws or traps is caught and
    returned as an `isError` result.
  - Any other method returns `-32601`; a line that isn't JSON returns `-32700` with a `null`
    `id`.
- **Limits.**
  - `MCPServerLimits.maxResultBytes` (default 256 KiB): a larger result is replaced by an
    `isError` result that says to narrow the query. It is never silently truncated.
  - The instructions check: `MCPServer.init` reports an issue (`reportIssue`-style
    precondition, debug only) when the first 512 characters of `instructions` end mid-sentence.
    Apps also pin their own instructions in tests.
- **Example target.** `mcp-hello` with two tools: `echo` (read-only) and `stage_note` (a write
  that stages into a `HandoffInbox` under `$TMPDIR`). It replaces the
  `@modelcontextprotocol/server-everything` test server and doubles as the ADR-0007 smoke test.

### `LLMHandoffKit.HandoffInbox` (additive)

A value type: `HandoffInbox(root: URL, fileExtension: String)`.

- `stage(_ contractText: String, slug: String, now: Date) throws -> StagedHandoff`: an atomic
  write of `<ISO8601>-<slug>.<ext>`. The slug is sanitized to `[a-z0-9-]`, at most 48
  characters.
- `list() throws -> [StagedHandoff]`, newest first. It excludes `Processed/`.
- `read(_:) throws -> String`.
- `markProcessed(_:) throws`: moves the file into `Processed/` and **never deletes**. On a name
  collision it appends `-2`, `-3`, and so on.
- `StagedHandoff` holds `url`, `stagedAt`, and `slug`.
- The inbox doesn't decode contracts. Callers validate with their own contract decoder before
  `stage` (ADR-0007 D3).

### `scripts/mcp-tunnel` (zsh)

Automates `docs/ios/mcp-access.md` steps 2–5. **It never prints, logs, or passes a key on a
command line except through `"$(pbpaste)"` in `store-key`.**

- `store-key`: stores the clipboard into the Keychain item `openai-tunnel-runtime` with `-U`,
  clears the clipboard, and prints only the stored length. It refuses keys shorter than 150
  characters ("truncated?").
- `init <profile> <tunnel_id> <helper-path> [--health-port N]`: runs `tunnel-client init` with
  the stdio sample, then `doctor`, with the key loaded from the Keychain into the child's
  environment only.
- `run <profile>`: loads the key from the Keychain and `exec`s `tunnel-client run`.
- `install-agent <profile>` / `uninstall-agent <profile>`: writes and loads (or unloads and
  removes) `~/Library/LaunchAgents/com.jonphillips.mcp-tunnel.<profile>.plist`. The agent
  invokes `mcp-tunnel run <profile>`, with `KeepAlive` and logs under
  `~/Library/Logs/mcp-tunnel/`.
- `status <profile>`: reports `/healthz` and `/readyz` from the profile's health port and
  whether the agent is loaded.
- `-n` gives a dry run that prints the commands.

### Doc touch

In `docs/ios/mcp-access.md`, replace "built in the ADR's build brief" with the real script
usage, and add the `mcp-hello` smoke test.

## Done when

- `swift test` is green for `MCPServerKit` and `LLMHandoffKit`. Run both through `quiet-run`.
- **Protocol tests** use `handle(line:)` and cover:
  - `initialize` with a supported version, an unsupported one, and none;
  - notifications produce no output;
  - `ping`;
  - `tools/list` shows every hint key exactly when it's set;
  - `tools/call` success, a handler that throws, and an unknown tool (each an `isError`
    result);
  - an unknown method gives `-32601`, and a non-JSON line gives `-32700`;
  - an oversize result is replaced by an error result;
  - a stdout capture of `run` over a scripted stdin contains only JSON-RPC lines.
- **Inbox tests** use a temp directory and cover stage, list order, read, markProcessed
  (including collisions), and that `Processed/` is excluded from `list`.
- `mcp-tunnel` passes `shellcheck`. `-n` output for each subcommand is checked by a small
  script test, and no subcommand's output contains the key. **Owed device gate (Jon):**
  - `store-key`, `init hello …` pointing at `mcp-hello`, and `install-agent hello`;
  - log out and back in, then call `echo` and `stage_note` from ChatGPT on the iPad;
  - confirm the staged file under `$TMPDIR`;
  - `uninstall-agent hello`.
- jon-platform `AGENTS.md` index and ADR-0007 already reference these. Mark ADR-0007
  **Accepted** in this PR only if Jon has merged it as Proposed and approves; otherwise leave it.
