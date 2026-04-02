#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNSearchModule.h"
#import "../shared/Phase27SearchTestSupport.h"

static NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *Phase27StreamingBuildBatches(void) {
  static NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *batches = nil;
  if (batches == nil) {
    batches = [NSMutableDictionary dictionary];
  }
  return batches;
}

static BOOL *Phase27StreamingLegacySnapshotFlag(void) {
  static BOOL legacySnapshotCalled = NO;
  return &legacySnapshotCalled;
}

static void Phase27ResetStreamingBuildCapture(void) {
  [Phase27StreamingBuildBatches() removeAllObjects];
  *Phase27StreamingLegacySnapshotFlag() = NO;
}

static NSDictionary *Phase27StreamingDocumentForRecord(NSDictionary *record, NSDictionary *metadata) {
  NSString *identifierField = [metadata[@"identifierField"] isKindOfClass:[NSString class]] ? metadata[@"identifierField"] : @"id";
  NSString *recordID = [record[identifierField] isKindOfClass:[NSString class]] ? record[identifierField] : @"";
  if ([recordID length] == 0 && [record[@"recordID"] isKindOfClass:[NSString class]]) {
    recordID = record[@"recordID"];
  }
  if ([recordID length] == 0) {
    return nil;
  }
  NSString *primaryField = [metadata[@"primaryField"] isKindOfClass:[NSString class]] ? metadata[@"primaryField"] : identifierField;
  NSString *summaryField = [metadata[@"summaryField"] isKindOfClass:[NSString class]] ? metadata[@"summaryField"] : @"";
  NSString *title = [record[primaryField] isKindOfClass:[NSString class]] ? record[primaryField] : recordID;
  NSString *summary = ([summaryField length] > 0 && [record[summaryField] isKindOfClass:[NSString class]]) ? record[summaryField] : @"";
  return @{
    @"resource" : metadata[@"identifier"] ?: @"",
    @"recordID" : recordID,
    @"title" : title ?: recordID,
    @"summary" : summary ?: @"",
    @"searchableText" : [NSString stringWithFormat:@"%@ %@", title ?: @"", summary ?: @""],
    @"autocompleteText" : title ?: recordID,
    @"fieldText" : @{},
    @"path" : @"",
    @"record" : [record isKindOfClass:[NSDictionary class]] ? record : @{},
  };
}

@interface Phase27StreamingCaptureSearchEngine : NSObject <ALNSearchEngine>
@end

@implementation Phase27StreamingCaptureSearchEngine

- (nullable NSDictionary *)searchModuleSnapshotForMetadata:(NSDictionary *)metadata
                                                   records:(NSArray<NSDictionary *> *)records
                                                generation:(NSUInteger)generation
                                                     error:(NSError **)error {
  *Phase27StreamingLegacySnapshotFlag() = YES;
  id state = [self searchModuleBeginBuildForMetadata:metadata generation:generation error:error];
  if (state == nil) {
    return nil;
  }
  if (![self searchModuleAppendBuildRecords:records metadata:metadata state:state error:error]) {
    return nil;
  }
  return [self searchModuleFinalizeBuildState:state metadata:metadata error:error];
}

- (nullable id)searchModuleBeginBuildForMetadata:(NSDictionary *)metadata
                                      generation:(NSUInteger)generation
                                           error:(NSError **)error {
  (void)metadata;
  (void)error;
  return [@{
    @"generation" : @(MAX((NSUInteger)1U, generation)),
    @"documents" : [NSMutableArray array],
  } mutableCopy];
}

- (BOOL)searchModuleAppendBuildRecords:(NSArray<NSDictionary *> *)records
                              metadata:(NSDictionary *)metadata
                                 state:(id)state
                                 error:(NSError **)error {
  (void)error;
  NSMutableDictionary *buildState = [state isKindOfClass:[NSMutableDictionary class]] ? (NSMutableDictionary *)state : nil;
  NSMutableArray *documents = [buildState[@"documents"] isKindOfClass:[NSMutableArray class]] ? buildState[@"documents"] : nil;
  if (documents == nil) {
    return NO;
  }
  NSString *identifier = [metadata[@"identifier"] isKindOfClass:[NSString class]] ? metadata[@"identifier"] : @"";
  NSMutableArray<NSNumber *> *batches = [Phase27StreamingBuildBatches()[identifier] isKindOfClass:[NSMutableArray class]]
                                            ? Phase27StreamingBuildBatches()[identifier]
                                            : [NSMutableArray array];
  [batches addObject:@([records count])];
  Phase27StreamingBuildBatches()[identifier] = batches;
  for (NSDictionary *record in [records isKindOfClass:[NSArray class]] ? records : @[]) {
    NSDictionary *document = Phase27StreamingDocumentForRecord(record, metadata);
    if (document != nil) {
      [documents addObject:document];
    }
  }
  return YES;
}

