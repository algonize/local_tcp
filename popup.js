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
  function addLog(msg, type = 'info') {
    const entry = document.createElement('div');
    entry.className = 'log-entry';
    const time = new Date().toLocaleTimeString([], { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });
    entry.innerHTML = `<span class="log-time">[${time}]</span> <span class="log-msg ${type}">${msg}</span>`;
    logBox.appendChild(entry);
    logBox.scrollTop = logBox.scrollHeight;

    // Visual pulse effect
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

    chrome.storage.local.set({ host, port }, () => {
      setTimeout(() => {
        saveBtn.classList.remove('loading');
        saveBtn.disabled = false;
        addLog('Configuration saved locally.', 'success');
      }, 300);
    });
  });

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
      payload: { host, port, bytes: [0x10, 0x04, 0x01] } // DLE EOT 1: Real-time status request
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
    }); // Fixed closing
  });

  downloadBtn.addEventListener('click', async () => {
    addLog('Starting dynamic build...', 'info');
    downloadBtn.disabled = true;
    downloadBtn.textContent = 'Bundling...';
    
    // 1. Detect OS
    let os = 'mac'; // default
    const platform = (navigator.userAgentData?.platform || navigator.platform).toLowerCase();
    if (platform.includes('win')) os = 'win';
    else if (platform.includes('linux')) os = 'linux';
    
    // 2. Define Files to fetch (from root /host folder on GitHub)
    const GITHUB_RAW = 'https://raw.githubusercontent.com/algonize/local_tcp/main/host/';
    const commonFiles = ['index.js', 'com.algoramming.localtcp.json'];
    const osFiles = {
      mac: ['install_setup_mac.sh', 'uninstall_setup_mac.sh', 'guide_mac.txt'],
      win: ['install_setup_windows.ps1', 'uninstall_setup_windows.ps1', 'guide_windows.txt'],
      linux: ['install_setup_linux.sh', 'uninstall_setup_linux.sh', 'guide_linux.txt']
    };

    const filesToFetch = [...commonFiles, ...osFiles[os]];

    try {
      addLog(`Fetching setup files for ${os}...`, 'info');
      downloadBtn.classList.add('loading');
      downloadBtn.disabled = true;
      
      const zip = new JSZip();
      
      for (const file of filesToFetch) {
        const response = await fetch(GITHUB_RAW + file);
        if (!response.ok) throw new Error(`Failed to fetch ${file}`);
        const blob = await response.blob();
        zip.file(file, blob);
      }

      const content = await zip.generateAsync({ type: 'blob' });
      const url = URL.createObjectURL(content);
      
      const a = document.createElement('a');
      a.href = url;
      a.download = `localtcp_bridge_${os}.zip`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      
      addLog('ZIP Downloaded! Follow guide.txt instructions.', 'success');
    } catch (err) {
      addLog(`Download Error: ${err.message}`, 'error');
    } finally {
      downloadBtn.classList.remove('loading');
      downloadBtn.disabled = false;
    }
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
