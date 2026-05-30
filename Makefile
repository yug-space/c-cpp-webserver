# Build both servers. Run `make` to compile, `make clean` to remove binaries.

CFLAGS = -Wall -Wextra -O2          # Warnings on, optimize a bit
CXXFLAGS = -Wall -Wextra -O2 -std=c++17
OBJCFLAGS = -Wall -Wextra -O2 -fobjc-arc
APP_NAME = MiniBrowser
APP_BUNDLE = $(APP_NAME).app
APP_BIN = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
APP_PLIST = $(APP_BUNDLE)/Contents/Info.plist

all: server_c server_cpp proxy_c proxy_cpp mini_browser   # `make` builds everything

server_c: server.c                 # Compile the C server
	$(CC) $(CFLAGS) -o server_c server.c

server_cpp: server.cpp             # Compile the C++ server
	$(CXX) $(CXXFLAGS) -o server_cpp server.cpp

proxy_c: proxy.c                   # Compile the C proxy (needs libcurl)
	$(CC) $(CFLAGS) -o proxy_c proxy.c -lcurl

proxy_cpp: proxy.cpp               # Compile the C++ proxy (needs libcurl)
	$(CXX) $(CXXFLAGS) -o proxy_cpp proxy.cpp -lcurl

mini_browser: $(APP_BIN) $(APP_PLIST) # Build native macOS WebKit browser app

$(APP_BIN): mac-browser/Browser.m
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	$(CC) $(OBJCFLAGS) -framework Cocoa -framework WebKit -o $(APP_BIN) mac-browser/Browser.m

$(APP_PLIST): mac-browser/Info.plist
	mkdir -p $(APP_BUNDLE)/Contents
	cp mac-browser/Info.plist $(APP_PLIST)

run-browser: mini_browser           # Open the native app
	open $(APP_BUNDLE)

clean:                             # Remove built binaries
	rm -f server_c server_cpp proxy_c proxy_cpp
	rm -rf $(APP_BUNDLE)

.PHONY: all mini_browser run-browser clean
