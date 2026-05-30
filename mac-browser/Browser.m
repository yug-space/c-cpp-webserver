// Browser.m - A small native macOS browser shell written in Objective-C.
//
// This is not a browser engine. It is the native application around Apple's
// WebKit engine: AppKit draws the window and controls, WKWebView renders pages.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface BrowserAppDelegate : NSObject <NSApplicationDelegate, NSSearchFieldDelegate, WKNavigationDelegate, WKUIDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSSearchField *addressField;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *forwardButton;
@property (nonatomic, strong) NSButton *reloadButton;
@property (nonatomic, strong) NSProgressIndicator *progressBar;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, copy) NSString *lastRecordedURL;
@end

@implementation BrowserAppDelegate

static void *BrowserProgressContext = &BrowserProgressContext;
static void *BrowserURLContext = &BrowserURLContext;
static void *BrowserCanGoBackContext = &BrowserCanGoBackContext;
static void *BrowserCanGoForwardContext = &BrowserCanGoForwardContext;

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    [self buildMenu];
    [self buildWindow];
    [self writeBrowserStateRunning:YES];
    [self loadURLString:@"https://www.google.com"];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self writeBrowserStateRunning:NO];
}

- (void)dealloc {
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    [self.webView removeObserver:self forKeyPath:@"URL"];
    [self.webView removeObserver:self forKeyPath:@"canGoBack"];
    [self.webView removeObserver:self forKeyPath:@"canGoForward"];
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"MiniBrowser"
                                                         action:nil
                                                  keyEquivalent:@""];
    [mainMenu addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"MiniBrowser"];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit MiniBrowser"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [appMenuItem setSubmenu:appMenu];

    NSMenuItem *navMenuItem = [[NSMenuItem alloc] initWithTitle:@"Navigate"
                                                         action:nil
                                                  keyEquivalent:@""];
    [mainMenu addItem:navMenuItem];

    NSMenu *navMenu = [[NSMenu alloc] initWithTitle:@"Navigate"];
    [self addMenuItem:@"Open Location" action:@selector(focusAddressBar:) key:@"l" menu:navMenu];
    [self addMenuItem:@"Reload" action:@selector(reloadPage:) key:@"r" menu:navMenu];
    [navMenu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"Back" action:@selector(goBack:) key:@"[" menu:navMenu];
    [self addMenuItem:@"Forward" action:@selector(goForward:) key:@"]" menu:navMenu];
    [navMenuItem setSubmenu:navMenu];

    [NSApp setMainMenu:mainMenu];
}

- (void)addMenuItem:(NSString *)title action:(SEL)action key:(NSString *)key menu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.target = self;
    item.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItem:item];
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 1200, 760);
    NSWindowStyleMask style = NSWindowStyleMaskTitled |
                              NSWindowStyleMaskClosable |
                              NSWindowStyleMaskMiniaturizable |
                              NSWindowStyleMaskResizable |
                              NSWindowStyleMaskFullSizeContentView;

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"MiniBrowser";
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.titlebarAppearsTransparent = YES;
    self.window.minSize = NSMakeSize(860, 560);
    [self.window center];

    NSView *root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    self.window.contentView = root;

    NSVisualEffectView *toolbar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    toolbar.material = NSVisualEffectMaterialHeaderView;
    toolbar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    toolbar.state = NSVisualEffectStateActive;
    [root addSubview:toolbar];

    self.backButton = [self toolbarButtonWithSymbol:@"chevron.left"
                                           fallback:@"<"
                                            tooltip:@"Back"
                                             action:@selector(goBack:)];
    self.forwardButton = [self toolbarButtonWithSymbol:@"chevron.right"
                                              fallback:@">"
                                               tooltip:@"Forward"
                                                action:@selector(goForward:)];
    self.reloadButton = [self toolbarButtonWithSymbol:@"arrow.clockwise"
                                             fallback:@"R"
                                              tooltip:@"Reload"
                                               action:@selector(reloadPage:)];

    self.addressField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    self.addressField.translatesAutoresizingMaskIntoConstraints = NO;
    self.addressField.placeholderString = @"Search or enter website name";
    self.addressField.delegate = self;
    self.addressField.target = self;
    self.addressField.action = @selector(loadFromAddressField:);
    self.addressField.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightRegular];
    self.addressField.controlSize = NSControlSizeLarge;

    self.statusLabel = [NSTextField labelWithString:@"Ready"];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    self.statusLabel.alignment = NSTextAlignmentRight;

    self.progressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressBar.indeterminate = NO;
    self.progressBar.minValue = 0.0;
    self.progressBar.maxValue = 1.0;
    self.progressBar.doubleValue = 0.0;
    self.progressBar.hidden = YES;
    self.progressBar.controlSize = NSControlSizeSmall;

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;
    [root addSubview:self.webView];

    for (NSView *view in @[ self.backButton, self.forwardButton, self.reloadButton,
                           self.addressField, self.statusLabel, self.progressBar ]) {
        [toolbar addSubview:view];
    }

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:root.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:72.0],

        [self.backButton.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:88.0],
        [self.backButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor constant:7.0],
        [self.forwardButton.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:8.0],
        [self.forwardButton.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
        [self.reloadButton.leadingAnchor constraintEqualToAnchor:self.forwardButton.trailingAnchor constant:8.0],
        [self.reloadButton.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],

        [self.addressField.leadingAnchor constraintEqualToAnchor:self.reloadButton.trailingAnchor constant:14.0],
        [self.addressField.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
        [self.addressField.heightAnchor constraintEqualToConstant:34.0],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.addressField.trailingAnchor constant:14.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-18.0],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.addressField.centerYAnchor],
        [self.statusLabel.widthAnchor constraintGreaterThanOrEqualToConstant:96.0],

        [self.progressBar.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor],
        [self.progressBar.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor],
        [self.progressBar.bottomAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [self.progressBar.heightAnchor constraintEqualToConstant:2.0],

        [self.webView.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
    ]];

    [self.webView addObserver:self
                   forKeyPath:@"estimatedProgress"
                      options:NSKeyValueObservingOptionNew
                      context:BrowserProgressContext];
    [self.webView addObserver:self
                   forKeyPath:@"URL"
                      options:NSKeyValueObservingOptionNew
                      context:BrowserURLContext];
    [self.webView addObserver:self
                   forKeyPath:@"canGoBack"
                      options:NSKeyValueObservingOptionNew
                      context:BrowserCanGoBackContext];
    [self.webView addObserver:self
                   forKeyPath:@"canGoForward"
                      options:NSKeyValueObservingOptionNew
                      context:BrowserCanGoForwardContext];

    [self updateControls];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSButton *)toolbarButtonWithSymbol:(NSString *)symbol
                             fallback:(NSString *)fallback
                              tooltip:(NSString *)tooltip
                               action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:@"" target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleRounded;
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    button.imagePosition = NSImageOnly;
    button.toolTip = tooltip;

    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tooltip];
        image.template = YES;
        button.image = image;
    }

    if (!button.image) {
        button.title = fallback;
        button.imagePosition = NSNoImage;
        button.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold];
    }

    [button.widthAnchor constraintEqualToConstant:34.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:30.0].active = YES;
    return button;
}

