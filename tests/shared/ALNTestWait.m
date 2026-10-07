#import "ALNTestWait.h"

#import <XCTest/XCTest.h>

#if !defined(_WIN32)
#import <arpa/inet.h>
#import <netinet/in.h>
#import <string.h>
#import <sys/socket.h>
#import <unistd.h>
#endif

#if __has_include(<XCTest/XCTWaiter.h>)
#define ALN_TEST_WAIT_HAS_WAITER 1
#else
#define ALN_TEST_WAIT_HAS_WAITER 0
#endif

const NSTimeInterval ALNTestWaitDefaultInterval = 0.05;

#if ALN_TEST_WAIT_HAS_WAITER
// Fulfills the expectation the first time the condition holds. Its timer runs
// on the waiting thread's run loop, which XCTWaiter spins while it waits.
@interface ALNTestWaitPoller : NSObject
- (instancetype)initWithCondition:(ALNTestWaitCondition)condition
                      expectation:(XCTestExpectation *)expectation;
- (void)poll:(NSTimer *)timer;
@end

@implementation ALNTestWaitPoller {
  ALNTestWaitCondition _condition;
  XCTestExpectation *_expectation;
  BOOL _met;
}

- (instancetype)initWithCondition:(ALNTestWaitCondition)condition
                      expectation:(XCTestExpectation *)expectation {
  self = [super init];
  if (self != nil) {
    _condition = [condition copy];
    _expectation = expectation;
  }
  return self;
}

- (void)poll:(NSTimer *)timer {
  (void)timer;
  if (!_met && _condition()) {
    _met = YES;
    [_expectation fulfill];
  }
}
@end
#endif

BOOL ALNTestWaitUntil(NSTimeInterval timeout, NSTimeInterval interval, ALNTestWaitCondition condition) {
  if (condition()) {
    return YES;
  }
  NSTimeInterval checkInterval = (interval > 0) ? interval : ALNTestWaitDefaultInterval;
#if ALN_TEST_WAIT_HAS_WAITER
  XCTestExpectation *expectation =
      [[XCTestExpectation alloc] initWithDescription:@"ALNTestWaitUntil condition"];
  ALNTestWaitPoller *poller = [[ALNTestWaitPoller alloc] initWithCondition:condition
                                                               expectation:expectation];
  NSTimer *timer = [NSTimer timerWithTimeInterval:checkInterval
                                           target:poller
                                         selector:@selector(poll:)
                                         userInfo:nil
                                          repeats:YES];
  [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
  XCTWaiterResult result = [XCTWaiter waitForExpectations:@[ expectation ] timeout:timeout];
  [timer invalidate];
  if (result == XCTWaiterResultCompleted) {
    return YES;
  }
#else
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while ([deadline timeIntervalSinceNow] > 0) {
    // sleep-ok: fallback for toolchain XCTest builds without XCTWaiter.
    [NSThread sleepForTimeInterval:checkInterval];
    if (condition()) {
      return YES;
    }
  }
#endif
  return condition();
}

BOOL ALNTestWaitForTaskExit(NSTask *task, NSTimeInterval timeout) {
  BOOL exited = ALNTestWaitUntil(timeout, 0.02, ^BOOL {
    return ![task isRunning];
  });
  if (exited) {
    [task waitUntilExit];
  }
  return exited;
}

#if !defined(_WIN32)
BOOL ALNTestTCPPortAcceptsConnections(int port) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) {
    return NO;
  }
  struct sockaddr_in address;
  memset(&address, 0, sizeof(address));
  address.sin_family = AF_INET;
  address.sin_port = htons((uint16_t)port);
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  BOOL connected = (connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0);
  close(fd);
  return connected;
}

BOOL ALNTestWaitForTCPPort(int port, NSTimeInterval timeout) {
  return ALNTestWaitUntil(timeout, ALNTestWaitDefaultInterval, ^BOOL {
    return ALNTestTCPPortAcceptsConnections(port);
  });
}
#endif
