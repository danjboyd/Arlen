#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNWebTestSupport.h"
#import "../shared/Phase27SearchTestSupport.h"
#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNEOCRuntime.h"
#import "ALNSearchModule.h"
#import "ALNView.h"

@interface Phase27SearchControllerTests : XCTestCase
@end

@implementation Phase27SearchControllerTests

- (void)setUp {
  [super setUp];
  Phase27SearchResetStores();
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
    @"searchModule" : @{
      @"providers" : @{ @"classes" : @[ @"Phase27SearchProvider" ] },
      @"persistence" : @{ @"enabled" : @NO },
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

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                      queryString:(NSString *)queryString
                          headers:(NSDictionary *)headers
                             body:(NSData *)body {
  return ALNTestRequestWithMethod(method, path, queryString, headers, body);
}

- (NSDictionary *)JSONObjectFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id json = ALNTestJSONDictionaryFromResponse(response, &error);
  XCTAssertNil(error);
  XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
  return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (NSArray<NSString *> *)resourceIdentifiersFromResourcePayload:(NSArray *)resources {
  NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
  for (NSDictionary *resource in [resources isKindOfClass:[NSArray class]] ? resources : @[]) {
    if ([resource[@"identifier"] isKindOfClass:[NSString class]]) {
      [identifiers addObject:resource[@"identifier"]];
    }
  }
  return identifiers;
}

- (NSDictionary *)apiResourcePayloadForApplication:(ALNApplication *)app headers:(NSDictionary *)headers {
  ALNResponse *response =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources"
                                       queryString:@""
                                           headers:headers ?: @{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSDictionary *json = [self JSONObjectFromResponse:response];
  return [json[@"data"] isKindOfClass:[NSDictionary class]] ? json[@"data"] : @{};
}

- (NSString *)renderedSearchDashboardForApplication:(ALNApplication *)app
                                            headers:(NSDictionary *)headers
                                              error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  NSDictionary *resourcePayload = [self apiResourcePayloadForApplication:app headers:headers];
  NSArray *resources = [resourcePayload[@"resources"] isKindOfClass:[NSArray class]] ? resourcePayload[@"resources"] : @[];
  NSArray *visibleIdentifiers = [self resourceIdentifiersFromResourcePayload:resources];
  NSDictionary *summary = [[ALNSearchModuleRuntime sharedRuntime] dashboardSummary] ?: @{};
  NSMutableArray *visibleRows = [NSMutableArray array];
  NSSet *identifierSet = [NSSet setWithArray:visibleIdentifiers ?: @[]];
  for (NSDictionary *row in [summary[@"resources"] isKindOfClass:[NSArray class]] ? summary[@"resources"] : @[]) {
    NSString *identifier = [row[@"identifier"] isKindOfClass:[NSString class]] ? row[@"identifier"] : @"";
    if ([identifierSet containsObject:identifier]) {
      [visibleRows addObject:row];
    }
  }
  NSMutableDictionary *visibleSummary = [NSMutableDictionary dictionaryWithDictionary:summary];
  visibleSummary[@"resources"] = visibleRows ?: @[];
  NSArray *roles = @[];
  NSString *rolesHeader = [headers isKindOfClass:[NSDictionary class]] ? headers[@"X-Search-Roles"] : nil;
  if ([rolesHeader isKindOfClass:[NSString class]] && [rolesHeader length] > 0) {
    roles = [[rolesHeader lowercaseString] componentsSeparatedByString:@","];
  }
  BOOL adminAllowed = [roles containsObject:@"admin"] || [roles containsObject:@"operator"];
  NSDictionary *context = @{
    @"pageTitle" : @"Search",
    @"pageHeading" : @"Search",
    @"message" : @"",
    @"errors" : @[],
    @"searchPrefix" : [ALNSearchModuleRuntime sharedRuntime].prefix ?: @"/search",
    @"searchAPIPrefix" : [ALNSearchModuleRuntime sharedRuntime].apiPrefix ?: @"/search/api",
    @"authLoginPath" : @"/auth/login",
    @"authLogoutPath" : @"/auth/logout",
    @"csrfToken" : @"",
    @"searchSummary" : visibleSummary ?: @{},
    @"searchResources" : resources ?: @[],
    @"searchAdminAllowed" : @(adminAllowed),
    @"query" : @"",
    @"parameters" : @{},
    @"searchResult" : @{ @"results" : @[], @"total" : @0 },
    @"activeResource" : @"",
    @"activeResourceMetadata" : @{},
    @"searchDrilldown" : @{},
  };
  return [ALNView renderTemplate:@"modules/search/dashboard/index"
                         context:context
                          layout:@"modules/search/layouts/main"
                           error:error];
}

- (void)seedSearchIndexesForApplication:(ALNApplication *)app {
  (void)app;
  NSError *error = nil;
  NSDictionary *queued = [[ALNSearchModuleRuntime sharedRuntime] queueReindexForResourceIdentifier:nil error:&error];
  XCTAssertNotNil(queued);
  XCTAssertNil(error);
  NSDictionary *worker = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:20 error:&error];
  XCTAssertNotNil(worker);
  XCTAssertNil(error);
}

- (void)testResourceListingFiltersByQueryPolicy {
  ALNApplication *app = [self application];
  [app addMiddleware:[[Phase27SearchContextMiddleware alloc] init]];
  [self registerModulesForApplication:app];
  [self seedSearchIndexesForApplication:app];

  ALNResponse *publicResources =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, publicResources.statusCode);
  NSDictionary *publicJSON = [self JSONObjectFromResponse:publicResources];
  NSArray *publicIdentifiers = [self resourceIdentifiersFromResourcePayload:publicJSON[@"data"][@"resources"]];
  XCTAssertEqualObjects((@[ @"products" ]), publicIdentifiers);
  XCTAssertEqualObjects(@"ALNDefaultSearchEngine", publicJSON[@"data"][@"engine"]);
  XCTAssertTrue([publicJSON[@"data"][@"engineCapabilities"][@"supportsPromotedResults"] boolValue]);

  ALNResponse *authenticatedResources =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources"
                                       queryString:@""
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"X-Search-User" : @"member-user",
                                           }
                                              body:nil]];
  NSDictionary *authenticatedJSON = [self JSONObjectFromResponse:authenticatedResources];
  NSArray *authenticatedIdentifiers = [self resourceIdentifiersFromResourcePayload:authenticatedJSON[@"data"][@"resources"]];
  XCTAssertTrue([authenticatedIdentifiers containsObject:@"products"]);
  XCTAssertTrue([authenticatedIdentifiers containsObject:@"members"]);
  XCTAssertFalse([authenticatedIdentifiers containsObject:@"finance"]);
  XCTAssertFalse([authenticatedIdentifiers containsObject:@"regional_docs"]);

  ALNResponse *fullResources =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources"
                                       queryString:@""
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"X-Search-User" : @"auditor-user",
                                             @"X-Search-Roles" : @"auditor",
                                             @"X-Search-Predicate" : @"allow",
                                           }
                                              body:nil]];
  NSDictionary *fullJSON = [self JSONObjectFromResponse:fullResources];
  NSArray *fullIdentifiers = [self resourceIdentifiersFromResourcePayload:fullJSON[@"data"][@"resources"]];
  XCTAssertTrue([fullIdentifiers containsObject:@"finance"]);
  XCTAssertTrue([fullIdentifiers containsObject:@"regional_docs"]);
}

