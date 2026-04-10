// Local TCP - popup.js
// Handles configuration UI and storage

document.addEventListener('DOMContentLoaded', async () => {
  const hostInput = document.getElementById('hostInput');
  const portInput = document.getElementById('portInput');
  const saveBtn = document.getElementById('saveBtn');
  const testBtn = document.getElementById('testBtn');
  const logBox = document.getElementById('logBox');

  // 1. Load existing settings
  const stored = await chrome.storage.local.get(['printerHost', 'printerPort']);
  if (stored.printerHost) hostInput.value = stored.printerHost;
  if (stored.printerPort) portInput.value = stored.printerPort;

  // ─── Logging Helper ────────────────────────────────────────────────────────
  function addLog(message, type = 'info') {
    const entry = document.createElement('div');
    entry.className = 'log-entry';
    
    const time = document.createElement('span');
    time.className = 'log-time';
    time.textContent = new Date().toLocaleTimeString([], { hour12: false });
    
    const msg = document.createElement('span');
    msg.className = `log-msg ${type}`;
    msg.textContent = message;
    
    entry.appendChild(time);
    entry.appendChild(msg);
    logBox.prepend(entry);
  }

  // ─── Save Settings ─────────────────────────────────────────────────────────
  saveBtn.addEventListener('click', async () => {
    const host = hostInput.value.trim();
    const port = portInput.value.trim();

    if (!host || !port) {
      addLog('Error: Host and Port are required.', 'error');
      return;
    }

    await chrome.storage.local.set({ printerHost: host, printerPort: port });
    addLog(`Configuration saved: ${host}:${port}`, 'success');
  });

  // ─── Test Connection ───────────────────────────────────────────────────────
  testBtn.addEventListener('click', async () => {
    const host = hostInput.value.trim();
    const port = portInput.value.trim();

    if (!host || !port) {
      addLog('Error: Host and Port required to test.', 'error');
      return;
    }

    testBtn.disabled = true;
    testBtn.textContent = 'Testing...';
    
    try {
      addLog(`Attempting to connect to ${host}:${port}...`);
      
      const response = await new Promise((resolve) => {
        chrome.runtime.sendMessage({ action: 'CONNECT', host, port }, resolve);
      });

      if (response && response.success) {
        addLog(`Connection successful: ${response.message}`, 'success');
        // Automatically disconnect after test
        chrome.runtime.sendMessage({ action: 'DISCONNECT' });
      } else {
        addLog(`Failed: ${response?.error || 'Unknown error'}`, 'error');
      }
    } catch (err) {
      addLog(`System Error: ${err.message}`, 'error');
    } finally {
      testBtn.disabled = false;
      testBtn.textContent = 'Test Connection';
    }
  });
});