- (nullable NSDictionary *)searchModuleFinalizeBuildState:(id)state
                                                 metadata:(NSDictionary *)metadata
                                                    error:(NSError **)error {
  (void)metadata;
  (void)error;
  NSDictionary *buildState = [state isKindOfClass:[NSDictionary class]] ? (NSDictionary *)state : @{};
  NSArray *documents = [buildState[@"documents"] isKindOfClass:[NSArray class]] ? buildState[@"documents"] : @[];
  NSNumber *generation = [buildState[@"generation"] respondsToSelector:@selector(unsignedIntegerValue)] ? buildState[@"generation"] : @1;
  return @{
    @"generation" : generation ?: @1,
    @"builtAt" : @([[NSDate date] timeIntervalSince1970]),
    @"documentCount" : @([documents count]),
    @"documents" : documents ?: @[],
  };
}

- (nullable NSDictionary *)searchModuleApplyOperation:(NSString *)operation
                                               record:(NSDictionary *)record
                                             metadata:(NSDictionary *)metadata
                                      existingSnapshot:(NSDictionary *)snapshot
                                                error:(NSError **)error {
  (void)operation;
  (void)record;
  (void)metadata;
  (void)error;
  return snapshot ?: @{
    @"generation" : @1,
    @"documentCount" : @0,
    @"documents" : @[],
  };
}

- (nullable NSDictionary *)searchModuleExecuteQuery:(NSString *)query
                                     resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                  snapshotsByResource:(NSDictionary<NSString *, NSDictionary *> *)snapshotsByResource
                                              filters:(NSDictionary *)filters
                                                 sort:(NSString *)sort
                                                limit:(NSUInteger)limit
                                               offset:(NSUInteger)offset
                                                error:(NSError **)error {
  (void)query;
  (void)resourceMetadata;
  (void)snapshotsByResource;
  (void)filters;
  (void)sort;
  (void)limit;
  (void)offset;
  (void)error;
  return @{
    @"query" : @"",
    @"mode" : @"search",
    @"availableModes" : @[ @"search" ],
    @"results" : @[],
    @"matchedDocuments" : @[],
    @"autocomplete" : @[],
    @"suggestions" : @[],
    @"total" : @0,
    @"limit" : @(limit),
    @"offset" : @(offset),
  };
}

- (NSDictionary *)searchModuleCapabilities {
  return @{
    @"engine" : @"streaming-capture",
    @"supportsIncrementalSync" : @YES,
  };
}

@end

@interface Phase27SearchTests : XCTestCase
@end

@implementation Phase27SearchTests

- (void)setUp {
  [super setUp];
  Phase27SearchResetStores();
  Phase27ResetStreamingBuildCapture();
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

- (NSString *)repoRoot {
  return [[NSFileManager defaultManager] currentDirectoryPath];
}

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  NSString *path = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",
                                                               prefix ?: @"phase27",
                                                               [[NSUUID UUID] UUIDString]]];
  NSError *error = nil;
  BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&error];
  XCTAssertTrue(created, @"failed creating temp dir %@: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  return created ? path : nil;
}

- (BOOL)writeText:(NSString *)text toPath:(NSString *)path {
  NSError *error = nil;
  BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&error];
  XCTAssertTrue(created, @"failed creating directory for %@: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  if (!created) {
    return NO;
  }
  BOOL wrote = [(text ?: @"") writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
  XCTAssertTrue(wrote, @"failed writing %@: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  return wrote;
}

- (BOOL)writeJSONPayload:(NSDictionary *)payload toPath:(NSString *)path {
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:payload ?: @{} options:NSJSONWritingPrettyPrinted error:&error];
  XCTAssertNotNil(data, @"failed encoding JSON for %@: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  if (data == nil) {
    return NO;
  }
  BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&error];
  XCTAssertTrue(created, @"failed creating directory for %@: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  if (!created) {
    return NO;
  }
  BOOL wrote = [data writeToFile:path options:0 error:&error];
  XCTAssertTrue(wrote, @"failed writing JSON %@: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  return wrote;
}

- (NSDictionary *)JSONPayloadAtPath:(NSString *)path {
  NSData *data = [NSData dataWithContentsOfFile:path];
  XCTAssertNotNil(data, @"missing JSON artifact at %@", path);
  if (data == nil) {
    return nil;
  }
  NSError *error = nil;
  id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  XCTAssertNil(error, @"failed parsing JSON %@: %@", path, error.localizedDescription);
  XCTAssertTrue([payload isKindOfClass:[NSDictionary class]]);
  return [payload isKindOfClass:[NSDictionary class]] ? payload : nil;
}

