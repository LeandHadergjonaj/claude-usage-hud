# Claude Usage HUD

Show your **Claude.ai session usage percentage** in the macOS menu bar at all
times — the same `23%` figure Claude shows in its own UI.

```
 ┌─────────────────────────────────────────────┐
 │  …  🔋  📶  🔊   23%   Tue 9:41              │   ← menu bar (green/orange/red)
 └─────────────────────────────────────────────┘
                      │ click
                      ▼
            ┌──────────────────────┐
            │    Claude Usage      │
            │       ╭───╮          │
            │       │23%│          │   ← popover: progress arc
            │       ╰───╯          │
            │  23% of session used │
            │  Updated 3s ago      │
            └──────────────────────┘
```

It has two pieces:

| Piece | What it does |
|-------|--------------|
| **`BrowserExtension/`** | A Chrome MV3 extension that runs on `claude.ai`, reads the usage percentage from the page, and POSTs it to `localhost:27420`. |
| **`MenuBarApp/`** | A SwiftUI + AppKit menu bar app that runs a tiny local HTTP server, displays the percentage (colour-coded), and shows a popover with a progress arc on click. |

```
claude-usage-hud/
├── MenuBarApp/                 ← Swift / SwiftUI Xcode project
│   ├── ClaudeUsageHUD.xcodeproj
│   └── ClaudeUsageHUD/
│       ├── ClaudeUsageHUDApp.swift   App entry point
│       ├── AppDelegate.swift         Status item + popover + server wiring
│       ├── UsageState.swift          Shared observable state
│       ├── UsageServer.swift         Loopback HTTP server (Network.framework)
│       ├── PopoverView.swift         SwiftUI popover (progress arc)
│       ├── Info.plist                LSUIElement = true (no Dock icon)
│       └── Assets.xcassets
├── BrowserExtension/           ← Chrome MV3 extension
│   ├── manifest.json
│   ├── content.js              Detects the % on claude.ai
│   ├── background.js           Forwards the % to the menu bar app
│   ├── popup.html / popup.js   Toolbar popup (status + last value)
└── README.md
```

---

## How it works

1. `content.js` runs on every `claude.ai` page and watches the DOM for the
   session usage percentage Claude shows natively.
2. Every few seconds (and on DOM changes) it sends the value to `background.js`.
3. `background.js` POSTs `{ "percentage": 23, "timestamp": "…" }` to
   `http://localhost:27420/usage`.
4. The Swift app runs an HTTP server on port **27420** (loopback only) and
   updates its state.
5. The menu bar shows `23%` in **green** (`<50`), **orange** (`50–79`), or
   **red** (`≥80`).
6. Clicking the menu bar item opens a popover with a progress arc and
   "23% of session used".

If the app isn't running, the extension just fails silently and keeps retrying.

---

## Setup

### 1. Build and run the menu bar app

**Requirements:** macOS 13+ and Xcode 15+ (no external dependencies).

1. Open `MenuBarApp/ClaudeUsageHUD.xcodeproj` in Xcode.
2. Select the **ClaudeUsageHUD** scheme and **My Mac** as the run destination.
3. *(If Xcode complains about signing)* select the **ClaudeUsageHUD** target →
   **Signing & Capabilities** → set **Team** to your personal team, or leave it
   on automatic — macOS will sign it to run locally.
4. Press **⌘R**.

The app has **no Dock icon** (`LSUIElement = true`). Look for `—` in the menu
bar — that means it's running and waiting for data. Once the extension sends a
value it becomes e.g. `23%`.

> **Note on the App Sandbox:** this project ships with the sandbox **disabled**
> so the local HTTP server can bind to port 27420 without extra entitlements.
> If you enable the App Sandbox later, add the **Incoming Connections (Server)**
> capability (`com.apple.security.network.server`).

#### Run it without keeping Xcode open

After building once, the app is in Xcode's Products. Right-click
**`ClaudeUsageHUD.app`** in the Project navigator → **Show in Finder**, then copy
it to `/Applications`. To launch it automatically at login, add it under
**System Settings → General → Login Items**.

### 2. Install the Chrome extension

1. Open `chrome://extensions`.
2. Toggle **Developer mode** (top-right) on.
3. Click **Load unpacked** and select the **`BrowserExtension/`** folder.
4. Open or reload a tab on **https://claude.ai** and use it normally.

Click the extension's toolbar icon to see the last detected value and whether
it can reach the menu bar app.

That's it — the menu bar percentage should start tracking your Claude session.

---

## Verifying it works

- **Test the server directly** (with the app running):

  ```sh
  curl -i -X POST http://localhost:27420/usage \
    -H 'Content-Type: application/json' \
    -d '{"percentage": 42, "timestamp": "2026-06-21T12:00:00Z"}'
  ```

  You should get `HTTP/1.1 200 OK` and the menu bar should jump to `42%`
  (orange).

- **Watch the extension:** on `chrome://extensions`, click **service worker**
  under the extension to open its console, or open DevTools on a `claude.ai` tab
  and set `DEBUG = true` at the top of `content.js` to log what it detects.

---

## Troubleshooting

**Menu bar shows `—` forever.**
The app is running but hasn't received a value. Make sure the extension is
loaded, you're on a `claude.ai` page with a percentage visible, and the server
is up (`curl` test above).

**`curl` works but the extension doesn't update.**
Open the extension's service-worker console (`chrome://extensions` → *service
worker*) and look for fetch errors. Reload the extension after any change.

**Nothing detected on `claude.ai`.**
Claude's markup changes frequently, so the selectors may need a tweak. Set
`DEBUG = true` in `content.js` and reload. The detector tries, in order:
1. elements with `data-testid` / `aria-label` / `title` / class names
   containing *usage*, *limit*, *context*, or *session*;
2. a lone `NN%` text node, preferring the one lowest on screen (Claude shows
   the figure in the chat input footer).

To target a specific element you found in DevTools, add its selector to the
`selectors` array in `findByAttributes()` inside `content.js`.

**Port 27420 already in use.**
Change the port in **two** places and reload both pieces:
- `MenuBarApp/ClaudeUsageHUD/AppDelegate.swift` → `UsageServer(port: 27420)`
- `BrowserExtension/background.js` → `ENDPOINT`
- and the matching `host_permissions` entries in
  `BrowserExtension/manifest.json`.

**Build fails on signing.**
For local use you don't need a paid Apple Developer account — set the target's
Team to your free personal team (or leave automatic) and Xcode will sign it to
run on your Mac.

---

## Privacy & security

- The server binds to **loopback only** and rejects any non-localhost
  connection — nothing is exposed to your network.
- Only a single integer (the percentage) and a timestamp ever leave the page.
  No message content, account info, or page data is read or transmitted.
- Nothing is sent anywhere except your own Mac on `localhost`.
