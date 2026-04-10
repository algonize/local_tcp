// Local TCP - background.js
// Bridges web app messages to Native Messaging Host for raw TCP communication

const HOST_NAME = 'com.algoramming.localtcp';
let nativePort = null;

// ─── Native Port Management ──────────────────────────────────────────────────

function getNativePort() {
  if (!nativePort) {
    try {
      console.log('Connecting to native host...');
      nativePort = chrome.runtime.connectNative(HOST_NAME);
      
      nativePort.onMessage.addListener((msg) => {
        // Log basic success/error but avoid logging massive binary responses
        if (msg.error) console.error('Bridge Error:', msg.error);
      });

      nativePort.onDisconnect.addListener(() => {
        console.error('Native Host disconnected:', chrome.runtime.lastError?.message);
        nativePort = null;
      });
    } catch (e) {
      console.error('Failed to connect to native host:', e);
      nativePort = null;
    }
  }
  return nativePort;
}

// ─── Shared Message Handler ───────────────────────────────────────────────────

async function handleMessage(request, sender) {
  // 1. Handle the 'LOCAL_TCP_PRINT' wrapper used by external apps & the dashboard test button
  if (request.type === 'LOCAL_TCP_PRINT' && request.payload) {
    request = {
      action: 'PRINT',
      ...request.payload,
      data: request.payload.bytes // Map 'bytes' to the 'data' field expected by index.js
    };
  }

  let { action, host, port, data, connectionId } = request;

  // 2. Internal Action: Check if bridge is installed
  if (action === 'CHECK_BRIDGE') {
    return new Promise((resolve) => {
      try {
        const p = chrome.runtime.connectNative(HOST_NAME);
        p.onMessage.addListener((res) => {
          resolve({ success: true, connected: true });
          p.disconnect();
        });
        p.onDisconnect.addListener(() => {
          resolve({ success: false, connected: false, error: chrome.runtime.lastError?.message });
        });
        // Send a ping to the host
        p.postMessage({ action: 'PING' });
      } catch (e) {
        resolve({ success: false, connected: false, error: e.message });
      }
    });
  }

  // Retrieve stored settings for fallback
  const stored = await chrome.storage.local.get(['printerHost', 'printerPort']);
  
  // Resolve Host and Port
  if (host && port) {
    await chrome.storage.local.set({ printerHost: host, printerPort: port });
  } else {
    host = host || stored.printerHost;
    port = port || stored.printerPort;
  }

  // Basic validation
  if (['CONNECT', 'PRINT', 'SEND', 'DISCONNECT'].includes(action)) {
    if (!host || !port) {
      return { success: false, error: 'Host/Port not configured.' };
    }
  }

  // Relay to Native Host and wait for response
  return new Promise((resolve) => {
    try {
      const p = getNativePort();
      if (!p) return resolve({ success: false, error: 'Bridge not available. Please install the native host.' });

      const onMessage = (res) => {
        p.onMessage.removeListener(onMessage);
        resolve(res);
      };
      
      p.onMessage.addListener(onMessage);
      
      p.postMessage({
        action,
        host,
        port: parseInt(port),
        data,
        connectionId: connectionId || `${host}:${port}`
      });
      
    } catch (err) {
      resolve({ success: false, error: 'Bridge communication failure: ' + err.message });
    }
  });
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
