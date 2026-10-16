# Next Up — M12 · Dispatch 1: library snapshot + preview annotations

**Slices:** M12 · S0, M12 · S1
**Briefs:** docs/milestones/M12-library-context-mcp.md §Library snapshot, §S0–S1, §Constants register
**Done when:** per the briefs — `swift test` green; S1's live ScriptingBridge read marked unverified in the PR.
**Owed:** M11 · Dispatch 2 device gate; M12 · S1 device gate (refresh timing, spot checks) on Jon's Mac.
**Notes:** No schema: the snapshot is a derived JSON file outside SQLiteData. The normalizer extraction in S0 must leave `CatalogMatchScorer` tests unchanged. Don't start S2 (the MCP server) in this dispatch.
