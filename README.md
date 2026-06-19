# 🛰️ Local TCP Bridge

**The missing link between Web Browsers and Local Hardware.**

Local TCP is a Native Messaging Bridge that allows web applications to communicate directly with local TCP hardware (like ESC/POS thermal printers) using a secure, low-latency binary protocol.

---

## 🚀 Key Features

- **One-Click Setup**: Native installers for Mac (.pkg), Windows (.exe), and Linux (.run). **No terminal needed** — the installer registers everything and auto-installs Node.js if it isn't already present.
- **Lightweight Host**: The bridge is a small Node.js script. Running through the system `node` is also what keeps it working under macOS 15/26 Local Network Privacy, where an unsigned standalone binary gets silently blocked from the LAN.
- **Enterprise Security**: Chrome Native Messaging sandbox + configurable **origin allowlist** — lock the bridge down to only your web apps.
- **Binary Performance**: Handles raw ESC/POS byte streams with millisecond precision and safe concurrent request correlation.
- **Platform Agnostic**: Works with Flutter Web, React, Vue, or any standard web framework. Registers with Chrome, Edge, Chromium, and Brave.

---

## 🏗️ Technical Architecture

Local TCP operates as a multi-layer relay:

1. **Web App**: Sends a `window.postMessage` to the Content Script.
2. **Content Script**: Forwards the message to the Extension Background.
3. **Background Script**: Checks the origin allowlist, then relays the request (tagged with a `reqId`) to the **Native Messaging Host**.
4. **Native Host (Node.js)**: Opens a raw TCP socket to your hardware (e.g., port `9100`) and echoes the `reqId` back so concurrent jobs never cross wires.

---

## 📥 Installation

1. Add the extension to Chrome.
2. Open the extension popup → click **Download One-Click Installer** (it auto-detects your OS).
3. Run the installer:
   - 🍎 **macOS**: double-click `localtcp-mac-installer.pkg` → Continue → Install. (macOS prompts for your password to complete setup; the host is installed for your user account.)
   - 🪟 **Windows**: double-click `localtcp-windows-installer.exe` → Install. (No admin rights needed — installs per-user.)
   - 🐧 **Linux**: `chmod +x localtcp-linux-installer.run && ./localtcp-linux-installer.run`
4. **Restart Chrome** completely. The popup will show **Bridge Linked**. Done.

That's the entire process — no copying files by hand. (The installer needs Node.js; if it's missing it installs it for you via your system package manager.)

---

## 🔒 Security: Origin Allowlist

By default the bridge accepts requests from any website (open mode). For production POS deployments, open the extension popup → **Security — Allowed Origins** and list your app origins (one per line):

```
https://pos.algoramming.com
http://localhost:3000
```

Requests from any other website are rejected before they ever reach your network.

---

## 🧩 Developer API

The bridge listens for standard messages via the `window` object.

### Command Format

```json
{
  "source": "localtcp_req",
  "messageId": "unique-id-123",
  "type": "LOCAL_TCP_PRINT",
  "payload": {
    "host": "192.168.1.100",
    "port": 9100,
    "bytes": [27, 64, 10],
    "readTimeoutMs": 1500
  }
}
```

`readTimeoutMs` is optional. When set, the bridge waits up to that many milliseconds
for the device to reply (e.g. an ESC/POS `DLE EOT` status query) and returns the bytes
in `response.data` (an array of integers). Omit it for fire-and-forget print jobs.

The response arrives as a `message` event with `source: "localtcp_res"` and a matching
`messageId`. Concurrent jobs to the same printer are serialized by the native host, so
their byte streams never interleave.

---

## 📦 Flutter Integration

We recommend the dedicated Flutter package for a high-level, type-safe experience.

**Pub.dev**: [flutter_esc_pos_network_universal](https://pub.dev/packages/flutter_esc_pos_network_universal)

```dart
import 'dart:html' as html;

void printToHardware(String ip, int port, List<int> bytes) {
  html.window.postMessage({
    'source': 'localtcp_req',
    'messageId': DateTime.now().microsecondsSinceEpoch.toString(),
    'type': 'LOCAL_TCP_PRINT',
    'payload': {'host': ip, 'port': port, 'bytes': bytes}
  }, '*');
}
```

---

## 🛠️ Building From Source

The native host is `host/index.js` (Node.js) — no build step. The cross-platform
installer that registers it lives in `installers/rust/`:

```bash
# Build the installer for the machine you're on (requires Rust)
cd installers/rust && cargo build --release
# → target/release/localtcp-installer        (run with: install | uninstall)
```

For local development you can also register the host directly with the scripts
in `host/` (e.g. `bash host/install_setup_mac.sh`) — no Rust needed.

Or just **push to `main`** — the GitHub Actions workflow builds all three installers and publishes them to a GitHub Release automatically, tagged from the `version` field in `manifest.json`. To cut a new version, bump `manifest.json` `version` (e.g. `2.0.1`) and push; re-pushing the same version refreshes the existing release's files. The extension popup always downloads from `releases/latest`, so users get the newest build without any link changes.

---

## 🗑️ Uninstallation

Just as easy as installing. In the extension popup click **Uninstall Setup Kit** — it downloads the uninstaller for your OS — then run it:

- 🪟 **Windows**: run `localtcp-windows-uninstaller.exe` (or Start Menu → **Uninstall Local TCP Bridge** / Settings → Apps → Uninstall).
- 🍎 **macOS**: double-click `localtcp-mac-uninstaller.pkg` → Continue → Install → enter your password → Done.
- 🐧 **Linux**: run `localtcp-linux-uninstaller.run` the same way you ran the installer.



---

## ⚖️ License & Support

© 2026 **Algoramming**. MIT License.
Distributed for professional hardware integration globally.
