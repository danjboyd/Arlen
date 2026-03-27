#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNWebTestSupport.h"
#import "ALNAdminUIModule.h"
#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNJobsModule.h"
#import "ALNOpsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSearchModule.h"

static NSMutableDictionary<NSString *, NSMutableDictionary *> *Phase16IntegrationOrderStore(void) {
  static NSMutableDictionary<NSString *, NSMutableDictionary *> *store = nil;
  if (store == nil) {
    store = [NSMutableDictionary dictionary];
  }
  return store;
}

static void Phase16IntegrationResetOrderStore(void) {
  NSMutableDictionary *store = Phase16IntegrationOrderStore();
  [store removeAllObjects];
  store[@"ord-100"] = [@{
    @"id" : @"ord-100",
    @"order_number" : @"100",
    @"status" : @"reviewed",
    @"owner_email" : @"buyer-one@example.test",
    @"total_cents" : @1250,
    @"updated_at" : @"2026-03-01",
  } mutableCopy];
  store[@"ord-102"] = [@{
    @"id" : @"ord-102",
    @"order_number" : @"102",
    @"status" : @"pending",
    @"owner_email" : @"priority@example.test",
    @"total_cents" : @2400,
    @"updated_at" : @"2026-03-08",
  } mutableCopy];
}

@interface Phase16IntegrationAuthMiddleware : NSObject <ALNMiddleware>
@end

@implementation Phase16IntegrationAuthMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  context.stash[ALNContextAuthSubjectStashKey] = @"phase16-admin";
  context.stash[ALNContextAuthRolesStashKey] = @[ @"admin", @"operator" ];
  context.stash[ALNContextAuthClaimsStashKey] = @{
    @"sub" : @"phase16-admin",
    @"roles" : @[ @"admin", @"operator" ],
    @"aal" : @2,
    @"amr" : @[ @"otp" ],
    @"iat" : @((NSInteger)now),
    @"auth_time" : @((NSInteger)now),
  };
  return YES;
}

@end

@interface Phase16IntegrationOrdersResource : NSObject <ALNAdminUIResource>
@end

@implementation Phase16IntegrationOrdersResource

