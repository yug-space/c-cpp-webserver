# Minimal C & C++ Web Servers

Two tiny HTTP/1.1 web servers built from scratch on POSIX sockets — one in C,
one in C++ — to show what a web server is underneath a framework. Both accept a
TCP connection, read the request, and return a fixed HTML page.

## Files

| File         | What it is                                              |
|--------------|---------------------------------------------------------|
| `server.c`   | The C server, listens on port **8080**                  |
| `server.cpp` | The C++ server, listens on port **8081**                |
| `proxy.c`    | C forward proxy — fetches real sites, port **8080**     |
| `proxy.cpp`  | C++ forward proxy — fetches real sites, port **8081**   |
| `mac-browser/Browser.m` | Native macOS browser shell using AppKit + WebKit |
| `Makefile`   | Builds the servers, proxies, and macOS browser app      |

## Build

```sh
make            # builds the servers, proxies, and MiniBrowser.app
```

Or compile by hand:

```sh
gcc -Wall -O2 -o server_c server.c
g++ -Wall -O2 -std=c++17 -o server_cpp server.cpp
```

## Run

```sh
./server_c      # then open http://localhost:8080
./server_cpp    # then open http://localhost:8081
```

Stop a server with `Ctrl+C`.

## Native macOS browser app

The `mac-browser/Browser.m` program is a small Chrome/Safari-style browser shell
written in Objective-C. It uses:

- **AppKit** for the native macOS window, toolbar, buttons, address field, and
  progress indicator.
- **WebKit** via `WKWebView` for real webpage rendering, JavaScript, CSS,
  images, history, and navigation.

Build it:

```sh
make mini_browser
```

Run it:

```sh
make run-browser
```

Or open it directly:

```sh
open MiniBrowser.app
```

What it supports:

- Loads `https://www.google.com` on launch.
- Address/search bar.
- Back, forward, reload, and stop.
- Loading progress.
- Native macOS titlebar and toolbar material.
- `Cmd+L`, `Cmd+R`, `Cmd+[`, and `Cmd+]` shortcuts.

This is a real native browser application, but not a custom browser engine. The
engine is WebKit, the same family of technology used by Safari. Writing a full
Chrome-style engine from scratch would require building HTML/CSS/JS/layout/paint
systems separately.

## How it works

Both programs follow the same socket lifecycle:

1. `socket()` — create a TCP socket.
2. `setsockopt(SO_REUSEADDR)` — allow quick restarts on the same port.
3. `bind()` — claim the port (`0.0.0.0:PORT`).
4. `listen()` — mark the socket as accepting connections.
5. `accept()` — block until a client connects; get a per-client socket.
6. `read()` / `write()` — read the HTTP request, write the HTTP response.
7. `close()` — hang up on the client, then loop back to `accept()`.

The C and C++ versions are intentionally near-identical so you can see exactly
what C++ adds: `std::string` for the response (no fixed buffer to overflow),
`std::cout`/`std::cerr` for I/O, `constexpr` constants, and C++ casts.

## Bonus: the forward proxies (loading google.com and more)

`proxy.c` / `proxy.cpp` go a step further — instead of returning a fixed page,
they **fetch a real website** with [libcurl](https://curl.se/libcurl/) and
return its HTML to your browser. libcurl handles TLS (HTTPS) and redirects,
which raw sockets alone can't do for sites like Google.

```sh
make proxy_c proxy_cpp        # needs libcurl (built into macOS; `apt install libcurl4-openssl-dev` on Debian/Ubuntu)
./proxy_c                     # port 8080
./proxy_cpp                   # port 8081
```

Then in a browser or curl:

| URL                                   | Fetches                  |
|---------------------------------------|--------------------------|
| `http://localhost:8080/`              | `https://www.google.com` |
| `http://localhost:8080/example.com`   | `https://example.com`    |
| `http://localhost:8080/https://x.com` | that exact URL           |

Verified working — `curl -s http://localhost:8080/` returns Google's real
`<title>Google</title>` page (~80 KB). Note: pages load as raw HTML, so
relative links/images on the fetched site won't resolve (the proxy doesn't
rewrite URLs) — it's a demonstration of server-side fetching, not a full proxy.

## Caveats (this is a learning demo, not production)

- Serves one client at a time (no threads / no event loop).
- Ignores the request — returns the same page for every path and method.
- No TLS, no logging, no timeouts.
