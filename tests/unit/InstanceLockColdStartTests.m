#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <dispatch/dispatch.h>
#import "ALNMetrics.h"

#import "../shared/ALNTestSupport.h"

@interface InstanceLockColdStartTests : XCTestCase
@end

@implementation InstanceLockColdStartTests

- (NSString *)includeFlagsForRepoRoot:(NSString *)repoRoot {
  NSMutableArray<NSString *> *flags = [NSMutableArray array];
  NSString *sourceRoot = [repoRoot stringByAppendingPathComponent:@"src"];
  [flags addObject:[NSString stringWithFormat:@"-I%@", ALNTestShellQuote(sourceRoot)]];
  NSString *arlenSource = [sourceRoot stringByAppendingPathComponent:@"Arlen"];
  NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:arlenSource];
  for (NSString *relativePath in enumerator) {
    NSString *path = [arlenSource stringByAppendingPathComponent:relativePath];
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
      [flags addObject:[NSString stringWithFormat:@"-I%@", ALNTestShellQuote(path)]];
    }
  }
  return [flags componentsJoinedByString:@" "];
}

// gnustep/libobjc2#424: the first @synchronized on an instance can hang, lose
// mutual exclusion, or abort when several threads race to it. Fresh metrics
// registries and Postgres pools are locked for the first time by 16 threads at
// once, in fresh processes, so no warmed state in the XCTest runner hides it.
- (void)testMetricsRegistryAndPgPoolAreSafeOnConcurrentFirstLock {
  NSString *repoRoot = ALNTestRepoRoot();
  NSString *temporaryDirectory = ALNTestTemporaryDirectory(@"instance_lock_cold_start");
  XCTAssertNotNil(temporaryDirectory);
  if (temporaryDirectory == nil) return;

  @try {
    NSString *binary = [temporaryDirectory stringByAppendingPathComponent:@"instance-lock-probe"];
    NSString *probe = [repoRoot stringByAppendingPathComponent:
        @"tests/fixtures/runtime/instance_lock_first_use_probe.m"];
    NSString *archive = [repoRoot stringByAppendingPathComponent:@"build/lib/libArlenFramework.a"];
    NSString *includeFlags = [self includeFlagsForRepoRoot:repoRoot];
#if defined(__APPLE__)
    archive = [repoRoot stringByAppendingPathComponent:@"build/apple/lib/libArlenFramework.a"];
    NSString *compiler = @"xcrun clang -fobjc-arc -fblocks -pthread";
    NSString *libraries = @"-framework Foundation -framework CoreFoundation -L\"${ARLEN_OPENSSL_PREFIX:-$(brew --prefix openssl@3)}/lib\" -lcrypto -lcurl";
#else
    NSString *compiler = [NSString stringWithFormat:
        @"%@ && clang $(gnustep-config --objc-flags) %@ -fobjc-arc -fblocks -pthread",
        ALNTestGNUstepSourceCommandForRepoRoot(repoRoot), ALNTestPlatformObjCFlags()];
    NSString *libraries = [NSString stringWithFormat:@"$(gnustep-config --base-libs) -lcrypto -ldispatch -lcurl %@", ALNTestPlatformLinkLibraries()];
#endif
    NSMutableString *sanitizers = [NSMutableString string];
    NSUInteger rounds = 2000;
#if __has_feature(address_sanitizer)
    [sanitizers appendString:@" -fsanitize=address -fno-omit-frame-pointer"];
    rounds = 500;
#endif
#if __has_feature(undefined_behavior_sanitizer)
    [sanitizers appendString:@" -fsanitize=undefined"];
    rounds = 500;
#endif
#if __has_feature(thread_sanitizer)
    [sanitizers appendString:@" -fsanitize=thread"];
    rounds = 200;
#endif
    NSString *compile = [NSString stringWithFormat:
        @"%@%@ -Wno-nullability-completeness -Wno-nonnull %@ %@ %@ -o %@ %@",
        compiler, sanitizers, includeFlags, ALNTestShellQuote(probe),
        ALNTestShellQuote(archive), ALNTestShellQuote(binary), libraries];
    NSString *command = [NSString stringWithFormat:
        @"LD_PRELOAD='' XCTEST_LD_PRELOAD='' bash -c %@", ALNTestShellQuote(compile)];
    int exitCode = 0;
    NSString *output = ALNTestRunShellCapture(command, &exitCode);
    XCTAssertEqual(0, exitCode, @"%@", output);
    if (exitCode != 0) return;

    // A hang is one of the failure modes, so every process runs under an
    // alarm (GNU timeout where present; perl on macOS, which lacks timeout(1)).
    NSString *bounded = [NSString stringWithFormat:@"%@ %@", ALNTestShellTimeoutPrefix(120),
                                                   ALNTestShellQuote(binary)];
    command = [NSString stringWithFormat:
        @"set -e; ulimit -c 0; export LD_PRELOAD='' XCTEST_LD_PRELOAD=''; %@ 1 %lu; "
         "for trial in {1..20}; do %@ 16 %lu; done",
        bounded, (unsigned long)rounds, bounded, (unsigned long)rounds];
    output = ALNTestRunShellCapture(command, &exitCode);
    XCTAssertEqual(0, exitCode, @"%@", output);
    XCTAssertEqual((NSUInteger)21,
        [[output componentsSeparatedByString:@"instance lock first-use rounds passed"] count] - 1,
        @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:temporaryDirectory error:NULL];
  }
}

- (void)testBatchedMetricsPreserveSnapshotsAndConcurrentTotals {
  ALNMetricsRegistry *metrics = [[ALNMetricsRegistry alloc] init];
  dispatch_apply(1000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
    @autoreleasepool {
      [metrics addGauge:@"active" delta:1];
      [metrics recordHTTPResponseStatus:(index % 2 ? 200 : 500)
                      totalMilliseconds:@2 routeMilliseconds:@1 controllerMilliseconds:nil];
      [metrics addGauge:@"active" delta:-1];
    }
  });
  NSDictionary *snapshot = [metrics snapshot];
  XCTAssertEqualObjects(@1000, snapshot[@"counters"][@"http_requests_total"]);
  XCTAssertEqualObjects(@500, snapshot[@"counters"][@"http_errors_total"]);
  XCTAssertEqualObjects(@500, snapshot[@"counters"][@"http_status_200_total"]);
  XCTAssertEqualObjects(@0, snapshot[@"gauges"][@"active"]);
  NSDictionary *timing = snapshot[@"timings"][@"http_request_duration_ms"];
  XCTAssertEqualObjects(@1000, timing[@"count"]);
  XCTAssertEqualObjects(@2000, timing[@"sum"]);
  XCTAssertEqualObjects(@2, timing[@"min"]);
  XCTAssertEqualObjects(@2, timing[@"max"]);
  XCTAssertNil(snapshot[@"timings"][@"http_controller_duration_ms"]);
  [metrics recordTiming:@"http_request_duration_ms" milliseconds:-1];
  XCTAssertEqualObjects(@1000, timing[@"count"], @"snapshots remain independent of later updates");
  XCTAssertEqualObjects(@0, [metrics snapshot][@"timings"][@"http_request_duration_ms"][@"min"]);
  XCTAssertTrue([[metrics prometheusText] containsString:@"http_requests_total 1000"]);
}

@end
