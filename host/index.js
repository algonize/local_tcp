#!/usr/bin/env node
// Local TCP — Native Messaging Host (Node.js)
// =============================================================================
// WHY NODE (and not the Go binary): on macOS 15/26, Local Network Privacy keys
// LAN access to the *executable's* code identity. Chrome ends up running the
// system/Homebrew `node` binary here (via the shebang the installer patches in),
// which macOS recognizes and allows to reach 192.168.x.x. A bare custom Go
// binary is an unknown executable that macOS silently denies — so its TCP
// connects to the printer fail with "no route to host" even though ping works.
// Running through `node` sidesteps that entirely. (See git history for the Go
// host that hit this wall.)
//
// Protocol: Chrome Native Messaging — 4-byte little-endian length prefix + JSON.
// Actions:  PING | CONNECT | SEND | PRINT | DISCONNECT
// Every response echoes the caller's `reqId` so background.js can correlate
// concurrent requests safely.
'use strict';

const net = require('net');

// Reported back on PING so the popup's "bridge status" shows which host is live.
// Independent of the extension's manifest version on purpose: this is the value
// that tells you *which native host binary* is actually installed.
const VERSION = '2.1.0';

// ─── Connection state ────────────────────────────────────────────────────────
const connections = new Map(); // id -> net.Socket (live, reusable)
const opChains = new Map();     // id -> Promise (serializes ops per connection)

// ─── Native Messaging framing ────────────────────────────────────────────────
function send(msg) {
  const body = Buffer.from(JSON.stringify(msg), 'utf8');
  const header = Buffer.allocUnsafe(4);
  header.writeUInt32LE(body.length, 0);
  process.stdout.write(header);
  process.stdout.write(body);
}

let inbuf = Buffer.alloc(0);
process.stdin.on('data', (chunk) => {
  inbuf = Buffer.concat([inbuf, chunk]);
  // Drain every complete framed message currently buffered.
  while (inbuf.length >= 4) {
    const len = inbuf.readUInt32LE(0);
    if (len === 0 || len > 64 * 1024 * 1024) { // corrupt framing — resync by dropping
      inbuf = Buffer.alloc(0);
      send({ success: false, error: 'invalid message length' });
      break;
    }
    if (inbuf.length < 4 + len) break; // wait for the rest
    const body = inbuf.subarray(4, 4 + len);
    inbuf = inbuf.subarray(4 + len);
    let req;
    try {
      req = JSON.parse(body.toString('utf8'));
    } catch (e) {
      send({ success: false, error: 'JSON parse error: ' + e.message });
      continue;
    }
    Promise.resolve()
      .then(() => handle(req))
      .catch((e) => send({ reqId: req && req.reqId, success: false, error: 'Host error: ' + (e && e.message || e) }));
  }
});
process.stdin.on('end', () => process.exit(0)); // Chrome closed the port
process.on('uncaughtException', (e) => { try { send({ success: false, error: 'Uncaught: ' + e.message }); } catch (_) {} });

// ─── Helpers ─────────────────────────────────────────────────────────────────
function connId(req) {
  return req.connectionId || `${req.host}:${req.port}`;
}

// A single TCP connect attempt with an application-level timeout.
function dialOnce(host, port, timeoutMs) {
  return new Promise((resolve, reject) => {
    const socket = new net.Socket();
    let settled = false;
    socket.setTimeout(timeoutMs > 0 ? timeoutMs : 5000);
    socket.once('connect', () => { settled = true; socket.setTimeout(0); resolve(socket); });
    socket.once('timeout', () => { if (!settled) { socket.destroy(); reject(Object.assign(new Error('connect timeout'), { code: 'ETIMEDOUT' })); } });
    socket.once('error', (err) => { if (!settled) { socket.destroy(); reject(err); } });
    socket.connect(port, host);
  });
}

// Errors that typically clear on retry (printer asleep / ARP not yet resolved /
// momentary timeout) rather than a hard config error like connection refused.
function isTransient(err) {
  const c = err && err.code;
  return c === 'EHOSTUNREACH' || c === 'EHOSTDOWN' || c === 'ENETUNREACH' ||
         c === 'ETIMEDOUT' || /timeout/i.test((err && err.message) || '');
}