- (NSDictionary *)runPhase27ConfidenceGeneratorWithOutputDir:(NSString *)outputDir
                                                   searchLog:(NSString *)searchLog
                                            characterization:(NSString *)characterization
                                            meiliManifest:(NSString *)meiliManifest
                                          opensearchManifest:(NSString *)opensearchManifest {
  NSString *script = [[self repoRoot] stringByAppendingPathComponent:@"tools/ci/generate_phase27_confidence_artifacts.py"];
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/usr/bin/env";
  task.arguments = @[
    @"python3",
    script,
    @"--output-dir",
    outputDir ?: @"",
    @"--search-log",
    searchLog ?: @"",
    @"--characterization",
    characterization ?: @"",
    @"--meilisearch-manifest",
    meiliManifest ?: @"",
    @"--opensearch-manifest",
    opensearchManifest ?: @"",
  ];
  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  task.standardOutput = stdoutPipe;
  task.standardError = stderrPipe;
  [task launch];
  [task waitUntilExit];

  NSString *stdoutText =
      [[NSString alloc] initWithData:[[stdoutPipe fileHandleForReading] readDataToEndOfFile]
                            encoding:NSUTF8StringEncoding] ?: @"";
  NSString *stderrText =
      [[NSString alloc] initWithData:[[stderrPipe fileHandleForReading] readDataToEndOfFile]
                            encoding:NSUTF8StringEncoding] ?: @"";
  return @{
    @"status" : @(task.terminationStatus),
    @"stdout" : stdoutText,
    @"stderr" : stderrText,
  };
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
  XCTAssertEqualObjects(@"sku", metadata[@"pagination"][@"cursorField"]);

  NSDictionary *tenantMetadata = [runtime resourceMetadataForIdentifier:@"tenant_orders"];
  XCTAssertEqualObjects(@"tenant_id", tenantMetadata[@"visibility"][@"tenantField"]);
  XCTAssertEqualObjects(@"deleted", tenantMetadata[@"visibility"][@"softDeleteField"]);
  XCTAssertEqualObjects(@"delete", tenantMetadata[@"syncPolicy"][@"softDeleteMode"]);
  XCTAssertEqualObjects(@2, tenantMetadata[@"syncPolicy"][@"bulkBatchSize"]);
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

  error = nil;
  XCTAssertNil([runtime searchQuery:@"priority"
                 resourceIdentifier:@"products"
                            filters:nil
                               sort:nil
                              limit:10
                             offset:0
                       queryOptions:@{ @"cursor" : @"not-supported" }
                              error:&error]);
  XCTAssertEqual(ALNSearchModuleErrorValidationFailed, error.code);
}

- (void)testReindexStreamsBuildBatchesInsteadOfUsingLegacySnapshotContract {
  ALNApplication *app = [self applicationWithConfig:@{
    @"engineClass" : @"Phase27StreamingCaptureSearchEngine",
  }
                                       database:nil];
  [self registerModulesForApplication:app];

  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  [self seedSearchIndexesForRuntime:runtime];

  NSDictionary *dashboard = [runtime dashboardSummary];
  NSDictionary *tenantOrders = [self resourceRowNamed:@"tenant_orders" fromDashboard:dashboard];
  XCTAssertEqualObjects(@3, tenantOrders[@"documentCount"]);
  XCTAssertEqualObjects((@[ @2, @1 ]), Phase27StreamingBuildBatches()[@"tenant_orders"]);
  XCTAssertFalse(*Phase27StreamingLegacySnapshotFlag());
}

