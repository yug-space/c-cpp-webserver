# MiniBrowser

A small native macOS browser written in Objective-C with AppKit and Apple's
WebKit framework.

This project builds a real `.app` bundle with:

- Native macOS window and toolbar
- Address/search bar
- Back, forward, reload, and stop controls
- Loading progress indicator
- `WKWebView` rendering for modern websites with HTML, CSS, JavaScript, images,
  history, and navigation
- Keyboard shortcuts: `Cmd+L`, `Cmd+R`, `Cmd+[`, and `Cmd+]`

## Files

| File | Purpose |
|------|---------|
| `mac-browser/Browser.m` | Objective-C AppKit + WebKit browser app |
| `mac-browser/Info.plist` | macOS app bundle metadata |
| `Makefile` | Builds and opens `MiniBrowser.app` |

## Build

```sh
make
```

This creates:

```text
MiniBrowser.app
```

## Run

```sh
make run-browser
```

Or:

```sh
open MiniBrowser.app
```

## Clean

```sh
make clean
```

## How It Works

`main()` starts an `NSApplication` and installs `BrowserAppDelegate` as the app
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

This is a native browser shell, not a custom browser engine. WebKit handles the
browser engine work: parsing HTML, applying CSS, running JavaScript, loading
images, handling links, and maintaining navigation history.
