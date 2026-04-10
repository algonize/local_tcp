# 🛰️ Local TCP Bridge

**Your browser can finally talk with local TCP.**

Local TCP is a powerful Chrome Extension that bridges the gap between modern Web Applications and local network devices. It allows web apps (like Flutter Web, React, or Vue) to communicate with TCP-based hardware—primarily ESC/POS thermal printers—without requiring a complex backend or local server relay.

---

## ✨ Features

- **Direct TCP Sockets**: Leverages native browser socket APIs to connect to any IP/Port.
- **Persistent Configuration**: Save your printer IP/Port once; send data-only requests thereafter.
- **Smart API**: Automatically saves configuration when provided via API calls.
- **Premium UI**: Clean, modern interface designed for developers and power users.
- **Platform Agnostic**: Works with any website that can send `window.postMessage`.

---

## 🚀 Installation

1.  Clone this repository.
2.  Open Chrome and navigate to `chrome://extensions`.
3.  Enable **Developer Mode** (top right).
4.  Click **Load Unpacked** and select the `local_tcp` folder.
5.  Click the extension icon to configure your default Host and Port.

---

## 💻 Integration

Integrating Local TCP into your project is as simple as sending a JavaScript message:

```javascript
window.postMessage({
  source: 'localtcp_req',
  action: 'PRINT',
  data: [27, 64, 72, 101, 108, 108, 111, 10, 29, 86, 65, 0] // ESC/POS bytes
}, '*');
```

For full API details, see [API.md](./API.md).

---

## 🎨 Branding

- **Name**: Local TCP
- **Primary Color**: `#5dc095`
- **Tagline**: Your browser can finally talk with local TCP.

---

## 🛠️ Tech Stack

- **Manifest V3**: Using modern service worker architecture.
- **Chrome Sockets API**: Low-level TCP management.
- **Vanilla JS & CSS**: Fast, lightweight, and zero-dependency UI.

---

## 📄 License

MIT License - feel free to use and distribute.
