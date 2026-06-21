// Renders the last-known usage value and whether the menu bar app is reachable.

function colorFor(pct) {
  if (pct < 50) return "#2ea043"; // green
  if (pct < 80) return "#d29922"; // orange
  return "#d9534f"; // red
}

function render(data) {
  const pctEl = document.getElementById("pct");
  const barEl = document.getElementById("bar");
  const statusEl = document.getElementById("status");

  const pct = data && typeof data.lastPercentage === "number" ? data.lastPercentage : null;

  if (pct == null) {
    pctEl.textContent = "—";
    barEl.style.width = "0";
    statusEl.textContent = "No usage detected yet. Open a chat on claude.ai.";
    statusEl.className = "status muted";
    return;
  }

  pctEl.textContent = pct + "%";
  pctEl.style.color = colorFor(pct);
  barEl.style.width = pct + "%";
  barEl.style.background = colorFor(pct);

  if (data.appReachable) {
    statusEl.textContent = "Connected to menu bar app ✓";
    statusEl.className = "status";
  } else {
    statusEl.textContent = "Menu bar app not reachable — is it running?";
    statusEl.className = "status bad";
  }
}

chrome.runtime.sendMessage({ type: "getStatus" }, (data) => {
  void chrome.runtime.lastError;
  render(data || {});
});
