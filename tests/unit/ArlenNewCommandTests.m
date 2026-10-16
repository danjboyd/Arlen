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

@end
