# 🛰️ Local TCP Bridge (Native Edition)

**Your browser can finally talk with local TCP.**

Local TCP is a powerful Chrome Extension that bridges the gap between Web Applications and physical ESC/POS hardware using a **Native Messaging Bridge**.

---

## 🏗️ Architecture

1.  **Extension**: Manages UI and bridges web page messages.
2.  **Native Host**: A lightweight Node.js script (`host/index.js`) that handles raw TCP sockets.
3.  **Client**: Your Flutter Web app or any site using the protocol.

---

## 🚀 Installation & Setup

1.  **One-Click Registration**:
    - **Mac**: Double-click `install_setup_mac.command`
    - **Windows**: Run `install_setup_windows.bat` (As Admin)
    - **Linux**: Run `install_setup_linux.sh`
2.  **Zero Configuration**: 
    - The Extension ID is now locked via a permanent key in `manifest.json`.
    - The setup scripts automatically register the bridge.
3.  **Restart Chrome** (Critical).

---

## 🗑️ Uninstallation

Should you need to remove the hardware bridge, each directory contains an uninstaller:
- **Mac**: `uninstall_setup_mac.command`
- **Windows**: `uninstall_setup_windows.bat`
- **Linux**: `uninstall_setup_linux.sh`

---

## 📡 Message Protocol (Developer API)

### Request Format
Send a `window.postMessage` with `source: 'localtcp_req'`.

```javascript
window.postMessage({
  source: 'localtcp_req',
  messageId: 'unique-uuid',
  action: 'PRINT', // PING, CONNECT, PRINT, SEND, DISCONNECT
  data: [27, 64, 10, ...] // Byte array
}, '*');
```

### 💙 Using with Flutter Web

To connect your Flutter Web app to the bridge, use the `dart:html` library (or `package:web` in newer versions) to send the print data:

```dart
import 'dart:html' as html;

void printToAlgonize(List<int> bytes) {
  // Use window.postMessage to talk to the extension
  html.window.postMessage({
    'source': 'localtcp_req',
    'messageId': DateTime.now().millisecondsSinceEpoch.toString(),
    'action': 'PRINT',
    'data': bytes,
  }, '*');
}
```

---

## 🛡️ Security & Fallback
- **Persistence**: Extension saves the last used Host/Port in `chrome.storage.local`.
- **Fallback**: If an API call omits host/port, the extension uses the saved config.

---

## 📄 License
MIT License - Algonize 2025.
