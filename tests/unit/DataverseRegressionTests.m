#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDataverseClient.h"
#import "ALNDataverseQuery.h"
#import "../shared/ALNDataverseTestSupport.h"

@interface DataverseRegressionTests : ALNDataverseTestCase
@end

@implementation DataverseRegressionTests

/// Issue 21: CRLF responses lost every header, because splitting on a newline
/// character set turned each CRLF into two separators and the blank-line
/// handling then ended a block between every pair of header lines.
- (void)testCurlHeaderParsingKeepsHeadersAcrossLineEndings_ISSUE_21 {
  NSDictionary *crlf = ALNDataverseParseHeaders(
      @"HTTP/1.1 201 Created\r\nOData-EntityId: expected\r\nLocation: fallback\r\n\r\n");
  XCTAssertEqualObjects(@"expected", crlf[@"odata-entityid"]);
  XCTAssertEqualObjects(@"fallback", crlf[@"location"]);

  NSDictionary *lf = ALNDataverseParseHeaders(@"HTTP/1.1 201 Created\nOData-EntityId: expected\n\n");
  XCTAssertEqualObjects(@"expected", lf[@"odata-entityid"]);

  NSDictionary *cr = ALNDataverseParseHeaders(@"HTTP/1.1 201 Created\rOData-EntityId: expected\r\r");
  XCTAssertEqualObjects(@"expected", cr[@"odata-entityid"]);
}

/// curl reports every response block it saw, so the parser must select the
/// final one rather than an interim 100 Continue or redirect.
- (void)testCurlHeaderParsingSelectsFinalResponseBlock_ISSUE_21 {
  NSDictionary *continued = ALNDataverseParseHeaders(
      @"HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 201 Created\r\nOData-EntityId: expected\r\n\r\n");
  XCTAssertEqualObjects(@"expected", continued[@"odata-entityid"]);

  NSDictionary *redirected = ALNDataverseParseHeaders(
      @"HTTP/1.1 302 Found\r\nOData-EntityId: stale\r\n\r\nHTTP/2 201\r\nOData-EntityId: expected\r\n\r\n");
  XCTAssertEqualObjects(@"expected", redirected[@"odata-entityid"]);
}

/// The defect dropped every header, not only odata-entityid, so the headers
/// other call sites depend on need coverage of their own.
- (void)testCurlHeaderParsingKeepsOtherHeaderDependentFields_ISSUE_21 {
  NSDictionary *headers = ALNDataverseParseHeaders(@"HTTP/1.1 429 Too Many Requests\r\n"
                                                    "Retry-After: 30\r\n"
                                                    "ETag: W/\"12345\"\r\n"
                                                    "Location: https://fixture.invalid/leads(1)\r\n"
                                                    "WWW-Authenticate: Bearer realm=\"dataverse\"\r\n"
                                                    "\r\n");
  XCTAssertEqualObjects(@"30", headers[@"retry-after"]);
  XCTAssertEqualObjects(@"W/\"12345\"", headers[@"etag"]);
  XCTAssertEqualObjects(@"https://fixture.invalid/leads(1)", headers[@"location"]);
  XCTAssertEqualObjects(@"Bearer realm=\"dataverse\"", headers[@"www-authenticate"]);
}

- (void)testCurlHeaderParsingNormalizesNamesAndPreservesValueColons_ISSUE_21 {
  NSDictionary *headers = ALNDataverseParseHeaders(
      @"HTTP/1.1 200 OK\r\nOData-EntityId: https://fixture.invalid/leads(9)\r\n\r\n");
  // Names lower-cased for lookup; a value containing ':' survives intact.
  XCTAssertEqualObjects(@"https://fixture.invalid/leads(9)", headers[@"odata-entityid"]);
  XCTAssertNil(headers[@"OData-EntityId"]);
}

- (void)testCurlHeaderParsingHandlesEmptyAndHeaderlessInput_ISSUE_21 {
  XCTAssertEqual((NSUInteger)0, [ALNDataverseParseHeaders(@"") count]);
  XCTAssertEqual((NSUInteger)0, [ALNDataverseParseHeaders(nil) count]);
  XCTAssertEqual((NSUInteger)0, [ALNDataverseParseHeaders(@"not a status line\r\n\r\n") count]);
  XCTAssertEqual((NSUInteger)0, [ALNDataverseParseHeaders(@"HTTP/1.1 204 No Content\r\n\r\n") count]);
}

