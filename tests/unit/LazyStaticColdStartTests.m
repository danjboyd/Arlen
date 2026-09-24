#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNTestSupport.h"

@interface LazyStaticColdStartTests : XCTestCase
@end

@implementation LazyStaticColdStartTests

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

// Issue #49: ALNSQLBuilder's lazily created regexes and operator sets raced on
// concurrent first use, and the losing store freed an object another thread
// was still matching with. A process has only one first use, so 32 threads
// build SQL at once in each of many fresh processes.
- (void)testSQLBuilderStaticsAreSafeOnConcurrentFirstUse {
  NSString *repoRoot = ALNTestRepoRoot();
  NSString *temporaryDirectory = ALNTestTemporaryDirectory(@"lazy_static_cold_start");
  XCTAssertNotNil(temporaryDirectory);
  if (temporaryDirectory == nil) return;

  @try {
    NSString *binary = [temporaryDirectory stringByAppendingPathComponent:@"lazy-static-probe"];
    NSString *probe = [repoRoot stringByAppendingPathComponent:
        @"tests/fixtures/runtime/lazy_static_first_use_probe.m"];
    NSString *archive = [repoRoot stringByAppendingPathComponent:@"build/lib/libArlenFramework.a"];
    NSString *includeFlags = [self includeFlagsForRepoRoot:repoRoot];
#if defined(__APPLE__)
    archive = [repoRoot stringByAppendingPathComponent:@"build/apple/lib/libArlenFramework.a"];
    NSString *compiler = @"xcrun clang -fobjc-arc -fblocks -pthread";
    NSString *libraries = @"-framework Foundation -framework CoreFoundation -L\"${ARLEN_OPENSSL_PREFIX:-$(brew --prefix openssl@3)}/lib\" -lcrypto -lcurl";
#else
    NSString *compiler = [NSString stringWithFormat:
        @"%@ && clang $(gnustep-config --objc-flags) -fobjc-arc -fblocks -pthread",
        ALNTestGNUstepSourceCommandForRepoRoot(repoRoot)];
    NSString *libraries = @"$(gnustep-config --base-libs) -lcrypto -ldispatch -ldl -lcurl";
#endif
    NSMutableString *sanitizers = [NSMutableString string];
    NSUInteger processes = 100;
#if __has_feature(address_sanitizer)
    [sanitizers appendString:@" -fsanitize=address -fno-omit-frame-pointer"];
    processes = 40;
#endif
#if __has_feature(undefined_behavior_sanitizer)
    [sanitizers appendString:@" -fsanitize=undefined"];
    processes = 40;
#endif
#if __has_feature(thread_sanitizer)
    [sanitizers appendString:@" -fsanitize=thread"];
    processes = 20;
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

    NSString *bounded = [NSString stringWithFormat:@"perl -e 'alarm shift; exec @ARGV' 60 %@",
                                                   ALNTestShellQuote(binary)];
    command = [NSString stringWithFormat:
        @"set -e; ulimit -c 0; export LD_PRELOAD='' XCTEST_LD_PRELOAD=''; %@ 1; "
         "for trial in $(seq 1 %lu); do %@ 32; done",
        bounded, (unsigned long)processes, bounded];
    output = ALNTestRunShellCapture(command, &exitCode);
    XCTAssertEqual(0, exitCode, @"%@", output);
    XCTAssertEqual(processes + 1,
        [[output componentsSeparatedByString:@"lazy static first-use probe passed"] count] - 1,
        @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:temporaryDirectory error:NULL];
  }
}

@end
