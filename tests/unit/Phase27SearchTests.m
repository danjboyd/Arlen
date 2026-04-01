#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNSearchModule.h"
#import "../shared/Phase27SearchTestSupport.h"

@interface Phase27SearchTests : XCTestCase
@end

@implementation Phase27SearchTests

- (void)setUp {
  [super setUp];
  Phase27SearchResetStores();
}

- (ALNApplication *)applicationWithConfig:(NSDictionary *)extraSearchConfig
                                 database:(NSDictionary *)database {
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
    @"database" : [database isKindOfClass:[NSDictionary class]] ? database : @{},
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

- (void)seedSearchIndexesForRuntime:(ALNSearchModuleRuntime *)runtime {
  NSError *error = nil;
  NSDictionary *queued = [runtime queueReindexForResourceIdentifier:nil error:&error];
  XCTAssertNotNil(queued);
  XCTAssertNil(error);
  NSDictionary *worker = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:20 error:&error];
  XCTAssertNotNil(worker);
  XCTAssertNil(error);
}

- (NSDictionary *)resourceRowNamed:(NSString *)identifier fromDashboard:(NSDictionary *)dashboard {
  for (NSDictionary *entry in [dashboard[@"resources"] isKindOfClass:[NSArray class]] ? dashboard[@"resources"] : @[]) {
    if ([entry[@"identifier"] isEqualToString:identifier]) {
      return entry;
    }
  }
  return @{};
}

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (void)testDefaultSearchShapesResultsAndExposesRichQuerySections {
  ALNApplication *app = [self applicationWithConfig:nil database:nil];
  [self registerModulesForApplication:app];

  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  [self seedSearchIndexesForRuntime:runtime];

  NSError *error = nil;
  NSDictionary *priority = [runtime searchQuery:@"priority"
                             resourceIdentifier:@"products"
                                        filters:nil
                                           sort:nil
                                          limit:10
                                         offset:0
                                   queryOptions:@{ @"mode" : @"search" }
                                          error:&error];
  XCTAssertNotNil(priority);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"search", priority[@"mode"]);
  XCTAssertEqualObjects(@[ @"products" ], priority[@"resources"]);
  XCTAssertEqualObjects(@"ALNDefaultSearchEngine", priority[@"engine"]);
  XCTAssertTrue([priority[@"engineCapabilities"][@"supportsFacets"] boolValue]);
  XCTAssertTrue([priority[@"engineCapabilities"][@"supportsPromotedResults"] boolValue]);
  XCTAssertTrue([priority[@"engineCapabilities"][@"supportsTypedFilters"] boolValue]);

  NSArray *promoted = [priority[@"promotedResults"] isKindOfClass:[NSArray class]] ? priority[@"promotedResults"] : @[];
  XCTAssertEqual((NSUInteger)1, [promoted count]);
  XCTAssertEqualObjects(@"sku-102", promoted[0][@"recordID"]);
  XCTAssertEqualObjects(@YES, promoted[0][@"promoted"]);
  XCTAssertEqualObjects(@"Featured", promoted[0][@"promotionLabel"]);
  XCTAssertNil(promoted[0][@"record"]);
  XCTAssertEqualObjects(@"featured", promoted[0][@"badge"]);

  NSArray *results = [priority[@"results"] isKindOfClass:[NSArray class]] ? priority[@"results"] : @[];
  XCTAssertEqual((NSUInteger)1, [results count]);
  XCTAssertEqualObjects(@"sku-103", results[0][@"recordID"]);
  XCTAssertNil(results[0][@"record"]);
  XCTAssertNil(results[0][@"fieldText"]);
  XCTAssertEqualObjects(@"featured", results[0][@"badge"]);
  XCTAssertEqualObjects(@"priority", results[0][@"fields"][@"category"]);
  XCTAssertNil(results[0][@"fields"][@"internal_cost"]);

  NSArray *facets = [priority[@"facets"] isKindOfClass:[NSArray class]] ? priority[@"facets"] : @[];
  XCTAssertEqual((NSUInteger)1, [facets count]);
  XCTAssertEqualObjects(@"category", facets[0][@"name"]);
  NSArray *facetValues = [facets[0][@"values"] isKindOfClass:[NSArray class]] ? facets[0][@"values"] : @[];
  XCTAssertEqualObjects(@"priority", facetValues[0][@"value"]);
  XCTAssertEqualObjects(@2, facetValues[0][@"count"]);

  NSDictionary *autocomplete = [runtime searchQuery:@"pri"
                                 resourceIdentifier:@"products"
                                            filters:nil
                                               sort:nil
                                              limit:10
                                             offset:0
                                       queryOptions:@{ @"mode" : @"autocomplete" }
                                              error:&error];
  XCTAssertNotNil(autocomplete);
  XCTAssertNil(error);
  XCTAssertTrue([(NSArray *)(autocomplete[@"autocomplete"] ?: @[]) containsObject:@"Priority Kit"]);

  NSDictionary *fuzzy = [runtime searchQuery:@"pririty"
                          resourceIdentifier:@"products"
                                     filters:nil
                                        sort:nil
                                       limit:10
                                      offset:0
                                queryOptions:@{ @"mode" : @"fuzzy" }
                                       error:&error];
  XCTAssertNotNil(fuzzy);
  XCTAssertNil(error);
  NSArray *suggestions = [fuzzy[@"suggestions"] isKindOfClass:[NSArray class]] ? fuzzy[@"suggestions"] : @[];
  XCTAssertTrue([suggestions containsObject:@"priority"]);

  NSDictionary *metadata = [runtime resourceMetadataForIdentifier:@"products"];
  XCTAssertTrue([metadata[@"queryModes"] containsObject:@"autocomplete"]);
  XCTAssertEqualObjects(@"integer", metadata[@"fieldTypes"][@"inventory_count"]);
  NSArray *filters = [metadata[@"filters"] isKindOfClass:[NSArray class]] ? metadata[@"filters"] : @[];
  NSDictionary *inventoryFilter = filters[1];
  XCTAssertTrue([(NSArray *)(inventoryFilter[@"operators"] ?: @[]) containsObject:@"gte"]);
  XCTAssertTrue([(NSArray *)(inventoryFilter[@"operators"] ?: @[]) containsObject:@"lte"]);
}

