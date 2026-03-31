#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNDataverseClient.h"
#import "ALNDataverseCodegen.h"
#import "ALNDataverseMetadata.h"
#import "ALNDataverseQuery.h"
#import "ALNJSONSerialization.h"
#import "../shared/ALNTestSupport.h"
#import "../shared/ALNWebTestSupport.h"

@interface ALNFakeDataverseTransport : NSObject <ALNDataverseTransport>

@property(nonatomic, strong) NSMutableArray *queuedResults;
@property(nonatomic, strong) NSMutableArray<ALNDataverseRequest *> *capturedRequests;

- (void)enqueueResponse:(ALNDataverseResponse *)response;
- (void)enqueueError:(NSError *)error;

@end

@implementation ALNFakeDataverseTransport

- (instancetype)init {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _queuedResults = [NSMutableArray array];
  _capturedRequests = [NSMutableArray array];
  return self;
}

- (void)enqueueResponse:(ALNDataverseResponse *)response {
  [self.queuedResults addObject:response ?: [NSNull null]];
}

- (void)enqueueError:(NSError *)error {
  [self.queuedResults addObject:error ?: [NSNull null]];
}

- (ALNDataverseResponse *)executeRequest:(ALNDataverseRequest *)request error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  [self.capturedRequests addObject:request];
  id next = ([self.queuedResults count] > 0) ? self.queuedResults[0] : nil;
  if ([self.queuedResults count] > 0) {
    [self.queuedResults removeObjectAtIndex:0];
  }
  if ([next isKindOfClass:[NSError class]]) {
    if (error != NULL) {
      *error = next;
    }
    return nil;
  }
  return [next isKindOfClass:[ALNDataverseResponse class]] ? next : nil;
}

@end

@interface ALNFakeDataverseTokenProvider : NSObject <ALNDataverseTokenProvider>

@property(nonatomic, copy) NSString *token;
@property(nonatomic, assign) NSUInteger requestCount;

@end

@implementation ALNFakeDataverseTokenProvider

- (instancetype)init {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _token = @"test-token";
  return self;
}

- (NSString *)accessTokenForTarget:(ALNDataverseTarget *)target
                         transport:(id<ALNDataverseTransport>)transport
                             error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  self.requestCount += 1;
  return self.token;
}

@end

@interface ALNDataverseRuntimeHarnessController : ALNController
@end

@implementation ALNDataverseRuntimeHarnessController

- (id)status:(ALNContext *)ctx {
  NSError *defaultError = nil;
  NSError *salesError = nil;
  ALNDataverseClient *defaultClient = [ctx dataverseClientNamed:nil error:&defaultError];
  ALNDataverseClient *salesClient = [self dataverseClientNamed:@"sales" error:&salesError];

  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"targets"] = [self dataverseTargetNames] ?: @[];
  if (defaultClient != nil) {
    payload[@"default_target"] = defaultClient.target.targetName ?: @"";
  }
  if (salesClient != nil) {
    payload[@"sales_target"] = salesClient.target.targetName ?: @"";
  }
  if (defaultError != nil) {
    payload[@"default_error"] = defaultError.localizedDescription ?: @"";
  }
  if (salesError != nil) {
    payload[@"sales_error"] = salesError.localizedDescription ?: @"";
  }
  [self renderJSON:payload error:NULL];
  return self.context.response;
}

@end

@interface DataverseTests : XCTestCase
@end

@implementation DataverseTests

- (ALNDataverseTarget *)targetWithError:(NSError **)error {
  return [self targetNamed:@"crm" maxRetries:0 pageSize:250 error:error];
}

- (ALNDataverseTarget *)targetNamed:(NSString *)targetName
                         maxRetries:(NSUInteger)maxRetries
                           pageSize:(NSUInteger)pageSize
                              error:(NSError **)error {
  return [[ALNDataverseTarget alloc] initWithServiceRootURLString:@"https://example.crm.dynamics.com/api/data/v9.2"
                                                         tenantID:@"tenant-id"
                                                         clientID:@"client-id"
                                                     clientSecret:@"client-secret"
                                                        targetName:targetName
                                                   timeoutInterval:5.0
                                                        maxRetries:maxRetries
                                                          pageSize:pageSize
                                                             error:error];
}

