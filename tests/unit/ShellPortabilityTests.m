#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "../ALNXCTestCompat.h"

#import "../shared/ALNTestSupport.h"

// Scripts that run on macOS execute under /bin/bash 3.2. These checks keep
// out the constructs that work on Linux's bash 5 but abort on 3.2. They are
// static so the GNUstep lanes catch regressions too.
@interface ShellPortabilityTests : XCTestCase
@end

@implementation ShellPortabilityTests

- (NSArray<NSString *> *)macOSScripts {
  return @[
    @"bin/arlen",
    @"bin/arlen-doctor",
    @"bin/build-apple",
    @"bin/jobs-worker",
    @"bin/propane",
    @"tools/apple_compile_program.sh",
    @"tools/build_apple.sh",
    @"tools/build_apple_app.sh",
    @"tests/performance/run_perf.sh",
    @"tools/build_apple_xctest.sh",
    @"tools/ci/run_durable_jobs.sh",
    @"tools/deploy/activate_release.sh",
    @"tools/deploy/build_release.sh",
    @"tools/deploy/rollback_release.sh",
    @"tools/deploy/smoke_release.sh",
    @"tools/deploy/validate_operability.sh",
    @"tools/platform.sh",
    @"tools/run_app_tests.sh",
    @"tools/test_apple.sh",
    @"tools/test_apple_xctest.sh",
  ];
}

- (NSArray<NSString *> *)linesOfScript:(NSString *)relativePath {
  NSError *error = nil;
  NSString *contents = [NSString stringWithContentsOfFile:ALNTestPathFromRepoRoot(relativePath)
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
  XCTAssertNotNil(contents, @"%@: %@", relativePath, error);
  return [contents componentsSeparatedByString:@"\n"];
}

- (NSArray<NSString *> *)violationsInScript:(NSString *)relativePath
                                matchingRegex:(NSString *)pattern
                                       reason:(NSString *)reason {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
  XCTAssertNotNil(regex);
  NSMutableArray<NSString *> *violations = [NSMutableArray array];
  NSArray<NSString *> *lines = [self linesOfScript:relativePath];
  for (NSUInteger idx = 0; idx < [lines count]; idx++) {
    NSString *line = lines[idx];
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed hasPrefix:@"#"]) {
      continue;
    }
    if ([regex firstMatchInString:line options:0 range:NSMakeRange(0, [line length])] != nil) {
      [violations addObject:[NSString stringWithFormat:@"%@:%lu: %@: %@", relativePath,
                                                       (unsigned long)(idx + 1), reason, trimmed]];
    }
  }
  return violations;
}

- (void)testMacOSScriptsAvoidBash4OnlySyntax {
  NSDictionary<NSString *, NSString *> *rules = @{
    @"\\$\\{[A-Za-z_][A-Za-z0-9_]*(,,|\\^\\^)\\}" : @"case-conversion expansion needs bash 4",
    @"\\b(mapfile|readarray)\\b" : @"mapfile/readarray need bash 4",
    @"\\b(declare|local|typeset) +-[a-zA-Z]*[An]" : @"associative arrays and namerefs need bash 4",
    @"(<\\(|\\$\\().*<<-?'?[A-Za-z_]+" : @"bash 3.2 misparses a heredoc nested in $(...) or <(...)",
  };
  NSMutableArray<NSString *> *violations = [NSMutableArray array];
  for (NSString *script in [self macOSScripts]) {
    for (NSString *pattern in rules) {
      [violations addObjectsFromArray:[self violationsInScript:script matchingRegex:pattern reason:rules[pattern]]];
    }
  }
  XCTAssertEqual((NSUInteger)0, [violations count], @"%@", [violations componentsJoinedByString:@"\n"]);
}

// Under `set -u`, bash 3.2 treats "${arr[@]}" on an empty array as unbound.
// propane, jobs-worker and the release scripts keep many arrays that are empty
// in normal runs (no async workers, passthrough args, shared paths or
// pre-package commands), so every expansion is guarded as ${arr[@]+"${arr[@]}"}.
- (void)testSupervisorScriptsGuardArrayExpansions {
  NSString *unguarded = @"(?<!\\+)\"\\$\\{[A-Za-z_][A-Za-z0-9_]*\\[@\\]\\}\"";
  NSMutableArray<NSString *> *violations = [NSMutableArray array];
  for (NSString *script in @[
         @"bin/jobs-worker", @"bin/propane", @"tools/deploy/build_release.sh", @"tools/deploy/rollback_release.sh"
       ]) {
    [violations addObjectsFromArray:[self violationsInScript:script
                                               matchingRegex:unguarded
                                                      reason:@"unguarded array expansion"]];
  }
  XCTAssertEqual((NSUInteger)0, [violations count], @"%@", [violations componentsJoinedByString:@"\n"]);
}

@end
