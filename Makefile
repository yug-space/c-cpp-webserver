# Build the native macOS browser app. Run `make`, then `make run-browser`.

OBJCFLAGS = -Wall -Wextra -O2 -fobjc-arc
APP_NAME = TrailBrowser
APP_BUNDLE = $(APP_NAME).app
APP_BIN = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
APP_PLIST = $(APP_BUNDLE)/Contents/Info.plist
MCP_DIR = mcp-history-server

all: mini_browser

mini_browser: $(APP_BIN) $(APP_PLIST) # Build native macOS WebKit browser app

$(APP_BIN): mac-browser/Browser.m
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	$(CC) $(OBJCFLAGS) -framework Cocoa -framework WebKit -o $(APP_BIN) mac-browser/Browser.m

$(APP_PLIST): mac-browser/Info.plist
	mkdir -p $(APP_BUNDLE)/Contents
	cp mac-browser/Info.plist $(APP_PLIST)

run-browser: mini_browser           # Open the native app
	open $(APP_BUNDLE)

mcp-install:                       # Install MCP server dependencies
	cd $(MCP_DIR) && npm install

run-history-mcp:                   # Run read-only history MCP server over stdio
	cd $(MCP_DIR) && npm start

clean:                             # Remove built binaries
	rm -rf $(APP_BUNDLE)

.PHONY: all mini_browser run-browser mcp-install run-history-mcp clean
