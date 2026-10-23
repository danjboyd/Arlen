#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNSearchModule.h"
#import "../shared/ALNTestSupport.h"
#import "../shared/ALNTestProcessCheckpoint.h"

// Private test seams: inject a second runtime while an engine call is in flight.
@interface ALNDefaultSearchEngine : NSObject <ALNSearchEngine>
@end
static void (^gPhase16DApplyHook)(void) = nil;
@interface Phase16DInterleavingEngine : ALNDefaultSearchEngine
@end
@implementation Phase16DInterleavingEngine
- (NSDictionary *)searchModuleApplyOperation:(NSString *)operation record:(NSDictionary *)record
    metadata:(NSDictionary *)metadata existingSnapshot:(NSDictionary *)snapshot error:(NSError **)error {
  void (^hook)(void) = gPhase16DApplyHook;
  gPhase16DApplyHook = nil;
  if (hook) hook();
  return [super searchModuleApplyOperation:operation record:record metadata:metadata existingSnapshot:snapshot error:error];
}
@end
@interface ALNSearchModuleRuntime (TransactionTestAccess)
- (BOOL)stateTransaction:(BOOL (^)(NSError **))block write:(BOOL)write error:(NSError **)error;
- (BOOL)stateTransaction:(BOOL (^)(NSError **))block write:(BOOL)write
 rollbackRecentQueriesOnly:(BOOL)rollbackRecentQueriesOnly error:(NSError **)error;
- (void)enqueueReplayOperation:(NSDictionary *)payload forResourceIdentifier:(NSString *)identifier metadata:(NSDictionary *)metadata;
- (NSDictionary *)drainReplayOperationsForResourceIdentifier:(NSString *)identifier mode:(NSString *)mode error:(NSError **)error;
- (NSDictionary *)applyIncrementalOperation:(NSString *)operation resourceIdentifier:(NSString *)identifier record:(NSDictionary *)record error:(NSError **)error;
@end

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
  if ([[[NSProcessInfo processInfo] environment][@"ARLEN_SEARCH_PROCESS_INDEX"] isEqual:@"0"]) {
    // Pause external/provider work while another process rebuilds the resource.
    NSString *path = [[NSProcessInfo processInfo] environment][@"ARLEN_SEARCH_SHARED_STATE_PATH"];
    if (!ALNTestSignalCheckpoint(path, @"building-0") || !ALNTestWaitCheckpoint(path, @"resume-0")) {
      if (error) *error = [NSError errorWithDomain:@"Phase16D" code:12 userInfo:@{NSLocalizedDescriptionKey:@"build checkpoint timed out"}];
      return nil;
    }
  }
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

@interface Phase16DAlternateResource : Phase16DSearchResource
@end
@implementation Phase16DAlternateResource
- (NSString *)searchModuleResourceIdentifier { return @"archive"; }
@end
@interface Phase16DAlternateProvider : NSObject <ALNSearchResourceProvider>
@end
@implementation Phase16DAlternateProvider
- (NSArray *)searchModuleResourcesForRuntime:(ALNSearchModuleRuntime *)runtime error:(NSError **)error {
  return @[[[Phase16DAlternateResource alloc] init]];
}
@end

@interface Phase16DTests : XCTestCase
@end

@implementation Phase16DTests

- (void)setUp {
  [super setUp];
  Phase16DResetOrderStore();
  gPhase16DSearchBuildShouldFail = NO;
  gPhase16DApplyHook = nil;
}

