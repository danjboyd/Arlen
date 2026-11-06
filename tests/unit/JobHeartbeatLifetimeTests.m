#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNServices.h"

@protocol JHBSubject <NSObject>
@property(nonatomic, strong) NSCondition *condition;
@property(nonatomic, strong) id adapter;
@property(nonatomic, strong) ALNJobLease *job;
@property(nonatomic, strong) NSError *failure;
@property(nonatomic, assign) BOOL stopping;
@property(nonatomic, assign) BOOL finished;
- (void)run;
- (NSError *)stop;
@end

static void JHBCheck(NSMutableArray *failures, BOOL ok, NSString *message) { if (!ok) [failures addObject:message]; }

@interface JHBCounter : NSObject
@property(nonatomic, strong) NSCondition *gate;
@property(nonatomic, assign) NSUInteger live;
@property(nonatomic, assign) BOOL blockDrain;
@property(nonatomic, assign) BOOL drainEntered;
@property(nonatomic, assign) BOOL drainReleased;
@property(nonatomic, assign) BOOL timedOut;
- (void)created;
- (void)retired;
- (NSUInteger)liveCount;
- (BOOL)awaitDrain;
- (void)releaseDrain;
@end
@implementation JHBCounter
- (instancetype)init { self = [super init]; if (self) _gate = [NSCondition new]; return self; }
- (void)created { [self.gate lock]; self.live++; [self.gate unlock]; }
- (void)retired {
  [self.gate lock];
  if (self.blockDrain && !self.drainEntered) {
    self.drainEntered = YES;
    [self.gate broadcast];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!self.drainReleased && [deadline timeIntervalSinceNow] > 0) [self.gate waitUntilDate:deadline];
    self.timedOut = !self.drainReleased;
  }
  self.live--;
  [self.gate unlock];
}
- (NSUInteger)liveCount { [self.gate lock]; NSUInteger value = self.live; [self.gate unlock]; return value; }
- (BOOL)awaitDrain {
  [self.gate lock];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!self.drainEntered && [deadline timeIntervalSinceNow] > 0) [self.gate waitUntilDate:deadline];
  BOOL entered = self.drainEntered;
  [self.gate unlock];
  return entered;
}
- (void)releaseDrain { [self.gate lock]; self.drainReleased = YES; [self.gate broadcast]; [self.gate unlock]; }
@end

@interface JHBProbe : NSObject
@property(nonatomic, strong) JHBCounter *counter;
- (instancetype)initWithCounter:(JHBCounter *)counter;
@end
@implementation JHBProbe
- (instancetype)initWithCounter:(JHBCounter *)counter {
  self = [super init]; if (self) { _counter = counter; [counter created]; } return self;
}
- (void)dealloc { [_counter retired]; }
@end

// A real pending autorelease, not optimized away by an ARC return-value claim.
__attribute__((noinline)) static void ProduceScratch(JHBCounter *counter) {
  JHBProbe *probe = [[JHBProbe alloc] initWithCounter:counter];
  void *pending = (__bridge_retained void *)probe;
  SEL selector = NSSelectorFromString(@"autorelease");
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[probe methodSignatureForSelector:selector]];
  invocation.target = (__bridge id)pending;
  invocation.selector = selector;
  [invocation invoke];
}

// Track temporaries created during deadline preparation, not just in renewJob.
@interface JHBLeaseFixture : ALNJobLease
@property(nonatomic, strong) JHBCounter *deadlineCounter;
@property(nonatomic, strong) NSCondition *deadlineGate;
@property(nonatomic, assign) BOOL deadlineObserved;
@end
@implementation JHBLeaseFixture
- (NSTimeInterval)leaseDurationSeconds {
  if (self.deadlineCounter) ProduceScratch(self.deadlineCounter);
  if (self.deadlineGate) {
    [self.deadlineGate lock]; self.deadlineObserved = YES;
    [self.deadlineGate broadcast]; [self.deadlineGate unlock];
  }
  return [super leaseDurationSeconds];
}
@end

