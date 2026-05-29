/* proxy.c — A tiny HTTP forward proxy in C.
 *
 * A browser connects to us; we fetch a target web page (default google.com)
 * using libcurl, and stream that page's HTML back to the browser.
 *
 * Why libcurl? Real sites like google.com speak HTTPS and issue redirects.
 * Doing TLS by hand with raw sockets is hundreds of lines; libcurl handles
 * the TLS handshake, redirects, and chunked transfer for us.
 *
 * Usage in a browser:
 *   http://localhost:8080/                  -> fetches https://www.google.com
 *   http://localhost:8080/example.com       -> fetches https://example.com
 *   http://localhost:8080/https://news.com  -> fetches that exact URL
 *
 * Build:  cc -Wall -O2 -o proxy_c proxy.c -lcurl
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <curl/curl.h>   /* libcurl: the network client that does the fetching */

#define PORT 8080
#define BACKLOG 10

/* A growable buffer that libcurl fills as bytes arrive from the remote site. */
struct memory {
    char  *data;   /* malloc'd block holding the page bytes so far            */
    size_t size;   /* how many bytes we've stored                             */
};

/* libcurl calls this callback repeatedly, handing us chunks of the response.
 * We append each chunk to our growable buffer. Returning a count != the bytes
 * libcurl gave us signals an error and aborts the transfer.                   */
static size_t write_cb(void *chunk, size_t sz, size_t nmemb, void *userp) {
    size_t total = sz * nmemb;                 /* bytes in this chunk          */
    struct memory *mem = (struct memory *)userp;

    /* Grow the buffer to fit the new chunk plus a trailing NUL.               */
    char *bigger = realloc(mem->data, mem->size + total + 1);
    if (!bigger) return 0;                     /* out of memory -> abort       */
    mem->data = bigger;

    memcpy(&mem->data[mem->size], chunk, total); /* copy chunk to the end      */
    mem->size += total;
    mem->data[mem->size] = '\0';               /* keep it a valid C string     */
    return total;                              /* tell libcurl we took it all  */
}

/* Fetch `url` and return a malloc'd, NUL-terminated body (caller frees it),
 * or NULL on failure. *out_len receives the body length.                      */
static char *fetch_url(const char *url, size_t *out_len) {
    CURL *curl = curl_easy_init();             /* create an easy-handle        */
    if (!curl) return NULL;

    struct memory mem = { malloc(1), 0 };      /* start with a 1-byte buffer   */
    mem.data[0] = '\0';

    curl_easy_setopt(curl, CURLOPT_URL, url);              /* what to fetch     */
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);    /* follow redirects  */
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);/* our sink         */
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &mem);       /* passed to write_cb*/
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "c-proxy/1.0");/* identify        */
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);          /* give up after 15s */

    CURLcode rc = curl_easy_perform(curl);     /* blocking: do the whole fetch  */
    curl_easy_cleanup(curl);                   /* free the handle              */

    if (rc != CURLE_OK) {                      /* DNS/TLS/network error?        */
        free(mem.data);
        return NULL;
    }
    *out_len = mem.size;
    return mem.data;
}

/* Turn the request path into a fetchable URL.
 *   "/"                -> "https://www.google.com"
 *   "/example.com"     -> "https://example.com"
 *   "/https://x.com"   -> "https://x.com"
 * Writes into out (size outsz).                                               */
static void path_to_url(const char *path, char *out, size_t outsz) {
    if (strcmp(path, "/") == 0) {                       /* bare root           */
        snprintf(out, outsz, "https://www.google.com");
        return;
    }
    const char *p = path + 1;                           /* skip leading '/'    */
    if (strncmp(p, "http://", 7) == 0 ||                /* already has scheme? */
        strncmp(p, "https://", 8) == 0) {
        snprintf(out, outsz, "%s", p);
    } else {
        snprintf(out, outsz, "https://%s", p);          /* default to https    */
    }
}

int main(void) {
    curl_global_init(CURL_GLOBAL_DEFAULT);     /* init libcurl once at startup  */

    /* --- identical socket setup to the basic server --- */
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) { perror("socket"); exit(EXIT_FAILURE); }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(PORT);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind"); exit(EXIT_FAILURE);
    }
    if (listen(server_fd, BACKLOG) < 0) { perror("listen"); exit(EXIT_FAILURE); }

    printf("C proxy on http://localhost:%d  (try /, /example.com)\n", PORT);

    while (1) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) { perror("accept"); continue; }

        /* Read the browser's request so we can pull out the path it asked for.*/
        char buffer[4096];
        ssize_t n = read(client_fd, buffer, sizeof(buffer) - 1);
        if (n <= 0) { close(client_fd); continue; }
        buffer[n] = '\0';

        /* The first line looks like: "GET /example.com HTTP/1.1".
         * Grab the middle token (the path) with sscanf.                       */
        char method[8], path[2048];
        if (sscanf(buffer, "%7s %2047s", method, path) != 2) {
            close(client_fd); continue;
        }

        /* Browsers also request /favicon.ico — skip it with a 404 so we don't
         * fire off a pointless fetch.                                         */
        if (strcmp(path, "/favicon.ico") == 0) {
            const char *nf = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n"
                             "Connection: close\r\n\r\n";
            write(client_fd, nf, strlen(nf));
            close(client_fd); continue;
        }

        char url[2100];
        path_to_url(path, url, sizeof(url));
        printf("  fetching %s\n", url);

        size_t body_len = 0;
        char *body = fetch_url(url, &body_len);

        if (!body) {                            /* fetch failed -> tell browser */
            const char *err =
                "HTTP/1.1 502 Bad Gateway\r\n"
                "Content-Type: text/plain\r\n"
                "Connection: close\r\n\r\n"
                "Proxy could not fetch the requested URL.\n";
            write(client_fd, err, strlen(err));
            close(client_fd); continue;
        }

        /* Send our own HTTP headers, then the fetched page as the body.
         * We send the header separately so the (binary-safe) body can follow
         * with its exact byte length.                                         */
        char header[256];
        int hlen = snprintf(header, sizeof(header),
            "HTTP/1.1 200 OK\r\n"
            "Content-Type: text/html; charset=utf-8\r\n"
            "Content-Length: %zu\r\n"
            "Connection: close\r\n\r\n",
            body_len);
        write(client_fd, header, hlen);
        write(client_fd, body, body_len);

        free(body);                             /* release the fetched page     */
        close(client_fd);
    }

    close(server_fd);
    curl_global_cleanup();
    return 0;
}
