#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNHTTPClient.h"
#import "ALNLogger.h"
#import "../shared/ALNTestSupport.h"
#import <dispatch/dispatch.h>
#include <fcntl.h>
#include <unistd.h>

// Native request setters may normalize invalid header values before the client
// sees them. Supply the raw value through an immutable request fixture instead.
@interface ALNHTTPClientInvalidHeadersRequest : NSURLRequest
@end
@implementation ALNHTTPClientInvalidHeadersRequest
- (NSDictionary<NSString *, NSString *> *)allHTTPHeaderFields {
  return @{ @"X-Test" : @"bad\nvalue" };
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

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
  [self startPeerWithTLS:NO];
}

- (void)startPeerWithTLS:(BOOL)tls {
  _peer = [NSTask new];
  _peer.launchPath = ALNTestToolPath(@"python3");
  _peer.arguments = @[ @"tests/fixtures/http/metadata_server.py", @"--trace", _tracePath,
                       @"--gate", [_tracePath stringByAppendingString:@".gate"] ];
  if (tls) _peer.arguments = [_peer.arguments arrayByAddingObject:@"--tls"];
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
  (void)ALNTestStopServerTask(_peer);
  [[NSFileManager defaultManager] removeItemAtPath:_tracePath error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:[_tracePath stringByAppendingString:@".gate"] error:nil];
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
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"idleTimeoutSeconds" : @0 },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"idleTimeoutSeconds" : @301 },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"idleTimeoutSeconds" : @YES },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"streamingTimeoutSeconds" : @0 },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"streamingTimeoutSeconds" : @86401 },
    @{ @"allowedHosts" : @[ @"api.example.com" ], @"streamingTimeoutSeconds" : @1.5 },
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
  XCTAssertEqual(30.0, client.idleTimeout);
  XCTAssertEqual(900.0, client.streamingTimeout);
  client = [self clientWith:@{ @"idleTimeoutSeconds" : @"2", @"streamingTimeoutSeconds" : @"86400" }];
  XCTAssertEqual(2.0, client.idleTimeout);
  XCTAssertEqual(86400.0, client.streamingTimeout);
}

- (void)testStreamDeliversBeforeServerCanFinishOnTheCallingThread {
  ALNHTTPClient *client = [self clientWith:nil];
  NSMutableArray *order = [NSMutableArray array];
  NSMutableData *body = [NSMutableData data];
  NSThread *caller = [NSThread currentThread];
  NSError *error = nil;
  BOOL complete = [client streamRequest:[NSURLRequest requestWithURL:[self URLForPath:@"/stream-gated"]]
      cancellation:nil onResponse:^BOOL(NSHTTPURLResponse *response) {
        XCTAssertEqualObjects(caller, [NSThread currentThread]);
        XCTAssertEqual(200, response.statusCode);
        [order addObject:@"headers"];
        return YES;
      } onData:^BOOL(NSData *data) {
        XCTAssertEqualObjects(caller, [NSThread currentThread]);
        XCTAssertEqualObjects(@"headers", order.firstObject);
        [order addObject:@"data"];
        [body appendData:data];
        // The peer cannot send its second part until this callback runs. A
        // buffered implementation times out, rather than satisfying this test.
        XCTAssertTrue([[NSFileManager defaultManager] createFileAtPath:[_tracePath stringByAppendingString:@".gate"]
            contents:[NSData data] attributes:nil]);
        return YES;
      } error:&error];
  XCTAssertTrue(complete, @"%@", error);
  XCTAssertNil(error);
  XCTAssertEqualObjects([@"data: first\n\ndata: second\n\n" dataUsingEncoding:NSUTF8StringEncoding], body);
  XCTAssertTrue(order.count >= 3);
  NSUInteger headerCount = [[order filteredArrayUsingPredicate:
      [NSPredicate predicateWithFormat:@"SELF == %@", @"headers"]] count];
  XCTAssertEqual((NSUInteger)1, headerCount);
}

