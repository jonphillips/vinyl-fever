# Effort — Listening settings refresh, and full poll errors

**Status:** Done 2026-10-22 as #123.
**Summary:** Vinyl Fever's Settings shows a stale lease after another Mac takes over. Refresh the
listening section when the window comes forward and on Re-probe, in both apps. Also record a
failed poll's full error, with its domain, code, file path, and underlying error, so the next
"The file couldn't be saved." says which file failed and why.
**Related:** [M13](../milestones/M13-listening-history.md) (S5 gate result) · [Efforts index](README.md)

Branch `effort/listening-settings-refresh`, from a fresh `main`. One PR: no schema, no sync, and
no change to the log format.

## Why

These came up at M13 S5's gate (2026-10-22).

- **Stale lease label.** The mini took the lease at 8:59:52 pm ET, and the laptop's
  `lease.json` said so within a minute. Vinyl Fever's Settings on the laptop still said "This Mac
  holds the lease", even after Jon closed and reopened Settings.
  - `SettingsView` calls `listeningModel.refresh()` only in its `.task`.
  - The Settings scene keeps its view alive when the window closes, so reopening it doesn't run
    `.task` again.
  - Re-probe (`refreshButtonTapped`) refreshes the tool statuses only.

  The poller app's window has the same blind spot while it stays open in the background.
- **An unexplained failed save.** The laptop's hourly run at 8:27 pm, on the S4 build, exited 1.
  All it left was `last-poll-error.txt` saying "The file couldn't be saved.".
  - It wrote no fetch line, so coverage can't show the failure.
  - The unified log had no entry.
  - The next run succeeded, and that cleared the error.

  `pollOnce` keeps only `localizedDescription`. That drops the file path and the underlying POSIX
  or iCloud error, which are what would explain it.

## Changes

- **Refresh when the window comes forward.**
  - **Vinyl Fever:** in `SettingsView`, read `@Environment(\.appearsActive)` and call
    `listeningModel.refresh()` whenever it becomes `true`. Don't poll on a timer. Re-probe also
    calls `listeningModel.refresh()`, after the tool statuses.
  - **Poller app:** add the same `appearsActive` refresh to `ListeningPollerSettingsView`.
    `appearsActive` is available on macOS 15, so the floor doesn't move.
- **Full poll errors.**
  - Add `ListeningErrorDescription.describe(_ error: Error) -> String` to
    `VinylFeverListening`. It returns the `localizedDescription`, then `[<domain> <code>]`, then
    the `NSFilePath` or `NSURL` if there is one. It follows `NSUnderlyingErrorKey` up to 3 levels
    deep, each level written as `underlying: [<domain> <code>] <description>`.
  - Use it in three places, all at `.public` privacy:
    - in `ListeningPoller.pollOnce`'s catch, for `writeLastPollError`;
    - in both mains' `could not write to iCloud` log lines;
    - in the `error` field of a `failed` fetch line, for the diff and fetch failures that write
      one.

    The file path is the user's own Listening folder, so logging it is fine.
  - Settings already shows the last poll error. Show it as is.

## DoD

- **`ListeningErrorDescription` tests (pure):** a `CocoaError(.fileWriteUnknown)` carrying a
  file path and an underlying `POSIXError(.EPERM)` gives a description that contains:
  - the localized text;
  - `NSCocoaErrorDomain 512`;
  - the path;
  - `NSPOSIXErrorDomain 1`.

  A plain Swift error gives just its description.
- **A `ListeningPollerTests` test:** a store whose `appendFetch` throws that error leaves a
  last-poll error containing `NSCocoaErrorDomain 512` and the path.
- **A Vinyl Fever model test:** `refresh()` after the lease changes to another Mac turns
  `leaseLabel` into "<host> holds the lease" and `canPollNow` false. The view wiring is checked
  on device.
- Listening and Core suites pass, with and without `VF_PERF_TESTS=1`. The macOS app tests pass,
  and `VF Listening Poller` builds.
- **Device check (Jon):**
  1. Open Vinyl Fever's Settings on the laptop, then take over on the mini.
  2. Click back into the laptop's Settings. Within a moment, without relaunching, it shows the
     mini holding the lease, and Poll now is gone.
  3. Re-probe does the same.
  4. Do the same with the poller app's window on the mini after the laptop takes over.