- (void)testConfidenceArtifactsFailClosedWhenPostgresOrLiveValidationIsMissing {
  NSString *tempDir = [self createTempDirectoryWithPrefix:@"phase27-confidence-fail"];
  NSString *outputDir = [tempDir stringByAppendingPathComponent:@"out"];
  NSString *searchLog = [tempDir stringByAppendingPathComponent:@"phase27_search_tests.log"];
  NSString *characterization = [tempDir stringByAppendingPathComponent:@"search_characterization.json"];
  NSString *meiliManifest = [tempDir stringByAppendingPathComponent:@"live_meilisearch/manifest.json"];
  NSString *openManifest = [tempDir stringByAppendingPathComponent:@"live_opensearch/manifest.json"];
  NSDictionary *characterizationPayload = @{
    @"default" : @{ @"status" : @"pass", @"topResult" : @"sku-103" },
    @"postgres" : @{ @"status" : @"skipped", @"reason" : @"missing_ARLEN_PG_TEST_DSN" },
    @"meilisearch" : @{ @"status" : @"pass", @"topResult" : @"sku-103" },
    @"opensearch" : @{ @"status" : @"pass", @"topResult" : @"sku-103" },
  };
  NSDictionary *meiliPayload = @{ @"status" : @"pass", @"reason" : @"" };
  NSDictionary *openPayload = @{
    @"status" : @"fail",
    @"reason" : @"missing_ARLEN_PHASE27_OPENSEARCH_URL",
  };

  XCTAssertTrue([self writeText:@"Executed 12 tests, with 0 failures\n" toPath:searchLog]);
  XCTAssertTrue([self writeJSONPayload:characterizationPayload toPath:characterization]);
  XCTAssertTrue([self writeJSONPayload:meiliPayload toPath:meiliManifest]);
  XCTAssertTrue([self writeJSONPayload:openPayload toPath:openManifest]);

  NSDictionary *execution = [self runPhase27ConfidenceGeneratorWithOutputDir:outputDir
                                                                   searchLog:searchLog
                                                            characterization:characterization
                                                                meiliManifest:meiliManifest
                                                              opensearchManifest:openManifest];
  XCTAssertEqual(1, [execution[@"status"] intValue]);

  NSDictionary *eval = [self JSONPayloadAtPath:[outputDir stringByAppendingPathComponent:@"phase27_confidence_eval.json"]];
  XCTAssertEqualObjects(@"phase27-confidence-v2", eval[@"version"]);
  XCTAssertEqualObjects(@"fail", eval[@"status"]);
  XCTAssertEqualObjects(@"skipped", eval[@"lanes"][@"postgres_characterization"]);
  XCTAssertEqualObjects(@"fail", eval[@"lanes"][@"live_external_validation"]);
  XCTAssertEqualObjects(@"missing_ARLEN_PHASE27_OPENSEARCH_URL", eval[@"live_validation"][@"opensearch_reason"]);

  NSError *error = nil;
  NSString *markdown = [NSString stringWithContentsOfFile:[outputDir stringByAppendingPathComponent:@"phase27_confidence.md"]
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
  XCTAssertNotNil(markdown);
  XCTAssertNil(error);
  XCTAssertTrue([markdown containsString:@"Live external query/sync validation: `fail`"]);
  XCTAssertTrue([markdown containsString:@"ARLEN_PG_TEST_DSN"]);
}

- (void)testConfidenceArtifactsPassOnlyWhenEveryRequiredLanePasses {
  NSString *tempDir = [self createTempDirectoryWithPrefix:@"phase27-confidence-pass"];
  NSString *outputDir = [tempDir stringByAppendingPathComponent:@"out"];
  NSString *searchLog = [tempDir stringByAppendingPathComponent:@"phase27_search_tests.log"];
  NSString *characterization = [tempDir stringByAppendingPathComponent:@"search_characterization.json"];
  NSString *meiliManifest = [tempDir stringByAppendingPathComponent:@"live_meilisearch/manifest.json"];
  NSString *openManifest = [tempDir stringByAppendingPathComponent:@"live_opensearch/manifest.json"];
  NSDictionary *characterizationPayload = @{
    @"default" : @{ @"status" : @"pass", @"topResult" : @"sku-103" },
    @"postgres" : @{ @"status" : @"pass", @"topResult" : @"sku-102" },
    @"meilisearch" : @{ @"status" : @"pass", @"topResult" : @"sku-103" },
    @"opensearch" : @{ @"status" : @"pass", @"topResult" : @"sku-103" },
  };
  NSDictionary *livePayload = @{ @"status" : @"pass", @"reason" : @"" };

  XCTAssertTrue([self writeText:@"Test Suite 'All tests' passed\nExecuted 24 tests, with 0 failures\n" toPath:searchLog]);
  XCTAssertTrue([self writeJSONPayload:characterizationPayload toPath:characterization]);
  XCTAssertTrue([self writeJSONPayload:livePayload toPath:meiliManifest]);
  XCTAssertTrue([self writeJSONPayload:livePayload toPath:openManifest]);

  NSDictionary *execution = [self runPhase27ConfidenceGeneratorWithOutputDir:outputDir
                                                                   searchLog:searchLog
                                                            characterization:characterization
                                                                meiliManifest:meiliManifest
                                                              opensearchManifest:openManifest];
  XCTAssertEqual(0, [execution[@"status"] intValue]);

  NSDictionary *eval = [self JSONPayloadAtPath:[outputDir stringByAppendingPathComponent:@"phase27_confidence_eval.json"]];
  XCTAssertEqualObjects(@"pass", eval[@"status"]);
  XCTAssertEqualObjects(@"pass", eval[@"lanes"][@"postgres_characterization"]);
  XCTAssertEqualObjects(@"pass", eval[@"lanes"][@"live_external_validation"]);
  XCTAssertEqualObjects(@"pass", eval[@"live_validation"][@"overall"]);
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
