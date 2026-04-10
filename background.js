// Local TCP - background.js
// Core TCP bridge service worker with persistent storage fallback
// Primary Color: #5dc095

const connections = {}; // connectionId -> socketId

// ─── Shared Message Handler ───────────────────────────────────────────────────
async function handleMessage(request, sender) {
  let { action, host, port, data, connectionId } = request;

  // Retrieve stored settings for fallback
  const stored = await chrome.storage.local.get(['printerHost', 'printerPort']);
  const storedHost = stored.printerHost;
  const storedPort = stored.printerPort;

  // 1. Resolve Host and Port
  if (host && port) {
    // If both are provided, update storage (Auto-Save)
    await chrome.storage.local.set({ printerHost: host, printerPort: port });
  } else {
    // Fallback to stored values if missing in API call
    host = host || storedHost;
    port = port || storedPort;
  }

  // 2. Validate prerequisites for network actions
  if (['CONNECT', 'PRINT', 'SEND', 'DISCONNECT'].includes(action)) {
    if (!host || !port) {
      return { 
        success: false, 
        error: 'Printer Host and Port are not configured. Please set them in the extension or provide them in the API call.' 
      };
    }
  }

  switch (action) {
    // ── PING: Maintenance & Health Check ──────────────────────────────────────
    case 'PING': {
      return {
        success: true,
        name: 'Local TCP',
        tagline: 'Your browser can finally talk with local TCP.',
        version: chrome.runtime.getManifest().version,
        config: { host, port }
      };
    }

    // ── CONNECT: Open socket ──────────────────────────────────────────────────
    case 'CONNECT': {
      const id = connectionId || `${host}:${port}`;
      if (connections[id]) {
        await new Promise((resolve) => {
          chrome.sockets.tcp.disconnect(connections[id], () => {
            chrome.sockets.tcp.close(connections[id], resolve);
          });
        });
        delete connections[id];
      }

      return new Promise((resolve) => {
        chrome.sockets.tcp.create({}, (createInfo) => {
          if (chrome.runtime.lastError) return resolve({ success: false, error: chrome.runtime.lastError.message });
          const socketId = createInfo.socketId;

          chrome.sockets.tcp.connect(socketId, host, parseInt(port), (result) => {
            if (result < 0) {
              chrome.sockets.tcp.close(socketId);
              resolve({ success: false, error: `Connection failed to ${host}:${port} (Code: ${result})` });
            } else {
              connections[id] = socketId;
              resolve({ success: true, connectionId: id, message: `Connected to ${host}:${port}` });
            }
          });
        });
      });
    }

    // ── SEND/PRINT: Stream Bytes ──────────────────────────────────────────────
    case 'PRINT':
    case 'SEND': {
      const id = connectionId || `${host}:${port}`;
      let socketId = connections[id];

      // Auto-connect if not connected
      if (!socketId) {
        const connectRes = await handleMessage({ action: 'CONNECT', host, port, connectionId: id });
        if (!connectRes.success) return connectRes;
        socketId = connections[id];
      }

      if (!data || !Array.isArray(data)) {
        return { success: false, error: 'Invalid data format: Expected byte array [int, int, ...]' };
      }

      const buffer = new Uint8Array(data).buffer;
      return new Promise((resolve) => {
        chrome.sockets.tcp.send(socketId, buffer, (sendInfo) => {
          if (chrome.runtime.lastError || sendInfo.resultCode < 0) {
            const err = chrome.runtime.lastError?.message || `Transmission failed (Code: ${sendInfo?.resultCode})`;
            resolve({ success: false, error: err });
          } else {
            resolve({ success: true, bytesSent: sendInfo.bytesSent });
          }
        });
      });
    }

    // ── DISCONNECT: Cleanup ───────────────────────────────────────────────────
    case 'DISCONNECT': {
      const id = connectionId || `${host}:${port}`;
      const socketId = connections[id];
      if (socketId) {
        return new Promise((resolve) => {
          chrome.sockets.tcp.disconnect(socketId, () => {
            chrome.sockets.tcp.close(socketId, () => {
              delete connections[id];
              resolve({ success: true, message: `Disconnected from ${id}` });
            });
          });
        });
      }
      return { success: true, message: 'No active connection found.' };
    }

    default:
      return { success: false, error: `Unsupported action: ${action}` };
  }
}

// ─── Listeners ───────────────────────────────────────────────────────────────
const messageListener = (request, sender, sendResponse) => {
  handleMessage(request, sender)
    .then(sendResponse)
    .catch((err) => sendResponse({ success: false, error: err.message || 'Internal logic error' }));
  return true; 
};

chrome.runtime.onMessageExternal.addListener(messageListener);
chrome.runtime.onMessage.addListener(messageListener);

chrome.runtime.onSuspend?.addListener(() => {
  Object.values(connections).forEach(socketId => {
    chrome.sockets.tcp.disconnect(socketId, () => chrome.sockets.tcp.close(socketId));
  });
});
