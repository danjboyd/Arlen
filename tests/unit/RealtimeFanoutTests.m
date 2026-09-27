#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNPg.h"
#import "ALNPgRealtimeFanout.h"
#import "ALNRealtime.h"

// GitHub issue 48: cross-process fanout for ALNRealtimeHub.
@interface RealtimeFanoutRecorder : NSObject <ALNRealtimeSubscriber>
@property(nonatomic, strong) NSMutableArray<NSString *> *messages;
@property(nonatomic, strong) NSCondition *arrived;
@end

@implementation RealtimeFanoutRecorder
- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _messages = [NSMutableArray array];
    _arrived = [[NSCondition alloc] init];
  }
  return self;
}
- (void)receiveRealtimeMessage:(NSString *)message onChannel:(NSString *)channel {
  [self.arrived lock];
  [self.messages addObject:[NSString stringWithFormat:@"%@:%@", channel, message]];
  [self.arrived broadcast];
  [self.arrived unlock];
}
- (BOOL)waitForCount:(NSUInteger)count timeout:(NSTimeInterval)timeout {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  [self.arrived lock];
  while ([self.messages count] < count && [self.arrived waitUntilDate:deadline]) {
  }
  BOOL reached = [self.messages count] >= count;
  [self.arrived unlock];
  return reached;
}
- (NSArray<NSString *> *)snapshot {
  [self.arrived lock];
  NSArray *copy = [self.messages copy];
  [self.arrived unlock];
  return copy;
}
@end

@interface RealtimeFakeFanout : NSObject <ALNRealtimeFanout>
@property(nonatomic, strong) NSMutableArray<NSString *> *published;
@property(nonatomic, assign) BOOL stopped;
@property(nonatomic, assign) BOOL raises;
@end

@implementation RealtimeFakeFanout
- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _published = [NSMutableArray array];
  }
  return self;
}
- (void)hub:(ALNRealtimeHub *)hub didPublishMessage:(NSString *)message onChannel:(NSString *)channel {
  [self.published addObject:[NSString stringWithFormat:@"%@:%@", channel, message]];
  if (self.raises) {
    [NSException raise:@"FakeFanout" format:@"backend down"];
  }
}
- (void)stop {
  self.stopped = YES;
}
@end

@interface RealtimeFanoutTests : XCTestCase
@end

@implementation RealtimeFanoutTests

- (void)testPublishDeliversLocallyAndHandsOffWhileRemoteDeliveryDoesNot {
  ALNRealtimeHub *hub = [[ALNRealtimeHub alloc] init];
  RealtimeFanoutRecorder *recorder = [[RealtimeFanoutRecorder alloc] init];
  XCTAssertNotNil([hub subscribeChannel:@"records.7" subscriber:recorder]);
  RealtimeFakeFanout *fanout = [[RealtimeFakeFanout alloc] init];
  hub.fanout = fanout;

  XCTAssertEqual((NSUInteger)1, [hub publishMessage:@"hello" onChannel:@"records.7"]);
  XCTAssertEqualObjects(@[ @"records.7:hello" ], fanout.published);
  XCTAssertEqual((NSUInteger)1, [hub deliverRemoteMessage:@"from-elsewhere" onChannel:@"records.7"]);
  XCTAssertEqual((NSUInteger)1, [fanout.published count], @"remote deliveries must not be re-broadcast");
  XCTAssertEqualObjects((@[ @"records.7:hello", @"records.7:from-elsewhere" ]), [recorder snapshot]);

  // A failing backend never breaks local delivery.
  fanout.raises = YES;
  XCTAssertEqual((NSUInteger)1, [hub publishMessage:@"still-local" onChannel:@"records.7"]);

  RealtimeFakeFanout *replacement = [[RealtimeFakeFanout alloc] init];
  hub.fanout = replacement;
  XCTAssertTrue(fanout.stopped);
  hub.fanout = nil;
  XCTAssertTrue(replacement.stopped);
}

- (void)testPostgresFanoutRejectsUnsafeChannels {
  NSError *error = nil;
  ALNRealtimeHub *hub = [[ALNRealtimeHub alloc] init];
  for (NSString *channel in @[ @"bad-name", @"1leading", @"x\"; DROP TABLE t; --" ]) {
    XCTAssertNil([[ALNPgRealtimeFanout alloc] initWithConnectionString:@"host=127.0.0.1 port=1"
                                                         notifyChannel:channel
                                                                   hub:hub
                                                                 error:&error], @"%@", channel);
  }
}

