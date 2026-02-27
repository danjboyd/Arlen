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
                               "$(ARC_REQUIRED_FLAG) $(FEATURE_FLAGS) $(EXTRA_OBJC_FLAGS)"]);
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

- (void)testGNUmakefileIncludesYYJSONCSourceInFrameworkBuilds {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefilePath = [repoRoot stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *makefile = [self readFile:makefilePath];

  XCTAssertTrue([makefile containsString:@"ARLEN_ENABLE_YYJSON ?= 1"]);
  XCTAssertTrue([makefile containsString:@"ARLEN_ENABLE_LLHTTP ?= 1"]);
  XCTAssertTrue([makefile containsString:@"ARLEN_ENABLE_YYJSON must be 0 or 1"]);
  XCTAssertTrue([makefile containsString:@"ARLEN_ENABLE_LLHTTP must be 0 or 1"]);
  XCTAssertTrue([makefile containsString:
                              @"FEATURE_FLAGS := -DARLEN_ENABLE_YYJSON=$(ARLEN_ENABLE_YYJSON) "
                               "-DARLEN_ENABLE_LLHTTP=$(ARLEN_ENABLE_LLHTTP)"]);
  XCTAssertTrue([makefile containsString:
                              @"YYJSON_C_SRCS := src/Arlen/Support/third_party/yyjson/yyjson.c"]);
  XCTAssertTrue([makefile containsString:@"LLHTTP_C_SRCS := src/Arlen/Support/third_party/llhttp/llhttp.c"]);
  XCTAssertTrue([makefile containsString:@"src/Arlen/Support/third_party/llhttp/api.c"]);
  XCTAssertTrue([makefile containsString:@"src/Arlen/Support/third_party/llhttp/http.c"]);
  XCTAssertTrue([makefile containsString:@"FRAMEWORK_SRCS += $(THIRD_PARTY_C_SRCS)"]);
  XCTAssertTrue([makefile containsString:
                              @"JSON_SERIALIZATION_SRCS := src/Arlen/Support/ALNJSONSerialization.m $(YYJSON_C_SRCS)"]);
}

- (void)testBoomhauerCompilePathIncludesYYJSONCSource {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"local enable_yyjson=\"${ARLEN_ENABLE_YYJSON:-1}\""]);
  XCTAssertTrue([script containsString:@"local enable_llhttp=\"${ARLEN_ENABLE_LLHTTP:-1}\""]);
  XCTAssertTrue([script containsString:@"ARLEN_ENABLE_YYJSON must be 0 or 1"]);
  XCTAssertTrue([script containsString:@"ARLEN_ENABLE_LLHTTP must be 0 or 1"]);
  XCTAssertTrue([script containsString:@"find \"$framework_root/src/Arlen/Support/third_party/yyjson\" -type f -name '*.c'"],
                @"boomhauer app compile path must include yyjson C source");
  XCTAssertTrue([script containsString:@"find \"$framework_root/src/Arlen/Support/third_party/llhttp\" -type f -name '*.c'"],
                @"boomhauer app compile path must include llhttp C sources");
  XCTAssertTrue([script containsString:@"-DARLEN_ENABLE_YYJSON=\"$enable_yyjson\""]);
  XCTAssertTrue([script containsString:@"-DARLEN_ENABLE_LLHTTP=\"$enable_llhttp\""]);
}

- (void)testGNUmakefileIncludesJSONReliabilityGateTargets {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefilePath = [repoRoot stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *makefile = [self readFile:makefilePath];

  XCTAssertTrue([makefile containsString:@"ci-json-abstraction:"]);
  XCTAssertTrue([makefile containsString:@"ci-json-perf:"]);
  XCTAssertTrue([makefile containsString:@"ci-dispatch-perf:"]);
  XCTAssertTrue([makefile containsString:@"ci-http-parse-perf:"]);
  XCTAssertTrue([makefile containsString:@"ci-route-match-perf:"]);
  XCTAssertTrue([makefile containsString:@"ci-backend-parity-matrix:"]);
  XCTAssertTrue([makefile containsString:@"ci-protocol-adversarial:"]);
  XCTAssertTrue([makefile containsString:@"ci-syscall-faults:"]);
  XCTAssertTrue([makefile containsString:@"ci-allocation-faults:"]);
  XCTAssertTrue([makefile containsString:@"ci-soak:"]);
  XCTAssertTrue([makefile containsString:@"ci-chaos-restart:"]);
  XCTAssertTrue([makefile containsString:@"ci-static-analysis:"]);
  XCTAssertTrue([makefile containsString:@"ci-blob-throughput:"]);
  XCTAssertTrue([makefile containsString:@"check: ci-json-abstraction"]);
}

- (void)testPhase5EQualityPipelineIncludesJSONPerformanceGate {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase5e_quality.sh"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"check_runtime_json_abstraction.py"]);
  XCTAssertTrue([script containsString:@"run_phase10e_json_performance.sh"]);
  XCTAssertTrue([script containsString:@"run_phase10g_dispatch_performance.sh"]);
  XCTAssertTrue([script containsString:@"run_phase10h_http_parse_performance.sh"]);
  XCTAssertTrue([script containsString:@"run_phase10m_blob_throughput.sh"]);
}

@end
