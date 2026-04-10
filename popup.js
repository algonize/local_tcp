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
    addLog('Detecting system...', 'info');
    
    // 1. Detect OS
    let os = 'mac'; // default
    const platform = (navigator.userAgentData?.platform || navigator.platform).toLowerCase();
    
    if (platform.includes('win')) os = 'win';
    else if (platform.includes('linux')) os = 'linux';
    
    addLog(`System: ${os.toUpperCase()}`, 'success');

    // 2. Define files based on OS
    const GITHUB_RAW = 'https://raw.githubusercontent.com/algonize/local_tcp/main/host/';
    const commonFiles = ['index.js', 'com.algonize.localtcp.json'];
    const osFiles = {
      mac: ['install_setup_mac.command', 'uninstall_setup_mac.command'],
      win: ['install_setup_windows.bat', 'uninstall_setup_windows.bat'],
      linux: ['install_setup_linux.sh', 'uninstall_setup_linux.sh']
    };

    const filesToDownload = [...commonFiles, ...osFiles[os]];

    // 3. Trigger Downloads
    addLog('Downloading setup kit...', 'info');
    filesToDownload.forEach(file => {
      chrome.downloads.download({
        url: GITHUB_RAW + file,
        filename: `algonize_bridge/${file}`,
        saveAs: false
      });
    });

    addLog('Success: Check your Downloads folder.', 'success');
    alert('Bridge Downloaded!\n\nPlease open your Downloads folder, go into "algonize_bridge", and run the install script.');
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
