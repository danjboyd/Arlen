#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNEventStream.h"
#import "ALNPgEventStream.h"

// GitHub issue 48, part 2: PostgreSQL event stream store and broker.
@interface PgEventStreamRecorder : NSObject <ALNEventStreamLiveSubscriber>
@property(nonatomic, strong) NSMutableArray<ALNEventEnvelope *> *events;
@property(nonatomic, strong) NSCondition *arrived;
@end

@implementation PgEventStreamRecorder
- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _events = [NSMutableArray array];
    _arrived = [[NSCondition alloc] init];
  }
  return self;
}
- (void)receiveCommittedEvent:(ALNEventEnvelope *)event onStream:(NSString *)streamID {
  [self.arrived lock];
  [self.events addObject:event];
  [self.arrived broadcast];
  [self.arrived unlock];
}
- (BOOL)waitForCount:(NSUInteger)count timeout:(NSTimeInterval)timeout {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  [self.arrived lock];
  while ([self.events count] < count && [self.arrived waitUntilDate:deadline]) {
  }
  BOOL reached = [self.events count] >= count;
  [self.arrived unlock];
  return reached;
}
- (NSUInteger)count {
  [self.arrived lock];
  NSUInteger count = [self.events count];
  [self.arrived unlock];
  return count;
}
@end

@interface PgEventStreamTests : XCTestCase
@property(nonatomic, copy) NSString *dsn;
@property(nonatomic, copy) NSString *table;
@end

@implementation PgEventStreamTests

- (void)setUp {
  [super setUp];
  const char *dsn = getenv("ARLEN_PG_TEST_DSN");
  self.dsn = (dsn != NULL && dsn[0] != '\0') ? [NSString stringWithUTF8String:dsn] : nil;
  self.table = [NSString stringWithFormat:@"arlen_evs_test_%u", arc4random_uniform(1000000000)];
}

- (ALNPgEventStreamStore *)store {
  NSError *error = nil;
  ALNPgEventStreamStore *store = [[ALNPgEventStreamStore alloc] initWithConnectionString:self.dsn
                                                                               tableName:self.table
                                                                          maxConnections:2
                                                                                   error:&error];
  XCTAssertNotNil(store, @"%@", error);
  return store;
}

- (void)testEnvelopeDictionaryRoundTripAndValidation {
  ALNEventEnvelope *envelope = [[ALNEventEnvelope alloc] initWithStreamID:@"Orders-A"
                                                                 sequence:4
                                                                  eventID:@"evt_1"
                                                                eventType:@"order.paid"
                                                               occurredAt:@"2026-09-27T00:00:00Z"
                                                                  payload:@{ @"total" : @12 }
                                                           idempotencyKey:@"pay-1"
                                                                    actor:@{ @"sub" : @"u1" }
                                                                 metadata:nil];
  ALNEventEnvelope *decoded = [ALNEventEnvelope envelopeWithDictionary:[envelope dictionaryRepresentation]];
  XCTAssertEqualObjects([envelope dictionaryRepresentation], [decoded dictionaryRepresentation]);
  XCTAssertNil([ALNEventEnvelope envelopeWithDictionary:@{ @"stream_id" : @"x" }]);

  NSError *error = nil;
  XCTAssertNil([[ALNPgEventStreamStore alloc] initWithConnectionString:@"host=127.0.0.1 port=1"
                                                             tableName:@"bad-name; drop"
                                                        maxConnections:1
                                                                 error:&error]);
  XCTAssertEqual(ALNEventStreamErrorInvalidArgument, error.code);
}

- (void)testStoreAppendReplayCursorAndIdempotency {
  if (self.dsn == nil) {
    return;  // Needs PostgreSQL; CI sets ARLEN_PG_TEST_DSN.
  }
  ALNPgEventStreamStore *store = [self store];
  NSError *error = nil;
  XCTAssertNil([store latestCursorForStream:@"Orders-A" error:&error]);
  XCTAssertNil(error);
  for (NSUInteger i = 1; i <= 3; i++) {
    ALNEventEnvelope *event = [store appendEvent:@{ @"event_type" : @"order.updated", @"payload" : @{ @"n" : @(i) },
                                                    @"actor" : @{ @"sub" : @"u1" }, @"metadata" : @{ @"source" : @"test" } }
                                        toStream:@"Orders-A"
                                           error:&error];
    XCTAssertEqual(i, event.sequence, @"%@", error);
  }
  // Stream identifiers are case-sensitive.
  NSDictionary *lowercaseEvent = @{ @"event_type" : @"x", @"payload" : @{} };
  XCTAssertEqual((NSUInteger)1, [store appendEvent:lowercaseEvent toStream:@"orders-a" error:&error].sequence);

  NSArray<ALNEventEnvelope *> *replay = [store eventsForStream:@"Orders-A" afterSequence:@1 limit:10 error:&error];
  XCTAssertEqual((NSUInteger)2, [replay count], @"%@", error);
  XCTAssertEqualObjects(@3, replay[1].payload[@"n"]);
  XCTAssertEqualObjects(@"u1", replay[0].actor[@"sub"]);
  XCTAssertEqualObjects(@"test", replay[0].metadata[@"source"]);
  XCTAssertEqual((NSUInteger)3, [store latestCursorForStream:@"Orders-A" error:&error].sequence);

  NSDictionary *paid = @{ @"event_type" : @"order.paid", @"payload" : @{ @"total" : @12 }, @"idempotency_key" : @"pay-1" };
  ALNEventEnvelope *first = [store appendEvent:paid toStream:@"Orders-A" error:&error];
  ALNEventEnvelope *again = [store appendEvent:paid toStream:@"Orders-A" error:&error];
  XCTAssertEqual((NSUInteger)4, first.sequence);
  XCTAssertEqualObjects(first.eventID, again.eventID);
  XCTAssertEqual((NSUInteger)4, [store latestCursorForStream:@"Orders-A" error:&error].sequence);
  NSDictionary *conflicting = @{ @"event_type" : @"order.paid", @"payload" : @{ @"total" : @13 }, @"idempotency_key" : @"pay-1" };
  XCTAssertNil([store appendEvent:conflicting toStream:@"Orders-A" error:&error]);
  XCTAssertEqual(ALNEventStreamErrorIdempotencyConflict, error.code);

  XCTAssertNil([store appendEvent:@{ @"payload" : @{} } toStream:@"Orders-A" error:&error]);
  XCTAssertEqual(ALNEventStreamErrorInvalidEnvelope, error.code);
}

