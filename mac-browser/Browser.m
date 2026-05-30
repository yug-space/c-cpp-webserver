// Browser.m - A small native macOS browser shell written in Objective-C.
//
// This is not a browser engine. It is the native application around Apple's
// WebKit engine: AppKit draws the window and controls, WKWebView renders pages.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#import "ChromeCookieImporter.h"

@interface BrowserTab : NSObject
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, copy) NSString *lastRecordedURL;
@property (nonatomic, strong) NSImage *favicon;
@property (nonatomic, copy) NSString *faviconURLString;
@property (nonatomic, copy) NSString *pendingFaviconURLString;
@end

@implementation BrowserTab
@end

@interface BrowserTabRowView : NSTableRowView
@end

@implementation BrowserTabRowView

- (void)drawBackgroundInRect:(NSRect)dirtyRect {
    [super drawBackgroundInRect:dirtyRect];
    if (!self.selected) return;

    NSRect fillRect = NSInsetRect(self.bounds, 3.0, 4.0);
    NSBezierPath *fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect
                                                             xRadius:7.0
                                                             yRadius:7.0];
    [[NSColor colorWithWhite:1.0 alpha:0.10] setFill];
    [fillPath fill];

    NSRect accentRect = NSMakeRect(NSMinX(fillRect) + 7.0,
                                   NSMidY(fillRect) - 8.0,
                                   2.0,
                                   16.0);
    NSBezierPath *accentPath = [NSBezierPath bezierPathWithRoundedRect:accentRect
                                                               xRadius:1.5
                                                               yRadius:1.5];
    [NSColor.controlAccentColor setFill];
    [accentPath fill];
}

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    (void)dirtyRect;
}

@end

@interface BrowserTabCellView : NSTableCellView
@property (nonatomic, strong) NSImageView *tabIconView;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *subtitleLabel;
@end

@implementation BrowserTabCellView
@end

@interface AssistantLauncherButton : NSButton
@end

@implementation AssistantLauncherButton

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.title = @"AI";
        self.toolTip = @"Open assistant";
        self.wantsLayer = YES;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = NSInsetRect(self.bounds, 1.0, 1.0);
    NSBezierPath *shape = [NSBezierPath bezierPathWithOvalInRect:bounds];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:0.05 green:0.72 blue:0.91 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.14 green:0.42 blue:0.96 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.58 green:0.25 blue:0.94 alpha:1.0]
    ]];
    [gradient drawInBezierPath:shape angle:35.0];

    [[NSColor colorWithWhite:1.0 alpha:0.22] setStroke];
    shape.lineWidth = 1.0;
    [shape stroke];

    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:16.0 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSAttributedString *label = [[NSAttributedString alloc] initWithString:@"AI"
                                                                attributes:attributes];
    NSSize labelSize = label.size;
    NSRect labelRect = NSMakeRect(NSMidX(self.bounds) - labelSize.width / 2.0,
                                  NSMidY(self.bounds) - labelSize.height / 2.0,
                                  labelSize.width,
                                  labelSize.height);
    [label drawInRect:labelRect];
}

@end

