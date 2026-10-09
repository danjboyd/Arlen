#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "../ALNXCTestCompat.h"

#import "../shared/ALNTestSupport.h"

// `arlen build/check/test/perf/routes` use the Apple toolchain on macOS when
// the framework root has bin/build-apple, and GNU make otherwise. `arlen perf`
// is still GNUstep-only (GitHub issue 147).
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

- (NSString *)runArlen:(NSString *)arguments frameworkRoot:(NSString *)frameworkRoot exitCode:(int *)exitCode {
  NSString *command = [NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ %@ 2>&1",
                                                 ALNTestShellQuote(frameworkRoot), ALNTestShellQuote(frameworkRoot),
                                                 ALNTestShellQuote([self arlenPath]), arguments];
  return ALNTestRunShellCapture(command, exitCode);
}

- (NSDictionary *)dryRunPayload:(NSString *)commandName frameworkRoot:(NSString *)frameworkRoot {
  int exitCode = -1;
  NSString *output = [self runArlen:[NSString stringWithFormat:@"%@ --dry-run --json", commandName]
                      frameworkRoot:frameworkRoot
                           exitCode:&exitCode];
  XCTAssertEqual(0, exitCode, @"%@", output);
  NSDictionary *payload = ALNTestJSONDictionaryFromString(output, NULL);
  XCTAssertNotNil(payload, @"%@", output);
  XCTAssertEqualObjects(@"planned", payload[@"status"]);
  return payload ?: @{};
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

- (void)testAppleReportsGNUstepOnlySuitesInsteadOfCallingMake {
#if defined(__APPLE__)
  NSString *root = [self createFrameworkFixtureWithAppleBuilder:YES];
  int exitCode = -1;
  NSString *perf = [self runArlen:@"perf" frameworkRoot:root exitCode:&exitCode];
  XCTAssertEqual(2, exitCode, @"%@", perf);
  XCTAssertTrue([perf containsString:@"runs only on GNUstep"], @"%@", perf);

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
#endif
}

@end
