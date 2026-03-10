#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <stdlib.h>

#import "ALNAdminUIModule.h"
#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNJobsModule.h"
#import "ALNOpsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSearchModule.h"

static NSMutableDictionary<NSString *, NSMutableDictionary *> *Phase14SearchOrdersStore(void) {
  static NSMutableDictionary<NSString *, NSMutableDictionary *> *store = nil;
  if (store == nil) {
    store = [@{
      @"ord-100" : [@{
        @"id" : @"ord-100",
        @"order_number" : @"100",
        @"status" : @"reviewed",
        @"owner_email" : @"buyer-one@example.test",
        @"total_cents" : @1250,
      } mutableCopy],
      @"ord-101" : [@{
        @"id" : @"ord-101",
        @"order_number" : @"101",
        @"status" : @"pending",
        @"owner_email" : @"buyer-two@example.test",
        @"total_cents" : @2400,
      } mutableCopy],
    } mutableCopy];
  }
  return store;
}

@interface Phase14SearchAuthMiddleware : NSObject <ALNMiddleware>
@end

@implementation Phase14SearchAuthMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  context.stash[ALNContextAuthSubjectStashKey] = @"search-admin";
  context.stash[ALNContextAuthRolesStashKey] = @[ @"admin", @"operator" ];
  context.stash[ALNContextAuthClaimsStashKey] = @{
    @"sub" : @"search-admin",
    @"roles" : @[ @"admin", @"operator" ],
    @"aal" : @2,
    @"amr" : @[ @"otp" ],
    @"iat" : @((NSInteger)now),
    @"auth_time" : @((NSInteger)now),
  };
  return YES;
}

@end

@interface Phase14SearchOrdersResource : NSObject <ALNAdminUIResource>
@end

@implementation Phase14SearchOrdersResource

- (NSString *)adminUIResourceIdentifier {
  return @"orders";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Orders",
    @"singularLabel" : @"Order",
    @"summary" : @"Searchable integration orders.",
    @"identifierField" : @"id",
    @"primaryField" : @"order_number",
    @"fields" : @[
      @{ @"name" : @"order_number", @"label" : @"Order", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"status", @"label" : @"Status", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"owner_email", @"label" : @"Owner", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"total_cents", @"label" : @"Total", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
    ],
    @"filters" : @[ @{ @"name" : @"q", @"label" : @"Search", @"type" : @"search" } ],
    @"actions" : @[ @{ @"name" : @"mark_reviewed", @"label" : @"Mark reviewed", @"scope" : @"row" } ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  (void)error;
  NSString *search = [query ?: @"" lowercaseString];
  NSArray *keys = [[Phase14SearchOrdersStore() allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *key in keys) {
    NSDictionary *record = Phase14SearchOrdersStore()[key];
    NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@",
                                                     record[@"order_number"] ?: @"",
                                                     record[@"status"] ?: @"",
                                                     record[@"owner_email"] ?: @""]
        lowercaseString];
    if ([search length] > 0 && [haystack rangeOfString:search].location == NSNotFound) {
      continue;
    }
    [records addObject:[record copy]];
  }
  NSUInteger start = MIN(offset, [records count]);
  NSUInteger length = MIN(limit, ([records count] - start));
  return [records subarrayWithRange:NSMakeRange(start, length)];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  NSDictionary *record = [Phase14SearchOrdersStore()[identifier ?: @""] copy];
  if (record == nil && error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14Search"
                                 code:404
                             userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
  }
  return record;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  NSMutableDictionary *record = Phase14SearchOrdersStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase14Search"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  NSString *status = [parameters[@"status"] isKindOfClass:[NSString class]] ? parameters[@"status"] : @"";
  if ([status length] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase14Search"
                                   code:422
                               userInfo:@{ NSLocalizedDescriptionKey : @"status is required" }];
    }
    return nil;
  }
  record[@"status"] = status;
  return [record copy];
}

