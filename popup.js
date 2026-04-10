// Local TCP - popup.js
// Handles configuration, UI states, and bridge status

document.addEventListener('DOMContentLoaded', async () => {
  const setupState = document.getElementById('setupState');
  const dashboardState = document.getElementById('dashboardState');
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  
  const hostInput = document.getElementById('hostInput');
  const portInput = document.getElementById('portInput');
  
  const saveBtn = document.getElementById('saveBtn');
  const testBtn = document.getElementById('testBtn');
  const downloadBtn = document.getElementById('downloadBtn');
  const resetConfigBtn = document.getElementById('resetConfigBtn');
  const clearLogsBtn = document.getElementById('clearLogsBtn');
  const logBox = document.getElementById('logBox');

  // 1. Check Bridge Status
  async function checkBridge() {
    statusText.textContent = 'Checking...';
    statusDot.className = 'dot';
    
    return new Promise((resolve) => {
      chrome.runtime.sendMessage({ action: 'CHECK_BRIDGE' }, (res) => {
        if (res && res.connected) {
          statusText.textContent = 'Bridge Linked';
          statusDot.className = 'dot active';
          setupState.classList.remove('active');
          dashboardState.classList.add('active');
          resolve(true);
        } else {
          statusText.textContent = 'Setup Required';
          statusDot.className = 'dot error';
          setupState.classList.add('active');
          dashboardState.classList.remove('active');
          resolve(false);
        }
      });
    });
  }

  // 2. Load settings
  async function loadSettings() {
    const stored = await chrome.storage.local.get(['printerHost', 'printerPort']);
    if (stored.printerHost) hostInput.value = stored.printerHost;
    if (stored.printerPort) portInput.value = stored.printerPort;
  }

  // 3. Logging Helper
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
    
    // Limit logs
    if (logBox.children.length > 50) logBox.removeChild(logBox.lastChild);
  }

  // Initial check
  const isLinked = await checkBridge();
  if (isLinked) await loadSettings();

  // ─── Actions ───────────────────────────────────────────────────────────────

  saveBtn.addEventListener('click', async () => {
    const host = hostInput.value.trim();
    const port = portInput.value.trim();
    if (!host || !port) return addLog('Host and Port required.', 'error');
    
    await chrome.storage.local.set({ printerHost: host, printerPort: port });
    addLog(`Config saved: ${host}:${port}`, 'success');
  });

  testBtn.addEventListener('click', async () => {
    const host = hostInput.value.trim();
    const port = portInput.value.trim();
    if (!host || !port) return addLog('Host/Port missing.', 'error');

    testBtn.disabled = true;
    testBtn.textContent = 'Pinging...';
    try {
      chrome.runtime.sendMessage({ action: 'CONNECT', host, port }, (res) => {
        if (res && res.success) {
          addLog(`Success: ${res.message}`, 'success');
          chrome.runtime.sendMessage({ action: 'DISCONNECT' });
        } else {
          addLog(`Error: ${res?.error || 'Unknown error'}`, 'error');
        }
        testBtn.disabled = false;
        testBtn.textContent = 'Test Ping';
      });
    } catch (e) {
      addLog(`Failed: ${e.message}`, 'error');
      testBtn.disabled = false;
      testBtn.textContent = 'Test Ping';
    }
  });

  downloadBtn.addEventListener('click', () => {
    addLog('Installer instructions:', 'warning');
    addLog('1. Go to the "local_tcp/host" directory in your files.');
    addLog('2. Run the setup file for your OS.');
    alert('Setup Guide:\nPlease navigate to the "local_tcp/host" folder in your installation and run the "install_setup_mac.command" or "install_setup_windows.bat" file.');
  });

  clearLogsBtn.addEventListener('click', () => {
    logBox.innerHTML = '';
    addLog('Logs cleared.');
  });

  resetConfigBtn.addEventListener('click', async () => {
    if (confirm('Are you sure you want to reset all printer settings?')) {
      await chrome.storage.local.clear();
      hostInput.value = '';
      portInput.value = '';
      addLog('All local data cleared.', 'warning');
    }
  });
});
