// Claude Usage HUD — background service worker.
//
// Receives usage updates from the content script and POSTs them to the local
// menu bar app. Doing the fetch from the background context (which holds the
// localhost host-permission) keeps it clear of page CORS restrictions, and the
// app also returns permissive CORS / Private Network Access headers.

const ENDPOINT = "http://localhost:27420/usage";

async function postUsage(payload) {
  const res = await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  return res.ok;
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || typeof message !== "object") return;

  if (message.type === "usage" && message.payload) {
    const payload = message.payload;
    // Remember the last value so the toolbar popup can show it even when the
    // app is offline.
    chrome.storage.local.set({
      lastPercentage: payload.percentage,
      lastTimestamp: payload.timestamp,
    });

    postUsage(payload)
      .then((ok) => {
        chrome.storage.local.set({ appReachable: ok, lastError: null });
        sendResponse({ ok });
      })
      .catch((err) => {
        chrome.storage.local.set({ appReachable: false, lastError: String(err) });
        sendResponse({ ok: false, error: String(err) });
      });
    return true; // async sendResponse
  }

  if (message.type === "getStatus") {
    chrome.storage.local.get(
      ["lastPercentage", "lastTimestamp", "appReachable", "lastError"],
      (data) => sendResponse(data)
    );
    return true;
  }
});
