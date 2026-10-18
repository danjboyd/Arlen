#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNDataverseTestSupport.h"

@interface DataverseWriteTests : ALNDataverseTestCase
@end

@implementation DataverseWriteTests

- (void)testCreateUpdateAndUpsertSerializeLookupChoicesAndMultiChoiceSemantics {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204
                                                                       headers:@{ @"OData-EntityId" : @"accounts(00000000-0000-0000-0000-000000000010)" }
                                                                      bodyData:nil]];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204
                                                                       headers:@{ @"ETag" : @"W/\"2\"" }
                                                                      bodyData:nil]];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204 headers:@{} bodyData:nil]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  NSDictionary *values = @{
    @"name" : @"Acme",
    @"primarycontactid" : [ALNDataverseLookupBinding bindingWithBindPath:@"contacts(00000000-0000-0000-0000-000000000020)"],
    @"statuscode" : [ALNDataverseChoiceValue valueWithIntegerValue:@1],
    @"categorycodes" : @[
      [ALNDataverseChoiceValue valueWithIntegerValue:@10],
      [ALNDataverseChoiceValue valueWithIntegerValue:@20],
    ],
    @"preferredchannels" : @[],
  };
  NSDictionary *createResult = [client createRecordInEntitySet:@"accounts"
                                                        values:values
                                           returnRepresentation:NO
                                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(createResult[@"odata_entity_id"], @"accounts(00000000-0000-0000-0000-000000000010)");

  NSDictionary *updateResult = [client updateRecordInEntitySet:@"accounts"
                                                      recordID:@"00000000-0000-0000-0000-000000000010"
                                                        values:@{ @"statuscode" : [ALNDataverseChoiceValue valueWithIntegerValue:@2] }
                                                       ifMatch:@"W/\"1\""
                                           returnRepresentation:NO
                                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(updateResult[@"etag"], @"W/\"2\"");

  NSDictionary *upsertResult = [client upsertRecordInEntitySet:@"accounts"
                                             alternateKeyValues:@{ @"accountnumber" : @"A-100" }
                                                         values:@{ @"name" : @"Acme Alt Key" }
                                                      createOnly:YES
                                                      updateOnly:NO
                                             returnRepresentation:NO
                                                          error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(upsertResult);

  NSDictionary *createBody = [self JSONObjectFromRequestBody:transport.capturedRequests[0]];
  NSArray *expectedCategoryCodes = @[ @10, @20 ];
  NSArray *expectedPreferredChannels = @[];
  XCTAssertEqualObjects(createBody[@"name"], @"Acme");
  XCTAssertEqualObjects(createBody[@"primarycontactid@odata.bind"],
                        @"/contacts(00000000-0000-0000-0000-000000000020)");
  XCTAssertEqualObjects(createBody[@"statuscode"], @1);
  XCTAssertEqualObjects(createBody[@"categorycodes"], expectedCategoryCodes);
  XCTAssertEqualObjects(createBody[@"preferredchannels"], expectedPreferredChannels);
  XCTAssertNil(createBody[@"omittedfield"]);

  ALNDataverseRequest *updateRequest = transport.capturedRequests[1];
  XCTAssertEqualObjects(updateRequest.method, @"PATCH");
  XCTAssertEqualObjects(updateRequest.headers[@"If-Match"], @"W/\"1\"");
  XCTAssertTrue([updateRequest.URLString containsString:@"accounts(00000000-0000-0000-0000-000000000010)"]);

  ALNDataverseRequest *upsertRequest = transport.capturedRequests[2];
  XCTAssertEqualObjects(upsertRequest.headers[@"If-None-Match"], @"*");
  XCTAssertTrue([upsertRequest.URLString containsString:@"accounts(accountnumber='A-100')"]);
}

- (void)testCreateAndUpdateReturnRepresentationUsePreferHeaderAndParseBodies {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:201
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"accountid" : @"00000000-0000-0000-0000-000000000011",
                                             @"name" : @"Acme",
                                           }]];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"accountid" : @"00000000-0000-0000-0000-000000000011",
                                             @"name" : @"Acme Renamed",
                                           }]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  NSDictionary *created = [client createRecordInEntitySet:@"accounts"
                                                   values:@{ @"name" : @"Acme" }
                                      returnRepresentation:YES
                                                    error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(created[@"name"], @"Acme");

  NSDictionary *updated = [client updateRecordInEntitySet:@"accounts"
                                                 recordID:@"00000000-0000-0000-0000-000000000011"
                                                   values:@{ @"name" : @"Acme Renamed" }
                                                  ifMatch:nil
                                      returnRepresentation:YES
                                                    error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(updated[@"name"], @"Acme Renamed");

  XCTAssertTrue([transport.capturedRequests[0].headers[@"Prefer"] containsString:@"return=representation"]);
  XCTAssertTrue([transport.capturedRequests[1].headers[@"Prefer"] containsString:@"return=representation"]);
}

- (void)testInvokeActionAndDeleteUseExpectedHTTPContracts {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{ @"completed" : @YES }]];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204 headers:@{} bodyData:nil]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  id actionResult = [client invokeActionNamed:@"new_Recalculate"
                                     boundPath:@"accounts(00000000-0000-0000-0000-000000000010)"
                                    parameters:@{ @"Force" : @YES }
                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(actionResult[@"completed"], @YES);

  BOOL deleted = [client deleteRecordInEntitySet:@"accounts"
                                        recordID:@"00000000-0000-0000-0000-000000000010"
                                         ifMatch:@"W/\"1\""
                                           error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(deleted);

  XCTAssertEqualObjects(transport.capturedRequests[0].method, @"POST");
  XCTAssertTrue([transport.capturedRequests[0].URLString containsString:@"/accounts(00000000-0000-0000-0000-000000000010)/new_Recalculate"]);
  XCTAssertEqualObjects(transport.capturedRequests[1].method, @"DELETE");
  XCTAssertEqualObjects(transport.capturedRequests[1].headers[@"If-Match"], @"W/\"1\"");
}

- (void)testAlternateKeyPathsAreDeterministicAndValidateInputs {
  NSError *error = nil;
  NSString *path = [ALNDataverseClient recordPathForEntitySet:@"accounts"
                                           alternateKeyValues:@{
                                             @"accountnumber" : @"A-100",
                                             @"name" : @"Acme",
                                           }
                                                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(path, @"accounts(accountnumber='A-100',name='Acme')");

  NSString *unsafePath = [ALNDataverseClient recordPathForEntitySet:@"accounts"
                                                 alternateKeyValues:@{ @"bad-key" : @"x" }
                                                              error:&error];
  XCTAssertNil(unsafePath);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(error.domain, ALNDataverseErrorDomain);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);
}

- (void)testRecordPathsAcceptOnlyGUIDRecordIDs {
  NSError *error = nil;
  XCTAssertEqualObjects([ALNDataverseClient recordPathForEntitySet:@"accounts"
                                                          recordID:@"00000000-0000-0000-0000-000000000010"
                                                             error:&error],
                        @"accounts(00000000-0000-0000-0000-000000000010)");
  XCTAssertNil(error);

  NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-0000000000AB"];
  NSString *uuidPath = [ALNDataverseClient recordPathForEntitySet:@"accounts" recordID:(NSString *)uuid error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(uuidPath, @"accounts(00000000-0000-0000-0000-0000000000AB)");

  NSArray<NSString *> *rejected = @[
    @"00000000-0000-0000-0000-000000000001)/../../systemusers?$select=internalemailaddress&x=(",
    @"(accountnumber='A-100')",
    @"accountnumber='A-100'",
    @"00000000-0000-0000-0000-00000000000g",
    @"ord-100",
    @"",
  ];
  for (NSString *recordID in rejected) {
    error = nil;
    NSString *path = [ALNDataverseClient recordPathForEntitySet:@"accounts" recordID:recordID error:&error];
    XCTAssertNil(path, @"%@", recordID);
    XCTAssertEqualObjects(error.domain, ALNDataverseErrorDomain, @"%@", recordID);
    XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code, @"%@", recordID);
  }
}

- (void)testNonGUIDRecordIDsFailBeforeAnyRequest {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);
  NSString *probe = @"00000000-0000-0000-0000-000000000001)/../../systemusers?$select=internalemailaddress&x=(";

  XCTAssertNil([client retrieveRecordInEntitySet:@"accounts"
                                        recordID:probe
                                    selectFields:nil
                                          expand:nil
                          includeFormattedValues:NO
                                           error:&error]);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);
  error = nil;
  XCTAssertNil([client updateRecordInEntitySet:@"accounts"
                                      recordID:probe
                                        values:@{ @"name" : @"x" }
                                       ifMatch:nil
                           returnRepresentation:NO
                                         error:&error]);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);
  error = nil;
  XCTAssertFalse([client deleteRecordInEntitySet:@"accounts" recordID:probe ifMatch:nil error:&error]);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);
  XCTAssertEqual((NSUInteger)0, [transport.capturedRequests count]);
}