- (NSString *)adminUIResourceIdentifier {
  return @"orders";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Orders",
    @"singularLabel" : @"Order",
    @"summary" : @"Phase 16 integration fixture resource.",
    @"identifierField" : @"id",
    @"primaryField" : @"order_number",
    @"legacyPath" : @"orders-support",
    @"pageSize" : @1,
    @"pageSizes" : @[ @1, @2, @10 ],
    @"fields" : @[
      @{ @"name" : @"order_number", @"label" : @"Order", @"list" : @YES, @"detail" : @YES },
      @{
        @"name" : @"status",
        @"label" : @"Status",
        @"list" : @YES,
        @"detail" : @YES,
        @"editable" : @YES,
        @"choices" : @[ @"pending", @"reviewed" ],
        @"autocomplete" : @{ @"enabled" : @YES, @"minQueryLength" : @1 },
      },
      @{ @"name" : @"owner_email", @"label" : @"Owner", @"kind" : @"email", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"total_cents", @"label" : @"Total", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"updated_at", @"label" : @"Updated", @"kind" : @"date", @"detail" : @YES, @"list" : @NO },
    ],
    @"filters" : @[
      @{ @"name" : @"q", @"label" : @"Search", @"type" : @"search", @"placeholder" : @"order, owner, status" },
      @{ @"name" : @"status", @"label" : @"Status", @"type" : @"select", @"choices" : @[ @"pending", @"reviewed" ] },
      @{ @"name" : @"total_min", @"label" : @"Min total", @"type" : @"number", @"min" : @"0", @"step" : @"1" },
      @{ @"name" : @"updated_after", @"label" : @"Updated after", @"type" : @"date" },
    ],
    @"sorts" : @[
      @{ @"name" : @"updated_at", @"label" : @"Updated", @"default" : @YES, @"direction" : @"desc" },
      @{ @"name" : @"total_cents", @"label" : @"Total", @"direction" : @"desc" },
      @{ @"name" : @"order_number", @"label" : @"Order" },
    ],
    @"actions" : @[
      @{ @"name" : @"mark_reviewed", @"label" : @"Mark reviewed", @"scope" : @"row" },
    ],
    @"bulkActions" : @[
      @{ @"name" : @"mark_reviewed", @"label" : @"Mark reviewed", @"method" : @"POST" },
    ],
    @"exports" : @[ @"json", @"csv" ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  return [self adminUIListRecordsWithParameters:@{ @"q" : query ?: @"" } limit:limit offset:offset error:error];
}

- (NSArray<NSDictionary *> *)adminUIListRecordsWithParameters:(NSDictionary *)parameters
                                                        limit:(NSUInteger)limit
                                                       offset:(NSUInteger)offset
                                                        error:(NSError **)error {
  (void)error;
  NSString *search = [parameters[@"q"] isKindOfClass:[NSString class]] ? [parameters[@"q"] lowercaseString] : @"";
  NSString *status = [parameters[@"status"] isKindOfClass:[NSString class]] ? [parameters[@"status"] lowercaseString] : @"";
  NSInteger totalMin = [parameters[@"total_min"] respondsToSelector:@selector(integerValue)] ? [parameters[@"total_min"] integerValue] : 0;
  NSString *updatedAfter = [parameters[@"updated_after"] isKindOfClass:[NSString class]] ? parameters[@"updated_after"] : @"";
  NSString *sort = [parameters[@"sort"] isKindOfClass:[NSString class]] ? [parameters[@"sort"] lowercaseString] : @"";

  NSMutableArray *records = [NSMutableArray array];
  for (NSString *key in [[Phase16IntegrationOrderStore() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    NSDictionary *record = [Phase16IntegrationOrderStore()[key] copy];
    NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@",
                                                     record[@"order_number"] ?: @"",
                                                     record[@"status"] ?: @"",
                                                     record[@"owner_email"] ?: @""]
        lowercaseString];
    if ([search length] > 0 && [haystack rangeOfString:search].location == NSNotFound) {
      continue;
    }
    if ([status length] > 0 && ![[record[@"status"] lowercaseString] isEqualToString:status]) {
      continue;
    }
    if ([record[@"total_cents"] integerValue] < totalMin) {
      continue;
    }
    if ([updatedAfter length] > 0 &&
        [[record[@"updated_at"] description] compare:updatedAfter options:NSNumericSearch] == NSOrderedAscending) {
      continue;
    }
    [records addObject:record];
  }

  BOOL descending = [sort hasPrefix:@"-"] || [sort length] == 0;
  NSString *sortField = ([sort hasPrefix:@"-"] ? [sort substringFromIndex:1] : sort);
  if ([sortField length] == 0) {
    sortField = @"updated_at";
  }
  [records sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    NSString *left = [[lhs[sortField] description] lowercaseString];
    NSString *right = [[rhs[sortField] description] lowercaseString];
    NSComparisonResult result = [left compare:right options:NSNumericSearch];
    if (result == NSOrderedSame) {
      result = [[[lhs[@"order_number"] description] lowercaseString] compare:[[rhs[@"order_number"] description] lowercaseString]];
    }
    return descending ? -result : result;
  }];

  NSUInteger start = MIN(offset, [records count]);
  NSUInteger length = MIN(limit, ([records count] - start));
  return [records subarrayWithRange:NSMakeRange(start, length)];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  NSDictionary *record = [Phase16IntegrationOrderStore()[identifier ?: @""] copy];
  if (record == nil && error != NULL) {
    *error = [NSError errorWithDomain:@"Phase16Integration"
                                 code:404
                             userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
  }
  return record;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  NSMutableDictionary *record = Phase16IntegrationOrderStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase16Integration"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  NSString *status = [parameters[@"status"] isKindOfClass:[NSString class]] ? parameters[@"status"] : @"";
  if ([status length] > 0) {
    record[@"status"] = status;
  }
  return [record copy];
}

- (NSDictionary *)adminUIPerformActionNamed:(NSString *)actionName
                                  identifier:(NSString *)identifier
                                  parameters:(NSDictionary *)parameters
                                       error:(NSError **)error {
  (void)parameters;
  if (![[actionName lowercaseString] isEqualToString:@"mark_reviewed"]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase16Integration"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Unknown action" }];
    }
    return nil;
  }
  NSMutableDictionary *record = Phase16IntegrationOrderStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase16Integration"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  record[@"status"] = @"reviewed";
  return @{
    @"message" : @"Order marked reviewed.",
    @"record" : [record copy],
  };
}

