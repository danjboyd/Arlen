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

// Release activation (#225): `ln -sfn` unlinks releases/current before making
// the new link, so a respawn could find it missing. The link is now renamed
// into place. A watcher checks `current` while it is swapped back and forth.
- (void)testLinkDirectoryKeepsLinkPresentWhileSwapping {
#if defined(_WIN32)
  // MSYS2 links releases with NTFS junctions, which can't be renamed over;
  // deploy on Windows is 0.4.0 scope (#200).
  XCTSkip(@"junction swaps are not atomic on Windows; deploy is 0.4.0 scope");
#endif
  NSString *root = ALNTestTemporaryDirectory(@"arlen-link-swap");
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }
  @try {
    NSString *script = [NSString stringWithFormat:
        @"set -euo pipefail\n"
         "source %@\n"
         "cd %@\n"
         "mkdir -p rel1 rel2\n"
         "aln_platform_link_directory \"$PWD/rel1\" current\n"
         "( for i in $(seq 1 150); do\n"
         "    aln_platform_link_directory \"$PWD/rel2\" current\n"
         "    aln_platform_link_directory \"$PWD/rel1\" current\n"
         "  done\n"
         "  aln_platform_link_directory \"$PWD/rel2\" current ) &\n"
         "swapper=$!\n"
         "missing=0\n"
         "while kill -0 \"$swapper\" 2>/dev/null; do\n"
         "  [[ -L current ]] || missing=$((missing + 1))\n"
         "done\n"
         "wait \"$swapper\"\n"
         "echo \"missing=$missing\"\n"
         "echo \"target=$(readlink current)\"\n"
         "echo \"entries=$(ls -A | tr '\\n' ' ')\"\n"
         "echo \"rel2=$(ls -A rel2 | tr '\\n' ' ')\"\n",
        ALNTestShellQuote(ALNTestPathFromRepoRoot(@"tools/platform.sh")), ALNTestShellQuote(root)];
    int code = 0;
    NSString *output = ALNTestRunShellCapture(script, &code);
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"missing=0\n"], @"%@", output);
    NSString *expectedTarget =
        [NSString stringWithFormat:@"target=%@/rel2\n", [root stringByResolvingSymlinksInPath]];
    NSString *unresolvedTarget = [NSString stringWithFormat:@"target=%@/rel2\n", root];
    XCTAssertTrue([output containsString:expectedTarget] || [output containsString:unresolvedTarget], @"%@", output);
    // No temporary link is left behind, and the swap never links inside a release.
    XCTAssertTrue([output containsString:@"entries=current rel1 rel2 \n"], @"%@", output);
    XCTAssertTrue([output containsString:@"rel2=\n"], @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
  }
}

- (void)testActivateAndRollbackRepointCurrentLink {
  NSString *root = ALNTestTemporaryDirectory(@"arlen-activate-swap");
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }
  @try {
    NSString *releases = [root stringByAppendingPathComponent:@"releases"];
    NSString *script = [NSString stringWithFormat:
        @"set -euo pipefail\n"
         "releases=%@\n"
         "mkdir -p \"$releases/rel1/metadata\" \"$releases/rel2/metadata\"\n"
         "%@ --releases-dir \"$releases\" --release-id rel1 >/dev/null\n"
         "%@ --releases-dir \"$releases\" --release-id rel2 >/dev/null\n"
         "echo \"activated=$(basename \"$(readlink \"$releases/current\")\")\"\n"
         "echo \"entries=$(ls -A \"$releases\" | tr '\\n' ' ')\"\n"
         "%@ --releases-dir \"$releases\" --release-id rel1 >/dev/null\n"
         "echo \"rolledback=$(basename \"$(readlink \"$releases/current\")\")\"\n"
         "echo \"rel1=$(ls -A \"$releases/rel1\" | tr '\\n' ' ')\"\n",
        ALNTestShellQuote(releases),
        ALNTestShellQuote(ALNTestPathFromRepoRoot(@"tools/deploy/activate_release.sh")),
        ALNTestShellQuote(ALNTestPathFromRepoRoot(@"tools/deploy/activate_release.sh")),
        ALNTestShellQuote(ALNTestPathFromRepoRoot(@"tools/deploy/rollback_release.sh"))];
    int code = 0;
    NSString *output = ALNTestRunShellCapture(script, &code);
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"activated=rel2\n"], @"%@", output);
    XCTAssertTrue([output containsString:@"entries=current rel1 rel2 \n"], @"%@", output);
    XCTAssertTrue([output containsString:@"rolledback=rel1\n"], @"%@", output);
    XCTAssertTrue([output containsString:@"rel1=metadata \n"], @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
  }
}

@end