- (void)loadFromAddressField:(id)sender {
    (void)sender;
    [self loadURLString:self.addressField.stringValue];
}

- (void)loadURLString:(NSString *)input {
    NSURL *url = [self URLForUserInput:input];
    if (!url) {
        NSBeep();
        return;
    }

    self.addressField.stringValue = url.absoluteString;
    self.statusLabel.stringValue = @"Loading";
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (NSURL *)URLForUserInput:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return nil;

    NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
    if (components.scheme.length > 0) {
        return components.URL;
    }

    BOOL looksLocal = [trimmed hasPrefix:@"localhost"] ||
                      [trimmed hasPrefix:@"127."] ||
                      [trimmed hasPrefix:@"0.0.0.0"] ||
                      [trimmed hasPrefix:@"["];
    BOOL looksLikeURL = looksLocal ||
                        [trimmed containsString:@"."] ||
                        [trimmed containsString:@":"];

    if (looksLikeURL) {
        NSString *scheme = looksLocal ? @"http://" : @"https://";
        return [NSURL URLWithString:[scheme stringByAppendingString:trimmed]];
    }

    NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&+=?"];
    NSString *query = [trimmed stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    return [NSURL URLWithString:[@"https://www.google.com/search?q=" stringByAppendingString:query]];
}

- (NSString *)supportDirectoryPath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                                     NSUserDomainMask,
                                                                     YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    NSString *directory = [base stringByAppendingPathComponent:@"MiniBrowser"];

    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error) {
        NSLog(@"Could not create MiniBrowser support directory: %@", error.localizedDescription);
    }

    return directory;
}

- (NSString *)historyFilePath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"history.jsonl"];
}

- (NSString *)stateFilePath {
    return [[self supportDirectoryPath] stringByAppendingPathComponent:@"state.json"];
}

- (BOOL)isSensitiveQueryName:(NSString *)name {
    NSString *lower = name.lowercaseString;
    NSArray<NSString *> *markers = @[ @"token", @"secret", @"password", @"passwd",
                                      @"pass", @"auth", @"session", @"sid", @"key",
                                      @"credential", @"code" ];
    for (NSString *marker in markers) {
        if ([lower containsString:marker]) return YES;
    }
    return NO;
}

- (NSString *)redactedURLStringForURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (!components) return url.absoluteString ?: @"";

    NSMutableArray<NSURLQueryItem *> *redactedItems = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        NSString *value = [self isSensitiveQueryName:item.name] ? @"[redacted]" : item.value;
        [redactedItems addObject:[NSURLQueryItem queryItemWithName:item.name value:value]];
    }
    if (redactedItems.count > 0) {
        components.queryItems = redactedItems;
    }

    return components.URL.absoluteString ?: url.absoluteString ?: @"";
}

