#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNAdminUIModule.h"
#import "ALNApplication.h"
#import "ALNAuthModule.h"

static NSMutableDictionary<NSString *, NSMutableDictionary *> *gPhase13HOrders = nil;

static NSMutableDictionary<NSString *, NSMutableDictionary *> *Phase13HOrderStore(void) {
  if (gPhase13HOrders == nil) {
    gPhase13HOrders = [@{
      @"ord-100" : [@{
        @"id" : @"ord-100",
        @"order_number" : @"100",
        @"status" : @"pending",
        @"total_cents" : @1250,
        @"owner_email" : @"buyer-one@example.test",
      } mutableCopy],
      @"ord-denied" : [@{
        @"id" : @"ord-denied",
        @"order_number" : @"denied",
        @"status" : @"pending",
        @"total_cents" : @777,
        @"owner_email" : @"buyer-two@example.test",
      } mutableCopy],
    } mutableCopy];
  }
  return gPhase13HOrders;
}

@interface Phase13HOrdersResource : NSObject <ALNAdminUIResource>
@end

@implementation Phase13HOrdersResource

- (NSString *)adminUIResourceIdentifier {
  return @"orders";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Orders",
    @"singularLabel" : @"Order",
    @"summary" : @"Example app-owned admin resource",
    @"identifierField" : @"id",
    @"primaryField" : @"order_number",
    @"fields" : @[
      @{ @"name" : @"order_number", @"label" : @"Order", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"status", @"label" : @"Status", @"list" : @YES, @"detail" : @YES, @"editable" : @YES },
      @{ @"name" : @"total_cents", @"label" : @"Total", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"owner_email", @"label" : @"Owner", @"kind" : @"email", @"list" : @YES, @"detail" : @YES },
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
  NSString *search = [(query ?: @"") lowercaseString];
  NSArray *allKeys = [[[Phase13HOrderStore() allKeys] sortedArrayUsingSelector:@selector(compare:)] copy];
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *key in allKeys) {
    NSDictionary *record = Phase13HOrderStore()[key];
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
  NSDictionary *record = [Phase13HOrderStore()[identifier ?: @""] copy];
  if (record == nil && error != NULL) {
    *error = [NSError errorWithDomain:@"Phase13H"
                                 code:404
                             userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
  }
  return record;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  NSMutableDictionary *record = Phase13HOrderStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase13H"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  NSString *status = [parameters[@"status"] isKindOfClass:[NSString class]] ? parameters[@"status"] : @"";
  if ([status length] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase13H"
                                   code:422
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"status is required",
                                 @"field" : @"status",
                               }];
    }
    return nil;
  }
  record[@"status"] = status;
  return [record copy];
}

- (BOOL)adminUIResourceAllowsOperation:(NSString *)operation
                            identifier:(NSString *)identifier
                               context:(ALNContext *)context
                                 error:(NSError **)error {
  (void)context;
  if ([[operation lowercaseString] isEqualToString:@"action:mark_reviewed"] &&
      [identifier isEqualToString:@"ord-denied"]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase13H"
                                   code:403
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"orders policy denied review for this record",
                               }];
    }
    return NO;
  }
  return YES;
}

- (NSDictionary *)adminUIPerformActionNamed:(NSString *)actionName
                                 identifier:(NSString *)identifier
                                 parameters:(NSDictionary *)parameters
                                      error:(NSError **)error {
  (void)parameters;
  NSMutableDictionary *record = Phase13HOrderStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase13H"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  if (![[actionName lowercaseString] isEqualToString:@"mark_reviewed"]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase13H"
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

@interface Phase13HOrdersProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation Phase13HOrdersProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase13HOrdersResource alloc] init] ];
}

@end

@interface Phase13HTests : XCTestCase
@end