- (void)testPublicQueryEnvelopeIsShapedAndPolicyRoutesFailClosed {
  ALNApplication *app = [self application];
  [app addMiddleware:[[Phase27SearchContextMiddleware alloc] init]];
  [self registerModulesForApplication:app];
  [self seedSearchIndexesForApplication:app];

  ALNResponse *productsQuery =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/products/query"
                                       queryString:@"q=priority&mode=search"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, productsQuery.statusCode);
  NSDictionary *productsJSON = [self JSONObjectFromResponse:productsQuery];
  NSDictionary *payload = productsJSON[@"data"];
  XCTAssertEqualObjects(@"products", payload[@"resource"]);
  XCTAssertEqualObjects(@"search", payload[@"mode"]);
  XCTAssertEqualObjects(@"Products", payload[@"resourceMetadata"][@"label"]);
  XCTAssertTrue([(NSArray *)(payload[@"promotedResults"] ?: @[]) count] > 0);
  XCTAssertTrue([(NSArray *)(payload[@"facets"] ?: @[]) count] > 0);
  NSArray *results = [payload[@"results"] isKindOfClass:[NSArray class]] ? payload[@"results"] : @[];
  XCTAssertEqualObjects(@"sku-103", results[0][@"recordID"]);
  XCTAssertNil(results[0][@"record"]);
  XCTAssertNil(results[0][@"fieldText"]);
  XCTAssertEqualObjects(@"priority", results[0][@"fields"][@"category"]);
  XCTAssertNil(results[0][@"fields"][@"internal_cost"]);

  ALNResponse *membersUnauthorized =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/members/query"
                                       queryString:@"q=alice"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)401, membersUnauthorized.statusCode);

  ALNResponse *membersAuthorized =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/members/query"
                                       queryString:@"q=alice"
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"X-Search-User" : @"member-user",
                                           }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, membersAuthorized.statusCode);

  ALNResponse *financeForbidden =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/finance/query"
                                       queryString:@"q=forecast"
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"X-Search-User" : @"member-user",
                                           }
                                              body:nil]];
  XCTAssertEqual((NSInteger)403, financeForbidden.statusCode);

  ALNResponse *financeAuthorized =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/finance/query"
                                       queryString:@"q=forecast"
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"X-Search-User" : @"auditor-user",
                                             @"X-Search-Roles" : @"auditor",
                                           }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, financeAuthorized.statusCode);

  ALNResponse *predicateForbidden =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/regional_docs/query"
                                       queryString:@"q=central"
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"X-Search-User" : @"member-user",
                                           }
                                              body:nil]];
  XCTAssertEqual((NSInteger)403, predicateForbidden.statusCode);

  ALNResponse *predicateAllowed =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/regional_docs/query"
                                       queryString:@"q=central"
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"X-Search-User" : @"member-user",
                                             @"X-Search-Predicate" : @"allow",
                                           }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, predicateAllowed.statusCode);
}

