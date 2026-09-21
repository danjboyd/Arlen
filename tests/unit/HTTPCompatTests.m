#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNHTTPCompat.h"

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