- (NSString *)temporaryDirectory {
  NSString *directory = ALNTestTemporaryDirectory(@"arlen-phase16d");
  XCTAssertNotNil(directory);
  return directory;
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
      @"engineClass":@"Phase16DInterleavingEngine",
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

- (void)testQueryHistoryRollbackOnBlockFailureAndExceptionPreservesTransactionDepth {
  NSString *statePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"search-state.plist"];
  ALNApplication *app = [self applicationWithStatePath:statePath];
  [self registerModulesForApplication:app];
  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  [self seedActiveIndexForRuntime:runtime];
  NSArray *historyBefore = [[runtime valueForKey:@"recentQueries"] copy];
  NSData *diskBefore = [NSData dataWithContentsOfFile:statePath];
  XCTAssertNotNil(diskBefore);

  NSError *error = nil;
  XCTAssertFalse([runtime stateTransaction:^BOOL(NSError **transactionError) {
    [[runtime valueForKey:@"recentQueries"] addObject:@{ @"query" : @"failed" }];
    if (transactionError) *transactionError = [NSError errorWithDomain:@"SearchHistoryTest" code:1 userInfo:nil];
    return NO;
  } write:YES rollbackRecentQueriesOnly:YES error:&error]);
  XCTAssertEqualObjects(@"SearchHistoryTest", error.domain);
  XCTAssertEqualObjects(historyBefore, [runtime valueForKey:@"recentQueries"]);
  XCTAssertEqualObjects(diskBefore, [NSData dataWithContentsOfFile:statePath]);

  BOOL caught = NO;
  @try {
    [runtime stateTransaction:^BOOL(NSError **transactionError) {
      [[runtime valueForKey:@"recentQueries"] addObject:@{ @"query" : @"exception" }];
      @throw [NSException exceptionWithName:@"SearchHistoryTestException" reason:@"rollback" userInfo:nil];
    } write:YES rollbackRecentQueriesOnly:YES error:NULL];
  } @catch (NSException *exception) {
    caught = YES;
    XCTAssertEqualObjects(@"SearchHistoryTestException", exception.name);
  }
  XCTAssertTrue(caught);
  XCTAssertEqualObjects(historyBefore, [runtime valueForKey:@"recentQueries"]);
  XCTAssertEqualObjects(diskBefore, [NSData dataWithContentsOfFile:statePath]);

  error = nil;
  XCTAssertTrue([runtime stateTransaction:^BOOL(NSError **transactionError) {
    XCTAssertEqual((NSUInteger)1, [[runtime valueForKey:@"stateTransactionDepth"] unsignedIntegerValue]);
    return [runtime stateTransaction:^BOOL(NSError **nestedError) {
      [[runtime valueForKey:@"recentQueries"] addObject:@{ @"query" : @"nested" }];
      return YES;
    } write:YES rollbackRecentQueriesOnly:YES error:transactionError];
  } write:YES error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)0, [[runtime valueForKey:@"stateTransactionDepth"] unsignedIntegerValue]);
  XCTAssertEqualObjects(@"nested", [[runtime valueForKey:@"recentQueries"] lastObject][@"query"]);
}