- (void)testAlternateKeyValuesArePercentEncodedInsideTheirLiteral {
  NSError *error = nil;
  NSString *path = [ALNDataverseClient
      recordPathForEntitySet:@"contacts"
          alternateKeyValues:@{ @"emailaddress1" : @"x/../../systemusers(00000000-0000-0000-0000-0000000000aa)#" }
                       error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(path, @"contacts(emailaddress1='x%2F..%2F..%2Fsystemusers%2800000000-0000-0000-0000-0000000000aa%29%23')");
  XCTAssertFalse([path containsString:@"/"]);
  XCTAssertFalse([path containsString:@"#"]);

  path = [ALNDataverseClient recordPathForEntitySet:@"contacts"
                                 alternateKeyValues:@{ @"name" : @"O'Brien & Co, a=b? 100% ü" }
                                              error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(path, @"contacts(name='O''Brien%20%26%20Co%2C%20a%3Db%3F%20100%25%20%C3%BC')");

  path = [ALNDataverseClient recordPathForEntitySet:@"contacts"
                                 alternateKeyValues:@{ @"externalid" : @42, @"active" : @YES }
                                              error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(path, @"contacts(active=true,externalid=42)");
}

- (void)testFunctionParametersAreEncodedAndOperationPathsValidated {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204 headers:@{} bodyData:nil]];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204 headers:@{} bodyData:nil]];
  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  [client invokeFunctionNamed:@"new_LookupContact"
                    boundPath:nil
                   parameters:@{ @"Email" : @"x/../../../systemusers?$select=internalemailaddress#" }
                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [transport.capturedRequests count]);
  XCTAssertTrue([transport.capturedRequests[0].URLString
      hasSuffix:@"/new_LookupContact(Email='x%2F..%2F..%2F..%2Fsystemusers%3F%24select%3Dinternalemailaddress%23')"]);

  [client invokeFunctionNamed:@"Microsoft.Dynamics.CRM.RetrievePrincipalAccess"
                    boundPath:@"systemusers(00000000-0000-0000-0000-000000000010)"
                   parameters:@{}
                        error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([transport.capturedRequests[1].URLString
      hasSuffix:@"/systemusers(00000000-0000-0000-0000-000000000010)/Microsoft.Dynamics.CRM.RetrievePrincipalAccess()"]);

  NSArray<NSString *> *badBoundPaths = @[
    @"accounts(00000000-0000-0000-0000-000000000010)/../../systemusers",
    @"accounts(name='x')",
    @"accounts?$select=name",
    @"accounts#",
  ];
  for (NSString *boundPath in badBoundPaths) {
    error = nil;
    XCTAssertNil([client invokeFunctionNamed:@"WhoAmI" boundPath:boundPath parameters:@{} error:&error], @"%@", boundPath);
    XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code, @"%@", boundPath);
    error = nil;
    XCTAssertNil([client invokeActionNamed:@"new_Recalculate" boundPath:boundPath parameters:@{} error:&error],
                 @"%@", boundPath);
    XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code, @"%@", boundPath);
  }
  error = nil;
  XCTAssertNil([client invokeFunctionNamed:@"WhoAmI()/../systemusers" boundPath:nil parameters:@{} error:&error]);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);
  error = nil;
  XCTAssertNil([client invokeActionNamed:@"new_Recalculate?x=1" boundPath:nil parameters:@{} error:&error]);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);
  error = nil;
  XCTAssertNil([client invokeFunctionNamed:@"WhoAmI" boundPath:nil parameters:@{ @"a)/x" : @"1" } error:&error]);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);
  XCTAssertEqual((NSUInteger)2, [transport.capturedRequests count]);
}

