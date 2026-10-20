#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>

#import "ALNRequest.h"
#import "ALNPercentDecoding.h"
#import "../shared/ALNTestSupport.h"

@interface RequestTests : XCTestCase
@end

@implementation RequestTests

- (void)testEmptyTransferEncodingCannotFallBackToContentLength {
  for (NSNumber *backend in @[@(ALNHTTPParserBackendLegacy), @(ALNHTTPParserBackendLLHTTP)]) {
    if (backend.integerValue == ALNHTTPParserBackendLLHTTP && ![ALNRequest isLLHTTPAvailable]) continue;
    for (NSString *value in @[@"", @" ", @"\t"]) {
      NSString *raw = [NSString stringWithFormat:@"POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding:%@\r\nContent-Length: 1\r\n\r\nxGET / HTTP/1.1\r\nHost: localhost\r\n\r\n", value];
      NSError *error = nil;
      XCTAssertNil([ALNRequest requestFromRawData:[raw dataUsingEncoding:NSUTF8StringEncoding]
                                       backend:backend.integerValue error:&error]);
      XCTAssertNotNil(error);
    }
  }
}

- (NSArray<NSNumber *> *)allBackends {
  NSMutableArray<NSNumber *> *backends = [NSMutableArray array];
  if ([ALNRequest isLLHTTPAvailable]) {
    [backends addObject:@(ALNHTTPParserBackendLLHTTP)];
  }
  [backends addObject:@(ALNHTTPParserBackendLegacy)];
  return backends;
}

- (NSString *)backendName:(ALNHTTPParserBackend)backend {
  return [ALNRequest parserBackendNameForBackend:backend] ?: @"unknown";
}

- (void)testStrictPercentDecoderHasOneCrossPlatformPolicy {
  XCTAssertEqualObjects(@"a b", ALNPercentDecodedString(@"a+b", YES));
  XCTAssertEqualObjects(@"a+b", ALNPercentDecodedString(@"a+b", NO));
  XCTAssertEqualObjects(@"a/b", ALNPercentDecodedString(@"a%2Fb", NO));
  XCTAssertEqualObjects(@"caf\u00e9", ALNPercentDecodedString(@"caf%C3%A9", YES));
  XCTAssertEqualObjects(@"%41", ALNPercentDecodedString(@"%2541", YES));
  for (NSString *invalid in @[ @"%zz", @"a%2", @"%G1", @"a%00b", @"%C0%AF",
                               @"%ED%A0%80", @"%F4%90%80%80", @"%FF" ]) {
    XCTAssertNil(ALNPercentDecodedString(invalid, YES), @"%@", invalid);
  }
}

- (void)testMalformedQueryEscapesRemainWholeAcrossBackends {
  NSString *raw = @"GET /?bad=a%00b&malformed=a%2&utf=%C0%AF&good=a%2Fb&space=a+b HTTP/1.1\r\n"
                  "Host: localhost\r\n\r\n";
  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:[raw dataUsingEncoding:NSUTF8StringEncoding]
                                                   backend:backend error:&error];
    XCTAssertNotNil(request, @"backend=%@ error=%@", [self backendName:backend], error);
    if (request == nil) continue;
    NSDictionary *expected = @{ @"bad" : @"a%00b", @"malformed" : @"a%2", @"utf" : @"%C0%AF",
                                @"good" : @"a/b", @"space" : @"a b" };
    XCTAssertEqualObjects(expected, request.queryParams, @"backend=%@", [self backendName:backend]);
    for (NSString *key in expected) {
      XCTAssertEqualObjects(expected[key], [request queryValueForName:key], @"backend=%@ key=%@",
                            [self backendName:backend], key);
    }
  }
}

- (void)testParsesRequestLineAndQueryParamsAcrossBackends {
  NSString *raw = @"GET /items/list?name=Peggy+Hill&city=Arlen HTTP/1.1\r\n"
                  "Host: localhost\r\n"
                  "X-Test: 1\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:data backend:backend error:&error];

    XCTAssertNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"GET", request.method, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"/items/list", request.path, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"HTTP/1.1", request.httpVersion, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"Peggy Hill", request.queryParams[@"name"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"Arlen", request.queryParams[@"city"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"1", request.headers[@"x-test"], @"backend=%@", [self backendName:backend]);
  }
}

