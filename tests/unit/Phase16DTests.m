#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNSearchModule.h"

static BOOL gPhase16DSearchBuildShouldFail = NO;

static NSMutableDictionary<NSString *, NSMutableDictionary *> *Phase16DOrderStore(void) {
  static NSMutableDictionary<NSString *, NSMutableDictionary *> *store = nil;
  if (store == nil) {
    store = [NSMutableDictionary dictionary];
  }
  return store;
}

static void Phase16DResetOrderStore(void) {
  NSMutableDictionary *store = Phase16DOrderStore();
  [store removeAllObjects];
  store[@"ord-100"] = [@{
    @"id" : @"ord-100",
    @"order_number" : @"100",
    @"status" : @"reviewed",
    @"owner_email" : @"buyer-one@example.test",
    @"total_cents" : @1250,
  } mutableCopy];
  store[@"ord-102"] = [@{
    @"id" : @"ord-102",
    @"order_number" : @"102",
    @"status" : @"pending",
    @"owner_email" : @"priority@example.test",
    @"total_cents" : @2400,
  } mutableCopy];
}

@interface Phase16DSearchResource : NSObject <ALNSearchResourceDefinition>
@end

@implementation Phase16DSearchResource

- (NSString *)searchModuleResourceIdentifier {
  return @"orders";
}

- (NSDictionary *)searchModuleResourceMetadata {
  return @{
    @"label" : @"Orders",
    @"identifierField" : @"id",
    @"primaryField" : @"order_number",
    @"indexedFields" : @[ @"order_number", @"status", @"owner_email" ],
    @"weightedFields" : @{
      @"order_number" : @4,
      @"status" : @2,
      @"owner_email" : @1,
    },
    @"filters" : @[
      @{ @"name" : @"status", @"operators" : @[ @"eq", @"in" ] },
      @{ @"name" : @"total_cents", @"operators" : @[ @"eq", @"gte", @"lte" ] },
    ],
    @"sorts" : @[
      @{ @"name" : @"order_number", @"default" : @YES },
      @{ @"name" : @"total_cents" },
    ],
    @"defaultSort" : @"order_number",
    @"pathTemplate" : @"/orders/:identifier",
  };
}

- (NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)runtime;
  if (gPhase16DSearchBuildShouldFail) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase16D"
                                   code:11
                               userInfo:@{ NSLocalizedDescriptionKey : @"expected search build failure" }];
    }
    return nil;
  }
  NSArray *keys = [[Phase16DOrderStore() allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *key in keys) {
    [records addObject:[Phase16DOrderStore()[key] copy]];
  }
  return records;
}

@end

@interface Phase16DSearchProvider : NSObject <ALNSearchResourceProvider>
@end

@implementation Phase16DSearchProvider

- (NSArray<id<ALNSearchResourceDefinition>> *)searchModuleResourcesForRuntime:(ALNSearchModuleRuntime *)runtime
                                                                        error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16DSearchResource alloc] init] ];
}

@end

@interface Phase16DTests : XCTestCase
@end

@implementation Phase16DTests

- (void)setUp {
  [super setUp];
  Phase16DResetOrderStore();
  gPhase16DSearchBuildShouldFail = NO;
}

- (NSString *)temporaryDirectory {
  NSString *template =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"arlen-phase16d-XXXXXX"];
  const char *templateCString = [template fileSystemRepresentation];
  char *buffer = strdup(templateCString);
  XCTAssertNotEqual(buffer, NULL);
  char *created = mkdtemp(buffer);
  XCTAssertNotEqual(created, NULL);
  NSString *result = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:buffer
                                                                                  length:strlen(buffer)];
  free(buffer);
  return result;
}

- (ALNApplication *)applicationWithStatePath:(NSString *)statePath {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[] },
      @"worker" : @{ @"retryDelaySeconds" : @0 },
    },
    @"searchModule" : @{
      @"providers" : @{ @"classes" : @[ @"Phase16DSearchProvider" ] },
      @"persistence" : @{
        @"enabled" : @YES,
        @"path" : statePath ?: @"",
      },
    },
  }];
}