- (NSDictionary *)applicationConfig {
  return @{
    @"dataverse" : @{
      @"serviceRootURL" : @"https://example.crm.dynamics.com/api/data/v9.2",
      @"tenantID" : @"tenant-id",
      @"clientID" : @"client-id",
      @"clientSecret" : @"client-secret",
      @"pageSize" : @250,
      @"maxRetries" : @2,
      @"timeout" : @5,
      @"targets" : @{
        @"sales" : @{
          @"serviceRootURL" : @"https://sales.crm.dynamics.com/api/data/v9.2",
          @"pageSize" : @100,
        },
      },
    },
  };
}

- (nullable NSString *)environmentValueForName:(NSString *)name {
  const char *value = getenv([name UTF8String]);
  if (value == NULL) {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (void)setEnvironmentValue:(nullable NSString *)value forName:(NSString *)name {
  if ([value length] > 0) {
    setenv([name UTF8String], [value UTF8String], 1);
  } else {
    unsetenv([name UTF8String]);
  }
}

- (NSDictionary<NSString *, NSString *> *)snapshotEnvironmentForNames:(NSArray<NSString *> *)names {
  NSMutableDictionary<NSString *, NSString *> *snapshot = [NSMutableDictionary dictionary];
  for (NSString *name in names) {
    NSString *value = [self environmentValueForName:name];
    if (value != nil) {
      snapshot[name] = value;
    }
  }
  return [snapshot copy];
}

- (void)restoreEnvironmentSnapshot:(NSDictionary<NSString *, NSString *> *)snapshot
                             names:(NSArray<NSString *> *)names {
  for (NSString *name in names) {
    [self setEnvironmentValue:snapshot[name] forName:name];
  }
}

- (ALNDataverseResponse *)responseWithStatus:(NSInteger)status
                                     headers:(NSDictionary<NSString *, NSString *> *)headers
                                  JSONObject:(id)object {
  NSData *data = nil;
  if (object != nil) {
    data = [ALNJSONSerialization dataWithJSONObject:object options:0 error:NULL];
  }
  return [[ALNDataverseResponse alloc] initWithStatusCode:status headers:headers bodyData:data];
}

- (NSDictionary *)JSONObjectFromRequestBody:(ALNDataverseRequest *)request {
  if ([request.bodyData length] == 0) {
    return nil;
  }
  id object = [ALNJSONSerialization JSONObjectWithData:request.bodyData options:0 error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

- (void)testApplicationResolvesDataverseClientsFromConfigAndEnvironment {
  NSArray<NSString *> *environmentNames = @[
    @"ARLEN_DATAVERSE_URL_SUPPORT",
    @"ARLEN_DATAVERSE_TENANT_ID_SUPPORT",
    @"ARLEN_DATAVERSE_CLIENT_ID_SUPPORT",
    @"ARLEN_DATAVERSE_CLIENT_SECRET_SUPPORT",
    @"ARLEN_DATAVERSE_PAGE_SIZE_SUPPORT",
    @"ARLEN_DATAVERSE_TIMEOUT_SUPPORT",
  ];
  NSDictionary<NSString *, NSString *> *snapshot = [self snapshotEnvironmentForNames:environmentNames];

  @try {
    [self setEnvironmentValue:@"https://support.crm.dynamics.com/api/data/v9.2"
                      forName:@"ARLEN_DATAVERSE_URL_SUPPORT"];
    [self setEnvironmentValue:@"support-tenant" forName:@"ARLEN_DATAVERSE_TENANT_ID_SUPPORT"];
    [self setEnvironmentValue:@"support-client" forName:@"ARLEN_DATAVERSE_CLIENT_ID_SUPPORT"];
    [self setEnvironmentValue:@"support-secret" forName:@"ARLEN_DATAVERSE_CLIENT_SECRET_SUPPORT"];
    [self setEnvironmentValue:@"125" forName:@"ARLEN_DATAVERSE_PAGE_SIZE_SUPPORT"];
    [self setEnvironmentValue:@"30" forName:@"ARLEN_DATAVERSE_TIMEOUT_SUPPORT"];

    ALNApplication *application = [[ALNApplication alloc] initWithConfig:[self applicationConfig]];
    NSArray<NSString *> *targets = [application dataverseTargetNames];
    XCTAssertTrue([targets containsObject:@"default"]);
    XCTAssertTrue([targets containsObject:@"sales"]);
    XCTAssertTrue([targets containsObject:@"support"]);

    NSError *error = nil;
    ALNDataverseClient *defaultClient = [application dataverseClient];
    XCTAssertNotNil(defaultClient);
    ALNDataverseClient *cachedDefault = [application dataverseClientNamed:@"default" error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(defaultClient, cachedDefault);
    XCTAssertEqualObjects(defaultClient.target.targetName, @"default");
    XCTAssertEqualObjects(defaultClient.target.serviceRootURLString,
                          @"https://example.crm.dynamics.com/api/data/v9.2");

    ALNDataverseClient *salesClient = [application dataverseClientNamed:@"sales" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(salesClient.target.targetName, @"sales");
    XCTAssertEqualObjects(salesClient.target.serviceRootURLString,
                          @"https://sales.crm.dynamics.com/api/data/v9.2");
    XCTAssertEqual((NSUInteger)100, salesClient.target.pageSize);

    ALNDataverseClient *supportClient = [application dataverseClientNamed:@"support" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(supportClient.target.targetName, @"support");
    XCTAssertEqualObjects(supportClient.target.serviceRootURLString,
                          @"https://support.crm.dynamics.com/api/data/v9.2");
    XCTAssertEqual((NSUInteger)125, supportClient.target.pageSize);
    XCTAssertEqualWithAccuracy(30.0, supportClient.target.timeoutInterval, 0.001);
  } @finally {
    [self restoreEnvironmentSnapshot:snapshot names:environmentNames];
  }
}

- (void)testApplicationRejectsMissingNamedDataverseTarget {
  ALNApplication *application = [[ALNApplication alloc] initWithConfig:[self applicationConfig]];
  NSError *error = nil;
  ALNDataverseClient *client = [application dataverseClientNamed:@"support" error:&error];
  XCTAssertNil(client);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(error.domain, @"Arlen.Application.Error");
  XCTAssertEqual((NSInteger)305, error.code);
}

- (void)testControllerAndContextHelpersResolveDataverseClientsDuringDispatch {
  ALNWebTestHarness *harness =
      [ALNWebTestHarness harnessWithConfig:[self applicationConfig]
                               routeMethod:@"GET"
                                      path:@"/dataverse"
                                 routeName:@"dataverse.status"
                           controllerClass:[ALNDataverseRuntimeHarnessController class]
                                    action:@"status"
                               middlewares:nil];

  ALNResponse *response = [harness dispatchMethod:@"GET" path:@"/dataverse"];
  ALNAssertResponseStatus(response, 200);

  NSError *error = nil;
  NSDictionary *payload = ALNTestJSONDictionaryFromResponse(response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(payload[@"default_target"], @"default");
  XCTAssertEqualObjects(payload[@"sales_target"], @"sales");
  NSArray *targets = [payload[@"targets"] isKindOfClass:[NSArray class]] ? payload[@"targets"] : @[];
  XCTAssertTrue([targets containsObject:@"default"]);
  XCTAssertTrue([targets containsObject:@"sales"]);
}

- (void)testQueryBuilderBuildsDeterministicParameters {
  NSError *error = nil;
  ALNDataverseQuery *query = [ALNDataverseQuery queryWithEntitySetName:@"accounts" error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(query);

  query = [query queryBySettingSelectFields:@[ @"accountid", @"name" ]];
  query = [query queryBySettingPredicate:@{
    @"accountnumber" : @{ @"-in" : @[ @"A1", @"B2" ] },
    @"name" : @{ @"-like" : @"%corp%" },
    @"parentaccountid" : [NSNull null],
    @"statecode" : @{ @"!=" : @1 },
  }];
  query = [query queryBySettingOrderBy:@[ @"name", @{ @"-desc" : @"createdon" } ]];
  query = [query queryBySettingTop:@50];
  query = [query queryBySettingSkip:@10];
  query = [query queryBySettingIncludeCount:YES];
  query = [query queryBySettingExpand:@{
    @"primarycontactid" : @{
      @"select" : @[ @"fullname" ],
      @"top" : @1,
    },
  }];

  NSDictionary<NSString *, NSString *> *parameters = [query queryParameters:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(parameters[@"$select"], @"accountid,name");
  XCTAssertEqualObjects(parameters[@"$filter"],
                        @"(accountnumber eq 'A1' or accountnumber eq 'B2') and contains(tolower(name),'corp') and parentaccountid eq null and statecode ne 1");
  XCTAssertEqualObjects(parameters[@"$orderby"], @"name asc,createdon desc");
  XCTAssertEqualObjects(parameters[@"$top"], @"50");
  XCTAssertEqualObjects(parameters[@"$skip"], @"10");
  XCTAssertEqualObjects(parameters[@"$count"], @"true");
  XCTAssertEqualObjects(parameters[@"$expand"], @"primarycontactid($select=fullname;$top=1)");
}

- (void)testFetchPageNormalizesFormattedValuesAndNextLink {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  NSDictionary *payload = @{
    @"@odata.count" : @1,
    @"@odata.nextLink" : @"https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=abc",
    @"value" : @[
      @{
        @"accountid" : @"00000000-0000-0000-0000-000000000001",
        @"name" : @"Acme",
        @"name@OData.Community.Display.V1.FormattedValue" : @"Acme Corporation",
        @"@odata.etag" : @"W/\"1\"",
      },
    ],
  };
  [transport enqueueResponse:[self responseWithStatus:200 headers:@{ @"Content-Type" : @"application/json" } JSONObject:payload]];

  NSError *error = nil;
  ALNDataverseTarget *target = [self targetWithError:&error];
  XCTAssertNil(error);
  ALNDataverseClient *client = [[ALNDataverseClient alloc] initWithTarget:target
                                                                transport:transport
                                                            tokenProvider:tokenProvider
                                                                    error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(client);

  ALNDataverseQuery *query = [[ALNDataverseQuery queryWithEntitySetName:@"accounts" error:&error]
      queryBySettingSelectFields:@[ @"accountid", @"name" ]];
  query = [query queryBySettingIncludeCount:YES];
  ALNDataverseEntityPage *page = [client fetchPageForQuery:query error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(page);
  XCTAssertEqual((NSUInteger)1, [page.records count]);
  XCTAssertEqualObjects(page.totalCount, @1);
  XCTAssertEqualObjects(page.nextLinkURLString,
                        @"https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=abc");
  ALNDataverseRecord *record = page.records[0];
  XCTAssertEqualObjects(record.values[@"name"], @"Acme");
  XCTAssertEqualObjects(record.formattedValues[@"name"], @"Acme Corporation");
  XCTAssertEqualObjects(record.etag, @"W/\"1\"");
  XCTAssertEqual((NSUInteger)1, tokenProvider.requestCount);

  ALNDataverseRequest *request = transport.capturedRequests[0];
  XCTAssertEqualObjects(request.method, @"GET");
  XCTAssertTrue([request.URLString containsString:@"accounts?"]);
  XCTAssertTrue([request.URLString containsString:@"%24count=true"] ||
                [request.URLString containsString:@"$count=true"]);
  XCTAssertTrue([request.URLString containsString:@"%24select=accountid%2Cname"] ||
                [request.URLString containsString:@"$select=accountid,name"]);
  XCTAssertEqualObjects(request.headers[@"Authorization"], @"Bearer test-token");
  XCTAssertTrue([request.headers[@"Prefer"] containsString:@"odata.maxpagesize=250"]);
  XCTAssertTrue([request.headers[@"Prefer"] containsString:@"odata.include-annotations"]);
}

- (void)testCreateUpdateAndUpsertSerializeLookupBindingsAndChoices {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204
                                                                       headers:@{ @"OData-EntityId" : @"accounts(00000000-0000-0000-0000-000000000010)" }
                                                                      bodyData:nil]];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204 headers:@{ @"ETag" : @"W/\"2\"" } bodyData:nil]];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204 headers:@{} bodyData:nil]];

  NSError *error = nil;
  ALNDataverseTarget *target = [self targetWithError:&error];
  ALNDataverseClient *client = [[ALNDataverseClient alloc] initWithTarget:target
                                                                transport:transport
                                                            tokenProvider:tokenProvider
                                                                    error:&error];
  XCTAssertNil(error);

  NSDictionary *values = @{
    @"name" : @"Acme",
    @"primarycontactid" : [ALNDataverseLookupBinding bindingWithBindPath:@"contacts(00000000-0000-0000-0000-000000000020)"],
    @"statuscode" : [ALNDataverseChoiceValue valueWithIntegerValue:@1],
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

  XCTAssertEqual((NSUInteger)3, [transport.capturedRequests count]);
  NSDictionary *createBody = [self JSONObjectFromRequestBody:transport.capturedRequests[0]];
  XCTAssertEqualObjects(createBody[@"name"], @"Acme");
  XCTAssertEqualObjects(createBody[@"primarycontactid@odata.bind"],
                        @"/contacts(00000000-0000-0000-0000-000000000020)");
  XCTAssertEqualObjects(createBody[@"statuscode"], @1);

  ALNDataverseRequest *updateRequest = transport.capturedRequests[1];
  XCTAssertEqualObjects(updateRequest.method, @"PATCH");
  XCTAssertEqualObjects(updateRequest.headers[@"If-Match"], @"W/\"1\"");
  XCTAssertTrue([updateRequest.URLString containsString:@"accounts(00000000-0000-0000-0000-000000000010)"]);

  ALNDataverseRequest *upsertRequest = transport.capturedRequests[2];
  XCTAssertEqualObjects(upsertRequest.headers[@"If-None-Match"], @"*");
  XCTAssertTrue([upsertRequest.URLString containsString:@"accounts(accountnumber='A-100')"]);
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
  [transport enqueueResponse:[self responseWithStatus:200 headers:@{ @"Content-Type" : @"application/json" } JSONObject:@{ @"value" : @42 }]];

  NSError *error = nil;
  ALNDataverseTarget *target = [self targetWithError:&error];
  ALNDataverseClient *client = [[ALNDataverseClient alloc] initWithTarget:target
                                                                transport:transport
                                                            tokenProvider:tokenProvider
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
  ALNDataverseTarget *target = [self targetNamed:@"sales" maxRetries:0 pageSize:250 error:&error];
  XCTAssertNil(error);
  ALNDataverseClient *client = [[ALNDataverseClient alloc] initWithTarget:target
                                                                transport:transport
                                                            tokenProvider:tokenProvider
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
  XCTAssertEqual((NSUInteger)1, transport.capturedRequests.count);
  XCTAssertEqualObjects(transport.capturedRequests[0].headers[@"Authorization"], @"Bearer test-token");
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
  ALNDataverseTarget *target = [self targetNamed:@"crm" maxRetries:1 pageSize:250 error:&error];
  XCTAssertNil(error);
  ALNDataverseClient *client = [[ALNDataverseClient alloc] initWithTarget:target
                                                                transport:transport
                                                            tokenProvider:tokenProvider
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
  XCTAssertTrue([transport.capturedRequests[0].URLString hasSuffix:@"/$batch"]);
  XCTAssertEqualObjects(transport.capturedRequests[0].headers[@"Authorization"], @"Bearer test-token");
  XCTAssertEqualObjects(transport.capturedRequests[1].headers[@"Authorization"], @"Bearer test-token");
}

- (void)testMetadataNormalizationAndCodegenAreDeterministic {
  NSError *error = nil;
  NSDictionary *fixture = ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase23/dataverse_entitydefinitions.json",
                                                              &error);
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);

  NSDictionary<NSString *, id> *normalized = [ALNDataverseMetadata normalizedMetadataFromPayload:fixture error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(normalized[@"entity_count"], @2);
  XCTAssertEqualObjects(normalized[@"attribute_count"], @7);

  NSDictionary *firstEntity = normalized[@"entities"][0];
  XCTAssertEqualObjects(firstEntity[@"logical_name"], @"account");
  XCTAssertEqualObjects(firstEntity[@"entity_set_name"], @"accounts");
  XCTAssertEqualObjects(firstEntity[@"attributes"][0][@"logical_name"], @"accountid");
  XCTAssertEqualObjects(firstEntity[@"keys"][0][@"key_attributes"][0], @"accountnumber");
  XCTAssertEqualObjects(firstEntity[@"lookups"][0][@"navigation_property_name"], @"primarycontactid");
  XCTAssertEqualObjects(firstEntity[@"attributes"][4][@"choices"][0][@"label"], @"Active");

  NSMutableDictionary *reversedFixture = [fixture mutableCopy];
  reversedFixture[@"value"] = [[fixture[@"value"] reverseObjectEnumerator] allObjects];
  NSDictionary<NSString *, id> *normalizedReversed =
      [ALNDataverseMetadata normalizedMetadataFromPayload:reversedFixture error:&error];
  XCTAssertNil(error);

  NSDictionary<NSString *, id> *artifacts = [ALNDataverseCodegen renderArtifactsFromMetadata:normalized
                                                                                  classPrefix:@"ALNDV"
                                                                              dataverseTarget:@"crm"
                                                                                        error:&error];
  XCTAssertNil(error);
  NSDictionary<NSString *, id> *artifactsReversed =
      [ALNDataverseCodegen renderArtifactsFromMetadata:normalizedReversed
                                           classPrefix:@"ALNDV"
                                       dataverseTarget:@"crm"
                                                 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(artifacts[@"header"], artifactsReversed[@"header"]);
  XCTAssertEqualObjects(artifacts[@"implementation"], artifactsReversed[@"implementation"]);
  XCTAssertEqualObjects(artifacts[@"manifest"], artifactsReversed[@"manifest"]);

  NSString *header = artifacts[@"header"];
  NSString *manifest = artifacts[@"manifest"];
  NSDictionary *manifestObject = ALNTestJSONDictionaryFromString(manifest, &error);
  XCTAssertNil(error);
  XCTAssertNotNil(manifestObject);
  XCTAssertTrue([header containsString:@"@interface ALNDVAccount : NSObject"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)fieldAccountid;"]);
  XCTAssertTrue([header containsString:@"typedef NS_ENUM(NSInteger, ALNDVAccountStatuscodeChoice)"]);
  XCTAssertTrue([header containsString:@"+ (NSString *)navigationPrimarycontactid;"]);
  XCTAssertEqualObjects(manifestObject[@"dataverse_target"], @"crm");
  XCTAssertEqualObjects(manifestObject[@"entities"][0][@"class_name"], @"ALNDVAccount");
}

- (void)testDataverseCodegenCLIFromFixture {
  NSString *tempDir = ALNTestTemporaryDirectory(@"dataverse_codegen");
  XCTAssertNotNil(tempDir);
  NSString *fixturePath =
      ALNTestPathFromRepoRoot(@"tests/fixtures/phase23/dataverse_entitydefinitions.json");
  NSString *outputDir = [tempDir stringByAppendingPathComponent:@"Generated"];
  NSString *manifestPath = [tempDir stringByAppendingPathComponent:@"dataverse.json"];
  NSString *command = [NSString stringWithFormat:@"%@ && %@ dataverse-codegen --input %@ --output-dir %@ --manifest %@ --prefix ALNDV --force",
                                                 ALNTestGNUstepSourceCommandForRepoRoot(ALNTestRepoRoot()),
                                                 ALNTestShellQuote([ALNTestPathFromRepoRoot(@"build/arlen") stringByStandardizingPath]),
                                                 ALNTestShellQuote(fixturePath),
                                                 ALNTestShellQuote(outputDir),
                                                 ALNTestShellQuote(manifestPath)];
  int exitCode = 0;
  NSString *output = ALNTestRunShellCapture(command, &exitCode);
  XCTAssertEqual(0, exitCode, @"%@", output);
  XCTAssertTrue([output containsString:@"Generated Dataverse artifacts."]);

  NSString *headerPath = [outputDir stringByAppendingPathComponent:@"ALNDVDataverseSchema.h"];
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:headerPath]);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:manifestPath]);
  NSString *header = [NSString stringWithContentsOfFile:headerPath
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
  XCTAssertTrue([header containsString:@"@interface ALNDVAccount : NSObject"]);
}

@end