@interface JHBAdapter : NSObject
@property(nonatomic, strong) JHBCounter *counter;
@property(nonatomic, strong) NSCondition *gate;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *previousLive;
@property(nonatomic, assign) NSUInteger calls;
@property(nonatomic, assign) NSUInteger checkpoint;
@property(nonatomic, assign) BOOL pooled;
@property(nonatomic, assign) BOOL failRenewal;
@property(nonatomic, assign) BOOL omitError;
@property(nonatomic, assign) BOOL released;
@property(nonatomic, assign) BOOL timedOut;
- (BOOL)renewJob:(id)job error:(NSError **)error;
- (BOOL)awaitCheckpoint;
- (void)releaseCallback;
@end
@implementation JHBAdapter
- (instancetype)init {
  self = [super init];
  if (self) { _gate = [NSCondition new]; _previousLive = [NSMutableArray array]; _checkpoint = 4; }
  return self;
}
- (BOOL)renewJob:(id)job error:(NSError **)error {
  (void)job;
  NSUInteger previous = [self.counter liveCount];
  if (self.pooled) { @autoreleasepool { ProduceScratch(self.counter); } }
  else { ProduceScratch(self.counter); }
  NSError *failure = nil;
  if (self.failRenewal && !self.omitError) {
    NSError *cause = [NSError errorWithDomain:@"HB.Cause" code:72 userInfo:@{@"token":@"renewal-error-survives"}];
    failure = [NSError errorWithDomain:@"HB.Fixture" code:73 userInfo:@{NSUnderlyingErrorKey:cause}];
  }
  [self.gate lock];
  [self.previousLive addObject:@(previous)];
  self.calls++;
  if (self.calls >= self.checkpoint) {
    [self.gate broadcast];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!self.released && [deadline timeIntervalSinceNow] > 0) [self.gate waitUntilDate:deadline];
    self.timedOut = !self.released;
  }
  BOOL fail = self.failRenewal && self.calls >= self.checkpoint;
  [self.gate unlock];
  if (fail && error) *error = failure;
  return !fail;
}
- (BOOL)awaitCheckpoint {
  [self.gate lock];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (self.calls < self.checkpoint && [deadline timeIntervalSinceNow] > 0) [self.gate waitUntilDate:deadline];
  BOOL reached = self.calls == self.checkpoint;
  [self.gate unlock];
  return reached;
}
- (void)releaseCallback { [self.gate lock]; self.released = YES; [self.gate broadcast]; [self.gate unlock]; }
@end

// The driver marks returned only after the subject's actual outer pool drains.
// The stopper independently observes the subject's stop/finished contract.
@interface JHBThreadCall : NSObject
@property(nonatomic, strong) id<JHBSubject> subject;
@property(nonatomic, strong) NSCondition *gate;
@property(nonatomic, assign) BOOL stopCall;
@property(nonatomic, assign) BOOL returned;
@property(nonatomic, strong) NSError *error;
- (void)execute;
- (BOOL)awaitReturn;
- (BOOL)hasReturned;
@end
@implementation JHBThreadCall
- (instancetype)init { self = [super init]; if (self) _gate = [NSCondition new]; return self; }
- (void)execute {
  @autoreleasepool {
    if (self.stopCall) self.error = [self.subject stop];
    else [self.subject run];
  }
  [self.gate lock]; self.returned = YES; [self.gate broadcast]; [self.gate unlock];
}
- (BOOL)awaitReturn {
  [self.gate lock];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!self.returned && [deadline timeIntervalSinceNow] > 0) [self.gate waitUntilDate:deadline];
  BOOL done = self.returned; [self.gate unlock]; return done;
}
- (BOOL)hasReturned { [self.gate lock]; BOOL done = self.returned; [self.gate unlock]; return done; }
@end

