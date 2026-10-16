#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../ALNXCTestCompat.h"
#import "../shared/ALNTestSupport.h"

// `arlen new <name>` scaffolds relative to the current directory, but an
// absolute target is used as given. It used to be appended to the cwd, so
// `arlen new /srv/app` created ./srv/app (and C:/apps/app broke on Windows).
@interface ArlenNewCommandTests : XCTestCase
@end

@implementation ArlenNewCommandTests

- (NSString *)arlenPath {
#if defined(__APPLE__)
  return ALNTestPathFromRepoRoot(@"build/apple/arlen");
#else
  return ALNTestPathFromRepoRoot(@"build/arlen");
#endif
}

- (int)runNewWithTarget:(NSString *)target inDirectory:(NSString *)directory output:(NSString **)output {
  int exitCode = -1;
  NSString *command = [NSString stringWithFormat:@"cd %@ && LD_PRELOAD='' XCTEST_LD_PRELOAD='' "
                                                  "ARLEN_FRAMEWORK_ROOT=%@ %@ new %@ --lite 2>&1",
                                                 ALNTestShellQuote(directory),
                                                 ALNTestShellQuote(ALNTestRepoRoot()),
                                                 ALNTestShellQuote([self arlenPath]),
                                                 ALNTestShellQuote(target)];
  NSString *captured = ALNTestRunShellCapture(command, &exitCode);
  if (output != NULL) {
    *output = captured;
  }
  return exitCode;
}

- (void)testAbsoluteTargetIsNotNestedUnderTheCurrentDirectory {
  NSString *root = ALNTestTemporaryDirectory(@"arlen-new-absolute");
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }
  NSString *cwd = [root stringByAppendingPathComponent:@"cwd"];
  NSString *target = [root stringByAppendingPathComponent:@"AbsoluteApp"];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:cwd
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:NULL]);
  NSString *output = nil;
  XCTAssertEqual(0, [self runNewWithTarget:target inDirectory:cwd output:&output], @"%@", output);

  NSFileManager *fileManager = [NSFileManager defaultManager];
  XCTAssertTrue([fileManager fileExistsAtPath:[target stringByAppendingPathComponent:@"app_lite.m"]], @"%@", output);
  XCTAssertEqualObjects(@[], [fileManager contentsOfDirectoryAtPath:cwd error:NULL], @"%@", output);
  [fileManager removeItemAtPath:root error:NULL];
}

- (void)testRelativeTargetIsCreatedUnderTheCurrentDirectory {
  NSString *root = ALNTestTemporaryDirectory(@"arlen-new-relative");
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }
  NSString *output = nil;
  XCTAssertEqual(0, [self runNewWithTarget:@"RelativeApp" inDirectory:root output:&output], @"%@", output);
  XCTAssertTrue([[NSFileManager defaultManager]
                    fileExistsAtPath:[root stringByAppendingPathComponent:@"RelativeApp/app_lite.m"]],
                @"%@", output);
  [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}

// A blank or "." name resolves to the current directory; refuse it rather than
// scaffold (or, with --force, overwrite) the cwd.
- (void)testBlankOrDotTargetIsRejectedAndLeavesTheDirectoryAlone {
  NSString *root = ALNTestTemporaryDirectory(@"arlen-new-blank");
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }
  for (NSString *target in @[ @"  ", @"." ]) {
    NSString *output = nil;
    XCTAssertEqual(2, [self runNewWithTarget:target inDirectory:root output:&output], @"'%@': %@", target, output);
    XCTAssertTrue([output containsString:@"must name a new directory"], @"'%@': %@", target, output);
  }
  XCTAssertEqualObjects(@[], [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL]);
  [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}

// GNU make splits targets at whitespace, so boomhauer could not build an app
// under a path with a space ("No rule to make target .../My"); it now builds
// through a space-free alias.
- (void)testBoomhauerBuildsAnAppWhosePathContainsASpace {
  NSString *root = ALNTestTemporaryDirectory(@"arlen-new-space");
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }
  NSString *output = nil;
  XCTAssertEqual(0, [self runNewWithTarget:@"My App" inDirectory:root output:&output], @"%@", output);
  NSString *appRoot = [root stringByAppendingPathComponent:@"My App"];
  int exitCode = -1;
  NSString *command = [NSString stringWithFormat:@"cd %@ && LD_PRELOAD='' XCTEST_LD_PRELOAD='' "
                                                  "ARLEN_FRAMEWORK_ROOT=%@ %@ --prepare-only 2>&1",
                                                 ALNTestShellQuote(appRoot),
                                                 ALNTestShellQuote(ALNTestRepoRoot()),
                                                 ALNTestShellQuote(ALNTestPathFromRepoRoot(@"bin/boomhauer"))];
  output = ALNTestRunShellCapture(command, &exitCode);
  XCTAssertEqual(0, exitCode, @"%@", output);
  XCTAssertTrue([output containsString:@"app path contains whitespace; building through"], @"%@", output);
  XCTAssertFalse([output containsString:@"No rule to make target"], @"%@", output);
  [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}

// The alias directory must be the user's own and private: another user could
// otherwise pre-create it in a shared tmp and swap an alias to their sources.
- (void)testBoomhauerRefusesAnAliasDirectoryOthersCanWrite {
#if defined(_WIN32)
  XCTSkip(@"POSIX ownership and mode bits; under MSYS2 tmp is inside the user's own toolchain root");
#endif
  NSString *root = ALNTestTemporaryDirectory(@"arlen-new-alias-perms");
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }
  NSString *output = nil;
  XCTAssertEqual(0, [self runNewWithTarget:@"My App" inDirectory:root output:&output], @"%@", output);
  NSString *tmp = [root stringByAppendingPathComponent:@"shared-tmp"];
  int exitCode = -1;
  NSString *command = [NSString stringWithFormat:
      @"mkdir -p %@ && mkdir -m 777 %@/arlen-boomhauer-aliases-$(id -u) && chmod 777 %@/arlen-boomhauer-aliases-$(id -u) && "
       "cd %@ && TMPDIR=%@ LD_PRELOAD='' XCTEST_LD_PRELOAD='' ARLEN_FRAMEWORK_ROOT=%@ %@ --prepare-only 2>&1",
      ALNTestShellQuote(tmp), ALNTestShellQuote(tmp), ALNTestShellQuote(tmp),
      ALNTestShellQuote([root stringByAppendingPathComponent:@"My App"]), ALNTestShellQuote(tmp),
      ALNTestShellQuote(ALNTestRepoRoot()), ALNTestShellQuote(ALNTestPathFromRepoRoot(@"bin/boomhauer"))];
  output = ALNTestRunShellCapture(command, &exitCode);
  XCTAssertNotEqual(0, exitCode, @"%@", output);
  XCTAssertTrue([output containsString:@"must be a directory owned by you and writable only by you"], @"%@", output);
  [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}

@end
