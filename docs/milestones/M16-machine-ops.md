# Milestone 16 — Machine Ops (a safe database home, one-command install, setup checks)

*Give Vinyl Fever's database its own file that no build can erase, and turn the setup guide into
two scripts. S0 runs as soon as M13 S3 merges, ahead of anything else; see Decision 5. Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply. Where this doc and those conflict, stop and flag
it.*

Summary: Jon's app state (artist aliases, recipes, policies, run logs) lives in
`~/Library/Application Support/SQLiteData.db`. That's SQLiteData's default name, at the top level
of Application Support, so any other unsandboxed app using SQLiteData's default would share it.
Worse, Debug builds turn on GRDB's `eraseDatabaseOnSchemaChange`, and the app Jon uses daily is a
Debug build. Launching any Debug build older than the newest migration silently erases the file.
S0 moves the database to a Vinyl Fever path, adopts the old file without deleting it, and
replaces silent erasure with a loud refusal and a backup. S1 adds `scripts/install-vinyl-fever`
(build, verify, install, restart, smoke test). S2 adds `scripts/setup-mac`, which checks a Mac
against [the setup guide](../setup/README.md) and applies the steps that can be automated. Three
slices in three dispatches.

## The milestone in one sentence

Opening an old build can never cost Jon his aliases. A new build is one command from tested to
serving ChatGPT, and a new Mac is one command from "what's missing?"

## Evidence (2026-10-21)

- The live file is `~/Library/Application Support/SQLiteData.db` (6.6 MB plus a 2.7 MB WAL). It
  holds 9 Vinyl Fever migrations (`Create 'sourceLabels' table` … `Create 'artistAliases' table`),
  83 artist aliases, 75 run records, 1 recipe, and 1 policy.
- `VinylFeverDatabase.open()` calls `SQLiteData.defaultDatabase(configuration:)`. In the `.live`
  context that's `<Application Support>/SQLiteData.db`. In `.test` and `.preview` it's a fresh
  temporary file, so **tests never touch the live file**.
- `#if DEBUG migrator.eraseDatabaseOnSchemaChange = true`. GRDB erases when the database
  contains a migration the running build doesn't know (`DatabaseMigrator.swift`: "Database
  contains an unknown migration"), or when a known migration's schema changed.
- This Mac has 5 `VinylFever.app` builds in DerivedData from different checkouts and branches.
  `/Applications/VinylFever.app` itself was missing until 2026-10-21, and the tunnel was running
  a helper from the deleted copy.
- Mitigation taken: an integrity-checked copy is at
  `~/Library/Application Support/VinylFever/Backups/SQLiteData-2026-10-21.db`.
- `vf-mcp` doesn't open the database; it reads `artist-aliases.json` (M15 Decision 4). The
  poller doesn't either.

## Slices

**Dispatch 1: S0** (Core + app; device gate). **Dispatch 2: S1** (scripts; device gate).
**Dispatch 3: S2** (scripts; device gate on the laptop and the Intel mini).

- [x] **S0 — The database's own home (Core + app).** Merged as #108; the laptop device gate passed 2026-10-21.
  - The live path is `~/Library/Application Support/VinylFever/VinylFever.sqlite`, next to the
    snapshot and inboxes. `VinylFeverDatabase.open()` passes it to
    `SQLiteData.defaultDatabase(path:configuration:)`, so `.test` and `.preview` keep their
    temporary files.
  - **Adopting the old file**, once, before opening:
    - Only when the new file doesn't exist and `SQLiteData.db` does.
    - Only when the old file is provably Vinyl Fever's: its `grdb_migrations` contains
      `Create 'sourceLabels' table`. Otherwise leave it alone and start fresh.
    - Copy with SQLite's online backup (GRDB `backup(to:)`), which carries the WAL. Then check
      the copy: `integrity_check` is `ok` and every table's row count matches.
    - Rename the old file and its `-wal`/`-shm` to `SQLiteData.db.moved-to-VinylFever`. Never
      delete it.
    - If any step fails, leave both files as they are and show the error. Don't start fresh.
  - **No erasing the live file, ever.** Remove `eraseDatabaseOnSchemaChange`.
    - **An older build** finds a migration it doesn't know (`hasBeenSuperseded`). It doesn't
      open the database. It shows "This build of Vinyl Fever is older than your data. Install
      the current build." and quits. Tests cover this with a typed error from `open`.
    - **Pending migrations** on the live file trigger a backup first:
      `VinylFever/Backups/VinylFever-<timestamp>.sqlite`, made with the online backup. Keep the
      newest 5.
    - **Merged migrations are immutable.** Add a line to `technical-architecture.md` (Persistence).
      A migration being edited on a branch only meets temporary test databases.
  - Settings → Chat Access shows the database path under the snapshot path.
  - Update [the setup guide](../setup/README.md) (*Moving to a replacement Mac*) to the new
    path.

  **DoD:**
  - Tests, all in temporary directories:
    - adoption copies, verifies, and renames, and the copy has every row;
    - a foreign `SQLiteData.db` (no Vinyl Fever migration) is untouched;
    - an existing new file wins, and the old file is untouched;
    - a failed verification leaves both files and throws;
    - an unknown migration throws the typed "older build" error and changes nothing;
    - pending migrations make a backup first, and only the newest 5 are kept.
  - **Device gate (laptop):**
    1. Quit every copy of Vinyl Fever, then install the S0 build.
    2. Launch a pre-S0 build and leave it running. Launch the S0 build. It must refuse with
       "Quit the other copy of Vinyl Fever, then open this one again.", and
       `VinylFever/VinylFever.sqlite` must not appear.
    3. Quit the pre-S0 copy and launch S0 again. Confirm the 83 aliases, recipe, and policy are
       present and `SQLiteData.db.moved-to-VinylFever` exists.
    4. Launch the pre-S0 build again. It starts on a new empty `SQLiteData.db`, and the new file
       remains untouched.