@interface BrowserAppDelegate : NSObject <NSApplicationDelegate, NSSearchFieldDelegate, WKNavigationDelegate, WKUIDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSView *webContainer;
@property (nonatomic, strong) NSVisualEffectView *sidebar;
@property (nonatomic, strong) NSBox *sidebarSeparator;
@property (nonatomic, strong) NSTableView *tabTable;
@property (nonatomic, strong) NSMutableArray<BrowserTab *> *tabs;
@property (nonatomic, strong) NSSearchField *addressField;
@property (nonatomic, strong) NSButton *backButton;
@property (nonatomic, strong) NSButton *forwardButton;
@property (nonatomic, strong) NSButton *sidebarToggleButton;
@property (nonatomic, strong) NSButton *reloadButton;
@property (nonatomic, strong) NSButton *homeButton;
@property (nonatomic, strong) NSButton *addTabButton;
@property (nonatomic, strong) NSButton *closeTabButton;
@property (nonatomic, strong) NSProgressIndicator *progressBar;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSVisualEffectView *assistantBar;
@property (nonatomic, strong) NSSegmentedControl *assistantModeControl;
@property (nonatomic, strong) NSTextField *assistantPromptField;
@property (nonatomic, strong) NSButton *assistantRunButton;
@property (nonatomic, strong) NSProgressIndicator *assistantSpinner;
@property (nonatomic, strong) NSVisualEffectView *assistantResultPanel;
@property (nonatomic, strong) NSTextView *assistantResultTextView;
@property (nonatomic, strong) NSButton *assistantResultCloseButton;
@property (nonatomic, strong) AssistantLauncherButton *assistantLauncherButton;
@property (nonatomic, strong) NSButton *assistantCollapseButton;
@property (nonatomic, strong) NSLayoutConstraint *sidebarWidthConstraint;
@property (nonatomic, copy) NSString *lastRecordedURL;
@property (nonatomic, assign) NSInteger activeTabIndex;
@property (nonatomic, assign) BOOL userEditingAddress;
@property (nonatomic, assign) BOOL sidebarVisible;
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
    [self newTabWithURLString:[self homeURLString] select:YES];
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
    for (BrowserTab *tab in self.tabs) {
        [self removeObserversFromWebView:tab.webView];
        [tab.webView stopLoading];
    }
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"TrailBrowser"
                                                         action:nil
                                                  keyEquivalent:@""];
    [mainMenu addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"TrailBrowser"];
    [self addMenuItem:@"Import Cookies from Chrome…"
               action:@selector(importChromeCookies:)
                  key:@""
                 menu:appMenu];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit TrailBrowser"
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
    [self addMenuItem:@"Toggle Sidebar" action:@selector(toggleSidebar:) key:@"b" menu:navMenu];
    [self addMenuItem:@"New Tab" action:@selector(newTab:) key:@"t" menu:navMenu];
    [self addMenuItem:@"Close Tab" action:@selector(closeCurrentTab:) key:@"w" menu:navMenu];
    [navMenu addItem:[NSMenuItem separatorItem]];
    [self addMenuItem:@"Home" action:@selector(goHome:) key:@"" menu:navMenu];
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
    self.tabs = [NSMutableArray array];
    self.activeTabIndex = -1;
    self.sidebarVisible = YES;

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
    self.window.title = @"TrailBrowser";
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.titlebarAppearsTransparent = YES;
    self.window.minSize = NSMakeSize(860, 560);
    if (@available(macOS 11.0, *)) {
        self.window.toolbarStyle = NSWindowToolbarStyleUnifiedCompact;
        self.window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
    }
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
    self.sidebarToggleButton = [self toolbarButtonWithSymbol:@"sidebar.left"
                                                    fallback:@"S"
                                                     tooltip:@"Toggle Sidebar"
                                                      action:@selector(toggleSidebar:)];
    self.reloadButton = [self toolbarButtonWithSymbol:@"arrow.clockwise"
                                             fallback:@"R"
                                              tooltip:@"Reload"
                                               action:@selector(reloadPage:)];
    self.homeButton = [self toolbarButtonWithSymbol:@"house"
                                           fallback:@"H"
                                            tooltip:@"Home"
                                             action:@selector(goHome:)];

    self.addressField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    self.addressField.translatesAutoresizingMaskIntoConstraints = NO;
    self.addressField.placeholderString = @"Search or enter website name";
    self.addressField.delegate = self;
    self.addressField.target = self;
    self.addressField.action = @selector(loadFromAddressField:);
    self.addressField.sendsSearchStringImmediately = NO;
    self.addressField.sendsWholeSearchString = YES;
    self.addressField.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightRegular];
    self.addressField.controlSize = NSControlSizeRegular;

    self.statusLabel = [NSTextField labelWithString:@"Ready"];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
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

    NSView *contentArea = [[NSView alloc] initWithFrame:NSZeroRect];
    contentArea.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:contentArea];

    self.sidebar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    self.sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebar.material = NSVisualEffectMaterialSidebar;
    self.sidebar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.sidebar.state = NSVisualEffectStateActive;
    [contentArea addSubview:self.sidebar];

    self.sidebarSeparator = [[NSBox alloc] initWithFrame:NSZeroRect];
    self.sidebarSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    self.sidebarSeparator.boxType = NSBoxSeparator;
    [contentArea addSubview:self.sidebarSeparator];

    self.webContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    self.webContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [contentArea addSubview:self.webContainer];
    [self buildAssistantOverlay];

    NSView *tabHeader = [[NSView alloc] initWithFrame:NSZeroRect];
    tabHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sidebar addSubview:tabHeader];

    NSTextField *tabTitle = [NSTextField labelWithString:@"Tabs"];
    tabTitle.translatesAutoresizingMaskIntoConstraints = NO;
    tabTitle.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold];
    tabTitle.textColor = NSColor.secondaryLabelColor;
    [tabHeader addSubview:tabTitle];

    self.addTabButton = [self sidebarButtonWithSymbol:@"plus"
                                             fallback:@"+"
                                              tooltip:@"New Tab"
                                               action:@selector(newTab:)];
    self.closeTabButton = [self sidebarButtonWithSymbol:@"xmark"
                                               fallback:@"x"
                                                tooltip:@"Close Tab"
                                                 action:@selector(closeCurrentTab:)];
    [tabHeader addSubview:self.addTabButton];
    [tabHeader addSubview:self.closeTabButton];

    self.tabTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tabTable.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabTable.headerView = nil;
    self.tabTable.rowHeight = 46.0;
    self.tabTable.intercellSpacing = NSMakeSize(0, 2);
    self.tabTable.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    self.tabTable.backgroundColor = NSColor.clearColor;
    self.tabTable.usesAlternatingRowBackgroundColors = NO;
    self.tabTable.allowsEmptySelection = NO;
    self.tabTable.focusRingType = NSFocusRingTypeNone;
    self.tabTable.dataSource = self;
    self.tabTable.delegate = self;

    NSTableColumn *tabColumn = [[NSTableColumn alloc] initWithIdentifier:@"TabColumn"];
    tabColumn.resizingMask = NSTableColumnAutoresizingMask;
    tabColumn.width = 200.0;
    [self.tabTable addTableColumn:tabColumn];

    NSScrollView *tabScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    tabScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    tabScrollView.documentView = self.tabTable;
    tabScrollView.hasVerticalScroller = YES;
    tabScrollView.autohidesScrollers = YES;
    tabScrollView.scrollerStyle = NSScrollerStyleOverlay;
    tabScrollView.borderType = NSNoBorder;
    tabScrollView.drawsBackground = NO;
    [self.sidebar addSubview:tabScrollView];

    for (NSView *view in @[ self.sidebarToggleButton, self.backButton, self.forwardButton, self.homeButton,
                           self.addressField, self.reloadButton, self.statusLabel, self.progressBar ]) {
        [toolbar addSubview:view];
    }

    self.sidebarWidthConstraint = [self.sidebar.widthAnchor constraintEqualToConstant:220.0];

    [NSLayoutConstraint activateConstraints:@[
        [toolbar.topAnchor constraintEqualToAnchor:root.topAnchor],
        [toolbar.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [toolbar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [toolbar.heightAnchor constraintEqualToConstant:54.0],

        [self.sidebarToggleButton.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor constant:88.0],
        [self.sidebarToggleButton.centerYAnchor constraintEqualToAnchor:toolbar.centerYAnchor],

        [self.backButton.leadingAnchor constraintEqualToAnchor:self.sidebarToggleButton.trailingAnchor constant:8.0],
        [self.backButton.centerYAnchor constraintEqualToAnchor:self.sidebarToggleButton.centerYAnchor],
        [self.forwardButton.leadingAnchor constraintEqualToAnchor:self.backButton.trailingAnchor constant:8.0],
        [self.forwardButton.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
        [self.homeButton.leadingAnchor constraintEqualToAnchor:self.forwardButton.trailingAnchor constant:8.0],
        [self.homeButton.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],

        [self.addressField.leadingAnchor constraintEqualToAnchor:self.homeButton.trailingAnchor constant:14.0],
        [self.addressField.centerYAnchor constraintEqualToAnchor:self.backButton.centerYAnchor],
        [self.addressField.heightAnchor constraintEqualToConstant:32.0],

        [self.reloadButton.leadingAnchor constraintEqualToAnchor:self.addressField.trailingAnchor constant:8.0],
        [self.reloadButton.centerYAnchor constraintEqualToAnchor:self.addressField.centerYAnchor],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.reloadButton.trailingAnchor constant:12.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor constant:-20.0],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:self.addressField.centerYAnchor],
        [self.statusLabel.widthAnchor constraintEqualToConstant:58.0],

        [self.progressBar.leadingAnchor constraintEqualToAnchor:toolbar.leadingAnchor],
        [self.progressBar.trailingAnchor constraintEqualToAnchor:toolbar.trailingAnchor],
        [self.progressBar.bottomAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [self.progressBar.heightAnchor constraintEqualToConstant:2.0],

        [contentArea.topAnchor constraintEqualToAnchor:toolbar.bottomAnchor],
        [contentArea.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [contentArea.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [contentArea.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],

        [self.sidebar.topAnchor constraintEqualToAnchor:contentArea.topAnchor],
        [self.sidebar.leadingAnchor constraintEqualToAnchor:contentArea.leadingAnchor],
        [self.sidebar.bottomAnchor constraintEqualToAnchor:contentArea.bottomAnchor],
        self.sidebarWidthConstraint,

        [self.sidebarSeparator.topAnchor constraintEqualToAnchor:contentArea.topAnchor],
        [self.sidebarSeparator.leadingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor],
        [self.sidebarSeparator.bottomAnchor constraintEqualToAnchor:contentArea.bottomAnchor],
        [self.sidebarSeparator.widthAnchor constraintEqualToConstant:1.0],

        [self.webContainer.topAnchor constraintEqualToAnchor:contentArea.topAnchor],
        [self.webContainer.leadingAnchor constraintEqualToAnchor:self.sidebarSeparator.trailingAnchor],
        [self.webContainer.trailingAnchor constraintEqualToAnchor:contentArea.trailingAnchor],
        [self.webContainer.bottomAnchor constraintEqualToAnchor:contentArea.bottomAnchor],

        [tabHeader.topAnchor constraintEqualToAnchor:self.sidebar.topAnchor constant:12.0],
        [tabHeader.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor constant:12.0],
        [tabHeader.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:-12.0],
        [tabHeader.heightAnchor constraintEqualToConstant:32.0],

        [tabTitle.leadingAnchor constraintEqualToAnchor:tabHeader.leadingAnchor],
        [tabTitle.centerYAnchor constraintEqualToAnchor:tabHeader.centerYAnchor],
        [tabTitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.addTabButton.leadingAnchor constant:-8.0],

        [self.closeTabButton.trailingAnchor constraintEqualToAnchor:tabHeader.trailingAnchor],
        [self.closeTabButton.centerYAnchor constraintEqualToAnchor:tabHeader.centerYAnchor],

        [self.addTabButton.trailingAnchor constraintEqualToAnchor:self.closeTabButton.leadingAnchor constant:-8.0],
        [self.addTabButton.centerYAnchor constraintEqualToAnchor:tabHeader.centerYAnchor],

        [tabScrollView.topAnchor constraintEqualToAnchor:tabHeader.bottomAnchor constant:6.0],
        [tabScrollView.leadingAnchor constraintEqualToAnchor:self.sidebar.leadingAnchor constant:8.0],
        [tabScrollView.trailingAnchor constraintEqualToAnchor:self.sidebar.trailingAnchor constant:-8.0],
        [tabScrollView.bottomAnchor constraintEqualToAnchor:self.sidebar.bottomAnchor constant:-10.0]
    ]];

    [self updateControls];
    self.window.initialFirstResponder = self.addressField;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    // Focus the address bar on launch so you can type a URL or search term
    // immediately, without having to click into it first.
    [self.window makeFirstResponder:self.addressField];
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
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = tooltip;

    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tooltip];
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:15.0
                                                                                             weight:NSFontWeightMedium];
        image = [image imageWithSymbolConfiguration:config] ?: image;
        image.template = YES;
        button.image = image;
    }

    if (!button.image) {
        button.title = fallback;
        button.imagePosition = NSNoImage;
        button.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold];
    }

    [button.widthAnchor constraintEqualToConstant:36.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:32.0].active = YES;
    return button;
}

- (NSButton *)sidebarButtonWithSymbol:(NSString *)symbol
                              fallback:(NSString *)fallback
                               tooltip:(NSString *)tooltip
                                action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:@"" target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleRounded;
    [button setButtonType:NSButtonTypeMomentaryPushIn];
    button.imagePosition = NSImageOnly;
    button.imageScaling = NSImageScaleProportionallyDown;
    button.toolTip = tooltip;

    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tooltip];
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                             weight:NSFontWeightSemibold];
        image = [image imageWithSymbolConfiguration:config] ?: image;
        image.template = YES;
        button.image = image;
    }

    if (!button.image) {
        button.title = fallback;
        button.imagePosition = NSNoImage;
        button.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    }

    [button.widthAnchor constraintEqualToConstant:32.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:28.0].active = YES;
    return button;
}

