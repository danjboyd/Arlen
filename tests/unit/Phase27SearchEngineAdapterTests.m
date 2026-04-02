#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNSearchModule.h"
#import "../shared/Phase27SearchTestSupport.h"

@interface ALNMeilisearchSearchEngine : NSObject <ALNSearchEngine>
@end

@interface ALNMeilisearchSearchEngine (Phase27AdapterCapture)
- (nullable NSDictionary *)jsonRequestWithMethod:(NSString *)method
                                            path:(NSString *)path
                                         headers:(NSDictionary *)headers
                                            body:(id)body
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                           error:(NSError **)error;
@end

@interface ALNOpenSearchSearchEngine : NSObject <ALNSearchEngine>
@end

@interface ALNOpenSearchSearchEngine (Phase27AdapterCapture)
- (nullable NSDictionary *)jsonRequestWithMethod:(NSString *)method
                                            path:(NSString *)path
                                         headers:(NSDictionary *)headers
                                            body:(id)body
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                           error:(NSError **)error;
- (nullable NSDictionary *)dataRequestWithMethod:(NSString *)method
                                            path:(NSString *)path
                                         headers:(NSDictionary *)headers
                                            body:(NSData *)body
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                           error:(NSError **)error;
@end

static id Phase27SearchCaptureValue(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"";
  }
  if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *items = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
      [items addObject:Phase27SearchCaptureValue(entry)];
    }
    return items;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (id rawKey in [(NSDictionary *)value allKeys]) {
      dictionary[[rawKey description]] = Phase27SearchCaptureValue([(NSDictionary *)value objectForKey:rawKey]);
    }
    return dictionary;
  }
  if ([value isKindOfClass:[NSData class]]) {
    return [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding] ?: @"";
  }
  return [value description] ?: @"";
}

static NSMutableArray<NSDictionary *> *Phase27CapturedMeilisearchRequests(void) {
  static NSMutableArray<NSDictionary *> *requests = nil;
  if (requests == nil) {
    requests = [NSMutableArray array];
  }
  return requests;
}

static NSMutableArray<NSDictionary *> *Phase27CapturedOpenSearchRequests(void) {
  static NSMutableArray<NSDictionary *> *requests = nil;
  if (requests == nil) {
    requests = [NSMutableArray array];
  }
  return requests;
}

static void Phase27ResetCapturedAdapterRequests(void) {
  [Phase27CapturedMeilisearchRequests() removeAllObjects];
  [Phase27CapturedOpenSearchRequests() removeAllObjects];
}

@interface Phase27CaptureMeilisearchEngine : ALNMeilisearchSearchEngine
@end

@implementation Phase27CaptureMeilisearchEngine

- (nullable NSDictionary *)jsonRequestWithMethod:(NSString *)method
                                            path:(NSString *)path
                                         headers:(NSDictionary *)headers
                                            body:(id)body
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                           error:(NSError **)error {
  (void)allowNotFound;
  (void)message;
  if (error != NULL) {
    *error = nil;
  }
  [Phase27CapturedMeilisearchRequests() addObject:@{
    @"method" : method ?: @"",
    @"path" : path ?: @"",
    @"headers" : Phase27SearchCaptureValue(headers ?: @{}),
    @"body" : Phase27SearchCaptureValue(body),
  }];
  if ([path hasSuffix:@"/search"]) {
    return @{
      @"status" : @200,
      @"headers" : @{},
      @"body" : @{
        @"hits" : @[
          @{
            @"recordID" : @"sku-103",
            @"_rankingScore" : @9.2,
            @"_formatted" : @{
              @"description" : @"Rack accessory for <em>priority</em> stations.",
            },
          },
        ],
        @"estimatedTotalHits" : @1,
        @"facetDistribution" : @{
          @"category" : @{
            @"priority" : @1,
          },
        },
      },
    };
  }
  return @{
    @"status" : @202,
    @"headers" : @{},
    @"body" : @{},
  };
}

@end

@interface Phase27CaptureOpenSearchEngine : ALNOpenSearchSearchEngine
@end

@implementation Phase27CaptureOpenSearchEngine