- [ ] **S1 — `scripts/install-vinyl-fever` (build → verify → install → restart → smoke).**
  - `xcodegen generate`, then build the `VinylFever` scheme into
    `.build/InstallDerivedData`, then `xcodegen generate` again so the checkout stays clean
    (the `build-listening-poller` pattern). `--configuration Debug|Release`, defaulting to
    Debug (Decision 6). `-n` prints the steps.
  - **Verify before installing:**
    - `codesign --verify --deep --strict`, and the `vf-mcp` helper is present;
    - the embedded profile is **Vinyl Fever Dev Profile**, and its `ProvisionedDevices`
      includes this Mac's Provisioning UDID (`system_profiler SPHardwareDataType`). That's the
      first thing to fail on a new Mac, so name the fix: the guide's *Signing* section.
  - **Install:**
    - If Vinyl Fever is running, ask, then quit it (AppleScript `quit`).
    - Copy the build next to the installed app, swap them, and keep the previous app until the
      smoke test passes. If the smoke test fails, swap back and exit non-zero.
  - **Restart:** if the `com.jonphillips.mcp-tunnel.vinyl-fever` agent is loaded, `launchctl
    kickstart -k` it, so `tunnel-client` starts the new helper. A running helper keeps the old
    binary otherwise. Wait for `/readyz`.
  - **Smoke:** `scripts/mcp-smoke <helper>` is a stdio JSON-RPC probe using Python's standard
    library, run with `python3 -I`. It runs `initialize`, then `tools/list` (expects
    `library_overview`), then `library_overview` and `recent_listening` (`24h`). It prints each
    call's timing and a short result.
    - A "not set up yet" result from `recent_listening` is a warning, not a failure.
    - Any other `isError` fails.
  - **Report:** one table of what passed. That includes `mcp-tunnel status` and, from
    `recent_listening` coverage, which Mac polls and the last fetch's age.

  **DoD:**
  - `shellcheck` passes on both scripts. `-n` output is reviewed in the PR.
  - **Device gate (laptop):** one run from a clean checkout of `main` installs, restarts the
    tunnel, and passes the smoke test. A second run with the profile check forced to fail stops
    before touching `/Applications`.

