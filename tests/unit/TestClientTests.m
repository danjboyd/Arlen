#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNAppRunner.h"
#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNTestClient.h"

// GitHub issue 65: the public in-process client apps use for request tests.
@interface TestClientFixtureController : ALNController
@end

@implementation TestClientFixtureController
- (id)hello:(ALNContext *)ctx {
  [self renderText:@"hello"];
  return nil;
}
- (id)echo:(ALNContext *)ctx {
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:ctx.request.body options:0 error:NULL];
  return @{ @"form" : ctx.request.formParams ?: @{}, @"json" : json ?: @{},
            @"query" : ctx.request.queryParams ?: @{}, @"uploads" : @(ctx.request.uploads.count),
            @"note" : ctx.request.formParams[@"note"] ?: @"" };
}
- (id)remember:(ALNContext *)ctx {
  [ctx session][@"remembered"] = @"yes";
  [ctx markSessionDirty];
  return @{ @"ok" : @YES };
}
- (id)me:(ALNContext *)ctx {
  return @{ @"subject" : [ctx authSubject] ?: @"", @"roles" : [ctx authRoles] ?: @[] };
}
@end

static void TestClientFixtureRoutes(ALNApplication *app) {
  Class controller = [TestClientFixtureController class];
  [app registerRouteMethod:@"GET" path:@"/hello" name:@"hello" controllerClass:controller action:@"hello"];
  [app registerRouteMethod:@"GET" path:@"/echo" name:@"echo_get" controllerClass:controller action:@"echo"];
  [app registerRouteMethod:@"POST" path:@"/echo" name:@"echo" controllerClass:controller action:@"echo"];
  [app registerRouteMethod:@"POST" path:@"/remember" name:@"remember" controllerClass:controller action:@"remember"];
  [app registerRouteMethod:@"GET" path:@"/me" name:@"me" controllerClass:controller action:@"me"];
}

// Stands in for an app's main() compiled with -Dmain=ALNAppMain.
static int TestClientFixtureAppMain(int argc, const char *const *argv) {
  return ALNRunAppMain(argc, argv, &TestClientFixtureRoutes);
}

@interface TestClientTests : XCTestCase
@property(nonatomic, copy) NSString *appRoot;
@end

@implementation TestClientTests

- (void)setUp {
  [super setUp];
  self.appRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                             [@"arlen-test-client-" stringByAppendingString:[NSUUID UUID].UUIDString]];
  NSString *configDir = [self.appRoot stringByAppendingPathComponent:@"config"];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:configDir
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:NULL]);
  NSString *config = @"{ logLevel = error; session = { enabled = YES; secret = \"test-client-session-secret-0123456789abcdef\"; }; "
                      "csrf = { enabled = YES; }; }";
  XCTAssertTrue([config writeToFile:[configDir stringByAppendingPathComponent:@"app.plist"]
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:NULL]);
}

- (void)tearDown {
  [ALNTestClient setAppMain:NULL];
  [[NSFileManager defaultManager] removeItemAtPath:self.appRoot error:NULL];
  [super tearDown];
}

- (ALNTestClient *)client {
  NSError *error = nil;
  ALNTestClient *client = [ALNTestClient clientWithAppRoot:self.appRoot
                                               environment:nil
                                           configOverrides:nil
                                            registerRoutes:&TestClientFixtureRoutes
                                                     error:&error];
  XCTAssertNotNil(client, @"%@", error);
  return client;
}

- (void)testCaptureRecordsRouteRegistrationWithoutRunningTheApp {
  XCTAssertEqual(&TestClientFixtureRoutes, ALNCaptureRouteRegistration(&TestClientFixtureAppMain));
  XCTAssertTrue(ALNCaptureRouteRegistration(NULL) == NULL);

  [ALNTestClient setAppMain:&TestClientFixtureAppMain];
  NSError *error = nil;
  ALNTestClient *client = [ALNTestClient clientWithAppRoot:self.appRoot
                                               environment:@"test"
                                           configOverrides:nil
                                            registerRoutes:NULL
                                                     error:&error];
  XCTAssertNotNil(client, @"%@", error);
  XCTAssertEqualObjects(@"test", client.application.environment);
  XCTAssertEqual(200, [client get:@"/hello"].statusCode);
  XCTAssertEqualObjects(@"hello", [[client get:@"/hello"] bodyText]);
}