// Fast path for an awake printer; on a transient miss, keep retrying within a
// budget kept under the extension's 30s request timeout so a real error still
// surfaces to the caller before it gives up.
async function dialWithRetry(host, port, timeoutMs) {
  const deadline = Date.now() + 25000;
  const perAttempt = Math.min(timeoutMs > 0 ? timeoutMs : 4000, 4000);
  let lastErr;
  do {
    try {
      return await dialOnce(host, port, perAttempt);
    } catch (e) {
      lastErr = e;
      if (!isTransient(e)) throw e; // hard error — fail fast
    }
  } while (Date.now() < deadline);
  throw lastErr;
}

function getConn(id) {
  const s = connections.get(id);
  return s && !s.destroyed ? s : null;
}
function setConn(id, s) {
  const old = connections.get(id);
  if (old && old !== s) old.destroy();
  connections.set(id, s);
  s.once('close', () => { if (connections.get(id) === s) connections.delete(id); });
}
function dropConn(id) {
  const s = connections.get(id);
  if (s) { s.destroy(); connections.delete(id); }
}

// Serialize all operations on the same connection id so two concurrent print
// jobs can't interleave their ESC/POS byte streams and corrupt output.
function chain(id, fn) {
  const prev = opChains.get(id) || Promise.resolve();
  const next = prev.then(fn, fn);
  opChains.set(id, next.catch(() => {}));
  return next;
}

// Read back a short reply (e.g. ESC/POS DLE EOT status) for up to timeoutMs.
function readBack(socket, timeoutMs) {
  return new Promise((resolve) => {
    const chunks = [];
    const onData = (d) => chunks.push(d);
    const finish = () => {
      socket.removeListener('data', onData);
      socket.removeListener('error', finish);
      clearTimeout(timer);
      resolve(Buffer.concat(chunks));
    };
    socket.on('data', onData);
    socket.once('error', finish);
    const timer = setTimeout(finish, timeoutMs);
  });
}

// ─── Request dispatch ────────────────────────────────────────────────────────
async function handle(req) {
  const reqId = req.reqId;
  switch (req.action) {
    case 'PING':
      return send({ reqId, success: true, message: 'Pong', version: VERSION });

    case 'CONNECT': {
      const id = connId(req);
      return chain(id, async () => {
        try {
          const s = await dialWithRetry(req.host, req.port, req.timeoutMs || 0);
          setConn(id, s);
          send({ reqId, success: true, message: `Connected to ${req.host}:${req.port}`, connectionId: id });
        } catch (e) {
          send({ reqId, success: false, error: 'Socket error: ' + e.message, connectionId: id });
        }
      });
    }

    case 'SEND':
    case 'PRINT': {
      const id = connId(req);
      if (!Array.isArray(req.data)) return send({ reqId, success: false, error: 'Invalid data format' });
      return chain(id, async () => {
        let s = getConn(id);
        if (!s) {
          try {
            s = await dialWithRetry(req.host, req.port, req.timeoutMs || 0);
            setConn(id, s);
          } catch (e) {
            return send({ reqId, success: false, error: 'Socket connect failed: ' + e.message });
          }
        }
        const payload = Buffer.from(req.data.map((b) => b & 0xFF));
        try {
          await new Promise((res, rej) => s.write(payload, (err) => (err ? rej(err) : res())));
        } catch (e) {
          dropConn(id); // stale socket — drop so the next attempt re-dials
          return send({ reqId, success: false, error: 'Write failed: ' + e.message });
        }
        const resp = { reqId, success: true, bytesSent: payload.length, connectionId: id };
        if (req.readTimeoutMs > 0) {
          const back = await readBack(s, req.readTimeoutMs);
          if (back.length) resp.data = Array.from(back);
          else resp.message = 'Written; no status reply within readTimeoutMs';
        }
        send(resp);
      });
    }

    case 'DISCONNECT': {
      const id = connId(req);
      return chain(id, async () => {
        if (getConn(id)) { dropConn(id); send({ reqId, success: true, message: 'Disconnected' }); }
        else send({ reqId, success: true, message: 'No connection to disconnect' });
      });
    }

    default:
      return send({ reqId, success: false, error: 'Unknown action: ' + req.action });
  }
}