- (nullable NSDictionary *)jsonRequestWithMethod:(NSString *)method
                                            path:(NSString *)path
                                         headers:(NSDictionary *)headers
                                            body:(id)body
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                           error:(NSError **)error {
  (void)allowNotFound;
  (void)message;
  if (error != NULL) {
    *error = nil;
  }
  [Phase27CapturedOpenSearchRequests() addObject:@{
    @"transport" : @"json",
    @"method" : method ?: @"",
    @"path" : path ?: @"",
    @"headers" : Phase27SearchCaptureValue(headers ?: @{}),
    @"body" : Phase27SearchCaptureValue(body),
  }];
  if ([path hasSuffix:@"/_search"]) {
    return @{
      @"status" : @200,
      @"headers" : @{},
      @"body" : @{
        @"hits" : @{
          @"total" : @{ @"value" : @1 },
          @"hits" : @[
            @{
              @"_source" : @{ @"recordID" : @"sku-103" },
              @"_score" : @12.5,
              @"highlight" : @{
                @"description" : @[ @"Rack accessory for <em>priority</em> stations." ],
              },
            },
          ],
        },
        @"aggregations" : @{
          @"category" : @{
            @"buckets" : @[
              @{ @"key" : @"priority", @"doc_count" : @1 },
            ],
          },
        },
      },
    };
  }
  return @{
    @"status" : @200,
    @"headers" : @{},
    @"body" : @{},
  };
}

- (nullable NSDictionary *)dataRequestWithMethod:(NSString *)method
                                            path:(NSString *)path
                                         headers:(NSDictionary *)headers
                                            body:(NSData *)body
                                   allowNotFound:(BOOL)allowNotFound
                                         message:(NSString *)message
                                           error:(NSError **)error {
  (void)allowNotFound;
  (void)message;
  if (error != NULL) {
    *error = nil;
  }
  [Phase27CapturedOpenSearchRequests() addObject:@{
    @"transport" : @"data",
    @"method" : method ?: @"",
    @"path" : path ?: @"",
    @"headers" : Phase27SearchCaptureValue(headers ?: @{}),
    @"bodyText" : Phase27SearchCaptureValue(body ?: [NSData data]),
  }];
  return @{
    @"status" : @200,
    @"headers" : @{},
    @"body" : @{ @"errors" : @NO },
    @"rawBody" : body ?: [NSData data],
  };
}

@end

@interface Phase27SearchEngineAdapterTests : XCTestCase
@end

@implementation Phase27SearchEngineAdapterTests

