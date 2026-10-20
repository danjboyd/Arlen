#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNWebTestSupport.h"
#import "../shared/Phase27SearchTestSupport.h"
#import "ALNAdminUIModule.h"
#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNJobsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSearchModule.h"

static NSString *Phase27SearchAdminHeaderValue(ALNContext *context, NSString *name) {
  NSDictionary *headers = [context.request.headers isKindOfClass:[NSDictionary class]] ? context.request.headers : @{};
  for (id key in [headers allKeys]) {
    if ([[[key description] lowercaseString] isEqualToString:name]) {
      return [[headers[key] description] lowercaseString];
    }
  }
  return @"";
}

// An app-owned admin-ui resource. `internal_note` is neither a list nor a
// detail field, so admin-ui never displays it.
@interface Phase27SearchAdminCaseFilesResource : NSObject <ALNAdminUIResource>
@end

@implementation Phase27SearchAdminCaseFilesResource

- (NSString *)adminUIResourceIdentifier {
  return @"casefiles";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Case Files",
    @"identifierField" : @"id",
    @"primaryField" : @"title",
    @"fields" : @[
      @{ @"name" : @"title", @"label" : @"Title", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"owner_email", @"label" : @"Owner", @"list" : @NO, @"detail" : @YES },
      @{ @"name" : @"status", @"label" : @"Status", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"internal_note", @"label" : @"Internal", @"list" : @NO, @"detail" : @NO },
    ],
    @"filters" : @[
      @{ @"name" : @"q", @"label" : @"Search", @"type" : @"search" },
      @{ @"name" : @"status", @"label" : @"Status", @"type" : @"select", @"choices" : @[ @"open", @"closed" ] },
    ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  (void)query;
  (void)limit;
  (void)offset;
  (void)error;
  return @[
    @{
      @"id" : @"case-1",
      @"title" : @"Alpha intake",
      @"owner_email" : @"owner-one@example.test",
      @"status" : @"open",
      @"internal_note" : @"zebracode",
    },
    @{
      @"id" : @"case-2",
      @"title" : @"Beta review",
      @"owner_email" : @"owner-two@example.test",
      @"status" : @"closed",
      @"internal_note" : @"zebracode",
    },
  ];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier error:(NSError **)error {
  (void)error;
  for (NSDictionary *record in [self adminUIListRecordsMatching:nil limit:10 offset:0 error:NULL]) {
    if ([record[@"id"] isEqual:identifier]) {
      return record;
    }
  }
  return nil;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  (void)parameters;
  return [self adminUIDetailRecordForIdentifier:identifier error:error];
}

- (BOOL)adminUIResourceAllowsOperation:(NSString *)operation
                            identifier:(NSString *)identifier
                               context:(ALNContext *)context
                                 error:(NSError **)error {
  (void)identifier;
  (void)error;
  if ([operation isEqualToString:@"list"] &&
      [Phase27SearchAdminHeaderValue(context, @"x-admin-list") isEqualToString:@"deny"]) {
    return NO;
  }
  return YES;
}

@end

@interface Phase27SearchAdminCaseFilesProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation Phase27SearchAdminCaseFilesProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase27SearchAdminCaseFilesResource alloc] init] ];
}

@end

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

- (void)resetAdminUIRuntime {
  ALNApplication *plain = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
  }];
  NSError *error = nil;
  XCTAssertTrue([[ALNAdminUIModuleRuntime sharedRuntime] configureWithApplication:plain error:&error]);
  XCTAssertNil(error);
}

- (NSDictionary *)JSONObjectFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id json = ALNTestJSONDictionaryFromResponse(response, &error);
  XCTAssertNil(error);
  return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (ALNResponse *)dispatchGET:(NSString *)path
                 queryString:(NSString *)queryString
                     headers:(NSDictionary *)headers
                 application:(ALNApplication *)app {
  NSMutableDictionary *allHeaders = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
  allHeaders[@"Accept"] = @"application/json";
  return [app dispatchRequest:ALNTestRequestWithMethod(@"GET", path, queryString ?: @"", allHeaders, nil)];
}

- (NSDictionary *)listedResource:(NSString *)identifier
                         headers:(NSDictionary *)headers
                     application:(ALNApplication *)app {
  ALNResponse *response = [self dispatchGET:@"/search/api/resources" queryString:@"" headers:headers application:app];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSDictionary *json = [self JSONObjectFromResponse:response];
  for (NSDictionary *resource in json[@"data"][@"resources"] ?: @[]) {
    if ([resource[@"identifier"] isEqual:identifier]) {
      return resource;
    }
  }
  return nil;
}