- (void)testStreamCancellationInterruptsSilenceBeforeHeadersAndBetweenChunks {
  for (NSString *path in @[ @"/sleep", @"/stream-stall" ]) {
    ALNHTTPClientCancellation *token = [ALNHTTPClientCancellation new];
    dispatch_group_t group = dispatch_group_create();
    dispatch_semaphore_t bodyArrived = dispatch_semaphore_create(0);
    BOOL betweenChunks = [path isEqual:@"/stream-stall"];
    dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      if (betweenChunks) dispatch_semaphore_wait(bodyArrived, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
      [NSThread sleepForTimeInterval:0.2]; // sleep-ok: cancel while the peer deliberately withholds response bytes
      [token cancel];
    });
    __block NSUInteger bytes = 0;
    NSError *error = nil;
    NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
    BOOL complete = [[self clientWith:nil] streamRequest:[NSURLRequest requestWithURL:[self URLForPath:path]]
        cancellation:token onResponse:^BOOL(NSHTTPURLResponse *response) { return YES; }
        onData:^BOOL(NSData *data) { bytes += data.length; dispatch_semaphore_signal(bodyArrived); return YES; } error:&error];
    XCTAssertFalse(complete);
    XCTAssertEqual(ALNHTTPClientErrorCancelled, error.code, @"%@", error);
    XCTAssertTrue(token.cancelled);
    XCTAssertTrue([NSDate timeIntervalSinceReferenceDate] - started < 1.5);
    XCTAssertEqual([path isEqual:@"/sleep"] ? (NSUInteger)0 : (NSUInteger)3, bytes);
    long finished = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC));
    XCTAssertEqual(0L, finished);
#if !OS_OBJECT_USE_OBJC
    if (finished == 0) {
      dispatch_release(group);
      dispatch_release(bodyArrived);
    }
#endif
  }
}

- (void)testPreCancelledStreamNeverConnects {
  ALNHTTPClientCancellation *token = [ALNHTTPClientCancellation new];
  [token cancel];
  [token cancel];
  NSError *error = nil;
  BOOL complete = [[self clientWith:nil] streamRequest:[NSURLRequest requestWithURL:[self URLForPath:@"/ok"]]
      cancellation:token onResponse:^BOOL(NSHTTPURLResponse *response) { XCTFail(@"Unexpected headers"); return YES; }
      onData:^BOOL(NSData *data) { XCTFail(@"Unexpected data"); return YES; } error:&error];
  XCTAssertFalse(complete);
  XCTAssertEqual(ALNHTTPClientErrorCancelled, error.code);
  XCTAssertEqual((NSUInteger)0, self.trace.count);
}

- (void)testStreamCallbackCanCancelAtHeadersOrData {
  for (NSNumber *atHeaders in @[ @YES, @NO ]) {
    __block NSUInteger callbacks = 0;
    NSError *error = nil;
    BOOL complete = [[self clientWith:nil] streamRequest:[NSURLRequest requestWithURL:[self URLForPath:@"/stream-stall"]]
        cancellation:nil onResponse:^BOOL(NSHTTPURLResponse *response) { return !atHeaders.boolValue; }
        onData:^BOOL(NSData *data) { callbacks++; return NO; } error:&error];
    XCTAssertFalse(complete);
    XCTAssertEqual(ALNHTTPClientErrorCancelled, error.code, @"%@", error);
    XCTAssertEqual(atHeaders.boolValue ? (NSUInteger)0 : (NSUInteger)1, callbacks);
  }
}

- (void)testStreamIdleTimeoutIncludesInitialSilenceAndMidBodyStall {
  for (NSString *path in @[ @"/sleep", @"/stream-stall" ]) {
    ALNHTTPClient *client = [self clientWith:@{ @"idleTimeoutSeconds" : @1, @"streamingTimeoutSeconds" : @5 }];
    __block NSUInteger bytes = 0;
    NSError *error = nil;
    NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
    BOOL complete = [client streamRequest:[NSURLRequest requestWithURL:[self URLForPath:path]]
        cancellation:nil onResponse:^BOOL(NSHTTPURLResponse *response) { return YES; }
        onData:^BOOL(NSData *data) { bytes += data.length; return YES; } error:&error];
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - started;
    XCTAssertFalse(complete);
    XCTAssertEqual(ALNHTTPClientErrorIdleTimedOut, error.code, @"%@", error);
    XCTAssertTrue(elapsed >= 0.9 && elapsed < 2.5, @"%f", elapsed);
    XCTAssertEqual([path isEqual:@"/sleep"] ? (NSUInteger)0 : (NSUInteger)3, bytes);
  }
}