- (void)testRequestsEncodeFormJSONQueryAndMultipart {
  ALNTestClient *client = [self client];
  NSDictionary *query = [[client get:@"/echo" query:@{ @"q" : @"a b&c" } headers:nil] JSONObject];
  XCTAssertEqualObjects(@"a b&c", query[@"query"][@"q"]);
  NSDictionary *form = [[client post:@"/echo" form:@{ @"name" : @"Ada & co" }] JSONObject];
  XCTAssertEqualObjects(@"Ada & co", form[@"form"][@"name"]);
  NSDictionary *json = [[client post:@"/echo" JSON:@{ @"n" : @3 }] JSONObject];
  XCTAssertEqualObjects(@3, json[@"json"][@"n"]);
  NSDictionary *multipart = [[client post:@"/echo"
                          multipartFields:@{ @"note" : @"hi" }
                                    files:@[ @{ @"name" : @"doc", @"filename" : @"a.bin",
                                                @"data" : [NSData dataWithBytes:"\0\1" length:2] } ]] JSONObject];
  XCTAssertEqualObjects(@1, multipart[@"uploads"]);
  XCTAssertEqualObjects(@"hi", multipart[@"note"]);
}

- (void)testCookieJarAndAutomaticCSRF {
  ALNTestClient *client = [self client];
  XCTAssertNil([client session]);
  XCTAssertEqual(200, [client post:@"/remember" form:nil].statusCode);
  XCTAssertEqualObjects(@"yes", [client session][@"remembered"]);
  XCTAssertNotNil([client csrfToken]);

  client.automaticCSRF = NO;
  XCTAssertEqual(403, [client post:@"/remember" form:nil].statusCode);
  XCTAssertEqual(200, [client requestWithMethod:@"POST"
                                           path:@"/remember"
                                          query:nil
                                        headers:@{ @"X-CSRF-Token" : [client csrfToken] }
                                           body:nil].statusCode);
  [client clearCookies];
  XCTAssertNil([client session]);
}

- (void)testSignInEstablishesAnAuthenticatedSession {
  ALNTestClient *client = [self client];
  XCTAssertEqualObjects(@"", [[client get:@"/me"] JSONObject][@"subject"]);
  NSError *error = nil;
  XCTAssertTrue([client signInAsSubject:@"user-42" roles:@[ @"admin" ] scopes:nil error:&error], @"%@", error);
  NSDictionary *me = [[client get:@"/me"] JSONObject];
  XCTAssertEqualObjects(@"user-42", me[@"subject"]);
  XCTAssertEqualObjects(@[ @"admin" ], me[@"roles"]);
}

- (void)testConfigOverridesAndMissingSessions {
  NSError *error = nil;
  ALNTestClient *client = [ALNTestClient clientWithAppRoot:self.appRoot
                                               environment:nil
                                           configOverrides:@{ @"session" : @{ @"enabled" : @NO },
                                                              @"csrf" : @{ @"enabled" : @NO } }
                                            registerRoutes:&TestClientFixtureRoutes
                                                     error:&error];
  XCTAssertNotNil(client, @"%@", error);
  XCTAssertEqual(200, [client post:@"/echo" form:@{ @"a" : @"b" }].statusCode);
  XCTAssertNil([client csrfToken]);
  XCTAssertFalse([client signInAsSubject:@"x" roles:nil scopes:nil error:&error]);
  XCTAssertNotNil(error);

  XCTAssertNil([ALNTestClient clientWithAppRoot:@"/nonexistent/arlen-app"
                                    environment:nil
                                configOverrides:@{ @"session" : @{ @"enabled" : @YES } }
                                 registerRoutes:NULL
                                          error:&error]);
}

@end