- (void)testPreservesBinaryBodyBytesAcrossBackends {
  NSString *header = @"POST /upload HTTP/1.1\r\n"
                     "Host: localhost\r\n"
                     "Content-Length: 4\r\n\r\n";
  NSMutableData *raw = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
  unsigned char bytes[4] = {0x00, 0xFF, 0x10, 0x7F};
  [raw appendBytes:bytes length:4];

  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:raw backend:backend error:&error];

    XCTAssertNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertEqual((NSUInteger)4, [request.body length], @"backend=%@", [self backendName:backend]);
    const unsigned char *bodyBytes = [request.body bytes];
    XCTAssertEqual((unsigned char)0x00, bodyBytes[0], @"backend=%@", [self backendName:backend]);
    XCTAssertEqual((unsigned char)0xFF, bodyBytes[1], @"backend=%@", [self backendName:backend]);
    XCTAssertEqual((unsigned char)0x10, bodyBytes[2], @"backend=%@", [self backendName:backend]);
    XCTAssertEqual((unsigned char)0x7F, bodyBytes[3], @"backend=%@", [self backendName:backend]);
  }
}

- (void)testInvalidHeaderEncodingReturnsErrorAcrossBackends {
  NSMutableData *raw = [NSMutableData data];
  unsigned char invalidHeader[3] = {0xC3, 0x28, 0x0A};
  [raw appendBytes:invalidHeader length:3];

  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:raw backend:backend error:&error];

    XCTAssertNil(request, @"backend=%@", [self backendName:backend]);
    XCTAssertNotNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(ALNRequestErrorDomain, error.domain, @"backend=%@", [self backendName:backend]);
  }
}

- (void)testParsesCookiesFromHeaderAcrossBackends {
  NSString *raw = @"GET / HTTP/1.1\r\n"
                  "Host: localhost\r\n"
                  "Cookie: a=1; b=two\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:data backend:backend error:&error];

    XCTAssertNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"1", request.cookies[@"a"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"two", request.cookies[@"b"], @"backend=%@", [self backendName:backend]);
  }
}

// Issue 213 (RFC 9112 §3.2): an HTTP/1.1 request needs exactly one Host.
- (void)testHostHeaderMustAppearExactlyOnceOnHTTP11AcrossBackends {
  NSDictionary<NSString *, NSNumber *> *cases = @{
    @"GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n" : @NO,
    @"GET / HTTP/1.1\r\nhost: a\r\nHOST: a\r\n\r\n" : @NO,
    @"GET / HTTP/1.1\r\nX-Test: 1\r\n\r\n" : @NO,
    @"GET / HTTP/1.0\r\nX-Test: 1\r\n\r\n" : @YES,
    @"GET / HTTP/1.1\r\nHost: a\r\n\r\n" : @YES,
  };
  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    for (NSString *raw in cases) {
      NSError *error = nil;
      ALNRequest *request = [ALNRequest requestFromRawData:[raw dataUsingEncoding:NSUTF8StringEncoding]
                                                   backend:backend
                                                     error:&error];
      if ([cases[raw] boolValue]) {
        XCTAssertNotNil(request, @"backend=%@ raw=%@ error=%@", [self backendName:backend], raw, error);
      } else {
        XCTAssertNil(request, @"backend=%@ raw=%@", [self backendName:backend], raw);
        XCTAssertNotNil(error, @"backend=%@ raw=%@", [self backendName:backend], raw);
      }
    }
  }
}

