# Milestone 19 — Backups (a daily copy of everything Vinyl Fever can't rebuild)

*Keep a second copy of every file Vinyl Fever can't rebuild, made every day without Jon doing
anything, in a place that fails differently from the original. Rules in
[../technical-architecture.md](../technical-architecture.md) and
`/Users/jon/code/jon-platform/AGENTS.md` apply. Where this doc and those conflict, stop and flag
it.*

Summary: Vinyl Fever's irreplaceable data has no working backup. The logs live only in iCloud
Drive, which syncs a deletion or a bad write to every Mac. The database lives only on the
laptop. The laptop's Time Machine last finished on 2026-02-15. S1 makes a daily backup set on
the laptop from the hourly listening agent: the iCloud logs are copied to local disk, and the
database to both local disk and iCloud Drive. Each set has a manifest that flags an append-only
log that lost lines. One slice, dispatched before M18 S2. It doesn't touch `vf-mcp`.

## The milestone in one sentence

Every day, each file Vinyl Fever can't rebuild gets a copy in the place it doesn't already live
(local disk for the iCloud logs, iCloud Drive for the database), and a log that shrinks is
caught.

## What's true today (architect, read-only, 2026-10-25)

- **What can't be rebuilt, and where it lives:**

  | Data | Where | Size |
  | --- | --- | --- |
  | Listening log (`Listening/fetches/<poller>/<month>.jsonl`) | iCloud Drive only | 220 KB after 5 days, two pollers |
  | Taste Intelligence: `notes*.jsonl`, `playlist-roles.json`, `curation/`, and from M17 S2 and M18 S1 `exposure/` and `recommendations/` | iCloud Drive only | under 30 KB |
  | App database (`VinylFever/VinylFever.sqlite`: aliases, recipes, policies, run logs) | laptop only, no CloudKit | 6.5 MB |
  | Processed playlist inbox (`PlaylistInbox/Processed/`) | laptop only | small |

  The library snapshot is rebuilt from Music.app, so it isn't backed up.
- **The laptop's Time Machine is broken.** Its destination, the SMB share on `PhillipsWest`,
  fails to mount, and the last snapshot is 2026-02-15. M13 Decision 1 said "the laptop's Time
  Machine backs it up". That hasn't been true since February.
- **Optimize Mac Storage is on for the laptop.** `notes.jsonl`, `playlist-roles.json`, and
  `lease.json` were cloud-only (`dataless`) on the laptop. Even a working Time Machine backs up
  only the placeholder of a cloud-only file.
- **Reading a cloud-only file downloads it.** Both a plain read and a coordinated read
  (`NSFileCoordinator`) returned the full contents and cleared the `dataless` flag (probed on
  `lease.json` and `notes.jsonl`). A backup that reads through coordination gets real bytes,
  as long as the Mac is online.
- **The only extra copies of the database:** M16's pre-migration backups
  (`VinylFever/Backups/VinylFever-<timestamp>.sqlite`, newest 5, made only when a migration is
  pending), and a manual copy from 2026-10-21. All of them are on the same disk.
- **An hourly agent already runs on the laptop without the app open.** It's
  `com.jonphillips.vinylfever.listening.agent`, which runs `VinylFever --poll-listening`
  (`VinylFeverApp.swift`) and is registered through `SMAppService`. It doesn't open the
  database.

## Shared rules

- **Tests never touch live paths.** The live database, `Backups/`, the iCloud `Vinyl Fever/`
  folder, and the inboxes are reached only through injected roots. Tests use temp directories.
- **Backups run only in the `.live` context.** The app-test host and previews never start one.
  M16 S0 hung the tests by running startup work outside `.live`.
- **A backup never writes to its sources.** The live database is opened read-only for the copy,
  and iCloud files are read through `NSFileCoordinator`. Nothing in `Vinyl Fever/` changes,
  except the new `Backups/` folder, which is excluded from the sets.
- **A backup failure never breaks polling or launch.** It logs, shows in Settings, and tries
  again on the next hourly run.

## Slices

