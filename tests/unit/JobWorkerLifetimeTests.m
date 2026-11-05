#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNServices.h"

@interface JWLLifetimeCounter : NSObject
@property(nonatomic, assign) NSUInteger live;
@end
@implementation JWLLifetimeCounter
@end

@interface JWLScratch : NSObject
@property(nonatomic, strong) JWLLifetimeCounter *counter;
- (instancetype)initWithCounter:(JWLLifetimeCounter *)counter;
@end
@implementation JWLScratch
- (instancetype)initWithCounter:(JWLLifetimeCounter *)counter {
  self = [super init];
  if (self) { _counter = counter; counter.live++; }
  return self;
}
- (void)dealloc { _counter.live--; }
@end

// Model an actual autoreleasing producer, independent of ARC's optimized
// return-value handshake. Transfer one +1 to autorelease via NSInvocation,
// which does not claim the returned object as an ARC caller would. The ARC
// local owns a separate +1. No fixture build flags or runtime pins change.
__attribute__((noinline)) static void JWLMakeAutoreleasedScratch(JWLLifetimeCounter *counter) {
  JWLScratch *scratch = [[JWLScratch alloc] initWithCounter:counter];
  void *pendingRelease = (__bridge_retained void *)scratch;
  SEL selector = NSSelectorFromString(@"autorelease");
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
      [scratch methodSignatureForSelector:selector]];
  [invocation setTarget:(__bridge id)pendingRelease];
  [invocation setSelector:selector];
  [invocation invoke];
}

static NSError *JWLAdapterError(NSString *stage) {
  NSError *cause = [NSError errorWithDomain:@"JWL.Cause" code:91
      userInfo:@{ @"detail" : [NSString stringWithFormat:@"%@-detail", stage] }];
  return [NSError errorWithDomain:@"JWL.Adapter" code:92
      userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"%@-failure", stage],
                  NSUnderlyingErrorKey : cause }];
}

// A local, deterministic adapter: durable paths use a real heartbeat thread but
// need no database or outside service. Failure errors are not retained here.
@interface JWLAdapter : NSObject <ALNJobAdapter>
@property(nonatomic, strong) NSMutableArray<ALNJobEnvelope *> *jobs;
@property(nonatomic, strong) NSMutableArray<NSDate *> *dequeueTimes;
@property(nonatomic, assign) BOOL durable;
@property(nonatomic, copy) NSString *failureStage;
@property(nonatomic, assign) NSUInteger completed;
@property(nonatomic, assign) NSUInteger retried;
@property(nonatomic, strong) id completedResult;
@property(nonatomic, copy) NSString *failureMessage;
@property(nonatomic, assign) NSTimeInterval retryDelay;
@property(nonatomic, strong) NSCondition *renewal;
@property(nonatomic, assign) BOOL renewed;
- (void)addJobs:(NSUInteger)count;
- (BOOL)waitForRenewal;
@end

