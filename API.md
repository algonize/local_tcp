# 🛠️ Local TCP Developer API

Local TCP allows any web application to communicate with physical TCP devices (like ESC/POS printers) directly from the browser. 

Communication is handled via `window.postMessage`, bridged through a content script to the extension's background socket service.

---

## 📡 Message Protocol

### **Request Format**
All requests must be sent to the `window` object with the `source` set to `localtcp_req`.

```javascript
window.postMessage({
  source: 'localtcp_req',
  messageId: 'unique-uuid-string', // Used to match the response
  action: 'PRINT',                 // Supported: PING, CONNECT, PRINT, SEND, DISCONNECT
  host: '192.168.1.100',           // Optional (falls back to extension config)
  port: '9100',                    // Optional (falls back to extension config)
  data: [27, 64, 10, ...]          // Required for PRINT/SEND (Byte array)
}, '*');
```

### **Response Format**
Responses are sent back via `window.postMessage` with `source: 'localtcp_res'`.

```javascript
window.addEventListener('message', (event) => {
  if (event.data.source === 'localtcp_res' && event.data.messageId === 'your-uuid') {
     console.log('Got response:', event.data.response);
  }
});
```

---

## 🏗️ Actions

### `PING`
Check if the extension is installed and get current configuration.
- **Returns**: `success`, `version`, `config` (saved host/port).

### `CONNECT`
Explicitly open a TCP socket.
- **Parameters**: `host` (optional), `port` (optional).
- **Behavior**: If host/port are provided, they are saved as the new defaults in the extension.

### `PRINT` / `SEND`
Send raw bytes to the device.
- **Parameters**: `data` (Required byte array), `host` (optional), `port` (optional).
- **Behavior**: 
  - If the socket isn't open, it attempts to `CONNECT` first.
  - If `host` and `port` are missing in the request, it uses the extension's saved configuration.

### `DISCONNECT`
Close the active socket.

---

## 💡 Smart Fallback Logic

The extension maintains a persistent configuration in `chrome.storage.local`. 
1. If an API call contains `host` and `port`, those values are used and **saved** as the new defaults.
2. If an API call omits `host` or `port`, the extension uses the **previously saved** values.
3. This allows developers to configure the printer once in the extension UI and thereafter simply send data: `{ action: 'PRINT', data: [...] }`.

---

## 🛡️ Security Disclaimer
- The extension listens to `window.postMessage`. Ensure your application validates the origin if you are handling sensitive data.
- Standard TCP communication is unencrypted. Use within trusted local networks.