- (void)testConcurrentWorkersNeverShareASequence {
  if (self.dsn == nil) {
    return;
  }
  ALNPgEventStreamStore *workerA = [self store];
  ALNPgEventStreamStore *workerB = [self store];
  dispatch_group_t group = dispatch_group_create();
  for (ALNPgEventStreamStore *store in @[ workerA, workerB ]) {
    for (NSUInteger i = 0; i < 20; i++) {
      dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSDictionary *tick = @{ @"event_type" : @"tick", @"payload" : @{} };
        XCTAssertNotNil([store appendEvent:tick toStream:@"shared" error:&error], @"%@", error);
      });
    }
  }
  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
  NSError *error = nil;
  NSArray<ALNEventEnvelope *> *events = [workerA eventsForStream:@"shared" afterSequence:nil limit:100 error:&error];
  XCTAssertEqual((NSUInteger)40, [events count], @"%@", error);
  for (NSUInteger i = 0; i < [events count]; i++) {
    XCTAssertEqual(i + 1, events[i].sequence);
  }
}

- (void)testBrokerDeliversAcrossProcessesAndServiceReportsResync {
  if (self.dsn == nil) {
    return;
  }
  NSString *channel = [NSString stringWithFormat:@"arlen_evs_chan_%u", arc4random_uniform(1000000000)];
  NSError *error = nil;
  ALNPgEventStreamBroker *brokerA = [[ALNPgEventStreamBroker alloc] initWithConnectionString:self.dsn notifyChannel:channel error:&error];
  ALNPgEventStreamBroker *brokerB = [[ALNPgEventStreamBroker alloc] initWithConnectionString:self.dsn notifyChannel:channel error:&error];
  XCTAssertNotNil(brokerA, @"%@", error);
  XCTAssertNotNil(brokerB, @"%@", error);
  @try {
    PgEventStreamRecorder *onA = [[PgEventStreamRecorder alloc] init];
    PgEventStreamRecorder *onB = [[PgEventStreamRecorder alloc] init];
    XCTAssertNotNil([brokerA subscribeToStream:@"Orders-A" subscriber:onA error:&error]);
    ALNEventStreamBrokerSubscription *subscriptionB = [brokerB subscribeToStream:@"Orders-A" subscriber:onB error:&error];
    XCTAssertNotNil(subscriptionB);
    ALNEventStreamService *service = [[ALNEventStreamService alloc] initWithStore:[self store] broker:brokerA];
    NSDictionary *paid = @{ @"event_type" : @"order.paid", @"payload" : @{ @"total" : @12 } };
    ALNEventStreamAppendResult *appended = [service appendEvent:paid toStream:@"Orders-A" error:&error];
    XCTAssertTrue(appended.livePublishSucceeded, @"%@", error);
    XCTAssertTrue([onB waitForCount:1 timeout:5.0]);
    XCTAssertEqualObjects([appended.committedEvent dictionaryRepresentation], [onB.events[0] dictionaryRepresentation]);
    // sleep-ok: gives a wrongly echoed copy time to arrive before checking it didn't.
    [NSThread sleepForTimeInterval:0.5];
    XCTAssertEqual((NSUInteger)1, [onA count], @"the publishing process gets one copy");

    [brokerB unsubscribe:subscriptionB];
    for (NSUInteger i = 0; i < 12; i++) {
      [service appendEvent:@{ @"event_type" : @"tick", @"payload" : @{} } toStream:@"Orders-A" error:&error];
    }
    ALNEventStreamReplayResult *stale = [service replayStream:@"Orders-A" afterSequence:@1 limit:5 replayWindow:5 error:&error];
    XCTAssertTrue(stale.resyncRequired, @"%@", [stale dictionaryRepresentation]);
    ALNEventStreamReplayResult *fresh = [service replayStream:@"Orders-A" afterSequence:@10 limit:5 replayWindow:5 error:&error];
    XCTAssertFalse(fresh.resyncRequired, @"%@", [fresh dictionaryRepresentation]);
    XCTAssertEqual((NSUInteger)3, [fresh.events count]);
  } @finally {
    [brokerA stop];
    [brokerB stop];
  }
}

@end
