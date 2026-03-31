#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDataverseQuery.h"
#import "../shared/ALNDataverseTestSupport.h"

@interface DataverseReadTests : ALNDataverseTestCase
@end

@implementation DataverseReadTests

- (void)testPingReturnsWhoAmIResponseObject {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"BusinessUnitId" : @"00000000-0000-0000-0000-000000000001",
                                             @"UserId" : @"00000000-0000-0000-0000-000000000002",
                                           }]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  NSDictionary<NSString *, id> *result = [client ping:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(result[@"UserId"], @"00000000-0000-0000-0000-000000000002");
  XCTAssertEqual((NSUInteger)1, tokenProvider.requestCount);
  XCTAssertEqualObjects(transport.capturedRequests[0].method, @"GET");
  XCTAssertTrue([transport.capturedRequests[0].URLString hasSuffix:@"/WhoAmI()"]);
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
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:payload]];

  NSError *error = nil;
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
  XCTAssertNotNil(page);
  XCTAssertEqual((NSUInteger)1, [page.records count]);
  XCTAssertEqualObjects(page.totalCount, @1);
  XCTAssertEqualObjects(page.nextLinkURLString,
                        @"https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=abc");
  ALNDataverseRecord *record = page.records[0];
  XCTAssertEqualObjects(record.values[@"name"], @"Acme");
  XCTAssertEqualObjects(record.formattedValues[@"name"], @"Acme Corporation");
  XCTAssertEqualObjects(record.etag, @"W/\"1\"");

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

- (void)testFetchNextPageUsesAbsoluteURLString {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  NSString *nextLink = @"https://example.crm.dynamics.com/api/data/v9.2/accounts?$skiptoken=def";
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"value" : @[
                                               @{
                                                 @"accountid" : @"00000000-0000-0000-0000-000000000002",
                                                 @"name" : @"Beta",
                                               },
                                             ],
                                           }]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  ALNDataverseEntityPage *page = [client fetchNextPageWithURLString:nextLink error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, page.records.count);
  XCTAssertEqualObjects(page.records[0].values[@"name"], @"Beta");
  XCTAssertEqualObjects(transport.capturedRequests[0].URLString, nextLink);
  XCTAssertTrue([transport.capturedRequests[0].headers[@"Prefer"] containsString:@"odata.maxpagesize=250"]);
}

- (void)testRetrieveRecordBuildsDeterministicSelectAndExpandQuery {
  ALNFakeDataverseTransport *transport = [[ALNFakeDataverseTransport alloc] init];
  ALNFakeDataverseTokenProvider *tokenProvider = [[ALNFakeDataverseTokenProvider alloc] init];
  [transport enqueueResponse:[self responseWithStatus:200
                                              headers:@{ @"Content-Type" : @"application/json" }
                                           JSONObject:@{
                                             @"accountid" : @"00000000-0000-0000-0000-000000000010",
                                             @"name" : @"Acme",
                                             @"primarycontactid" : @{
                                               @"fullname" : @"Grace Hopper",
                                             },
                                           }]];

  NSError *error = nil;
  ALNDataverseClient *client = [self clientWithTransport:transport
                                           tokenProvider:tokenProvider
                                              targetName:@"crm"
                                              maxRetries:0
                                                pageSize:250
                                                   error:&error];
  XCTAssertNil(error);

  ALNDataverseRecord *record = [client retrieveRecordInEntitySet:@"accounts"
                                                        recordID:@"00000000-0000-0000-0000-000000000010"
                                                    selectFields:@[ @"accountid", @"name" ]
                                                          expand:@{
                                                            @"primarycontactid" : @{
                                                              @"select" : @[ @"fullname" ],
                                                            },
                                                          }
                                          includeFormattedValues:YES
                                                           error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(record.values[@"name"], @"Acme");

  ALNDataverseRequest *request = transport.capturedRequests[0];
  XCTAssertTrue([request.URLString containsString:@"accounts(00000000-0000-0000-0000-000000000010)?"]);
  XCTAssertTrue([request.URLString containsString:@"primarycontactid"]);
  XCTAssertTrue([request.URLString containsString:@"fullname"]);
  XCTAssertTrue([request.headers[@"Prefer"] containsString:@"odata.include-annotations"]);
}

@end
