#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "../shared/ALNWebTestSupport.h"

@interface SPAFallbackRouteController : ALNController
@end

@implementation SPAFallbackRouteController

- (id)explorers:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"explorers route\n"];
  return nil;
}

- (id)catchAll:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"app wildcard\n"];
  return nil;
}

@end

@interface SPAFallbackTests : XCTestCase
@property(nonatomic, copy) NSString *directory;
@property(nonatomic, copy) NSString *shellPath;
@end

@implementation SPAFallbackTests

- (void)setUp {
  [super setUp];
  self.directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                               [NSString stringWithFormat:@"arlen-spa-%@",
                                                                          [[NSUUID UUID] UUIDString]]];
  [[NSFileManager defaultManager] createDirectoryAtPath:self.directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  self.shellPath = [self.directory stringByAppendingPathComponent:@"index.html"];
  XCTAssertTrue([@"<!doctype html><div id=app></div>\n" writeToFile:self.shellPath
                                                         atomically:YES
                                                           encoding:NSUTF8StringEncoding
                                                              error:NULL]);
}

- (void)tearDown {
  [[NSFileManager defaultManager] removeItemAtPath:self.directory error:NULL];
  [super tearDown];
}

- (ALNApplication *)applicationWithFallback:(NSDictionary *)fallbackExtra config:(NSDictionary *)configExtra {
  NSMutableDictionary *fallback = [@{
    @"file" : self.shellPath,
    @"excludePrefixes" : @[ @"/api", @"/auth", @"/media" ],
  } mutableCopy];
  [fallback addEntriesFromDictionary:fallbackExtra ?: @{}];
  NSMutableDictionary *config = [@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @(YES),
      @"secret" : @"unit-test-secret-value-0123456789abcdef",
      @"secure" : @(NO),
    },
    @"csrf" : @{ @"enabled" : @(YES) },
    @"spaFallback" : fallback,
  } mutableCopy];
  [config addEntriesFromDictionary:configExtra ?: @{}];
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:config];
  [app registerRouteMethod:@"GET"
                      path:@"/explorers"
                      name:@"explorers"
           controllerClass:[SPAFallbackRouteController class]
                    action:@"explorers"];
  return app;
}

- (ALNResponse *)app:(ALNApplication *)app
              method:(NSString *)method
                path:(NSString *)path
             headers:(NSDictionary *)headers {
  return [app dispatchRequest:ALNTestRequestWithMethod(method, path, @"", headers ?: @{}, nil)];
}

- (NSDictionary *)html {
  return @{ @"accept" : @"text/html,application/xhtml+xml,*/*;q=0.8" };
}

- (void)assertShell:(ALNResponse *)response {
  XCTAssertEqual((NSInteger)200, response.statusCode);
  ALNAssertResponseHeaderEquals(response, @"Content-Type", @"text/html; charset=utf-8");
  ALNAssertResponseHeaderEquals(response, @"Cache-Control", @"no-cache");
  XCTAssertEqualObjects(self.shellPath, response.fileBodyPath);
}

- (void)assertPlain404:(ALNResponse *)response {
  XCTAssertEqual((NSInteger)404, response.statusCode);
  XCTAssertNil(response.fileBodyPath);
}

- (void)testDeepLinkServesShellThroughMiddleware {
  ALNApplication *app = [self applicationWithFallback:nil config:nil];
  ALNResponse *response = [self app:app method:@"GET" path:@"/explorers/3/map" headers:[self html]];
  [self assertShell:response];
  // Middleware ran: security headers and a session cookie (carrying the CSRF token).
  XCTAssertNotNil([response headerForName:@"Content-Security-Policy"]);
  XCTAssertNotNil([response headerForName:@"X-Frame-Options"]);
  XCTAssertTrue([[response headerForName:@"Set-Cookie"] length] > 0);
  [self assertShell:[self app:app method:@"GET" path:@"/" headers:[self html]]];
}

- (void)testRealRoutesAndAppWildcardsWin {
  ALNApplication *app = [self applicationWithFallback:nil config:nil];
  ALNResponse *route = [self app:app method:@"GET" path:@"/explorers" headers:[self html]];
  XCTAssertEqualObjects(@"explorers route\n", ALNTestStringFromResponse(route));

  [app registerRouteMethod:@"GET"
                      path:@"/*path"
                      name:@"app_shell"
           controllerClass:[SPAFallbackRouteController class]
                    action:@"catchAll"];
  ALNResponse *wildcard = [self app:app method:@"GET" path:@"/explorers/3/map" headers:[self html]];
  XCTAssertEqualObjects(@"app wildcard\n", ALNTestStringFromResponse(wildcard));
}

- (void)testExcludedPrefixesUseSegmentBoundaries {
  ALNApplication *app = [self applicationWithFallback:nil config:nil];
  for (NSString *path in @[ @"/api", @"/api/missing", @"/auth/x", @"/media/photo" ]) {
    [self assertPlain404:[self app:app method:@"GET" path:path headers:[self html]]];
  }
  [self assertShell:[self app:app method:@"GET" path:@"/apiary" headers:[self html]]];
  [self assertShell:[self app:app method:@"GET" path:@"/mediaeval/x" headers:[self html]]];
}