- (void)testQueryHistoryRollbackOnPersistentWriteFailureKeepsDiskAndFreshRuntime {
  NSString *directory = [self temporaryDirectory];
  NSString *statePath = [directory stringByAppendingPathComponent:@"search-state.plist"];
  ALNApplication *app = [self applicationWithStatePath:statePath];
  [self registerModulesForApplication:app];
  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  [self seedActiveIndexForRuntime:runtime];
  NSArray *historyBefore = [[runtime valueForKey:@"recentQueries"] copy];
  NSData *diskBefore = [NSData dataWithContentsOfFile:statePath];
  XCTAssertNotNil(diskBefore);

  // The read/reload succeeds from the real file. Inside the block, redirect
  // only the attempted atomic write to an existing directory so it fails
  // deterministically without relying on platform-specific file permissions.
  NSError *error = nil;
  BOOL succeeded = NO;
  @try {
    succeeded = [runtime stateTransaction:^BOOL(NSError **transactionError) {
      [[runtime valueForKey:@"recentQueries"] addObject:@{ @"query" : @"write-failed" }];
      [runtime setValue:directory forKey:@"statePath"];
      return YES;
    } write:YES rollbackRecentQueriesOnly:YES error:&error];
  } @finally {
    [runtime setValue:statePath forKey:@"statePath"];
  }
  XCTAssertFalse(succeeded);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(historyBefore, [runtime valueForKey:@"recentQueries"]);
  XCTAssertEqualObjects(diskBefore, [NSData dataWithContentsOfFile:statePath]);

  ALNSearchModuleRuntime *fresh = [[ALNSearchModuleRuntime alloc] init];
  error = nil;
  XCTAssertTrue([[ALNJobsModuleRuntime sharedRuntime] configureWithApplication:app error:&error], @"%@", error);
  XCTAssertNil(error);
  XCTAssertTrue([fresh configureWithApplication:app error:&error], @"%@", error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(historyBefore, [fresh valueForKey:@"recentQueries"]);
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

  // One job: the failed rebuild is retried with retryDelaySeconds = 0, and on
  // a ~1 ms clock (Windows) that retry can be due in the same worker pass,
  // which would record a second failure.
  NSDictionary *workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:1 error:&error];
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

- (void)testSearchStateTransactionsAcrossProcesses {
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
  NSString *sharedPath = environment[@"ARLEN_SEARCH_SHARED_STATE_PATH"];
  if (sharedPath.length > 0) {
    [self registerModulesForApplication:[self applicationWithStatePath:sharedPath]];
    ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
    NSString *index = environment[@"ARLEN_SEARCH_PROCESS_INDEX"];
    if ([environment[@"ARLEN_MODULE_PROCESS_PROBE_ABORT"] boolValue]) return;
    XCTAssertTrue(ALNTestSignalCheckpoint(sharedPath, [@"ready-" stringByAppendingString:index]));
    BOOL started = ALNTestWaitCheckpoint(sharedPath, [@"start-" stringByAppendingString:index]);
    XCTAssertTrue(started);
    if (!started) return;
    BOOL first = [environment[@"ARLEN_SEARCH_PROCESS_INDEX"] isEqual:@"0"];
    NSError *error = nil;
    NSDictionary *result = [runtime processReindexJobPayload:@{@"resource":@"orders", @"mode":@"full"} error:&error];
    if (first) {
      XCTAssertNil(result);
      XCTAssertEqualObjects(@"state_conflict", error.userInfo[@"reason"]);
      error = nil;
      NSDictionary *fresh = [runtime searchQuery:@"replacement" resourceIdentifier:@"orders" filters:nil sort:nil limit:10 offset:0 error:&error];
      XCTAssertEqualObjects(@1, fresh[@"total"]);
      XCTAssertNil(error);
      NSDictionary *deleted = [runtime searchQuery:@"buyer-one" resourceIdentifier:@"orders" filters:nil sort:nil limit:10 offset:0 error:&error];
      XCTAssertEqualObjects(@0, deleted[@"total"]);
      XCTAssertEqualObjects(@2, [self ordersRowFromDashboard:[runtime dashboardSummary]][@"activeGeneration"]);
    } else {
      XCTAssertNotNil(result, @"%@", error);
      XCTAssertNil(error);
      XCTAssertEqualObjects(@2, result[@"resources"][0][@"generation"]);
      XCTAssertNotNil(([runtime processReindexJobPayload:@{@"resource":@"orders", @"mode":@"incremental",
          @"operation":@"delete", @"record":@{@"id":@"ord-100"}} error:&error]));
      NSDictionary *replacement = @{@"id":@"ord-102", @"order_number":@"102", @"status":@"replacement", @"owner_email":@"new@example.test", @"total_cents":@10};
      XCTAssertNotNil(([runtime processReindexJobPayload:@{@"resource":@"orders", @"mode":@"incremental",
          @"operation":@"upsert", @"record":replacement} error:&error]));
      XCTAssertNil(error);
      XCTAssertTrue(ALNTestSignalCheckpoint(sharedPath, @"changed-1"));
    }
    XCTAssertTrue(ALNTestSignalCheckpoint(sharedPath, [@"complete-" stringByAppendingString:index]));
    return;
  }
  NSString *path = [[self temporaryDirectory] stringByAppendingPathComponent:@"search-process-state.plist"];
  NSMutableArray<NSTask *> *children = [NSMutableArray array];
  NSMutableArray<NSFileHandle *> *logs = [NSMutableArray array];
  @try {
    for (NSUInteger index = 0; index < 2; index++) {
      NSTask *child = [[NSTask alloc] init];
      child.launchPath = [[[NSProcessInfo processInfo] arguments] firstObject];
      NSString *bundle = [[NSBundle bundleForClass:[self class]] bundlePath];
#if defined(__APPLE__)
      child.arguments = @[@"-XCTest", @"Phase16DTests/testSearchStateTransactionsAcrossProcesses", bundle];
#else
      child.arguments = @[@"-only-testing:ArlenUnitTests/Phase16DTests/testSearchStateTransactionsAcrossProcesses", @"-output-format", @"apple", bundle];
#endif
      NSMutableDictionary *childEnvironment = [environment mutableCopy];
      childEnvironment[@"ARLEN_SEARCH_SHARED_STATE_PATH"] = path;
      childEnvironment[@"ARLEN_SEARCH_PROCESS_INDEX"] = [@(index) stringValue];
      child.environment = childEnvironment;
      NSString *logPath = [path stringByAppendingFormat:@".child-%lu.log", (unsigned long)index];
      [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
      NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logPath];
      [logs addObject:log];
      child.standardOutput = log; child.standardError = log;
      [child launch];
      [children addObject:child];
    }
    for (NSUInteger index = 0; index < 2; index++) {
      BOOL ready = ALNTestWaitCheckpoint(path, [NSString stringWithFormat:@"ready-%lu", (unsigned long)index]);
      XCTAssertTrue(ready, @"child %lu did not reach its fixture", (unsigned long)index);
      if (!ready) return;
    }
    XCTAssertTrue(ALNTestSignalCheckpoint(path, @"start-0"));
    BOOL firstReady = ALNTestWaitCheckpoint(path, @"building-0");
    XCTAssertTrue(firstReady);
    if (!firstReady) return;
    XCTAssertTrue(ALNTestSignalCheckpoint(path, @"start-1"));
    BOOL secondReady = ALNTestWaitCheckpoint(path, @"changed-1");
    XCTAssertTrue(secondReady);
    if (!secondReady) return;
    XCTAssertTrue(ALNTestSignalCheckpoint(path, @"resume-0"));
    for (NSUInteger index = 0; index < children.count; index++) {
      NSTask *child = children[index];
      BOOL exited = ALNTestWaitForTaskExit(child, 20.0);
      XCTAssertTrue(exited, @"child %lu did not exit", (unsigned long)index);
      if (!exited) return;
      XCTAssertEqual(0, child.terminationStatus);
      NSString *complete = [path stringByAppendingFormat:@".complete-%lu", (unsigned long)index];
      XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:complete]);
      NSString *logPath = [path stringByAppendingFormat:@".child-%lu.log", (unsigned long)index];
      NSString *output = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:NULL];
      XCTAssertTrue([output containsString:@"Executed 1 test"], @"%@", output);
    }
  } @finally {
    for (NSTask *child in children) XCTAssertTrue(ALNTestReapChild(child));
    for (NSFileHandle *log in logs) [log closeFile];
  }
  [self registerModulesForApplication:[self applicationWithStatePath:path]];
  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  NSDictionary *row = [self ordersRowFromDashboard:[runtime dashboardSummary]];
  XCTAssertEqualObjects(@2, row[@"activeGeneration"]);
  XCTAssertEqualObjects(@1, row[@"documentCount"]);
  NSError *error = nil;
  NSDictionary *fresh = [runtime searchQuery:@"replacement" resourceIdentifier:@"orders" filters:nil sort:nil limit:10 offset:0 error:&error];
  XCTAssertEqualObjects(@1, fresh[@"total"]);
  XCTAssertNil(error);
}

