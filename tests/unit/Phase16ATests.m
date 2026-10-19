#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "../shared/ALNTestSupport.h"
#import "../shared/ALNTestProcessCheckpoint.h"

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
  NSString *directory = ALNTestTemporaryDirectory(@"arlen-phase16a");
  XCTAssertNotNil(directory);
  return directory;
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

- (void)testJobsOperatorStateTransactionsAcrossProcesses {
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
  NSString *sharedPath = environment[@"ARLEN_JOBS_SHARED_STATE_PATH"];
  if ([sharedPath length] > 0) {
    [self registerJobsForApplication:[self applicationWithStatePath:sharedPath]];
    ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
    NSString *index = environment[@"ARLEN_JOBS_PROCESS_INDEX"];
    if ([environment[@"ARLEN_MODULE_PROCESS_PROBE_ABORT"] boolValue]) return;
    XCTAssertTrue(ALNTestSignalCheckpoint(sharedPath, [@"ready-" stringByAppendingString:index]));
    BOOL started = ALNTestWaitCheckpoint(sharedPath, [@"start-" stringByAppendingString:index]);
    XCTAssertTrue(started);
    if (!started) return;
    NSError *error = nil;
    BOOL first = [environment[@"ARLEN_JOBS_PROCESS_INDEX"] isEqual:@"0"];
    if (first) {
      XCTAssertTrue([runtime pauseQueueNamed:@"shared" error:&error]);
    } else {
      // A cached reader must see the pause, and a stale resume must remove it.
      XCTAssertTrue([runtime isQueuePaused:@"shared"]);
      XCTAssertTrue([runtime resumeQueueNamed:@"shared" error:&error]);
    }
    XCTAssertNil(error);
    XCTAssertTrue(ALNTestSignalCheckpoint(sharedPath, [@"changed-" stringByAppendingString:index]));
    if (first) {
      BOOL resumed = ALNTestWaitCheckpoint(sharedPath, @"resume-0");
      XCTAssertTrue(resumed);
      if (!resumed) return;
      XCTAssertFalse([runtime isQueuePaused:@"shared"]);
    }
    NSString *queue = [NSString stringWithFormat:@"queue-%@", environment[@"ARLEN_JOBS_PROCESS_INDEX"]];
    XCTAssertTrue([runtime pauseQueueNamed:queue error:&error]);
    XCTAssertNotNil([runtime runWorkerAt:[NSDate date] limit:1 error:&error]);
    XCTAssertNil(error);
    XCTAssertTrue(ALNTestSignalCheckpoint(sharedPath, [@"complete-" stringByAppendingString:index]));
    return;
  }

  NSString *statePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"jobs-process-state.plist"];
  NSMutableArray<NSTask *> *children = [NSMutableArray array];
  NSMutableArray<NSFileHandle *> *logs = [NSMutableArray array];
  @try {
    for (NSUInteger index = 0; index < 2; index++) {
      NSTask *child = [[NSTask alloc] init];
      child.launchPath = [[[NSProcessInfo processInfo] arguments] firstObject];
      NSString *bundle = [[NSBundle bundleForClass:[self class]] bundlePath];
#if defined(__APPLE__)
      child.arguments = @[@"-XCTest", @"Phase16ATests/testJobsOperatorStateTransactionsAcrossProcesses", bundle];
#else
      child.arguments = @[@"-only-testing:ArlenUnitTests/Phase16ATests/testJobsOperatorStateTransactionsAcrossProcesses", @"-output-format", @"apple", bundle];
#endif
      NSMutableDictionary *childEnvironment = [environment mutableCopy];
      childEnvironment[@"ARLEN_JOBS_SHARED_STATE_PATH"] = statePath;
      childEnvironment[@"ARLEN_JOBS_PROCESS_INDEX"] = [@(index) stringValue];
      child.environment = childEnvironment;
      NSString *logPath = [statePath stringByAppendingFormat:@".child-%lu.log", (unsigned long)index];
      [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
      NSFileHandle *log = [NSFileHandle fileHandleForWritingAtPath:logPath];
      [logs addObject:log];
      child.standardOutput = log; child.standardError = log;
      [child launch];
      [children addObject:child];
    }
    for (NSUInteger index = 0; index < 2; index++) {
      BOOL ready = ALNTestWaitCheckpoint(statePath, [NSString stringWithFormat:@"ready-%lu", (unsigned long)index]);
      XCTAssertTrue(ready, @"child %lu did not reach its fixture", (unsigned long)index);
      if (!ready) return;
    }
    XCTAssertTrue(ALNTestSignalCheckpoint(statePath, @"start-0"));
    BOOL firstReady = ALNTestWaitCheckpoint(statePath, @"changed-0");
    XCTAssertTrue(firstReady);
    if (!firstReady) return;
    XCTAssertTrue(ALNTestSignalCheckpoint(statePath, @"start-1"));
    BOOL secondReady = ALNTestWaitCheckpoint(statePath, @"changed-1");
    XCTAssertTrue(secondReady);
    if (!secondReady) return;
    XCTAssertTrue(ALNTestSignalCheckpoint(statePath, @"resume-0"));
    for (NSUInteger index = 0; index < children.count; index++) {
      NSTask *child = children[index];
      BOOL exited = ALNTestWaitForTaskExit(child, 20.0);
      XCTAssertTrue(exited, @"child %lu did not exit", (unsigned long)index);
      if (!exited) return;
      XCTAssertEqual(0, child.terminationStatus);
      NSString *complete = [statePath stringByAppendingFormat:@".complete-%lu", (unsigned long)index];
      XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:complete]);
      NSString *logPath = [statePath stringByAppendingFormat:@".child-%lu.log", (unsigned long)index];
      NSString *output = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:NULL];
      XCTAssertTrue([output containsString:@"Executed 1 test"], @"%@", output);
    }
  } @finally {
    for (NSTask *child in children) XCTAssertTrue(ALNTestReapChild(child));
    for (NSFileHandle *log in logs) [log closeFile];
  }
  // Restart a third runtime; do not rely on NSDictionary's platform-dependent
  // convenience plist reader (GNUstep does not read binary plists there).
  [self registerJobsForApplication:[self applicationWithStatePath:statePath]];
  ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
  XCTAssertTrue([runtime isQueuePaused:@"queue-0"]);
  XCTAssertTrue([runtime isQueuePaused:@"queue-1"]);
  XCTAssertFalse([runtime isQueuePaused:@"shared"]);
  XCTAssertEqual((NSUInteger)2, [(NSArray *)[runtime dashboardSummary][@"recentRuns"] count]);
}

- (void)testJobsRejectsCorruptStateWithoutOverwritingIt {
  NSString *path = [[self temporaryDirectory] stringByAppendingPathComponent:@"corrupt.plist"];
  ALNJobsModuleRuntime *runtime = [[ALNJobsModuleRuntime alloc] init];
  NSError *error = nil;
  XCTAssertTrue([runtime configureWithApplication:[self applicationWithStatePath:path] error:&error]);
  NSData *invalid = [@"broken state" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertTrue([invalid writeToFile:path atomically:YES]);
  XCTAssertFalse([runtime resumeQueueNamed:@"default" error:&error]);
  XCTAssertNotNil(error);
  XCTAssertTrue([runtime isQueuePaused:@"default"]); // Failed refresh cannot authorize work.
  XCTAssertEqualObjects(invalid, [NSData dataWithContentsOfFile:path]);
}

@end