- (void)testStreamTotalDeadlineCannotBeExtendedByIncomingBytes {
  ALNHTTPClient *client = [self clientWith:@{ @"idleTimeoutSeconds" : @1, @"streamingTimeoutSeconds" : @1 }];
  __block NSUInteger bytes = 0;
  NSError *error = nil;
  BOOL complete = [client streamRequest:[NSURLRequest requestWithURL:[self URLForPath:@"/stream-heartbeat"]]
      cancellation:nil onResponse:^BOOL(NSHTTPURLResponse *response) { return YES; }
      onData:^BOOL(NSData *data) { bytes += data.length; return YES; } error:&error];
  XCTAssertFalse(complete);
  XCTAssertEqual(ALNHTTPClientErrorTimedOut, error.code, @"%@", error);
  XCTAssertTrue(bytes > 0 && bytes < 12);
}

- (void)testStreamUsesItsOwnTotalDeadlineAndRefreshesIdleOnBytes {
  ALNHTTPClient *client = [self clientWith:@{ @"timeoutSeconds" : @1, @"idleTimeoutSeconds" : @1,
                                            @"streamingTimeoutSeconds" : @5 }];
  __block NSUInteger bytes = 0;
  NSError *error = nil;
  XCTAssertTrue([client streamRequest:[NSURLRequest requestWithURL:[self URLForPath:@"/stream-heartbeat"]]
      cancellation:nil onResponse:^BOOL(NSHTTPURLResponse *response) { return YES; }
      onData:^BOOL(NSData *data) { bytes += data.length; return YES; } error:&error], @"%@", error);
  XCTAssertEqual((NSUInteger)12, bytes);
  // The new streaming settings do not relax the buffered one-second deadline.
  XCTAssertNil([client GETURL:[self URLForPath:@"/stream-heartbeat"] headers:nil error:&error]);
  XCTAssertEqual(ALNHTTPClientErrorTimedOut, error.code);
}

- (void)testStreamDisconnectAfterPartialDataIsFailure {
  NSMutableData *body = [NSMutableData data];
  NSError *error = nil;
  XCTAssertFalse([[self clientWith:nil] streamRequest:[NSURLRequest requestWithURL:[self URLForPath:@"/stream-broken"]]
      cancellation:nil onResponse:^BOOL(NSHTTPURLResponse *response) { return YES; }
      onData:^BOOL(NSData *data) { [body appendData:data]; return YES; } error:&error]);
  XCTAssertEqualObjects([@"abc" dataUsingEncoding:NSUTF8StringEncoding], body);
  XCTAssertEqualObjects(ALNHTTPClientErrorDomain, error.domain);
  XCTAssertEqual(ALNHTTPClientErrorTransport, error.code);
}

- (void)testStreamByteLimitCoversDeclaredChunkedAndRedirectBodies {
  for (NSString *path in @[ @"/declared", @"/chunked", @"/budget/2" ]) {
    NSUInteger limit = [path isEqual:@"/budget/2"] ? 12 : 16;
    __block NSUInteger bytes = 0;
    NSError *error = nil;
    ALNHTTPClient *client = [self clientWith:@{ @"maxResponseBytes" : @(limit), @"maxRedirects" : @3 }];
    XCTAssertFalse([client streamRequest:[NSURLRequest requestWithURL:[self URLForPath:path]]
        cancellation:nil onResponse:^BOOL(NSHTTPURLResponse *response) { return YES; }
        onData:^BOOL(NSData *data) { bytes += data.length; return YES; } error:&error]);
    XCTAssertEqual(ALNHTTPClientErrorResponseTooLarge, error.code, @"%@: %@", path, error);
    XCTAssertTrue(bytes <= limit);
    if ([path isEqual:@"/budget/2"]) XCTAssertEqual((NSUInteger)0, bytes, @"Followed redirect bodies must be hidden");
  }
  __block NSUInteger bytes = 0;
  NSError *error = nil;
  XCTAssertTrue([[self clientWith:@{ @"maxResponseBytes" : @32 }] streamRequest:
      [NSURLRequest requestWithURL:[self URLForPath:@"/exact"]] cancellation:nil
      onResponse:^BOOL(NSHTTPURLResponse *response) { return YES; }
      onData:^BOOL(NSData *data) { bytes += data.length; return YES; } error:&error], @"%@", error);
  XCTAssertEqual((NSUInteger)32, bytes);
}