// Issue 213 (RFC 9112 §3.2.2): an absolute-form target routes by its path,
// and its authority replaces the Host header.
- (void)testAbsoluteFormTargetUsesItsPathAndAuthorityAcrossBackends {
  NSString *raw = @"GET http://example.test:8080/items/list?name=Peggy HTTP/1.1\r\n"
                  "Host: ignored.test\r\n"
                  "X-Test: 1\r\n\r\n";
  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:[raw dataUsingEncoding:NSUTF8StringEncoding]
                                                 backend:backend
                                                   error:&error];
    XCTAssertNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"/items/list", request.path, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"Peggy", request.queryParams[@"name"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"example.test:8080", [request headerValueForName:@"host"],
                          @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"example.test:8080", request.headers[@"host"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"1", request.headers[@"x-test"], @"backend=%@", [self backendName:backend]);
  }
  NSString *bare = @"GET HTTPS://example.test HTTP/1.1\r\n\r\n";
  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:[bare dataUsingEncoding:NSUTF8StringEncoding]
                                                 backend:backend
                                                   error:&error];
    XCTAssertNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"/", request.path, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"example.test", [request headerValueForName:@"host"], @"backend=%@",
                          [self backendName:backend]);
  }
}

- (void)testDefaultsHTTPVersionWhenMissingFromRequestLineAcrossBackends {
  NSString *raw = @"GET /healthz\r\n"
                  "Host: localhost\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:data backend:backend error:&error];

    XCTAssertNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"HTTP/1.1", request.httpVersion, @"backend=%@", [self backendName:backend]);
  }
}

- (void)testLLHTTPMissingVersionFallbackPreservesBodyHeadersAndQuery {
  if (![ALNRequest isLLHTTPAvailable]) {
    return;
  }

  NSString *raw = @"POST /legacy/items?x=1&y=two\r\n"
                  "Host: localhost\r\n"
                  "Cookie: sid=abc123\r\n"
                  "X-Trace: zzz\r\n"
                  "Content-Length: 7\r\n\r\n"
                  "payload";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  NSError *llhttpError = nil;
  ALNRequest *llhttp = [ALNRequest requestFromRawData:data
                                              backend:ALNHTTPParserBackendLLHTTP
                                                error:&llhttpError];
  XCTAssertNil(llhttpError);
  XCTAssertNotNil(llhttp);

  NSError *legacyError = nil;
  ALNRequest *legacy = [ALNRequest requestFromRawData:data
                                              backend:ALNHTTPParserBackendLegacy
                                                error:&legacyError];
  XCTAssertNil(legacyError);
  XCTAssertNotNil(legacy);

  if (llhttp == nil || legacy == nil) {
    return;
  }

  XCTAssertEqualObjects(@"HTTP/1.1", llhttp.httpVersion);
  XCTAssertEqualObjects(legacy.method, llhttp.method);
  XCTAssertEqualObjects(legacy.path, llhttp.path);
  XCTAssertEqualObjects(legacy.queryString, llhttp.queryString);
  XCTAssertEqualObjects(legacy.headers, llhttp.headers);
  XCTAssertEqualObjects(legacy.body, llhttp.body);
  XCTAssertEqualObjects(legacy.queryParams, llhttp.queryParams);
  XCTAssertEqualObjects(legacy.cookies, llhttp.cookies);
}