- (void)buildAssistantOverlay {
    self.assistantBar = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    self.assistantBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantBar.material = NSVisualEffectMaterialHUDWindow;
    self.assistantBar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.assistantBar.state = NSVisualEffectStateActive;
    self.assistantBar.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    self.assistantBar.wantsLayer = YES;
    self.assistantBar.layer.cornerRadius = 14.0;
    self.assistantBar.layer.masksToBounds = YES;
    self.assistantBar.layer.borderWidth = 1.0;
    self.assistantBar.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.18].CGColor;
    self.assistantBar.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.08 alpha:0.88].CGColor;
    self.assistantBar.hidden = YES;
    [self.webContainer addSubview:self.assistantBar];

    self.assistantModeControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    self.assistantModeControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantModeControl.segmentCount = 2;
    [self.assistantModeControl setLabel:@"Ask" forSegment:0];
    [self.assistantModeControl setLabel:@"Edit" forSegment:1];
    [self.assistantModeControl setWidth:52.0 forSegment:0];
    [self.assistantModeControl setWidth:52.0 forSegment:1];
    self.assistantModeControl.selectedSegment = 0;
    self.assistantModeControl.target = self;
    self.assistantModeControl.action = @selector(assistantModeChanged:);
    self.assistantModeControl.controlSize = NSControlSizeSmall;
    [self.assistantBar addSubview:self.assistantModeControl];

    self.assistantPromptField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.assistantPromptField.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantPromptField.placeholderString = @"Ask about this page";
    self.assistantPromptField.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    self.assistantPromptField.controlSize = NSControlSizeRegular;
    self.assistantPromptField.textColor = NSColor.labelColor;
    self.assistantPromptField.target = self;
    self.assistantPromptField.action = @selector(runPageAssistant:);
    [self.assistantBar addSubview:self.assistantPromptField];

    self.assistantSpinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.assistantSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantSpinner.style = NSProgressIndicatorStyleSpinning;
    self.assistantSpinner.controlSize = NSControlSizeSmall;
    self.assistantSpinner.displayedWhenStopped = NO;
    self.assistantSpinner.hidden = YES;
    [self.assistantBar addSubview:self.assistantSpinner];

    self.assistantRunButton = [self toolbarButtonWithSymbol:@"arrow.up"
                                                   fallback:@"Go"
                                                    tooltip:@"Run"
                                                     action:@selector(runPageAssistant:)];
    [self.assistantBar addSubview:self.assistantRunButton];

    self.assistantCollapseButton = [self sidebarButtonWithSymbol:@"xmark"
                                                        fallback:@"x"
                                                         tooltip:@"Collapse"
                                                          action:@selector(collapseAssistant:)];
    [self.assistantBar addSubview:self.assistantCollapseButton];

    self.assistantResultPanel = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    self.assistantResultPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantResultPanel.material = NSVisualEffectMaterialHUDWindow;
    self.assistantResultPanel.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.assistantResultPanel.state = NSVisualEffectStateActive;
    self.assistantResultPanel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    self.assistantResultPanel.hidden = YES;
    self.assistantResultPanel.wantsLayer = YES;
    self.assistantResultPanel.layer.cornerRadius = 14.0;
    self.assistantResultPanel.layer.masksToBounds = YES;
    self.assistantResultPanel.layer.borderWidth = 1.0;
    self.assistantResultPanel.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.18].CGColor;
    self.assistantResultPanel.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.08 alpha:0.92].CGColor;
    [self.webContainer addSubview:self.assistantResultPanel positioned:NSWindowBelow relativeTo:self.assistantBar];

    self.assistantLauncherButton = [[AssistantLauncherButton alloc] initWithFrame:NSZeroRect];
    self.assistantLauncherButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.assistantLauncherButton.target = self;
    self.assistantLauncherButton.action = @selector(openAssistant:);
    [self.webContainer addSubview:self.assistantLauncherButton positioned:NSWindowAbove relativeTo:self.assistantBar];

    self.assistantResultCloseButton = [self sidebarButtonWithSymbol:@"xmark"
                                                           fallback:@"x"
                                                            tooltip:@"Close"
                                                             action:@selector(closeAssistantResult:)];
    [self.assistantResultPanel addSubview:self.assistantResultCloseButton];

    NSScrollView *resultScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    resultScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    resultScrollView.borderType = NSNoBorder;
    resultScrollView.drawsBackground = NO;
    resultScrollView.hasVerticalScroller = YES;
    resultScrollView.autohidesScrollers = YES;
    resultScrollView.scrollerStyle = NSScrollerStyleOverlay;
    [self.assistantResultPanel addSubview:resultScrollView];

    self.assistantResultTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.assistantResultTextView.editable = NO;
    self.assistantResultTextView.selectable = YES;
    self.assistantResultTextView.drawsBackground = NO;
    self.assistantResultTextView.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    self.assistantResultTextView.textColor = NSColor.labelColor;
    self.assistantResultTextView.textContainerInset = NSMakeSize(0.0, 2.0);
    resultScrollView.documentView = self.assistantResultTextView;

    [NSLayoutConstraint activateConstraints:@[
        [self.assistantBar.centerXAnchor constraintEqualToAnchor:self.webContainer.centerXAnchor],
        [self.assistantBar.bottomAnchor constraintEqualToAnchor:self.webContainer.bottomAnchor constant:-18.0],
        [self.assistantBar.widthAnchor constraintLessThanOrEqualToConstant:760.0],
        [self.assistantBar.widthAnchor constraintGreaterThanOrEqualToConstant:620.0],
        [self.assistantBar.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.webContainer.leadingAnchor constant:28.0],
        [self.assistantBar.trailingAnchor constraintLessThanOrEqualToAnchor:self.webContainer.trailingAnchor constant:-28.0],
        [self.assistantBar.heightAnchor constraintEqualToConstant:48.0],

        [self.assistantModeControl.leadingAnchor constraintEqualToAnchor:self.assistantBar.leadingAnchor constant:10.0],
        [self.assistantModeControl.centerYAnchor constraintEqualToAnchor:self.assistantBar.centerYAnchor],
        [self.assistantModeControl.widthAnchor constraintEqualToConstant:108.0],
        [self.assistantModeControl.heightAnchor constraintEqualToConstant:28.0],

        [self.assistantPromptField.leadingAnchor constraintEqualToAnchor:self.assistantModeControl.trailingAnchor constant:10.0],
        [self.assistantPromptField.centerYAnchor constraintEqualToAnchor:self.assistantBar.centerYAnchor],
        [self.assistantPromptField.heightAnchor constraintEqualToConstant:30.0],

        [self.assistantSpinner.leadingAnchor constraintEqualToAnchor:self.assistantPromptField.trailingAnchor constant:8.0],
        [self.assistantSpinner.centerYAnchor constraintEqualToAnchor:self.assistantBar.centerYAnchor],
        [self.assistantSpinner.widthAnchor constraintEqualToConstant:18.0],
        [self.assistantSpinner.heightAnchor constraintEqualToConstant:18.0],

        [self.assistantCollapseButton.leadingAnchor constraintEqualToAnchor:self.assistantSpinner.trailingAnchor constant:8.0],
        [self.assistantCollapseButton.centerYAnchor constraintEqualToAnchor:self.assistantBar.centerYAnchor],

        [self.assistantRunButton.leadingAnchor constraintEqualToAnchor:self.assistantCollapseButton.trailingAnchor constant:8.0],
        [self.assistantRunButton.trailingAnchor constraintEqualToAnchor:self.assistantBar.trailingAnchor constant:-10.0],
        [self.assistantRunButton.centerYAnchor constraintEqualToAnchor:self.assistantBar.centerYAnchor],

        [self.assistantLauncherButton.trailingAnchor constraintEqualToAnchor:self.webContainer.trailingAnchor constant:-24.0],
        [self.assistantLauncherButton.bottomAnchor constraintEqualToAnchor:self.webContainer.bottomAnchor constant:-24.0],
        [self.assistantLauncherButton.widthAnchor constraintEqualToConstant:58.0],
        [self.assistantLauncherButton.heightAnchor constraintEqualToConstant:58.0],

        [self.assistantResultPanel.centerXAnchor constraintEqualToAnchor:self.assistantBar.centerXAnchor],
        [self.assistantResultPanel.widthAnchor constraintEqualToAnchor:self.assistantBar.widthAnchor],
        [self.assistantResultPanel.bottomAnchor constraintEqualToAnchor:self.assistantBar.topAnchor constant:-10.0],
        [self.assistantResultPanel.heightAnchor constraintEqualToConstant:220.0],

        [self.assistantResultCloseButton.topAnchor constraintEqualToAnchor:self.assistantResultPanel.topAnchor constant:10.0],
        [self.assistantResultCloseButton.trailingAnchor constraintEqualToAnchor:self.assistantResultPanel.trailingAnchor constant:-10.0],

        [resultScrollView.topAnchor constraintEqualToAnchor:self.assistantResultPanel.topAnchor constant:12.0],
        [resultScrollView.leadingAnchor constraintEqualToAnchor:self.assistantResultPanel.leadingAnchor constant:14.0],
        [resultScrollView.trailingAnchor constraintEqualToAnchor:self.assistantResultCloseButton.leadingAnchor constant:-8.0],
        [resultScrollView.bottomAnchor constraintEqualToAnchor:self.assistantResultPanel.bottomAnchor constant:-12.0]
    ]];
}

- (WKWebView *)createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration {
    WKWebViewConfiguration *config = configuration ?: [[WKWebViewConfiguration alloc] init];
    [self configureForLowMemory:config];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.allowsBackForwardNavigationGestures = YES;
    webView.hidden = YES;
    if (self.assistantResultPanel) {
        [self.webContainer addSubview:webView positioned:NSWindowBelow relativeTo:self.assistantResultPanel];
    } else {
        [self.webContainer addSubview:webView];
    }

    [NSLayoutConstraint activateConstraints:@[
        [webView.topAnchor constraintEqualToAnchor:self.webContainer.topAnchor],
        [webView.leadingAnchor constraintEqualToAnchor:self.webContainer.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:self.webContainer.trailingAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:self.webContainer.bottomAnchor]
    ]];

    if (self.assistantResultPanel) {
        [self.webContainer addSubview:self.assistantResultPanel positioned:NSWindowAbove relativeTo:webView];
        [self.webContainer addSubview:self.assistantBar positioned:NSWindowAbove relativeTo:self.assistantResultPanel];
        [self.webContainer addSubview:self.assistantLauncherButton positioned:NSWindowAbove relativeTo:self.assistantBar];
    }

    [self addObserversToWebView:webView];
    return webView;
}

