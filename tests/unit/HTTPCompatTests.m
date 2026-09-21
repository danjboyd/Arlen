#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNHTTPCompat.h"

extern NSString *ALNHTTPReceivedReasonPhraseFromStatusLine(NSString *line);

// Regression coverage for issue #22: ALNSynchronousURLRequest must follow
// loopback redirects instead of waiting out its timeout on GNUstep.
@interface HTTPCompatTests : XCTestCase
@end

@implementation HTTPCompatTests {
  NSTask *_peer;
  NSInteger _port;
  NSString *_tracePath;
}

- (void)setUp {
  [super setUp];
  _tracePath = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"arlen-http-compat-%@.trace",
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

- (NSMutableURLRequest *)requestForPath:(NSString *)path timeout:(NSTimeInterval)timeout {
  NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld%@", (long)_port, path]];
  return [NSMutableURLRequest requestWithURL:url
                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                             timeoutInterval:timeout];
}

- (NSArray<NSString *> *)trace {
  NSString *contents = [NSString stringWithContentsOfFile:_tracePath encoding:NSUTF8StringEncoding error:NULL] ?: @"";
  NSMutableArray *paths = [NSMutableArray array];
  for (NSString *line in [contents componentsSeparatedByString:@"\n"]) {
    if (line.length) [paths addObject:line];
  }
  return paths;
}

- (void)testResultRedirectBudgetPreservesCompleteFinalResponse {
  for (NSString *prefix in @[@"/budget", @"/absolute-budget"]) {
    for (NSNumber *budget in @[@0, @1, @3]) {
      for (NSNumber *extra in @[@0, @1]) {
        NSUInteger hops = budget.unsignedIntegerValue + extra.unsignedIntegerValue;
        NSUInteger before = self.trace.count;
        NSString *path = [NSString stringWithFormat:@"%@/%lu", prefix, (unsigned long)hops];
        NSError *error = nil;
        ALNHTTPClientResult *result = ALNSynchronousHTTPResult([self requestForPath:path timeout:3],
            budget.unsignedIntegerValue, ALNHTTPRedirectLimitReturnResponse, &error);
        XCTAssertNil(error);
        XCTAssertNotNil(result);
        XCTAssertEqual(extra.boolValue ? 302 : 200, result.response.statusCode);
        XCTAssertEqual(extra.boolValue, result.stoppedAtRedirectLimit);
        XCTAssertEqualObjects(extra.boolValue ? @"Budget Boundary" : @"Finished", result.receivedReasonPhrase);
        XCTAssertEqualObjects(extra.boolValue ? @"body-1" : @"body-0",
            [[NSString alloc] initWithData:result.body encoding:NSUTF8StringEncoding]);
        XCTAssertEqualObjects(extra.boolValue ? @"1" : @"0", result.response.allHeaderFields[@"X-Hop"]);
        if (extra.boolValue) XCTAssertNotNil(result.response.allHeaderFields[@"Location"]);
        NSMutableArray *expected = [NSMutableArray array];
        for (NSUInteger i = 0; i <= budget.unsignedIntegerValue; i++) {
          [expected addObject:[NSString stringWithFormat:@"%@/%lu", prefix, (unsigned long)(hops-i)]];
        }
        NSArray *trace = self.trace;
        XCTAssertEqualObjects(expected, [trace subarrayWithRange:NSMakeRange(before, trace.count-before)]);
      }
    }
  }
}

- (void)testReasonPhraseAbsenceForProtocolsWithoutPhrases {
  XCTAssertNil(ALNHTTPReceivedReasonPhraseFromStatusLine(@"HTTP/2 200\r\n"));
  XCTAssertNil(ALNHTTPReceivedReasonPhraseFromStatusLine(@"HTTP/3 503\r\n"));
  XCTAssertEqualObjects(@"", ALNHTTPReceivedReasonPhraseFromStatusLine(@"HTTP/1.1 200\r\n"));
  XCTAssertEqualObjects(@" Custom  ", ALNHTTPReceivedReasonPhraseFromStatusLine(@"HTTP/1.0 503  Custom  \r\n"));
}

- (void)testResultReceivedReasonPhraseSelectsFinalHeaderBlock {
  NSDictionary *cases = @{@"/ok":@"OK", @"/reason-custom":@"Extractor Unavailable  ",
                         @"/reason-empty":@"", @"/reason-interim":@"Final Phrase", @"/reason-redirect":@""};
  for (NSString *path in cases) {
    NSError *error = nil;
    ALNHTTPClientResult *result = ALNSynchronousHTTPResult([self requestForPath:path timeout:3], 3,
        ALNHTTPRedirectLimitReturnResponse, &error);
    XCTAssertNil(error);
    XCTAssertEqualObjects(cases[path], result.receivedReasonPhrase);
    XCTAssertEqualObjects(@"{}", [[NSString alloc] initWithData:result.body encoding:NSUTF8StringEncoding]);
    XCTAssertNil(result.response.allHeaderFields[@"X-Stale"]);
  }
}

- (void)testResultErrorsAndLoopBudget {
  NSError *error = nil;
  NSUInteger before = self.trace.count;
  ALNHTTPClientResult *result = ALNSynchronousHTTPResult([self requestForPath:@"/loop" timeout:3], 3,
      ALNHTTPRedirectLimitReturnResponse, &error);
  XCTAssertNil(error);
  XCTAssertEqual(302, result.response.statusCode);
  XCTAssertTrue(result.stoppedAtRedirectLimit);
  XCTAssertEqual(before + 4, self.trace.count);
  for (NSString *path in @[@"/budget/4", @"/redirect-timeout", @"/redirect-file", @"/disconnect"]) {
    error = nil;
    result = ALNSynchronousHTTPResult([self requestForPath:path timeout:0.2], 3, ALNHTTPRedirectLimitError, &error);
    XCTAssertNil(result);
    XCTAssertEqualObjects(NSURLErrorDomain, error.domain);
    NSInteger code = [path isEqualToString:@"/budget/4"] ? NSURLErrorHTTPTooManyRedirects :
        ([path isEqualToString:@"/redirect-timeout"] ? NSURLErrorTimedOut :
         ([path isEqualToString:@"/redirect-file"] ? NSURLErrorUnsupportedURL : NSURLErrorNetworkConnectionLost));
    XCTAssertEqual(code, error.code);
  }
  result = ALNSynchronousHTTPResult([self requestForPath:@"/budget/1" timeout:3], 0, ALNHTTPRedirectLimitError, &error);
  XCTAssertNil(error);
  XCTAssertEqual(302, result.response.statusCode);
}

- (void)testResultRedirectMethodsBodiesAndCredentialBoundaries {
  for (NSNumber *status in @[@301, @302, @303, @307, @308]) {
    NSMutableURLRequest *request = [self requestForPath:[NSString stringWithFormat:@"/method/%@", status] timeout:3];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [@"payload" dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"Bearer test" forHTTPHeaderField:@"Authorization"];
    NSError *error = nil;
    ALNHTTPClientResult *result = ALNSynchronousHTTPResult(request, 1, ALNHTTPRedirectLimitReturnResponse, &error);
    XCTAssertNil(error);
    NSDictionary *echo = [NSJSONSerialization JSONObjectWithData:result.body options:0 error:&error];
    XCTAssertNil(error);
    BOOL preserve = status.integerValue >= 307;
    XCTAssertEqualObjects(preserve ? @"POST" : @"GET", echo[@"method"]);
    XCTAssertEqualObjects(preserve ? @"payload" : @"", echo[@"body"]);
    XCTAssertEqualObjects(@"Bearer test", echo[@"headers"][@"authorization"]);
  }
  NSMutableURLRequest *request = [self requestForPath:@"/cross-origin" timeout:3];
  [request setValue:@"Bearer secret" forHTTPHeaderField:@"Authorization"];
  [request setValue:@"session=secret" forHTTPHeaderField:@"Cookie"];
  NSError *error = nil;
  ALNHTTPClientResult *result = ALNSynchronousHTTPResult(request, 1, ALNHTTPRedirectLimitReturnResponse, &error);
  XCTAssertNil(error);
  NSDictionary *echo = [NSJSONSerialization JSONObjectWithData:result.body options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertNil(echo[@"headers"][@"authorization"]);
  XCTAssertNil(echo[@"headers"][@"cookie"]);
}

- (void)testImmediateResponseCompletes {
  XCTAssertTrue(_port > 0);
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = ALNSynchronousURLRequest([self requestForPath:@"/ok" timeout:3], &response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"{}", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
  XCTAssertTrue([response isKindOfClass:[NSHTTPURLResponse class]]);
  XCTAssertEqual(200, [(NSHTTPURLResponse *)response statusCode]);
  XCTAssertEqualObjects(@[ @"/ok" ], [self trace]);
}

- (void)testRelativeRedirectIsFollowed {
  XCTAssertTrue(_port > 0);
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
  NSData *data = ALNSynchronousURLRequest([self requestForPath:@"/redirect" timeout:3], &response, &error);
  NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"{}", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
  XCTAssertEqual(200, [(NSHTTPURLResponse *)response statusCode]);
  XCTAssertEqualObjects(@"/ok", response.URL.path);
  XCTAssertTrue(elapsed < 2.0, @"redirect took %f seconds", elapsed);
  XCTAssertEqualObjects((@[ @"/redirect", @"/ok" ]), [self trace]);
}

- (void)testAbsoluteSameOriginRedirectIsFollowed {
  XCTAssertTrue(_port > 0);
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = ALNSynchronousURLRequest([self requestForPath:@"/redirect-absolute" timeout:3], &response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"{}", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
  XCTAssertEqual(200, [(NSHTTPURLResponse *)response statusCode]);
  XCTAssertEqualObjects(@"/ok", response.URL.path);
  XCTAssertEqualObjects((@[ @"/redirect-absolute", @"/ok" ]), [self trace]);
}

- (void)testBoundedRedirectChainIsFollowedWithinBudget {
  XCTAssertTrue(_port > 0);
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = ALNSynchronousURLRequest([self requestForPath:@"/chain/3" timeout:3], &response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"{}", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
  XCTAssertEqual(200, [(NSHTTPURLResponse *)response statusCode]);
  XCTAssertEqualObjects((@[ @"/chain/3", @"/chain/2", @"/chain/1", @"/ok" ]), [self trace]);
}

- (void)testRedirectBudgetIsEnforced {
  XCTAssertTrue(_port > 0);
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = ALNSynchronousURLRequestFollowingRedirects([self requestForPath:@"/chain/3" timeout:3], 2,
                                                            &response, &error);
  XCTAssertNil(data);
  XCTAssertNil(response);
  XCTAssertEqualObjects(NSURLErrorDomain, error.domain);
  XCTAssertEqual(NSURLErrorHTTPTooManyRedirects, error.code);
  XCTAssertEqualObjects((@[ @"/chain/3", @"/chain/2", @"/chain/1" ]), [self trace]);
}

- (void)testRedirectLoopIsRejected {
  XCTAssertTrue(_port > 0);
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
  NSData *data = ALNSynchronousURLRequest([self requestForPath:@"/loop" timeout:5], &response, &error);
  NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
  XCTAssertNil(data);
  XCTAssertEqualObjects(NSURLErrorDomain, error.domain);
  XCTAssertEqual(NSURLErrorHTTPTooManyRedirects, error.code);
  XCTAssertTrue(elapsed < 4.0, @"loop rejection took %f seconds", elapsed);
  XCTAssertEqual(ALNSynchronousURLRequestDefaultMaxRedirects + 1, [self trace].count);
}

- (void)testZeroRedirectBudgetReturnsRedirectResponse {
  XCTAssertTrue(_port > 0);
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = ALNSynchronousURLRequestFollowingRedirects([self requestForPath:@"/redirect" timeout:3], 0,
                                                            &response, &error);
  XCTAssertNil(error);
  XCTAssertNotNil(data);
  XCTAssertEqual(302, [(NSHTTPURLResponse *)response statusCode]);
  NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
  NSString *location = nil;
  for (NSString *key in headers) {
    if ([key caseInsensitiveCompare:@"Location"] == NSOrderedSame) location = headers[key];
  }
  XCTAssertEqualObjects(@"/ok", location);
  XCTAssertEqualObjects(@[ @"/redirect" ], [self trace]);
}

- (void)testHTTPErrorStatusIsAResponseNotAnError {
  XCTAssertTrue(_port > 0);
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = ALNSynchronousURLRequest([self requestForPath:@"/status" timeout:3], &response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"{}", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
  XCTAssertEqual(503, [(NSHTTPURLResponse *)response statusCode]);
}

- (void)testGenuineTimeoutReportsTimedOut {
  XCTAssertTrue(_port > 0);
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
  NSData *data = ALNSynchronousURLRequest([self requestForPath:@"/timeout" timeout:0.3], &response, &error);
  NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
  XCTAssertNil(data);
  XCTAssertEqualObjects(NSURLErrorDomain, error.domain);
  XCTAssertEqual(NSURLErrorTimedOut, error.code);
  XCTAssertTrue(elapsed >= 0.25, @"%f", elapsed);
  XCTAssertTrue(elapsed < 0.9, @"timeout took %f seconds", elapsed);
}

@end