- (void)testQueryParamsAndCookiesAreCachedAfterFirstAccessAcrossBackends {
  NSString *raw = @"GET /items/list?name=Peggy+Hill&city=Arlen HTTP/1.1\r\n"
                  "Host: localhost\r\n"
                  "Cookie: sid=abc123; role=admin\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:data backend:backend error:&error];
    XCTAssertNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertNotNil(request, @"backend=%@", [self backendName:backend]);
    if (request == nil) {
      continue;
    }

    NSDictionary *queryParamsFirst = request.queryParams;
    NSDictionary *queryParamsSecond = request.queryParams;
    NSDictionary *cookiesFirst = request.cookies;
    NSDictionary *cookiesSecond = request.cookies;

    XCTAssertEqualObjects(@"Peggy Hill", queryParamsFirst[@"name"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"Arlen", queryParamsFirst[@"city"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"abc123", cookiesFirst[@"sid"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"admin", cookiesFirst[@"role"], @"backend=%@", [self backendName:backend]);
    XCTAssertTrue(queryParamsFirst == queryParamsSecond, @"backend=%@", [self backendName:backend]);
    XCTAssertTrue(cookiesFirst == cookiesSecond, @"backend=%@", [self backendName:backend]);
  }
}

- (void)testQueryValueForNameReturnsDecodedLastValueAcrossBackends {
  NSString *raw = @"GET /items/list?name=Peggy+Hill&empty&encoded%20key=value+two&name=Bobby HTTP/1.1\r\n"
                  "Host: localhost\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:data backend:backend error:&error];
    XCTAssertNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertNotNil(request, @"backend=%@", [self backendName:backend]);
    if (request == nil) {
      continue;
    }

    XCTAssertEqualObjects(@"Bobby", [request queryValueForName:@"name"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"", [request queryValueForName:@"empty"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"value two", [request queryValueForName:@"encoded key"], @"backend=%@", [self backendName:backend]);
    XCTAssertNil([request queryValueForName:@"missing"], @"backend=%@", [self backendName:backend]);
  }
}

- (void)testHeaderValueForNameFindsDeferredHeadersAcrossBackends {
  NSString *raw = @"GET /items/list HTTP/1.1\r\n"
                  "Host: localhost\r\n"
                  "X-Custom-Trace: trace-value\r\n"
                  "X-Another-Header: another-value\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:data backend:backend error:&error];
    XCTAssertNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertNotNil(request, @"backend=%@", [self backendName:backend]);
    if (request == nil) {
      continue;
    }

    XCTAssertEqualObjects(@"trace-value", [request headerValueForName:@"X-Custom-Trace"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"trace-value", [request headerValueForName:@"x-custom-trace"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"another-value", [request headerValueForName:@"X-Another-Header"], @"backend=%@", [self backendName:backend]);
  }
}

- (void)testQueryValueForNameCachesRepeatedLookupsAcrossBackends {
  NSString *raw = @"GET /items/list?name=Peggy+Hill&empty&encoded%20key=value+two&name=Bobby HTTP/1.1\r\n"
                  "Host: localhost\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  for (NSNumber *backendValue in [self allBackends]) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:data backend:backend error:&error];
    XCTAssertNil(error, @"backend=%@", [self backendName:backend]);
    XCTAssertNotNil(request, @"backend=%@", [self backendName:backend]);
    if (request == nil) {
      continue;
    }

    for (NSUInteger idx = 0; idx < 5; idx++) {
      XCTAssertEqualObjects(@"Bobby", [request queryValueForName:@"name"], @"backend=%@", [self backendName:backend]);
      XCTAssertEqualObjects(@"value two", [request queryValueForName:@"encoded key"], @"backend=%@", [self backendName:backend]);
      XCTAssertEqualObjects(@"", [request queryValueForName:@"empty"], @"backend=%@", [self backendName:backend]);
      XCTAssertNil([request queryValueForName:@"missing"], @"backend=%@", [self backendName:backend]);
    }

    NSDictionary *queryParams = [request queryParams];
    XCTAssertEqualObjects(@"Bobby", queryParams[@"name"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"value two", queryParams[@"encoded key"], @"backend=%@", [self backendName:backend]);
    XCTAssertEqualObjects(@"", queryParams[@"empty"], @"backend=%@", [self backendName:backend]);
  }
}

- (void)testLLHTTPDeferredHeaderValueLookupRemainsStableAcrossRepeatedAccess {
  if (![ALNRequest isLLHTTPAvailable]) {
    return;
  }

  NSString *raw = @"GET /items/list HTTP/1.1\r\n"
                  "Host: localhost\r\n"
                  "X-Custom-Trace: trace-value\r\n"
                  "X-Another-Header: another-value\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  ALNRequest *request = [ALNRequest requestFromRawData:data
                                               backend:ALNHTTPParserBackendLLHTTP
                                                 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(request);
  if (request == nil) {
    return;
  }

  for (NSUInteger idx = 0; idx < 5; idx++) {
    XCTAssertEqualObjects(@"trace-value", [request headerValueForName:@"X-Custom-Trace"]);
    XCTAssertEqualObjects(@"another-value", [request headerValueForName:@"X-Another-Header"]);
  }

  NSDictionary *headers = [request headers];
  XCTAssertEqualObjects(@"trace-value", headers[@"x-custom-trace"]);
  XCTAssertEqualObjects(@"another-value", headers[@"x-another-header"]);
  XCTAssertEqualObjects(@"trace-value", [request headerValueForName:@"X-Custom-Trace"]);
}

- (void)testLegacyParserRejectsDuplicateContentLengthHeader {
  NSString *raw = @"POST /upload HTTP/1.1\r\n"
                  "Host: localhost\r\n"
                  "Content-Length: 5\r\n"
                  "Content-Length: 5\r\n\r\n"
                  "hello";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  ALNRequest *request = [ALNRequest requestFromRawData:data
                                               backend:ALNHTTPParserBackendLegacy
                                                 error:&error];
  XCTAssertNil(request);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.localizedDescription containsString:@"Duplicate Content-Length"]);
}

- (void)testLegacyParserRejectsTransferEncodingHeader {
  NSString *raw = @"POST /upload HTTP/1.1\r\n"
                  "Host: localhost\r\n"
                  "Transfer-Encoding: chunked\r\n\r\n";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  ALNRequest *request = [ALNRequest requestFromRawData:data
                                               backend:ALNHTTPParserBackendLegacy
                                                 error:&error];
  XCTAssertNil(request);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.localizedDescription containsString:@"Unsupported Transfer-Encoding"]);
}