- (void)addObserversToWebView:(WKWebView *)webView {
    [webView addObserver:self
              forKeyPath:@"estimatedProgress"
                 options:NSKeyValueObservingOptionNew
                 context:BrowserProgressContext];
    [webView addObserver:self
              forKeyPath:@"URL"
                 options:NSKeyValueObservingOptionNew
                 context:BrowserURLContext];
    [webView addObserver:self
              forKeyPath:@"canGoBack"
                 options:NSKeyValueObservingOptionNew
                 context:BrowserCanGoBackContext];
    [webView addObserver:self
              forKeyPath:@"canGoForward"
                 options:NSKeyValueObservingOptionNew
                 context:BrowserCanGoForwardContext];
}

- (void)removeObserversFromWebView:(WKWebView *)webView {
    if (!webView) return;
    @try {
        [webView removeObserver:self forKeyPath:@"estimatedProgress"];
        [webView removeObserver:self forKeyPath:@"URL"];
        [webView removeObserver:self forKeyPath:@"canGoBack"];
        [webView removeObserver:self forKeyPath:@"canGoForward"];
    } @catch (NSException *exception) {
        (void)exception;
    }
}

- (void)configureForLowMemory:(WKWebViewConfiguration *)configuration {
    configuration.suppressesIncrementalRendering = YES;
    configuration.allowsAirPlayForMediaPlayback = NO;
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
}

- (BrowserTab *)newTabWithURLString:(NSString *)urlString select:(BOOL)select {
    return [self newTabWithConfiguration:nil URLString:urlString select:select];
}

- (BrowserTab *)newTabWithConfiguration:(WKWebViewConfiguration *)configuration
                              URLString:(NSString *)urlString
                                 select:(BOOL)select {
    BrowserTab *tab = [[BrowserTab alloc] init];
    tab.title = @"New Tab";
    tab.urlString = urlString ?: [self homeURLString];
    if (configuration) tab.webView = [self createWebViewWithConfiguration:configuration];
    [self.tabs addObject:tab];
    [self.tabTable reloadData];

    NSInteger index = (NSInteger)self.tabs.count - 1;
    if (select) [self selectTabAtIndex:index];

    return tab;
}

- (BrowserTab *)activeTab {
    if (self.activeTabIndex < 0 || self.activeTabIndex >= (NSInteger)self.tabs.count) return nil;
    return self.tabs[(NSUInteger)self.activeTabIndex];
}

- (BrowserTab *)tabForWebView:(WKWebView *)webView {
    for (BrowserTab *tab in self.tabs) {
        if (tab.webView == webView) return tab;
    }
    return nil;
}

- (WKWebView *)ensureWebViewForTab:(BrowserTab *)tab {
    if (!tab.webView) {
        tab.webView = [self createWebViewWithConfiguration:nil];
    }
    return tab.webView;
}

- (void)sleepTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) return;

    BrowserTab *tab = self.tabs[(NSUInteger)index];
    WKWebView *webView = tab.webView;
    if (!webView) return;

    if (webView.URL.absoluteString.length > 0) tab.urlString = webView.URL.absoluteString;
    if (webView.title.length > 0) tab.title = webView.title;

    [webView stopLoading];
    [self removeObserversFromWebView:webView];
    [webView removeFromSuperview];
    tab.webView = nil;
}

- (void)selectTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabs.count) return;
    if (index == self.activeTabIndex && self.webView == self.tabs[(NSUInteger)index].webView) return;

    NSInteger previousIndex = self.activeTabIndex;
    self.webView.hidden = YES;
    self.activeTabIndex = index;
    BrowserTab *tab = [self activeTab];
    self.webView = [self ensureWebViewForTab:tab];
    self.webView.hidden = NO;

    if (previousIndex >= 0 && previousIndex != index) {
        [self sleepTabAtIndex:previousIndex];
    }

    NSIndexSet *selection = [NSIndexSet indexSetWithIndex:(NSUInteger)index];
    [self.tabTable selectRowIndexes:selection byExtendingSelection:NO];
    [self.tabTable scrollRowToVisible:index];
    if (self.tabs.count > 0) {
        NSIndexSet *rows = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.tabs.count)];
        NSIndexSet *columns = [NSIndexSet indexSetWithIndex:0];
        [self.tabTable reloadDataForRowIndexes:rows columnIndexes:columns];
    }

    if (self.webView.URL == nil && tab.urlString.length > 0) {
        if ([self isHomeURLString:tab.urlString]) {
            [self loadNativeHomePageInWebView:self.webView];
        } else {
            NSURL *url = [self URLForUserInput:tab.urlString];
            if (url) [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }

    if (self.webView.URL) {
        [self syncAddressBarWithWebView];
    } else if (tab.urlString.length > 0) {
        self.addressField.stringValue = tab.urlString;
    }
    [self updateControls];
    self.statusLabel.stringValue = self.webView.loading ? @"Loading" : @"Ready";
    self.progressBar.doubleValue = self.webView.estimatedProgress;
    self.progressBar.hidden = !self.webView.loading || self.webView.estimatedProgress >= 1.0;
}

- (void)newTab:(id)sender {
    (void)sender;
    [self newTabWithURLString:[self homeURLString] select:YES];
}

- (void)closeCurrentTab:(id)sender {
    (void)sender;
    if (self.tabs.count == 0) return;

    NSInteger closingIndex = self.activeTabIndex;
    if (closingIndex < 0 || closingIndex >= (NSInteger)self.tabs.count) closingIndex = 0;
    BrowserTab *closingTab = self.tabs[(NSUInteger)closingIndex];

    [self removeObserversFromWebView:closingTab.webView];
    [closingTab.webView stopLoading];
    [closingTab.webView removeFromSuperview];
    [self.tabs removeObjectAtIndex:(NSUInteger)closingIndex];
    [self.tabTable reloadData];

    self.webView = nil;
    self.activeTabIndex = -1;

    if (self.tabs.count == 0) {
        [self newTabWithURLString:[self homeURLString] select:YES];
        return;
    }

    NSInteger nextIndex = MIN(closingIndex, (NSInteger)self.tabs.count - 1);
    [self selectTabAtIndex:nextIndex];
}

- (void)loadFromAddressField:(id)sender {
    (void)sender;
    self.userEditingAddress = NO;
    [self loadURLString:self.addressField.stringValue];
}

- (void)loadURLString:(NSString *)input {
    if (!self.webView) {
        [self newTabWithURLString:input select:YES];
        return;
    }

    if ([self isHomeURLString:input]) {
        [self loadNativeHomePageInWebView:self.webView];
        return;
    }

    NSURL *url = [self URLForUserInput:input];
    if (!url) {
        NSBeep();
        return;
    }

    self.addressField.stringValue = url.absoluteString;
    BrowserTab *tab = [self activeTab];
    tab.urlString = url.absoluteString;
    self.statusLabel.stringValue = @"Loading";
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (NSString *)homeURLString {
    return @"trailbrowser://home";
}

- (BOOL)isHomeURLString:(NSString *)input {
    NSString *trimmed = [[input ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return [trimmed isEqualToString:@"trailbrowser://home"] ||
           [trimmed isEqualToString:@"trailbrowser://home/"] ||
           [trimmed isEqualToString:@"about:trailbrowser"];
}

- (NSString *)nativeHomeHTML {
    NSURL *homeURL = [[NSBundle mainBundle] URLForResource:@"Home"
                                             withExtension:@"html"
                                              subdirectory:@"home"];
    NSError *error = nil;
    NSString *html = homeURL ? [NSString stringWithContentsOfURL:homeURL
                                                        encoding:NSUTF8StringEncoding
                                                           error:&error] : nil;
    if (html.length > 0) return html;

    NSLog(@"Could not load home page resource: %@", error.localizedDescription);
    return @"<!doctype html><title>TrailBrowser</title><body><h1>TrailBrowser</h1></body>";
}

- (NSURL *)nativeHomeBaseURL {
    NSURL *homeURL = [[NSBundle mainBundle] URLForResource:@"Home"
                                             withExtension:@"html"
                                              subdirectory:@"home"];
    return homeURL.URLByDeletingLastPathComponent ?: [NSURL URLWithString:[self homeURLString]];
}

- (BOOL)isNativeHomeFileURL:(NSURL *)url {
    return url.isFileURL &&
           [url.lastPathComponent isEqualToString:@"Home.html"] &&
           [url.path containsString:@"/Resources/home/"];
}

- (NSString *)queryValueNamed:(NSString *)name inURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if ([item.name isEqualToString:name]) return item.value ?: @"";
    }
    return @"";
}

- (BOOL)handleInternalURL:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:@"trailbrowser"]) return NO;

    NSString *host = url.host.lowercaseString ?: @"";
    if ([host isEqualToString:@"open"]) {
        NSString *input = [self queryValueNamed:@"input" inURL:url];
        if (input.length > 0) [self loadURLString:input];
        return YES;
    }

    if ([host isEqualToString:@"deep-search"]) {
        NSString *query = [self queryValueNamed:@"q" inURL:url];
        if (query.length > 0) [self runDeepSearchForQuery:query];
        return YES;
    }

    if ([host isEqualToString:@"assistant"]) {
        [self openAssistant:nil];
        return YES;
    }

    if ([host isEqualToString:@"home"] || host.length == 0) {
        if (self.webView) [self loadNativeHomePageInWebView:self.webView];
        return YES;
    }

    return NO;
}