static NSDictionary *Scenario(NSString *name, BOOL pooled, BOOL fail, BOOL omitError, BOOL blockDrain, BOOL deadlineScratch) {
  NSMutableArray *failures = [NSMutableArray array];
  JHBCheck(failures, [ALNJobWorker class] != Nil, @"framework worker linked");
  JHBCounter *counter = [JHBCounter new];
  JHBAdapter *adapter = [JHBAdapter new]; adapter.counter = counter; adapter.pooled = pooled;
  adapter.failRenewal = fail; adapter.omitError = omitError;
  id<JHBSubject> subject = (id)[NSClassFromString(@"ALNJobHeartbeat") new];
  JHBCheck(failures, subject != nil, @"actual framework heartbeat class loaded");
  ALNJobEnvelope *envelope = [[ALNJobEnvelope alloc] initWithJobID:@"heartbeat-fixture"
      name:@"lifetime" payload:@{} attempt:1 maxAttempts:2 notBefore:[NSDate date]
      createdAt:[NSDate date] sequence:1];
  JHBLeaseFixture *lease = [[JHBLeaseFixture alloc] initWithEnvelope:envelope
      leaseToken:@"heartbeat-claim" leaseExpiresAt:[NSDate dateWithTimeIntervalSinceNow:30]
      leaseDurationSeconds:0.009];
  JHBCounter *deadlineCounter = [JHBCounter new];
  if (deadlineScratch) lease.deadlineCounter = deadlineCounter;
  subject.adapter = adapter; subject.job = lease;
  JHBThreadCall *driver = [JHBThreadCall new]; driver.subject = subject;
  [[[NSThread alloc] initWithTarget:driver selector:@selector(execute) object:nil] start];
  BOOL checkpoint = [adapter awaitCheckpoint];
  JHBCheck(failures, checkpoint, [name stringByAppendingString:@": reached renewal checkpoint"]);
  NSUInteger liveAtCheckpoint = [counter liveCount];
  JHBCheck(failures, liveAtCheckpoint == (pooled ? 0 : 1), [name stringByAppendingString:@": expected retained scratch count"]);
  NSArray *expected = @[@0,@0,@0,@0];
  JHBCheck(failures, [adapter.previousLive isEqual:expected], [name stringByAppendingString:@": previous-renewal scratch sequence"]);
  if (deadlineScratch) JHBCheck(failures, [deadlineCounter liveCount] == 1,
      @"only the current cycle's deadline scratch can remain live");
  counter.blockDrain = blockDrain;
  JHBThreadCall *stopper = [JHBThreadCall new]; stopper.subject = subject; stopper.stopCall = YES;
  [[[NSThread alloc] initWithTarget:stopper selector:@selector(execute) object:nil] start];
  [subject.condition lock];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!subject.stopping && [deadline timeIntervalSinceNow] > 0) [subject.condition waitUntilDate:deadline];
  BOOL stopping = subject.stopping;
  BOOL finishedBeforeCallbackReturn = subject.finished;
  [subject.condition unlock];
  JHBCheck(failures, stopping && !finishedBeforeCallbackReturn, [name stringByAppendingString:@": stop waits for in-flight renewal"]);
  JHBCheck(failures, ![stopper hasReturned], [name stringByAppendingString:@": stop cannot return before renewal callback"]);
  [adapter releaseCallback];
  if (blockDrain) {
    JHBCheck(failures, [counter awaitDrain], @"scratch destructor reached deterministic drain gate");
    // This lock must be available while destruction is blocked: draining under
    // the heartbeat lock would prevent stop from requesting/waiting safely.
    [subject.condition lock];
    BOOL prematureFinished = subject.finished;
    [subject.condition unlock];
    JHBCheck(failures, !prematureFinished, @"finished must be published after scratch destruction");
    JHBCheck(failures, ![stopper hasReturned], @"stop must wait until scratch destruction completes");
    [counter releaseDrain];
  }
  JHBCheck(failures, [stopper awaitReturn], [name stringByAppendingString:@": stop returns"]);
  JHBCheck(failures, [driver awaitReturn], [name stringByAppendingString:@": heartbeat run returns after pool drainage"]);
  JHBCheck(failures, [counter liveCount] == 0 && !counter.timedOut && !adapter.timedOut, [name stringByAppendingString:@": scratch fully released without timeout"]);
  JHBCheck(failures, [deadlineCounter liveCount] == 0, @"deadline scratch drains before heartbeat return");
  JHBCheck(failures, adapter.calls == 4, [name stringByAppendingString:@": no renewals after stop"]);
  if (fail && !omitError) {
    NSError *cause = stopper.error.userInfo[NSUnderlyingErrorKey];
    JHBCheck(failures, [stopper.error.domain isEqual:@"HB.Fixture"] && stopper.error.code == 73 &&
          [cause.userInfo[@"token"] isEqual:@"renewal-error-survives"], @"nested renewal error survives heartbeat pool drain");
  } else if (fail) {
    JHBCheck(failures, [stopper.error.domain isEqual:ALNServiceErrorDomain] && stopper.error.code == 505,
          @"missing renewal error produces retained fallback505");
  } else {
    JHBCheck(failures, stopper.error == nil, @"successful renewal/stop has no error");
  }
  JHBCheck(failures, [subject stop] == stopper.error, @"repeated stop preserves failure result");
  return @{ @"name":name, @"adapterScratchPool":@(pooled), @"renewals":@(adapter.calls),
            @"previousLive":adapter.previousLive, @"liveDuringRenewal":@(liveAtCheckpoint),
            @"liveAfterRunReturned":@([counter liveCount]), @"failures":failures,
            @"errorDomain":stopper.error.domain ?: @"", @"errorCode":@(stopper.error.code) };
}


