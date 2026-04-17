#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNAdminUIModule.h"
#import "ALNApplication.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

static NSMutableDictionary<NSString *, NSMutableDictionary *> *Phase16FWidgetStore(void) {
  static NSMutableDictionary<NSString *, NSMutableDictionary *> *store = nil;
  if (store == nil) {
    store = [NSMutableDictionary dictionary];
  }
  return store;
}

static void Phase16FResetWidgetStore(void) {
  NSMutableDictionary *store = Phase16FWidgetStore();
  [store removeAllObjects];
  store[@"wid-100"] = [@{
    @"id" : @"wid-100",
    @"name" : @"Alpha",
    @"status" : @"new",
    @"count" : @1,
    @"updated_at" : @"2026-03-01",
  } mutableCopy];
  store[@"wid-101"] = [@{
    @"id" : @"wid-101",
    @"name" : @"Bravo",
    @"status" : @"ready",
    @"count" : @5,
    @"updated_at" : @"2026-03-08",
  } mutableCopy];
  store[@"wid-102"] = [@{
    @"id" : @"wid-102",
    @"name" : @"Charlie",
    @"status" : @"archived",
    @"count" : @3,
    @"updated_at" : @"2026-03-04",
  } mutableCopy];
}

@interface Phase16FWidgetsResource : NSObject <ALNAdminUIResource>
@end

@implementation Phase16FWidgetsResource

- (NSString *)adminUIResourceIdentifier {
  return @"widgets";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Widgets",
    @"singularLabel" : @"Widget",
    @"summary" : @"Phase 16 admin productivity fixture resource.",
    @"identifierField" : @"id",
    @"primaryField" : @"name",
    @"pageSize" : @1,
    @"pageSizes" : @[ @1, @2, @5 ],
    @"fields" : @[
      @{ @"name" : @"name", @"label" : @"Name", @"list" : @YES, @"detail" : @YES },
      @{
        @"name" : @"status",
        @"label" : @"Status",
        @"list" : @YES,
        @"detail" : @YES,
        @"editable" : @YES,
        @"choices" : @[ @"new", @"ready", @"archived" ],
        @"autocomplete" : @{ @"enabled" : @YES, @"minQueryLength" : @1 },
      },
      @{
        @"name" : @"count",
        @"label" : @"Count",
        @"kind" : @"integer",
        @"inputType" : @"number",
        @"list" : @YES,
        @"detail" : @YES,
        @"editable" : @YES,
      },
      @{ @"name" : @"updated_at", @"label" : @"Updated", @"kind" : @"date", @"detail" : @YES, @"list" : @NO },
    ],
    @"filters" : @[
      @{ @"name" : @"q", @"label" : @"Search", @"type" : @"search", @"placeholder" : @"name or status" },
      @{ @"name" : @"status", @"label" : @"Status", @"type" : @"select", @"choices" : @[ @"new", @"ready", @"archived" ] },
      @{ @"name" : @"count_min", @"label" : @"Min count", @"type" : @"number", @"min" : @"0", @"step" : @"1" },
      @{ @"name" : @"updated_after", @"label" : @"Updated after", @"type" : @"date" },
    ],
    @"sorts" : @[
      @{ @"name" : @"updated_at", @"label" : @"Updated", @"default" : @YES, @"direction" : @"desc" },
      @{ @"name" : @"name", @"label" : @"Name" },
    ],
    @"bulkActions" : @[
      @{ @"name" : @"reset_status", @"label" : @"Reset status", @"method" : @"POST" },
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
  NSInteger countMin = [parameters[@"count_min"] respondsToSelector:@selector(integerValue)] ? [parameters[@"count_min"] integerValue] : 0;
  NSString *updatedAfter = [parameters[@"updated_after"] isKindOfClass:[NSString class]] ? parameters[@"updated_after"] : @"";
  NSString *sort = [parameters[@"sort"] isKindOfClass:[NSString class]] ? [parameters[@"sort"] lowercaseString] : @"";

  NSMutableArray *records = [NSMutableArray array];
  for (NSString *key in [[Phase16FWidgetStore() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    NSDictionary *record = [Phase16FWidgetStore()[key] copy];
    NSString *haystack = [[NSString stringWithFormat:@"%@ %@", record[@"name"] ?: @"", record[@"status"] ?: @""] lowercaseString];
    if ([search length] > 0 && [haystack rangeOfString:search].location == NSNotFound) {
      continue;
    }
    if ([status length] > 0 && ![[record[@"status"] lowercaseString] isEqualToString:status]) {
      continue;
    }
    if ([record[@"count"] integerValue] < countMin) {
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
      result = [[[lhs[@"name"] description] lowercaseString] compare:[[rhs[@"name"] description] lowercaseString]];
    }
    return descending ? -result : result;
  }];

  NSUInteger start = MIN(offset, [records count]);
  NSUInteger length = MIN(limit, ([records count] - start));
  return [records subarrayWithRange:NSMakeRange(start, length)];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  NSDictionary *record = [Phase16FWidgetStore()[identifier ?: @""] copy];
  if (record == nil && error != NULL) {
    *error = [NSError errorWithDomain:@"Phase16F"
                                 code:404
                             userInfo:@{ NSLocalizedDescriptionKey : @"Widget not found" }];
  }
  return record;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  NSMutableDictionary *record = Phase16FWidgetStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase16F"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Widget not found" }];
    }
    return nil;
  }
  NSString *status = [parameters[@"status"] isKindOfClass:[NSString class]] ? parameters[@"status"] : @"";
  if ([status length] > 0) {
    record[@"status"] = status;
  }
  if ([parameters[@"count"] respondsToSelector:@selector(integerValue)]) {
    record[@"count"] = @([parameters[@"count"] integerValue]);
  }
  return [record copy];
}