- (void)testResolvedParserBackendDefaultsToLLHTTPAndAllowsLegacyOverride {
  unsetenv("ARLEN_HTTP_PARSER_BACKEND");
  ALNHTTPParserBackend expectedDefaultBackend =
      [ALNRequest isLLHTTPAvailable] ? ALNHTTPParserBackendLLHTTP : ALNHTTPParserBackendLegacy;
  XCTAssertEqual(expectedDefaultBackend, [ALNRequest resolvedParserBackend]);
  XCTAssertEqualObjects([ALNRequest isLLHTTPAvailable] ? @"llhttp" : @"legacy",
                        [ALNRequest resolvedParserBackendName]);

  setenv("ARLEN_HTTP_PARSER_BACKEND", "legacy", 1);
  XCTAssertEqual(ALNHTTPParserBackendLegacy, [ALNRequest resolvedParserBackend]);
  XCTAssertEqualObjects(@"legacy", [ALNRequest resolvedParserBackendName]);

  unsetenv("ARLEN_HTTP_PARSER_BACKEND");
}

- (void)testLLHTTPVersionLooksValid {
  NSString *version = [ALNRequest llhttpVersion];
  if (![ALNRequest isLLHTTPAvailable]) {
    XCTAssertEqualObjects(@"disabled", version);
    return;
  }
  XCTAssertTrue([version isKindOfClass:[NSString class]]);
  NSRange match = [version rangeOfString:@"^\\d+\\.\\d+\\.\\d+$"
                                 options:NSRegularExpressionSearch];
  XCTAssertNotEqual((NSUInteger)NSNotFound, match.location);
}