- (void)testStreamReportsFinalHeadersOnceAndIgnoresTrailers {
  for (NSString *path in @[ @"/reason-interim", @"/reason-redirect", @"/stream-trailers", @"/stream-lf", @"/status" ]) {
    NSMutableData *body = [NSMutableData data];
    __block NSHTTPURLResponse *headers = nil;
    __block NSUInteger responses = 0;
    NSError *error = nil;
    XCTAssertTrue([[self clientWith:@{ @"maxRedirects" : @3 }] streamRequest:
        [NSURLRequest requestWithURL:[self URLForPath:path]] cancellation:nil
        onResponse:^BOOL(NSHTTPURLResponse *response) { headers = response; responses++; return YES; }
        onData:^BOOL(NSData *data) { [body appendData:data]; return YES; } error:&error], @"%@", error);
    XCTAssertEqual((NSUInteger)1, responses);
    XCTAssertEqual([path isEqual:@"/status"] ? 503 : 200, headers.statusCode);
    XCTAssertNil(headers.allHeaderFields[@"X-Stale"]);
    XCTAssertNil(headers.allHeaderFields[@"X-Trailer"]);
    XCTAssertEqualObjects([@"{}" dataUsingEncoding:NSUTF8StringEncoding], body);
  }
}

- (void)testStreamRedirectsShareOneDeadline {
  ALNHTTPClient *client = [self clientWith:@{ @"streamingTimeoutSeconds" : @1, @"maxRedirects" : @3 }];
  NSError *error = nil;
  XCTAssertFalse([client streamRequest:[NSURLRequest requestWithURL:[self URLForPath:@"/stream-slow-redirect/2"]]
      cancellation:nil onResponse:^BOOL(NSHTTPURLResponse *response) { XCTFail(@"Unexpected final response"); return YES; }
      onData:^BOOL(NSData *data) { XCTFail(@"Unexpected final body"); return YES; } error:&error]);
  XCTAssertEqual(ALNHTTPClientErrorTimedOut, error.code, @"%@", error);
  XCTAssertEqual((NSUInteger)2, self.trace.count);
}

- (void)testStreamRedirectMethodAndBodyReplayRules {
  ALNHTTPClient *client = [self clientWith:@{ @"maxRedirects" : @2 }];
  for (NSNumber *status in @[ @303, @307, @308 ]) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
        [self URLForPath:[NSString stringWithFormat:@"/method/%@", status]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [@"posted" dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"ignored.invalid" forHTTPHeaderField:@"Host"];
    NSMutableData *body = [NSMutableData data];
    NSError *error = nil;
    XCTAssertTrue([client streamRequest:request cancellation:nil
        onResponse:^BOOL(NSHTTPURLResponse *response) { XCTAssertEqual(200, response.statusCode); return YES; }
        onData:^BOOL(NSData *data) { [body appendData:data]; return YES; } error:&error], @"%@", error);
    NSDictionary *echo = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
    XCTAssertEqualObjects(status.integerValue == 303 ? @"GET" : @"POST", echo[@"method"]);
    XCTAssertEqualObjects(status.integerValue == 303 ? @"" : @"posted", echo[@"body"]);
    XCTAssertEqualObjects(status.integerValue == 303 ? nil : @"text/plain", echo[@"headers"][@"content-type"]);
    XCTAssertFalse([echo[@"headers"][@"host"] containsString:@"ignored"]);
  }
}

