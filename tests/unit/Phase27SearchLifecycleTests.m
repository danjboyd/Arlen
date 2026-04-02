#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNWebTestSupport.h"
#import "../shared/Phase27SearchTestSupport.h"
#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNSearchModule.h"

@interface Phase27SearchLifecycleTests : XCTestCase
@end

@implementation Phase27SearchLifecycleTests

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

- (void)seedIndexes {
  NSError *error = nil;
  XCTAssertNotNil([[ALNSearchModuleRuntime sharedRuntime] queueReindexForResourceIdentifier:nil error:&error]);
  XCTAssertNil(error);
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:20 error:&error]);
  XCTAssertNil(error);
}

- (void)testTenantScopedQueryFiltersSoftDeletedAndArchivedRecords {
  ALNApplication *app = [self application];
  [app addMiddleware:[[Phase27SearchContextMiddleware alloc] init]];
  [self registerModulesForApplication:app];
  [self seedIndexes];

  ALNResponse *missingTenant =
      [app dispatchRequest:ALNTestRequestWithMethod(@"GET",
                                                    @"/search/api/resources/tenant_orders/query",
                                                    @"q=runbook",
                                                    @{ @"Accept" : @"application/json", @"X-Search-User" : @"member-a" },
                                                    nil)];
  XCTAssertEqual((NSInteger)403, missingTenant.statusCode);

  ALNResponse *tenantA =
      [app dispatchRequest:ALNTestRequestWithMethod(@"GET",
                                                    @"/search/api/resources/tenant_orders/query",
                                                    @"q=runbook",
                                                    @{
                                                      @"Accept" : @"application/json",
                                                      @"X-Search-User" : @"member-a",
                                                      @"X-Search-Tenant" : @"tenant-a",
                                                    },
                                                    nil)];
  XCTAssertEqual((NSInteger)200, tenantA.statusCode);
  NSError *jsonError = nil;
  NSDictionary *tenantAJSON = ALNTestJSONDictionaryFromResponse(tenantA, &jsonError);
  XCTAssertNil(jsonError);
  NSArray *tenantAResults = tenantAJSON[@"data"][@"results"];
  XCTAssertEqual((NSUInteger)1, [tenantAResults count]);
  XCTAssertEqualObjects(@"ord-100", tenantAResults[0][@"recordID"]);
  XCTAssertEqualObjects(@"tenant-a", tenantAResults[0][@"fields"][@"tenant_id"]);

  NSDictionary *metadata = [[ALNSearchModuleRuntime sharedRuntime] resourceMetadataForIdentifier:@"tenant_orders"];
  XCTAssertEqualObjects(@"tenant_id", metadata[@"visibility"][@"tenantField"]);
  XCTAssertEqualObjects(@"deleted", metadata[@"visibility"][@"softDeleteField"]);
  XCTAssertEqualObjects(@2, metadata[@"syncPolicy"][@"bulkBatchSize"]);
}

- (void)testPausedResourcesFailClosedAndReplayQueueDrainsAfterRecovery {
  Phase27SearchSetTenantOrdersPaused(YES);
  ALNApplication *pausedApp = [self application];
  [self registerModulesForApplication:pausedApp];

  NSError *error = nil;
  XCTAssertNil([[ALNSearchModuleRuntime sharedRuntime] queueReindexForResourceIdentifier:@"tenant_orders" error:&error]);
  XCTAssertEqual(ALNSearchModuleErrorValidationFailed, error.code);

  Phase27SearchResetStores();
  ALNApplication *app = [self application];
  [self registerModulesForApplication:app];
  [self seedIndexes];

  Phase27SearchSetTenantOrdersIndexingShouldFail(YES);
  NSDictionary *payload = @{
    @"resource" : @"tenant_orders",
    @"mode" : @"incremental",
    @"operation" : @"upsert",
    @"record" : @{
      @"id" : @"ord-106",
      @"title" : @"Tenant A Recovery Note",
      @"description" : @"Replay me after a temporary failure.",
      @"tenant_id" : @"tenant-a",
      @"deleted" : @"false",
      @"archived" : @"false",
      @"published" : @"yes",
      @"status" : @"active",
    },
  };
  XCTAssertNil([[ALNSearchModuleRuntime sharedRuntime] processReindexJobPayload:payload error:&error]);
  XCTAssertEqualObjects(@"expected tenant orders indexing failure", error.localizedDescription);

  NSDictionary *afterFailure = [[ALNSearchModuleRuntime sharedRuntime] resourceDrilldownForIdentifier:@"tenant_orders"];
  XCTAssertEqualObjects(@1, afterFailure[@"resource"][@"replayQueueDepth"]);

  Phase27SearchSetTenantOrdersIndexingShouldFail(NO);
  error = nil;
  NSDictionary *reindex = [[ALNSearchModuleRuntime sharedRuntime] processReindexJobPayload:@{
    @"resource" : @"tenant_orders",
    @"mode" : @"full",
  }
                                                                                           error:&error];
  XCTAssertNotNil(reindex);
  XCTAssertNil(error);
  NSDictionary *afterRecovery = [[ALNSearchModuleRuntime sharedRuntime] resourceDrilldownForIdentifier:@"tenant_orders"];
  XCTAssertEqualObjects(@0, afterRecovery[@"resource"][@"replayQueueDepth"]);
  XCTAssertEqualObjects(@"drained", afterRecovery[@"resource"][@"lastReplayStatus"]);

  error = nil;
  NSDictionary *tenantResult = [[ALNSearchModuleRuntime sharedRuntime] searchQuery:@"recovery"
                                                                 resourceIdentifier:@"tenant_orders"
                                                                            filters:@{ @"tenant_id" : @"tenant-a" }
                                                                               sort:nil
                                                                              limit:10
                                                                             offset:0
                                                                       queryOptions:nil
                                                                              error:&error];
  XCTAssertNotNil(tenantResult);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"ord-106", [tenantResult[@"results"] firstObject][@"recordID"]);
}

@end
