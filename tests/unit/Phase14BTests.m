#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"

static NSMutableArray<NSString *> *gPhase14BExecutions = nil;

static NSMutableArray<NSString *> *Phase14BExecutions(void) {
  if (gPhase14BExecutions == nil) {
    gPhase14BExecutions = [NSMutableArray array];
  }
  return gPhase14BExecutions;
}

@interface Phase14BRecordedJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase14BRecordedJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase14b.recorded";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Recorded Job",
    @"queue" : @"default",
    @"maxAttempts" : @3,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"value"] isKindOfClass:[NSString class]] &&
      [((NSString *)payload[@"value"]) length] > 0) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14B"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"value is required" }];
  }
  return NO;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)context;
  (void)error;
  [Phase14BExecutions() addObject:payload[@"value"]];
  return YES;
}

@end

@interface Phase14BFailingJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase14BFailingJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase14b.failing";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Failing Job",
    @"queue" : @"default",
    @"maxAttempts" : @1,
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
    *error = [NSError errorWithDomain:@"Phase14B"
                                 code:2
                             userInfo:@{ NSLocalizedDescriptionKey : @"expected failure" }];
  }
  return NO;
}

@end

@interface Phase14BJobProvider : NSObject <ALNJobsJobProvider>
@end

@implementation Phase14BJobProvider

- (NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14BFailingJob alloc] init], [[Phase14BRecordedJob alloc] init] ];
}

@end

@interface Phase14BScheduleProvider : NSObject <ALNJobsScheduleProvider>
@end

@implementation Phase14BScheduleProvider

- (NSArray<NSDictionary *> *)jobsModuleScheduleDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                               error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    @{
      @"identifier" : @"phase14b.interval",
      @"job" : @"phase14b.recorded",
      @"intervalSeconds" : @60,
      @"payload" : @{ @"value" : @"scheduled-interval" },
    },
    @{
      @"identifier" : @"phase14b.cron",
      @"job" : @"phase14b.recorded",
      @"cron" : @"0 15 * * *",
      @"payload" : @{ @"value" : @"scheduled-cron" },
    },
  ];
}

@end

@interface Phase14BTests : XCTestCase
@end

@implementation Phase14BTests

- (void)setUp {
  [super setUp];
  gPhase14BExecutions = [NSMutableArray array];
}

- (ALNApplication *)applicationWithConfig:(NSDictionary *)extraConfig {
  NSMutableDictionary *config = [NSMutableDictionary dictionaryWithDictionary:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{
      @"enabled" : @NO,
    },
    @"jobsModule" : @{
      @"providers" : @{
        @"classes" : @[ @"Phase14BJobProvider" ],
      },
      @"schedules" : @{
        @"classes" : @[ @"Phase14BScheduleProvider" ],
      },
    },
  }];
  [config addEntriesFromDictionary:extraConfig ?: @{}];
  return [[ALNApplication alloc] initWithConfig:config];
}

- (NSDate *)dateAtUTCYear:(NSInteger)year month:(NSInteger)month day:(NSInteger)day hour:(NSInteger)hour minute:(NSInteger)minute {
  NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
  calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  NSDateComponents *components = [[NSDateComponents alloc] init];
  components.year = year;
  components.month = month;
  components.day = day;
  components.hour = hour;
  components.minute = minute;
  components.second = 0;
  return [calendar dateFromComponents:components];
}

- (void)testSchedulesAreNormalizedAndExecutedThroughSharedWorkerContract {
  ALNApplication *app = [self applicationWithConfig:nil];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
  NSArray<NSDictionary *> *schedules = [runtime registeredSchedules];
  XCTAssertEqual((NSUInteger)2, [schedules count]);
  XCTAssertEqualObjects(@"phase14b.cron", schedules[0][@"identifier"]);
  XCTAssertEqualObjects(@"phase14b.interval", schedules[1][@"identifier"]);

  NSDate *matchingCronTime = [self dateAtUTCYear:2026 month:3 day:9 hour:15 minute:0];
  NSDictionary *schedulerSummary = [runtime runSchedulerAt:matchingCronTime error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@2, schedulerSummary[@"triggeredCount"]);
  XCTAssertEqual((NSUInteger)2, [[runtime pendingJobs] count]);

  NSDictionary *workerSummary = [runtime runWorkerAt:matchingCronTime limit:10 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@2, workerSummary[@"acknowledgedCount"]);
  XCTAssertEqualObjects((@[ @"scheduled-cron", @"scheduled-interval" ]),
                        [Phase14BExecutions() sortedArrayUsingSelector:@selector(compare:)]);
}

- (void)testPauseAndDeadLetterReplayAreDeterministic {
  ALNApplication *app = [self applicationWithConfig:nil];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
  XCTAssertTrue([runtime pauseQueueNamed:@"default" error:&error]);
  XCTAssertNil(error);

  NSDictionary *pausedSummary = [runtime runWorkerAt:[NSDate date] limit:5 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@YES, pausedSummary[@"pausedDefaultQueue"]);

  XCTAssertTrue([runtime resumeQueueNamed:@"default" error:&error]);
  XCTAssertNil(error);

  NSString *jobID = [runtime enqueueJobIdentifier:@"phase14b.failing" payload:@{} options:nil error:&error];
  XCTAssertNotNil(jobID);
  XCTAssertNil(error);

  NSDictionary *summary = [runtime runWorkerAt:[NSDate date] limit:5 error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@1, summary[@"retriedCount"]);
  XCTAssertEqual((NSUInteger)1, [[runtime deadLetterJobs] count]);

  NSDictionary *replay = [runtime replayDeadLetterJobID:jobID delaySeconds:0 error:&error];
  XCTAssertNotNil(replay);
  XCTAssertNil(error);
  XCTAssertEqualObjects(jobID, replay[@"deadLetterJobID"]);
  XCTAssertNotEqualObjects(jobID, replay[@"replayedJobID"]);
}

@end
