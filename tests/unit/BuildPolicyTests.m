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
  XCTAssertTrue([makefile containsString:@"PIC_FLAG := -fPIC"]);
  XCTAssertTrue([makefile containsString:
                              @"COMMON_COMPILE_FLAGS := $(FEATURE_FLAGS) $(THIRD_PARTY_FEATURE_FLAGS) "
                               "$(PIC_FLAG) $(EXTRA_OBJC_FLAGS)"]);
  XCTAssertTrue([makefile containsString:
                              @"override OBJC_FLAGS := $$(gnustep-config --objc-flags) "
                               "$(ARC_REQUIRED_FLAG) $(COMMON_COMPILE_FLAGS)"]);
  XCTAssertTrue([makefile containsString:
                              @"override C_COMPILE_FLAGS := $$(gnustep-config --objc-flags) "
                               "$(COMMON_COMPILE_FLAGS)"]);
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
    XCTAssertTrue([trimmed containsString:@"$(OBJC_FLAGS)"] ||
                      [trimmed containsString:@"$(C_COMPILE_FLAGS)"],
                  @"clang recipe must compile or link with central flags: %@", trimmed);
    XCTAssertFalse([trimmed containsString:@"$(gnustep-config --objc-flags)"],
                   @"clang recipe must not bypass ARC policy flags directly: %@", trimmed);
  }

  XCTAssertTrue(clangRecipeCount > 0, @"expected at least one clang recipe in GNUmakefile");
}