- (void)loadNativeHomePageInWebView:(WKWebView *)webView {
    BrowserTab *tab = [self tabForWebView:webView];
    if (tab) {
        tab.title = @"TrailBrowser Home";
        tab.urlString = [self homeURLString];
        tab.favicon = nil;
        [self reloadSidebarRowForTab:tab];
    }
    self.addressField.stringValue = [self homeURLString];
    self.statusLabel.stringValue = @"Ready";
    [webView loadHTMLString:[self nativeHomeHTML]
                    baseURL:[self nativeHomeBaseURL]];
}

- (NSURL *)URLForUserInput:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return nil;

    if ([self inputContainsWhitespace:trimmed]) {
        return [self searchURLForQuery:trimmed];
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
    if ([self isSupportedExplicitScheme:components.scheme] || [trimmed containsString:@"://"]) {
        return components.URL;
    }

    if ([self inputLooksLikeHostOrLocalAddress:trimmed]) {
        NSString *scheme = [self inputLooksLocal:trimmed] ? @"http://" : @"https://";
        return [NSURL URLWithString:[scheme stringByAppendingString:trimmed]];
    }

    return [self searchURLForQuery:trimmed];
}

- (BOOL)isSupportedExplicitScheme:(NSString *)scheme {
    NSString *lower = scheme.lowercaseString;
    return [lower isEqualToString:@"http"] ||
           [lower isEqualToString:@"https"] ||
           [lower isEqualToString:@"file"] ||
           [lower isEqualToString:@"about"];
}

- (BOOL)inputContainsWhitespace:(NSString *)input {
    return [input rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound;
}

- (BOOL)inputLooksLocal:(NSString *)input {
    NSString *lower = input.lowercaseString;
    return [lower hasPrefix:@"localhost"] ||
           [lower hasPrefix:@"127."] ||
           [lower hasPrefix:@"0.0.0.0"] ||
           [lower hasPrefix:@"::1"] ||
           [lower hasPrefix:@"["];
}

- (BOOL)inputLooksLikeHostOrLocalAddress:(NSString *)input {
    if ([self inputLooksLocal:input]) return YES;

    NSString *pattern =
        @"^(([A-Za-z0-9-]+\\.)+[A-Za-z]{2,}|\\d{1,3}(\\.\\d{1,3}){3})"
         "(:[0-9]{1,5})?([/?#].*)?$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:0
                                                                             error:nil];
    NSRange fullRange = NSMakeRange(0, input.length);
    NSTextCheckingResult *match = [regex firstMatchInString:input options:0 range:fullRange];
    return match && NSEqualRanges(match.range, fullRange);
}

- (NSURL *)searchURLForQuery:(NSString *)query {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"https";
    components.host = @"www.google.com";
    components.path = @"/search";
    components.queryItems = @[ [NSURLQueryItem queryItemWithName:@"q" value:query] ];
    return components.URL;
}

- (NSString *)supportDirectoryPath {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                                     NSUserDomainMask,
                                                                     YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    NSString *directory = [base stringByAppendingPathComponent:@"TrailBrowser"];

    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error) {
        NSLog(@"Could not create TrailBrowser support directory: %@", error.localizedDescription);
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

    BrowserTab *tab = [self tabForWebView:webView];
    NSString *lastRecordedURL = tab ? tab.lastRecordedURL : self.lastRecordedURL;
    if ([lastRecordedURL isEqualToString:urlString]) return;
    if (tab) {
        tab.lastRecordedURL = urlString;
    } else {
        self.lastRecordedURL = urlString;
    }

    NSDictionary<NSString *, id> *entry = @{
        @"timestamp": [[self historyDateFormatter] stringFromDate:[NSDate date]],
        @"url": urlString,
        @"title": webView.title ?: @"",
        @"host": url.host ?: @"",
        @"source": @"TrailBrowser"
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

- (void)toggleSidebar:(id)sender {
    (void)sender;
    self.sidebarVisible = !self.sidebarVisible;
    if (self.sidebarVisible) {
        self.sidebar.hidden = NO;
        self.sidebarSeparator.hidden = NO;
    }

    self.sidebarWidthConstraint.constant = self.sidebarVisible ? 220.0 : 0.0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.18;
        [self.window.contentView layoutSubtreeIfNeeded];
    } completionHandler:^{
        if (!self.sidebarVisible) {
            self.sidebar.hidden = YES;
            self.sidebarSeparator.hidden = YES;
        }
    }];
    [self updateControls];
}

- (void)goBack:(id)sender {
    (void)sender;
    if (self.webView.canGoBack) [self.webView goBack];
}

- (void)goForward:(id)sender {
    (void)sender;
    if (self.webView.canGoForward) [self.webView goForward];
}

- (void)goHome:(id)sender {
    (void)sender;
    [self loadURLString:[self homeURLString]];
}

- (void)reloadPage:(id)sender {
    (void)sender;
    if (!self.webView) return;
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

- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    if (notification.object == self.addressField) self.userEditingAddress = YES;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.addressField) self.userEditingAddress = NO;
}

#pragma mark - Page assistant

- (void)assistantModeChanged:(id)sender {
    (void)sender;
    BOOL editMode = self.assistantModeControl.selectedSegment == 1;
    self.assistantPromptField.placeholderString = editMode
        ? @"Change this page"
        : @"Ask about this page";
}

- (void)closeAssistantResult:(id)sender {
    (void)sender;
    self.assistantResultPanel.hidden = YES;
}

- (void)openAssistant:(id)sender {
    (void)sender;
    self.assistantLauncherButton.hidden = YES;
    self.assistantBar.hidden = NO;
    [self.webContainer addSubview:self.assistantResultPanel positioned:NSWindowAbove relativeTo:self.webView];
    [self.webContainer addSubview:self.assistantBar positioned:NSWindowAbove relativeTo:self.assistantResultPanel];
    [self.window makeFirstResponder:self.assistantPromptField];
}

- (void)collapseAssistant:(id)sender {
    (void)sender;
    self.assistantResultPanel.hidden = YES;
    self.assistantBar.hidden = YES;
    self.assistantLauncherButton.hidden = NO;
    [self.webContainer addSubview:self.assistantLauncherButton positioned:NSWindowAbove relativeTo:self.webView];
}

- (NSError *)assistantErrorWithMessage:(NSString *)message {
    return [NSError errorWithDomain:@"TrailBrowserAssistant"
                               code:1
                           userInfo:@{ NSLocalizedDescriptionKey: message ?: @"Assistant failed" }];
}

- (void)setAssistantWorking:(BOOL)working {
    self.assistantPromptField.enabled = !working;
    self.assistantModeControl.enabled = !working;
    self.assistantRunButton.enabled = !working;
    self.assistantSpinner.hidden = !working;
    if (working) {
        [self.assistantSpinner startAnimation:nil];
    } else {
        [self.assistantSpinner stopAnimation:nil];
    }
}

- (void)showAssistantMessage:(NSString *)message {
    [self openAssistant:nil];
    self.assistantResultPanel.hidden = NO;
    self.assistantResultTextView.string = message ?: @"";
}

- (void)runDeepSearchForQuery:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        NSBeep();
        return;
    }

    self.assistantModeControl.selectedSegment = 0;
    [self assistantModeChanged:nil];
    self.assistantPromptField.stringValue = @"";
    [self setAssistantWorking:YES];
    [self showAssistantMessage:[NSString stringWithFormat:@"Deep Search is researching: %@", trimmed]];

    NSString *prompt = [NSString stringWithFormat:
                        @"You are TrailBrowser Deep Search.\n"
                         "Use live web search when helpful. Produce a detailed, high-signal answer.\n"
                         "Include concrete findings, dates when relevant, tradeoffs, and source links when available.\n"
                         "If the query asks for a comparison or recommendation, give a clear conclusion and rationale.\n\n"
                         "Deep Search query:\n%@\n",
                        trimmed];

    [self runCodexWithPrompt:prompt enableSearch:YES completion:^(NSString *output, NSError *error) {
        [self setAssistantWorking:NO];
        if (error) {
            [self showAssistantMessage:error.localizedDescription];
            return;
        }
        [self showAssistantMessage:[output stringByTrimmingCharactersInSet:
                                    NSCharacterSet.whitespaceAndNewlineCharacterSet]];
    }];
}

