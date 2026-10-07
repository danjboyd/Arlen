#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <signal.h>
#import <errno.h>
#import "../shared/ALNTestSupport.h"
#import "../shared/ALNTestWait.h"

@interface TestSupportTests : XCTestCase
@end
@implementation TestSupportTests
- (void)testJSONStdoutRemainsSeparateFromNoticesAndLargeStderr {
  NSDictionary *result = ALNTestRunShellCaptureStreams(
      @"printf '{\"status\":\"ok\"}'; printf 'NOTICE: already exists\\n' >&2; "
       "head -c 131072 /dev/zero >&2; exit 7");
  XCTAssertEqualObjects(@7, result[@"status"]);
  NSError *error = nil;
  NSDictionary *json = ALNTestJSONDictionaryFromString(result[@"stdout"], &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"ok", json[@"status"]);
  XCTAssertTrue([result[@"stderr"] hasPrefix:@"NOTICE: already exists"]);
  XCTAssertTrue([result[@"stderr"] length] > 131072);
}
- (void)testServerCleanupReapsAnExecLaunchedProcess {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[ @"-c", @"exec sleep 60" ];
  [task launch];
  int pid = task.processIdentifier;
  @try {
    XCTAssertTrue([task isRunning]);
  } @finally {
    XCTAssertTrue(ALNTestStopServerTask(task));
  }
  XCTAssertEqual(-1, kill(pid, 0));
  XCTAssertEqual(ESRCH, errno);
  XCTAssertTrue(ALNTestStopServerTask(task));
}
- (void)testServerCleanupRunsAfterAnException {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[ @"-c", @"exec sleep 60" ];
  [task launch];
  int pid = task.processIdentifier;
  BOOL caught = NO;
  @try {
    @try {
      [NSException raise:@"SimulatedTestFailure" format:@"exercise failure cleanup"];
    } @finally {
      XCTAssertTrue(ALNTestStopServerTask(task));
    }
  } @catch (NSException *exception) {
    caught = [exception.name isEqualToString:@"SimulatedTestFailure"];
  }
  XCTAssertTrue(caught);
  XCTAssertEqual(-1, kill(pid, 0));
  XCTAssertEqual(ESRCH, errno);
}
- (void)testServerCleanupEscalatesWhenTermIsIgnored {
  NSString *ready = [ALNTestTemporaryDirectory(@"server-cleanup") stringByAppendingPathComponent:@"ready"];
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[ @"-c", [NSString stringWithFormat:@"trap '' TERM; touch %@; exec sleep 60", ALNTestShellQuote(ready)] ];
  [task launch];
  int pid = task.processIdentifier;
  @try {
    XCTAssertTrue(ALNTestWaitUntil(5.0, 0.02, ^BOOL {
      return [[NSFileManager defaultManager] fileExistsAtPath:ready];
    }));
  } @finally {
    XCTAssertTrue(ALNTestStopServerTask(task));
    [[NSFileManager defaultManager] removeItemAtPath:[ready stringByDeletingLastPathComponent] error:NULL];
  }
  XCTAssertEqual(-1, kill(pid, 0));
  XCTAssertEqual(ESRCH, errno);
}
- (void)testWaitUntilReturnsOnceTheConditionHolds {
  __block NSUInteger checks = 0;
  NSDate *started = [NSDate date];
  XCTAssertTrue(ALNTestWaitUntil(10.0, 0.01, ^BOOL {
    checks += 1;
    return checks >= 3;
  }));
  XCTAssertEqual((NSUInteger)3, checks);
  XCTAssertLessThan(-[started timeIntervalSinceNow], 5.0);
}
- (void)testWaitUntilReturnsNoWhenTheConditionNeverHolds {
  NSDate *started = [NSDate date];
  XCTAssertFalse(ALNTestWaitUntil(0.2, 0.02, ^BOOL {
    return NO;
  }));
  XCTAssertGreaterThanOrEqual(-[started timeIntervalSinceNow], 0.2);
}
- (void)testWaitForTaskExitReapsTheTask {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/sh";
  task.arguments = @[ @"-c", @"exit 3" ];
  [task launch];
  XCTAssertTrue(ALNTestWaitForTaskExit(task, 10.0));
  XCTAssertFalse([task isRunning]);
  XCTAssertEqual(3, task.terminationStatus);
}
@end