- (void)testGNUmakefileCentralizesLinkLibrariesWithDispatch {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefilePath = [repoRoot stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *makefile = [self readFile:makefilePath];

  XCTAssertTrue([makefile containsString:@"ARLEN_XCTEST ?= xctest"]);
  XCTAssertTrue([makefile containsString:@"ARLEN_XCTEST_LD_LIBRARY_PATH ?="]);
  XCTAssertTrue([makefile containsString:@"BASE_LINK_LIBS := $$(gnustep-config --base-libs) -ldl -lcrypto -ldispatch"]);
  XCTAssertTrue([makefile containsString:@"XCTEST_LINK_LIBS := $(BASE_LINK_LIBS) -lXCTest"]);
  XCTAssertTrue([makefile containsString:@"UNIT_TEST_TARGET_NAME := $(notdir $(basename $(UNIT_TEST_BUNDLE)))"]);
  XCTAssertTrue([makefile containsString:@"INTEGRATION_TEST_TARGET_NAME := $(notdir $(basename $(INTEGRATION_TEST_BUNDLE)))"]);
  XCTAssertTrue([makefile containsString:@"define xctest_filter_args"]);
  XCTAssertTrue([makefile containsString:@"define xctest_runtime_env"]);
  XCTAssertTrue([makefile containsString:@"test-unit-filter: $(UNIT_TEST_BIN)"]);
  XCTAssertTrue([makefile containsString:@"test-integration-filter: $(INTEGRATION_TEST_BIN)"]);
  XCTAssertTrue([makefile containsString:@"$(xctest_runtime_env) \"$(ARLEN_XCTEST)\" $(UNIT_TEST_BUNDLE)"]);
  XCTAssertTrue([makefile containsString:@"$(xctest_runtime_env) \"$(ARLEN_XCTEST)\" $(INTEGRATION_TEST_BUNDLE)"]);
  XCTAssertTrue([makefile containsString:@"$(xctest_runtime_env) \"$(ARLEN_XCTEST)\" $(BROWSER_ERROR_AUDIT_TEST_BUNDLE)"]);
  XCTAssertTrue([makefile containsString:@"-only-testing:$(1)/$(strip $(TEST))"]);
  XCTAssertTrue([makefile containsString:@"-skip-testing:$(1)/$(strip $(SKIP_TEST))"]);
  XCTAssertTrue([makefile containsString:@"LD_LIBRARY_PATH=\"$(ARLEN_XCTEST_LD_LIBRARY_PATH)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}\""]);
  XCTAssertTrue([makefile containsString:@"$(call xctest_filter_args,$(UNIT_TEST_TARGET_NAME))"]);
  XCTAssertTrue([makefile containsString:@"$(call xctest_filter_args,$(INTEGRATION_TEST_TARGET_NAME))"]);
}

- (void)testGNUmakefileUsesIncrementalObjectsDepfilesAndManifestedTemplates {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefilePath = [repoRoot stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *makefile = [self readFile:makefilePath];

  XCTAssertTrue([makefile containsString:@"OBJ_DIR := $(BUILD_DIR)/obj"]);
  XCTAssertTrue([makefile containsString:@"LIB_DIR := $(BUILD_DIR)/lib"]);
  XCTAssertTrue([makefile containsString:@"ARLEN_FRAMEWORK_LIB := $(LIB_DIR)/libArlenFramework.a"]);
  XCTAssertTrue([makefile containsString:@"ROOT_TEMPLATE_MANIFEST := $(GEN_DIR)/manifest.json"]);
  XCTAssertTrue([makefile containsString:@"TECH_DEMO_TEMPLATE_MANIFEST := $(TECH_DEMO_GEN_DIR)/manifest.json"]);
  XCTAssertTrue([makefile containsString:@"ROOT_TRANSPILE_STATE := $(GEN_DIR)/.transpile.state"]);
  XCTAssertTrue([makefile containsString:@"MODULE_TRANSPILE_STATE := $(MODULE_GEN_DIR)/.transpile.state"]);
  XCTAssertTrue([makefile containsString:@"ROOT_TEMPLATE_DIRS := $(shell if [ -d $(TEMPLATE_ROOT) ]; then find $(TEMPLATE_ROOT) -type d | sort; fi)"]);
  XCTAssertTrue([makefile containsString:@"framework-artifacts: eocc $(ARLEN_FRAMEWORK_LIB)"]);
  XCTAssertTrue([makefile containsString:@"-MMD -MP -MF $(@:.o=.d) -c $< -o $@"]);
  XCTAssertTrue([makefile containsString:
                              @"$(EOC_TOOL) --template-root $(TEMPLATE_ROOT) --output-dir $(GEN_DIR) "
                               "--manifest $(ROOT_TEMPLATE_MANIFEST) $(TEMPLATE_FILES);"]);
  XCTAssertTrue([makefile containsString:@"$(GEN_DIR)/%.html.eoc.m: $(TEMPLATE_ROOT)/%.html.eoc | $(ROOT_TRANSPILE_STATE)"]);
  XCTAssertTrue([makefile containsString:@"$(TECH_DEMO_GEN_DIR)/%.html.eoc.m: $(TECH_DEMO_TEMPLATE_ROOT)/%.html.eoc | $(TECH_DEMO_TRANSPILE_STATE)"]);
  XCTAssertTrue([makefile containsString:@"$(call module_generated_source_for,$(1)): $(1) | $(MODULE_TRANSPILE_STATE)"]);
  XCTAssertFalse([makefile containsString:@"FORCE:"]);
}

- (void)testGNUmakefileInvalidatesRepoArtifactsWhenCompileFlagsChange {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefilePath = [repoRoot stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *makefile = [self readFile:makefilePath];

  XCTAssertTrue([makefile containsString:
                              @"BUILD_FLAGS_SENTINEL_INPUT := GNUSTEP_SH=$(GNUSTEP_SH)|"
                               "ARC_REQUIRED_FLAG=$(ARC_REQUIRED_FLAG)|PIC_FLAG=$(PIC_FLAG)|"
                               "FEATURE_FLAGS=$(FEATURE_FLAGS)|THIRD_PARTY_FEATURE_FLAGS="
                               "$(THIRD_PARTY_FEATURE_FLAGS)|EXTRA_OBJC_FLAGS=$(EXTRA_OBJC_FLAGS)"]);
  XCTAssertTrue([makefile containsString:
                              @"BUILD_FLAGS_SENTINEL := $(BUILD_DIR)/.build-flags."
                               "$(BUILD_FLAGS_SENTINEL_HASH)"]);
  XCTAssertTrue([makefile containsString:@"$(BUILD_FLAGS_SENTINEL): | $(BUILD_DIR)"]);
  XCTAssertTrue([makefile containsString:@"@rm -f $(BUILD_DIR)/.build-flags.*"]);
  XCTAssertTrue([makefile containsString:
                              @"$(call root_generated_object_for,$(1)): $(BUILD_FLAGS_SENTINEL) "
                               "$(call root_generated_source_for,$(1)) $(1)"]);
  XCTAssertTrue([makefile containsString:@"$(OBJ_DIR)/%.o: %.m $(BUILD_FLAGS_SENTINEL)"]);
  XCTAssertTrue([makefile containsString:@"$(OBJ_DIR)/%.o: %.c $(BUILD_FLAGS_SENTINEL)"]);
}

- (void)testBoomhauerGeneratedAppMakefileEnforcesARCAndFrameworkReuse {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"printf 'FRAMEWORK_LIB := %s\\n' \"$framework_lib\""]);
  XCTAssertTrue([script containsString:@"printf 'GNUSTEP_OBJC_FLAGS := %s\\n' \"$gnustep_objc_flags\""]);
  XCTAssertTrue([script containsString:
                             @"printf 'OBJC_FLAGS := $(GNUSTEP_OBJC_FLAGS) -fobjc-arc -fPIC "
                              "-DARLEN_ENABLE_YYJSON=%s -DARLEN_ENABLE_LLHTTP=%s "
                              "-DARGON2_NO_THREADS=1\\n'"]);
  XCTAssertTrue([script containsString:
                             @"printf '>source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) "
                              "$(ALL_OBJECTS) $(FRAMEWORK_LIB) -o $(APP_BINARY) $(BASE_LINK_LIBS)\\n\\n'"]);
  XCTAssertTrue([script containsString:
                             @"printf '>source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) "
                              "-MMD -MP -MF %s -c %s -o %s\\n\\n'"]);
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
  XCTAssertTrue([makefile containsString:@"ARGON2_C_SRCS := src/Arlen/Support/third_party/argon2/src/argon2.c"]);
  XCTAssertTrue([makefile containsString:@"src/Arlen/Support/third_party/argon2/src/core.c"]);
  XCTAssertTrue([makefile containsString:@"src/Arlen/Support/third_party/argon2/src/encoding.c"]);
  XCTAssertTrue([makefile containsString:@"src/Arlen/Support/third_party/argon2/src/ref.c"]);
  XCTAssertTrue([makefile containsString:@"src/Arlen/Support/third_party/argon2/src/blake2/blake2b.c"]);
  XCTAssertTrue([makefile containsString:@"THIRD_PARTY_FEATURE_FLAGS := -DARGON2_NO_THREADS=1"]);
  XCTAssertTrue([makefile containsString:
                              @"FRAMEWORK_C_SRCS := $(YYJSON_C_SRCS) $(LLHTTP_C_SRCS) $(ARGON2_C_SRCS)"]);
  XCTAssertTrue([makefile containsString:@"FRAMEWORK_SRCS := $(FRAMEWORK_OBJC_SRCS) $(FRAMEWORK_C_SRCS)"]);
  XCTAssertTrue([makefile containsString:
                              @"JSON_SERIALIZATION_SRCS := src/Arlen/Support/ALNJSONSerialization.m $(YYJSON_C_SRCS)"]);
}

- (void)testBoomhauerAppBuildUsesFeatureFlagsAndFrameworkArtifacts {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"local enable_yyjson=\"${ARLEN_ENABLE_YYJSON:-1}\""]);
  XCTAssertTrue([script containsString:@"local enable_llhttp=\"${ARLEN_ENABLE_LLHTTP:-1}\""]);
  XCTAssertTrue([script containsString:@"ARLEN_ENABLE_YYJSON must be 0 or 1"]);
  XCTAssertTrue([script containsString:@"ARLEN_ENABLE_LLHTTP must be 0 or 1"]);
  XCTAssertTrue([script containsString:@"framework_lib=\"$framework_root/build/lib/libArlenFramework.a\""]);
  XCTAssertTrue([script containsString:@"framework_artifacts_are_current() {"]);
  XCTAssertTrue([script containsString:@"make -q -C \"$framework_root\" \"$framework_root/build/eocc\" \"$framework_lib\""]);
  XCTAssertTrue([script containsString:@"find \"$framework_root/modules\" -mindepth 2 -maxdepth 2 -type d -name 'Sources'"],
                @"boomhauer app build must include first-party framework module headers");
  XCTAssertTrue([script containsString:@"find \"$app_root/modules\" -mindepth 2 -maxdepth 2 -type d -name 'Sources'"],
                @"boomhauer app build must include vendored app module headers");
  XCTAssertTrue([script containsString:@"-DARLEN_ENABLE_YYJSON=%s -DARLEN_ENABLE_LLHTTP=%s"]);
  XCTAssertTrue([script containsString:@"-DARGON2_NO_THREADS=1"]);
  XCTAssertTrue([script containsString:@"printf 'BASE_LINK_LIBS := %s -ldl -lcrypto -ldispatch\\n' \"$gnustep_base_libs\""]);
  XCTAssertTrue([script containsString:@"-ldispatch"]);
}