- (void)appendJSONLine:(NSDictionary<NSString *, id> *)entry toPath:(NSString *)path {
    if (![NSJSONSerialization isValidJSONObject:entry]) return;

    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:entry options:0 error:&error];
    if (!json) {
        NSLog(@"Could not encode JSON line: %@", error.localizedDescription);
        return;
    }

    NSMutableData *line = [json mutableCopy];
    const char newline = '\n';
    [line appendBytes:&newline length:1];

    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (![line writeToFile:path options:NSDataWritingAtomic error:&error]) {
            NSLog(@"Could not create %@: %@", path, error.localizedDescription);
        }
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return;
    @try {
        [handle seekToEndOfFile];
        [handle writeData:line];
    } @catch (NSException *exception) {
        NSLog(@"Could not append history: %@", exception.reason);
    } @finally {
        [handle closeFile];
    }
}

- (NSDateFormatter *)historyDateFormatter {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    return formatter;
}

- (void)recordHistoryEntryForWebView:(WKWebView *)webView {
    NSURL *url = webView.URL;
    if (!url) return;

    NSString *urlString = [self redactedURLStringForURL:url];
    if (urlString.length == 0) return;

    if ([self.lastRecordedURL isEqualToString:urlString]) return;
    self.lastRecordedURL = urlString;

    NSDictionary<NSString *, id> *entry = @{
        @"timestamp": [[self historyDateFormatter] stringFromDate:[NSDate date]],
        @"url": urlString,
        @"title": webView.title ?: @"",
        @"host": url.host ?: @"",
        @"source": @"MiniBrowser"
    };

    [self appendJSONLine:entry toPath:[self historyFilePath]];
}

- (void)writeBrowserStateRunning:(BOOL)running {
    NSDictionary<NSString *, id> *state = @{
        @"running": @(running),
        @"updatedAt": [[self historyDateFormatter] stringFromDate:[NSDate date]],
        @"historyFile": [self historyFilePath],
        @"cookiesExposed": @NO
    };

    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:state
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (!json) return;
    [json writeToFile:[self stateFilePath] options:NSDataWritingAtomic error:nil];
}

- (void)goBack:(id)sender {
    (void)sender;
    if (self.webView.canGoBack) [self.webView goBack];
}

- (void)goForward:(id)sender {
    (void)sender;
    if (self.webView.canGoForward) [self.webView goForward];
}

- (void)reloadPage:(id)sender {
    (void)sender;
    if (self.webView.loading) {
        [self.webView stopLoading];
    } else {
        [self.webView reload];
    }
}

- (void)focusAddressBar:(id)sender {
    (void)sender;
    [self.window makeFirstResponder:self.addressField];
    [self.addressField selectText:nil];
}

- (void)updateControls {
    self.backButton.enabled = self.webView.canGoBack;
    self.forwardButton.enabled = self.webView.canGoForward;

    BOOL loading = self.webView.loading;
    self.reloadButton.toolTip = loading ? @"Stop" : @"Reload";
    if (@available(macOS 11.0, *)) {
        NSString *symbol = loading ? @"xmark" : @"arrow.clockwise";
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:self.reloadButton.toolTip];
        image.template = YES;
        self.reloadButton.image = image;
    } else {
        self.reloadButton.title = loading ? @"X" : @"R";
    }

    self.progressBar.hidden = !loading;
    if (!loading) self.progressBar.doubleValue = 0.0;
}

- (void)syncAddressBarWithWebView {
    NSURL *url = self.webView.URL;
    if (url) self.addressField.stringValue = url.absoluteString;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    (void)object;
    (void)change;

    if (context == BrowserProgressContext) {
        double progress = self.webView.estimatedProgress;
        self.progressBar.doubleValue = progress;
        self.progressBar.hidden = !self.webView.loading || progress >= 1.0;
        return;
    }

    if (context == BrowserURLContext) {
        [self syncAddressBarWithWebView];
        return;
    }

    if (context == BrowserCanGoBackContext || context == BrowserCanGoForwardContext) {
        [self updateControls];
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    self.statusLabel.stringValue = @"Loading";
    [self updateControls];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    [self syncAddressBarWithWebView];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    self.statusLabel.stringValue = @"Ready";
    [self syncAddressBarWithWebView];
    [self recordHistoryEntryForWebView:self.webView];
    [self writeBrowserStateRunning:YES];
    [self updateControls];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    self.statusLabel.stringValue = error.localizedDescription ?: @"Failed";
    [self updateControls];
}

- (void)webView:(WKWebView *)webView
didFailProvisionalNavigation:(WKNavigation *)navigation
      withError:(NSError *)error {
    [self webView:webView didFailNavigation:navigation withError:error];
}

- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
    (void)configuration;
    (void)windowFeatures;

    if (!navigationAction.targetFrame) {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        BrowserAppDelegate *delegate = [[BrowserAppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }

    return 0;
}
