/* server.c — A minimal HTTP/1.1 web server written in C using POSIX sockets. */

#include <stdio.h>      /* printf, perror — console output and error reporting   */
#include <stdlib.h>     /* exit, EXIT_FAILURE — process control                  */
#include <string.h>     /* memset, strlen — buffer setup and string length       */
#include <unistd.h>     /* read, write, close — file-descriptor I/O              */
#include <arpa/inet.h>  /* socket, bind, listen, accept, htons, sockaddr_in      */

#define PORT 8080       /* TCP port the server listens on                        */
#define BACKLOG 10      /* Max number of pending connections in the accept queue */

int main(void) {
    /* 1. Create a TCP socket.
     *    AF_INET     = IPv4 address family.
     *    SOCK_STREAM = a reliable, ordered byte stream (TCP).
     *    0           = let the kernel pick the default protocol (TCP for STREAM).
     *    Returns a file descriptor (a small int) or -1 on failure.            */
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");          /* Print "socket: <reason>" to stderr.       */
        exit(EXIT_FAILURE);        /* Stop: without a socket we can't continue. */
    }

    /* 2. Allow the address to be reused immediately after the program exits.
     *    Without SO_REUSEADDR the port can sit in TIME_WAIT for ~minutes,
     *    causing "Address already in use" on a quick restart.                  */
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    /* 3. Describe the address we want to bind to.
     *    sockaddr_in is the IPv4 form of a socket address.                     */
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));   /* Zero every field first.         */
    address.sin_family = AF_INET;           /* IPv4, must match the socket.    */
    address.sin_addr.s_addr = INADDR_ANY;   /* Accept connections on any local
                                               interface (0.0.0.0).            */
    address.sin_port = htons(PORT);         /* Port number in network byte
                                               order (big-endian). htons =
                                               "host TO network short".        */

    /* 4. Bind the socket to that address/port — claim the port for ourselves. */
    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind");
        exit(EXIT_FAILURE);
    }

    /* 5. Switch the socket into listening mode so it can accept connections.
     *    BACKLOG bounds how many not-yet-accepted connections may queue up.    */
    if (listen(server_fd, BACKLOG) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    printf("C server listening on http://localhost:%d\n", PORT);

    /* 6. The HTTP response we send to every client. A valid HTTP/1.1 response
     *    is: status line, headers, a blank line, then the body.
     *    Content-Length tells the client exactly how many body bytes follow.
     *    Connection: close tells the client we hang up after responding.       */
    const char *body =
        "<!DOCTYPE html><html><body><h1>Hello from C!</h1></body></html>";
    char response[512];
    int response_len = snprintf(
        response, sizeof(response),
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/html\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n"
        "\r\n"
        "%s",
        strlen(body), body);

    /* 7. Serve forever: accept one client at a time, reply, close, repeat.     */
    while (1) {
        /* accept() blocks until a client connects, then returns a NEW socket
         * dedicated to that one client. server_fd keeps listening.             */
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) {
            perror("accept");
            continue;              /* Skip this one; keep the server alive.     */
        }

        /* Read the client's HTTP request into a buffer. We don't parse it —
         * we reply the same way regardless — but we must drain it so the
         * client's write completes cleanly.                                    */
        char buffer[4096];
        read(client_fd, buffer, sizeof(buffer) - 1);

        /* Write our fixed response back to this client.                        */
        write(client_fd, response, response_len);

        /* Close this client's socket; the browser then renders the page.       */
        close(client_fd);
    }

    /* Unreachable in this demo, but closing the listening socket is correct.   */
    close(server_fd);
    return 0;
}