- (void)testBoomhauerRebuildsOrRejectsSanitizedExternalFrameworkArtifacts {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"framework_archive_contains_sanitizers() {"]);
  XCTAssertTrue([script containsString:@"symbol_dump=\"$(mktemp)\""]);
  XCTAssertTrue([script containsString:@"nm -A \"$archive_path\" >\"$symbol_dump\" 2>/dev/null"]);
  XCTAssertTrue([script containsString:@"grep -Eq '(__asan_|__ubsan_)' \"$symbol_dump\""]);
  XCTAssertTrue([script containsString:
                             @"boomhauer: [1/4] detected sanitizer-instrumented framework artifacts; rebuilding clean framework artifacts"]);
  XCTAssertTrue([script containsString:
                             @"make -C \"$framework_root\" clean &&"]);
  XCTAssertTrue([script containsString:
                             @"boomhauer: selected framework root contains sanitizer-instrumented framework artifacts:"]);
  XCTAssertTrue([script containsString:@"app-root builds link libArlenFramework.a without sanitizer runtimes"]);
  XCTAssertTrue([script containsString:@"framework_link_mode"]);
}

- (void)testBoomhauerReportsPhase19BuildStagesAndScopeModes {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"boomhauer: prepare-only mode; building app artifacts without starting the server"]);
  XCTAssertTrue([script containsString:@"boomhauer: route inspection mode; ensuring artifacts are current before printing routes"]);
  XCTAssertTrue([script containsString:@"boomhauer: [1/4]"]);
  XCTAssertTrue([script containsString:@"boomhauer: [2/4] transpiling templates"]);
  XCTAssertTrue([script containsString:@"boomhauer: [3/4]"]);
  XCTAssertTrue([script containsString:@"boomhauer: [4/4]"]);
}

