#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"

@interface Phase16APriorityJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase16APriorityJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase16a.priority";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Priority Import",
    @"description" : @"Exercises queue metadata normalization and persistence",
    @"queue" : @"priority",
    @"queuePriority" : @5,
    @"maxAttempts" : @4,
    @"tags" : @[ @"imports", @"notifications", @"imports" ],
    @"uniqueness" : @{
      @"enabled" : @YES,
      @"scope" : @"payload",
    },
    @"retryBackoff" : @{
      @"strategy" : @"linear",
      @"baseSeconds" : @3,
      @"maxSeconds" : @30,
    },
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"value"] isKindOfClass:[NSString class]]) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase16A"
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

@interface Phase16AFailingJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase16AFailingJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase16a.failing";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Backoff Job",
    @"queue" : @"slow",
    @"maxAttempts" : @3,
    @"retryBackoff" : @{
      @"strategy" : @"exponential",
      @"baseSeconds" : @2,
      @"multiplier" : @2,
      @"maxSeconds" : @10,
    },
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  (void)payload;
  (void)error;
  return YES;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)payload;
  (void)context;
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase16A"
                                 code:2
                             userInfo:@{ NSLocalizedDescriptionKey : @"expected failure" }];
  }
  return NO;
}

@end

@interface Phase16AJobProvider : NSObject <ALNJobsJobProvider>
@end

@implementation Phase16AJobProvider

- (NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16AFailingJob alloc] init], [[Phase16APriorityJob alloc] init] ];
}

@end

@interface Phase16ATests : XCTestCase
@end

@implementation Phase16ATests

- (NSString *)temporaryDirectory {
  NSString *template =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"arlen-phase16a-XXXXXX"];
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

- (ALNApplication *)applicationWithStatePath:(NSString *)statePath {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[ @"Phase16AJobProvider" ] },
      @"persistence" : @{
        @"enabled" : @YES,
        @"path" : statePath ?: @"",
      },
    },
  }];
}

- (void)registerJobsForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (void)testMetadataAndOperatorStatePersistAcrossReconfigure {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"jobs-state.plist"];

  ALNApplication *app = [self applicationWithStatePath:statePath];
  [self registerJobsForApplication:app];

  ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
  NSArray<NSDictionary *> *definitions = [runtime registeredJobDefinitions];
  XCTAssertEqual((NSUInteger)2, [definitions count]);
  XCTAssertEqualObjects(@"phase16a.priority", definitions[1][@"identifier"]);
  XCTAssertEqualObjects(@5, definitions[1][@"queuePriority"]);
  XCTAssertEqualObjects((@[ @"imports", @"notifications" ]), definitions[1][@"tags"]);
  XCTAssertEqualObjects(@YES, definitions[1][@"uniqueness"][@"enabled"]);
  XCTAssertEqualObjects(@"linear", definitions[1][@"retryBackoff"][@"strategy"]);

  NSError *error = nil;
  XCTAssertTrue([runtime pauseQueueNamed:@"priority" error:&error]);
  XCTAssertNil(error);

  NSDictionary *workerSummary = [runtime runWorkerAt:[NSDate date] limit:1 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);

  ALNApplication *restarted = [self applicationWithStatePath:statePath];
  [self registerJobsForApplication:restarted];

  runtime = [ALNJobsModuleRuntime sharedRuntime];
  XCTAssertTrue([runtime isQueuePaused:@"priority"]);
  NSDictionary *dashboard = [runtime dashboardSummary];
  NSArray *queues = [dashboard[@"queues"] isKindOfClass:[NSArray class]] ? dashboard[@"queues"] : @[];
  NSPredicate *priorityPredicate = [NSPredicate predicateWithFormat:@"name == %@", @"priority"];
  NSDictionary *priorityQueue = [[queues filteredArrayUsingPredicate:priorityPredicate] firstObject];
  XCTAssertEqualObjects(@YES, priorityQueue[@"paused"]);
  XCTAssertEqual((NSUInteger)1, [dashboard[@"recentRuns"] count]);
}

- (void)testPerJobBackoffInfluencesRetryDelay {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"jobs-state.plist"]];
  [self registerJobsForApplication:app];

  ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSString *jobID = [runtime enqueueJobIdentifier:@"phase16a.failing" payload:@{} options:nil error:&error];
  XCTAssertNotNil(jobID);
  XCTAssertNil(error);

  NSDate *beforeRun = [NSDate date];
  NSDictionary *summary = [runtime runWorkerAt:beforeRun limit:1 error:&error];
  XCTAssertNotNil(summary);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@1, summary[@"retriedCount"]);

  NSArray<NSDictionary *> *pending = [runtime pendingJobs];
  XCTAssertEqual((NSUInteger)1, [pending count]);
  NSTimeInterval notBefore = [pending[0][@"notBefore"] doubleValue];
  NSTimeInterval delay = notBefore - [beforeRun timeIntervalSince1970];
  XCTAssertTrue(delay >= 1.5);
  XCTAssertTrue(delay <= 3.5);
  XCTAssertEqualObjects(@"slow", pending[0][@"queue"]);
}

- (void)testUniquenessMetadataDerivesStableIdempotencyKey {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"jobs-state.plist"]];
  [self registerJobsForApplication:app];

  ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSString *firstJobID =
      [runtime enqueueJobIdentifier:@"phase16a.priority" payload:@{ @"value" : @"same" } options:nil error:&error];
  XCTAssertNotNil(firstJobID);
  XCTAssertNil(error);

  NSString *secondJobID =
      [runtime enqueueJobIdentifier:@"phase16a.priority" payload:@{ @"value" : @"same" } options:nil error:&error];
  XCTAssertNotNil(secondJobID);
  XCTAssertNil(error);
  XCTAssertEqualObjects(firstJobID, secondJobID);
  XCTAssertEqual((NSUInteger)1, [[runtime pendingJobs] count]);
}

@end