@implementation Phase13HTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (ALNApplication *)applicationWithConfig:(NSDictionary *)extraConfig {
  NSString *dsn = [self pgTestDSN];
  NSMutableDictionary *config = [NSMutableDictionary dictionaryWithDictionary:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{
      @"enabled" : @YES,
      @"secret" : @"phase13h-session-secret-0123456789abcdef",
    },
    @"csrf" : @{
      @"enabled" : @YES,
      @"allowQueryParamFallback" : @YES,
    },
    @"database" : @{
      @"connectionString" : dsn ?: @"",
    },
  }];
  [config addEntriesFromDictionary:extraConfig ?: @{}];
  return [[ALNApplication alloc] initWithConfig:config];
}

- (void)setUp {
  [super setUp];
  gPhase13HOrders = nil;
}

- (void)testResourceRegistrationOrderAndMetadataStayDeterministic {
  if ([[self pgTestDSN] length] == 0) {
    return;
  }
  ALNApplication *app = [self applicationWithConfig:@{
    @"adminUI" : @{
      @"resourceProviders" : @{
        @"classes" : @[ @"Phase13HOrdersProvider" ],
      },
    },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNAdminUIModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  ALNAdminUIModuleRuntime *runtime = [ALNAdminUIModuleRuntime sharedRuntime];
  NSArray *resources = [runtime registeredResources];
  XCTAssertEqual((NSUInteger)2, [resources count]);
  XCTAssertEqualObjects(@"users", resources[0][@"identifier"]);
  XCTAssertEqualObjects(@"orders", resources[1][@"identifier"]);

  NSDictionary *orders = [runtime resourceMetadataForIdentifier:@"orders"];
  XCTAssertEqualObjects(@"Orders", orders[@"label"]);
  XCTAssertEqualObjects(@"Order", orders[@"singularLabel"]);
  XCTAssertEqualObjects(@"id", orders[@"identifierField"]);
  XCTAssertEqualObjects(@"order_number", orders[@"primaryField"]);
  XCTAssertEqualObjects(@"order_number", orders[@"fields"][0][@"name"]);
  XCTAssertEqualObjects(@"status", orders[@"fields"][1][@"name"]);
  XCTAssertEqualObjects(@"mark_reviewed", orders[@"actions"][0][@"name"]);
  XCTAssertEqualObjects(@"/admin/resources/orders", orders[@"paths"][@"html_index"]);
  XCTAssertEqualObjects(@"/admin/api/resources/orders/items", orders[@"paths"][@"api_items"]);
}

- (void)testResourceActionAndPolicyHooksAreResolvedFromSameResourceDefinition {
  if ([[self pgTestDSN] length] == 0) {
    return;
  }
  ALNApplication *app = [self applicationWithConfig:@{
    @"adminUI" : @{
      @"resourceProviders" : @{
        @"classes" : @[ @"Phase13HOrdersProvider" ],
      },
    },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNAdminUIModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  ALNAdminUIModuleRuntime *runtime = [ALNAdminUIModuleRuntime sharedRuntime];
  ALNContext *fakeContext = (ALNContext *)(id)[NSObject new];
  NSError *policyError = nil;
  XCTAssertTrue([runtime resourceIdentifier:@"orders"
                             allowsOperation:@"action:mark_reviewed"
                                   recordID:@"ord-100"
                                    context:fakeContext
                                      error:&policyError]);
  XCTAssertNil(policyError);

  NSError *deniedError = nil;
  XCTAssertFalse([runtime resourceIdentifier:@"orders"
                              allowsOperation:@"action:mark_reviewed"
                                    recordID:@"ord-denied"
                                     context:fakeContext
                                       error:&deniedError]);
  XCTAssertEqualObjects(@"orders policy denied review for this record", deniedError.localizedDescription);

  NSDictionary *updated = [runtime updateRecordForResourceIdentifier:@"orders"
                                                            recordID:@"ord-100"
                                                          parameters:@{ @"status" : @"packed" }
                                                               error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"packed", updated[@"status"]);

  NSDictionary *actionResult = [runtime performActionNamed:@"mark_reviewed"
                                     forResourceIdentifier:@"orders"
                                                  recordID:@"ord-100"
                                                parameters:@{}
                                                     error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"Order marked reviewed.", actionResult[@"message"]);
  XCTAssertEqualObjects(@"reviewed", actionResult[@"record"][@"status"]);
}

@end
