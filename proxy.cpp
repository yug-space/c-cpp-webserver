// proxy.cpp — A tiny HTTP forward proxy in C++.
//
// A browser connects to us; we fetch a target web page (default google.com)
// with libcurl and send that page's HTML back to the browser.
//
// Same idea as proxy.c, but C++ gives us std::string for the growable buffer
// (no manual realloc) and stream I/O.
//
// Usage:
//   http://localhost:8081/                 -> https://www.google.com
//   http://localhost:8081/example.com      -> https://example.com
//   http://localhost:8081/https://news.com -> that exact URL
//
// Build:  g++ -Wall -O2 -std=c++17 -o proxy_cpp proxy.cpp -lcurl

#include <iostream>
#include <string>
#include <cstring>
#include <cstdio>       // snprintf, sscanf
#include <unistd.h>
#include <arpa/inet.h>
#include <curl/curl.h>

constexpr int PORT = 8081;
constexpr int BACKLOG = 10;

// libcurl hands us chunks of the remote response here. We append each chunk to
// the std::string pointed to by userp. std::string grows itself — no realloc.
static size_t write_cb(char *chunk, size_t sz, size_t nmemb, void *userp) {
    size_t total = sz * nmemb;
    auto *out = static_cast<std::string *>(userp);
    out->append(chunk, total);              // append raw bytes (binary-safe)
    return total;                           // tell libcurl we consumed it all
}

// Fetch `url`; return the body as a string. `ok` is set to false on failure.
static std::string fetch_url(const std::string &url, bool &ok) {
    std::string body;
    ok = false;

    CURL *curl = curl_easy_init();
    if (!curl) return body;

    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);   // follow redirects
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &body);     // -> userp in write_cb
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "cpp-proxy/1.0");
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);

    CURLcode rc = curl_easy_perform(curl);   // blocking fetch
    curl_easy_cleanup(curl);

    ok = (rc == CURLE_OK);
    return body;
}

// Convert the request path into a fetchable URL (see proxy.c for the rules).
static std::string path_to_url(const std::string &path) {
    if (path == "/") return "https://www.google.com";
    std::string p = path.substr(1);                       // drop leading '/'
    if (p.rfind("http://", 0) == 0 || p.rfind("https://", 0) == 0)
        return p;                                          // already has scheme
    return "https://" + p;                                 // default to https
}

int main() {
    curl_global_init(CURL_GLOBAL_DEFAULT);

    // --- identical socket setup to the basic server ---
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) { std::cerr << "socket failed\n"; return 1; }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in address;
    std::memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(PORT);

    if (bind(server_fd, reinterpret_cast<sockaddr *>(&address),
             sizeof(address)) < 0) {
        std::cerr << "bind failed\n"; return 1;
    }
    if (listen(server_fd, BACKLOG) < 0) { std::cerr << "listen failed\n"; return 1; }

    std::cout << "C++ proxy on http://localhost:" << PORT
              << "  (try /, /example.com)\n";

    while (true) {
        int client_fd = accept(server_fd, nullptr, nullptr);
        if (client_fd < 0) { std::cerr << "accept failed\n"; continue; }

        char buffer[4096];
        ssize_t n = read(client_fd, buffer, sizeof(buffer) - 1);
        if (n <= 0) { close(client_fd); continue; }
        buffer[n] = '\0';

        // Parse the request line: "GET /example.com HTTP/1.1".
        char method[8], path[2048];
        if (std::sscanf(buffer, "%7s %2047s", method, path) != 2) {
            close(client_fd); continue;
        }

        if (std::strcmp(path, "/favicon.ico") == 0) {     // ignore favicon
            const char *nf = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n"
                             "Connection: close\r\n\r\n";
            write(client_fd, nf, std::strlen(nf));
            close(client_fd); continue;
        }

        std::string url = path_to_url(path);
        std::cout << "  fetching " << url << "\n";

        bool ok = false;
        std::string body = fetch_url(url, ok);

        if (!ok) {
            std::string err =
                "HTTP/1.1 502 Bad Gateway\r\n"
                "Content-Type: text/plain\r\n"
                "Connection: close\r\n\r\n"
                "Proxy could not fetch the requested URL.\n";
            write(client_fd, err.c_str(), err.size());
            close(client_fd); continue;
        }

        // Headers first, then the fetched page as the body.
        std::string header =
            "HTTP/1.1 200 OK\r\n"
            "Content-Type: text/html; charset=utf-8\r\n"
            "Content-Length: " + std::to_string(body.size()) + "\r\n"
            "Connection: close\r\n\r\n";
        write(client_fd, header.c_str(), header.size());
        write(client_fd, body.c_str(), body.size());

        close(client_fd);
    }

    close(server_fd);
    curl_global_cleanup();
    return 0;
}