- (void)runPageAssistant:(id)sender {
    (void)sender;
    NSString *request = [self.assistantPromptField.stringValue stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (request.length == 0) {
        NSBeep();
        return;
    }
    if (!self.webView) {
        [self showAssistantMessage:@"No active page."];
        return;
    }

    BOOL editMode = self.assistantModeControl.selectedSegment == 1;
    self.assistantPromptField.stringValue = @"";
    [self setAssistantWorking:YES];
    [self showAssistantMessage:editMode ? @"Codex is preparing a structured page update..."
                                   : @"Codex is reading the page and writing an answer..."];

    [self pageSnapshotWithCompletion:^(NSString *snapshot, NSError *snapshotError) {
        if (snapshotError) {
            [self setAssistantWorking:NO];
            [self showAssistantMessage:snapshotError.localizedDescription];
            return;
        }

        NSString *prompt = [self codexPromptForRequest:request
                                              snapshot:snapshot
                                              editMode:editMode];
        [self runCodexWithPrompt:prompt enableSearch:NO completion:^(NSString *output, NSError *codexError) {
            [self setAssistantWorking:NO];
            if (codexError) {
                [self showAssistantMessage:codexError.localizedDescription];
                return;
            }

            if (editMode) {
                [self applyAssistantJavaScript:[self editJavaScriptFromCodexOutput:output]];
            } else {
                [self showAssistantMessage:[output stringByTrimmingCharactersInSet:
                                            NSCharacterSet.whitespaceAndNewlineCharacterSet]];
            }
        }];
    }];
}

- (void)pageSnapshotWithCompletion:(void (^)(NSString *snapshot, NSError *error))completion {
    NSString *script =
        @"(() => {"
         "const clipText = (value, limit) => String(value || '').replace(/\\s+/g, ' ').trim().slice(0, limit);"
         "const clipRaw = (value, limit) => String(value || '').slice(0, limit);"
         "const sensitive = /(token|secret|password|passwd|auth|session|sid|key|credential|cookie|bearer)/i;"
         "const clone = document.documentElement ? document.documentElement.cloneNode(true) : null;"
         "if (clone) {"
         "clone.querySelectorAll('script,noscript,iframe').forEach(node => node.remove());"
         "clone.querySelectorAll('input,textarea,select').forEach(node => {"
         "node.removeAttribute('value');"
         "if (node.tagName === 'TEXTAREA') node.textContent = '';"
         "});"
         "clone.querySelectorAll('*').forEach(node => {"
         "Array.from(node.attributes || []).forEach(attr => {"
         "if (sensitive.test(attr.name) || sensitive.test(attr.value)) node.setAttribute(attr.name, '[redacted]');"
         "});"
         "});"
         "}"
         "const metas = Array.from(document.querySelectorAll('meta[name=\"description\"],meta[property=\"og:description\"]'))"
         ".map(m => m.content).filter(Boolean).slice(0, 3).join('\\n');"
         "const headings = Array.from(document.querySelectorAll('h1,h2,h3'))"
         ".map(h => h.innerText).filter(Boolean).slice(0, 40).join('\\n');"
         "const selection = String(window.getSelection ? window.getSelection() : '');"
         "const text = document.body ? document.body.innerText : '';"
         "const stylesheetLinks = Array.from(document.querySelectorAll('link[rel~=\"stylesheet\"][href]'))"
         ".map(link => link.href).slice(0, 20);"
         "const inlineStyles = Array.from(document.querySelectorAll('style'))"
         ".map(style => style.textContent || '').join('\\n\\n');"
         "return JSON.stringify({"
         "url: location.href,"
         "title: document.title,"
         "selection: clipText(selection, 4000),"
         "description: clipText(metas, 2000),"
         "headings: clipText(headings, 4000),"
         "visibleText: clipText(text, 20000),"
         "stylesheetLinks,"
         "inlineStyles: clipRaw(inlineStyles, 12000),"
         "sanitizedHTML: clipRaw(clone ? clone.outerHTML : '', 70000)"
         "});"
         "})()";

    [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        if (![result isKindOfClass:NSString.class]) {
            completion(nil, [self assistantErrorWithMessage:@"Could not read page text."]);
            return;
        }
        completion(result, nil);
    }];
}

- (NSString *)codexPromptForRequest:(NSString *)request
                            snapshot:(NSString *)snapshot
                            editMode:(BOOL)editMode {
    if (editMode) {
        return [NSString stringWithFormat:
                @"You are TrailBrowser's page editing assistant.\n"
                 "Return strict JSON only. No markdown, no explanation.\n"
                 "Schema: {\"html\": string|null, \"css\": string|null, \"js\": string|null, \"summary\": string|null}.\n"
                 "TrailBrowser applies html first, then css, then js to the current WKWebView.\n"
                 "Use html when replacing the page body or whole document. Use css for styling. Use js for behavior, DOM patches, or incremental changes.\n"
                 "The html field may be a complete HTML document or a body fragment.\n"
                 "The css field should be raw CSS only.\n"
                 "The js field should be raw JavaScript only. Use it only when needed.\n"
                 "Use the sanitizedHTML field for structural edits and the visibleText/headings fields for content edits.\n"
                 "Do not fetch remote URLs, navigate, submit forms, read cookies, read localStorage/sessionStorage/indexedDB, use clipboard APIs, or exfiltrate data.\n"
                 "The edit is temporary and should keep the page usable. Make substantial changes when requested, including full redesigns.\n\n"
                 "User request:\n%@\n\n"
                 "Current page snapshot JSON:\n%@\n",
                request, snapshot ?: @"{}"];
    }

    return [NSString stringWithFormat:
            @"You are TrailBrowser's page question assistant.\n"
             "Answer using only the current page snapshot JSON. You can use visibleText, headings, sanitizedHTML, stylesheetLinks, and inlineStyles.\n"
             "If the answer is not present, say that it is not visible on the page.\n"
             "Give a useful, detailed answer with concrete observations from the page. Structure it with short paragraphs or bullets when helpful.\n\n"
             "User question:\n%@\n\n"
             "Current page snapshot JSON:\n%@\n",
            request, snapshot ?: @"{}"];
}

- (NSString *)shellQuotedString:(NSString *)string {
    NSString *escaped = [string stringByReplacingOccurrencesOfString:@"'"
                                                         withString:@"'\\''"];
    return [NSString stringWithFormat:@"'%@'", escaped];
}

- (void)runCodexWithPrompt:(NSString *)prompt
              enableSearch:(BOOL)enableSearch
                completion:(void (^)(NSString *output, NSError *error))completion {
    NSString *supportPath = [self supportDirectoryPath];
    NSString *uuid = NSUUID.UUID.UUIDString;
    NSString *outputPath = [supportPath stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"codex-%@.txt", uuid]];
    NSString *logPath = [supportPath stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"codex-%@.log", uuid]];
    [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];

    NSFileHandle *logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    NSPipe *inputPipe = [NSPipe pipe];
    NSString *searchFlag = enableSearch ? @"--search " : @"";
    NSString *command = [NSString stringWithFormat:
                         @"for d in \"$HOME\"/.nvm/versions/node/*/bin /opt/homebrew/bin /usr/local/bin; do "
                          "[ -d \"$d\" ] && PATH=\"$d:$PATH\"; done; export PATH; "
                          "codex %@exec --skip-git-repo-check --sandbox read-only "
                          "--ephemeral --color never --output-last-message %@ -",
                         searchFlag,
                         [self shellQuotedString:outputPath]];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
    task.arguments = @[ @"-lc", command ];
    task.currentDirectoryURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    task.standardInput = inputPipe;
    task.standardOutput = logHandle;
    task.standardError = logHandle;
    task.terminationHandler = ^(NSTask *finishedTask) {
        [logHandle closeFile];
        NSData *outputData = [NSData dataWithContentsOfFile:outputPath];
        NSData *logData = [NSData dataWithContentsOfFile:logPath];
        NSString *output = [[NSString alloc] initWithData:outputData ?: [NSData data]
                                                 encoding:NSUTF8StringEncoding] ?: @"";
        NSString *log = [[NSString alloc] initWithData:logData ?: [NSData data]
                                             encoding:NSUTF8StringEncoding] ?: @"";

        [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:logPath error:nil];

        NSString *finalOutput = output.length ? output : log;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finishedTask.terminationStatus != 0) {
                NSString *message = log.length ? log : @"Codex command failed.";
                completion(nil, [self assistantErrorWithMessage:message]);
                return;
            }
            completion(finalOutput, nil);
        });
    };

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        [logHandle closeFile];
        completion(nil, launchError);
        return;
    }

    NSData *promptData = [prompt dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    [[inputPipe fileHandleForWriting] writeData:promptData];
    [[inputPipe fileHandleForWriting] closeFile];
}

- (NSString *)javaScriptStringLiteralForString:(NSString *)string {
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[ string ?: @"" ]
                                                   options:0
                                                     error:nil];
    NSString *arrayLiteral = [[NSString alloc] initWithData:json ?: [NSData data]
                                                   encoding:NSUTF8StringEncoding] ?: @"[\"\"]";
    if (arrayLiteral.length < 2) return @"\"\"";
    return [arrayLiteral substringWithRange:NSMakeRange(1, arrayLiteral.length - 2)];
}

- (NSString *)scriptForReplacingDocumentWithHTML:(NSString *)html {
    NSString *literal = [self javaScriptStringLiteralForString:html ?: @""];
    return [NSString stringWithFormat:
            @"(() => { document.open(); document.write(%@); document.close(); })();",
            literal];
}

- (NSString *)scriptForInjectingCSS:(NSString *)css {
    NSString *literal = [self javaScriptStringLiteralForString:css ?: @""];
    return [NSString stringWithFormat:
            @"(() => {"
             "let style = document.getElementById('__trailbrowser_codex_style__');"
             "if (!style) { style = document.createElement('style'); style.id = '__trailbrowser_codex_style__'; document.head.appendChild(style); }"
             "style.textContent = %@;"
             "})();",
            literal];
}

