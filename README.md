# 🛰️ Local TCP Bridge

**The missing link between Web Browsers and Local Hardware.**

Local TCP is a Native Messaging Bridge that allows web applications to communicate directly with local TCP hardware (like ESC/POS thermal printers) using a secure, low-latency binary protocol.

---

## 🚀 Key Features

- **One-Click Setup**: Native installers for Mac (.pkg), Windows (.exe), and Linux (.run). **No terminal. No Node.js. No dependencies.**
- **Zero Dependencies**: The bridge is a single ~2.5MB static binary written in Go.
- **Enterprise Security**: Chrome Native Messaging sandbox + configurable **origin allowlist** — lock the bridge down to only your web apps.
- **Binary Performance**: Handles raw ESC/POS byte streams with millisecond precision and safe concurrent request correlation.
- **Platform Agnostic**: Works with Flutter Web, React, Vue, or any standard web framework. Registers with Chrome, Edge, Chromium, and Brave.

---

## 🏗️ Technical Architecture

Local TCP operates as a multi-layer relay:

1. **Web App**: Sends a `window.postMessage` to the Content Script.
2. **Content Script**: Forwards the message to the Extension Background.
3. **Background Script**: Checks the origin allowlist, then relays the request (tagged with a `reqId`) to the **Native Messaging Host**.
4. **Native Host (Go binary)**: Opens a raw TCP socket to your hardware (e.g., port `9100`) and echoes the `reqId` back so concurrent jobs never cross wires.

---

## 📥 Installation

1. Add the extension to Chrome.
2. Open the extension popup → click **Download One-Click Installer** (it auto-detects your OS).
3. Run the installer:
   - 🍎 **macOS**: double-click `localtcp-mac-installer.pkg` → Continue → Install. (macOS prompts for your password — the bridge installs system-wide under `/Library`.)
   - 🪟 **Windows**: double-click `localtcp-windows-installer.exe` → Install. (No admin rights needed — installs per-user.)
   - 🐧 **Linux**: `chmod +x localtcp-linux-installer.run && ./localtcp-linux-installer.run`
4. **Restart Chrome** completely. The popup will show **Bridge Linked**. Done.

That's the entire process — no shell scripts, no copying files, no Node.js.

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

```bash
# 1. Build the native host for all platforms (requires Go 1.21+)
cd host-go && bash build.sh

# 2. Build installers
cd installers/linux && bash build_run.sh        # any OS
cd installers/mac   && bash build_pkg.sh        # on macOS
# Windows: compile installers/windows/installer.iss with Inno Setup 6
```

Or just **push to `main`** — the GitHub Actions workflow builds all three installers and publishes them to a GitHub Release automatically, tagged from the `version` field in `manifest.json`. To cut a new version, bump `manifest.json` `version` (e.g. `2.0.1`) and push; re-pushing the same version refreshes the existing release's files. The extension popup always downloads from `releases/latest`, so users get the newest build without any link changes.

---

## 🗑️ Uninstallation

Just as easy as installing — one double-click:

- 🪟 **Windows**: Start Menu → **Uninstall Local TCP Bridge** (or Settings → Apps → Uninstall).
- 🍎 **macOS**: open **Applications** → double-click **Uninstall Local TCP** → enter your password → Done.
- 🐧 **Linux**: run `localtcp-linux-uninstaller.run` (from GitHub Releases) the same way you ran the installer, or `bash ~/.local/lib/localtcp/uninstall.sh`.



---

## ⚖️ License & Support

© 2026 **Algoramming**. MIT License.
Distributed for professional hardware integration globally.
