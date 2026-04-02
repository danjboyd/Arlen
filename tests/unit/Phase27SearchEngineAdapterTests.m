#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNSearchModule.h"
#import "../shared/Phase27SearchTestSupport.h"

@interface Phase27SearchEngineAdapterTests : XCTestCase
@end

@implementation Phase27SearchEngineAdapterTests

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

- (void)seedSearchIndexes {
  NSError *error = nil;
  XCTAssertNotNil([[ALNSearchModuleRuntime sharedRuntime] queueReindexForResourceIdentifier:nil error:&error]);
  XCTAssertNil(error);
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:20 error:&error]);
  XCTAssertNil(error);
}

- (void)testMeilisearchFixtureAdapterProvidesCursorPaginationAndEngineState {
  ALNApplication *app = [self applicationWithSearchConfig:@{
    @"engineClass" : @"ALNMeilisearchSearchEngine",
    @"engine" : @{
      @"meilisearch" : @{
        @"fixturesPath" : Phase27SearchFixturesPath(@"meilisearch_fixtures.json"),
        @"indexPrefix" : @"phase27meili",
        @"rankingRules" : @[ @"words", @"typo", @"sort" ],
      },
    },
  }];
  [self registerModulesForApplication:app];
  [self seedSearchIndexes];

  NSError *error = nil;
  NSDictionary *pageOne = [[ALNSearchModuleRuntime sharedRuntime] searchQuery:@"kit"
                                                           resourceIdentifier:@"products"
                                                                      filters:nil
                                                                         sort:nil
                                                                        limit:1
                                                                       offset:0
                                                                 queryOptions:@{ @"mode" : @"search" }
                                                                        error:&error];
  XCTAssertNotNil(pageOne);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"ALNMeilisearchSearchEngine", pageOne[@"engine"]);
  XCTAssertTrue([pageOne[@"engineCapabilities"][@"supportsCursorPagination"] boolValue]);
  XCTAssertEqualObjects(@"sku-102", [pageOne[@"results"] firstObject][@"recordID"]);
  XCTAssertEqualObjects(@"words", [pageOne[@"results"] firstObject][@"explain"][@"rankingRule"]);
  NSString *nextCursor = pageOne[@"cursor"][@"next"];
  XCTAssertTrue([nextCursor length] > 0);

  NSDictionary *pageTwo = [[ALNSearchModuleRuntime sharedRuntime] searchQuery:@"kit"
                                                           resourceIdentifier:@"products"
                                                                      filters:nil
                                                                         sort:nil
                                                                        limit:1
                                                                       offset:0
                                                                 queryOptions:@{
                                                                   @"mode" : @"search",
                                                                   @"cursor" : nextCursor,
                                                                   @"explain" : @YES,
                                                                 }
                                                                        error:&error];
  XCTAssertNotNil(pageTwo);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"sku-100", [pageTwo[@"results"] firstObject][@"recordID"]);
  XCTAssertEqualObjects(@"meilisearch", pageTwo[@"debug"][@"adapter"]);

  NSDictionary *drilldown = [[ALNSearchModuleRuntime sharedRuntime] resourceDrilldownForIdentifier:@"products"];
  NSDictionary *resource = drilldown[@"resource"];
  XCTAssertEqualObjects(@"phase27meili_products", resource[@"engineDescriptor"][@"indexName"]);
  XCTAssertEqualObjects(@"fixture-v1", resource[@"engineDescriptor"][@"settingsVersion"]);
  XCTAssertEqualObjects(@4102, resource[@"engineDescriptor"][@"taskUID"]);
}

- (void)testOpenSearchFixtureAdapterDecoratesExplainabilityAndMappings {
  ALNApplication *app = [self applicationWithSearchConfig:@{
    @"engineClass" : @"ALNOpenSearchSearchEngine",
    @"engine" : @{
      @"opensearch" : @{
        @"fixturesPath" : Phase27SearchFixturesPath(@"opensearch_fixtures.json"),
        @"indexPrefix" : @"phase27os",
        @"analysis" : @{ @"analyzer" : @"standard" },
        @"aliases" : @[ @"phase27_products_active" ],
      },
    },
  }];
  [self registerModulesForApplication:app];
  [self seedSearchIndexes];

  NSError *error = nil;
  NSDictionary *result = [[ALNSearchModuleRuntime sharedRuntime] searchQuery:@"kit"
                                                          resourceIdentifier:@"products"
                                                                     filters:nil
                                                                        sort:nil
                                                                       limit:10
                                                                      offset:0
                                                                queryOptions:@{ @"mode" : @"search", @"explain" : @YES }
                                                                       error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"ALNOpenSearchSearchEngine", result[@"engine"]);
  XCTAssertEqualObjects(@"sku-100", [result[@"results"] firstObject][@"recordID"]);
  XCTAssertEqualObjects(@"bool", result[@"results"][1][@"explain"][@"query"]);
  XCTAssertEqualObjects(@"opensearch", result[@"debug"][@"adapter"]);

  NSDictionary *drilldown = [[ALNSearchModuleRuntime sharedRuntime] resourceDrilldownForIdentifier:@"products"];
  NSDictionary *resource = drilldown[@"resource"];
  XCTAssertEqualObjects(@"phase27os_products", resource[@"engineDescriptor"][@"indexName"]);
  XCTAssertEqualObjects(@"phase27_products_active", [resource[@"engineDescriptor"][@"aliases"] firstObject]);
  XCTAssertTrue([resource[@"engineDescriptor"][@"mappings"][@"properties"][@"name"] isKindOfClass:[NSDictionary class]]);
}

@end
