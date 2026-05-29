# Minimal C & C++ Web Servers

Two tiny HTTP/1.1 web servers built from scratch on POSIX sockets — one in C,
one in C++ — to show what a web server is underneath a framework. Both accept a
TCP connection, read the request, and return a fixed HTML page.

## Files

| File         | What it is                                              |
|--------------|---------------------------------------------------------|
| `server.c`   | The C server, listens on port **8080**                  |
| `server.cpp` | The C++ server, listens on port **8081**                |
| `Makefile`   | Builds both binaries                                    |

## Build

```sh
make            # builds server_c and server_cpp
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

## Caveats (this is a learning demo, not production)

- Serves one client at a time (no threads / no event loop).
- Ignores the request — returns the same page for every path and method.
- No TLS, no logging, no timeouts.