- (void)testInvalidQueryModeFailsClosed {
  ALNApplication *app = [self applicationWithConfig:nil database:nil];
  [self registerModulesForApplication:app];

  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  [self seedSearchIndexesForRuntime:runtime];

  NSError *error = nil;
  XCTAssertNil([runtime searchQuery:@"priority"
                 resourceIdentifier:@"products"
                            filters:nil
                               sort:nil
                              limit:10
                             offset:0
                       queryOptions:@{ @"mode" : @"boolean" }
                              error:&error]);
  XCTAssertEqual(ALNSearchModuleErrorValidationFailed, error.code);
}

- (void)testPostgresEngineSupportsFTSIncrementalSyncAndDegradedFallback {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *tableName = Phase27SearchUniquePostgresTableName();
  ALNApplication *app = [self applicationWithConfig:@{
    @"engineClass" : @"ALNPostgresSearchEngine",
    @"engine" : @{
      @"postgres" : @{
        @"tableName" : tableName,
        @"textSearchConfiguration" : @"simple",
      },
    },
  }
                                       database:@{
                                         @"connectionString" : dsn,
                                       }];
  [self registerModulesForApplication:app];

  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  [self seedSearchIndexesForRuntime:runtime];

  NSError *error = nil;
  NSDictionary *phrase = [runtime searchQuery:@"Priority Kit"
                           resourceIdentifier:@"products"
                                      filters:nil
                                         sort:nil
                                        limit:10
                                       offset:0
                                 queryOptions:@{ @"mode" : @"phrase" }
                                        error:&error];
  XCTAssertNotNil(phrase);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"ALNPostgresSearchEngine", phrase[@"engine"]);
  XCTAssertTrue([phrase[@"engineCapabilities"][@"supportsFullTextRanking"] boolValue]);
  XCTAssertEqualObjects(@"sku-102", [phrase[@"promotedResults"] firstObject][@"recordID"]);

  NSDictionary *fuzzy = [runtime searchQuery:@"pririty"
                          resourceIdentifier:@"products"
                                     filters:nil
                                        sort:nil
                                       limit:10
                                      offset:0
                                queryOptions:@{ @"mode" : @"fuzzy" }
                                       error:&error];
  XCTAssertNotNil(fuzzy);
  XCTAssertNil(error);
  NSArray *fuzzyResults = [fuzzy[@"results"] isKindOfClass:[NSArray class]] ? fuzzy[@"results"] : @[];
  XCTAssertEqualObjects(@"sku-103", fuzzyResults[0][@"recordID"]);
  XCTAssertTrue([(NSArray *)(fuzzyResults[0][@"highlights"] ?: @[]) count] > 0);

  NSMutableDictionary *updated = [Phase27SearchProductStore()[@"sku-103"] mutableCopy];
  updated[@"description"] = @"Escalation bench for newly urgent requests.";
  Phase27SearchProductStore()[@"sku-103"] = updated;
  NSDictionary *queued = [runtime queueIncrementalSyncForResourceIdentifier:@"products"
                                                                     record:[updated copy]
                                                                  operation:@"upsert"
                                                                      error:&error];
  XCTAssertNotNil(queued);
  XCTAssertNil(error);
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error]);
  XCTAssertNil(error);

  NSDictionary *incremental = [runtime searchQuery:@"Escalation"
                                resourceIdentifier:@"products"
                                           filters:nil
                                              sort:nil
                                             limit:10
                                            offset:0
                                      queryOptions:@{ @"mode" : @"search" }
                                             error:&error];
  XCTAssertNotNil(incremental);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"sku-103", [incremental[@"results"] firstObject][@"recordID"]);

  Phase27SearchSetProductsBuildShouldFail(YES);
  XCTAssertNotNil([runtime queueReindexForResourceIdentifier:@"products" error:&error]);
  XCTAssertNil(error);
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error]);
  XCTAssertNil(error);

  NSDictionary *dashboard = [runtime dashboardSummary];
  NSDictionary *products = [self resourceRowNamed:@"products" fromDashboard:dashboard];
  XCTAssertEqualObjects(@"degraded", products[@"indexState"]);

  NSDictionary *fallback = [runtime searchQuery:@"Escalation"
                             resourceIdentifier:@"products"
                                        filters:nil
                                           sort:nil
                                          limit:10
                                         offset:0
                                   queryOptions:@{ @"mode" : @"search" }
                                          error:&error];
  XCTAssertNotNil(fallback);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"sku-103", [fallback[@"results"] firstObject][@"recordID"]);
}

@end