- (void)testIncrementalConflictDoesNotOverwriteConcurrentSameResourceChanges {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"state.plist"]];
  [self registerModulesForApplication:app];
  ALNSearchModuleRuntime *first = [ALNSearchModuleRuntime sharedRuntime];
  [self seedActiveIndexForRuntime:first];
  ALNSearchModuleRuntime *second = [[ALNSearchModuleRuntime alloc] init];
  NSError *error = nil;
  XCTAssertTrue([[ALNJobsModuleRuntime sharedRuntime] configureWithApplication:app error:&error]);
  XCTAssertTrue([second configureWithApplication:app error:&error], @"%@", error);
  gPhase16DApplyHook = ^{
    NSError *nested = nil;
    XCTAssertNotNil(([second applyIncrementalOperation:@"upsert" resourceIdentifier:@"orders"
        record:@{@"id":@"ord-102", @"order_number":@"replacement", @"status":@"new"} error:&nested]));
    XCTAssertNil(nested);
  };
  XCTAssertNil(([first applyIncrementalOperation:@"delete" resourceIdentifier:@"orders" record:@{@"id":@"ord-100"} error:&error]));
  XCTAssertEqualObjects(@"state_conflict", error.userInfo[@"reason"]);
  error = nil;
  XCTAssertNotNil(([first applyIncrementalOperation:@"delete" resourceIdentifier:@"orders" record:@{@"id":@"ord-100"} error:&error]));
  NSDictionary *query = [second searchQuery:@"replacement" resourceIdentifier:@"orders" filters:nil sort:nil limit:10 offset:0 error:&error];
  XCTAssertEqualObjects(@1, query[@"total"]);
  XCTAssertEqualObjects(@1, [self ordersRowFromDashboard:[second dashboardSummary]][@"documentCount"]);
  XCTAssertNil(error);
}