@implementation JWLAdapter
- (instancetype)init {
  self = [super init];
  if (self) {
    _jobs = [NSMutableArray array];
    _dequeueTimes = [NSMutableArray array];
    _failureStage = @"";
    _renewal = [NSCondition new];
  }
  return self;
}
- (BOOL)respondsToSelector:(SEL)selector {
  if (selector == @selector(completeJob:result:error:)) return self.durable;
  return [super respondsToSelector:selector];
}
- (NSString *)adapterName { return @"lifetime-fixture"; }
- (void)addJobs:(NSUInteger)count {
  for (NSUInteger index = 0; index < count; index++) {
    ALNJobEnvelope *job = [[ALNJobEnvelope alloc]
        initWithJobID:[NSString stringWithFormat:@"job-%lu", (unsigned long)index]
        name:@"lifetime" payload:@{} attempt:1 maxAttempts:2
        notBefore:[NSDate dateWithTimeIntervalSince1970:1]
        createdAt:[NSDate dateWithTimeIntervalSince1970:1] sequence:index];
    if (self.durable) {
      job = [[ALNJobLease alloc] initWithEnvelope:job leaseToken:job.jobID
          leaseExpiresAt:[NSDate dateWithTimeIntervalSinceNow:30] leaseDurationSeconds:0.03];
    }
    [self.jobs addObject:job];
  }
}
- (NSString *)enqueueJobNamed:(NSString *)name payload:(NSDictionary *)payload options:(NSDictionary *)options error:(NSError **)error {
  (void)name; (void)payload; (void)options; (void)error;
  [self addJobs:1];
  return [[self.jobs lastObject] jobID];
}
- (ALNJobEnvelope *)dequeueDueJobAt:(NSDate *)timestamp error:(NSError **)error {
  [self.dequeueTimes addObject:timestamp];
  if ([self.failureStage isEqualToString:@"dequeue"]) {
    if (error) *error = JWLAdapterError(@"dequeue");
    return nil;
  }
  ALNJobEnvelope *job = [self.jobs firstObject];
  if (job) [self.jobs removeObjectAtIndex:0];
  return job;
}
- (BOOL)acknowledgeJobID:(NSString *)jobID error:(NSError **)error {
  (void)jobID;
  if ([self.failureStage isEqualToString:@"ack"]) {
    if (error) *error = JWLAdapterError(@"ack");
    return NO;
  }
  self.completed++;
  return YES;
}
- (BOOL)retryJob:(ALNJobEnvelope *)job delaySeconds:(NSTimeInterval)delay error:(NSError **)error {
  return [self retryJob:job delaySeconds:delay failureMessage:nil error:error];
}
- (BOOL)retryJob:(ALNJobEnvelope *)job delaySeconds:(NSTimeInterval)delay failureMessage:(NSString *)message error:(NSError **)error {
  (void)job;
  if ([self.failureStage isEqualToString:@"retry"]) {
    if (error) *error = JWLAdapterError(@"retry");
    return NO;
  }
  self.retried++;
  self.retryDelay = delay;
  self.failureMessage = message;
  return YES;
}
- (BOOL)completeJob:(ALNJobLease *)job result:(id)result error:(NSError **)error {
  (void)job;
  if ([self.failureStage isEqualToString:@"complete"]) {
    if (error) *error = JWLAdapterError(@"complete");
    return NO;
  }
  self.completedResult = result;
  self.completed++;
  return YES;
}
- (BOOL)renewJob:(ALNJobLease *)job error:(NSError **)error {
  (void)job;
  BOOL fail = [self.failureStage isEqualToString:@"heartbeat"];
  if (fail && error) *error = JWLAdapterError(@"heartbeat");
  [self.renewal lock];
  self.renewed = YES;
  [self.renewal broadcast];
  [self.renewal unlock];
  return !fail;
}
- (BOOL)waitForRenewal {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  [self.renewal lock];
  while (!self.renewed && [deadline timeIntervalSinceNow] > 0) [self.renewal waitUntilDate:deadline];
  BOOL renewed = self.renewed;
  [self.renewal unlock];
  return renewed;
}
- (NSArray *)pendingJobsSnapshot { return [self.jobs copy]; }
- (NSArray *)deadLetterJobsSnapshot { return @[]; }
- (void)reset { [self.jobs removeAllObjects]; }
@end

@interface JWLRuntime : NSObject <ALNJobWorkerRuntime>
@property(nonatomic, strong) JWLLifetimeCounter *counter;
@property(nonatomic, strong) JWLAdapter *adapter;
@property(nonatomic, assign) NSUInteger calls;
@property(nonatomic, assign) NSUInteger maximumPreviousScratch;
@property(nonatomic, assign) BOOL retry;
@property(nonatomic, assign) BOOL throwFirst;
@property(nonatomic, assign) BOOL waitForHeartbeat;
@property(nonatomic, assign) BOOL observedHeartbeat;
@end
@implementation JWLRuntime
- (ALNJobWorkerDisposition)handleJob:(ALNJobEnvelope *)job error:(NSError **)error {
  (void)job;
  self.maximumPreviousScratch = MAX(self.maximumPreviousScratch, self.counter.live);
  self.calls++;
  JWLMakeAutoreleasedScratch(self.counter);
  if (self.waitForHeartbeat) self.observedHeartbeat = [self.adapter waitForRenewal];
  if (self.throwFirst && self.calls == 1) [NSException raise:@"JWL.Poison" format:@"fixture poison"];
  if (self.retry) {
    if (error) *error = JWLAdapterError(@"handler");
    return ALNJobWorkerDispositionRetry;
  }
  return ALNJobWorkerDispositionAcknowledge;
}
- (id)jobWorker:(ALNJobWorker *)worker resultForJob:(ALNJobEnvelope *)job {
  (void)worker;
  return @{ @"job" : [NSString stringWithFormat:@"%@-result", job.jobID], @"nested" : @[@1, @2] };
}
- (NSTimeInterval)jobWorker:(ALNJobWorker *)worker retryDelayForJob:(ALNJobEnvelope *)job
               handlerError:(NSError *)error baseRetryDelay:(NSTimeInterval)delay {
  (void)worker; (void)job; (void)delay;
  // The handler's autoreleased error must remain valid through retry policy.
  NSError *cause = error.userInfo[NSUnderlyingErrorKey];
  if (self.retry && ![cause.userInfo[@"detail"] isEqual:@"handler-detail"]) return 999;
  return 7;
}
@end

