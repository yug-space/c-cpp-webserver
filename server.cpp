// server.cpp — A minimal HTTP/1.1 web server in C++ using POSIX sockets and
// a couple of C++ conveniences (std::string, std::cout, exceptions-free style).

#include <iostream>     // std::cout, std::cerr — type-safe stream I/O
#include <string>       // std::string — owns and manages its own memory
#include <cstring>      // std::memset — zero out the address struct
#include <unistd.h>     // read, write, close — POSIX file-descriptor I/O
#include <arpa/inet.h>  // socket, bind, listen, accept, htons, sockaddr_in

constexpr int PORT = 8081;   // Compile-time constant: the port we listen on
constexpr int BACKLOG = 10;  // Max queued, not-yet-accepted connections

int main() {
    // 1. Create an IPv4 TCP socket. Same call as in C — the sockets API is C.
    //    Returns a file descriptor, or -1 on failure.
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        std::cerr << "socket failed\n";   // C++ stream instead of perror
        return 1;
    }

    // 2. Reuse the address right away so restarts don't hit "Address already
    //    in use" while the port lingers in TIME_WAIT.
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    // 3. Fill in the IPv4 address we want to bind to (0.0.0.0:PORT).
    sockaddr_in address;
    std::memset(&address, 0, sizeof(address)); // Zero all fields first
    address.sin_family = AF_INET;               // IPv4
    address.sin_addr.s_addr = INADDR_ANY;       // Any local interface
    address.sin_port = htons(PORT);             // Port in network byte order

    // 4. Bind the socket to the address/port — claim it.
    if (bind(server_fd, reinterpret_cast<sockaddr *>(&address),
             sizeof(address)) < 0) {            // C++ cast instead of C cast
        std::cerr << "bind failed\n";
        return 1;
    }

    // 5. Start listening for incoming connections.
    if (listen(server_fd, BACKLOG) < 0) {
        std::cerr << "listen failed\n";
        return 1;
    }

    std::cout << "C++ server listening on http://localhost:" << PORT << "\n";

    // 6. Build the HTTP response once. std::string handles the buffer sizing
    //    for us, so there's no fixed-size char array to overflow.
    //    Format: status line + headers + blank line + body.
    const std::string body =
        "<!DOCTYPE html><html><body><h1>Hello from C++!</h1></body></html>";
    const std::string response =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/html\r\n"
        "Content-Length: " + std::to_string(body.size()) + "\r\n"
        "Connection: close\r\n"
        "\r\n" +
        body;

    // 7. Serve forever: accept a client, reply, close, repeat.
    while (true) {
        // accept() blocks until a client connects and returns a new socket
        // just for that client; server_fd keeps listening.
        int client_fd = accept(server_fd, nullptr, nullptr);
        if (client_fd < 0) {
            std::cerr << "accept failed\n";
            continue;                            // Keep the server running
        }

        // Drain the client's request so its write completes; we don't parse it.
        char buffer[4096];
        read(client_fd, buffer, sizeof(buffer) - 1);

        // Send our response. .c_str() gives a const char*, .size() the length.
        write(client_fd, response.c_str(), response.size());

        // Hang up on this client; the browser renders the returned HTML.
        close(client_fd);
    }

    close(server_fd);  // Unreachable here, but the correct cleanup.
    return 0;
}