- (NSDictionary *)adminUIPerformBulkActionNamed:(NSString *)actionName
                                      identifiers:(NSArray<NSString *> *)identifiers
                                       parameters:(NSDictionary *)parameters
                                            error:(NSError **)error {
  (void)parameters;
  if (![[actionName lowercaseString] isEqualToString:@"reset_status"]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase16F"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Unknown bulk action" }];
    }
    return nil;
  }
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *identifier in identifiers) {
    NSMutableDictionary *record = Phase16FWidgetStore()[identifier];
    if (record == nil) {
      continue;
    }
    record[@"status"] = @"new";
    [records addObject:[record copy]];
  }
  return @{
    @"count" : @([records count]),
    @"records" : records,
    @"message" : @"Statuses reset.",
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
  for (NSString *value in @[ @"new", @"ready", @"archived" ]) {
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

@interface Phase16FResourceProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation Phase16FResourceProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16FWidgetsResource alloc] init] ];
}

@end

@interface Phase16FTests : XCTestCase
@end

@implementation Phase16FTests

- (void)setUp {
  [super setUp];
  Phase16FResetWidgetStore();
}

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"adminUI" : @{
      @"resourceProviders" : @{ @"classes" : @[ @"Phase16FResourceProvider" ] },
    },
  }];
}

- (ALNApplication *)applicationWithSecurity:(NSDictionary *)security {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"security" : security ?: @{},
    @"adminUI" : @{
      @"resourceProviders" : @{ @"classes" : @[ @"Phase16FResourceProvider" ] },
    },
  }];
}

- (void)registerModuleForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNAdminUIModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (ALNResponse *)dispatchGETPath:(NSString *)path
                      remoteAddress:(NSString *)remoteAddress
                       application:(ALNApplication *)app {
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET"
                                                      path:path ?: @"/"
                                               queryString:@""
                                                   headers:@{}
                                                      body:[NSData data]];
  request.remoteAddress = remoteAddress ?: @"";
  return [app dispatchRequest:request];
}

