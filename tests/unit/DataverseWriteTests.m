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

@end
