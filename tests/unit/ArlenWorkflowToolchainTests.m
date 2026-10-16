#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "../ALNXCTestCompat.h"

#import "../shared/ALNTestSupport.h"

// `arlen build/check/test/perf/routes` use the Apple toolchain on macOS when
// the framework root has bin/build-apple, and GNU make otherwise.
@interface ArlenWorkflowToolchainTests : XCTestCase
@end

@implementation ArlenWorkflowToolchainTests

- (NSString *)arlenPath {
#if defined(__APPLE__)
  return ALNTestPathFromRepoRoot(@"build/apple/arlen");
#else
  return ALNTestPathFromRepoRoot(@"build/arlen");
#endif
}

- (NSString *)createFrameworkFixtureWithAppleBuilder:(BOOL)withAppleBuilder {
  NSString *root = ALNTestTemporaryDirectory(@"arlen-toolchain-fixture");
  XCTAssertNotNil(root);
  NSError *error = nil;
  NSDictionary<NSString *, NSString *> *files = @{
    @"GNUmakefile" : @"all:\n\t@echo built\n",
    @"tools/boomhauer.m" : @"int main(void) { return 0; }\n",
    @"src/Arlen/ArlenServer.h" : @"#import <Foundation/Foundation.h>\n",
  };
  for (NSString *relativePath in files) {
    XCTAssertTrue(ALNTestWriteUTF8File([root stringByAppendingPathComponent:relativePath], files[relativePath], &error),
                  @"%@", error);
  }
  if (withAppleBuilder) {
    NSDictionary<NSString *, NSString *> *scripts = @{
      @"bin/build-apple" : @"#!/usr/bin/env bash\necho apple-built\n",
      @"tools/test_apple_xctest.sh" : @"#!/usr/bin/env bash\necho \"apple-suite $*\"\n",
      @"tests/performance/run_perf.sh" : @"#!/usr/bin/env bash\necho apple-perf\n",
    };
    for (NSString *relativePath in scripts) {
      NSString *script = [root stringByAppendingPathComponent:relativePath];
      XCTAssertTrue(ALNTestWriteUTF8File(script, scripts[relativePath], &error), @"%@", error);
      XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions : @0755 }
                                                     ofItemAtPath:script
                                                            error:&error],
                    @"%@", error);
    }
  }
  return root;
}

- (NSString *)arlenCommand:(NSString *)arguments frameworkRoot:(NSString *)frameworkRoot {
  // The Linux ASan lane preloads a sanitizer runtime that conflicts with the
  // one linked into build/arlen, so clear it as BuildPolicyTests does.
  return [NSString stringWithFormat:@"cd %@ && LD_PRELOAD='' XCTEST_LD_PRELOAD='' "
                                     "ARLEN_FRAMEWORK_ROOT=%@ %@ %@",
                                    ALNTestShellQuote(frameworkRoot), ALNTestShellQuote(frameworkRoot),
                                    ALNTestShellQuote([self arlenPath]), arguments];
}

- (NSString *)runArlen:(NSString *)arguments frameworkRoot:(NSString *)frameworkRoot exitCode:(int *)exitCode {
  NSString *command = [[self arlenCommand:arguments frameworkRoot:frameworkRoot] stringByAppendingString:@" 2>&1"];
  return ALNTestRunShellCapture(command, exitCode);
}

- (NSDictionary *)dryRunPayload:(NSString *)commandName frameworkRoot:(NSString *)frameworkRoot {
  // Parse stdout alone: the toolchain may print warnings on stderr (GNUstep
  // reports unknown GNUstep.conf keys there), and they are not part of the JSON.
  NSDictionary *result = ALNTestRunShellCaptureStreams(
      [self arlenCommand:[NSString stringWithFormat:@"%@ --dry-run --json", commandName] frameworkRoot:frameworkRoot]);
  NSString *output = [NSString stringWithFormat:@"stdout:\n%@\nstderr:\n%@", result[@"stdout"], result[@"stderr"]];
  XCTAssertEqualObjects(@0, result[@"status"], @"%@", output);
  NSDictionary *payload = ALNTestJSONDictionaryFromString(result[@"stdout"], NULL);
  XCTAssertNotNil(payload, @"%@", output);
  XCTAssertEqualObjects(@"planned", payload[@"status"]);
  return payload ?: @{};
}

