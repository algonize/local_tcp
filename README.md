# 🛰️ Local TCP Bridge

**The missing link between Web Browsers and Local Hardware.**

Local TCP is a professional-grade Native Messaging Bridge that allows web applications to communicate directly with local TCP hardware (like ESC/POS thermal printers) using a secure, low-latency binary protocol.

---

## 🚀 Key Features

- **Zero-Config Setup**: Professional installer scripts for Mac, Windows, and Linux.
- **Enterprise Security**: Uses Chrome's Native Messaging sandbox for safe, isolated communication.
- **Binary Performance**: Handles raw ESC/POS byte streams with millisecond precision.
- **Platform Agnostic**: Works with Flutter Web, React, Vue, or any standard web framework.
- **Real-Time Monitoring**: Integrated dashboard for configuration and log tracking.

---

## 🏗️ Technical Architecture

Local TCP operates as a multi-layer relay:
1. **Web App**: Sends a `window.postMessage` to the Content Script.
2. **Content Script**: Forwards the message to the Extension Background.
3. **Background Script**: Relays the request to the **Native Messaging Host** (the Bridge).
4. **Native Host (Node.js)**: Opens a raw TCP socket to your hardware (e.g., `9100`).

---

## 📥 Installation

The extension provides a **Setup Kit** tailored to your operating system. Click **"Download Setup Kit"** in the extension popup and follow the instructions below:

### 🍎 MacOS (Professional Bash)
1. Open the **Terminal** app.
2. Type `bash ` (ensure there is a space after bash).
3. **Drag & Drop** the `install_setup_mac.sh` file into the terminal.
4. Press **Enter**. (Restart Chrome to activate).

### 🪟 Windows (Professional PowerShell)
1. Right-click `install_setup_windows.ps1`.
2. Select **"Run with PowerShell"**.
3. Confirm any security prompts. (Restart Chrome to activate).

### 🐧 Linux (Professional Shell)
1. Open your terminal in the bundle folder.
2. Run `bash install_setup_linux.sh`. (Restart Chrome to activate).

---

## 🧩 Developer API

Integrating Local TCP into your web application is trivial. The bridge listens for standard messages via the `window` object.

### Command Format
```json
{
  "type": "LOCAL_TCP_PRINT",
  "payload": {
    "host": "192.168.1.100",
    "port": 9100,
    "bytes": [27, 64, 10, ... ] // Raw ESC/POS byte array
  }
}
```

### Flutter Web Example
```dart
import 'dart:html' as html;

void printToHardware(String ip, int port, List<int> bytes) {
  html.window.postMessage({
    'type': 'LOCAL_TCP_PRINT',
    'payload': {
      'host': ip,
      'port': port,
      'bytes': bytes,
    }
  }, '*');
}
```

---

## 🗑️ Uninstallation

Cleaning up is just as easy:
- **Mac/Linux**: Run the `uninstall_setup_xxx.sh` script in your Terminal.
- **Windows**: Right-click `uninstall_setup_windows.ps1` and Run with PowerShell.

---

## ⚖️ License & Support

© 2026 **Algoramming**. All Rights Reserved.  
Distributed for professional hardware integration globally.