- (void)testLLHTTPAndLegacyParsersProduceEquivalentRequestObject {
  if (![ALNRequest isLLHTTPAvailable]) {
    return;
  }

  NSString *raw = @"POST /v1/ping?x=1&y=two HTTP/1.1\r\n"
                  "Host: localhost\r\n"
                  "X-Trace: abc123\r\n"
                  "Cookie: sid=xyz; role=admin\r\n"
                  "Content-Length: 17\r\n\r\n"
                  "{\"hello\":\"world\"}";
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  NSError *llhttpError = nil;
  ALNRequest *llhttp = [ALNRequest requestFromRawData:data
                                              backend:ALNHTTPParserBackendLLHTTP
                                                error:&llhttpError];
  XCTAssertNil(llhttpError);
  XCTAssertNotNil(llhttp);

  NSError *legacyError = nil;
  ALNRequest *legacy = [ALNRequest requestFromRawData:data
                                              backend:ALNHTTPParserBackendLegacy
                                                error:&legacyError];
  XCTAssertNil(legacyError);
  XCTAssertNotNil(legacy);

  if (llhttp == nil || legacy == nil) {
    return;
  }

  XCTAssertEqualObjects(legacy.method, llhttp.method);
  XCTAssertEqualObjects(legacy.path, llhttp.path);
  XCTAssertEqualObjects(legacy.queryString, llhttp.queryString);
  XCTAssertEqualObjects(legacy.httpVersion, llhttp.httpVersion);
  XCTAssertEqualObjects(legacy.headers, llhttp.headers);
  XCTAssertEqualObjects(legacy.body, llhttp.body);
  XCTAssertEqualObjects(legacy.queryParams, llhttp.queryParams);
  XCTAssertEqualObjects(legacy.cookies, llhttp.cookies);
}

- (void)testLLHTTPAndLegacyParsersHandleLargePathAndHeaderWhitespace {
  if (![ALNRequest isLLHTTPAvailable]) {
    return;
  }

  NSMutableString *largeSegment = [NSMutableString string];
  for (NSUInteger idx = 0; idx < 2048; idx++) {
    [largeSegment appendString:@"ab"];
  }
  NSString *path = [NSString stringWithFormat:@"/api/echo/%@", largeSegment];
  NSString *raw = [NSString stringWithFormat:@"GET %@?k=v HTTP/1.1\r\n"
                                         "Host: localhost\r\n"
                                         "X-Trace:\t  trace-value  \r\n"
                                         "Cookie: sid=abc123\r\n\r\n",
                                         path];
  NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];

  NSError *llhttpError = nil;
  ALNRequest *llhttp = [ALNRequest requestFromRawData:data
                                              backend:ALNHTTPParserBackendLLHTTP
                                                error:&llhttpError];
  XCTAssertNil(llhttpError);
  XCTAssertNotNil(llhttp);

  NSError *legacyError = nil;
  ALNRequest *legacy = [ALNRequest requestFromRawData:data
                                              backend:ALNHTTPParserBackendLegacy
                                                error:&legacyError];
  XCTAssertNil(legacyError);
  XCTAssertNotNil(legacy);

  if (llhttp == nil || legacy == nil) {
    return;
  }

  XCTAssertEqualObjects(legacy.path, llhttp.path);
  XCTAssertEqualObjects(legacy.queryString, llhttp.queryString);
  XCTAssertEqualObjects(@"trace-value", llhttp.headers[@"x-trace"]);
  XCTAssertEqualObjects(@"trace-value", legacy.headers[@"x-trace"]);
  XCTAssertEqualObjects(@"abc123", llhttp.cookies[@"sid"]);
  XCTAssertEqualObjects(@"abc123", legacy.cookies[@"sid"]);
}

- (void)testBufferedLLHTTPParserReturnsNilUntilRequestComplete {
  if (![ALNRequest isLLHTTPAvailable]) {
    return;
  }

  NSString *partialRaw = @"GET /healthz HTTP/1.1\r\nHost: localhost\r\n";
  NSData *partialData = [partialRaw dataUsingEncoding:NSUTF8StringEncoding];
  NSUInteger consumedLength = 999;
  BOOL headersComplete = YES;
  NSInteger contentLength = -1;
  NSError *partialError = nil;
  ALNRequest *partialRequest = [ALNRequest requestFromBufferedData:partialData
                                                           backend:ALNHTTPParserBackendLLHTTP
                                                    consumedLength:&consumedLength
                                                   headersComplete:&headersComplete
                                                     contentLength:&contentLength
                                                             error:&partialError];
  XCTAssertNil(partialRequest);
  XCTAssertNil(partialError);
  XCTAssertEqual((NSUInteger)0, consumedLength);
  XCTAssertFalse(headersComplete);

  NSString *completeRaw = [partialRaw stringByAppendingString:@"\r\n"];
  NSData *completeData = [completeRaw dataUsingEncoding:NSUTF8StringEncoding];
  consumedLength = 0;
  headersComplete = NO;
  contentLength = -1;
  NSError *completeError = nil;
  ALNRequest *completeRequest = [ALNRequest requestFromBufferedData:completeData
                                                            backend:ALNHTTPParserBackendLLHTTP
                                                     consumedLength:&consumedLength
                                                    headersComplete:&headersComplete
                                                      contentLength:&contentLength
                                                              error:&completeError];
  XCTAssertNil(completeError);
  XCTAssertNotNil(completeRequest);
  XCTAssertEqualObjects(@"GET", completeRequest.method);
  XCTAssertEqualObjects(@"/healthz", completeRequest.path);
  XCTAssertTrue(headersComplete);
  XCTAssertEqual((NSInteger)0, contentLength);
  XCTAssertEqual([completeData length], consumedLength);
}

