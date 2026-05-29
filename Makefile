# Build both servers. Run `make` to compile, `make clean` to remove binaries.

CFLAGS = -Wall -Wextra -O2          # Warnings on, optimize a bit
CXXFLAGS = -Wall -Wextra -O2 -std=c++17

all: server_c server_cpp proxy_c proxy_cpp   # `make` builds everything

server_c: server.c                 # Compile the C server
	$(CC) $(CFLAGS) -o server_c server.c

server_cpp: server.cpp             # Compile the C++ server
	$(CXX) $(CXXFLAGS) -o server_cpp server.cpp

proxy_c: proxy.c                   # Compile the C proxy (needs libcurl)
	$(CC) $(CFLAGS) -o proxy_c proxy.c -lcurl

proxy_cpp: proxy.cpp               # Compile the C++ proxy (needs libcurl)
	$(CXX) $(CXXFLAGS) -o proxy_cpp proxy.cpp -lcurl

clean:                             # Remove built binaries
	rm -f server_c server_cpp proxy_c proxy_cpp

.PHONY: all clean