@interface JobWorkerLifetimeTests : XCTestCase
@end
@implementation JobWorkerLifetimeTests
- (void)testScratchFixtureRemainsLiveUntilPoolDrains {
  JWLLifetimeCounter *counter = [JWLLifetimeCounter new];
  @autoreleasepool {
    JWLMakeAutoreleasedScratch(counter);
    XCTAssertEqual((NSUInteger)1, counter.live, @"fixture must create a pending autorelease");
  }
  XCTAssertEqual((NSUInteger)0, counter.live);
}

- (JWLRuntime *)runtimeForAdapter:(JWLAdapter *)adapter {
  JWLRuntime *runtime = [JWLRuntime new];
  runtime.counter = [JWLLifetimeCounter new];
  runtime.adapter = adapter;
  return runtime;
}
- (void)checkBatchWithRetry:(BOOL)retry throwFirst:(BOOL)throwFirst {
  JWLAdapter *adapter = [JWLAdapter new];
  adapter.durable = retry;
  [adapter addJobs:4];
  JWLRuntime *runtime = [self runtimeForAdapter:adapter];
  runtime.retry = retry;
  runtime.throwFirst = throwFirst;
  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:adapter];
  worker.maxJobsPerRun = 4;
  NSDate *runAt = [NSDate dateWithTimeIntervalSince1970:100];
  ALNJobWorkerRunSummary *summary = nil;
  @autoreleasepool {
    NSError *error = nil;
    summary = [worker runDueJobsAt:runAt runtime:runtime error:&error];
    XCTAssertNotNil(summary);
    XCTAssertNil(error);
    XCTAssertEqual((NSUInteger)0, runtime.maximumPreviousScratch, @"previous handler scratch survived to the next handler");
    XCTAssertEqual((NSUInteger)0, runtime.counter.live, @"last handler scratch survived worker return");
  }
  XCTAssertEqual((NSUInteger)0, runtime.counter.live);
  XCTAssertEqual((NSUInteger)4, summary.leasedCount);
  XCTAssertEqual(retry ? (NSUInteger)0 : (throwFirst ? (NSUInteger)3 : (NSUInteger)4), summary.acknowledgedCount);
  XCTAssertEqual(retry ? (NSUInteger)4 : (throwFirst ? (NSUInteger)1 : (NSUInteger)0), summary.retriedCount);
  XCTAssertEqual(summary.retriedCount, summary.handlerErrorCount);
  XCTAssertTrue(summary.reachedRunLimit);
  for (NSDate *timestamp in adapter.dequeueTimes) XCTAssertTrue(timestamp == runAt);
  if (retry) {
    XCTAssertEqual((NSTimeInterval)7, adapter.retryDelay);
    XCTAssertEqualObjects(@"handler-failure", adapter.failureMessage);
  }
}
- (void)testAcknowledgedBatchDrainsEachHandlerAndLastHandler { [self checkBatchWithRetry:NO throwFirst:NO]; }
- (void)testRetriedBatchDrainsEachHandlerAndPreservesRetryError { [self checkBatchWithRetry:YES throwFirst:NO]; }
- (void)testPoisonHandlerDrainsAndLaterJobsStillRun { [self checkBatchWithRetry:NO throwFirst:YES]; }