- (void)testBufferedLLHTTPParserReportsConsumedLengthForPipelinedRequests {
  if (![ALNRequest isLLHTTPAvailable]) {
    return;
  }

  NSString *firstRaw = @"GET /one HTTP/1.1\r\nHost: localhost\r\n\r\n";
  NSString *secondRaw = @"GET /two HTTP/1.1\r\nHost: localhost\r\n\r\n";
  NSData *buffer = [[firstRaw stringByAppendingString:secondRaw] dataUsingEncoding:NSUTF8StringEncoding];
  NSUInteger consumedLength = 0;
  BOOL headersComplete = NO;
  NSInteger contentLength = -1;
  NSError *error = nil;
  ALNRequest *first = [ALNRequest requestFromBufferedData:buffer
                                                  backend:ALNHTTPParserBackendLLHTTP
                                           consumedLength:&consumedLength
                                          headersComplete:&headersComplete
                                            contentLength:&contentLength
                                                    error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(first);
  XCTAssertEqualObjects(@"/one", first.path);
  XCTAssertTrue(headersComplete);
  XCTAssertEqual((NSInteger)0, contentLength);
  XCTAssertTrue(consumedLength > 0);
  XCTAssertTrue(consumedLength < [buffer length]);

  NSData *remainder = [buffer subdataWithRange:NSMakeRange(consumedLength, [buffer length] - consumedLength)];
  NSUInteger secondConsumedLength = 0;
  BOOL secondHeadersComplete = NO;
  NSInteger secondContentLength = -1;
  NSError *secondError = nil;
  ALNRequest *second = [ALNRequest requestFromBufferedData:remainder
                                                   backend:ALNHTTPParserBackendLLHTTP
                                            consumedLength:&secondConsumedLength
                                           headersComplete:&secondHeadersComplete
                                             contentLength:&secondContentLength
                                                     error:&secondError];
  XCTAssertNil(secondError);
  XCTAssertNotNil(second);
  XCTAssertEqualObjects(@"/two", second.path);
  XCTAssertTrue(secondHeadersComplete);
  XCTAssertEqual((NSInteger)0, secondContentLength);
  XCTAssertEqual([remainder length], secondConsumedLength);
}

// The server parses from its connection buffer without copying and then shifts
// the next pipelined request to the front of that buffer. Headers read after
// the shift must still be the ones this request sent.
- (void)testBufferedLLHTTPHeadersSurviveThePipelinedBufferBeingReused {
  if (![ALNRequest isLLHTTPAvailable]) {
    return;
  }

  NSArray<NSString *> *raws = @[
    @"GET /one HTTP/1.1\r\nHost: first.example\r\nX-User: alice\r\nAuthorization: Bearer AAAAAAAAAAAA\r\n\r\n",
    @"GET /two HTTP/1.1\r\nHost: second.example\r\nX-User: mallory-padding\r\n"
    @"Authorization: Bearer BBBBBBBBBBBB\r\nUser-Agent: second-agent\r\n\r\n",
    @"GET /three HTTP/1.1\r\nHost: third.example\r\nX-User: carol\r\nConnection: close\r\n\r\n",
  ];
  NSMutableData *buffer = [NSMutableData data];
  for (NSString *raw in raws) {
    [buffer appendData:[raw dataUsingEncoding:NSUTF8StringEncoding]];
  }

  NSMutableArray<ALNRequest *> *requests = [NSMutableArray array];
  while ([buffer length] > 0) {
    NSData *view = [NSData dataWithBytesNoCopy:[buffer mutableBytes] length:[buffer length] freeWhenDone:NO];
    NSUInteger consumedLength = 0;
    BOOL headersComplete = NO;
    NSInteger contentLength = -1;
    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromBufferedData:view
                                                      backend:ALNHTTPParserBackendLLHTTP
                                               consumedLength:&consumedLength
                                              headersComplete:&headersComplete
                                                contentLength:&contentLength
                                                        error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(request);
    if (request == nil || consumedLength == 0) {
      break;
    }
    [requests addObject:request];
    // Shift the rest to the front, overwriting this request's bytes.
    NSUInteger remaining = [buffer length] - consumedLength;
    memmove([buffer mutableBytes], (char *)[buffer mutableBytes] + consumedLength, remaining);
    memset((char *)[buffer mutableBytes] + remaining, 'Z', consumedLength);
    [buffer setLength:remaining];
  }

  XCTAssertEqual((NSUInteger)3, [requests count]);
  if ([requests count] != 3) {
    return;
  }
  XCTAssertEqualObjects(@"first.example", [requests[0] headerValueForName:@"host"]);
  XCTAssertEqualObjects(@"alice", [requests[0] headerValueForName:@"x-user"]);
  XCTAssertEqualObjects(@"Bearer AAAAAAAAAAAA", [requests[0] headerValueForName:@"authorization"]);
  XCTAssertEqual((NSUInteger)0, [[requests[0] headerValueForName:@"user-agent"] length]);
  XCTAssertEqualObjects(@"second.example", [requests[1] headerValueForName:@"host"]);
  XCTAssertEqualObjects(@"mallory-padding", [requests[1] headerValueForName:@"x-user"]);
  XCTAssertEqualObjects(@"Bearer BBBBBBBBBBBB", [requests[1] headerValueForName:@"authorization"]);
  XCTAssertEqualObjects(@"second-agent", [requests[1] headerValueForName:@"user-agent"]);
  XCTAssertEqualObjects(@"third.example", [requests[2] headerValueForName:@"host"]);
  XCTAssertEqualObjects(@"carol", [requests[2] headerValueForName:@"x-user"]);
  XCTAssertEqual((NSUInteger)0, [[requests[2] headerValueForName:@"authorization"] length]);
}


// A handler exception leaks the request (ARC frames unwind without releasing
// them), so the server's explicit removeTemporaryFiles must not depend on the
// request being freed: it releases the request's own mapping of a spooled
// body, and on Windows the spool file can then be deleted.
- (void)testRemovingTemporaryFilesReleasesASpooledBodyWhileTheRequestLives {
  NSString *directory = ALNTestTemporaryDirectory(@"request-spooled-body");
  XCTAssertNotNil(directory);
  NSString *path = [directory stringByAppendingPathComponent:@"arlen-body-test"];
  NSData *payload = [@"a=1&b=2" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertTrue([payload writeToFile:path atomically:NO]);
  NSData *head = [@"POST /explode HTTP/1.1\r\nHost: localhost\r\nContent-Length: 7\r\n\r\n"
      dataUsingEncoding:NSUTF8StringEncoding];
  ALNRequest *request = [ALNRequest requestFromHeadData:head backend:ALNHTTPParserBackendLegacy error:NULL];
  XCTAssertNotNil(request);
  NSError *error = nil;
  XCTAssertTrue([request adoptSpooledBodyAtPath:path error:&error], @"%@", error);
  XCTAssertEqualObjects(payload, request.body);

  [request removeTemporaryFiles];
  XCTAssertEqual((NSUInteger)0, request.body.length);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:path],
                 @"the spool file must go while the request is still alive");
  [request removeTemporaryFiles];
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

@end
