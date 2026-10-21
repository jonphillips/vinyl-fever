# Setting up a Mac

What a new Mac needs to build Vinyl Fever, serve chat (MCP), or poll listening history. The
detailed pages ([MCP setup](../chatgpt/MCP-SETUP.md), [poller setup](../listening/POLLER-SETUP.md),
jon-platform's [MCP access guide](../../../jon-platform/docs/ios/mcp-access.md)) stay the
reference. This page is the order to do things in and the steps those pages assume.

## Roles

One Mac can do several of these jobs. Today the laptop does the first two, and the Mac mini polls.

| Role | What it runs | Needs to be |
| --- | --- | --- |
| **Build Mac** | Xcode, the checkouts, builds every `.app` | Apple silicon, macOS 27, Xcode 27 |
| **Chat host** | `VinylFever.app`, `tunnel-client` → `vf-mcp` | Awake whenever ChatGPT should reach the library |
| **Polling Mac** | Hourly listening poll into iCloud Drive | Always on, always logged in |

The library snapshot `vf-mcp` reads is written locally on the Mac that runs Vinyl Fever
(`~/Library/Application Support/VinylFever/LibrarySnapshot/`). It doesn't sync. So the chat host
must be a Mac where Vinyl Fever runs and has built a snapshot.

## Every Mac

1. Sign in with Jon's Apple ID. Turn on **Apple Music** (Music → Settings → General → Sync
   Library) and **iCloud Drive**.
2. In System Settings → Apple Account → iCloud → Drive, turn **Optimize Mac Storage off** so
   iCloud never offloads the listening log.
3. Turn on **iCloud Keychain**. It carries the Claude API key the Setlist Normalizer uses
   (LLMClientKit stores it as a synchronizable item).