- (void)checkFatalStage:(NSString *)stage durable:(BOOL)durable code:(NSInteger)code {
  JWLAdapter *adapter = [JWLAdapter new];
  adapter.durable = durable;
  adapter.failureStage = stage;
  [adapter addJobs:2];
  JWLRuntime *runtime = [self runtimeForAdapter:adapter];
  runtime.retry = [stage isEqualToString:@"retry"];
  runtime.waitForHeartbeat = [stage isEqualToString:@"heartbeat"];
  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:adapter];
  NSError *error = nil;
  @autoreleasepool {
    XCTAssertNil([worker runDueJobsAt:nil runtime:runtime error:&error]);
  }
  XCTAssertEqualObjects(ALNServiceErrorDomain, error.domain);
  XCTAssertEqual(code, error.code);
  NSError *cause = error.userInfo[NSUnderlyingErrorKey];
  XCTAssertEqualObjects(@"JWL.Adapter", cause.domain);
  XCTAssertEqualObjects([stage stringByAppendingString:@"-failure"], cause.localizedDescription);
  NSError *leaf = cause.userInfo[NSUnderlyingErrorKey];
  XCTAssertEqualObjects([stage stringByAppendingString:@"-detail"], leaf.userInfo[@"detail"]);
  XCTAssertEqual((NSUInteger)0, runtime.counter.live);
  XCTAssertEqual((NSUInteger)0, adapter.completed);
  if (runtime.waitForHeartbeat) XCTAssertTrue(runtime.observedHeartbeat);
}
- (void)testDequeueErrorSurvivesPoolDrain { [self checkFatalStage:@"dequeue" durable:NO code:502]; }
- (void)testAcknowledgeErrorSurvivesPoolDrain { [self checkFatalStage:@"ack" durable:NO code:503]; }
- (void)testCompletionErrorSurvivesPoolDrain { [self checkFatalStage:@"complete" durable:YES code:503]; }
- (void)testRetryErrorSurvivesPoolDrain { [self checkFatalStage:@"retry" durable:NO code:504]; }
- (void)testDurableRetryErrorSurvivesPoolDrain { [self checkFatalStage:@"retry" durable:YES code:504]; }
- (void)testHeartbeatFailureIsJoinedAndPreventsCompletion { [self checkFatalStage:@"heartbeat" durable:YES code:505]; }

- (void)testHeartbeatSuccessAndCompletionResultSurvivePoolDrain {
  JWLAdapter *adapter = [JWLAdapter new];
  adapter.durable = YES;
  [adapter addJobs:1];
  JWLRuntime *runtime = [self runtimeForAdapter:adapter];
  runtime.waitForHeartbeat = YES;
  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:adapter];
  ALNJobWorkerRunSummary *summary = nil;
  @autoreleasepool {
    NSError *error = nil;
    summary = [worker runDueJobsAt:nil runtime:runtime error:&error];
    XCTAssertNotNil(summary);
    XCTAssertNil(error);
  }
  XCTAssertTrue(runtime.observedHeartbeat);
  XCTAssertEqual((NSUInteger)1, adapter.completed);
  XCTAssertEqualObjects((@{ @"job" : @"job-0-result", @"nested" : @[@1, @2] }), adapter.completedResult);
  XCTAssertEqual((NSUInteger)1, summary.acknowledgedCount);
  XCTAssertFalse(summary.reachedRunLimit);
  XCTAssertEqual((NSUInteger)0, runtime.counter.live);
}

- (void)testEmptyAndLimitedSummariesSurvivePoolDrain {
  JWLAdapter *adapter = [JWLAdapter new];
  JWLRuntime *runtime = [self runtimeForAdapter:adapter];
  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:adapter];
  ALNJobWorkerRunSummary *empty = nil;
  ALNJobWorkerRunSummary *limited = nil;
  @autoreleasepool {
    empty = [worker runDueJobsAt:nil runtime:runtime error:NULL];
    [adapter addJobs:2];
    worker.maxJobsPerRun = 1;
    limited = [worker runDueJobsAt:nil runtime:runtime error:NULL];
  }
  XCTAssertEqual((NSUInteger)0, empty.leasedCount);
  XCTAssertFalse(empty.reachedRunLimit);
  XCTAssertEqual((NSUInteger)1, limited.leasedCount);
  XCTAssertTrue(limited.reachedRunLimit);
  XCTAssertEqual((NSUInteger)1, [adapter.jobs count]);
}

- (void)testFatalErrorsAcceptNullOutput {
  for (NSString *stage in @[@"dequeue", @"ack", @"retry", @"complete", @"heartbeat"]) {
    JWLAdapter *adapter = [JWLAdapter new];
    adapter.failureStage = stage;
    adapter.durable = [@[@"complete", @"heartbeat"] containsObject:stage];
    [adapter addJobs:1];
    JWLRuntime *runtime = [self runtimeForAdapter:adapter];
    runtime.retry = [stage isEqualToString:@"retry"];
    runtime.waitForHeartbeat = [stage isEqualToString:@"heartbeat"];
    ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:adapter];
    @autoreleasepool { XCTAssertNil([worker runDueJobsAt:nil runtime:runtime error:NULL]); }
    if (runtime.waitForHeartbeat) XCTAssertTrue(runtime.observedHeartbeat);
    XCTAssertEqual((NSUInteger)0, adapter.completed);
  }
}
@end