- (void)registerModulesForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNSearchModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (NSDictionary *)ordersRowFromDashboard:(NSDictionary *)dashboard {
  NSArray *resources = [dashboard[@"resources"] isKindOfClass:[NSArray class]] ? dashboard[@"resources"] : @[];
  for (NSDictionary *entry in resources) {
    if ([entry[@"identifier"] isEqualToString:@"orders"]) {
      return entry;
    }
  }
  return @{};
}

- (void)seedActiveIndexForRuntime:(ALNSearchModuleRuntime *)runtime {
  NSError *error = nil;
  NSDictionary *queued = [runtime queueReindexForResourceIdentifier:@"orders" error:&error];
  XCTAssertNotNil(queued);
  XCTAssertNil(error);
  NSDictionary *workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);
}

- (void)testFullReindexAndIncrementalSyncShareJobContractAndPersistGenerationState {
  NSString *statePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"search-state.plist"];
  ALNApplication *app = [self applicationWithStatePath:statePath];
  [self registerModulesForApplication:app];

  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *queued = [runtime queueReindexForResourceIdentifier:@"orders" error:&error];
  XCTAssertNotNil(queued);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"full", queued[@"mode"]);
  XCTAssertEqual((NSUInteger)1, [[[ALNJobsModuleRuntime sharedRuntime] pendingJobs] count]);

  NSDictionary *workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);

  NSDictionary *query = [runtime searchQuery:@"priority"
                          resourceIdentifier:@"orders"
                                     filters:nil
                                        sort:nil
                                       limit:10
                                      offset:0
                                       error:&error];
  XCTAssertNotNil(query);
  XCTAssertNil(error);
  NSArray *results = [query[@"results"] isKindOfClass:[NSArray class]] ? query[@"results"] : @[];
  XCTAssertEqual((NSUInteger)1, [results count]);
  XCTAssertEqualObjects(@"ord-102", results[0][@"recordID"]);
  XCTAssertEqual((NSUInteger)1, [results[0][@"highlights"] count]);

  NSDictionary *dashboard = [runtime dashboardSummary];
  NSDictionary *orders = [self ordersRowFromDashboard:dashboard];
  XCTAssertEqualObjects(@1, orders[@"activeGeneration"]);
  XCTAssertEqualObjects(@1, orders[@"generationCount"]);
  XCTAssertEqualObjects(@"ready", orders[@"indexState"]);

  NSMutableDictionary *updatedRecord = [Phase16DOrderStore()[@"ord-102"] mutableCopy];
  updatedRecord[@"status"] = @"reviewed";
  Phase16DOrderStore()[@"ord-102"] = updatedRecord;

  NSDictionary *incremental = [runtime queueIncrementalSyncForResourceIdentifier:@"orders"
                                                                          record:[updatedRecord copy]
                                                                       operation:@"upsert"
                                                                           error:&error];
  XCTAssertNotNil(incremental);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"incremental", incremental[@"mode"]);

  workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);

  query = [runtime searchQuery:nil
            resourceIdentifier:@"orders"
                       filters:@{ @"status" : @"reviewed" }
                          sort:@"-total_cents"
                         limit:10
                        offset:0
                         error:&error];
  XCTAssertNotNil(query);
  XCTAssertNil(error);
  results = [query[@"results"] isKindOfClass:[NSArray class]] ? query[@"results"] : @[];
  XCTAssertEqual((NSUInteger)2, [results count]);
  XCTAssertEqualObjects(@"ord-102", results[0][@"recordID"]);

  dashboard = [runtime dashboardSummary];
  orders = [self ordersRowFromDashboard:dashboard];
  XCTAssertEqualObjects(@1, orders[@"activeGeneration"]);
  XCTAssertEqualObjects(@1, orders[@"generationCount"]);
  XCTAssertEqualObjects(@"upsert", orders[@"lastSyncOperation"]);

  ALNApplication *restarted = [self applicationWithStatePath:statePath];
  [self registerModulesForApplication:restarted];
  runtime = [ALNSearchModuleRuntime sharedRuntime];
  dashboard = [runtime dashboardSummary];
  orders = [self ordersRowFromDashboard:dashboard];
  XCTAssertEqualObjects(@2, orders[@"documentCount"]);
  XCTAssertEqualObjects(@1, orders[@"activeGeneration"]);
  XCTAssertEqualObjects(@"ready", orders[@"indexState"]);
}