- (NSDictionary *)adminUIPerformBulkActionNamed:(NSString *)actionName
                                      identifiers:(NSArray<NSString *> *)identifiers
                                       parameters:(NSDictionary *)parameters
                                            error:(NSError **)error {
  (void)parameters;
  if (![[actionName lowercaseString] isEqualToString:@"mark_reviewed"]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase16Integration"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Unknown action" }];
    }
    return nil;
  }
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *identifier in identifiers) {
    NSMutableDictionary *record = Phase16IntegrationOrderStore()[identifier];
    if (record == nil) {
      continue;
    }
    record[@"status"] = @"reviewed";
    [records addObject:[record copy]];
  }
  return @{
    @"count" : @([records count]),
    @"records" : records,
    @"message" : @"Orders marked reviewed.",
  };
}

- (NSArray<NSDictionary *> *)adminUIAutocompleteSuggestionsForFieldNamed:(NSString *)fieldName
                                                                    query:(NSString *)query
                                                                    limit:(NSUInteger)limit
                                                                    error:(NSError **)error {
  (void)error;
  if (![[fieldName lowercaseString] isEqualToString:@"status"]) {
    return @[];
  }
  NSString *needle = [query isKindOfClass:[NSString class]] ? [query lowercaseString] : @"";
  NSMutableArray *matches = [NSMutableArray array];
  for (NSString *value in @[ @"pending", @"reviewed" ]) {
    if ([needle length] > 0 && [[value lowercaseString] rangeOfString:needle].location == NSNotFound) {
      continue;
    }
    [matches addObject:@{ @"value" : value, @"label" : [value capitalizedString] }];
    if ([matches count] >= MAX((NSUInteger)1U, limit)) {
      break;
    }
  }
  return matches;
}

@end

@interface Phase16IntegrationOrdersProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation Phase16IntegrationOrdersProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16IntegrationOrdersResource alloc] init] ];
}

@end

@interface Phase16IntegrationOpsCardProvider : NSObject <ALNOpsCardProvider>
@end

@implementation Phase16IntegrationOpsCardProvider

- (NSArray<NSDictionary *> *)opsModuleCardsForRuntime:(ALNOpsModuleRuntime *)runtime
                                                 error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    @{
      @"label" : @"Review Queue",
      @"value" : @"1",
      @"status" : @"healthy",
      @"summary" : @"orders pending review",
    },
  ];
}

- (NSArray<NSDictionary *> *)opsModuleWidgetsForRuntime:(ALNOpsModuleRuntime *)runtime
                                                   error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    @{
      @"title" : @"Operator Note",
      @"body" : @"Phase 16 widget seam active",
      @"status" : @"informational",
    },
  ];
}

@end

@interface Phase16ModuleIntegrationTests : XCTestCase
@end

@implementation Phase16ModuleIntegrationTests

- (void)setUp {
  [super setUp];
  Phase16IntegrationResetOrderStore();
}

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[] },
      @"worker" : @{ @"retryDelaySeconds" : @0 },
    },
    @"adminUI" : @{
      @"resourceProviders" : @{ @"classes" : @[ @"Phase16IntegrationOrdersProvider" ] },
    },
    @"opsModule" : @{
      @"cardProviders" : @{ @"classes" : @[ @"Phase16IntegrationOpsCardProvider" ] },
    },
    @"searchModule" : @{
      @"adminUI" : @{
        @"autoResources" : @YES,
        @"resourceProviderClass" : @"ALNSearchAdminResourceProvider",
      },
    },
  }];
}

