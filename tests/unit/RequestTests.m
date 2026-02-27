#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>

#import "ALNRequest.h"

@interface RequestTests : XCTestCase
@end

@implementation RequestTests

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

@end
