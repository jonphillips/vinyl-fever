# VF Listening Poller setup

## Build and install

On the laptop, from the Vinyl Fever checkout, run:

```sh
scripts/build-listening-poller
```

The script builds a universal app and prints its path. Copy that `.app` to
`/Applications` on the Intel Mac mini (for example, with AirDrop or a shared
folder). Keep the app in `/Applications` so Login Items can find it after updates.

## First launch

1. Open **VF Listening Poller** from `/Applications` on the mini.
2. Click **Authorize** and allow Apple Music access.
3. Turn on **Poll every hour on this Mac**.
4. If macOS asks for approval, click **Open Login Items** and allow VF Listening
   Poller in **System Settings → General → Login Items**.
5. Confirm that a `baseline` record appears on the laptop in iCloud Drive → Vinyl
   Fever → Listening → `fetches/<poller-id>/`.

Keep the mini logged in and awake. Turn off **Optimize Mac Storage** for iCloud
Drive so the listening folder stays available to the poller.

The poller does not prompt in the background. Its window shows authorization,
agent status, the latest fetch, today's play count, and whether this Mac holds the
lease. A write error appears in the window; headless write errors are recorded in
the system log and exit non-zero.