- (NSDictionary *)adminUIPerformActionNamed:(NSString *)actionName
                                 identifier:(NSString *)identifier
                                 parameters:(NSDictionary *)parameters
                                      error:(NSError **)error {
  (void)parameters;
  NSMutableDictionary *record = Phase14SearchOrdersStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase14Search"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  if (![[actionName lowercaseString] isEqualToString:@"mark_reviewed"]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase14Search"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Action not found" }];
    }
    return nil;
  }
  record[@"status"] = @"reviewed";
  return @{
    @"record" : [record copy],
    @"message" : @"Order marked reviewed.",
  };
}

@end

@interface Phase14SearchOrdersProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation Phase14SearchOrdersProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14SearchOrdersResource alloc] init] ];
}

@end

@interface Phase14SearchIntegrationTests : XCTestCase
@end

@implementation Phase14SearchIntegrationTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (void)setUp {
  [super setUp];
  Phase14SearchOrdersStore();
}

- (ALNApplication *)application {
  NSString *dsn = [self pgTestDSN];
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"database" : @{
      @"connectionString" : dsn ?: @"",
    },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"adminUI" : @{
      @"resourceProviders" : @{ @"classes" : @[ @"Phase14SearchOrdersProvider" ] },
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
  return [[ALNRequest alloc] initWithMethod:method ?: @"GET"
                                      path:path ?: @"/"
                               queryString:queryString ?: @""
                                   headers:headers ?: @{}
                                      body:body ?: [NSData data]];
}

- (NSDictionary *)JSONObjectFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
  return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (void)testSearchQueryAndReindexStatusSurfaceThroughAdminAndOps {
  if ([[self pgTestDSN] length] == 0) {
    return;
  }
  ALNApplication *app = [self application];
  [app addMiddleware:[[Phase14SearchAuthMiddleware alloc] init]];
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
  XCTAssertTrue([queueJSON[@"data"][@"jobID"] isKindOfClass:[NSString class]]);

  ALNResponse *workerResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/jobs/api/run-worker"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, workerResponse.statusCode);
  NSDictionary *workerJSON = [self JSONObjectFromResponse:workerResponse];
  XCTAssertEqualObjects(@1, workerJSON[@"data"][@"acknowledgedCount"]);

  ALNResponse *queryResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/search/api/resources/orders/query"
                                       queryString:@"q=reviewed"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, queryResponse.statusCode);
  NSDictionary *queryJSON = [self JSONObjectFromResponse:queryResponse];
  NSArray *results = [queryJSON[@"data"][@"results"] isKindOfClass:[NSArray class]] ? queryJSON[@"data"][@"results"] : @[];
  XCTAssertEqual((NSUInteger)1, [results count]);
  XCTAssertEqualObjects(@"ord-100", results[0][@"recordID"]);

  ALNResponse *adminResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/admin/api/resources/search_indexes/items"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, adminResponse.statusCode);
  NSDictionary *adminJSON = [self JSONObjectFromResponse:adminResponse];
  NSArray *items = [adminJSON[@"items"] isKindOfClass:[NSArray class]] ? adminJSON[@"items"] : @[];
  XCTAssertEqual((NSUInteger)2, [items count]);
  NSPredicate *ordersPredicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
    (void)bindings;
    return [entry[@"identifier"] isEqualToString:@"orders"];
  }];
  NSDictionary *ordersStatus = [[items filteredArrayUsingPredicate:ordersPredicate] firstObject];
  XCTAssertEqualObjects(@2, ordersStatus[@"documentCount"]);

  ALNResponse *opsResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/ops/api/summary"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, opsResponse.statusCode);
  NSDictionary *opsJSON = [self JSONObjectFromResponse:opsResponse];
  NSDictionary *search = opsJSON[@"data"][@"search"];
  XCTAssertEqualObjects(@YES, search[@"available"]);
  XCTAssertEqualObjects(@2, search[@"totals"][@"documents"]);
}

@end
