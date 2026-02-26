#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@interface BuildPolicyTests : XCTestCase
@end

@implementation BuildPolicyTests

- (NSString *)readFile:(NSString *)path {
  NSError *error = nil;
  NSString *contents =
      [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNotNil(contents);
  XCTAssertNil(error);
  return contents ?: @"";
}

- (void)testGNUmakefileEnforcesARCFlagsAndRejectsOptOut {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefilePath = [repoRoot stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *makefile = [self readFile:makefilePath];

  XCTAssertTrue([makefile containsString:@"ARC_REQUIRED_FLAG := -fobjc-arc"]);
  XCTAssertTrue([makefile containsString:
                              @"override OBJC_FLAGS := $$(gnustep-config --objc-flags) "
                               "$(ARC_REQUIRED_FLAG) $(EXTRA_OBJC_FLAGS)"]);
  XCTAssertTrue([makefile containsString:@"EXTRA_OBJC_FLAGS cannot contain -fno-objc-arc"]);
  XCTAssertTrue([makefile containsString:@"OBJC_FLAGS cannot disable ARC"]);
}

- (void)testGNUmakefileClangRecipesUseCentralARCFlags {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefilePath = [repoRoot stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *makefile = [self readFile:makefilePath];

  NSArray<NSString *> *lines = [makefile componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  NSUInteger clangRecipeCount = 0;
  for (NSString *line in lines) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (![trimmed hasPrefix:@">"] || [trimmed containsString:@"clang "] == NO) {
      continue;
    }
    clangRecipeCount += 1;
    XCTAssertTrue([trimmed containsString:@"$(OBJC_FLAGS)"],
                  @"clang recipe must compile with $(OBJC_FLAGS): %@", trimmed);
    XCTAssertFalse([trimmed containsString:@"$(gnustep-config --objc-flags)"],
                   @"clang recipe must not bypass ARC policy flags directly: %@", trimmed);
  }

  XCTAssertTrue(clangRecipeCount > 0, @"expected at least one clang recipe in GNUmakefile");
}

- (void)testBoomhauerCompilePathEnforcesARC {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  NSString *script = [self readFile:scriptPath];

  NSError *error = nil;
  NSRegularExpression *regex =
      [NSRegularExpression regularExpressionWithPattern:
                               @"clang\\s+\\$\\(gnustep-config --objc-flags\\)(?:\\s+|\\\\\\n)+-fobjc-arc"
                                                options:0
                                                  error:&error];
  XCTAssertNotNil(regex);
  XCTAssertNil(error);
  if (regex == nil || error != nil) {
    return;
  }

  NSUInteger matches =
      [regex numberOfMatchesInString:script options:0 range:NSMakeRange(0, [script length])];
  XCTAssertTrue(matches > 0, @"boomhauer compile path must enforce -fobjc-arc");
}

@end
