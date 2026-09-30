#ifndef ALN_TEST_CLIENT_H
#define ALN_TEST_CLIENT_H

#import <Foundation/Foundation.h>

#import "ALNAppRunner.h"
#import "ALNResponse.h"

@class ALNApplication;

NS_ASSUME_NONNULL_BEGIN

// Plain C so the test bundle's load-time constructor can call it before any
// Objective-C messaging is safe. Same effect as +[ALNTestClient setAppMain:].
FOUNDATION_EXPORT void ALNTestClientSetAppMain(ALNAppMainFunction _Nullable appMain);

// In-process request client for app tests (docs/TESTING_WORKFLOW.md). It builds the
// app from its config directory, registers the app's own routes, and dispatches
// requests without a socket. Cookies persist across requests like a browser jar.
@interface ALNTestClient : NSObject

@property(nonatomic, strong, readonly) ALNApplication *application;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *cookies;
// Adds the app's CSRF header to unsafe requests that do not set it. Default YES.
@property(nonatomic, assign) BOOL automaticCSRF;

// `arlen test --app` registers the app's `main` (renamed for the test build) so
// clients can capture its route registration. Tests do not call this.
+ (void)setAppMain:(nullable ALNAppMainFunction)appMain;

// The app at ARLEN_APP_ROOT (or the current directory) in `environment` (default
// "test"), with `configOverrides` merged over the loaded config, routed exactly as
// the app's main registers them.
+ (nullable instancetype)clientWithEnvironment:(nullable NSString *)environment
                               configOverrides:(nullable NSDictionary *)configOverrides
                                         error:(NSError *_Nullable *_Nullable)error;
// Explicit app root and route registration; nil `registerRoutes` uses the app's main.
+ (nullable instancetype)clientWithAppRoot:(nullable NSString *)appRoot
                               environment:(nullable NSString *)environment
                           configOverrides:(nullable NSDictionary *)configOverrides
                            registerRoutes:(nullable ALNRouteRegistrationCallback)registerRoutes
                                     error:(NSError *_Nullable *_Nullable)error;
// Wraps an application built by the caller; starts it if needed.
- (nullable instancetype)initWithApplication:(ALNApplication *)application
                                       error:(NSError *_Nullable *_Nullable)error;

- (ALNResponse *)get:(NSString *)path;
- (ALNResponse *)get:(NSString *)path
               query:(nullable NSDictionary<NSString *, NSString *> *)query
             headers:(nullable NSDictionary<NSString *, NSString *> *)headers;
// application/x-www-form-urlencoded
- (ALNResponse *)post:(NSString *)path form:(nullable NSDictionary<NSString *, NSString *> *)form;
- (ALNResponse *)post:(NSString *)path JSON:(nullable id)object;
// Each file is @{ @"name", @"filename", @"data" (NSData), optional @"contentType" }.
- (ALNResponse *)post:(NSString *)path
      multipartFields:(nullable NSDictionary<NSString *, NSString *> *)fields
                files:(nullable NSArray<NSDictionary *> *)files;
- (ALNResponse *)requestWithMethod:(NSString *)method
                              path:(NSString *)path
                             query:(nullable NSString *)query
                           headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                              body:(nullable NSData *)body;

// The session in the cookie jar, decoded with the app's session secret; nil when
// sessions are disabled or no session cookie is held.
- (nullable NSDictionary *)session;
// Edits the session in the jar (creating one if needed). NO when sessions are disabled.
- (BOOL)updateSession:(void (^)(NSMutableDictionary *session))update
                error:(NSError *_Nullable *_Nullable)error;
// The CSRF token for the current session, creating the session if needed.
- (nullable NSString *)csrfToken;
// Establishes an authenticated session as ALNAuthSession would after a login.
- (BOOL)signInAsSubject:(NSString *)subject
                  roles:(nullable NSArray<NSString *> *)roles
                 scopes:(nullable NSArray<NSString *> *)scopes
                  error:(NSError *_Nullable *_Nullable)error;
- (void)clearCookies;

@end

@interface ALNResponse (ALNTestClient)
// UTF-8 body text ("" when empty or not UTF-8).
- (NSString *)bodyText;
// Parsed JSON body, or nil when it is not JSON.
- (nullable id)JSONObject;
@end

NS_ASSUME_NONNULL_END

#endif
