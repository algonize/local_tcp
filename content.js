// Local TCP - content.js
// Bridges standard web page `window.postMessage` to the extension background.
// Responses are posted back to the page's own origin (no '*' wildcard).

window.addEventListener('message', (event) => {
  // 1. Only accept messages from this page itself
  if (event.source !== window || !event.data || event.data.source !== 'localtcp_req') {
    return;
  }

  // 2. Prepare payload for the background script
  const payload = { ...event.data };
  const messageId = payload.messageId;
  delete payload.source;
  delete payload.messageId;

  // 3. Send to the background (sender origin is attached automatically by
  //    Chrome, which the background uses for the origin allowlist check)
  chrome.runtime.sendMessage(payload, (response) => {
    // 4. Return the result back to the same page, scoped to its origin
    window.postMessage({
      source: 'localtcp_res',
      messageId: messageId,
      response: response || { success: false, error: chrome.runtime.lastError?.message || 'Unknown error' }
    }, window.location.origin);
  });
});
