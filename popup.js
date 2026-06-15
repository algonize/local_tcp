// Local TCP - popup.js
// Handles configuration, UI states, bridge status, and the security allowlist.
// The Setup Kit button downloads a one-click installer from GitHub Releases.

const RELEASE_BASE = 'https://github.com/algonize/local_tcp/releases/latest/download/';
const INSTALLER_ASSETS = {
  win: 'LocalTCP-Setup-Windows.exe',
  mac: 'LocalTCP-Setup-Mac.pkg',
  linux: 'localtcp-linux-installer.run'
};

document.addEventListener('DOMContentLoaded', async () => {
  const setupState = document.getElementById('setupState');
  const dashboardState = document.getElementById('dashboardState');
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');

  const hostInput = document.getElementById('hostInput');
  const portInput = document.getElementById('portInput');
  const originsInput = document.getElementById('originsInput');

  const saveBtn = document.getElementById('saveBtn');
  const testBtn = document.getElementById('testBtn');
  const saveOriginsBtn = document.getElementById('saveOriginsBtn');
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
          statusText.textContent = res.version ? `Bridge v${res.version}` : 'Bridge Linked';
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
    const stored = await chrome.storage.local.get(['printerHost', 'printerPort', 'allowedOrigins']);
    if (stored.printerHost) hostInput.value = stored.printerHost;
    if (stored.printerPort) portInput.value = stored.printerPort;
    if (originsInput && Array.isArray(stored.allowedOrigins)) {
      originsInput.value = stored.allowedOrigins.join('\n');
    }
  }

  // 3. Logging Helper
  function addLog(msg, type = 'info') {
    const entry = document.createElement('div');
    entry.className = 'log-entry';
    const time = new Date().toLocaleTimeString([], { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
    entry.innerHTML = `<span class="log-time">[${time}]</span> <span class="log-msg ${type}">${msg}</span>`;
    logBox.appendChild(entry);
    logBox.scrollTop = logBox.scrollHeight;

    logBox.classList.add('active');
    setTimeout(() => logBox.classList.remove('active'), 500);
  }

  // Initial check
  const isLinked = await checkBridge();
  if (isLinked) await loadSettings();

  // ─── Actions ───────────────────────────────────────────────────────────────

  saveBtn.addEventListener('click', async () => {
    const host = hostInput.value.trim();
    const port = parseInt(portInput.value.trim());

    if (!host || !port) {
      addLog('Error: Host and Port are required.', 'error');
      return;
    }

    saveBtn.classList.add('loading');
    saveBtn.disabled = true;

    chrome.storage.local.set({ printerHost: host, printerPort: port }, () => {
      setTimeout(() => {
        saveBtn.classList.remove('loading');
        saveBtn.disabled = false;
        addLog('Configuration saved locally.', 'success');
      }, 300);
    });
  });

  if (saveOriginsBtn && originsInput) {
    saveOriginsBtn.addEventListener('click', async () => {
      const lines = originsInput.value
        .split('\n')
        .map((s) => s.trim().replace(/\/+$/, '')) // strip trailing slashes
        .filter(Boolean);

      // Validate each entry is a proper origin
      const invalid = [];
      const origins = [];
      for (const line of lines) {
        try {
          const u = new URL(line);
          origins.push(u.origin);
        } catch (_) {
          invalid.push(line);
        }
      }
      if (invalid.length) {
        addLog(`Invalid origin(s): ${invalid.join(', ')}`, 'error');
        return;
      }
      await chrome.storage.local.set({ allowedOrigins: origins });
      if (origins.length === 0) {
        addLog('Allowlist cleared — bridge is open to ALL websites.', 'warning');
      } else {
        addLog(`Allowlist saved (${origins.length} origin${origins.length > 1 ? 's' : ''}).`, 'success');
      }
    });
  }

  testBtn.addEventListener('click', () => {
    const host = hostInput.value.trim();
    const port = parseInt(portInput.value.trim());

    if (!host || !port) {
      addLog('Error: Set config before testing.', 'error');
      return;
    }

    testBtn.classList.add('loading');
    testBtn.disabled = true;

    addLog(`Testing connection to ${host}:${port}...`, 'info');

    chrome.runtime.sendMessage({
      type: 'LOCAL_TCP_PRINT',
      payload: { host, port, bytes: [0x10, 0x04, 0x01] } // DLE EOT 1: real-time status request
    }, (response) => {
      testBtn.classList.remove('loading');
      testBtn.disabled = false;

      if (chrome.runtime.lastError) {
        addLog(`System Error: ${chrome.runtime.lastError.message}`, 'error');
      } else if (response && response.success) {
        addLog('Success: Bridge reached hardware!', 'success');
      } else {
        addLog(`Failed: ${response?.error || 'Unknown error'}`, 'error');
      }
    });
  });

  downloadBtn.addEventListener('click', () => {
    // Detect OS and download the matching one-click installer from
    // GitHub Releases. No terminal, no Node.js — just run the installer
    // and restart Chrome.
    let os = 'mac';
    const platform = (navigator.userAgentData?.platform || navigator.platform || '').toLowerCase();
    if (platform.includes('win')) os = 'win';
    else if (platform.includes('linux')) os = 'linux';

    const url = RELEASE_BASE + INSTALLER_ASSETS[os];
    addLog(`Downloading ${INSTALLER_ASSETS[os]}...`, 'info');
    chrome.tabs.create({ url });
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
      if (originsInput) originsInput.value = '';
      addLog('All local data cleared.', 'warning');
    }
  });
});