**Dispatch 1: S1** (Core + app + `setup-mac`; Jon's laptop gate). It runs before M18 S2, and its
completing PR advances `NEXT_UP.md` to M16 S4 (added 2026-10-25), which runs before M18 S2.

- [ ] **S1 — The daily backup set (Core + app).**
  - **When:** after each `--poll-listening` run, and once at app launch in `.live`, Vinyl Fever
    makes today's set if it doesn't exist yet ("today" is the local calendar day). Both paths
    call one Core function. A lock file keeps the app and the agent from building the same set
    at once, and the loser just returns.
  - **The local set:** `~/Library/Application Support/VinylFever/Backups/Daily/<yyyy-MM-dd>/`.
    It's built in `<yyyy-MM-dd>.partial/`, then renamed into place. A `.partial` folder left by
    a crash is removed on the next run. The set contains:
    - `VinylFever.sqlite`: SQLite's online backup (GRDB `backup(to:)`, as M16 S0 does) from a
      read-only connection, so it works while the app holds the database. Check the copy with
      `integrity_check`.
    - `iCloud/`: every file under iCloud Drive's `Vinyl Fever/`, read through
      `NSFileCoordinator`, keeping relative paths. Leave out `Backups/` and `.DS_Store`.
    - `PlaylistInbox/Processed/`.
    - `manifest.json`: `{"format":"vf-backup-manifest","version":1,...}` with `createdAt`,
      `host`, the build, and each file's relative path, byte count, SHA-256, line count for
      `.jsonl` files, and any warnings.
  - **Hard links for unchanged files:** a file whose size and SHA-256 match the previous set's
    copy is hard-linked to it, not copied. Old months of the listening log then cost nothing
    per day.
  - **The database in iCloud:** also copy the set's database to
    `iCloud Drive/Vinyl Fever/Backups/<host>/VinylFever-<yyyy-MM-dd>.sqlite`. Name the host
    with `ListeningStore.liveHostName()` and the same filename sanitizing as the taste logs.
    That way the database survives losing the laptop.
  - **Shrink check:** compare each `.jsonl` with the previous set's copy.
    - Fewer lines than before, or a file that's gone, adds a warning (`shrank` or `missing`)
      naming the file.
    - A file that can't be read (offline and cloud-only, or a coordination timeout) adds
      `unreadable`, and the previous set's copy is hard-linked in its place, so the set is still
      complete.
    - A set with any warning, and the set before it, are never pruned.
  - **Pruning** (after a set is complete):
    - local: keep the newest 30 sets, plus the first set of every month, forever;
    - iCloud database copies: keep the newest 14, plus the first of each month for 12 months;
    - never touch M16's pre-migration backups in `Backups/`, or anything else outside `Daily/`.
  - **Settings → Backups:** the newest set's date and size, any warnings from the last 30 days
    (with file names), and a **Show in Finder** button. If there's no set from the last 2 days,
    say so.
  - **`scripts/setup-mac`:** add warn-only checks. Warn when Time Machine has no destination or
    its newest snapshot is older than 7 days, and when the newest daily set is older than 2
    days.
  - **Docs:** add *Backups and restoring* to [the setup guide](../setup/README.md): what's in a
    set, where the sets are, and how to restore.
    - **The database:** quit the app, turn off the agent, then copy the set's file over
      `VinylFever.sqlite` and remove its `-wal` and `-shm`.
    - **A log file:** copy it back into iCloud Drive only when the live file is missing or has
      fewer lines. Never overwrite a file that has more lines.

  **DoD:**
  - **Core tests** (all in temp roots):
    - a set has the database, every iCloud file except `Backups/` and `.DS_Store`, the processed
      inbox, and a manifest whose hashes and line counts match;
    - the database copy is made while another connection writes in WAL mode, passes
      `integrity_check`, and has every row;
    - an unchanged file is a hard link to the previous set's copy (same inode), and a changed
      file is a fresh copy;
    - each warning: `shrank`, `missing`, and `unreadable`, where `unreadable` hard-links the
      previous copy;
    - a set with a warning, and the set before it, survive pruning;
    - pruning keeps 30 daily sets plus each month's first, keeps the iCloud copies at 14 plus
      monthly, and leaves `Backups/VinylFever-*.sqlite` alone;
    - a leftover `.partial` folder is removed, and two simultaneous runs make one set;
    - **restore round-trip:** a set's files, read from the set, give the same `ListeningLog`,
      taste notes, roles, and recommendation ledger as the sources, and the database opens with
      the same row counts.
  - **App tests:** the backup doesn't run in the test context, and the Settings row's states
    (no set, an old set, warnings, OK).
  - `shellcheck scripts/setup-mac`, and an isolated `setup-mac` run that shows both warnings.
  - **Jon's laptop gate (after install, owed until done):**
    1. Run `VinylFever --poll-listening` once, or wait for the hourly agent. Today's set appears
       under `Backups/Daily/`, and `Vinyl Fever/Backups/<host>/` in iCloud Drive has today's
       database.
    2. `notes.jsonl` and `playlist-roles.json` are in the set with their real sizes (3,152 and
       17,472 bytes or more), which proves cloud-only files were downloaded.
    3. Settings → Backups shows the set. The next day's set hard-links the unchanged files (the
       architect checks inodes).

