#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "../ALNXCTestCompat.h"
#import "../shared/ALNTestSupport.h"

@interface JobsWorkerLoopTests : XCTestCase
@end

@implementation JobsWorkerLoopTests
- (void)checkScenario:(NSString *)scenario polls:(NSUInteger)polls ticks:(NSUInteger)ticks {
  NSString *root = ALNTestTemporaryDirectory(@"jobs-loop-lifetime");
  XCTAssertNotNil(root);
  if (root == nil) return;
  @try {
    NSError *error = nil;
    XCTAssertTrue(ALNTestWriteUTF8File([root stringByAppendingPathComponent:@"config/app.plist"],
                                      @"{}\n", &error), @"%@", error);
    XCTAssertTrue(ALNTestWriteUTF8File([root stringByAppendingPathComponent:@"config/environments/test.plist"],
                                      @"{}\n", &error), @"%@", error);
    NSString *binary = ALNTestExecutablePath(ALNTestPathFromRepoRoot(@"build/jobs-worker-loop-probe"));
    NSString *command = [NSString stringWithFormat:@"ARLEN_APP_ROOT=%@ %@ %@ %@",
                          ALNTestShellQuote(root), ALNTestShellTimeoutPrefix(10),
                          ALNTestShellQuote(binary), ALNTestShellQuote(scenario)];
    NSDictionary *streams = ALNTestRunShellCaptureStreams(command);
    XCTAssertEqualObjects(@0, streams[@"status"], @"%@", streams);
    NSDictionary *result = ALNTestJSONDictionaryFromString(streams[@"stdout"], &error);
    XCTAssertNotNil(result, @"%@ / %@", error, streams);
    XCTAssertTrue([result[@"created"] unsignedIntegerValue] > 0);
    XCTAssertEqualObjects(@(polls), result[@"polls"]);
    XCTAssertEqualObjects(@(ticks), result[@"ticks"]);
    XCTAssertEqualObjects(result[@"created"], result[@"destroyed"]);
    XCTAssertEqualObjects(@NO, result[@"missedDrain"]);
    XCTAssertEqualObjects([scenario isEqualToString:@"once"] ? @0 : @1, result[@"status"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
  }
}
- (void)testIdlePollsDrainBeforeTheNextIteration { [self checkScenario:@"idle" polls:4 ticks:0]; }
- (void)testBusyPollsDrainOnContinue { [self checkScenario:@"busy" polls:4 ticks:0]; }
- (void)testRunLimitPollsDrainOnContinue { [self checkScenario:@"limit" polls:4 ticks:0]; }
- (void)testSchedulerAndWorkerDrainBetweenIterations { [self checkScenario:@"scheduler" polls:4 ticks:4]; }
- (void)testOnceDrainsBeforeReturningSuccess { [self checkScenario:@"once" polls:1 ticks:0]; }
- (void)testWorkerErrorDrainsBeforeReturningFailure { [self checkScenario:@"worker-error" polls:1 ticks:0]; }
- (void)testSchedulerErrorDrainsBeforeReturningFailure { [self checkScenario:@"scheduler-error" polls:0 ticks:1]; }
@end