- (NSString *)scriptForStructuredPageUpdate:(NSDictionary<NSString *, id> *)payload {
    id htmlValue = payload[@"html"];
    id cssValue = payload[@"css"];
    id jsValue = payload[@"js"];
    NSString *html = [htmlValue isKindOfClass:NSString.class] ? htmlValue : @"";
    NSString *css = [cssValue isKindOfClass:NSString.class] ? cssValue : @"";
    NSString *js = [jsValue isKindOfClass:NSString.class] ? jsValue : @"";

    NSString *jsonLiteral = [self javaScriptStringLiteralForString:
                             [[NSString alloc] initWithData:
                              [NSJSONSerialization dataWithJSONObject:@{
                                  @"html": html ?: @"",
                                  @"css": css ?: @"",
                                  @"js": js ?: @""
                              }
                                                              options:0
                                                                error:nil] ?: [NSData data]
                                                       encoding:NSUTF8StringEncoding] ?: @"{}"];

    return [NSString stringWithFormat:
            @"(() => {"
             "const payload = JSON.parse(%@);"
             "const html = String(payload.html || '');"
             "const css = String(payload.css || '');"
             "const js = String(payload.js || '');"
             "if (html.trim()) {"
             "const lower = html.trim().slice(0, 80).toLowerCase();"
             "if (lower.startsWith('<!doctype') || lower.startsWith('<html')) {"
             "document.open(); document.write(html); document.close();"
             "} else {"
             "if (!document.body) document.documentElement.appendChild(document.createElement('body'));"
             "document.body.innerHTML = html;"
             "}"
             "}"
             "if (css.trim()) {"
             "let style = document.getElementById('__trailbrowser_codex_style__');"
             "if (!style) { style = document.createElement('style'); style.id = '__trailbrowser_codex_style__'; document.head.appendChild(style); }"
             "style.textContent = css;"
             "}"
             "if (js.trim()) { (new Function(js))(); }"
             "})();",
            jsonLiteral];
}

- (BOOL)looksLikeHTML:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *lower = trimmed.lowercaseString;
    return [lower hasPrefix:@"<!doctype"] ||
           [lower hasPrefix:@"<html"] ||
           [lower hasPrefix:@"<body"] ||
           ([lower hasPrefix:@"<"] && [lower containsString:@">"] && [lower containsString:@"</"]);
}

- (BOOL)looksLikeCSS:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([self looksLikeHTML:trimmed]) return NO;
    if ([trimmed containsString:@"=>"] || [trimmed containsString:@"function"] || [trimmed containsString:@"document."]) return NO;
    return ([trimmed containsString:@"{"] && [trimmed containsString:@"}"] && [trimmed containsString:@":"]);
}

- (NSString *)editJavaScriptFromCodexOutput:(NSString *)output {
    NSString *trimmed = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:@"```([A-Za-z0-9_-]+)?\\s*(.*?)```"
                                                  options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators
                                                    error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:trimmed
                                                    options:0
                                                      range:NSMakeRange(0, trimmed.length)];
    NSString *language = @"";
    NSString *code = trimmed;
    if (match.numberOfRanges > 2) {
        NSRange languageRange = [match rangeAtIndex:1];
        NSRange codeRange = [match rangeAtIndex:2];
        if (languageRange.location != NSNotFound) {
            language = [[trimmed substringWithRange:languageRange] lowercaseString];
        }
        code = [[trimmed substringWithRange:codeRange]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }

    NSData *jsonData = [code dataUsingEncoding:NSUTF8StringEncoding];
    id json = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
    if ([json isKindOfClass:NSDictionary.class]) {
        return [self scriptForStructuredPageUpdate:json];
    }

    if ([language isEqualToString:@"json"]) {
        return @"";
    } else if ([language isEqualToString:@"html"] || [self looksLikeHTML:code]) {
        return [self scriptForReplacingDocumentWithHTML:code];
    }
    if ([language isEqualToString:@"css"] || [self looksLikeCSS:code]) {
        return [self scriptForInjectingCSS:code];
    }
    return code;
}

- (void)applyAssistantJavaScript:(NSString *)script {
    if (script.length == 0) {
        [self showAssistantMessage:@"Codex did not return JavaScript."];
        return;
    }

    [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)result;
        if (error) {
            [self showAssistantMessage:error.localizedDescription ?: @"Could not apply page edit."];
            return;
        }
        [self showAssistantMessage:@"Applied page edit."];
    }];
}

#pragma mark - Sidebar tabs

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.tabs.count;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    (void)tableView;
    (void)row;
    return [[BrowserTabRowView alloc] initWithFrame:NSZeroRect];
}

- (NSString *)subtitleForTab:(BrowserTab *)tab {
    NSURL *url = [NSURL URLWithString:tab.urlString ?: @""];
    if (url.host.length > 0) return url.host;
    if (tab.urlString.length > 0) return tab.urlString;
    return @"New tab";
}

- (void)reloadSidebarRowForTab:(BrowserTab *)tab {
    NSUInteger index = [self.tabs indexOfObject:tab];
    if (index == NSNotFound) return;

    [self.tabTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:index]
                             columnIndexes:[NSIndexSet indexSetWithIndex:0]];
}

- (BOOL)isHTTPURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

- (NSURL *)defaultFaviconURLForPageURL:(NSURL *)pageURL {
    if (![self isHTTPURL:pageURL]) return nil;

    NSURLComponents *components = [NSURLComponents componentsWithURL:pageURL
                                             resolvingAgainstBaseURL:NO];
    components.path = @"/favicon.ico";
    components.query = nil;
    components.fragment = nil;
    return components.URL;
}

- (void)fetchFaviconForWebView:(WKWebView *)webView {
    BrowserTab *tab = [self tabForWebView:webView];
    NSURL *pageURL = webView.URL;
    NSURL *fallbackURL = [self defaultFaviconURLForPageURL:pageURL];
    if (!tab || !fallbackURL) return;

    NSString *script =
        @"(() => {"
         "const links = Array.from(document.querySelectorAll('link[rel][href]'));"
         "const rel = /(apple-touch-icon|shortcut icon|icon)/i;"
         "const picked = links.find(link => rel.test(link.rel));"
         "return picked ? picked.href : (location.origin + '/favicon.ico');"
         "})()";

    [webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        (void)error;
        NSString *faviconString = [result isKindOfClass:NSString.class] ? result : nil;
        NSURL *faviconURL = faviconString.length > 0 ? [NSURL URLWithString:faviconString] : fallbackURL;
        if (![self isHTTPURL:faviconURL]) faviconURL = fallbackURL;
        [self requestFaviconAtURL:faviconURL fallbackURL:fallbackURL forTab:tab];
    }];
}

- (void)requestFaviconAtURL:(NSURL *)faviconURL
                fallbackURL:(NSURL *)fallbackURL
                     forTab:(BrowserTab *)tab {
    if (![self isHTTPURL:faviconURL]) return;

    NSString *faviconURLString = faviconURL.absoluteString;
    if ([tab.faviconURLString isEqualToString:faviconURLString] && tab.favicon) return;
    if ([tab.pendingFaviconURLString isEqualToString:faviconURLString]) return;

    tab.pendingFaviconURLString = faviconURLString;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:faviconURL
                                                           completionHandler:^(NSData *data,
                                                                               NSURLResponse *response,
                                                                               NSError *error) {
        (void)response;
        NSImage *image = nil;
        if (!error && data.length > 0 && data.length < 512 * 1024) {
            image = [[NSImage alloc] initWithData:data];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.tabs indexOfObject:tab] == NSNotFound) return;

            tab.pendingFaviconURLString = nil;
            if (!image) {
                BOOL canTryFallback = fallbackURL &&
                    ![fallbackURL.absoluteString isEqualToString:faviconURLString];
                if (canTryFallback) {
                    [self requestFaviconAtURL:fallbackURL fallbackURL:nil forTab:tab];
                }
                return;
            }

            image.template = NO;
            tab.favicon = image;
            tab.faviconURLString = faviconURLString;
            [self reloadSidebarRowForTab:tab];
        });
    }];
    [task resume];
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    (void)tableColumn;
    if (row < 0 || row >= (NSInteger)self.tabs.count) return nil;

    static NSString *identifier = @"TrailBrowserTabCell";
    BrowserTabCellView *cell = (BrowserTabCellView *)[tableView makeViewWithIdentifier:identifier owner:self];

    if (!cell) {
        cell = [[BrowserTabCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;

        NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.imageScaling = NSImageScaleProportionallyDown;
        icon.wantsLayer = YES;
        icon.layer.cornerRadius = 4.0;
        icon.layer.masksToBounds = YES;
        if (@available(macOS 11.0, *)) {
            NSImage *image = [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:@"Tab"];
            image.template = YES;
            icon.image = image;
        }
        if (@available(macOS 10.14, *)) {
            icon.contentTintColor = NSColor.tertiaryLabelColor;
        }
        [cell addSubview:icon];
        cell.tabIconView = icon;
        cell.imageView = icon;

        NSTextField *title = [NSTextField labelWithString:@""];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        title.maximumNumberOfLines = 1;
        [cell addSubview:title];
        cell.titleLabel = title;
        cell.textField = title;

        NSTextField *subtitle = [NSTextField labelWithString:@""];
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        subtitle.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
        subtitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
        subtitle.maximumNumberOfLines = 1;
        [cell addSubview:subtitle];
        cell.subtitleLabel = subtitle;

        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:16.0],
            [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:18.0],
            [icon.heightAnchor constraintEqualToConstant:18.0],

            [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10.0],
            [title.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12.0],
            [title.topAnchor constraintEqualToAnchor:cell.topAnchor constant:7.0],

            [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
            [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:0.0]
        ]];
    }

    BrowserTab *tab = self.tabs[(NSUInteger)row];
    BOOL selected = row == tableView.selectedRow;
    cell.titleLabel.stringValue = tab.title.length ? tab.title : @"New Tab";
    cell.subtitleLabel.stringValue = [self subtitleForTab:tab];
    cell.titleLabel.textColor = selected ? NSColor.labelColor : NSColor.secondaryLabelColor;
    cell.subtitleLabel.textColor = selected ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor;

    if (tab.favicon) {
        tab.favicon.template = NO;
        cell.tabIconView.image = tab.favicon;
        if (@available(macOS 10.14, *)) cell.tabIconView.contentTintColor = nil;
    } else {
        if (@available(macOS 11.0, *)) {
            NSImage *image = [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:@"Website"];
            image.template = YES;
            cell.tabIconView.image = image;
        }
        if (@available(macOS 10.14, *)) {
            cell.tabIconView.contentTintColor = selected ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor;
        }
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object != self.tabTable) return;
    NSInteger row = self.tabTable.selectedRow;
    if (row >= 0 && row != self.activeTabIndex) {
        [self selectTabAtIndex:row];
    }
}