- (void)setUp {
  [super setUp];
  Phase27SearchResetStores();
  Phase27ResetCapturedAdapterRequests();
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

- (void)testMeilisearchLiveAdapterSyncsChunksAndTranslatesSearchPayload {
  ALNApplication *app = [self applicationWithSearchConfig:@{
    @"engineClass" : @"Phase27CaptureMeilisearchEngine",
    @"engine" : @{
      @"meilisearch" : @{
        @"serviceURL" : @"http://meili.test",
        @"apiKey" : @"phase27-test-key",
        @"liveRequestsEnabled" : @YES,
        @"indexPrefix" : @"phase27live_meili",
        @"chunkSize" : @2,
      },
    },
  }];
  [self registerModulesForApplication:app];
  [self seedSearchIndexes];

  NSMutableArray<NSDictionary *> *productUploads = [NSMutableArray array];
  for (NSDictionary *request in Phase27CapturedMeilisearchRequests()) {
    if ([request[@"path"] containsString:@"/phase27live_meili_products/documents?"]) {
      [productUploads addObject:request];
    }
  }
  XCTAssertEqual((NSUInteger)2, [productUploads count]);
  XCTAssertEqual((NSUInteger)2, [productUploads[0][@"body"] count]);
  XCTAssertEqual((NSUInteger)1, [productUploads[1][@"body"] count]);

  NSError *error = nil;
  NSDictionary *result = [[ALNSearchModuleRuntime sharedRuntime] searchQuery:@"priority"
                                                          resourceIdentifier:@"products"
                                                                     filters:@{
                                                                       @"category" : @"priority",
                                                                       @"inventory_count__gte" : @5,
                                                                     }
                                                                        sort:@"-inventory_count"
                                                                       limit:10
                                                                      offset:0
                                                                queryOptions:@{ @"mode" : @"search" }
                                                                       error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"meilisearch", result[@"debug"][@"adapter"]);
  XCTAssertEqualObjects(@"sku-103", [result[@"results"] firstObject][@"recordID"]);
  XCTAssertEqualObjects(@1, result[@"total"]);
  XCTAssertEqualObjects(@"category", [result[@"facets"] firstObject][@"name"]);

  NSDictionary *searchRequest = [Phase27CapturedMeilisearchRequests() lastObject];
  XCTAssertTrue([searchRequest[@"path"] hasSuffix:@"/search"]);
  XCTAssertTrue([(NSArray *)(searchRequest[@"body"][@"filter"] ?: @[]) containsObject:@"category = \"priority\""]);
  XCTAssertTrue([(NSArray *)(searchRequest[@"body"][@"filter"] ?: @[]) containsObject:@"inventory_count >= 5"]);
  XCTAssertEqualObjects(@[ @"inventory_count:desc" ], searchRequest[@"body"][@"sort"]);
  XCTAssertEqualObjects(@[ @"category" ], searchRequest[@"body"][@"facets"]);
  XCTAssertTrue([(NSArray *)(searchRequest[@"body"][@"attributesToSearchOn"] ?: @[]) containsObject:@"name"]);
}

- (void)testOpenSearchLiveAdapterUsesBulkSyncAndDSLQueryTranslation {
  ALNApplication *app = [self applicationWithSearchConfig:@{
    @"engineClass" : @"Phase27CaptureOpenSearchEngine",
    @"engine" : @{
      @"opensearch" : @{
        @"serviceURL" : @"http://opensearch.test",
        @"apiKey" : @"phase27-opensearch-key",
        @"liveRequestsEnabled" : @YES,
        @"indexPrefix" : @"phase27live_os",
        @"chunkSize" : @2,
      },
    },
  }];
  [self registerModulesForApplication:app];
  [self seedSearchIndexes];

  NSMutableArray<NSDictionary *> *productBulks = [NSMutableArray array];
  for (NSDictionary *request in Phase27CapturedOpenSearchRequests()) {
    if ([request[@"path"] containsString:@"/phase27live_os_products/_bulk?refresh=true"]) {
      [productBulks addObject:request];
    }
  }
  XCTAssertEqual((NSUInteger)2, [productBulks count]);
  XCTAssertTrue([productBulks[0][@"bodyText"] containsString:@"sku-100"]);
  XCTAssertTrue([productBulks[0][@"bodyText"] containsString:@"sku-102"]);
  XCTAssertTrue([productBulks[1][@"bodyText"] containsString:@"sku-103"]);

  NSError *error = nil;
  NSDictionary *result = [[ALNSearchModuleRuntime sharedRuntime] searchQuery:@"priority"
                                                          resourceIdentifier:@"products"
                                                                     filters:@{
                                                                       @"category" : @"priority",
                                                                       @"inventory_count__gte" : @5,
                                                                     }
                                                                        sort:@"-inventory_count"
                                                                       limit:10
                                                                      offset:0
                                                                queryOptions:@{ @"mode" : @"search", @"explain" : @YES }
                                                                       error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"opensearch", result[@"debug"][@"adapter"]);
  XCTAssertEqualObjects(@"sku-103", [result[@"results"] firstObject][@"recordID"]);
  XCTAssertEqualObjects(@"category", [result[@"facets"] firstObject][@"name"]);

  NSDictionary *searchRequest = [Phase27CapturedOpenSearchRequests() lastObject];
  NSDictionary *payload = searchRequest[@"body"];
  XCTAssertTrue([searchRequest[@"path"] hasSuffix:@"/_search"]);
  XCTAssertEqualObjects(@"priority", payload[@"query"][@"bool"][@"must"][0][@"multi_match"][@"query"]);
  XCTAssertEqualObjects(@"priority", payload[@"query"][@"bool"][@"filter"][0][@"term"][@"category.keyword"]);
  XCTAssertEqualObjects(@5, payload[@"query"][@"bool"][@"filter"][1][@"range"][@"inventory_count"][@"gte"]);
  XCTAssertEqualObjects(@"desc", payload[@"sort"][0][@"inventory_count"][@"order"]);
  XCTAssertEqualObjects(@"category.keyword", payload[@"aggs"][@"category"][@"terms"][@"field"]);
  XCTAssertTrue([payload[@"highlight"][@"fields"][@"description"] isKindOfClass:[NSDictionary class]]);
}

@end