- (void)testAdminUIAutoResourcesAreGatedByAdminUIAccess {
  [self resetAdminUIRuntime];
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[] },
      @"worker" : @{ @"retryDelaySeconds" : @0 },
    },
    @"adminUI" : @{
      @"resourceProviders" : @{ @"classes" : @[ @"Phase27SearchAdminCaseFilesProvider" ] },
    },
    @"searchModule" : @{
      @"providers" : @{ @"classes" : @[ @"Phase27SearchRoleGatedProvider" ] },
      @"persistence" : @{ @"enabled" : @NO },
      @"adminUI" : @{ @"autoResources" : @YES },
    },
  }];
  [app addMiddleware:[[Phase27SearchContextMiddleware alloc] init]];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNAdminUIModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNSearchModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  [self seedIndexes];

  NSDictionary *metadata = [[ALNSearchModuleRuntime sharedRuntime] resourceMetadataForIdentifier:@"casefiles"];
  XCTAssertEqualObjects(@"role_gated", metadata[@"queryPolicy"]);
  XCTAssertEqualObjects(@[ @"admin" ], metadata[@"queryRoles"]);
  XCTAssertEqualObjects(@2, metadata[@"queryMinimumAuthAssuranceLevel"]);
  XCTAssertFalse([metadata[@"resultFields"] containsObject:@"internal_note"]);
  XCTAssertFalse([metadata[@"indexedFields"] containsObject:@"internal_note"]);

  NSDictionary *admin = @{ @"X-Search-User" : @"admin-user", @"X-Search-Roles" : @"admin" };
  NSArray<NSArray *> *deniedCallers = @[
    @[ @{}, @401 ],
    @[ @{ @"X-Search-User" : @"member-user", @"X-Search-Roles" : @"user" }, @403 ],
    @[ @{ @"X-Search-User" : @"operator-user", @"X-Search-Roles" : @"operator" }, @403 ],
    @[ @{ @"X-Search-User" : @"admin-user", @"X-Search-Roles" : @"admin", @"X-Search-AAL" : @"1" }, @403 ],
    @[ @{ @"X-Search-User" : @"admin-user", @"X-Search-Roles" : @"admin", @"X-Admin-List" : @"deny" }, @403 ],
  ];
  for (NSArray *entry in deniedCallers) {
    NSDictionary *headers = entry[0];
    NSString *label = [headers description];
    ALNResponse *scoped = [self dispatchGET:@"/search/api/resources/casefiles/query"
                                queryString:@"q=alpha"
                                    headers:headers
                                application:app];
    XCTAssertEqual([entry[1] integerValue], scoped.statusCode, @"%@", label);
    ALNResponse *unscoped = [self dispatchGET:@"/search/api/query" queryString:@"q=alpha" headers:headers application:app];
    XCTAssertEqual((NSInteger)200, unscoped.statusCode, @"%@", label);
    NSDictionary *unscopedJSON = [self JSONObjectFromResponse:unscoped];
    XCTAssertEqualObjects(@0, unscopedJSON[@"data"][@"total"], @"%@", label);
    XCTAssertNil([self listedResource:@"casefiles" headers:headers application:app], @"%@", label);
  }

  ALNResponse *allowed = [self dispatchGET:@"/search/api/resources/casefiles/query"
                               queryString:@"q=alpha"
                                   headers:admin
                               application:app];
  XCTAssertEqual((NSInteger)200, allowed.statusCode);
  NSDictionary *allowedJSON = [self JSONObjectFromResponse:allowed];
  NSArray *results = allowedJSON[@"data"][@"results"] ?: @[];
  XCTAssertEqual((NSUInteger)1, [results count]);
  NSDictionary *fields = [results firstObject][@"fields"] ?: @{};
  XCTAssertEqualObjects(@"Alpha intake", fields[@"title"]);
  XCTAssertEqualObjects(@"owner-one@example.test", fields[@"owner_email"]);
  XCTAssertNil(fields[@"internal_note"]);
  NSString *body = [[NSString alloc] initWithData:allowed.bodyData encoding:NSUTF8StringEncoding] ?: @"";
  XCTAssertFalse([body containsString:@"zebracode"]);

  ALNResponse *hidden = [self dispatchGET:@"/search/api/resources/casefiles/query"
                              queryString:@"q=zebracode"
                                  headers:admin
                              application:app];
  XCTAssertEqual((NSInteger)200, hidden.statusCode);
  XCTAssertEqualObjects(@0, [self JSONObjectFromResponse:hidden][@"data"][@"total"]);

  NSDictionary *listed = [self listedResource:@"casefiles" headers:admin application:app];
  XCTAssertNotNil(listed);
  XCTAssertEqualObjects(@"role_gated", listed[@"queryPolicy"]);

  [self resetAdminUIRuntime];
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