- (void)registerModulesForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNAdminUIModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNSearchModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNOpsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                      queryString:(NSString *)queryString
                          headers:(NSDictionary *)headers
                             body:(NSData *)body {
  return ALNTestRequestWithMethod(method, path, queryString, headers, body);
}

- (NSData *)JSONBody:(NSDictionary *)payload {
  return [NSJSONSerialization dataWithJSONObject:payload ?: @{} options:0 error:NULL] ?: [NSData data];
}

- (NSDictionary *)JSONObjectFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id json = ALNTestJSONDictionaryFromResponse(response, &error);
  XCTAssertNil(error);
  XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
  return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (NSString *)stringFromResponse:(ALNResponse *)response {
  return ALNTestStringFromResponse(response);
}

- (void)testWebHarnessExposesRegisteredModulesRoutesAndMiddleware {
  ALNApplication *app = [self application];
  [app addMiddleware:[[Phase16IntegrationAuthMiddleware alloc] init]];
  [self registerModulesForApplication:app];

  ALNWebTestHarness *harness = [ALNWebTestHarness harnessWithApplication:app];
  XCTAssertTrue([[harness middlewares] count] > 0);
  BOOL foundAuthMiddleware = NO;
  for (id middleware in [harness middlewares]) {
    if ([middleware isKindOfClass:[Phase16IntegrationAuthMiddleware class]]) {
      foundAuthMiddleware = YES;
      break;
    }
  }
  XCTAssertTrue(foundAuthMiddleware);
  XCTAssertNotNil([harness routeNamed:@"jobs_api_run_worker"]);
  XCTAssertNotNil([harness routeNamed:@"search_api_resource_query"]);
  XCTAssertNotNil([harness routeNamed:@"ops_dashboard"]);
  XCTAssertTrue([[harness routeTable] count] > 0);
  XCTAssertEqualObjects(@"test", harness.application.environment);
}