- (void)testJobsWorkerCLIAndScriptAreShipped {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *toolPath = [repoRoot stringByAppendingPathComponent:@"tools/arlen.m"];
  NSString *tool = [self readFile:toolPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/jobs-worker"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([tool containsString:@"jobs worker [worker args...]"]);
  XCTAssertTrue([tool containsString:@"./bin/jobs-worker"]);
  XCTAssertTrue([script containsString:@"--run-scheduler"]);
  XCTAssertTrue([script containsString:@"--jobs-worker"]);
  XCTAssertTrue([script containsString:@"--no-watch --prepare-only"]);
}

- (void)testBoomhauerWatchModeBuildsFallbackServerLazily {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"ensure_error_server_built() {"]);
  XCTAssertTrue([script containsString:@"if ! ensure_error_server_built; then"]);
  XCTAssertFalse([script containsString:
                              @"if ! make -C \"$framework_root\" boomhauer >/dev/null; then\n"
                               "  echo \"boomhauer: failed to build fallback dev error server\" >&2\n"
                               "  exit 1\n"
                               "fi"],
                 @"watch mode should not build the fallback error server eagerly at startup");
}

- (void)testBoomhauerWatchModeAdvertisesAndRetriesBuildErrors {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"ARLEN_BOOMHAUER_BUILD_ERROR_RETRY_SECONDS"],
                @"watch mode should export retry cadence to the fallback server");
  XCTAssertTrue([script containsString:@"ARLEN_BOOMHAUER_BUILD_ERROR_AUTO_REFRESH_SECONDS"],
                @"watch mode should export browser auto-refresh cadence to the fallback server");
  XCTAssertTrue([script containsString:@"ARLEN_BOOMHAUER_BUILD_ERROR_RECOVERY_HINT"],
                @"watch mode should export a recovery hint to the fallback server");
  XCTAssertTrue([script containsString:@"boomhauer: retrying failed build..."],
                @"watch mode should periodically retry failed builds");
}