@interface JobHeartbeatLifetimeTests : XCTestCase
@end
@implementation JobHeartbeatLifetimeTests
- (void)checkScenario:(NSString *)name pooled:(BOOL)pooled fail:(BOOL)fail
           omitError:(BOOL)omitError drainGate:(BOOL)drainGate deadlineScratch:(BOOL)deadlineScratch {
  NSDictionary *result = Scenario(name, pooled, fail, omitError, drainGate, deadlineScratch);
  XCTAssertEqual((NSUInteger)0, [result[@"failures"] count], @"%@", result[@"failures"]);
}
- (void)testScratchFixtureCreatesPendingAutorelease {
  JHBCounter *counter = [JHBCounter new];
  @autoreleasepool { ProduceScratch(counter); XCTAssertEqual((NSUInteger)1, [counter liveCount]); }
  XCTAssertEqual((NSUInteger)0, [counter liveCount]);
}
- (void)testRenewalScratchDrainsBeforeNextCycle {
  [self checkScenario:@"renewal cycles" pooled:NO fail:NO omitError:NO drainGate:NO deadlineScratch:NO];
}
- (void)testAdapterLocalPoolControlRemainsBounded {
  [self checkScenario:@"adapter pool control" pooled:YES fail:NO omitError:NO drainGate:NO deadlineScratch:NO];
}
- (void)testDeadlinePreparationScratchDrainsEachCycle {
  [self checkScenario:@"deadline cycles" pooled:YES fail:NO omitError:NO drainGate:NO deadlineScratch:YES];
}
- (void)testNestedRenewalErrorSurvivesDrainAndRepeatedStop {
  [self checkScenario:@"nested error" pooled:NO fail:YES omitError:NO drainGate:NO deadlineScratch:NO];
}
- (void)testFallback505SurvivesDrainAndRepeatedStop {
  [self checkScenario:@"fallback error" pooled:NO fail:YES omitError:YES drainGate:NO deadlineScratch:NO];
}
- (void)testAdapterPooledNestedErrorSurvivesCleanup {
  [self checkScenario:@"pooled nested error" pooled:YES fail:YES omitError:NO drainGate:NO deadlineScratch:NO];
}
- (void)testAdapterPooledFallbackErrorSurvivesCleanup {
  [self checkScenario:@"pooled fallback error" pooled:YES fail:YES omitError:YES drainGate:NO deadlineScratch:NO];
}
- (void)testStopWakesLongDeadlineWithoutRenewal {
  XCTAssertNotNil([ALNJobWorker class]);
  id<JHBSubject> subject = (id)[NSClassFromString(@"ALNJobHeartbeat") new];
  XCTAssertNotNil(subject);
  JHBAdapter *adapter = [JHBAdapter new]; adapter.counter = [JHBCounter new];
  ALNJobEnvelope *envelope = [[ALNJobEnvelope alloc] initWithJobID:@"waiting"
      name:@"lifetime" payload:@{} attempt:1 maxAttempts:2 notBefore:[NSDate date]
      createdAt:[NSDate date] sequence:1];
  JHBLeaseFixture *lease = [[JHBLeaseFixture alloc] initWithEnvelope:envelope
      leaseToken:@"waiting-claim" leaseExpiresAt:[NSDate dateWithTimeIntervalSinceNow:7200]
      leaseDurationSeconds:3600];
  lease.deadlineCounter = [JHBCounter new]; lease.deadlineGate = [NSCondition new];
  subject.adapter = adapter; subject.job = lease;
  JHBThreadCall *driver = [JHBThreadCall new]; driver.subject = subject;
  [[[NSThread alloc] initWithTarget:driver selector:@selector(execute) object:nil] start];
  [lease.deadlineGate lock];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!lease.deadlineObserved && [deadline timeIntervalSinceNow] > 0)
    [lease.deadlineGate waitUntilDate:deadline];
  BOOL observed = lease.deadlineObserved;
  [lease.deadlineGate unlock];
  JHBThreadCall *stopper = [JHBThreadCall new]; stopper.subject = subject; stopper.stopCall = YES;
  [[[NSThread alloc] initWithTarget:stopper selector:@selector(execute) object:nil] start];
  BOOL stopped = [stopper awaitReturn];
  if (!stopped) {
    // Bound failure cleanup even if the implementation forgets the stop wakeup.
    [subject.condition lock]; subject.stopping = YES;
    [subject.condition broadcast]; [subject.condition unlock];
  }
  BOOL returned = [driver awaitReturn];
  XCTAssertTrue(observed);
  XCTAssertTrue(stopped);
  XCTAssertTrue(returned);
  XCTAssertNil(stopper.error);
  XCTAssertEqual((NSUInteger)0, adapter.calls);
  XCTAssertEqual((NSUInteger)0, [lease.deadlineCounter liveCount]);
}
- (void)testStopWaitsForCallbackAndFinalDestructorOutsideLock {
  [self checkScenario:@"drain ordering" pooled:NO fail:NO omitError:NO drainGate:YES deadlineScratch:NO];
}
@end