- (void)testPhase16AdminSearchAndOpsRoutesExposeMaturedContracts {
  ALNApplication *app = [self application];
  [app addMiddleware:[[Phase16IntegrationAuthMiddleware alloc] init]];
  [self registerModulesForApplication:app];

  ALNResponse *queueResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/search/api/resources/orders/reindex"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, queueResponse.statusCode);
  NSDictionary *queueJSON = [self JSONObjectFromResponse:queueResponse];
  XCTAssertEqualObjects(@"orders", queueJSON[@"data"][@"resource"]);

  ALNResponse *workerResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/jobs/api/run-worker"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, workerResponse.statusCode);

  ALNResponse *queryResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/orders/query"
                                       queryString:@"q=priority"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, queryResponse.statusCode);
  NSDictionary *queryJSON = [self JSONObjectFromResponse:queryResponse];
  NSArray *results = [queryJSON[@"data"][@"results"] isKindOfClass:[NSArray class]] ? queryJSON[@"data"][@"results"] : @[];
  XCTAssertEqual((NSUInteger)1, [results count]);
  XCTAssertEqualObjects(@"ord-102", results[0][@"recordID"]);
  XCTAssertEqual((NSUInteger)1, [results[0][@"highlights"] count]);

  ALNResponse *invalidFilterResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/orders/query"
                                       queryString:@"filter.unknown=bad"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)422, invalidFilterResponse.statusCode);

  ALNResponse *invalidSortResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/orders/query"
                                       queryString:@"sort=-missing"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)422, invalidSortResponse.statusCode);

  ALNResponse *bulkActionResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/admin/api/resources/orders/bulk-actions/mark_reviewed"
                                       queryString:@""
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"Content-Type" : @"application/json",
                                           }
                                              body:[self JSONBody:@{ @"identifiers" : @[ @"ord-102" ] }]]];
  XCTAssertEqual((NSInteger)200, bulkActionResponse.statusCode);
  NSDictionary *bulkActionJSON = [self JSONObjectFromResponse:bulkActionResponse];
  XCTAssertEqualObjects(@"ok", bulkActionJSON[@"status"]);
  XCTAssertEqualObjects(@1, bulkActionJSON[@"result"][@"count"]);

  workerResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/jobs/api/run-worker"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, workerResponse.statusCode);

  queryResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/orders/query"
                                       queryString:@"filter.status=reviewed&sort=-total_cents"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, queryResponse.statusCode);
  queryJSON = [self JSONObjectFromResponse:queryResponse];
  results = [queryJSON[@"data"][@"results"] isKindOfClass:[NSArray class]] ? queryJSON[@"data"][@"results"] : @[];
  XCTAssertEqual((NSUInteger)2, [results count]);
  XCTAssertEqualObjects(@"ord-102", results[0][@"recordID"]);

  ALNResponse *drilldownResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/orders"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, drilldownResponse.statusCode);
  NSDictionary *drilldownJSON = [self JSONObjectFromResponse:drilldownResponse];
  XCTAssertEqualObjects(@"orders", drilldownJSON[@"data"][@"resource"][@"identifier"]);
  XCTAssertTrue([(NSArray *)(drilldownJSON[@"data"][@"history"] ?: @[]) count] > 0);

  ALNResponse *exportResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/admin/api/resources/orders/export/csv"
                                       queryString:@"status=reviewed"
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, exportResponse.statusCode);
  XCTAssertTrue([exportResponse.headers[@"content-type"] containsString:@"text/csv"]);
  NSString *csv = [self stringFromResponse:exportResponse];
  XCTAssertTrue([csv containsString:@"Order,Status,Owner,Total"]);
  XCTAssertTrue([csv containsString:@"102"]);

  ALNResponse *autocompleteResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/admin/api/resources/orders/autocomplete/status"
                                       queryString:@"q=re"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, autocompleteResponse.statusCode);
  NSDictionary *autocompleteJSON = [self JSONObjectFromResponse:autocompleteResponse];
  XCTAssertEqualObjects(@"ok", autocompleteJSON[@"status"]);
  XCTAssertEqualObjects(@"reviewed", autocompleteJSON[@"suggestions"][0][@"value"]);

  ALNResponse *adminListHTML =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/admin/resources/orders"
                                       queryString:@"status=reviewed&limit=1&updated_after=2026-03-01"
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, adminListHTML.statusCode);
  NSString *adminListString = [self stringFromResponse:adminListHTML];
  XCTAssertTrue([adminListString containsString:@"Export CSV"]);
  XCTAssertTrue([adminListString containsString:@"Mark reviewed"]);
  XCTAssertTrue([adminListString containsString:@"type=\"date\""]);
  XCTAssertTrue([adminListString containsString:@"Page 1"]);

  ALNResponse *adminDetailHTML =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/admin/resources/orders/ord-100"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, adminDetailHTML.statusCode);
  NSString *adminDetailString = [self stringFromResponse:adminDetailHTML];
  XCTAssertTrue([adminDetailString containsString:@"data-autocomplete-path=\"/admin/api/resources/orders/autocomplete/status\""]);

  ALNResponse *opsSummaryResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/ops/api/summary"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, opsSummaryResponse.statusCode);
  NSDictionary *opsSummaryJSON = [self JSONObjectFromResponse:opsSummaryResponse];
  NSDictionary *opsSummary = opsSummaryJSON[@"data"];
  NSArray *widgets = [opsSummary[@"widgets"] isKindOfClass:[NSArray class]] ? opsSummary[@"widgets"] : @[];
  XCTAssertEqual((NSUInteger)1, [widgets count]);
  XCTAssertEqualObjects(@"Operator Note", widgets[0][@"title"]);
  XCTAssertTrue([(NSArray *)(opsSummary[@"history"] ?: @[]) count] > 0);

  ALNResponse *opsDrilldownResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/ops/api/modules/search"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, opsDrilldownResponse.statusCode);
  NSDictionary *opsDrilldownJSON = [self JSONObjectFromResponse:opsDrilldownResponse];
  XCTAssertEqualObjects(@"search", opsDrilldownJSON[@"data"][@"identifier"]);
  XCTAssertTrue([(NSArray *)(opsDrilldownJSON[@"data"][@"history"] ?: @[]) count] > 0);

  ALNResponse *opsHTML =
      [app dispatchRequest:[self requestWithMethod:@"GET" path:@"/ops" queryString:@"" headers:@{} body:nil]];
  XCTAssertEqual((NSInteger)200, opsHTML.statusCode);
  XCTAssertTrue([[self stringFromResponse:opsHTML] containsString:@"Operator Note"]);
}

