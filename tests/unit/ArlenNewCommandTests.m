#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../ALNXCTestCompat.h"
#import "ALNConfig.h"
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

// boomhauer links apps against an uninstrumented framework, so run against a
// sanitizer build it would `make clean` the shared repo build mid-suite.
- (BOOL)frameworkIsSanitizerInstrumented {
#if defined(__has_feature)
#if __has_feature(address_sanitizer) || __has_feature(thread_sanitizer)
  return YES;
#endif
#endif
  const char *extraFlags = getenv("EXTRA_OBJC_FLAGS");
  return extraFlags != NULL && strstr(extraFlags, "-fsanitize") != NULL;
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

// Issue 215: the scaffold used to write `session.secure = NO` and
// `docsUIEnabled = YES` into the base app.plist, which cancelled the
// production defaults (Secure cookies, no OpenAPI explorer).
- (void)testGeneratedAppsKeepProductionSecureDefaults_Issue215 {
  for (NSString *mode in @[ @"--lite", @"--full" ]) {
    NSString *root = ALNTestTemporaryDirectory(@"arlen-new-prod-defaults");
    XCTAssertNotNil(root);
    if (root == nil) {
      return;
    }
    int exitCode = -1;
    NSString *command = [NSString stringWithFormat:@"cd %@ && LD_PRELOAD='' XCTEST_LD_PRELOAD='' "
                                                    "ARLEN_FRAMEWORK_ROOT=%@ %@ new DefaultsApp %@ 2>&1",
                                                   ALNTestShellQuote(root),
                                                   ALNTestShellQuote(ALNTestRepoRoot()),
                                                   ALNTestShellQuote([self arlenPath]), mode];
    NSString *output = ALNTestRunShellCapture(command, &exitCode);
    XCTAssertEqual(0, exitCode, @"%@: %@", mode, output);
    NSString *appRoot = [root stringByAppendingPathComponent:@"DefaultsApp"];

    NSError *error = nil;
    NSDictionary *production = [ALNConfig loadConfigAtRoot:appRoot environment:@"production" error:&error];
    XCTAssertNil(error, @"%@", mode);
    XCTAssertEqualObjects(@YES, production[@"session"][@"secure"], @"%@", mode);
    XCTAssertEqualObjects(@NO, production[@"openapi"][@"docsUIEnabled"], @"%@", mode);

    NSDictionary *development = [ALNConfig loadConfigAtRoot:appRoot environment:@"development" error:&error];
    XCTAssertNil(error, @"%@", mode);
    XCTAssertEqualObjects(@NO, development[@"session"][@"secure"], @"%@", mode);
    XCTAssertEqualObjects(@YES, development[@"openapi"][@"docsUIEnabled"], @"%@", mode);
    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
  }
}

// The scaffold used to write `csrf.enabled = NO`, so an app that later turned
// sessions on (as the auth module needs) ran without CSRF protection.
- (void)testGeneratedAppsLeaveCSRFFollowingSessions {
  for (NSString *mode in @[ @"--lite", @"--full" ]) {
    NSString *root = ALNTestTemporaryDirectory(@"arlen-new-csrf");
    XCTAssertNotNil(root);
    if (root == nil) {
      return;
    }
    int exitCode = -1;
    NSString *command = [NSString stringWithFormat:@"cd %@ && LD_PRELOAD='' XCTEST_LD_PRELOAD='' "
                                                    "ARLEN_FRAMEWORK_ROOT=%@ %@ new CSRFApp %@ 2>&1",
                                                   ALNTestShellQuote(root),
                                                   ALNTestShellQuote(ALNTestRepoRoot()),
                                                   ALNTestShellQuote([self arlenPath]), mode];
    NSString *output = ALNTestRunShellCapture(command, &exitCode);
    XCTAssertEqual(0, exitCode, @"%@: %@", mode, output);
    NSString *appRoot = [root stringByAppendingPathComponent:@"CSRFApp"];

    NSDictionary *appPlist =
        [NSDictionary dictionaryWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]];
    XCTAssertNotNil(appPlist, @"%@", mode);
    XCTAssertNil(appPlist[@"csrf"][@"enabled"], @"%@", mode);

    NSString *development = [appRoot stringByAppendingPathComponent:@"config/environments/development.plist"];
    XCTAssertTrue([@"{\n  session = { enabled = YES; secret = \"0123456789abcdef0123456789abcdef\"; };\n}\n"
                      writeToFile:development
                       atomically:YES
                         encoding:NSUTF8StringEncoding
                            error:NULL]);
    NSError *error = nil;
    NSDictionary *config = [ALNConfig loadConfigAtRoot:appRoot environment:@"development" error:&error];
    XCTAssertNil(error, @"%@", mode);
    XCTAssertEqualObjects(@YES, config[@"csrf"][@"enabled"], @"%@", mode);
    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
  }
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
  XCTSkipIf([self frameworkIsSanitizerInstrumented],
            @"boomhauer would rebuild the shared repo framework without sanitizers");
  NSString *root = ALNTestTemporaryDirectory(@"arlen-new-space");
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }
  NSString *output = nil;
  XCTAssertEqual(0, [self runNewWithTarget:@"My App" inDirectory:root output:&output], @"%@", output);
  NSString *appRoot = [root stringByAppendingPathComponent:@"My App"];
  // The alias goes under the test's own TMPDIR, so it is removed with the test
  // root instead of being left dangling in the real tmp.
  NSString *tmp = [root stringByAppendingPathComponent:@"tmp"];
  int exitCode = -1;
  NSString *command = [NSString stringWithFormat:@"mkdir -p %@ && cd %@ && TMPDIR=%@ LD_PRELOAD='' XCTEST_LD_PRELOAD='' "
                                                  "ARLEN_FRAMEWORK_ROOT=%@ %@ --prepare-only 2>&1",
                                                 ALNTestShellQuote(tmp), ALNTestShellQuote(appRoot), ALNTestShellQuote(tmp),
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
  XCTSkipIf([self frameworkIsSanitizerInstrumented],
            @"boomhauer would rebuild the shared repo framework without sanitizers");
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