- (void)testStreamLogsNeverExposeRequestOrCallbackSecrets {
  int fds[2];
  XCTAssertTrue(ALNTestCreatePipe(fds, YES));
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  logger.minimumLevel = ALNLogLevelInfo;
  logger.outputFileDescriptor = fds[1];
  ALNHTTPClient *client = [self clientWith:nil];
  client.logger = logger;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self URLForPath:@"/ok?SECRET-QUERY"]];
  request.HTTPMethod = @"POST";
  request.HTTPBody = [@"SECRET-BODY" dataUsingEncoding:NSUTF8StringEncoding];
  [request setValue:@"Bearer SECRET-TOKEN" forHTTPHeaderField:@"Authorization"];
  NSError *error = nil;
  XCTAssertTrue([client streamRequest:request cancellation:nil
      onResponse:^BOOL(NSHTTPURLResponse *response) { return YES; }
      onData:^BOOL(NSData *data) { return YES; } error:&error], @"%@", error);
  XCTAssertFalse([client streamRequest:request cancellation:nil
      onResponse:^BOOL(NSHTTPURLResponse *response) { [NSException raise:@"SECRET-CALLBACK" format:@"SECRET"]; return YES; }
      onData:^BOOL(NSData *data) { return YES; } error:&error]);
  close(fds[1]);
  NSMutableData *data = [NSMutableData data];
  char bytes[4096];
  ssize_t length;
  while ((length = read(fds[0], bytes, sizeof(bytes))) > 0) [data appendBytes:bytes length:(NSUInteger)length];
  close(fds[0]);
  NSString *logs = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  XCTAssertTrue([logs containsString:@"http_client.request"]);
  XCTAssertTrue([logs containsString:@"Stream callback failed"]);
  XCTAssertFalse([logs containsString:@"SECRET"], @"%@", logs);
  XCTAssertFalse([error.description containsString:@"SECRET"]);
}

- (void)testStreamCredentialRedirectAndAllowlistProtections {
  ALNHTTPClient *client = [self clientWith:@{ @"maxRedirects" : @2 }];
  for (NSString *credential in @[ @"Authorization", @"Cookie" ]) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self URLForPath:@"/redirect"]];
    [request setValue:@"SECRET" forHTTPHeaderField:credential];
    __block NSInteger status = 0;
    NSUInteger before = self.trace.count;
    NSError *error = nil;
    XCTAssertTrue([client streamRequest:request cancellation:nil
        onResponse:^BOOL(NSHTTPURLResponse *response) { status = response.statusCode; return YES; }
        onData:^BOOL(NSData *data) { return YES; } error:&error], @"%@", error);
    XCTAssertEqual(302, status);
    XCTAssertEqual(before + 1, self.trace.count);
  }
  for (NSString *path in @[ @"/cross-origin", @"/redirect-file", @"/loop" ]) {
    NSError *error = nil;
    XCTAssertFalse([client streamRequest:[NSURLRequest requestWithURL:[self URLForPath:path]] cancellation:nil
        onResponse:^BOOL(NSHTTPURLResponse *response) { XCTFail(@"Unexpected final headers"); return YES; }
        onData:^BOOL(NSData *data) { XCTFail(@"Unexpected data"); return YES; } error:&error]);
    XCTAssertEqual([path isEqual:@"/loop"] ? ALNHTTPClientErrorTooManyRedirects : ALNHTTPClientErrorRedirectNotAllowed,
                   error.code, @"%@", error);
  }
}