- (void)testListMetadataBulkExportAndAutocompleteContracts {
  ALNApplication *app = [self application];
  [self registerModuleForApplication:app];

  ALNAdminUIModuleRuntime *runtime = [ALNAdminUIModuleRuntime sharedRuntime];
  NSDictionary *resource = [runtime resourceMetadataForIdentifier:@"widgets"];
  XCTAssertNotNil(resource);
  XCTAssertEqualObjects(@1, resource[@"pagination"][@"defaultLimit"]);
  XCTAssertEqual((NSUInteger)3, [resource[@"pagination"][@"pageSizes"] count]);
  NSArray *filters = [resource[@"filters"] isKindOfClass:[NSArray class]] ? resource[@"filters"] : @[];
  XCTAssertEqualObjects(@"number", filters[2][@"inputType"]);
  XCTAssertEqualObjects(@"date", filters[3][@"inputType"]);

  NSError *error = nil;
  NSArray *records = [runtime listRecordsForResourceIdentifier:@"widgets"
                                                    parameters:@{
                                                      @"status" : @"ready",
                                                      @"sort" : @"-updated_at",
                                                    }
                                                         limit:10
                                                        offset:0
                                                         error:&error];
  XCTAssertNotNil(records);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [records count]);
  XCTAssertEqualObjects(@"wid-101", records[0][@"id"]);

  NSDictionary *bulkResult = [runtime performBulkActionNamed:@"reset_status"
                                       forResourceIdentifier:@"widgets"
                                                   recordIDs:@[ @"wid-101", @"wid-102" ]
                                                  parameters:@{}
                                                       error:&error];
  XCTAssertNotNil(bulkResult);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@2, bulkResult[@"count"]);

  NSDictionary *jsonPayload = [runtime exportPayloadForResourceIdentifier:@"widgets"
                                                                   format:@"json"
                                                               parameters:@{ @"status" : @"new", @"exportLimit" : @10 }
                                                                    error:&error];
  XCTAssertNotNil(jsonPayload);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"application/json", jsonPayload[@"contentType"]);

  NSDictionary *csvPayload = [runtime exportPayloadForResourceIdentifier:@"widgets"
                                                                  format:@"csv"
                                                              parameters:@{ @"status" : @"new", @"exportLimit" : @10 }
                                                                   error:&error];
  XCTAssertNotNil(csvPayload);
  XCTAssertNil(error);
  XCTAssertTrue([csvPayload[@"contentType"] containsString:@"text/csv"]);
  NSString *csv = [[NSString alloc] initWithData:csvPayload[@"bodyData"] encoding:NSUTF8StringEncoding] ?: @"";
  XCTAssertTrue([csv containsString:@"Name,Status,Count"]);
  XCTAssertTrue([csv containsString:@"Alpha"]);

  NSArray *suggestions = [runtime autocompleteSuggestionsForResourceIdentifier:@"widgets"
                                                                     fieldName:@"status"
                                                                         query:@"re"
                                                                         limit:5
                                                                         error:&error];
  XCTAssertNotNil(suggestions);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [suggestions count]);
  XCTAssertEqualObjects(@"ready", suggestions[0][@"value"]);
}

- (void)testAdminRoutesAttachConfiguredAdminPolicyAndDenyDisallowedSourceIP {
  NSDictionary *security = @{
    @"routePolicies" : @{
      @"admin" : @{
        @"sourceIPAllowlist" : @[ @"127.0.0.1/32" ],
      }
    }
  };
  ALNApplication *app = [self applicationWithSecurity:security];
  [self registerModuleForApplication:app];

  ALNAdminUIModuleRuntime *runtime = [ALNAdminUIModuleRuntime sharedRuntime];
  NSArray *routeTable = [runtime.mountedApplication routeTable];
  XCTAssertTrue([routeTable count] > 0);
  for (NSDictionary *route in routeTable) {
    XCTAssertEqualObjects((@[ @"admin" ]), route[@"policies"]);
  }

  NSError *error = nil;
  XCTAssertTrue([app startWithError:&error]);
  XCTAssertNil(error);

  ALNResponse *denied = [self dispatchGETPath:@"/admin"
                                remoteAddress:@"198.51.100.10"
                                  application:app];
  XCTAssertEqual((NSInteger)403, denied.statusCode);
  XCTAssertEqualObjects(@"source_ip_denied", [denied headerForName:@"X-Arlen-Policy-Denial-Reason"]);

  ALNResponse *allowedToReachAdminAuth = [self dispatchGETPath:@"/admin"
                                                 remoteAddress:@"127.0.0.1"
                                                   application:app];
  XCTAssertEqual((NSInteger)302, allowedToReachAdminAuth.statusCode);
  XCTAssertNil([allowedToReachAdminAuth headerForName:@"X-Arlen-Policy-Denial-Reason"]);
}

@end