- (void)testBatchAndFunctionEscapeHatchesWork {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  NSString *batchBody =
      @"--batchresponse_123\r\n"
       "Content-Type: application/http\r\n"
       "Content-Transfer-Encoding: binary\r\n"
       "\r\n"
       "HTTP/1.1 200 OK\r\n"
       "Content-Type: application/json; charset=utf-8\r\n"
       "Content-ID: 1\r\n"
       "\r\n"
       "{\"name\":\"Acme\"}\r\n"
       "--batchresponse_123--\r\n";
  NSData *batchData = [batchBody dataUsingEncoding:NSUTF8StringEncoding];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:200
                                                                       headers:@{ @"Content-Type" : @"multipart/mixed; boundary=batchresponse_123" }
                                                                      bodyData:batchData]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{ @"value" : @42 }]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  NSArray<ALNDataverseBatchResponse *> *responses = [client executeBatchRequests:@[
    [ALNDataverseBatchRequest requestWithMethod:@"GET"
                                   relativePath:@"accounts?$top=1"
                                        headers:nil
                                     bodyObject:nil
                                      contentID:@"1"],
  ]
                                                                       error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [responses count]);
  XCTAssertEqual((NSInteger)200, responses[0].statusCode);
  XCTAssertTrue([responses[0].bodyText containsString:@"Acme"]);

  id functionResult = [client invokeFunctionNamed:@"WhoAmI"
                                         boundPath:nil
                                        parameters:@{}
                                             error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(functionResult[@"value"], @42);

  XCTAssertEqual((NSUInteger)2, [transport.capturedRequests count]);
  XCTAssertTrue([transport.capturedRequests[0].URLString hasSuffix:@"/$batch"]);
  XCTAssertEqualObjects(transport.capturedRequests[1].method, @"GET");
  XCTAssertTrue([transport.capturedRequests[1].URLString hasSuffix:@"/WhoAmI()"]);
}

- (void)testThrottleErrorsIncludeStructuredDiagnostics {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:429
                                              headers:@{
                                                @"Content-Type" : @"application/json",
                                                @"Retry-After" : @"17",
                                                @"x-ms-request-id" : @"corr-123",
                                              }
                                           JSONObject:@{ @"error" : @{ @"message" : @"Slow down" } }]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"sales"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  ALNDataverseResponse *response = [client performRequestWithMethod:@"GET"
                                                               path:@"WhoAmI()"
                                                              query:nil
                                                            headers:@{ @"If-Match" : @"W/\"1\"" }
                                                         bodyObject:nil
                                             includeFormattedValues:NO
                                               returnRepresentation:NO
                                                   consistencyCount:NO
                                                              error:&error];
  XCTAssertNil(response);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(error.domain, ALNDataverseErrorDomain);
  XCTAssertEqual((NSInteger)ALNDataverseErrorThrottled, error.code);
  XCTAssertEqualObjects(error.userInfo[ALNDataverseErrorRequestMethodKey], @"GET");
  XCTAssertEqualObjects(error.userInfo[ALNDataverseErrorTargetNameKey], @"sales");
  XCTAssertEqual(17, [error.userInfo[ALNDataverseErrorRetryAfterKey] integerValue]);
  XCTAssertEqualObjects(error.userInfo[ALNDataverseErrorCorrelationIDKey], @"corr-123");
  XCTAssertTrue([error.userInfo[ALNDataverseErrorRequestURLKey] containsString:@"/WhoAmI()"]);

  NSDictionary *requestHeaders = [error.userInfo[ALNDataverseErrorRequestHeadersKey] isKindOfClass:[NSDictionary class]]
                                     ? error.userInfo[ALNDataverseErrorRequestHeadersKey]
                                     : @{};
  XCTAssertEqualObjects(requestHeaders[@"Authorization"], @"Bearer [redacted]");
  XCTAssertEqualObjects(requestHeaders[@"If-Match"], @"W/\"1\"");

  NSDictionary *diagnostics = [error.userInfo[ALNDataverseErrorDiagnosticsKey] isKindOfClass:[NSDictionary class]]
                                  ? error.userInfo[ALNDataverseErrorDiagnosticsKey]
                                  : @{};
  XCTAssertEqualObjects(diagnostics[@"attempt"], @1);
  XCTAssertEqualObjects(diagnostics[@"max_attempts"], @1);
  XCTAssertEqualObjects(diagnostics[@"status_code"], @429);
  XCTAssertEqualObjects(diagnostics[@"target_name"], @"sales");
  XCTAssertEqualObjects(diagnostics[@"body_bytes"], @0);
}