- (void)testHeaderValuesWithLineBreaksAreRejectedBeforeAnyRequest {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);
  NSString *injected = @"W/\"1\"\r\nMSCRM.CallerObjectId: 11111111-2222-3333-4444-555555555555";

  XCTAssertNil([client updateRecordInEntitySet:@"accounts"
                                      recordID:@"00000000-0000-0000-0000-000000000010"
                                        values:@{ @"name" : @"x" }
                                       ifMatch:injected
                           returnRepresentation:NO
                                         error:&error]);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);
  error = nil;
  XCTAssertFalse([client deleteRecordInEntitySet:@"accounts"
                                        recordID:@"00000000-0000-0000-0000-000000000010"
                                         ifMatch:@"W/\"1\"\nIf-Match: *"
                                           error:&error]);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);

  NSArray<NSDictionary *> *badHeaders = @[
    @{ @"X-Note" : @"a\r\nMSCRM.BypassCustomPluginExecution: true" },
    @{ @"X-Note" : [NSString stringWithFormat:@"nul%Cbyte", (unichar)0] },
    @{ @"X Bad" : @"value" },
    @{ @"X-Bad:\r\nInjected" : @"value" },
  ];
  for (NSDictionary *headers in badHeaders) {
    error = nil;
    XCTAssertNil([client performRequestWithMethod:@"GET"
                                             path:@"accounts"
                                            query:nil
                                          headers:headers
                                       bodyObject:nil
                           includeFormattedValues:NO
                             returnRepresentation:NO
                                 consistencyCount:NO
                                            error:&error],
                 @"%@", headers);
    XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code, @"%@", headers);
  }

  NSArray<ALNDataverseBatchRequest *> *badParts = @[
    [ALNDataverseBatchRequest requestWithMethod:@"PATCH"
                                   relativePath:@"contacts(00000000-0000-0000-0000-000000000001)"
                                        headers:@{ @"If-Match" : injected }
                                     bodyObject:@{ @"firstname" : @"x" }
                                      contentID:@"1"],
    [ALNDataverseBatchRequest requestWithMethod:@"PATCH"
                                   relativePath:@"contacts(00000000-0000-0000-0000-000000000001)"
                                        headers:nil
                                     bodyObject:@{ @"firstname" : @"x" }
                                      contentID:@"1\r\nMSCRM.CallerObjectId: 1111"],
    [ALNDataverseBatchRequest requestWithMethod:@"PATCH"
                                   relativePath:@"contacts(1) HTTP/1.1\r\nIf-Match: *\r\nX-Pad: ("
                                        headers:nil
                                     bodyObject:@{ @"firstname" : @"x" }
                                      contentID:@"1"],
    [ALNDataverseBatchRequest requestWithMethod:@"PATCH /x HTTP/1.1\r\nIf-Match: *\r\nX"
                                   relativePath:@"contacts(00000000-0000-0000-0000-000000000001)"
                                        headers:nil
                                     bodyObject:nil
                                      contentID:@"1"],
  ];
  for (ALNDataverseBatchRequest *part in badParts) {
    error = nil;
    XCTAssertNil([client executeBatchRequests:@[ part ] error:&error], @"%@", part.contentID);
    XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code, @"%@", part.contentID);
  }
  XCTAssertEqual((NSUInteger)0, [transport.capturedRequests count]);

  // The curl transport checks the request it is handed too, before staging
  // any file or starting curl.
  ALNDataverseCurlTransport *curl = [[ALNDataverseCurlTransport alloc] initWithTimeoutInterval:1];
  ALNDataverseRequest *request = [[ALNDataverseRequest alloc] initWithMethod:@"GET"
                                                                   URLString:@"http://127.0.0.1:9/api/data/v9.2/accounts"
                                                                     headers:@{ @"If-Match" : injected }
                                                                    bodyData:nil];
  error = nil;
  XCTAssertNil([curl executeRequest:request error:&error]);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);
}

