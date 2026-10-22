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
**Dispatch 3: S2** (scripts; device gate on the laptop and the Intel mini). **Dispatch 4: S3**
(scripts + tests; added 2026-10-22 from the #108 and #110 reviews; no device gate beyond the
laptop).

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

- [x] **S1 — `scripts/install-vinyl-fever` (build → verify → install → restart → smoke).**
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
  - `shellcheck` passes on the installer, `mcp-smoke --self-test` passes, and `-n` output is reviewed in the PR.
  - **Device gate (laptop):** one run from a clean checkout of `main` installs, restarts the
    tunnel, and passes the smoke test. A second run with the profile check forced to fail stops
    before touching `/Applications`.
  - **Gate passed 2026-10-21 after review changes:** plain Debug install passed with Vinyl Fever
    open (the dialog appeared and the app quit); forced profile failure stopped before install;
    forced smoke failure restored the prior app and restarted the tunnel. `lsof` showed the
    running helper and installed helper share inode `538835276`.

- [x] **S2 — `scripts/setup-mac` (check, then apply what can be automated).** Both device gates
  passed (laptop 2026-10-21, Intel mini 2026-10-22).
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
    - `--apply` installs missing packages and clones jon-platform. It runs
      `install-vinyl-fever` only when `/Applications/VinylFever.app` is missing; use the installer
      directly for updates.
  - **Chat role:**
    - the runtime key in the Keychain (checked by presence and length; it's never printed);
    - the `tunnel-client` profile points at `/Applications/VinylFever.app/Contents/Helpers/vf-mcp`
      and the configured tunnel ID;
    - the agent is loaded and `mcp-tunnel status` is ready;
    - `~/music-chat` exists with its files.
    - `--apply` runs `mcp-tunnel store-key` (it asks Jon to copy the key first),
      `init --force`, and `install-agent` when needed. It copies only missing files into
      `~/music-chat`; existing files, including customized `AGENTS.md`, are never overwritten.
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
    - **Laptop — passed 2026-10-21:** `--role build,chat` reports no failures. Removing
      `xcodegen` and unloading the tunnel agent were both detected; `--apply` restored each role,
      and the follow-up reports passed. With the app already installed, repeating Build and Chat
      `--apply` made no changes.
    - **Intel mini (macOS 15, no Xcode) — passed 2026-10-22:** copy `scripts/setup-mac` and
      `scripts/machine.conf` to any folder on the mini, then run `./setup-mac --role poll`. Expect
      automatic login, `pmset`, and lease/freshness checks to pass with the lease held by the mini's
      ComputerName. Record FileVault status; when enabled, it blocks automatic login. Build and
      Chat checks are skipped on this Poll-only run.
      - **Result:** Jon ran it on the mini and it checked out. The lease is held as
        "Jon’s Mac mini (2)", the mini's ComputerName. **FileVault is on**, so macOS won't log in
        automatically: after a restart or power cut, the mini waits at the FileVault unlock screen
        and polling stops until Jon logs in. The signal is the last fetch's age, in
        `coverage` and in Settings.

- [x] **S3 — Hardening: System Events access, stale builds, and load-proof timing tests
  (scripts + app + tests).** *Amended 2026-10-22, before dispatch: the stale-build items below.
  Right after `install-vinyl-fever` succeeded, Jon opened "Vinyl Fever" from Spotlight or the
  Dock and got the Oct 21 Xcode build in DerivedData, from before S3 and S0. It had no polling
  toggle, and it created an empty `SQLiteData.db`. Also amended 2026-10-22: stop tracking the
  generated Xcode project. Every `xcodegen generate` (the installer runs it twice) left a
  target-order diff in `project.pbxproj`, which stopped the executor's "go" on an unclean
  tree.*
  - **The installer refuses when it can't tell whether Vinyl Fever is running.**
    - Today, `running_count` in `scripts/install-vinyl-fever` prints nothing when Automation
      access to System Events is denied. `[[ "" -gt 0 ]]` is false, so the install goes ahead
      and swaps out an open app's bundle.
    - Make `running_count` print only an integer. If `osascript` fails or prints anything else,
      exit before staging: "Vinyl Fever can't check whether it's running. Allow your terminal
      to control System Events (System Settings → Privacy & Security → Automation), or quit
      Vinyl Fever, then run this again." Do the same in the 30 s wait loop.
    - For the gate, honor `VF_INSTALL_RUNNING_COUNT` as a test override of the count (like
      `VF_MCP_SMOKE_FAIL`): `denied` simulates a failed `osascript`.
  - **`setup-mac` reports the grant.** In the build role, run the same System Events count:
    - `passed` when it returns an integer;
    - `failed` with the same Automation instructions when access is denied;
    - `manual` when the error can't be classified.
    It may trigger macOS's one-time Automation prompt; `--help` says so.
  - **Timing tests become opt-in perf checks.** Two tests assert absolute or relative wall-clock
    timings and failed at load average 60–116 while passing on re-runs and on `main`:
    - `LibrarySnapshotTests` "artist identity index build stays within 1.25x…";
    - `ListeningEngineTests` "a year of JSONL log files loads quickly with one or two pollers".
    - Keep every correctness `#expect` in both tests, always on. Move only the timing
      `#expect`s behind a shared `.enabled(if: ProcessInfo.processInfo.environment["VF_PERF_TESTS"] == "1")`
      condition. The cleanest way is to split each into a correctness test and a perf test.
    - Perf tests take the best of 3 runs for each measured side, to cut noise when they do run.
    - `docs/verification.md` adds `VF_PERF_TESTS=1 swift test --package-path …` as the perf
      check to run before a PR that touches `LibraryIndex`, `ArtistIdentity`, or the listening
      log reader.
  - **The installer reopens what it quit.** If `install-vinyl-fever` quit Vinyl Fever to install,
    it reopens the app afterwards with `open /Applications/VinylFever.app`:
    - after a passing smoke test, the new build;
    - after a rollback, the restored build.
    The report gains a "Reopened" row. If nothing was running, it opens nothing.
  - **Stop tracking the generated Xcode project; keep the dependency pins.**
    - **Why:** `xcodegen` 2.46 writes the targets in `project.yml` order (poller first), but every
      committed `project.pbxproj` from #85 to #105 had VinylFever first, almost certainly saved by
      Xcode. So any regeneration dirtied the checkout. #114 committed `xcodegen`'s order by
      accident; that fixed this one direction but not the cause. #100's scheme flips were the
      same problem.
    - **Untrack** with `git rm --cached`, and add to `.gitignore`:
      - `VinylFever.xcodeproj/project.pbxproj`
      - `VinylFever.xcodeproj/xcshareddata/xcschemes/`
      - `VinylFever.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
    - **Keep tracking `VinylFever.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.**
      It pins the Swift package versions; losing it would make builds resolve new versions
      silently. Verify that `xcodegen generate` leaves it in place and unchanged, including on a
      fresh clone where the project folder holds only that file.
    - **`.githooks/xcodegen-sync`:** if `VinylFever.xcodeproj/project.pbxproj` is missing, run
      `xcodegen generate` *without* `--use-cache`, since the cache could skip it. Remove the
      "tracked project changed" warning, which no longer applies. Keep `--use-cache`
      otherwise.
    - **`setup-mac`, build role:** check `git config core.hooksPath` equals `.githooks`;
      `--apply` sets it. Also check that `VinylFever.xcodeproj/project.pbxproj` exists;
      `--apply` runs `xcodegen generate`.
    - **Docs:**
      - `README.md` and `docs/verification.md`: the project is generated and never committed, so
        run `xcodegen generate` after cloning (the hooks do it after checkout, pull, and rebase).
      - Setup guide, Build Mac: add `git config core.hooksPath .githooks` before the first
        `xcodegen generate`.
      - `scripts/README.md` notes the same.
    - **The PR description warns** that pulling it deletes the tracked project files from every
      existing checkout. The post-merge hook regenerates them where hooks are enabled. Elsewhere,
      run `xcodegen generate` once. That includes the jon-platform workspace, which opens
      `vinyl-fever/VinylFever.xcodeproj`.
  - **Vinyl Fever warns when it's an older copy than the installed one.**
    - **When:** at launch, before the window opens and before the database. Only in the `.live`
      context: never under tests or previews, and never on the `--poll-listening` path.
    - **The check** is a pure function in Core, so it can be tested. Given the running bundle's
      URL and build date, and `/Applications/VinylFever.app`'s URL and build date if that app
      exists, it returns `.current` or `.olderThanInstalled(installedDate)`.
      - A bundle's **build date** is the newest modification date in its `Contents/MacOS/`.
        That covers both `VinylFever` and Debug's `VinylFever.debug.dylib`, and `ditto` keeps the
        build's dates when it installs.
      - It's `.current` when the running bundle *is* `/Applications/VinylFever.app` (compare
        resolved paths), when that app doesn't exist, or when the running copy is no more than 60 s
        older than it.
    - **If it's older**, show an alert: "This copy of Vinyl Fever was built <date>, and the one in
      Applications was built <date>. Open the installed copy?" The buttons are **Open Installed
      Copy** (the default) and **Keep This Copy**.
      - **Open Installed Copy** activates the already-running `/Applications/VinylFever.app` copy
        and exits, if one is running. Otherwise it starts the installed copy as a new instance
        (`NSWorkspace.openApplication`, `createsNewApplicationInstance`), then exits. If S0's
        duplicate-copy guard is relevant, the new instance applies it.
      - **Keep This Copy** continues as today. A newer Xcode build never sees the alert, so
        development runs are undisturbed.
    - Reuse S0's `showStartupAlert` style, so the alert comes to the front.

  **DoD:**
  - `shellcheck` passes on both scripts. The Listening and Core suites pass with and without
    `VF_PERF_TESTS=1` on an idle laptop.
  - **Laptop checks (the executor can run them):**
    - `VF_INSTALL_RUNNING_COUNT=denied scripts/install-vinyl-fever` stops before staging, with
      the Automation message, and `/Applications/VinylFever.app` is unchanged.
    - A normal install still passes.
    - `setup-mac --role build` reports System Events access as `passed`.
    - **Untracked project:**
      - After `xcodegen generate`, `scripts/install-vinyl-fever`, and `scripts/build-listening-poller`,
        `git status` is clean.
      - A fresh clone (`git clone` into a scratch folder with hooks enabled, plus the jon-platform
        sibling) generates the project on checkout and builds.
      - `Package.resolved` is unchanged in both.
      - `setup-mac --role build` reports the hooks path and the project as `passed`.
    - With Vinyl Fever open, `install-vinyl-fever` quits it, installs, and reopens the
      `/Applications` copy (`ps` shows the `/Applications` path).
  - **Stale-build check tests:** same path → `.current`; installed app missing → `.current`;
    running copy newer, or older by 60 s or less → `.current`; older by more than 60 s →
    `.olderThanInstalled` with the installed date.
  - **Jon's check (laptop) — passed 2026-10-22:** copy the installed app somewhere else and set its `Contents/MacOS`
    dates back a day with `touch -t`. Open the copy: the alert appears. With no installed copy
    already running, choose **Open Installed Copy** and confirm the installed copy starts. Then
    open the stale copy again while `/Applications/VinylFever.app` is already running and choose
    **Open Installed Copy**. Confirm the same `/Applications` PID is frontmost, no second
    installed instance starts, and the stale copy exits. Finally, open the stale copy again and
    choose **Keep This Copy**; it runs normally.
    - **Result:** all three cases passed on the merged #117 build (`6568a91`). With the installed
      copy not running, **Open Installed Copy** started it and the stale copy exited. With it
      already running, **Open Installed Copy** brought the same `/Applications` PID to the front
      and started no second instance. **Keep This Copy** ran normally.
    - The second case needs `open -n` on the stale copy. While the installed copy runs, a Finder
      double-click on a copy with the same bundle ID just activates the running one.

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