- (void)testServerCommandsStayInTheCallersProcessGroup {
  // arlen boomhauer, propane and jobs worker must run the server in the
  // caller's process group, so a terminal Ctrl-C (or a signal to that group)
  // stops the server instead of only arlen.
  NSString *root = [self createFrameworkFixtureWithAppleBuilder:NO];
  NSError *error = nil;
  NSString *pgidScript = @"#!/usr/bin/env bash\n"
                         @"python3 -c 'import os; print(\"server pgid=%d\" % os.getpgrp())'\n";
  for (NSString *name in @[ @"bin/boomhauer", @"bin/propane", @"bin/jobs-worker" ]) {
    NSString *script = [root stringByAppendingPathComponent:name];
    XCTAssertTrue(ALNTestWriteUTF8File(script, pgidScript, &error), @"%@", error);
    XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions : @0755 }
                                                   ofItemAtPath:script
                                                          error:&error],
                  @"%@", error);
  }
  for (NSString *arguments in @[ @"boomhauer", @"propane", @"jobs worker" ]) {
    int exitCode = -1;
    NSString *output = [self runArlen:[NSString stringWithFormat:@"%@ && python3 -c 'import os; "
                                                                 @"print(\"caller pgid=%%d\" %% os.getpgrp())'",
                                                                 arguments]
                        frameworkRoot:root
                             exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@: %@", arguments, output);
    NSArray<NSString *> *lines = [[output stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]
        componentsSeparatedByString:@"\n"];
    XCTAssertEqual((NSUInteger)2, [lines count], @"%@: %@", arguments, output);
    if ([lines count] == 2) {
      NSString *serverGroup = [lines[0] stringByReplacingOccurrencesOfString:@"server pgid=" withString:@""];
      NSString *callerGroup = [lines[1] stringByReplacingOccurrencesOfString:@"caller pgid=" withString:@""];
      XCTAssertEqualObjects(callerGroup, serverGroup, @"%@: %@", arguments, output);
    }
  }
  [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
}

- (void)testBuildAndCheckUseThePlatformToolchain {
  NSString *root = [self createFrameworkFixtureWithAppleBuilder:YES];
  NSDictionary *build = [self dryRunPayload:@"build" frameworkRoot:root];
  NSDictionary *check = [self dryRunPayload:@"check" frameworkRoot:root];
#if defined(__APPLE__)
  XCTAssertEqualObjects(@"apple", build[@"toolchain"]);
  XCTAssertEqualObjects(@"", build[@"make_target"]);
  XCTAssertTrue([build[@"shell_command"] hasSuffix:@"&& ./bin/build-apple --with-boomhauer"], @"%@", build);
  XCTAssertEqualObjects(@"apple", check[@"toolchain"]);
  XCTAssertTrue([check[@"shell_command"] hasSuffix:@"&& ./tools/test_apple.sh"], @"%@", check);
#else
  XCTAssertEqualObjects(@"make", build[@"toolchain"]);
  XCTAssertEqualObjects(@"all", build[@"make_target"]);
  XCTAssertEqualObjects(@"make", check[@"toolchain"]);
  XCTAssertEqualObjects(@"check", check[@"make_target"]);
#endif
  [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
}

- (void)testFrameworkRootWithoutAppleBuilderUsesMake {
  NSString *root = [self createFrameworkFixtureWithAppleBuilder:NO];
  NSDictionary *build = [self dryRunPayload:@"build" frameworkRoot:root];
  XCTAssertEqualObjects(@"make", build[@"toolchain"]);
  XCTAssertEqualObjects(@"all", build[@"make_target"]);
  XCTAssertTrue([build[@"shell_command"] hasSuffix:@"&& make all"], @"%@", build);
  [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
}

- (void)testAppleRunsTestSuitesAndPerfWithoutMake {
#if !defined(__APPLE__)
  XCTSkip(@"Apple toolchain dispatch runs only on macOS");
#endif
  NSString *root = [self createFrameworkFixtureWithAppleBuilder:YES];
  int exitCode = -1;
  NSString *perf = [self runArlen:@"perf" frameworkRoot:root exitCode:&exitCode];
  XCTAssertEqual(0, exitCode, @"%@", perf);
  XCTAssertEqualObjects(@"apple-perf\n", perf);

  // The unit and integration suites run as Apple XCTest bundles.
  NSDictionary<NSString *, NSString *> *expectedSuites = @{
    @"test --unit" : @"apple-suite --suite unit\n",
    @"test --integration" : @"apple-suite --suite integration\n",
    @"test --all" : @"apple-suite --suite unit\napple-suite --suite integration\n",
  };
  for (NSString *arguments in expectedSuites) {
    NSString *output = [self runArlen:arguments frameworkRoot:root exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@: %@", arguments, output);
    XCTAssertEqualObjects(expectedSuites[arguments], output, @"%@", arguments);
  }
  [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
}

@end