4. **Register the Mac for development signing.** Both apps are signed by hand with development
   profiles that list devices. A Mac that isn't in the profile won't launch the app. See
   [Signing](#signing-adding-a-mac-to-the-profiles).

## Build Mac

1. Install Xcode 27 and open it once to accept the license and install components.
2. Install the tools from Homebrew:

   ```bash
   brew install xcodegen ffmpeg flac
   ```

   `ffmpeg`, `ffprobe`, and `metaflac` are called by the live-show import and metadata flows.
   Vinyl Fever looks for them in `/opt/homebrew/bin` and `/usr/local/bin`.
3. Check out both repos as siblings under `~/code`. The project depends on
   `../jon-platform/packages/LLMClientKit`, and the scripts call
   `~/code/jon-platform/scripts/quiet-run`.

   ```bash
   git clone https://github.com/jonphillips/jon-platform ~/code/jon-platform
   git clone https://github.com/jonphillips/vinyl-fever ~/code/vinyl-fever
   ```

4. In Xcode → Settings → Accounts, sign in to the developer account (team `7MQEE539G9`) and
   create an **Apple Development** certificate for this Mac if there isn't one. The private key
   lives only on the Mac that made it.
5. Download and open **Vinyl Fever Dev Profile** and **VF Listening Poller Dev Profile** from the
   developer portal. Opening the file installs it into
   `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`.
6. Generate the project and run the tests ([verification](../verification.md)):

   ```bash
   cd ~/code/vinyl-fever
   xcodegen generate
   ```

7. Build the `VinylFever` scheme and copy `VinylFever.app` from the build products to
   `/Applications`. The tunnel profile, Login Items, and the MCP client configs all use that
   path.
8. For the legacy scripts only, run the Python setup in [scripts/README.md](../../scripts/README.md).

**First launch.** Open Vinyl Fever and:

- check **Settings**: every audio tool resolves, and the Claude key shows a masked preview (if it
  doesn't, enter it there);
- open **Playlists** and allow Vinyl Fever to control Music when asked. That builds the library
  snapshot. Settings → Chat Access (MCP) then shows its track count and age;
- authorize Apple Music when asked. Catalog matching needs it.

## Chat host

The tunnel and the ChatGPT plugin belong to the account, so they survive a machine change. The
key, the `tunnel-client` profile, and the login agent are per Mac.

| What | Where it lives | Moves with the account? |
| --- | --- | --- |
| Tunnel `tunnel_6ad14536fd9881918f7df150f0ab8366` | platform.openai.com → Organization → Tunnels | Yes |
| ChatGPT plugin **Vinyl Fever** | ChatGPT → Plugins (personal) | Yes |
| Runtime API key | Login Keychain, service `openai-tunnel-runtime` | No: store it again |
| `tunnel-client` profile | `~/.config/tunnel-client/vinyl-fever.yaml` | No: `init` again |
| Login agent | `~/Library/LaunchAgents/com.jonphillips.mcp-tunnel.vinyl-fever.plist` | No: install again |

The tunnel ID isn't a secret. It was created for the 2026-10-15 hello-world proof and then reused
for Vinyl Fever, so the Tunnels page may still call it something else.

1. Set up the Build Mac first, or copy a built `VinylFever.app` into `/Applications`. Then do
   the first launch above so a snapshot exists.
2. Install `tunnel-client` from OpenAI's tap (or download it from the Tunnels page):

   ```bash
   brew install openai/tools/tunnel-client
   ```
3. Store the runtime key. Copy it with the API keys page's copy button (or create a new
   **Restricted** key with only **Tunnels: Read + Use**). Then run this from the jon-platform
   checkout:

   ```bash
   scripts/mcp-tunnel store-key
   ```

   Don't use `security add-generic-password -w` at a prompt: it truncates at 128 characters
   and OpenAI keys are 164.
4. Create the profile and the login agent:

   ```bash
   scripts/mcp-tunnel init vinyl-fever tunnel_6ad14536fd9881918f7df150f0ab8366 "/Applications/VinylFever.app/Contents/Helpers/vf-mcp"
   scripts/mcp-tunnel install-agent vinyl-fever
   scripts/mcp-tunnel status vinyl-fever
   ```

   `status` should report `live`, `ready`, and the agent loaded. Use `--force` with `init` when a
   profile is already there.
5. Only one Mac should run the `vinyl-fever` agent. When moving the chat host, run
   `scripts/mcp-tunnel uninstall-agent vinyl-fever` on the old Mac.
6. Smoke test: in ChatGPT, ask `@Vinyl Fever` for a library overview. If tools changed since the
   plugin was added, use **Refresh** on the plugin's detail page.

For Claude Code and Codex, recreate `~/music-chat` from [MCP setup](../chatgpt/MCP-SETUP.md).
Settings → Chat Access (MCP) copies each client's configuration with the helper path filled in.

## Polling Mac (Apple silicon)

After [M13 S3](../milestones/M13-listening-history.md), Vinyl Fever polls by itself on any
Apple-silicon Mac. A new Mac mini needs Vinyl Fever, not the separate poller app.

1. Do [Every Mac](#every-mac). Add the mini to **Vinyl Fever Dev Profile**, then rebuild on the
   Build Mac.
2. Copy that `VinylFever.app` to `/Applications` on the mini.
3. Keep the mini on and logged in:
   - System Settings → Users & Groups → **Automatically log in as** Jon. FileVault blocks
     automatic login, so either leave FileVault off on the mini or log in by hand after every
     restart.
   - System Settings → Energy: turn on **Prevent automatic sleeping when the display is off**
     and **Start up automatically after a power failure**.
4. Open Music and confirm it's signed in (the Account menu shows the Apple ID).
5. Open Vinyl Fever and authorize Apple Music.
6. In **Settings → Listening History**, turn on **Poll listening on this Mac**. If another Mac
   holds the lease, confirm the takeover. If macOS asks, allow Vinyl Fever in System Settings →
   General → **Login Items**.
7. On any Mac, confirm a `baseline` record in iCloud Drive → Vinyl Fever → Listening →
   `fetches/<poller-id>/`. The next hourly fetches should be `none` or `plays`.
8. Turn off polling on the previous Mac. The lease already moved, so its runs write nothing, but
   turning it off unregisters its agent.

Until S3 ships, or for the Intel mini on macOS 15, polling uses the separate VF Listening Poller
app: see [poller setup](../listening/POLLER-SETUP.md).

**If the mini is also the chat host:** it needs a library snapshot of its own, which means
running Vinyl Fever there and opening Playlists once. The mini's Music library play counts come
from Sync Library and can differ from the laptop's. That trade-off is still open.

## Signing: adding a Mac to the profiles

Both apps sign manually: automatic signing picks the wildcard team profile, which has no
MusicKit, and every catalog call then fails with "Failed to request developer token" (see the
comment in `project.yml`).

1. On the new Mac, get its **Provisioning UDID** from System Information → Hardware.
2. In the developer portal → Devices, register it.
3. Edit **Vinyl Fever Dev Profile** (App ID `com.jonphillips.vinylfever`). For a Mac that runs the
   separate poller, also edit **VF Listening Poller Dev Profile**
   (`com.jonphillips.vinylfever.listeningpoller`). Add the device and save.
4. Download each profile again and **open the file** on the Build Mac. A downloaded profile isn't
   installed until it's opened.
5. Rebuild. The app embeds the profile, so a build made before the device was added won't launch
   on it.

## Moving to a replacement Mac

- **New laptop (Build Mac + chat host):** Every Mac, Build Mac, then Chat host. Uninstall the
  tunnel agent on the old laptop. The listening log is already in iCloud Drive. Everything else
  is local to the old Mac. To keep it, quit Vinyl Fever and copy across:
  - app state and settings (recipes, aliases, run logs):
    `~/Library/Application Support/VinylFever/VinylFever.sqlite`, with its `-wal` and `-shm`
    files;
  - inboxes and the snapshot: `~/Library/Application Support/VinylFever/`. The snapshot rebuilds
    on its own, so this is only for the inboxes.
- **New polling Mac:** Polling Mac, then turn off polling on the old one. A takeover starts a
  new stream with a `baseline`, so plays are never double-counted.
