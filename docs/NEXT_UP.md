# Next Up — M12 · Dispatch 3: S2 vf-mcp server + playlist inbox

**Slices:** M12 · S2 (branch `m12/s2-vf-mcp`)
**Briefs:** docs/milestones/M12-library-context-mcp.md § S2
**Done when:** S2's DoD; core and app tests green on macOS 27; PR opened in `jonphillips/vinyl-fever`.
**Owed:** S2's device gate (iPad ChatGPT through a `vinyl-fever` tunnel, plus one Claude Code session). (The effort's mcp-hello iPad gate passed on Jon's Mac, 2026-10-17.)
**Notes:** The kit merged as jon-platform#74 (`b6f48d6`); pull jon-platform `main` before building. Use the kit's API as shipped: handlers are `async throws`; `MCPToolResult.json(_:)` already encodes ISO 8601 dates with sorted keys; pin the instructions with `MCPServer.instructionsHeadStandsAlone`.