- (void)testSearchHTMLOnlyListsVisibleResourcesForCurrentContext {
  ALNEOCClearTemplateRegistry();
  ALNApplication *app = [self application];
  [app addMiddleware:[[Phase27SearchContextMiddleware alloc] init]];
  [self registerModulesForApplication:app];
  [self seedSearchIndexesForApplication:app];

  NSError *publicRenderError = nil;
  NSString *publicRendered = [self renderedSearchDashboardForApplication:app
                                                                 headers:@{ @"Accept" : @"application/json" }
                                                                   error:&publicRenderError];
  XCTAssertNotNil(publicRendered, @"public dashboard render failed: %@", publicRenderError);
  XCTAssertNil(publicRenderError, @"public dashboard render failed: %@", publicRenderError);

  ALNResponse *publicHTML =
      [app dispatchRequest:[self requestWithMethod:@"GET" path:@"/search" queryString:@"" headers:@{} body:nil]];
  XCTAssertEqual((NSInteger)200, publicHTML.statusCode);
  NSString *publicBody = ALNTestStringFromResponse(publicHTML);
  XCTAssertTrue([publicBody containsString:@"Products"]);
  XCTAssertFalse([publicBody containsString:@"Finance"]);
  XCTAssertFalse([publicBody containsString:@"Regional Docs"]);
  XCTAssertFalse([publicBody containsString:@"gen "]);

  NSError *auditorRenderError = nil;
  NSString *auditorRendered = [self renderedSearchDashboardForApplication:app
                                                                  headers:@{
                                                                    @"Accept" : @"application/json",
                                                                    @"X-Search-User" : @"auditor-user",
                                                                    @"X-Search-Roles" : @"auditor,admin,operator",
                                                                    @"X-Search-Predicate" : @"allow",
                                                                  }
                                                                    error:&auditorRenderError];
  XCTAssertNotNil(auditorRendered, @"auditor dashboard render failed: %@", auditorRenderError);
  XCTAssertNil(auditorRenderError, @"auditor dashboard render failed: %@", auditorRenderError);

  ALNResponse *auditorHTML =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search"
                                       queryString:@""
                                           headers:@{
                                             @"X-Search-User" : @"auditor-user",
                                             @"X-Search-Roles" : @"auditor,admin,operator",
                                             @"X-Search-Predicate" : @"allow",
                                           }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, auditorHTML.statusCode);
  NSString *auditorBody = ALNTestStringFromResponse(auditorHTML);
  XCTAssertTrue([auditorBody containsString:@"Finance"]);
  XCTAssertTrue([auditorBody containsString:@"Regional Docs"]);
  XCTAssertTrue([auditorBody containsString:@"gen "]);
}

@end