- (void)testStreamRejectsInvalidRequestsBeforeTransport {
  ALNHTTPClient *client = [self clientWith:nil];
  NSURLRequest *badHeader = [[ALNHTTPClientInvalidHeadersRequest alloc] initWithURL:[self URLForPath:@"/ok"]];
  NSURLRequest *rawCopy = [badHeader copy];
  XCTAssertEqualObjects(@"bad\nvalue", rawCopy.allHTTPHeaderFields[@"X-Test"]);
  NSMutableURLRequest *badMethod = [NSMutableURLRequest requestWithURL:[self URLForPath:@"/ok"]];
  badMethod.HTTPMethod = @"TRACE";
  NSMutableURLRequest *bodyStream = [NSMutableURLRequest requestWithURL:[self URLForPath:@"/ok"]];
  bodyStream.HTTPMethod = @"POST";
  bodyStream.HTTPBodyStream = [NSInputStream inputStreamWithData:[@"payload" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertNotNil(bodyStream.HTTPBodyStream);
  for (NSURLRequest *request in @[ badHeader, badMethod, bodyStream,
        [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://evil.example/secret?SECRET"]] ]) {
    NSError *error = nil;
    XCTAssertFalse([client streamRequest:request cancellation:nil
        onResponse:^BOOL(NSHTTPURLResponse *response) { XCTFail(@"Unexpected headers"); return YES; }
        onData:^BOOL(NSData *data) { XCTFail(@"Unexpected data"); return YES; } error:&error]);
    XCTAssertNotNil(error, @"method=%@, bodyStream=%@", request.HTTPMethod, request.HTTPBodyStream);
    XCTAssertFalse([error.description containsString:@"SECRET"]);
  }
  XCTAssertEqual((NSUInteger)0, self.trace.count);
}

- (void)testStreamCallbackExceptionsBecomeSanitizedErrors {
  for (NSNumber *inHeaders in @[ @YES, @NO ]) {
    NSError *error = nil;
    XCTAssertFalse([[self clientWith:nil] streamRequest:[NSURLRequest requestWithURL:[self URLForPath:@"/ok"]]
        cancellation:nil onResponse:^BOOL(NSHTTPURLResponse *response) {
          if (inHeaders.boolValue) [NSException raise:@"SECRET-HEADER" format:@"SECRET"];
          return YES;
        } onData:^BOOL(NSData *data) {
          [NSException raise:@"SECRET-DATA" format:@"SECRET"];
          return YES;
        } error:&error]);
    XCTAssertEqual(ALNHTTPClientErrorTransport, error.code);
    XCTAssertFalse([error.description containsString:@"SECRET"]);
  }
}

- (void)testStreamRejectsUntrustedTLSBeforeAnyResponseCallback {
  (void)ALNTestStopServerTask(_peer);
  [self startPeerWithTLS:YES];
  XCTAssertTrue(_port > 0);
  NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://127.0.0.1:%ld/ok", (long)_port]];
  NSError *error = nil;
  XCTAssertFalse([[self clientWith:nil] streamRequest:[NSURLRequest requestWithURL:url] cancellation:nil
      onResponse:^BOOL(NSHTTPURLResponse *response) { XCTFail(@"Untrusted TLS must not deliver headers"); return YES; }
      onData:^BOOL(NSData *data) { XCTFail(@"Untrusted TLS must not deliver data"); return YES; } error:&error]);
  XCTAssertEqual(ALNHTTPClientErrorTransport, error.code, @"%@", error);
  XCTAssertEqual((NSUInteger)0, self.trace.count);
}

- (void)testContentEncodingDoesNotEnableImplicitBrotliDecoding {
  ALNHTTPClient *client = [self clientWith:@{}];
  for (NSDictionary *headers in @[ @{}, @{ @"Accept-Encoding" : @"br" } ]) {
    NSError *error = nil;
    ALNHTTPClientResult *result = [client GETURL:[self URLForPath:@"/encoded-br"]
                                       headers:headers error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertNil(error);
    XCTAssertEqualObjects(result.body, [@"raw-brotli-audit-marker" dataUsingEncoding:NSUTF8StringEncoding]);
  }
}

- (void)testInvalidHeadersAreRejectedBeforeTransport {
  ALNHTTPClient *client = [self clientWith:@{}];
  NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/", (long)_port]];
  unichar nul = 0;
  NSArray *headers = @[
    @{@"X-Search": @"ok\r\nX-Injected: yes"}, @{@"X-Test": @"bad\nvalue"},
    @{@"Bad Name": @"value"}, @{@"Bad:Name": @"value"},
    @{@"X-Test": [NSString stringWithCharacters:&nul length:1]}
  ];
  for (NSDictionary *fields in headers) {
    NSError *error = nil;
    XCTAssertNil([client GETURL:url headers:fields error:&error]);
    XCTAssertEqual(ALNHTTPClientErrorInvalidRequest, error.code);
    error = nil;
    XCTAssertNil([client POSTJSONObject:@{} toURL:url headers:fields error:&error]);
    XCTAssertEqual(ALNHTTPClientErrorInvalidRequest, error.code);
  }
  XCTAssertEqual((NSUInteger)0, [self trace].count);
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
  XCTAssertTrue(ALNTestCreatePipe(fds, YES));
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
