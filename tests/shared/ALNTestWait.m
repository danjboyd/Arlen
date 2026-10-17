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

BOOL ALNTestWaitUntil(NSTimeInterval timeout, NSTimeInterval interval, ALNTestWaitCondition condition) {
  NSTimeInterval checkInterval = (interval > 0) ? interval : ALNTestWaitDefaultInterval;
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (YES) {
    if (condition()) {
      return YES;
    }
    NSTimeInterval remaining = [deadline timeIntervalSinceNow];
    if (remaining <= 0) {
      return NO;
    }
    NSTimeInterval pause = MIN(checkInterval, remaining);
#if ALN_TEST_WAIT_HAS_WAITER
    // Check the condition outside XCTWaiter and use the waiter only for the
    // pause. A condition can block (a curl that a busy server never answers);
    // run inside a waiter, that overran the timeout and Apple XCTest's stall
    // detector aborted the whole bundle. The class-method waiter records no
    // failure when the never-fulfilled expectation times out.
    XCTestExpectation *pauseExpectation =
        [[XCTestExpectation alloc] initWithDescription:@"ALNTestWaitUntil pause"];
    (void)[XCTWaiter waitForExpectations:@[ pauseExpectation ] timeout:pause];
#else
    // sleep-ok: fallback for toolchain XCTest builds without XCTWaiter.
    [NSThread sleepForTimeInterval:pause];
#endif
  }
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
