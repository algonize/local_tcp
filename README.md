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

## ⚡ Quick Start

There are two supported ways to talk to the bridge:

- **JavaScript / any web framework** (React, Vue, Angular, plain JS) — post messages to the page `window`; the extension's content script relays them to the printer. No SDK required.
- **Flutter** (web **and** mobile/desktop) — use the official package, which auto-detects the platform and routes through this extension on web.

> In all cases the end user must have the extension installed and the bridge **Linked** (see [Installation](#-installation)). Always check availability first with `CHECK_BRIDGE`.

---

## 🟨 Using it in a JavaScript / Web project

The extension injects a content script into **every page**, which bridges `window.postMessage` ⇄ the native host. You send a request tagged with a unique `messageId` and listen for the correlated response — no imports, no globals to load.

### 1. Drop-in client

```js
// localtcp.js — a tiny promise-based client for the Local TCP bridge.
export class LocalTcp {
  constructor({ timeoutMs = 30000 } = {}) {
    this._timeout = timeoutMs;
    this._pending = new Map();
    window.addEventListener('message', (e) => {
      const d = e.data;
      if (!d || d.source !== 'localtcp_res') return;
      const p = this._pending.get(d.messageId);
      if (!p) return;
      clearTimeout(p.timer);
      this._pending.delete(d.messageId);
      p.resolve(d.response || { success: false, error: 'Empty response' });
    });
  }

  _send(message) {
    return new Promise((resolve) => {
      const messageId =
        (crypto.randomUUID && crypto.randomUUID()) || `${Date.now()}-${Math.random()}`;
      const timer = setTimeout(() => {
        this._pending.delete(messageId);
        resolve({ success: false, error: 'Bridge timeout — is the extension installed & linked?' });
      }, this._timeout);
      this._pending.set(messageId, { resolve, timer });
      window.postMessage({ source: 'localtcp_req', messageId, ...message }, '*');
    });
  }

  /** Is the extension installed AND the native host linked? → {success, connected, version} */
  checkBridge()              { return this._send({ action: 'CHECK_BRIDGE' }); }
  connect(host, port = 9100) { return this._send({ action: 'CONNECT', host, port }); }
  /** Send raw ESC/POS bytes (Array<number>). */
  print(host, port, bytes)   { return this._send({ action: 'PRINT', host, port, data: bytes }); }
  disconnect(host, port)     { return this._send({ action: 'DISCONNECT', host, port }); }
}
```

### 2. Print a receipt

Generate ESC/POS bytes with any encoder (e.g. [`esc-pos-encoder`](https://www.npmjs.com/package/esc-pos-encoder)), then send them:

```js
import EscPosEncoder from 'esc-pos-encoder';
import { LocalTcp } from './localtcp.js';

const printer = new LocalTcp();

// 1. Make sure the bridge is ready
const bridge = await printer.checkBridge();
if (!bridge.connected) {
  alert('Please install the Local TCP extension and run the one-click installer.');
  // window.open('https://chromewebstore.google.com/detail/local-tcp/ngbakchodnmhndnghhejmocfadjfekkf');
  return;
}

// 2. Build the receipt
const data = new EscPosEncoder()
  .initialize()
  .align('center').bold(true).line('ALGORAMMING CAFE').bold(false)
  .align('left')
  .line('1x Espresso         $3.00')
  .line('1x Croissant        $2.50')
  .newline().line('TOTAL               $5.50')
  .newline().newline().cut()
  .encode(); // → Uint8Array

// 3. Print — pass a PLAIN Array, then close the socket
const res = await printer.print('192.168.1.50', 9100, Array.from(data));
if (!res.success) console.error('Print failed:', res.error);
await printer.disconnect('192.168.1.50', 9100);
```

> ⚠️ **Always pass a plain `Array<number>`** (`Array.from(uint8array)`). A raw `Uint8Array` does not survive the extension's JSON message hop and arrives malformed.

### 3. Read a status reply (optional)

For ESC/POS status queries (e.g. `DLE EOT`), set `readTimeoutMs`; the response's `data` holds the bytes the printer returned:

```js
const res = await printer._send({
  action: 'PRINT', host: '192.168.1.50', port: 9100,
  data: [0x10, 0x04, 0x01], readTimeoutMs: 1500,
});
console.log('Printer replied:', res.data); // e.g. [22]
```

---

## 🐦 Using it in a Flutter project

Use the official package — one type-safe API for **mobile, desktop, and web**. On web it automatically routes through this extension; on mobile/desktop it opens a direct TCP socket. **Your code is identical on every platform.**

**Pub.dev:** [`flutter_esc_pos_network_universal`](https://pub.dev/packages/flutter_esc_pos_network_universal)

### 1. Add the dependency

```yaml
dependencies:
  flutter_esc_pos_network_universal: ^1.1.0
```

### 2. Print raw ESC/POS bytes

```dart
import 'package:flutter/material.dart';
import 'package:flutter_esc_pos_network_universal/flutter_esc_pos_network_universal.dart';

Future<void> printReceipt() async {
  final printer = PrinterNetworkManager(
    '192.168.1.50',
    port: 9100,
    paperSize: ThermalPosPrinterPageSize.size80mm,
    // On web, give the bridge time to wake a sleeping Wi-Fi printer.
    timeout: const Duration(seconds: 30),
  );

  final profile = await CapabilityProfile.load();
  final g = Generator(PaperSize.mm80, profile);
  final bytes = <int>[
    ...g.text('ALGORAMMING CAFE',
        styles: const PosStyles(align: PosAlign.center, bold: true)),
    ...g.text('Espresso .......... \$3.00'),
    ...g.feed(2),
    ...g.cut(),
  ];

  final result = await printer.printTicket(bytes); // connect → print → disconnect
  if (result != PosPrintResult.success) debugPrint(result.msg);

  printer.dispose(); // closes the socket (IO) / removes the bridge listener (web)
}
```

### 3. Print any Flutter widget as a receipt

```dart
await printer.printWidget(context, child: const MyReceiptWidget());
```

The widget is rendered to a bitmap and sent as a single ESC/POS raster image — perfect for logos, QR codes, and rich layouts.

### 4. Detect the bridge on web (recommended)

On web the user needs this extension installed and linked. Ping it before printing — a full Riverpod example lives in [`example/lib/provider/local_tcp_extension_provider.dart`](https://github.com/algonize/flutter_esc_pos_network_universal/blob/main/example/lib/provider/local_tcp_extension_provider.dart). The gist is a `CHECK_BRIDGE` round-trip that returns `{ success: true, connected: true, version: '...' }`.

### Platform notes

| Platform | Transport | Extension needed? |
|---|---|---|
| Android / iOS / Windows / macOS / Linux | Direct TCP socket | No |
| **Web** | This Local TCP extension | **Yes** |

- Always call `printer.dispose()` when finished (especially on web — it removes the message listener).
- 58mm & 80mm map 1:1; **72mm** renders at 512 px and prints via the 80mm profile.
- On web, image processing runs on the main thread; for very large receipts prefer `printTicket` with pre-built bytes over `printWidget`.

---

## 📨 Message Protocol Reference (advanced)

For any other client, this is the full contract. Post to `window` with `source: "localtcp_req"` and a unique `messageId`; the response returns on a `window` `message` event with `source: "localtcp_res"` and the **same** `messageId`.

**Request**

| Field | Type | Notes |
|---|---|---|
| `source` | string | must be `"localtcp_req"` |
| `messageId` | string | your unique id; echoed back for correlation |
| `action` | string | `CHECK_BRIDGE` · `CONNECT` · `PRINT` · `SEND` · `DISCONNECT` · `PING` |
| `host` | string | printer IP on the LAN |
| `port` | number \| string | default `9100` |
| `data` | number[] | ESC/POS bytes (0–255) for `PRINT`/`SEND` — **plain array** |
| `readTimeoutMs` | number | optional; wait this long for a device reply, returned in `data` |

> A high-level alias is also accepted: `{ type: "LOCAL_TCP_PRINT", payload: { host, port, bytes, readTimeoutMs } }` — `bytes` maps to `data`.

**Response** (the `response` field of the `localtcp_res` message)

| Field | Type | Notes |
|---|---|---|
| `success` | bool | overall result |
| `connected` | bool | (`CHECK_BRIDGE`) host installed & reachable |
| `version` | string | (`PING` / `CHECK_BRIDGE`) installed host version |
| `bytesSent` | number | (`PRINT` / `SEND`) |
| `data` | number[] | bytes read back when `readTimeoutMs` was set |
| `error` | string | present on failure |

Concurrent jobs to the same printer are serialized by the native host, so byte streams never interleave.

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
