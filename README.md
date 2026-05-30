# TrailBrowser

A small native browser shell for macOS and Linux.

TrailBrowser uses the native UI toolkit on each platform and a system WebKit
engine for rendering:

- macOS: Objective-C, AppKit, Apple WebKit
- Linux: C, GTK, WebKitGTK

This gives you real website rendering without Electron or a bundled Chromium
runtime.

The app includes:

- Native desktop window and toolbar
- Address/search bar
- Back, forward, reload, home, and stop controls
- Sidebar tabs with add/close controls
- Low-memory tab sleeping on macOS: inactive sidebar tabs keep URL/title
  metadata and release their WebKit view
- Loading progress indicator
- WebKit rendering for modern websites with HTML, CSS, JavaScript, images,
  history, and navigation
- macOS keyboard shortcuts: `Cmd+L`, `Cmd+R`, `Cmd+[`, and `Cmd+]`
- Optional, user-initiated **cookie import from Google Chrome** on macOS

## Files

| File | Purpose |
|------|---------|
| `mac-browser/Browser.m` | Objective-C AppKit + WebKit browser app |
| `mac-browser/ChromeCookieImporter.h/.m` | Imports cookies from a local Chrome profile |
| `mac-browser/Info.plist` | macOS app bundle metadata |
| `linux-browser/trailbrowser.c` | Lightweight C/GTK/WebKitGTK Linux browser app |
| `mcp-history-server/server.mjs` | Read-only MCP server for TrailBrowser history |
| `Makefile` | Builds the native app for macOS or Linux |

## Build

On macOS:

```sh
make
```

This creates:

```text
TrailBrowser.app
```

On Debian/Ubuntu Linux, install native dependencies first:

```sh
sudo apt update
sudo apt install build-essential pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev
```

Then build:

```sh
make
```

This creates:

```text
./trailbrowser
```

If your distro still ships WebKitGTK as `webkit2gtk-4.0`, install
`libwebkit2gtk-4.0-dev` instead; the Makefile checks for `4.1` first, then
falls back to `4.0`.

## Run

```sh
make run-browser
```

Or:

```sh
open TrailBrowser.app
```

On Linux:

```sh
./trailbrowser
```

Type in the top address bar and press Return. TrailBrowser only decides after
Return: full URLs and domain-like inputs open as websites, while phrases become
Google searches.

## Clean

```sh
make clean
```

## Import Cookies from Chrome

On macOS, TrailBrowser → **Import Cookies from Chrome…** copies cookies from a local
Google Chrome profile into TrailBrowser's own WebKit cookie store, so sites you
were signed in to in Chrome stay signed in here. This is the same kind of
"import from another browser" migration that Safari, Edge, Arc, and Brave ship.

How it works:

1. Lists the Chrome profiles under
   `~/Library/Application Support/Google/Chrome` (and their account emails from
   `Local State`). If you have more than one profile, you choose which to import.
2. Reads the AES key from the `Chrome Safe Storage` Keychain item. macOS shows a
   consent prompt the first time — this is the gate that keeps the import
   user-authorized.
3. Copies the profile's `Cookies` SQLite database to a temp file, decrypts each
   `v10`/`v11` value (AES-128-CBC, PBKDF2-derived key), and writes the cookies
   into `WKHTTPCookieStore`.

It only ever touches the current user's own Chrome data on this machine, never
sends cookies anywhere, and deletes the temporary database copy when done. The
import is entirely manual — nothing is read until you invoke the menu item.

The Linux build does not import Chrome cookies. It keeps the Linux binary small
and avoids pulling browser-profile migration code into the GTK shell.

## History MCP Server

TrailBrowser writes its own browsing history to:

```text
~/Library/Application Support/TrailBrowser/history.jsonl
```

On Linux, history is stored at:

```text
${XDG_DATA_HOME:-~/.local/share}/trailbrowser/history.jsonl
```

The MCP server reads that file and exposes read-only tools:

- `browser_status`
- `history_recent`
- `history_search`
- `history_by_domain`
- `history_top_domains`

Install dependencies:

```sh
make mcp-install
```

Run the MCP server over stdio:

```sh
make run-history-mcp
```

The MCP server is strictly read-only over `history.jsonl`: it does **not** read
Chrome profiles, decrypt Keychain data, read cookies, or expose session cookies.
Cookie handling lives entirely in the browser app's user-initiated Chrome import
(above); imported cookies stay inside WebKit's own cookie store and are never
written to `history.jsonl` or surfaced through MCP.

## How It Works

On macOS, `main()` starts an `NSApplication` and installs `BrowserAppDelegate` as the app
delegate.

When macOS finishes launching the app, `applicationDidFinishLaunching:` runs.
That method creates the menu, builds the browser window, and loads
`https://www.google.com`.

The UI is native AppKit:

- `NSWindow` is the main app window.
- `NSVisualEffectView` creates the macOS toolbar surface.
- `NSButton` creates the navigation buttons.
- `NSSearchField` is the address/search bar.
- `NSProgressIndicator` shows page load progress.

The web page itself is rendered by WebKit:

- `WKWebView` displays the website.
- `loadRequest:` loads a URL.
- `goBack`, `goForward`, and `reload` control navigation.
- Key-value observing tracks `estimatedProgress`, `URL`, `canGoBack`, and
  `canGoForward` so the UI stays in sync.
- Finished navigations append redacted history entries to `history.jsonl`.
- The MCP server reads `history.jsonl` and exposes safe browsing-history lookup
  tools to MCP clients.
- Inactive macOS sidebar tabs are slept to keep memory close to one active
  WebKit page instead of one live WebKit instance per tab.

On Linux, `linux-browser/trailbrowser.c` does the same job with GTK widgets and
`WebKitWebView` from WebKitGTK. It writes history to the XDG data directory and
uses the same URL-vs-search rules as the macOS address bar.

This is a native browser shell, not a custom browser engine. WebKit handles the
browser engine work: parsing HTML, applying CSS, running JavaScript, loading
images, handling links, and maintaining navigation history.