- (void)testBatchRequestsUseSharedRetryPolicy {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:503
                                                                       headers:@{
                                                                         @"Content-Type" : @"application/json",
                                                                         @"Retry-After" : @"1",
                                                                       }
                                                                      bodyData:nil]];

  NSString *batchBody =
      @"--batchresponse_123\r\n"
       "Content-Type: application/http\r\n"
       "Content-Transfer-Encoding: binary\r\n"
       "\r\n"
       "HTTP/1.1 200 OK\r\n"
       "Content-Type: application/json; charset=utf-8\r\n"
       "Content-ID: 1\r\n"
       "\r\n"
       "{\"name\":\"Acme\"}\r\n"
       "--batchresponse_123--\r\n";
  NSData *batchData = [batchBody dataUsingEncoding:NSUTF8StringEncoding];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:200
                                                                       headers:@{ @"Content-Type" : @"multipart/mixed; boundary=batchresponse_123" }
                                                                      bodyData:batchData]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:1
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  NSArray<ALNDataverseBatchResponse *> *responses = [client executeBatchRequests:@[
    [ALNDataverseBatchRequest requestWithMethod:@"GET"
                                   relativePath:@"accounts?$top=1"
                                        headers:nil
                                     bodyObject:nil
                                      contentID:@"1"],
  ]
                                                                       error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, responses.count);
  XCTAssertTrue([responses[0].bodyText containsString:@"Acme"]);
  XCTAssertEqual((NSUInteger)2, transport.capturedRequests.count);
  XCTAssertEqual((NSUInteger)1, tokenProvider.requestCount);
}

- (void)testAuthenticationAndTransportErrorsRetainDataverseDiagnostics {
  NSError *error = nil;

  ALNFakeDataverseTransport *authTransport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *authProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  authProvider.queuedError = [NSError errorWithDomain:@"TokenProvider.Error"
                                                 code:91
                                             userInfo:@{
                                               NSLocalizedDescriptionKey : @"token unavailable",
                                             }];
  ALNDataverseClient *authClient = [self clientWithTransport:authTransport
                                               tokenProvider:authProvider
                                                  targetName:@"crm"
                                                  maxRetries:0
                                                    pageSize:250
                                                       error:&error];
  XCTAssertNil(error);

  NSDictionary *authResult = [authClient ping:&error];
  XCTAssertNil(authResult);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(error.domain, ALNDataverseErrorDomain);
  XCTAssertEqual((NSInteger)ALNDataverseErrorAuthenticationFailed, error.code);
  NSError *underlyingAuthError = [error.userInfo[NSUnderlyingErrorKey] isKindOfClass:[NSError class]]
                                      ? error.userInfo[NSUnderlyingErrorKey]
                                      : nil;
  XCTAssertEqualObjects(underlyingAuthError.domain, @"TokenProvider.Error");
  XCTAssertEqualObjects(error.userInfo[ALNDataverseErrorTargetNameKey], @"crm");
  XCTAssertEqualObjects(error.userInfo[ALNDataverseErrorRequestMethodKey], @"GET");

  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueError:[NSError errorWithDomain:@"Transport.Error"
                                              code:77
                                          userInfo:@{
                                            NSLocalizedDescriptionKey : @"socket closed",
                                          }]];
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  NSDictionary *transportResult = [client ping:&error];
  XCTAssertNil(transportResult);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(error.domain, ALNDataverseErrorDomain);
  XCTAssertEqual((NSInteger)ALNDataverseErrorTransportFailed, error.code);
  NSError *underlyingTransportError = [error.userInfo[NSUnderlyingErrorKey] isKindOfClass:[NSError class]]
                                           ? error.userInfo[NSUnderlyingErrorKey]
                                           : nil;
  XCTAssertEqualObjects(underlyingTransportError.domain, @"Transport.Error");
  NSDictionary *diagnostics = [error.userInfo[ALNDataverseErrorDiagnosticsKey] isKindOfClass:[NSDictionary class]]
                                  ? error.userInfo[ALNDataverseErrorDiagnosticsKey]
                                  : @{};
  XCTAssertEqualObjects(diagnostics[@"transport_error"], @"socket closed");
  XCTAssertEqualObjects(error.userInfo[ALNDataverseErrorTargetNameKey], @"crm");
}

- (void)testFetchPageRejectsInvalidPayloads {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{ @"count" : @1 }]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  ALNDataverseQuery *query = [ALNDataverseQuery queryWithEntitySetName:@"accounts" error:&error];
  XCTAssertNil(error);
  ALNDataverseEntityPage *page = [client fetchPageForQuery:query error:&error];
  XCTAssertNil(page);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(error.domain, ALNDataverseErrorDomain);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidResponse, error.code);
}

@end