- (void)testAdminLegacyPathsKeepHTMLAndAPIActionParity {
  ALNApplication *app = [self application];
  [app addMiddleware:[[Phase16IntegrationAuthMiddleware alloc] init]];
  [self registerModulesForApplication:app];

  NSDictionary *resource = [[ALNAdminUIModuleRuntime sharedRuntime] resourceMetadataForIdentifier:@"orders"];
  XCTAssertEqualObjects(@"/admin/orders-support", resource[@"paths"][@"html_index"]);
  XCTAssertEqualObjects(@"/admin/resources/orders", resource[@"paths"][@"html_index_generic"]);
  XCTAssertEqualObjects(@"/admin/api/orders-support", resource[@"paths"][@"legacy_api_items"]);

  ALNResponse *legacyList =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/admin/orders-support"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, legacyList.statusCode);
  NSString *legacyListHTML = [self stringFromResponse:legacyList];
  XCTAssertTrue([legacyListHTML containsString:@"Orders"]);
  XCTAssertTrue([legacyListHTML containsString:@"action=\"/admin/orders-support/export/csv\""]);

  ALNResponse *legacyDetail =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/admin/orders-support/ord-100"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, legacyDetail.statusCode);
  NSString *legacyDetailHTML = [self stringFromResponse:legacyDetail];
  XCTAssertTrue([legacyDetailHTML containsString:@"action=\"/admin/orders-support/ord-100/actions/mark_reviewed\""]);
  XCTAssertTrue([legacyDetailHTML containsString:@"action=\"/admin/orders-support/ord-100\""]);

  ALNResponse *legacyAction =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/admin/orders-support/ord-100/actions/mark_reviewed"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, legacyAction.statusCode);
  NSString *legacyActionHTML = [self stringFromResponse:legacyAction];
  XCTAssertTrue([legacyActionHTML containsString:@"Order marked reviewed."]);
  XCTAssertTrue([legacyActionHTML containsString:@"reviewed"]);

  ALNResponse *legacyUpdate =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/admin/orders-support/ord-102"
                                       queryString:@""
                                           headers:@{ @"Content-Type" : @"application/json" }
                                              body:[self JSONBody:@{ @"status" : @"pending" }]]];
  XCTAssertEqual((NSInteger)302, legacyUpdate.statusCode);
  XCTAssertEqualObjects(@"/admin/orders-support/ord-102", legacyUpdate.headers[@"location"]);

  ALNResponse *legacyAPIAction =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/admin/api/orders-support/ord-102/actions/mark_reviewed"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, legacyAPIAction.statusCode);
  NSDictionary *legacyAPIActionJSON = [self JSONObjectFromResponse:legacyAPIAction];
  XCTAssertEqualObjects(@"reviewed", legacyAPIActionJSON[@"result"][@"record"][@"status"]);

  ALNResponse *legacyAPIList =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/admin/api/orders-support"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, legacyAPIList.statusCode);
  NSDictionary *legacyAPIListJSON = [self JSONObjectFromResponse:legacyAPIList];
  XCTAssertEqualObjects(@"ok", legacyAPIListJSON[@"status"]);
  XCTAssertEqual((NSUInteger)1, [legacyAPIListJSON[@"items"] count]);
  XCTAssertEqualObjects(@1, legacyAPIListJSON[@"pagination"][@"limit"]);
}

@end
