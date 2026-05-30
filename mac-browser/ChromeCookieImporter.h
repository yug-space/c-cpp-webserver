// ChromeCookieImporter.h - Import cookies from a local Google Chrome profile
// into TrailBrowser's WebKit cookie store.
//
// This is an opt-in, user-initiated "import from Chrome" feature, like the
// migration assistants shipped by Safari, Edge, Arc, and Brave. It only ever
// touches the current user's own Chrome data on this machine, and decrypting
// the cookie values requires the macOS Keychain to grant access to the
// "Chrome Safe Storage" item (the OS shows a consent prompt the first time).

#import <Foundation/Foundation.h>

@class WKHTTPCookieStore;

NS_ASSUME_NONNULL_BEGIN

// A Chrome profile on disk (e.g. "Default", "Profile 1").
@interface ChromeProfile : NSObject
@property (nonatomic, copy) NSString *directory;          // on-disk dir name
@property (nonatomic, copy) NSString *displayName;        // friendly name
@property (nonatomic, copy, nullable) NSString *email;    // account email if known
@end

// Outcome of an import run.
@interface ChromeCookieImportResult : NSObject
@property (nonatomic, assign) NSUInteger imported;        // cookies written
@property (nonatomic, assign) NSUInteger skipped;         // cookies dropped
@end

@interface ChromeCookieImporter : NSObject

// Returns YES if a Chrome user-data directory exists for this user.
+ (BOOL)isChromeInstalled;

// Lists the Chrome profiles found on disk. Returns an empty array if none.
+ (NSArray<ChromeProfile *> *)availableProfiles;

// Extracts and decrypts cookies from the given profile directory, returning
// ready-to-use NSHTTPCookie objects. Blocking: reads the Keychain and SQLite,
// so call this off the main thread. On failure returns nil and sets *error.
+ (nullable NSArray<NSHTTPCookie *> *)cookiesForProfileDirectory:(NSString *)directory
                                                          error:(NSError **)error;

// Convenience: extract cookies from `directory` and write them into `store`.
// Extraction runs on a background queue; injection and `completion` run on the
// main queue. On extraction failure, result is nil and error is set.
+ (void)importProfileDirectory:(NSString *)directory
                 intoCookieStore:(WKHTTPCookieStore *)store
                      completion:(void (^)(ChromeCookieImportResult *_Nullable result,
                                           NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
