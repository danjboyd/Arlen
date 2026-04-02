#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNWebTestSupport.h"
#import "../shared/Phase27SearchTestSupport.h"
#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNSearchModule.h"

@interface Phase27SearchAdminTests : XCTestCase
@end

@implementation Phase27SearchAdminTests

- (void)setUp {
  [super setUp];
  Phase27SearchResetStores();
}

- (ALNApplication *)applicationWithSearchConfig:(NSDictionary *)extraSearchConfig {
  NSMutableDictionary *searchModule = [NSMutableDictionary dictionaryWithDictionary:@{
    @"providers" : @{ @"classes" : @[ @"Phase27SearchProvider" ] },
    @"persistence" : @{ @"enabled" : @NO },
  }];
  if ([extraSearchConfig isKindOfClass:[NSDictionary class]]) {
    [searchModule addEntriesFromDictionary:extraSearchConfig];
  }
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[] },
      @"worker" : @{ @"retryDelaySeconds" : @0 },
    },
    @"searchModule" : searchModule,
  }];
}

- (void)registerModulesForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNSearchModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (void)seedIndexes {
  NSError *error = nil;
  XCTAssertNotNil([[ALNSearchModuleRuntime sharedRuntime] queueReindexForResourceIdentifier:nil error:&error]);
  XCTAssertNil(error);
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:20 error:&error]);
  XCTAssertNil(error);
}

- (void)testDashboardSummaryAndAdminDrilldownExposeExplainabilityAndRecoveryState {
  ALNApplication *app = [self applicationWithSearchConfig:@{
    @"engineClass" : @"ALNMeilisearchSearchEngine",
    @"engine" : @{
      @"meilisearch" : @{
        @"fixturesPath" : Phase27SearchFixturesPath(@"meilisearch_fixtures.json"),
        @"indexPrefix" : @"phase27meili",
      },
    },
  }];
  [app addMiddleware:[[Phase27SearchContextMiddleware alloc] init]];
  [self registerModulesForApplication:app];
  [self seedIndexes];

  NSError *error = nil;
  NSDictionary *query = [[ALNSearchModuleRuntime sharedRuntime] searchQuery:@"priority"
                                                         resourceIdentifier:@"products"
                                                                    filters:nil
                                                                       sort:nil
                                                                      limit:10
                                                                     offset:0
                                                               queryOptions:@{ @"mode" : @"search", @"explain" : @YES }
                                                                      error:&error];
  XCTAssertNotNil(query);
  XCTAssertNil(error);

  NSDictionary *summary = [[ALNSearchModuleRuntime sharedRuntime] dashboardSummary];
  XCTAssertEqualObjects(@"ALNMeilisearchSearchEngine", summary[@"engine"][@"identifier"]);
  XCTAssertTrue([summary[@"totals"][@"recentQueries"] unsignedIntegerValue] >= 1U);
  XCTAssertTrue([summary[@"totals"][@"replayQueueDepth"] unsignedIntegerValue] == 0U);

  ALNResponse *drilldownResponse =
      [app dispatchRequest:ALNTestRequestWithMethod(@"GET",
                                                    @"/search/api/resources/products",
                                                    @"",
                                                    @{
                                                      @"Accept" : @"application/json",
                                                      @"X-Search-User" : @"admin-user",
                                                      @"X-Search-Roles" : @"admin,operator",
                                                    },
                                                    nil)];
  XCTAssertEqual((NSInteger)200, drilldownResponse.statusCode);
  NSDictionary *drilldownJSON = ALNTestJSONDictionaryFromResponse(drilldownResponse, &error);
  XCTAssertNil(error);
  NSDictionary *resource = drilldownJSON[@"data"][@"resource"];
  XCTAssertEqualObjects(@"phase27meili_products", resource[@"engineDescriptor"][@"indexName"]);
  XCTAssertEqualObjects(@"drained", resource[@"lastReplayStatus"]);
  XCTAssertTrue([drilldownJSON[@"data"][@"recentQueries"] count] >= 1U);
  XCTAssertEqualObjects(@"priority", [drilldownJSON[@"data"][@"recentQueries"] lastObject][@"query"]);
}

@end