- (void)testReplayClaimsPreserveConcurrentEnqueueAndFenceStaleOwners {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"state.plist"]];
  [self registerModulesForApplication:app];
  ALNSearchModuleRuntime *first = [ALNSearchModuleRuntime sharedRuntime];
  [self seedActiveIndexForRuntime:first];
  ALNSearchModuleRuntime *second = [[ALNSearchModuleRuntime alloc] init];
  NSError *error = nil;
  XCTAssertTrue([[ALNJobsModuleRuntime sharedRuntime] configureWithApplication:app error:&error]);
  XCTAssertTrue([second configureWithApplication:app error:&error], @"%@", error);
  NSDictionary *payload = @{@"operation":@"upsert", @"record":@{@"id":@"replay-1", @"order_number":@"replayed"}};
  XCTAssertTrue(([first stateTransaction:^BOOL(NSError **transactionError) {
    [first enqueueReplayOperation:payload forResourceIdentifier:@"orders" metadata:@{}]; return YES;
  } write:YES error:&error]));
  gPhase16DApplyHook = ^{
    NSError *nested = nil;
    NSDictionary *busy = [second drainReplayOperationsForResourceIdentifier:@"orders" mode:@"test" error:&nested];
    XCTAssertEqualObjects(@0, busy[@"replayed"]);
    XCTAssertEqualObjects(@1, busy[@"remaining"]);
    XCTAssertTrue(([second stateTransaction:^BOOL(NSError **transactionError) {
      [second enqueueReplayOperation:@{@"operation":@"upsert", @"record":@{@"id":@"replay-2", @"order_number":@"another"}}
          forResourceIdentifier:@"orders" metadata:@{}]; return YES;
    } write:YES error:&nested]));
    XCTAssertNil(nested);
  };
  NSDictionary *drained = [first drainReplayOperationsForResourceIdentifier:@"orders" mode:@"test" error:&error];
  XCTAssertEqualObjects(@2, drained[@"replayed"]);
  XCTAssertEqualObjects(@0, drained[@"remaining"]);
  XCTAssertNil(error);
  XCTAssertTrue(([first stateTransaction:^BOOL(NSError **transactionError) {
    [first enqueueReplayOperation:@{@"operation":@"delete", @"record":@{@"id":@"ord-100"}}
        forResourceIdentifier:@"orders" metadata:@{}]; return YES;
  } write:YES error:&error]));
  gPhase16DApplyHook = ^{
    XCTAssertTrue(([second stateTransaction:^BOOL(NSError **transactionError) {
      NSMutableArray *queue = [second valueForKey:@"pendingReplayOperationsByResource"][@"orders"];
      NSMutableDictionary *claim = [queue[0] mutableCopy];
      claim[@"claimToken"] = @"replacement-owner";
      queue[0] = claim;
      return YES;
    } write:YES error:NULL]));
  };
  NSDictionary *fenced = [first drainReplayOperationsForResourceIdentifier:@"orders" mode:@"test" error:&error];
  XCTAssertEqualObjects(@0, fenced[@"replayed"]);
  XCTAssertEqualObjects(@1, fenced[@"remaining"]);
  XCTAssertEqualObjects(@"state_conflict", error.userInfo[@"reason"]);
  XCTAssertEqualObjects(@4, [self ordersRowFromDashboard:[second dashboardSummary]][@"documentCount"]);
  // Simulate a crashed claimant's expiry without a wall-clock sleep.
  XCTAssertTrue(([second stateTransaction:^BOOL(NSError **transactionError) {
    NSMutableArray *queue = [second valueForKey:@"pendingReplayOperationsByResource"][@"orders"];
    NSMutableDictionary *claim = [queue[0] mutableCopy]; claim[@"claimUntil"] = @0; queue[0] = claim; return YES;
  } write:YES error:NULL]));
  error = nil;
  NSDictionary *recovered = [second drainReplayOperationsForResourceIdentifier:@"orders" mode:@"test" error:&error];
  XCTAssertEqualObjects(@1, recovered[@"replayed"]);
  XCTAssertEqualObjects(@0, recovered[@"remaining"]);
  XCTAssertEqualObjects(@3, [self ordersRowFromDashboard:[first dashboardSummary]][@"documentCount"]);
  XCTAssertNil(error);
}