## Prerequisites (Jon, not the executor's)

- [ ] **Fix the laptop's Time Machine.** The SMB share on `PhillipsWest` fails to mount, and the
  last backup is 2026-02-15. Either repair the share, or point Time Machine at a local disk.
  Until then, the local sets live on the same disk as the originals, and the only off-laptop
  copy of the database is the one in iCloud.
- **Not needed:** turning off Optimize Mac Storage, or marking the folder Keep Downloaded. The
  sets are real local files, so Time Machine will back them up either way.

## Constants register (starting values)

| Constant | Value | Rationale |
| --- | --- | --- |
| Local daily sets kept | 30 newest + the first of each month, forever | A month of daily rollback. The monthly sets cost little with hard links. |
| iCloud database copies kept | 14 newest + monthly for 12 months | About 7 MB each, so about 180 MB at most of Jon's iCloud. |
| Backup cadence | once per local calendar day | The logs change hourly, but losing a day of log is recoverable from the other Mac's stream. |
| "Backups are stale" warning | 2 days with no set | The agent runs hourly, so 2 days means it has stopped. |
| Time Machine warning in `setup-mac` | newest snapshot older than 7 days | Catches February's silent failure within a week. |

## Out of scope — with destinations

- **A copy on the Intel mini** (the poller backing up the iCloud logs to the mini's disk). →
  Only if Time Machine can't be fixed. iCloud already keeps the logs off the laptop.
- **A restore script.** → If restoring is ever done twice. Until then it's a documented
  procedure.
- **Backing up the library snapshot.** → No. It's rebuilt from Music.app.
- **Backup status in `vf-mcp`.** → No. The chat doesn't need it, and M18 S2 edits `vf-mcp`.
- **The iOS apps' backups** (Yes Chef, Galavant). → jon-platform: `CloudSyncKit`'s
  `DatabaseBackup` is manual today. Scheduled backups would be a platform decision, not Vinyl
  Fever's.

## Decisions

Open — the architect's recommendation is listed first. Merging this plan approves them and sets
`NEXT_UP.md` to Dispatch 1.

1. **Each copy goes where the original isn't.** The iCloud logs are copied to local disk, which
   covers iCloud syncing a deletion or a bad write. The laptop's database is copied to iCloud
   Drive, which covers losing the laptop. Time Machine is a third layer once it's fixed. The
   plan doesn't depend on it.
2. **It runs from the existing hourly agent and at launch.** Not from a new launchd job or a
   shell script. The agent is already registered, runs without the app open, and keeps the
   work in tested Swift.
3. **Daily sets with hard links, not a single rolling copy.** A rolling copy would faithfully
   copy a bad write over the good one. Hard links keep 30 days plus monthly sets cheap.
4. **Catch a log that shrinks.** These logs are append-only, so a line count that drops is the
   one visible sign of loss. A set with a warning pins the set before it.
5. **The database copy uses M16's GRDB online backup, not `CloudSyncKit`.** Vinyl Fever doesn't
   sync with CloudKit. `CloudSyncKit`'s restore guards are about sync, and M16 already has the
   copy.
6. **Restore stays manual and documented.**
7. **S1 runs before M18 S2.** M18 S1 adds another log that can't be rebuilt, and M18 S2's gate
   waits two weeks for New Music data anyway. S1 doesn't touch `vf-mcp`, so it doesn't collide
   with M18's work.