- (void)testBoomhauerWatchFingerprintUsesHighResolutionMetadataAndModuleHeaders {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"file_fingerprint_fields() {"]);
  XCTAssertTrue([script containsString:@"stat -c %y \"$path\""],
                @"watch mode should keep sub-second mtime precision");
  XCTAssertTrue([script containsString:@"stat -c %z \"$path\""],
                @"watch mode should keep sub-second ctime precision");
  XCTAssertTrue([script containsString:
                              @"append_fingerprint_entries \"$framework_root\" \"framework\" src modules GNUmakefile tools/eocc.m"],
                @"watch mode should invalidate on framework module header changes");
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

- (void)testPhase10MBlobThroughputGateUsesHighSampleDefaults {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase10m_blob_throughput.sh"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"repeats=\"${ARLEN_PHASE10M_BLOB_REPEATS:-5}\""]);
  XCTAssertTrue([script containsString:@"requests=\"${ARLEN_PHASE10M_BLOB_REQUESTS:-180}\""]);
  XCTAssertTrue([script containsString:@"perf_cooldown_seconds=\"${ARLEN_PERF_COOLDOWN_SECONDS:-15}\""]);
  XCTAssertTrue([script containsString:@"perf_retry_count=\"${ARLEN_PERF_RETRY_COUNT:-2}\""]);
  XCTAssertTrue([script containsString:@"phase10m blob throughput failed on attempt"]);
  XCTAssertTrue([script containsString:@"sleep \"$perf_cooldown_seconds\""]);
}

- (void)testGNUmakefileIncludesPerfSmokeTarget {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefilePath = [repoRoot stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *makefile = [self readFile:makefilePath];

  XCTAssertTrue([makefile containsString:@"ci-perf-smoke:"]);
}

- (void)testPhase4QualityPipelineRunsBroaderMacroPerfProfiles {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase4_quality.sh"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"run_perf_profile default"]);
  XCTAssertTrue([script containsString:@"run_perf_profile middleware_heavy"]);
  XCTAssertTrue([script containsString:@"run_perf_profile template_heavy"]);
  XCTAssertTrue([script containsString:@"run_perf_profile api_reference"]);
  XCTAssertTrue([script containsString:@"run_perf_profile migration_sample"]);
  XCTAssertTrue([script containsString:@"capture_perf_artifacts() {\n  local profile=\"$1\"\n  mkdir -p build/perf/ci"]);
  XCTAssertTrue([script containsString:@"perf_cooldown_seconds=\"${ARLEN_PERF_COOLDOWN_SECONDS:-15}\""]);
  XCTAssertTrue([script containsString:@"perf_retry_count=\"${ARLEN_PERF_RETRY_COUNT:-2}\""]);
  XCTAssertTrue([script containsString:@"retrying after cooldown"]);
  XCTAssertTrue([script containsString:@"sleep \"$perf_cooldown_seconds\""]);
}

- (void)testPhase10GDispatchPerformanceScriptRetriesAfterCooldown {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath =
      [repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase10g_dispatch_performance.sh"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"perf_cooldown_seconds=\"${ARLEN_PERF_COOLDOWN_SECONDS:-15}\""]);
  XCTAssertTrue([script containsString:@"perf_retry_count=\"${ARLEN_PERF_RETRY_COUNT:-2}\""]);
  XCTAssertTrue([script containsString:@"while (( attempt <= perf_retry_count )); do"]);
  XCTAssertTrue([script containsString:@"phase10g dispatch performance failed on attempt"]);
  XCTAssertTrue([script containsString:@"sleep \"$perf_cooldown_seconds\""]);
}