- (void)testWorkersWithDifferentResourcesPreserveEachOthersState {
  NSString *path = [[self temporaryDirectory] stringByAppendingPathComponent:@"state.plist"];
  ALNApplication *app = [self applicationWithStatePath:path];
  [self registerModulesForApplication:app];
  ALNSearchModuleRuntime *first = [ALNSearchModuleRuntime sharedRuntime];
  [self seedActiveIndexForRuntime:first];
  NSMutableDictionary *config = [app.config mutableCopy];
  NSMutableDictionary *search = [config[@"searchModule"] mutableCopy];
  search[@"providers"] = @{@"classes":@[@"Phase16DAlternateProvider"]};
  config[@"searchModule"] = search;
  ALNApplication *otherApp = [[ALNApplication alloc] initWithConfig:config];
  NSError *error = nil;
  XCTAssertTrue([[ALNJobsModuleRuntime sharedRuntime] configureWithApplication:otherApp error:&error]);
  ALNSearchModuleRuntime *second = [[ALNSearchModuleRuntime alloc] init];
  XCTAssertTrue([second configureWithApplication:otherApp error:&error]);
  XCTAssertEqualObjects(@0, [second resourceDrilldownForIdentifier:@"archive"][@"resource"][@"documentCount"]);
  XCTAssertNotNil(([second processReindexJobPayload:@{@"resource":@"archive", @"mode":@"full"} error:&error]));
  XCTAssertNotNil(([first applyIncrementalOperation:@"delete" resourceIdentifier:@"orders" record:@{@"id":@"ord-100"} error:&error]));
  XCTAssertEqualObjects(@2, [second resourceDrilldownForIdentifier:@"archive"][@"resource"][@"documentCount"]);
  XCTAssertEqualObjects(@1, [first resourceDrilldownForIdentifier:@"orders"][@"resource"][@"documentCount"]);
  XCTAssertNil(error);
}

@end
