// Local TCP - background.js
// Bridges web app messages to the Native Messaging Host for raw TCP communication.
//
// Design:
//  - Request/response correlation via `reqId` (safe under concurrent print jobs)
//  - Origin allowlist: only approved web origins may use the bridge
//  - Per-request timeout so callers never hang forever
//  - Single persistent native port with one dispatcher listener

const HOST_NAME = 'com.algoramming.localtcp';
const REQUEST_TIMEOUT_MS = 15000;

let nativePort = null;
let reqCounter = 0;
const pending = new Map(); // reqId -> { resolve, timer }

// ─── Native Port Management ──────────────────────────────────────────────────

function getNativePort() {
  if (nativePort) return nativePort;
  try {
    nativePort = chrome.runtime.connectNative(HOST_NAME);

    nativePort.onMessage.addListener((msg) => {
      if (msg && msg.reqId && pending.has(msg.reqId)) {
        const { resolve, timer } = pending.get(msg.reqId);
        clearTimeout(timer);
        pending.delete(msg.reqId);
        resolve(msg);
      } else if (msg && msg.error) {
        console.error('Bridge Error (uncorrelated):', msg.error);
      }
    });

    nativePort.onDisconnect.addListener(() => {
      const err = chrome.runtime.lastError?.message || 'Native host disconnected';
      console.error('Native Host disconnected:', err);
      nativePort = null;
      // Fail every in-flight request instead of leaving callers hanging
      for (const [id, { resolve, timer }] of pending) {
        clearTimeout(timer);
        resolve({ success: false, error: 'Bridge disconnected: ' + err });
      }
      pending.clear();
    });
  } catch (e) {
    console.error('Failed to connect to native host:', e);
    nativePort = null;
  }
  return nativePort;
}

function sendToHost(message) {
  return new Promise((resolve) => {
    const p = getNativePort();
    if (!p) {
      return resolve({ success: false, error: 'Bridge not available. Please install the native host.' });
    }
    const reqId = `req_${Date.now()}_${++reqCounter}`;
    const timer = setTimeout(() => {
      if (pending.has(reqId)) {
        pending.delete(reqId);
        resolve({ success: false, error: 'Bridge timeout: no response within ' + REQUEST_TIMEOUT_MS + 'ms' });
      }
    }, REQUEST_TIMEOUT_MS);

    pending.set(reqId, { resolve, timer });

    try {
      p.postMessage({ ...message, reqId });
    } catch (err) {
      clearTimeout(timer);
      pending.delete(reqId);
      resolve({ success: false, error: 'Bridge communication failure: ' + err.message });
    }
  });
}

// ─── Origin Allowlist ────────────────────────────────────────────────────────
// Stored in chrome.storage.local as `allowedOrigins`: array of origin strings,
// e.g. ["https://app.algoramming.com", "http://localhost:3000"].
// An EMPTY list means "allow all" (backward compatible). Configure it from the
// extension popup to lock the bridge down to your own apps.

async function isOriginAllowed(sender) {
  // Messages from the extension itself (popup/dashboard) are always allowed
  if (sender.id === chrome.runtime.id && !sender.tab && !sender.url?.startsWith('http')) {
    return true;
  }
  const { allowedOrigins } = await chrome.storage.local.get(['allowedOrigins']);
  if (!Array.isArray(allowedOrigins) || allowedOrigins.length === 0) {
    return true; // open mode
  }
  let origin = sender.origin;
  if (!origin && sender.url) {
    try { origin = new URL(sender.url).origin; } catch (_) { /* ignore */ }
  }
  return !!origin && allowedOrigins.includes(origin);
}

// ─── Shared Message Handler ──────────────────────────────────────────────────

async function handleMessage(request, sender) {
  // 1. Unwrap the 'LOCAL_TCP_PRINT' wrapper used by external apps & the test button
  if (request.type === 'LOCAL_TCP_PRINT' && request.payload) {
    request = {
      action: 'PRINT',
      ...request.payload,
      data: request.payload.bytes // map 'bytes' -> 'data' expected by the host
    };
  }

  let { action, host, port, data, connectionId } = request;

  // 2. Internal action: bridge health check
  if (action === 'CHECK_BRIDGE') {
    const res = await sendToHost({ action: 'PING' });
    return { success: !!res.success, connected: !!res.success, version: res.version, error: res.error };
  }

  // 3. Security gate for everything that touches the network
  if (!(await isOriginAllowed(sender))) {
    console.warn('Blocked request from unauthorized origin:', sender.origin || sender.url);
    return { success: false, error: 'Origin not allowed. Add this origin in the Local TCP extension settings.' };
  }

  // 4. Resolve host/port (explicit values win and are persisted as defaults)
  const stored = await chrome.storage.local.get(['printerHost', 'printerPort']);
  if (host && port) {
    await chrome.storage.local.set({ printerHost: host, printerPort: port });
  } else {
    host = host || stored.printerHost;
    port = port || stored.printerPort;
  }

  if (['CONNECT', 'PRINT', 'SEND', 'DISCONNECT'].includes(action)) {
    if (!host || !port) {
      return { success: false, error: 'Host/Port not configured.' };
    }
  }

  // 5. Relay to native host (correlated + timeout-protected)
  return sendToHost({
    action,
    host,
    port: parseInt(port),
    data,
    connectionId: connectionId || `${host}:${port}`
  });
}

// ─── Listeners ───────────────────────────────────────────────────────────────

const messageListener = (request, sender, sendResponse) => {
  handleMessage(request, sender)
    .then(sendResponse)
    .catch((err) => sendResponse({ success: false, error: err.message || 'Internal logic error' }));
  return true; // keep the channel open for the async response
};

chrome.runtime.onMessageExternal.addListener(messageListener);
chrome.runtime.onMessage.addListener(messageListener);
