#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNOpsModule.h"

@interface Phase16EOpsJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase16EOpsJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase16e.echo";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Phase16E Echo",
    @"queue" : @"default",
    @"maxAttempts" : @2,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"value"] isKindOfClass:[NSString class]]) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase16E"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"value is required" }];
  }
  return NO;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)payload;
  (void)context;
  (void)error;
  return YES;
}

@end

@interface Phase16EOpsJobProvider : NSObject <ALNJobsJobProvider>
@end

@implementation Phase16EOpsJobProvider

- (NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16EOpsJob alloc] init] ];
}

@end

@interface Phase16EOpsCardProvider : NSObject <ALNOpsCardProvider>
@end

@implementation Phase16EOpsCardProvider

- (NSArray<NSDictionary *> *)opsModuleCardsForRuntime:(ALNOpsModuleRuntime *)runtime
                                                 error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    @{
      @"label" : @"External Queue",
      @"value" : @"7",
      @"status" : @"degraded",
      @"summary" : @"background backlog",
      @"href" : @"/ops/modules/jobs",
    },
    @{
      @"label" : @"",
      @"value" : @"skip",
    },
  ];
}

- (NSArray<NSDictionary *> *)opsModuleWidgetsForRuntime:(ALNOpsModuleRuntime *)runtime
                                                   error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    @{
      @"title" : @"Incident Notes",
      @"body" : @"No active incidents",
      @"status" : @"informational",
    },
    @{
      @"title" : @"Runbook",
      @"value" : @"Jobs",
      @"href" : @"/ops/modules/jobs",
    },
    @{
      @"body" : @"skip",
    },
  ];
}

@end

@interface Phase16ETests : XCTestCase
@end

@implementation Phase16ETests

- (NSString *)temporaryDirectory {
  NSString *template =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"arlen-phase16e-XXXXXX"];
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

- (ALNApplication *)applicationWithStatePath:(NSString *)statePath includeJobs:(BOOL)includeJobs {
  NSMutableDictionary *config = [@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"opsModule" : @{
      @"persistence" : @{
        @"path" : statePath ?: @"",
      },
      @"cardProviders" : @{ @"classes" : @[ @"Phase16EOpsCardProvider" ] },
    },
  } mutableCopy];
  if (includeJobs) {
    config[@"jobsModule"] = @{
      @"providers" : @{ @"classes" : @[ @"Phase16EOpsJobProvider" ] },
    };
  }
  return [[ALNApplication alloc] initWithConfig:config];
}

- (void)registerJobsAndOpsForApplication:(ALNApplication *)app includeJobs:(BOOL)includeJobs {
  NSError *error = nil;
  if (includeJobs) {
    XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
    XCTAssertNil(error);
  }
  XCTAssertTrue([[[ALNOpsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (void)testHistoryAndCardWidgetsPersistAcrossReconfigure {
  NSString *statePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"ops-state.plist"];
  ALNApplication *app = [self applicationWithStatePath:statePath includeJobs:YES];
  [self registerJobsAndOpsForApplication:app includeJobs:YES];

  NSError *error = nil;
  NSString *jobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:@"phase16e.echo"
                                                                       payload:@{ @"value" : @"queued" }
                                                                       options:nil
                                                                         error:&error];
  XCTAssertNotNil(jobID);
  XCTAssertNil(error);

  ALNOpsModuleRuntime *runtime = [ALNOpsModuleRuntime sharedRuntime];
  NSDictionary *summary = [runtime dashboardSummary];
  NSArray *cards = [summary[@"cards"] isKindOfClass:[NSArray class]] ? summary[@"cards"] : @[];
  NSArray *widgets = [summary[@"widgets"] isKindOfClass:[NSArray class]] ? summary[@"widgets"] : @[];
  NSPredicate *cardPredicate = [NSPredicate predicateWithFormat:@"label == %@", @"External Queue"];
  NSPredicate *widgetPredicate = [NSPredicate predicateWithFormat:@"title == %@", @"Incident Notes"];
  XCTAssertEqual((NSUInteger)1, [[cards filteredArrayUsingPredicate:cardPredicate] count]);
  XCTAssertEqual((NSUInteger)1, [[widgets filteredArrayUsingPredicate:widgetPredicate] count]);
  XCTAssertEqual((NSUInteger)2, [widgets count]);

  NSDictionary *workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:5 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);

  summary = [runtime dashboardSummary];
  NSArray *history = [summary[@"history"] isKindOfClass:[NSArray class]] ? summary[@"history"] : @[];
  XCTAssertTrue([history count] >= 2);

  ALNApplication *restarted = [self applicationWithStatePath:statePath includeJobs:YES];
  [self registerJobsAndOpsForApplication:restarted includeJobs:YES];
  runtime = [ALNOpsModuleRuntime sharedRuntime];
  summary = [runtime dashboardSummary];
  history = [summary[@"history"] isKindOfClass:[NSArray class]] ? summary[@"history"] : @[];
  XCTAssertTrue([history count] >= 2);
  XCTAssertEqualObjects(@YES, [runtime resolvedConfigSummary][@"persistenceEnabled"]);
  XCTAssertEqualObjects(@1, [runtime resolvedConfigSummary][@"cardProviderCount"]);

  NSDictionary *drilldown = [runtime moduleDrilldownForIdentifier:@"jobs"];
  XCTAssertNotNil(drilldown);
  XCTAssertEqualObjects(@"jobs", drilldown[@"identifier"]);
  XCTAssertTrue([(NSArray *)(drilldown[@"history"] ?: @[]) count] > 0);
}

- (void)testOpsRemainsUsefulWhenOnlyOpsModuleIsInstalled {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"ops-state.plist"]
                                           includeJobs:NO];
  [self registerJobsAndOpsForApplication:app includeJobs:NO];

  ALNOpsModuleRuntime *runtime = [ALNOpsModuleRuntime sharedRuntime];
  NSDictionary *summary = [runtime dashboardSummary];
  XCTAssertEqualObjects(@NO, summary[@"jobs"][@"available"]);
  XCTAssertEqualObjects(@NO, summary[@"notifications"][@"available"]);
  XCTAssertEqualObjects(@NO, summary[@"storage"][@"available"]);
  XCTAssertEqualObjects(@NO, summary[@"search"][@"available"]);
  XCTAssertEqualObjects(@"informational", summary[@"jobs"][@"status"]);
  XCTAssertEqualObjects(@"informational", summary[@"notifications"][@"status"]);
  XCTAssertNotNil([runtime moduleDrilldownForIdentifier:@"notifications"]);
}

@end
