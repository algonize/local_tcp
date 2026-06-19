# Local TCP — Native Host Installer (Rust)

A single, dependency-free binary that installs the **Node.js** native-messaging
host (`host/index.js`) and registers it with Chromium-family browsers.

## Why Node, not a compiled host

On **macOS 15/26**, *Local Network Privacy* keys LAN access to the executable's
code identity. When Chrome runs the host, the process is the system `node`
binary (macOS recognizes it → allowed to reach `192.168.x.x`). A bare custom
binary (e.g. the old Go host) is an unknown executable → **silently denied** →
TCP connects to the printer fail with `no route to host` even though `ping`
works. This installer wires Chrome to run `node index.js`, which sidesteps that.

## What it does

| OS | Host path the manifest points to | Registration |
|----|----------------------------------|--------------|
| macOS | `~/Library/Application Support/LocalTCP/index.js` (shebang → absolute node) | manifest JSON in each browser's `NativeMessagingHosts/` |
| Linux | `~/.local/lib/algoramming/localtcp/index.js` (shebang → absolute node) | manifest JSON in each browser's `NativeMessagingHosts/` |
| Windows | `%APPDATA%\Algoramming\LocalTCP\run_bridge.bat` (calls node) | `HKCU` registry keys |

Browsers covered: Chrome, Chrome Beta/Canary, Chromium, Microsoft Edge, Brave.

`index.js` and the manifest template are **embedded at compile time**, so the
installer is fully self-contained — no loose files to ship alongside it.

## Build

Native (the machine you're on):

```bash
./build.sh                 # → target/release/localtcp-installer
```

Per-OS binaries are best produced on their own OS (or via the CI matrix in
`.github/workflows/installer.yml`). Cross-builds from macOS are possible with a
cross linker (see comments in `build.sh`).

## Use

```bash
localtcp-installer            # install (default)
localtcp-installer install
localtcp-installer uninstall
```

Requires Node.js on the machine (the installer locates it; if missing it prints
a per-OS install hint). After install/uninstall, **restart the browser**.

## Verify

```bash
# bridge health (PING → version) without the extension:
printf '' # the extension's popup bridge-check is the easiest path
```

The extension popup's bridge status should report the `index.js` version
(`2.1.0`). A successful test print confirms the full path end-to-end.