- [ ] **S2 — `scripts/setup-mac` (check, then apply what can be automated).**
  - `setup-mac [--role build,chat,poll] [--apply]`. The default is a read-only report: one line
    per step from [the setup guide](../setup/README.md), marked passed, failed, or manual, with
    the guide's anchor for each one that isn't passed.
  - Constants live in `scripts/machine.conf` (not secret): the team ID, the profile names, the
    tunnel ID, the tunnel profile name, and the Homebrew packages. The guide points to it.
  - **Every Mac:** iCloud Drive's folder exists. iCloud Keychain and Optimize Mac Storage are
    *manual* unless S2 finds a reliable read for them.
  - **Build role:**
    - Xcode installed with its first launch done (`xcodebuild -checkFirstLaunchStatus`);
    - Homebrew packages; jon-platform as a sibling checkout;
    - an Apple Development identity for team `7MQEE539G9`;
    - both profiles installed and including this Mac.
    - `--apply` installs the packages, clones jon-platform, then runs `install-vinyl-fever`.
  - **Chat role:**
    - the runtime key in the Keychain (checked by presence and length; it's never printed);
    - the `tunnel-client` profile points at `/Applications/VinylFever.app/Contents/Helpers/vf-mcp`
      and the configured tunnel ID;
    - the agent is loaded and `mcp-tunnel status` is ready;
    - `~/music-chat` exists with its files.
    - `--apply` runs `mcp-tunnel store-key` (it asks Jon to copy the key first),
      `init --force`, and `install-agent`. It writes `~/music-chat` from templates.
  - **The `~/music-chat` template becomes files.** Move the `AGENTS.md` text out of
    `MCP-SETUP.md` into `docs/chatgpt/music-chat/` (`AGENTS.md`, `CLAUDE.md`, `.mcp.json`), and
    MCP-SETUP links to it. `--apply` copies them and adds `[mcp_servers.vinyl-fever]` to
    `~/.codex/config.toml` only when it's missing.
  - **Poll role (checks only):**
    - automatic login is on (`defaults read /Library/Preferences/com.apple.loginwindow
      autoLoginUser`), and FileVault's status is reported because it blocks automatic login;
    - `pmset -g` shows `sleep 0` and `autorestart 1`;
    - this Mac holds the listening lease, and its stream's last fetch is under 2 hours old.
    - A wrong `pmset` value prints the `sudo pmset` command to run. The script never runs
      `sudo` itself.
  - Never automated (*manual* with the guide anchor): the Apple ID, the developer portal, Settings
    toggles, and Login Items approval.

  **DoD:**
  - `shellcheck` passes. `--apply` run twice changes nothing the second time.
  - **Device gate (laptop and Intel mini; amended 2026-10-21, as no new mini is planned):**
    - **Laptop:** `--role build,chat` reports no failures. Remove one thing per role, such as
      the tunnel agent (`mcp-tunnel uninstall-agent vinyl-fever`) or a Homebrew package. Then
      the report flags it, `--apply` restores it, and a second `--apply` changes nothing.
    - **Intel mini (macOS 15, no Xcode):** run from a copy of `scripts/`. `--role poll` passes
      the lease, freshness, `pmset`, and automatic-login checks for the VF Listening Poller.
      The Vinyl Fever app checks are skipped there.

## Constants register (starting values)

| Constant | Value | Rationale |
| --- | --- | --- |
| Database path | `~/Library/Application Support/VinylFever/VinylFever.sqlite` | Beside the snapshot and inboxes; one folder to copy when moving Macs. |
| Adopted file's new name | `SQLiteData.db.moved-to-VinylFever` | Says what happened; never deleted. |
| Pre-migration backups kept | 5 | A few schema changes of history; the file is under 10 MB. |
| Install configuration | Debug | The build Jon runs today and the one gated with the tunnel. |
| Smoke test calls | `library_overview`, `recent_listening` (`24h`) | One snapshot tool, one log tool. |
| Poll freshness threshold | 2 h | Two missed hourly fetches. |

## Out of scope — with destinations

- **Developer-portal automation** (register the device and regenerate the profile through the
  App Store Connect API). It would remove the last manual step on a new Mac, but it needs an API
  key in the Keychain and profiles get recreated, not edited. → A candidate after S2's gate, if
  the manual step bites twice.
- **Deploying to another Mac over SSH** (`install-vinyl-fever --host mini.local`). → A
  candidate after S2.
- **Installing Xcode** (`xcodes`). → No; it's once per Mac and needs an Apple ID.
- **Sharing `setup-mac`'s tunnel and Homebrew parts across Jon's apps.** → Lift into
  jon-platform when a second app needs them (Yes Chef's MCP server).
- **Release builds by default.** → A candidate after S1. The helper's 9.7 s first call is a
  Debug number; flip the default once a Release build passes the same smoke test.

## Decisions

Open — the architect's recommendation is listed first. Merging this plan approves the
recommendations, including Decision 2's schema and migration change, which is Jon's call. It
doesn't dispatch anything: the review that approves M13 S3 sets `NEXT_UP.md` to Dispatch 1.

1. **The database lives at `VinylFever/VinylFever.sqlite` in Application Support,** not at a
   bundle-ID path. Everything else Vinyl Fever keeps locally is already in that folder.
2. **Adopt the old file by copying and renaming it, never by moving or deleting.** Proving it's
   Vinyl Fever's before adopting it keeps the copy from ever swallowing another app's database.
   A failure stops loudly instead of starting fresh, because starting fresh looks exactly like
   data loss.
3. **Refuse loudly instead of erasing.** An older build quits with a message. Erasing is what
   makes an old build dangerous, and every test database is already temporary, so erasing buys
   nothing.
4. **Back up before every migration of the live file.** It's cheap and local, and it covers the
   case a refusal can't: a new migration with a bug.
5. **S0 goes next, right after M13 S3, ahead of any other milestone.** It's a data-safety fix,
   and the danger is live today. S0 touches `VinylFeverApp.swift`, which S3 also changes, so it
   waits for S3 instead of running alongside. S1 and S2 only touch `scripts/` and docs.
6. **Install Debug for now.** Release signing hasn't been tried with the manual profile, a
   Release build of `vf-mcp` takes about 5 minutes (`open-questions.md`, M12), and Debug is what
   passed the tunnel smoke test on 2026-10-21. The flag makes switching one word.
7. **Scripts check first and never use `sudo` or the developer portal.** The read-only report is
   the useful part on a new Mac. `--apply` only does what's idempotent and local.
