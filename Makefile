# Build both servers. Run `make` to compile, `make clean` to remove binaries.

CFLAGS = -Wall -Wextra -O2          # Warnings on, optimize a bit
CXXFLAGS = -Wall -Wextra -O2 -std=c++17

all: server_c server_cpp           # `make` builds both targets

server_c: server.c                 # Compile the C server
	$(CC) $(CFLAGS) -o server_c server.c

server_cpp: server.cpp             # Compile the C++ server
	$(CXX) $(CXXFLAGS) -o server_cpp server.cpp

clean:                             # Remove built binaries
	rm -f server_c server_cpp

.PHONY: all clean