- (void)testNonNavigationRequestsKeepThe404 {
  ALNApplication *app = [self applicationWithFallback:nil config:nil];
  [self assertPlain404:[self app:app method:@"GET" path:@"/deep/link" headers:@{ @"accept" : @"application/json" }]];
  [self assertPlain404:[self app:app method:@"GET" path:@"/deep/link" headers:@{ @"accept" : @"*/*" }]];
  [self assertPlain404:[self app:app method:@"GET" path:@"/deep/link" headers:@{}]];
  [self assertPlain404:[self app:app method:@"POST" path:@"/deep/link" headers:[self html]]];
  // A missing hashed asset is a 404, not an HTML page with status 200.
  [self assertPlain404:[self app:app method:@"GET" path:@"/assets/app-3f9a.js" headers:[self html]]];
  ALNResponse *json = [self app:app method:@"GET" path:@"/deep/link" headers:@{ @"accept" : @"application/json" }];
  XCTAssertTrue([ALNTestStringFromResponse(json) containsString:@"not_found"], @"%@", ALNTestStringFromResponse(json));
}

- (void)testAllowDottedPathsAndPrefixOption {
  ALNApplication *dotted = [self applicationWithFallback:@{ @"allowDottedPaths" : @"YES" } config:nil];
  [self assertShell:[self app:dotted method:@"GET" path:@"/users/jane.doe" headers:[self html]]];

  ALNApplication *scoped = [self applicationWithFallback:@{ @"prefix" : @"/app/" } config:nil];
  [self assertShell:[self app:scoped method:@"GET" path:@"/app" headers:[self html]]];
  [self assertShell:[self app:scoped method:@"GET" path:@"/app/explorers/3" headers:[self html]]];
  [self assertPlain404:[self app:scoped method:@"GET" path:@"/other/page" headers:[self html]]];
  [self assertPlain404:[self app:scoped method:@"GET" path:@"/apple" headers:[self html]]];
}

- (void)testRouteMissBuiltInsStillWin {
  ALNApplication *app = [self applicationWithFallback:nil config:nil];
  ALNResponse *live = [self app:app method:@"GET" path:@"/arlen/live.js" headers:[self html]];
  XCTAssertEqual((NSInteger)200, live.statusCode);
  XCTAssertNil(live.fileBodyPath);
  ALNResponse *health = [self app:app method:@"GET" path:@"/healthz" headers:[self html]];
  XCTAssertEqual((NSInteger)200, health.statusCode);
  XCTAssertNil(health.fileBodyPath);
  ALNResponse *openapi = [self app:app method:@"GET" path:@"/openapi.json" headers:[self html]];
  XCTAssertNil(openapi.fileBodyPath);
}

- (void)testConditionalAndHeadRequests {
  ALNApplication *app = [self applicationWithFallback:nil config:nil];
  ALNResponse *first = [self app:app method:@"GET" path:@"/deep" headers:[self html]];
  NSString *etag = [first headerForName:@"ETag"];
  XCTAssertTrue([etag length] > 0);
  NSMutableDictionary *conditional = [[self html] mutableCopy];
  conditional[@"if-none-match"] = etag;
  ALNResponse *notModified = [self app:app method:@"GET" path:@"/deep" headers:conditional];
  XCTAssertEqual((NSInteger)304, notModified.statusCode);
  ALNAssertResponseHeaderEquals(notModified, @"Cache-Control", @"no-cache");
  ALNResponse *head = [self app:app method:@"HEAD" path:@"/deep" headers:[self html]];
  XCTAssertEqual((NSInteger)200, head.statusCode);
}

- (void)testMissingShellFileIs404AndApiOnlyDisablesFallback {
  [[NSFileManager defaultManager] removeItemAtPath:self.shellPath error:NULL];
  ALNApplication *app = [self applicationWithFallback:nil config:nil];
  XCTAssertTrue([app startWithError:NULL]);
  [self assertPlain404:[self app:app method:@"GET" path:@"/deep" headers:[self html]]];

  ALNApplication *apiOnly = [self applicationWithFallback:nil config:@{ @"apiOnly" : @(YES) }];
  [self assertPlain404:[self app:apiOnly method:@"GET" path:@"/deep" headers:[self html]]];
}

- (void)testInvalidConfigurationFailsStartup {
  NSArray *invalid = @[
    @{ @"file" : @"" },
    @{ @"prefix" : @"app" },
    @{ @"prefix" : @"//evil.example" },
    @{ @"excludePrefixes" : @"/api" },
    @{ @"excludePrefixes" : @[ @"/" ] },
    @{ @"excludePrefixes" : @[ @"/api?x" ] },
    @{ @"cacheControl" : @"no-cache\r\nX-Injected: 1" },
    @{ @"allowDottedPaths" : @"sometimes" },
  ];
  for (NSDictionary *change in invalid) {
    ALNApplication *app = [self applicationWithFallback:change config:nil];
    NSError *error = nil;
    XCTAssertFalse([app startWithError:&error], @"%@", change);
    XCTAssertTrue([error.localizedDescription containsString:@"spaFallback"], @"%@ %@", change, error);
    XCTAssertNil(app.spaFallback, @"%@", change);
  }
  ALNApplication *notDictionary = [[ALNApplication alloc] initWithConfig:@{ @"spaFallback" : @"index.html" }];
  XCTAssertFalse([notDictionary startWithError:NULL]);
}

- (void)testProgrammaticConfigurationResolvesRelativeToAppRoot {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"appRoot" : self.directory,
  }];
  NSError *error = nil;
  XCTAssertTrue([app setSPAFallbackFile:@"index.html" options:@{ @"cacheControl" : @"no-store" } error:&error],
                @"%@", error);
  XCTAssertEqualObjects(self.shellPath, app.spaFallback[@"file"]);
  ALNResponse *response = [self app:app method:@"GET" path:@"/x/y" headers:[self html]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  ALNAssertResponseHeaderEquals(response, @"Cache-Control", @"no-store");
  XCTAssertFalse([app setSPAFallbackFile:@"" options:nil error:&error]);
}

@end
