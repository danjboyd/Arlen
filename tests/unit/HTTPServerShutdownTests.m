#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNApplication.h"
#import "ALNHTTPServer.h"

@interface ALNHTTPServer (ShutdownTests)
- (BOOL)startHTTPWorkerPoolIfNeeded;
- (BOOL)waitForHTTPBackgroundThreads;
@end

@interface HTTPShutdownState : NSObject
@property(nonatomic, strong) NSCondition *condition;
@property(nonatomic, assign) BOOL entered;
@property(nonatomic, assign) BOOL releaseWorker;
@property(nonatomic, assign) BOOL joined;
@property(nonatomic, assign) BOOL destroyedThreadLocal;
@end
@implementation HTTPShutdownState
@end

@interface HTTPShutdownThreadLocal : NSObject
@property(nonatomic, strong) HTTPShutdownState *state;
@end
@implementation HTTPShutdownThreadLocal
- (void)dealloc {
  [_state.condition lock];
  _state.destroyedThreadLocal = YES;
  [_state.condition broadcast];
  [_state.condition unlock];
}
@end

@interface HTTPShutdownProbeServer : ALNHTTPServer
@property(nonatomic, strong) HTTPShutdownState *state;
@end
@implementation HTTPShutdownProbeServer
- (void)startIdleConnectionWatcher {}
- (void)runHTTPWorkerLoop:(NSNumber *)index {
  (void)index;
  HTTPShutdownThreadLocal *marker = [[HTTPShutdownThreadLocal alloc] init];
  marker.state = self.state;
  [NSThread currentThread].threadDictionary[@"HTTPShutdownThreadLocal"] = marker;
  [self.state.condition lock];
  self.state.entered = YES;
  [self.state.condition broadcast];
  while (!self.state.releaseWorker) [self.state.condition wait];
  [self.state.condition unlock];
}
@end

@interface HTTPServerShutdownTests : XCTestCase
@end
@implementation HTTPServerShutdownTests
- (void)testHTTPWorkerShutdownWaitsForWorkAndNativeThreadLocalCleanup {
  HTTPShutdownState *state = [[HTTPShutdownState alloc] init];
  state.condition = [[NSCondition alloc] init];
  HTTPShutdownProbeServer *server = [[HTTPShutdownProbeServer alloc]
      initWithApplication:[[ALNApplication alloc] initWithConfig:@{}] publicRoot:@"."];
  server.state = state;
  [server setValue:@1 forKey:@"maxConcurrentHTTPWorkers"];
  XCTAssertTrue([server startHTTPWorkerPoolIfNeeded]);
  [state.condition lock];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!state.entered && [state.condition waitUntilDate:deadline]) {}
  XCTAssertTrue(state.entered);
  [state.condition unlock];
  NSThread *joiner = [[NSThread alloc] initWithBlock:^{
    BOOL joined = [server waitForHTTPBackgroundThreads];
    [state.condition lock];
    state.joined = joined;
    [state.condition broadcast];
    [state.condition unlock];
  }];
  [joiner start];
  [state.condition lock];
  @try {
    [state.condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    XCTAssertFalse(state.joined, @"Shutdown returned while an HTTP worker was still running");
  } @finally {
    state.releaseWorker = YES;
    [state.condition broadcast];
  }
  deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!state.joined && [state.condition waitUntilDate:deadline]) {}
  XCTAssertTrue(state.joined);
  XCTAssertTrue(state.destroyedThreadLocal,
                @"Worker completion must include native thread-local library cleanup");
  [state.condition unlock];
}
@end