- (void)testUnsupportedFiltersAndSortsFailClosed {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"search-state.plist"]];
  [self registerModulesForApplication:app];

  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  [self seedActiveIndexForRuntime:runtime];

  NSError *error = nil;
  XCTAssertNil([runtime searchQuery:nil
                 resourceIdentifier:@"orders"
                            filters:@{ @"unknown" : @"value" }
                               sort:nil
                              limit:10
                             offset:0
                              error:&error]);
  XCTAssertEqual(ALNSearchModuleErrorValidationFailed, error.code);

  error = nil;
  XCTAssertNil([runtime searchQuery:nil
                 resourceIdentifier:@"orders"
                            filters:nil
                               sort:@"-missing"
                              limit:10
                             offset:0
                              error:&error]);
  XCTAssertEqual(ALNSearchModuleErrorValidationFailed, error.code);

  error = nil;
  NSDictionary *filtered = [runtime searchQuery:nil
                             resourceIdentifier:@"orders"
                                        filters:@{ @"total_cents__gte" : @"2000" }
                                           sort:@"-total_cents"
                                          limit:10
                                         offset:0
                                          error:&error];
  XCTAssertNotNil(filtered);
  XCTAssertNil(error);
  NSArray *results = [filtered[@"results"] isKindOfClass:[NSArray class]] ? filtered[@"results"] : @[];
  XCTAssertEqual((NSUInteger)1, [results count]);
  XCTAssertEqualObjects(@"ord-102", results[0][@"recordID"]);
}

- (void)testFailedRebuildPreservesActiveResultsAndSurfacesDegradedState {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"search-state.plist"]];
  [self registerModulesForApplication:app];

  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  [self seedActiveIndexForRuntime:runtime];

  gPhase16DSearchBuildShouldFail = YES;
  NSError *error = nil;
  NSDictionary *queued = [runtime queueReindexForResourceIdentifier:@"orders" error:&error];
  XCTAssertNotNil(queued);
  XCTAssertNil(error);

  NSDictionary *workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);

  NSDictionary *dashboard = [runtime dashboardSummary];
  NSDictionary *orders = [self ordersRowFromDashboard:dashboard];
  XCTAssertEqualObjects(@"degraded", orders[@"indexState"]);
  XCTAssertTrue([orders[@"lastError"] isKindOfClass:[NSString class]]);
  XCTAssertTrue([orders[@"lastError"] length] > 0);
  XCTAssertEqualObjects(@1, orders[@"activeGeneration"]);

  error = nil;
  NSDictionary *query = [runtime searchQuery:@"priority"
                          resourceIdentifier:@"orders"
                                     filters:nil
                                        sort:nil
                                       limit:10
                                      offset:0
                                       error:&error];
  XCTAssertNotNil(query);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@1, query[@"total"]);

  NSDictionary *drilldown = [runtime resourceDrilldownForIdentifier:@"orders"];
  NSArray *history = [drilldown[@"history"] isKindOfClass:[NSArray class]] ? drilldown[@"history"] : @[];
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"status == %@", @"failed"];
  XCTAssertEqual((NSUInteger)1, [[history filteredArrayUsingPredicate:predicate] count]);
}

@end