- (void)testPerfSmokeScriptDefaultsToTriageProfiles {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"tools/ci/run_perf_smoke.sh"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"ARLEN_PERF_SMOKE_PROFILES:-default,template_heavy"]);
  XCTAssertTrue([script containsString:@"make perf"]);
}

- (void)testDocsQualityPipelineIncludesRoadmapConsistencyCheck {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"tools/ci/run_docs_quality.sh"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"check_roadmap_consistency.py"]);
  XCTAssertTrue([script containsString:@"check_benchmark_contracts.py"]);
}

- (void)testGNUmakefileIncludesBenchmarkContractTarget {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefilePath = [repoRoot stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *makefile = [self readFile:makefilePath];

  XCTAssertTrue([makefile containsString:@"ci-benchmark-contracts:"]);
}

- (void)testSanitizerScriptsForceCleanBuildsBeforeInstrumentedLanes {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *phase4Script =
      [self readFile:[repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase4_sanitizers.sh"]];
  NSString *phase5eScript =
      [self readFile:[repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase5e_tsan_experimental.sh"]];
  NSString *phase10mScript = [self
      readFile:[repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase10m_sanitizer_matrix.sh"]];

  XCTAssertTrue([phase4Script containsString:@"make clean"]);
  XCTAssertTrue([phase5eScript containsString:@"make clean"]);
  XCTAssertTrue([phase10mScript containsString:@"make clean"]);
}

- (void)testTSANScriptStagesArtifactsOutsideCleanBuildTree {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *script = [self
      readFile:[repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase5e_tsan_experimental.sh"]];

  XCTAssertTrue([script containsString:@"staging_dir=\"$(mktemp -d)\""]);
  XCTAssertTrue([script containsString:@"staged_log_path=\"$staging_dir/tsan.log\""]);
  XCTAssertTrue([script containsString:@"staged_summary_path=\"$staging_dir/summary.json\""]);
  XCTAssertTrue([script containsString:@"finalize_artifacts() {"]);
  XCTAssertTrue([script containsString:@"mkdir -p \"$artifact_dir\""]);
  XCTAssertTrue([script containsString:@"cp \"$staged_log_path\" \"$log_path\""]);
  XCTAssertTrue([script containsString:@"cp \"$staged_summary_path\" \"$summary_path\""]);
  XCTAssertTrue([script containsString:@"trap cleanup EXIT"]);
  XCTAssertTrue([script containsString:@"second_deadlock_stack=1"]);
}

- (void)testCIToolchainInstallerSupportsClangGNUstepStrategies {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *script = [self
      readFile:[repoRoot stringByAppendingPathComponent:@"tools/ci/install_ci_dependencies.sh"]];

  XCTAssertTrue([script containsString:@"ARLEN_CI_GNUSTEP_STRATEGY"]);
  XCTAssertTrue([script containsString:@"case \"$strategy\" in"]);
  XCTAssertTrue([script containsString:@"apt)"]);
  XCTAssertTrue([script containsString:@"preinstalled)"]);
  XCTAssertTrue([script containsString:@"bootstrap)"]);
  XCTAssertTrue([script containsString:@"ARLEN_CI_GNUSTEP_BOOTSTRAP_SCRIPT"]);
  XCTAssertTrue([script containsString:@"gnustep-clang-tools-xctest"]);
  XCTAssertTrue([script containsString:@"gnustep-clang-make"]);
  XCTAssertTrue([script containsString:@"gnustep-clang-libs-base"]);
  XCTAssertTrue([script containsString:@"-fobjc-runtime=gnustep-2.2"]);
}

- (void)testGitHubWorkflowsUseCentralCIToolchainInstaller {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSArray<NSString *> *workflowPaths = @[
    @".github/workflows/phase3c-quality.yml",
    @".github/workflows/phase4-quality.yml",
    @".github/workflows/phase4-sanitizers.yml",
    @".github/workflows/docs-quality.yml",
  ];

  for (NSString *relativePath in workflowPaths) {
    NSString *workflow = [self readFile:[repoRoot stringByAppendingPathComponent:relativePath]];
    XCTAssertTrue([workflow containsString:@"ARLEN_CI_GNUSTEP_STRATEGY: preinstalled"],
                  @"workflow should declare clang GNUstep strategy: %@", relativePath);
    XCTAssertTrue([workflow containsString:@"bash ./tools/ci/install_ci_dependencies.sh"],
                  @"workflow should use central CI dependency installer: %@", relativePath);
  }
}

- (void)testBackendParityArtifactsRebuildPerFeatureCombo {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *script = [self
      readFile:[repoRoot stringByAppendingPathComponent:@"tools/ci/generate_phase10m_backend_parity_artifacts.py"]];

  XCTAssertTrue([script containsString:@"run_command([\"make\", \"clean\"], repo_root)"]);
}

- (void)testRuntimeConcurrencyProbeKeepsSerializedModeOnKeepAliveContract {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *script =
      [self readFile:[repoRoot stringByAppendingPathComponent:@"tools/ci/runtime_concurrency_probe.py"]];

  XCTAssertTrue([script containsString:@"run_mode(args.binary, \"serialized\", True, args.iterations)"]);
  XCTAssertTrue([script containsString:@"def reserve_port() -> int:"]);
  XCTAssertTrue([script containsString:@"sock.bind((\"127.0.0.1\", 0))"]);
  XCTAssertTrue([script containsString:@"log_tail = read_log_tail(log_path)"]);
  XCTAssertTrue([script containsString:@"server failed readiness probe"]);
}

- (void)testRuntimeFaultInjectionKeepAliveUsesRealCRLFRequests {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *script =
      [self readFile:[repoRoot stringByAppendingPathComponent:@"tools/ci/runtime_fault_injection.py"]];

  XCTAssertTrue([script containsString:@"f\"GET {path} HTTP/1.1\\r\\n\""]);
  XCTAssertTrue([script containsString:@"f\"Connection: {connection_header}\\r\\n\\r\\n\""]);
  XCTAssertFalse([script containsString:@"f\"GET {path} HTTP/1.1\\\\r\\\\n\""]);
  XCTAssertFalse([script containsString:@"f\"Connection: {connection_header}\\\\r\\\\n\\\\r\\\\n\""]);
}

- (void)testReleaseCertificationStartsFromCleanBuildTree {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *script = [self
      readFile:[repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase9j_release_certification.sh"]];

  XCTAssertTrue([script containsString:@"make clean"]);
  XCTAssertTrue([script containsString:@"bash ./tools/ci/run_phase5e_quality.sh"]);
  XCTAssertTrue([script containsString:@"stash_release_artifact_dir phase5e"]);
  XCTAssertTrue([script containsString:@"stash_release_artifact_dir phase9i"]);
  XCTAssertTrue([script containsString:@"restore_release_artifact_dir phase5e"]);
  XCTAssertTrue([script containsString:@"restore_release_artifact_dir phase9i"]);
}

@end