- (void)testPostgresFanoutCrossesProcessBoundariesAndRecovers {
  const char *dsnValue = getenv("ARLEN_PG_TEST_DSN");
  if (dsnValue == NULL || dsnValue[0] == '\0') {
    return;  // Needs PostgreSQL; CI sets ARLEN_PG_TEST_DSN.
  }
  NSString *dsn = [NSString stringWithUTF8String:dsnValue];
  NSString *notifyChannel = [NSString stringWithFormat:@"arlen_rt_test_%u", arc4random_uniform(1000000000)];
  // Two hubs with their own fanouts stand in for two propane workers.
  ALNRealtimeHub *workerA = [[ALNRealtimeHub alloc] init];
  ALNRealtimeHub *workerB = [[ALNRealtimeHub alloc] init];
  NSError *error = nil;
  ALNPgRealtimeFanout *fanoutA = [[ALNPgRealtimeFanout alloc] initWithConnectionString:dsn notifyChannel:notifyChannel hub:workerA error:&error];
  ALNPgRealtimeFanout *fanoutB = [[ALNPgRealtimeFanout alloc] initWithConnectionString:dsn notifyChannel:notifyChannel hub:workerB error:&error];
  XCTAssertNotNil(fanoutA, @"%@", error);
  XCTAssertNotNil(fanoutB, @"%@", error);
  workerA.fanout = fanoutA;
  workerB.fanout = fanoutB;
  @try {
    XCTAssertTrue([fanoutA startWaitingUpTo:5.0]);
    XCTAssertTrue([fanoutB startWaitingUpTo:5.0]);
    RealtimeFanoutRecorder *onA = [[RealtimeFanoutRecorder alloc] init];
    RealtimeFanoutRecorder *onB = [[RealtimeFanoutRecorder alloc] init];
    [workerA subscribeChannel:@"records.7" subscriber:onA];
    [workerB subscribeChannel:@"records.7" subscriber:onB];

    [workerA publishMessage:@"reply-1" onChannel:@"records.7"];
    XCTAssertTrue([onB waitForCount:1 timeout:5.0], @"%@", [onB snapshot]);
    XCTAssertEqualObjects(@[ @"records.7:reply-1" ], [onB snapshot]);
    // The publisher's own subscribers get exactly one copy (no echo back from PostgreSQL).
    [NSThread sleepForTimeInterval:0.5];
    XCTAssertEqualObjects(@[ @"records.7:reply-1" ], [onA snapshot]);

    // Payloads beyond NOTIFY's limit travel through arlen_realtime_payloads.
    NSString *large = [@"" stringByPaddingToLength:20000 withString:@"x" startingAtIndex:0];
    [workerB publishMessage:large onChannel:@"records.7"];
    XCTAssertTrue([onA waitForCount:2 timeout:5.0], @"%@", [onA snapshot]);
    XCTAssertEqualObjects([@"records.7:" stringByAppendingString:large], [onA snapshot][1]);

    // Kill B's listener backend: it reconnects and receives later publishes.
    ALNPgConnection *admin = [[ALNPgConnection alloc] initWithConnectionString:dsn error:&error];
    XCTAssertNotNil(admin, @"%@", error);
    NSString *listen = [NSString stringWithFormat:@"LISTEN \"%@\"", notifyChannel];
    XCTAssertNotNil([admin executeQuery:@"SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                                         "WHERE query = $1 AND pid <> pg_backend_pid()"
                             parameters:@[ listen ]
                                  error:&error], @"%@", error);
    [admin close];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    BOOL delivered = NO;
    for (NSUInteger attempt = 0; !delivered && [deadline timeIntervalSinceNow] > 0; attempt++) {
      [workerA publishMessage:[NSString stringWithFormat:@"after-reconnect-%lu", (unsigned long)attempt] onChannel:@"records.7"];
      [fanoutA flushPublishes];
      delivered = [onB waitForCount:2 timeout:1.0];
    }
    XCTAssertTrue(delivered, @"%@", [onB snapshot]);
  } @finally {
    workerA.fanout = nil;
    workerB.fanout = nil;
  }
}

@end
