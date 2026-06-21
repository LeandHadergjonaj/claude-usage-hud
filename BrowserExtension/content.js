// Claude Usage HUD — content script.
//
// Runs on claude.ai. It watches the DOM for the session usage percentage that
// Claude shows natively, then forwards it to the background service worker,
// which POSTs it to the local menu bar app on http://localhost:27420/usage.
//
// claude.ai's markup changes often, so detection uses several strategies and
// falls back to scanning for a lone "NN%" near the bottom of the page.

(function () {
  "use strict";

  const POLL_INTERVAL_MS = 4000;
  const RESEND_INTERVAL_MS = 30000; // re-send an unchanged value at least this often
  const DEBUG = false;

  let lastSent = null;
  let lastSentAt = 0;

  function log(...args) {
    if (DEBUG) console.debug("[Claude Usage HUD]", ...args);
  }

  // Extract the first plausible percentage (0–100) from an arbitrary string.
  function extractPercent(str) {
    if (!str) return null;
    const m = String(str).match(/(\d{1,3})\s*%/);
    if (!m) return null;
    const n = parseInt(m[1], 10);
    if (Number.isNaN(n) || n < 0 || n > 100) return null;
    return n;
  }

  // True when the trimmed text is *only* a percentage, e.g. "23%".
  function isLonePercent(text) {
    return /^\s*\d{1,3}\s*%\s*$/.test(text || "");
  }

  // Strategy 1: elements that explicitly advertise usage/limit/context via
  // data-testid, aria-label, title, or class names.
  function findByAttributes() {
    const selectors = [
      '[data-testid*="usage" i]',
      '[data-testid*="limit" i]',
      '[data-testid*="context" i]',
      '[data-testid*="session" i]',
      '[aria-label*="usage" i]',
      '[aria-label*="limit" i]',
      '[aria-label*="session" i]',
      '[aria-label*="context" i]',
      '[class*="usage" i]',
      '[title*="usage" i]',
      '[title*="limit" i]',
    ];

    for (const sel of selectors) {
      let nodes;
      try {
        nodes = document.querySelectorAll(sel);
      } catch (e) {
        continue;
      }
      for (const node of nodes) {
        const fromLabel =
          extractPercent(node.getAttribute("aria-label")) ??
          extractPercent(node.getAttribute("title"));
        if (fromLabel != null) {
          log("matched via attribute", sel, fromLabel);
          return fromLabel;
        }
        const fromText = extractPercent(node.textContent);
        if (fromText != null) {
          log("matched via attribute text", sel, fromText);
          return fromText;
        }
      }
    }
    return null;
  }

  // Strategy 2: scan text nodes for a standalone "NN%" and prefer the one
  // lowest on the screen (Claude shows the usage figure in the input footer).
  function findByLonePercent() {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const v = node.nodeValue;
        if (!v) return NodeFilter.FILTER_REJECT;
        const t = v.trim();
        if (t.length === 0 || t.length > 5) return NodeFilter.FILTER_REJECT;
        return isLonePercent(t) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      },
    });

    const candidates = [];
    let node;
    while ((node = walker.nextNode())) {
      const value = extractPercent(node.nodeValue);
      // A "lone" usage indicator is realistically between 1% and 99%.
      if (value == null || value < 1 || value > 99) continue;
      const el = node.parentElement;
      const rect = el ? el.getBoundingClientRect() : null;
      // Ignore off-screen / zero-size nodes.
      if (rect && rect.width === 0 && rect.height === 0) continue;
      candidates.push({ value, top: rect ? rect.top : 0 });
    }

    if (candidates.length === 0) return null;
    candidates.sort((a, b) => b.top - a.top); // lowest on screen first
    log("matched via lone percent", candidates[0].value, "of", candidates.length);
    return candidates[0].value;
  }

  function detect() {
    return findByAttributes() ?? findByLonePercent();
  }

  function send(percentage) {
    const now = Date.now();
    if (percentage === lastSent && now - lastSentAt < RESEND_INTERVAL_MS) return;
    lastSent = percentage;
    lastSentAt = now;

    const payload = { percentage, timestamp: new Date().toISOString() };
    try {
      chrome.runtime.sendMessage({ type: "usage", payload }, () => {
        // Swallow "receiving end does not exist" etc. — nothing to do.
        void chrome.runtime.lastError;
      });
    } catch (e) {
      // Extension context can be invalidated on reload; ignore.
    }
  }

  function tick() {
    try {
      const pct = detect();
      if (pct != null) send(pct);
    } catch (e) {
      log("tick error", e);
    }
  }

  // Re-check on DOM mutations (debounced) in addition to the steady poll.
  let debounceTimer = null;
  const observer = new MutationObserver(() => {
    if (debounceTimer) return;
    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      tick();
    }, 1000);
  });

  function start() {
    tick();
    setInterval(tick, POLL_INTERVAL_MS);
    if (document.body) {
      observer.observe(document.body, {
        childList: true,
        subtree: true,
        characterData: true,
      });
    }
    log("started");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