- (void)updateSidebarTitleForWebView:(WKWebView *)webView {
    BrowserTab *tab = [self tabForWebView:webView];
    if (!tab) return;

    if ([self isHomeURLString:tab.urlString] || [self isNativeHomeFileURL:webView.URL]) {
        tab.title = @"TrailBrowser Home";
        tab.urlString = [self homeURLString];
        [self reloadSidebarRowForTab:tab];
        return;
    }

    NSString *previousHost = [NSURL URLWithString:tab.urlString ?: @""].host.lowercaseString;
    NSString *currentHost = webView.URL.host.lowercaseString;
    if (previousHost.length > 0 &&
        currentHost.length > 0 &&
        ![previousHost isEqualToString:currentHost]) {
        tab.favicon = nil;
        tab.faviconURLString = nil;
        tab.pendingFaviconURLString = nil;
    }

    NSString *title = webView.title;
    if (title.length == 0) {
        title = webView.URL.host.length ? webView.URL.host : @"New Tab";
    }
    tab.title = title;
    if (webView.URL.absoluteString.length > 0) tab.urlString = webView.URL.absoluteString;

    [self reloadSidebarRowForTab:tab];
}

#pragma mark - Chrome cookie import

- (void)importChromeCookies:(id)sender {
    (void)sender;

    if (![ChromeCookieImporter isChromeInstalled]) {
        [self showImportAlertWithStyle:NSAlertStyleInformational
                                 title:@"Google Chrome not found"
                               message:@"No Google Chrome data was found for your user account."];
        return;
    }

    NSArray<ChromeProfile *> *profiles = [ChromeCookieImporter availableProfiles];
    if (profiles.count == 0) {
        [self showImportAlertWithStyle:NSAlertStyleInformational
                                 title:@"No Chrome profiles found"
                               message:@"TrailBrowser could not find any Chrome profiles with cookies."];
        return;
    }

    ChromeProfile *profile = [self promptForProfileFrom:profiles];
    if (!profile) return;  // user cancelled

    [self performCookieImportForProfile:profile];
}

// Show a confirmation that also lets the user pick a profile when more than one
// exists. Returns the chosen profile, or nil if the user cancelled.
- (ChromeProfile *)promptForProfileFrom:(NSArray<ChromeProfile *> *)profiles {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"Import cookies from Chrome";
    alert.informativeText =
        @"TrailBrowser will copy cookies from your Chrome profile into this browser "
         "so you stay signed in to your sites. macOS may ask permission to read "
         "\"Chrome Safe Storage\" from your Keychain.";
    [alert addButtonWithTitle:@"Import"];
    [alert addButtonWithTitle:@"Cancel"];

    NSPopUpButton *picker = nil;
    if (profiles.count > 1) {
        picker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 26)
                                            pullsDown:NO];
        for (ChromeProfile *profile in profiles) {
            NSString *label = profile.email.length
                ? [NSString stringWithFormat:@"%@ (%@)", profile.displayName, profile.email]
                : profile.displayName;
            [picker addItemWithTitle:label];
        }
        [picker selectItemAtIndex:0];
        alert.accessoryView = picker;
    }

    NSModalResponse response = [alert runModal];
    if (response != NSAlertFirstButtonReturn) return nil;

    NSUInteger index = picker ? (NSUInteger)picker.indexOfSelectedItem : 0;
    if (index >= profiles.count) index = 0;
    return profiles[index];
}

- (void)performCookieImportForProfile:(ChromeProfile *)profile {
    self.statusLabel.stringValue = @"Importing cookies…";

    WKHTTPCookieStore *store = self.webView.configuration.websiteDataStore.httpCookieStore;
    [ChromeCookieImporter importProfileDirectory:profile.directory
                                 intoCookieStore:store
                                      completion:^(ChromeCookieImportResult *result, NSError *error) {
        self.statusLabel.stringValue = @"Ready";

        if (error) {
            [self showImportAlertWithStyle:NSAlertStyleWarning
                                     title:@"Could not import cookies"
                                   message:error.localizedDescription ?: @"An unknown error occurred."];
            return;
        }

        NSString *message = [NSString stringWithFormat:
                             @"Imported %lu cookie%@ from \"%@\".\n\n"
                              "Reload the current page to use them.",
                             (unsigned long)result.imported,
                             result.imported == 1 ? @"" : @"s",
                             profile.displayName];
        [self showImportAlertWithStyle:NSAlertStyleInformational
                                 title:@"Cookies imported"
                               message:message];

        if (self.webView.URL) [self.webView reload];
    }];
}

- (void)showImportAlertWithStyle:(NSAlertStyle)style
                           title:(NSString *)title
                         message:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = style;
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)updateControls {
    self.backButton.enabled = self.webView && self.webView.canGoBack;
    self.forwardButton.enabled = self.webView && self.webView.canGoForward;
    self.closeTabButton.enabled = self.tabs.count > 1;

    BOOL loading = self.webView && self.webView.loading;
    self.reloadButton.toolTip = loading ? @"Stop" : @"Reload";
    if (@available(macOS 11.0, *)) {
        NSString *symbol = loading ? @"xmark" : @"arrow.clockwise";
        NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:self.reloadButton.toolTip];
        image.template = YES;
        self.reloadButton.image = image;

        NSString *sidebarSymbol = self.sidebarVisible ? @"sidebar.left" : @"sidebar.leading";
        NSImage *sidebarImage = [NSImage imageWithSystemSymbolName:sidebarSymbol
                                         accessibilityDescription:self.sidebarToggleButton.toolTip];
        if (sidebarImage) {
            sidebarImage.template = YES;
            self.sidebarToggleButton.image = sidebarImage;
        }
    } else {
        self.reloadButton.title = loading ? @"X" : @"R";
    }

    self.progressBar.hidden = !loading;
    if (!loading) self.progressBar.doubleValue = 0.0;
}

- (void)syncAddressBarWithWebView {
    if ([self isAddressFieldBeingEdited]) return;

    BrowserTab *tab = [self activeTab];
    if ([self isHomeURLString:tab.urlString]) {
        self.addressField.stringValue = [self homeURLString];
        return;
    }

    NSURL *url = self.webView.URL;
    if (url) self.addressField.stringValue = url.absoluteString;
}

- (BOOL)isAddressFieldBeingEdited {
    return self.userEditingAddress ||
           self.window.firstResponder == self.addressField ||
           self.window.firstResponder == self.addressField.currentEditor;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    (void)change;
    WKWebView *observedWebView = [object isKindOfClass:WKWebView.class] ? object : nil;

    if (context == BrowserProgressContext) {
        if (observedWebView != self.webView) return;
        double progress = self.webView.estimatedProgress;
        self.progressBar.doubleValue = progress;
        self.progressBar.hidden = !self.webView.loading || progress >= 1.0;
        return;
    }

    if (context == BrowserURLContext) {
        if (observedWebView) [self updateSidebarTitleForWebView:observedWebView];
        if (observedWebView == self.webView) [self syncAddressBarWithWebView];
        return;
    }

    if (context == BrowserCanGoBackContext || context == BrowserCanGoForwardContext) {
        if (observedWebView == self.webView) [self updateControls];
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    (void)navigation;
    if (webView != self.webView) return;
    self.statusLabel.stringValue = @"Loading";
    [self updateControls];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [self updateSidebarTitleForWebView:webView];
    if (webView == self.webView) [self syncAddressBarWithWebView];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)navigation;
    [self updateSidebarTitleForWebView:webView];
    [self fetchFaviconForWebView:webView];
    if (webView == self.webView) {
        self.statusLabel.stringValue = @"Ready";
        [self syncAddressBarWithWebView];
    }
    [self recordHistoryEntryForWebView:webView];
    [self writeBrowserStateRunning:YES];
    if (webView == self.webView) [self updateControls];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)navigation;
    if (webView != self.webView) return;
    self.statusLabel.stringValue = error.localizedDescription ?: @"Failed";
    [self updateControls];
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    (void)webView;
    NSURL *url = navigationAction.request.URL;
    if (url && [self handleInternalURL:url]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
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
    (void)webView;
    (void)windowFeatures;

    if (!navigationAction.targetFrame) {
        BrowserTab *tab = [self newTabWithConfiguration:configuration URLString:nil select:YES];
        return tab.webView;
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
