#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDataverseCodegen.h"
#import "ALNDataverseMetadata.h"
#import "ALNDataverseQuery.h"
#import "../shared/ALNDataverseTestSupport.h"
#import "../shared/ALNTestSupport.h"

@interface DataverseArtifactTests : ALNDataverseTestCase
@end

@implementation DataverseArtifactTests

- (void)testCharacterizationSnapshotMatchesCurrentContracts {
  NSError *error = nil;
  NSDictionary *snapshot =
      ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase23/dataverse_contract_snapshot.json", &error);
  XCTAssertNil(error);
  XCTAssertNotNil(snapshot);

  NSDictionary *queryContract =
      [snapshot[@"query_page_contract"] isKindOfClass:[NSDictionary class]] ? snapshot[@"query_page_contract"] : @{};
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"@odata.count" : @1,
                                             @"value" : @[
                                               @{
                                                 @"accountid" : @"00000000-0000-0000-0000-000000000001",
                                                 @"name" : @"Acme",
                                                 @"name@OData.Community.Display.V1.FormattedValue" : @"Acme Corporation",
                                               },
                                             ],
                                           }]];

  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  ALNDataverseQuery *query = [[ALNDataverseQuery queryWithEntitySetName:@"accounts" error:&error]
      queryBySettingSelectFields:@[ @"accountid", @"name" ]];
  query = [query queryBySettingIncludeCount:YES];
  ALNDataverseEntityPage *page = [client fetchPageForQuery:query error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, page.records.count);

  ALNDataverseRequest *queryRequest = transport.capturedRequests[0];
  XCTAssertEqualObjects(queryRequest.method, queryContract[@"method"]);
  NSArray *preferContains =
      [queryContract[@"prefer_contains"] isKindOfClass:[NSArray class]] ? queryContract[@"prefer_contains"] : @[];
  for (NSString *fragment in preferContains) {
    XCTAssertTrue([queryRequest.headers[@"Prefer"] containsString:fragment], @"missing %@", fragment);
  }

  NSDictionary *createContract =
      [snapshot[@"create_contract"] isKindOfClass:[NSDictionary class]] ? snapshot[@"create_contract"] : @{};
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204
                                                                       headers:@{ @"OData-EntityId" : @"accounts(00000000-0000-0000-0000-000000000010)" }
                                                                      bodyData:nil]];
  [transport enqueueResponse:[[ALNDataverseResponse alloc] initWithStatusCode:204 headers:@{} bodyData:nil]];

  NSDictionary *createValues = @{
    @"name" : @"Acme",
    @"preferredchannels" : @[],
    @"primarycontactid" : [ALNDataverseLookupBinding bindingWithBindPath:@"contacts(00000000-0000-0000-0000-000000000020)"],
    @"statuscode" : [ALNDataverseChoiceValue valueWithIntegerValue:@1],
  };
  NSDictionary *createResult = [client createRecordInEntitySet:@"accounts"
                                                        values:createValues
                                           returnRepresentation:NO
                                                         error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(createResult);
  NSDictionary *createBody = [self JSONObjectFromRequestBody:transport.capturedRequests[1]];
  NSDictionary *expectedCreateFields =
      [createContract[@"body_fields"] isKindOfClass:[NSDictionary class]] ? createContract[@"body_fields"] : @{};
  for (NSString *key in expectedCreateFields) {
    XCTAssertEqualObjects(createBody[key], expectedCreateFields[key], @"%@", key);
  }

  NSDictionary *upsertContract =
      [snapshot[@"upsert_contract"] isKindOfClass:[NSDictionary class]] ? snapshot[@"upsert_contract"] : @{};
  NSDictionary *upsertResult = [client upsertRecordInEntitySet:@"accounts"
                                             alternateKeyValues:@{ @"accountnumber" : @"A-100" }
                                                         values:@{ @"name" : @"Acme Alt Key" }
                                                      createOnly:YES
                                                      updateOnly:NO
                                             returnRepresentation:NO
                                                          error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(upsertResult);
  ALNDataverseRequest *upsertRequest = [transport.capturedRequests lastObject];
  XCTAssertEqualObjects(upsertRequest.method, upsertContract[@"method"]);
  XCTAssertEqualObjects(upsertRequest.headers[@"If-None-Match"], upsertContract[@"headers"][@"If-None-Match"]);
  XCTAssertTrue([upsertRequest.URLString containsString:upsertContract[@"url_contains"][0]]);

  NSDictionary *throttleContract =
      [snapshot[@"throttle_error_contract"] isKindOfClass:[NSDictionary class]] ? snapshot[@"throttle_error_contract"] : @{};
  ALNFakeDataverseTransport *errorTransport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *errorTokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [errorTransport enqueueResponse:[self responseWithStatus:429
                                                   headers:@{
                                                     @"Content-Type" : @"application/json",
                                                     @"Retry-After" : @"17",
                                                     @"x-ms-request-id" : @"corr-123",
                                                   }
                                                JSONObject:@{ @"error" : @{ @"message" : @"Slow down" } }]];
  ALNDataverseClient *errorClient = [self clientWithTransport:errorTransport
                                                tokenProvider:errorTokenProvider
                                                   targetName:@"sales"
                                                   maxRetries:0
                                                     pageSize:250
                                                        error:&error];
  XCTAssertNil(error);
  XCTAssertNil([errorClient ping:&error]);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(error.domain, throttleContract[@"domain"]);
  XCTAssertEqual((NSInteger)[throttleContract[@"code"] integerValue], error.code);
  NSArray *userInfoKeys =
      [throttleContract[@"user_info_keys"] isKindOfClass:[NSArray class]] ? throttleContract[@"user_info_keys"] : @[];
  for (NSString *key in userInfoKeys) {
    XCTAssertNotNil(error.userInfo[key], @"%@", key);
  }

  NSDictionary *metadataContract =
      [snapshot[@"metadata_contract"] isKindOfClass:[NSDictionary class]] ? snapshot[@"metadata_contract"] : @{};
  NSDictionary *fixture = ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase23/dataverse_entitydefinitions.json",
                                                              &error);
  XCTAssertNil(error);
  NSDictionary<NSString *, id> *normalized = [ALNDataverseMetadata normalizedMetadataFromPayload:fixture error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(normalized[@"entity_count"], metadataContract[@"normalized_entity_count"]);
  XCTAssertEqualObjects(normalized[@"attribute_count"], metadataContract[@"normalized_attribute_count"]);
  NSDictionary<NSString *, id> *artifacts = [ALNDataverseCodegen renderArtifactsFromMetadata:normalized
                                                                                  classPrefix:@"ALNDV"
                                                                              dataverseTarget:@"crm"
                                                                                        error:&error];
  XCTAssertNil(error);
  NSDictionary *manifestObject = ALNTestJSONDictionaryFromString(artifacts[@"manifest"], &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(manifestObject[@"dataverse_target"], metadataContract[@"manifest_target"]);
  NSArray *headerContains =
      [metadataContract[@"header_contains"] isKindOfClass:[NSArray class]] ? metadataContract[@"header_contains"] : @[];
  for (NSString *fragment in headerContains) {
    XCTAssertTrue([artifacts[@"header"] containsString:fragment], @"%@", fragment);
  }
}

- (void)testPerlParityMatrixIsGapFreeAndReferencesFocusedCoverage {
  NSError *error = nil;
  NSDictionary *parity =
      ALNTestJSONDictionaryAtRelativePath(@"tests/fixtures/phase23/dataverse_perl_parity_matrix.json", &error);
  XCTAssertNil(error);
  XCTAssertNotNil(parity);
  XCTAssertEqualObjects(parity[@"version"], @"phase23-perl-parity-v1");

  NSArray *families = [parity[@"families"] isKindOfClass:[NSArray class]] ? parity[@"families"] : @[];
  XCTAssertTrue([families count] >= 8);
  for (NSDictionary *family in families) {
    XCTAssertEqualObjects(family[@"status"], @"covered");
    XCTAssertTrue([family[@"perl_tests"] count] > 0);
    XCTAssertTrue([family[@"arlen_tests"] count] > 0);
  }

  NSArray *remainingGaps =
      [parity[@"remaining_gaps"] isKindOfClass:[NSArray class]] ? parity[@"remaining_gaps"] : @[];
  XCTAssertEqual((NSUInteger)0, remainingGaps.count);

  NSArray *intentionalOmissions =
      [parity[@"intentional_omissions"] isKindOfClass:[NSArray class]] ? parity[@"intentional_omissions"] : @[];
  XCTAssertTrue(intentionalOmissions.count >= 3);
}

@end