- (void)testRequestMethodsMustBeTokensBeforeAnyRequest {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);
  NSString *smuggled = @"GET /api/data/v9.2/WhoAmI HTTP/1.1\r\nHost: crm.example\r\nContent-Length: 0\r\n\r\nDELETE";
  NSArray<NSString *> *methods = @[ smuggled, @"GET\nX", @"GE T", @"PATCH(" ];
  for (NSString *method in methods) {
    error = nil;
    XCTAssertNil([client performRequestWithMethod:method
                                             path:@"accounts(00000000-0000-0000-0000-00000000000b)"
                                            query:nil
                                          headers:nil
                                       bodyObject:nil
                           includeFormattedValues:NO
                             returnRepresentation:NO
                                 consistencyCount:NO
                                            error:&error],
                 @"%@", method);
    XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code, @"%@", method);
  }
  XCTAssertEqual((NSUInteger)0, [transport.capturedRequests count]);
  XCTAssertEqual((NSUInteger)0, tokenProvider.requestCount);

  ALNDataverseCurlTransport *curl = [[ALNDataverseCurlTransport alloc] initWithTimeoutInterval:1];
  ALNDataverseRequest *request = [[ALNDataverseRequest alloc] initWithMethod:smuggled
                                                                   URLString:@"http://127.0.0.1:9/api/data/v9.2/WhoAmI"
                                                                     headers:@{}
                                                                    bodyData:nil];
  error = nil;
  XCTAssertNil([curl executeRequest:request error:&error]);
  XCTAssertEqual((NSInteger)ALNDataverseErrorInvalidArgument, error.code);
}

@end
