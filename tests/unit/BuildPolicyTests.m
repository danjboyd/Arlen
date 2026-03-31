#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@interface BuildPolicyTests : XCTestCase
@end

@implementation BuildPolicyTests

- (BOOL)isThreadSanitizerRuntimeActive {
  NSString *ldPreload = [[[NSProcessInfo processInfo] environment] objectForKey:@"LD_PRELOAD"];
  return [ldPreload length] > 0;
}

- (NSString *)readFile:(NSString *)path {
  NSError *error = nil;
  NSString *contents =
      [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNotNil(contents);
  XCTAssertNil(error);
  return contents ?: @"";
}

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  NSString *path = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",
                                                               prefix ?: @"arlen",
                                                               [[NSUUID UUID] UUIDString]]];
  NSError *error = nil;
  BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&error];
  XCTAssertTrue(created, @"failed creating temp dir %@: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  return created ? path : nil;
}

- (BOOL)writeFile:(NSString *)path content:(NSString *)content {
  NSString *dir = [path stringByDeletingLastPathComponent];
  NSError *error = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&error]) {
    XCTFail(@"failed creating directory %@: %@", dir, error.localizedDescription);
    return NO;
  }
  if (![content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
    XCTFail(@"failed writing file %@: %@", path, error.localizedDescription);
    return NO;
  }
  return YES;
}

- (BOOL)makeExecutableAtPath:(NSString *)path {
  NSError *error = nil;
  BOOL updated = [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions : @0755 }
                                                  ofItemAtPath:path
                                                         error:&error];
  XCTAssertTrue(updated, @"failed marking %@ executable: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  return updated;
}

- (NSString *)shellQuoted:(NSString *)value {
  NSString *safeValue = value ?: @"";
  return [NSString stringWithFormat:@"'%@'",
                                    [safeValue stringByReplacingOccurrencesOfString:@"'"
                                                                            withString:@"'\"'\"'"]];
}

- (NSString *)runShellCapture:(NSString *)command exitCode:(int *)exitCode {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[ @"-lc", command ?: @"" ];
  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  task.standardOutput = stdoutPipe;
  task.standardError = stderrPipe;
  [task launch];
  [task waitUntilExit];

  if (exitCode != NULL) {
    *exitCode = task.terminationStatus;
  }
  NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding];
  return output ?: @"";
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
  XCTAssertTrue([makefile containsString:@"XCTEST_BUNDLE_RUNNER_TOOL := $(BUILD_DIR)/arlen-xctest-runner"]);
  XCTAssertTrue([makefile containsString:@"PHASE24_WINDOWS_TEMPLATE_TEST_TOOL := $(BUILD_DIR)/tests/ArlenPhase21TemplateTestsRunner"]);
  XCTAssertTrue([makefile containsString:@"PHASE24_WINDOWS_DB_SMOKE_TEST_TOOL := $(BUILD_DIR)/tests/ArlenPhase24WindowsDBSmokeTestsRunner"]);
  XCTAssertTrue([makefile containsString:@"BASE_LINK_LIBS := $(ARLEN_PLATFORM_LINK_DIRS) $$(gnustep-config --base-libs) -lcrypto -ldispatch $(ARLEN_PLATFORM_LINK_LIBS)"]);
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
  XCTAssertTrue([makefile containsString:@"phase24-windows-tests: $(PHASE24_WINDOWS_TEMPLATE_TEST_TOOL)"]);
  XCTAssertTrue([makefile containsString:@"PHASE24_WINDOWS_DB_SMOKE_TEST_BUNDLE := $(BUILD_DIR)/tests/ArlenPhase24WindowsDBSmokeTests.xctest"]);
  XCTAssertTrue([makefile containsString:@"PHASE24_WINDOWS_DB_SMOKE_TEST_SRCS := tests/phase24/Phase24WindowsTransportSmokeTests.m"]);
  XCTAssertTrue([makefile containsString:@"phase24-windows-db-smoke: $(PHASE24_WINDOWS_DB_SMOKE_TEST_TOOL)"]);
  XCTAssertTrue([makefile containsString:@"phase24-windows-confidence:"]);
  XCTAssertTrue([makefile containsString:@"bash ./tools/ci/run_phase24_windows_preview.sh"]);
  XCTAssertTrue([makefile containsString:@"\"$(PHASE24_WINDOWS_TEMPLATE_TEST_TOOL)\""]);
  XCTAssertTrue([makefile containsString:@"\"$(PHASE24_WINDOWS_DB_SMOKE_TEST_TOOL)\""]);
}

- (void)testWindowsPreviewBuildGraphIncludesDataLayerSources {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefile = [self readFile:[repoRoot stringByAppendingPathComponent:@"GNUmakefile"]];
  NSString *umbrella = [self readFile:[repoRoot stringByAppendingPathComponent:@"src/Arlen/Arlen.h"]];

  XCTAssertTrue([makefile containsString:@"ARLEN_DATA_SRCS := $(shell find src/Arlen/Data -type f -name '*.m' | sort)"]);
  XCTAssertTrue([makefile containsString:@"FRAMEWORK_OBJC_SRCS := $(WINDOWS_PREVIEW_FRAMEWORK_OBJC_SRCS) $(ARLEN_DATA_SRCS)"]);
  XCTAssertTrue([umbrella containsString:@"#import \"Data/ALNPg.h\""]);
  XCTAssertTrue([umbrella containsString:@"#import \"Data/ALNMSSQL.h\""]);
}

- (void)testGNUmakefileDefinesFocusedPhase20ConfidenceLanes {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *makefilePath = [repoRoot stringByAppendingPathComponent:@"GNUmakefile"];
  NSString *makefile = [self readFile:makefilePath];

  XCTAssertTrue([makefile containsString:
                              @"PHASE20_SQL_BUILDER_TEST_BUNDLE := $(BUILD_DIR)/tests/"
                               "ArlenPhase20SQLBuilderTests.xctest"]);
  XCTAssertTrue([makefile containsString:
                              @"PHASE20_SCHEMA_TEST_BUNDLE := $(BUILD_DIR)/tests/"
                               "ArlenPhase20SchemaTests.xctest"]);
  XCTAssertTrue([makefile containsString:
                              @"PHASE20_POSTGRES_LIVE_TEST_BUNDLE := $(BUILD_DIR)/tests/"
                               "ArlenPhase20PostgresLiveTests.xctest"]);
  XCTAssertTrue([makefile containsString:
                              @"PHASE20_MSSQL_LIVE_TEST_BUNDLE := $(BUILD_DIR)/tests/"
                               "ArlenPhase20MSSQLLiveTests.xctest"]);
  XCTAssertTrue([makefile containsString:
                              @"PHASE20_ROUTING_TEST_BUNDLE := $(BUILD_DIR)/tests/"
                               "ArlenPhase20RoutingTests.xctest"]);
  XCTAssertTrue([makefile containsString:@"TEST_SHARED_SRCS := $(shell find tests/shared -type f -name '*.m' 2>/dev/null | sort)"]);
  XCTAssertTrue([makefile containsString:@"phase20-sql-builder-tests: $(PHASE20_SQL_BUILDER_TEST_BIN)"]);
  XCTAssertTrue([makefile containsString:@"phase20-schema-tests: $(PHASE20_SCHEMA_TEST_BIN)"]);
  XCTAssertTrue([makefile containsString:@"phase20-postgres-live-tests: $(PHASE20_POSTGRES_LIVE_TEST_BIN)"]);
  XCTAssertTrue([makefile containsString:@"phase20-mssql-live-tests: $(PHASE20_MSSQL_LIVE_TEST_BIN)"]);
  XCTAssertTrue([makefile containsString:@"phase20-routing-tests: $(PHASE20_ROUTING_TEST_BIN)"]);
  XCTAssertTrue([makefile containsString:
                              @"phase20-focused: phase20-sql-builder-tests phase20-schema-tests "
                               "phase20-routing-tests phase20-postgres-live-tests "
                               "phase20-mssql-live-tests"]);
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
                              "-DARLEN_ENABLE_YYJSON=%s -DARLEN_ENABLE_LLHTTP=%s -DARLEN_WINDOWS_PREVIEW=%s "
                              "-DARGON2_NO_THREADS=1\\n'"]);
  XCTAssertTrue([script containsString:
                             @"printf '>source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) "
                              "$(ALL_OBJECTS) $(FRAMEWORK_LIB) -o $(APP_BINARY) $(BASE_LINK_LIBS)\\n\\n'"]);
  XCTAssertTrue([script containsString:
                             @"printf '>source $(GNUSTEP_SH) && clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) "
                              "-MMD -MP -MF %s -c %s -o %s\\n\\n'"]);
}

- (void)testPhase20FocusedRunnerScriptExecutesRepoNativeLaneTargets {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath =
      [repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase20_focused.sh"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"make -C \"$repo_root\" phase20-sql-builder-tests"]);
  XCTAssertTrue([script containsString:@"make -C \"$repo_root\" phase20-schema-tests"]);
  XCTAssertTrue([script containsString:@"make -C \"$repo_root\" phase20-routing-tests"]);
  XCTAssertTrue([script containsString:@"make -C \"$repo_root\" phase20-postgres-live-tests"]);
  XCTAssertTrue([script containsString:@"make -C \"$repo_root\" phase20-mssql-live-tests"]);
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
  XCTAssertTrue([script containsString:@"printf 'ARLEN_PLATFORM_LINK_LIBS := %s\\n' \"$platform_link_libs\""]);
  XCTAssertTrue([script containsString:@"printf 'BASE_LINK_LIBS := %s -lcrypto -ldispatch $(ARLEN_PLATFORM_LINK_LIBS)\\n' \"$gnustep_base_libs\""]);
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
  XCTAssertTrue([script containsString:@"python3 - \"$path\" <<'PY'"],
                @"watch mode should use a portable metadata probe");
  XCTAssertTrue([script containsString:@"stat_result.st_mtime_ns"],
                @"watch mode should keep sub-second mtime precision");
  XCTAssertTrue([script containsString:@"stat_result.st_ctime_ns"],
                @"watch mode should keep sub-second ctime precision");
  XCTAssertFalse([script containsString:@"sha256sum"],
                 @"watch mode should not depend on sha256sum on Windows preview");
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

- (void)testPhase10MLongRunSoakScriptRetriesAfterCooldown {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase10m_soak.sh"];
  NSString *script = [self readFile:scriptPath];

  XCTAssertTrue([script containsString:@"perf_cooldown_seconds=\"${ARLEN_PERF_COOLDOWN_SECONDS:-15}\""]);
  XCTAssertTrue([script containsString:@"perf_retry_count=\"${ARLEN_PERF_RETRY_COUNT:-2}\""]);
  XCTAssertTrue([script containsString:@"while (( attempt <= perf_retry_count )); do"]);
  XCTAssertTrue([script containsString:@"phase10m long-run soak failed on attempt"]);
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
  XCTAssertTrue([script containsString:
                              @"tsan_suppressions_file=\"${ARLEN_TSAN_SUPPRESSIONS_FILE:-$repo_root/tests/fixtures/sanitizers/phase9h_tsan.supp}\""]);
  XCTAssertTrue([script containsString:@"suppressions=$tsan_suppressions_file"]);
  XCTAssertTrue([script containsString:@"trap cleanup EXIT"]);
  XCTAssertTrue([script containsString:@"second_deadlock_stack=1"]);
}

- (void)testTSANHotPathsAvoidObjCSynchronizedMonitors {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *response =
      [self readFile:[repoRoot stringByAppendingPathComponent:@"src/Arlen/HTTP/ALNResponse.m"]];
  NSString *pg = [self readFile:[repoRoot stringByAppendingPathComponent:@"src/Arlen/Data/ALNPg.m"]];
  NSString *pgTests = [self readFile:[repoRoot stringByAppendingPathComponent:@"tests/unit/PgTests.m"]];

  XCTAssertTrue([response containsString:@"dispatch_once(&onceToken, ^{"]);
  XCTAssertTrue([response containsString:@"ALNResponseFaultInjectionStateLock(void)"]);
  XCTAssertFalse([response containsString:@"@synchronized([NSProcessInfo processInfo])"]);
  XCTAssertFalse([response containsString:@"@synchronized([ALNResponse class])"]);

  XCTAssertTrue([pg containsString:@"static NSLock *ALNLibpqLoadLock(void)"]);
  XCTAssertTrue([pg containsString:@"[loadLock lock];"]);
  XCTAssertFalse([pg containsString:@"@synchronized([ALNPg class])"]);
  XCTAssertFalse([pg containsString:@"@synchronized(ALNLibpqLoadLockToken())"]);

  XCTAssertTrue([pgTests containsString:@"NSLock *stateLock = [[NSLock alloc] init];"]);
  XCTAssertFalse([pgTests containsString:@"@synchronized(state)"]);
}

- (void)testTSANScriptBootstrapsEOCCUnsanitizedBeforeInstrumentedBuilds {
  if ([self isThreadSanitizerRuntimeActive]) {
    return;
  }
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *fixtureRoot = [self createTempDirectoryWithPrefix:@"arlen-tsan-fixture"];
  NSString *fakeBin = [self createTempDirectoryWithPrefix:@"arlen-tsan-fakebin"];
  XCTAssertNotNil(fixtureRoot);
  XCTAssertNotNil(fakeBin);
  if (fixtureRoot == nil || fakeBin == nil) {
    return;
  }

  @try {
    NSString *toolsDir = [fixtureRoot stringByAppendingPathComponent:@"tools/ci"];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:toolsDir
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error]);
    XCTAssertNil(error);

    NSString *sourceScript =
        [repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase5e_tsan_experimental.sh"];
    NSString *targetScript = [toolsDir stringByAppendingPathComponent:@"run_phase5e_tsan_experimental.sh"];
    XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:sourceScript
                                                          toPath:targetScript
                                                           error:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([self makeExecutableAtPath:targetScript]);

    NSString *probeScript = [toolsDir stringByAppendingPathComponent:@"runtime_concurrency_probe.py"];
    XCTAssertTrue([self writeFile:probeScript
                          content:@"import argparse\n"
                                  "import os\n"
                                  "import sys\n"
                                  "\n"
                                  "parser = argparse.ArgumentParser()\n"
                                  "parser.add_argument('--binary', required=True)\n"
                                  "parser.add_argument('--iterations', required=True)\n"
                                  "args = parser.parse_args()\n"
                                  "if not os.path.exists(args.binary):\n"
                                  "    sys.stderr.write('missing boomhauer binary\\n')\n"
                                  "    sys.exit(61)\n"
                                  "print(f'probe ok {args.binary} {args.iterations}')\n"]);

    NSString *dummyTSAN = [fakeBin stringByAppendingPathComponent:@"libtsan.so"];
    XCTAssertTrue([self writeFile:dummyTSAN content:@""]);

    NSString *fakeMake = [fakeBin stringByAppendingPathComponent:@"make"];
    XCTAssertTrue([self writeFile:fakeMake
                          content:@"#!/usr/bin/env bash\n"
                                  "set -euo pipefail\n"
                                  "repo_root=\"$(pwd)\"\n"
                                  "log_path=\"$repo_root/make.log\"\n"
                                  "bootstrap_eocc=\"\"\n"
                                  "make_extra_flags=\"${EXTRA_OBJC_FLAGS-}\"\n"
                                  "args=(\"$@\")\n"
                                  "for arg in \"${args[@]}\"; do\n"
                                  "  case \"$arg\" in\n"
                                  "    EOC_TOOL=*) bootstrap_eocc=\"${arg#EOC_TOOL=}\" ;;\n"
                                  "    EXTRA_OBJC_FLAGS=*) make_extra_flags=\"${arg#EXTRA_OBJC_FLAGS=}\" ;;\n"
                                  "  esac\n"
                                  "done\n"
                                  "printf 'MAKE_EXTRA_OBJC_FLAGS=%s ARGS=%s\\n' \"$make_extra_flags\" \"$*\" >>\"$log_path\"\n"
                                  "if [[ \" $* \" == *\" clean \"* ]]; then\n"
                                  "  rm -rf \"$repo_root/build\" \"$repo_root/.gnustep\" \"$repo_root/.gnustep-home\"\n"
                                  "  exit 0\n"
                                  "fi\n"
                                  "if [[ \" $* \" == *\" eocc \"* ]]; then\n"
                                  "  if [[ -n \"$make_extra_flags\" ]]; then\n"
                                  "    echo \"bootstrap_eocc_should_be_unsanitized\" >&2\n"
                                  "    exit 91\n"
                                  "  fi\n"
                                  "  if [[ -z \"$bootstrap_eocc\" ]]; then\n"
                                  "    echo \"missing_bootstrap_eocc\" >&2\n"
                                  "    exit 92\n"
                                  "  fi\n"
                                  "  mkdir -p \"$(dirname \"$bootstrap_eocc\")\" \"$repo_root/build/gen/templates\" \"$repo_root/build/gen/module_templates\"\n"
                                  "  : >\"$bootstrap_eocc\"\n"
                                  "  : >\"$repo_root/build/gen/templates/.transpile.state\"\n"
                                  "  : >\"$repo_root/build/gen/module_templates/.transpile.state\"\n"
                                  "  exit 0\n"
                                  "fi\n"
                                  "if [[ \" $* \" == *\" boomhauer \"* || \" $* \" == *\" arlen \"* || \" $* \" == *\" test-unit \"* ]]; then\n"
                                  "  if [[ \"$make_extra_flags\" != *\"-fsanitize=thread\"* ]]; then\n"
                                  "    echo \"sanitized_make_missing_flag\" >&2\n"
                                  "    exit 93\n"
                                  "  fi\n"
                                  "  if [[ -z \"$bootstrap_eocc\" ]]; then\n"
                                  "    echo \"missing_sanitized_eocc_assignment\" >&2\n"
                                  "    exit 94\n"
                                  "  fi\n"
                                  "  saw_hold_old=0\n"
                                  "  prev=\"\"\n"
                                  "  for arg in \"${args[@]}\"; do\n"
                                  "    if [[ \"$prev\" == \"-o\" && \"$arg\" == \"$bootstrap_eocc\" ]]; then\n"
                                  "      saw_hold_old=1\n"
                                  "      break\n"
                                  "    fi\n"
                                  "    prev=\"$arg\"\n"
                                  "  done\n"
                                  "  if [[ \"$saw_hold_old\" -ne 1 ]]; then\n"
                                  "    echo \"missing_make_hold_old\" >&2\n"
                                  "    exit 95\n"
                                  "  fi\n"
                                  "  mkdir -p \"$repo_root/build\" \"$repo_root/build/tests\"\n"
                                  "  if [[ \" $* \" == *\" boomhauer \"* ]]; then\n"
                                  "    : >\"$repo_root/build/boomhauer\"\n"
                                  "  fi\n"
                                  "  if [[ \" $* \" == *\" arlen \"* ]]; then\n"
                                  "    : >\"$repo_root/build/arlen\"\n"
                                  "    chmod 755 \"$repo_root/build/arlen\"\n"
                                  "  fi\n"
                                  "  exit 0\n"
                                  "fi\n"
                                  "echo \"unexpected_make_args: $*\" >&2\n"
                                  "exit 96\n"]);
    XCTAssertTrue([self makeExecutableAtPath:fakeMake]);

    NSString *fakeClang = [fakeBin stringByAppendingPathComponent:@"clang"];
    NSString *fakeClangContents =
        [NSString stringWithFormat:@"#!/usr/bin/env bash\n"
                                   "if [[ \"${1:-}\" == \"-print-file-name=libtsan.so\" ]]; then\n"
                                   "  printf '%%s\\n' %@\n"
                                   "  exit 0\n"
                                   "fi\n"
                                   "exec /usr/bin/clang \"$@\"\n",
                                   [self shellQuoted:dummyTSAN]];
    XCTAssertTrue([self writeFile:fakeClang content:fakeClangContents]);
    XCTAssertTrue([self makeExecutableAtPath:fakeClang]);

    NSString *command = [NSString
        stringWithFormat:@"cd %@ && LD_PRELOAD='' PATH=%@:$PATH bash ./tools/ci/run_phase5e_tsan_experimental.sh 2>&1",
                         [self shellQuoted:fixtureRoot],
                         [self shellQuoted:fakeBin]];
    int exitCode = 0;
    NSString *output = [self runShellCapture:command exitCode:&exitCode];

    XCTAssertEqual(0, exitCode, @"%@", output);
    XCTAssertTrue([output containsString:@"ci: tsan bootstrap eocc "], @"%@", output);
    XCTAssertTrue([output containsString:@"ci: phase5e tsan experimental run complete"], @"%@", output);

    NSString *makeLog = [self readFile:[fixtureRoot stringByAppendingPathComponent:@"make.log"]];
    XCTAssertTrue([makeLog containsString:@"ARGS=clean"], @"%@", makeLog);
    XCTAssertTrue([makeLog containsString:@"MAKE_EXTRA_OBJC_FLAGS= ARGS=EXTRA_OBJC_FLAGS= EOC_TOOL="],
                  @"%@", makeLog);
    XCTAssertTrue([makeLog containsString:@"eocc transpile module-transpile"], @"%@", makeLog);
    XCTAssertTrue([makeLog containsString:@"MAKE_EXTRA_OBJC_FLAGS=-fsanitize=thread -fno-omit-frame-pointer ARGS=EXTRA_OBJC_FLAGS=-fsanitize=thread -fno-omit-frame-pointer EOC_TOOL="],
                  @"%@", makeLog);
    XCTAssertTrue([makeLog containsString:@" -o "], @"%@", makeLog);
    XCTAssertTrue([makeLog containsString:@"arlen"], @"%@", makeLog);
    XCTAssertTrue([makeLog containsString:@"boomhauer"], @"%@", makeLog);
    XCTAssertTrue([makeLog containsString:@"test-unit"], @"%@", makeLog);

    NSString *artifactRoot = [fixtureRoot stringByAppendingPathComponent:@"build/sanitizers/tsan"];
    NSString *summary = [self readFile:[artifactRoot stringByAppendingPathComponent:@"summary.json"]];
    XCTAssertTrue([summary containsString:@"\"status\": \"pass\""], @"%@", summary);
    XCTAssertTrue([summary containsString:@"\"exit_code\": 0"], @"%@", summary);

    NSString *tsanLog = [self readFile:[artifactRoot stringByAppendingPathComponent:@"tsan.log"]];
    XCTAssertTrue([tsanLog containsString:@"ci: tsan bootstrap eocc "], @"%@", tsanLog);
    XCTAssertTrue([tsanLog containsString:@"probe ok ./build/boomhauer 1"], @"%@", tsanLog);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:fixtureRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:fakeBin error:nil];
  }
}

- (void)testTSANScriptStopsOnInstrumentedFailureBeforeRuntimeProbe {
  if ([self isThreadSanitizerRuntimeActive]) {
    return;
  }
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *fixtureRoot = [self createTempDirectoryWithPrefix:@"arlen-tsan-fail-fixture"];
  NSString *fakeBin = [self createTempDirectoryWithPrefix:@"arlen-tsan-fail-fakebin"];
  XCTAssertNotNil(fixtureRoot);
  XCTAssertNotNil(fakeBin);
  if (fixtureRoot == nil || fakeBin == nil) {
    return;
  }

  @try {
    NSString *toolsDir = [fixtureRoot stringByAppendingPathComponent:@"tools/ci"];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:toolsDir
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error]);
    XCTAssertNil(error);

    NSString *sourceScript =
        [repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase5e_tsan_experimental.sh"];
    NSString *targetScript = [toolsDir stringByAppendingPathComponent:@"run_phase5e_tsan_experimental.sh"];
    XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:sourceScript
                                                          toPath:targetScript
                                                           error:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([self makeExecutableAtPath:targetScript]);

    NSString *probeScript = [toolsDir stringByAppendingPathComponent:@"runtime_concurrency_probe.py"];
    XCTAssertTrue([self writeFile:probeScript
                          content:@"import pathlib\n"
                                  "(pathlib.Path('probe-ran.txt')).write_text('ran\\n', encoding='utf-8')\n"
                                  "print('probe ran')\n"]);

    NSString *dummyTSAN = [fakeBin stringByAppendingPathComponent:@"libtsan.so"];
    XCTAssertTrue([self writeFile:dummyTSAN content:@""]);

    NSString *fakeMake = [fakeBin stringByAppendingPathComponent:@"make"];
    XCTAssertTrue([self writeFile:fakeMake
                          content:@"#!/usr/bin/env bash\n"
                                  "set -euo pipefail\n"
                                  "repo_root=\"$(pwd)\"\n"
                                  "bootstrap_eocc=\"\"\n"
                                  "make_extra_flags=\"${EXTRA_OBJC_FLAGS-}\"\n"
                                  "args=(\"$@\")\n"
                                  "for arg in \"${args[@]}\"; do\n"
                                  "  case \"$arg\" in\n"
                                  "    EOC_TOOL=*) bootstrap_eocc=\"${arg#EOC_TOOL=}\" ;;\n"
                                  "    EXTRA_OBJC_FLAGS=*) make_extra_flags=\"${arg#EXTRA_OBJC_FLAGS=}\" ;;\n"
                                  "  esac\n"
                                  "done\n"
                                  "if [[ \" $* \" == *\" clean \"* ]]; then\n"
                                  "  rm -rf \"$repo_root/build\" \"$repo_root/.gnustep\" \"$repo_root/.gnustep-home\"\n"
                                  "  exit 0\n"
                                  "fi\n"
                                  "if [[ \" $* \" == *\" eocc \"* ]]; then\n"
                                  "  mkdir -p \"$(dirname \"$bootstrap_eocc\")\" \"$repo_root/build/gen/templates\" \"$repo_root/build/gen/module_templates\"\n"
                                  "  : >\"$bootstrap_eocc\"\n"
                                  "  : >\"$repo_root/build/gen/templates/.transpile.state\"\n"
                                  "  : >\"$repo_root/build/gen/module_templates/.transpile.state\"\n"
                                  "  exit 0\n"
                                  "fi\n"
                                  "if [[ \" $* \" == *\" boomhauer \"* || \" $* \" == *\" arlen \"* ]]; then\n"
                                  "  mkdir -p \"$repo_root/build\"\n"
                                  "  : >\"$repo_root/build/boomhauer\"\n"
                                  "  if [[ \" $* \" == *\" arlen \"* ]]; then\n"
                                  "    : >\"$repo_root/build/arlen\"\n"
                                  "    chmod 755 \"$repo_root/build/arlen\"\n"
                                  "  fi\n"
                                  "  exit 0\n"
                                  "fi\n"
                                  "if [[ \" $* \" == *\" test-unit \"* ]]; then\n"
                                  "  echo \"stub test-unit failure\"\n"
                                  "  exit 88\n"
                                  "fi\n"
                                  "echo \"unexpected_make_args: $*\" >&2\n"
                                  "exit 96\n"]);
    XCTAssertTrue([self makeExecutableAtPath:fakeMake]);

    NSString *fakeClang = [fakeBin stringByAppendingPathComponent:@"clang"];
    NSString *fakeClangContents =
        [NSString stringWithFormat:@"#!/usr/bin/env bash\n"
                                   "if [[ \"${1:-}\" == \"-print-file-name=libtsan.so\" ]]; then\n"
                                   "  printf '%%s\\n' %@\n"
                                   "  exit 0\n"
                                   "fi\n"
                                   "exec /usr/bin/clang \"$@\"\n",
                                   [self shellQuoted:dummyTSAN]];
    XCTAssertTrue([self writeFile:fakeClang content:fakeClangContents]);
    XCTAssertTrue([self makeExecutableAtPath:fakeClang]);

    NSString *command = [NSString
        stringWithFormat:@"cd %@ && LD_PRELOAD='' PATH=%@:$PATH bash ./tools/ci/run_phase5e_tsan_experimental.sh 2>&1",
                         [self shellQuoted:fixtureRoot],
                         [self shellQuoted:fakeBin]];
    int exitCode = 0;
    NSString *output = [self runShellCapture:command exitCode:&exitCode];

    XCTAssertEqual(88, exitCode, @"%@", output);
    XCTAssertTrue([output containsString:@"stub test-unit failure"], @"%@", output);
    XCTAssertFalse([output containsString:@"ci: phase5e tsan experimental run complete"], @"%@", output);

    NSString *probeMarker = [fixtureRoot stringByAppendingPathComponent:@"probe-ran.txt"];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:probeMarker]);

    NSString *summary =
        [self readFile:[fixtureRoot stringByAppendingPathComponent:@"build/sanitizers/tsan/summary.json"]];
    XCTAssertTrue([summary containsString:@"\"status\": \"fail\""], @"%@", summary);
    XCTAssertTrue([summary containsString:@"\"exit_code\": 88"], @"%@", summary);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:fixtureRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:fakeBin error:nil];
  }
}

- (void)testThreadRaceNightlyPropagatesUnderlyingTSANFailureExitCodeAndPreservesLog {
  if ([self isThreadSanitizerRuntimeActive]) {
    return;
  }
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *fixtureRoot = [self createTempDirectoryWithPrefix:@"arlen-thread-race-fixture"];
  NSString *fakeBin = [self createTempDirectoryWithPrefix:@"arlen-thread-race-fakebin"];
  XCTAssertNotNil(fixtureRoot);
  XCTAssertNotNil(fakeBin);
  if (fixtureRoot == nil || fakeBin == nil) {
    return;
  }

  @try {
    NSString *toolsDir = [fixtureRoot stringByAppendingPathComponent:@"tools/ci"];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:toolsDir
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error]);
    XCTAssertNil(error);

    NSString *sourceScript =
        [repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase10m_thread_race_nightly.sh"];
    NSString *targetScript =
        [toolsDir stringByAppendingPathComponent:@"run_phase10m_thread_race_nightly.sh"];
    XCTAssertTrue([[NSFileManager defaultManager] copyItemAtPath:sourceScript
                                                          toPath:targetScript
                                                           error:&error]);
    XCTAssertNil(error);
    XCTAssertTrue([self makeExecutableAtPath:targetScript]);

    NSString *stubTSAN = [toolsDir stringByAppendingPathComponent:@"run_phase5e_tsan_experimental.sh"];
    XCTAssertTrue([self writeFile:stubTSAN
                          content:@"#!/usr/bin/env bash\n"
                                  "set -euo pipefail\n"
                                  "repo_root=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")/../..\" && pwd)\"\n"
                                  "artifact_dir=\"${ARLEN_TSAN_ARTIFACT_DIR:?}\"\n"
                                  "rm -rf \"$repo_root/build\"\n"
                                  "mkdir -p \"$artifact_dir\"\n"
                                  "printf 'stub tsan failure\\n' >\"$artifact_dir/tsan.log\"\n"
                                  "cat >\"$artifact_dir/summary.json\" <<'EOF'\n"
                                  "{\n"
                                  "  \"version\": \"phase9h-tsan-run-v1\",\n"
                                  "  \"status\": \"fail\",\n"
                                  "  \"exit_code\": 77,\n"
                                  "  \"reason\": \"tsan_lane_failure\",\n"
                                  "  \"log_path\": \"stub-tsan.log\"\n"
                                  "}\n"
                                  "EOF\n"
                                  "echo \"stub tsan failure\"\n"
                                  "exit 77\n"]);
    XCTAssertTrue([self makeExecutableAtPath:stubTSAN]);

    NSString *dummyTSAN = [fakeBin stringByAppendingPathComponent:@"libtsan.so"];
    XCTAssertTrue([self writeFile:dummyTSAN content:@""]);

    NSString *fakeMake = [fakeBin stringByAppendingPathComponent:@"make"];
    XCTAssertTrue([self writeFile:fakeMake
                          content:@"#!/usr/bin/env bash\n"
                                  "exit 0\n"]);
    XCTAssertTrue([self makeExecutableAtPath:fakeMake]);

    NSString *fakeClang = [fakeBin stringByAppendingPathComponent:@"clang"];
    NSString *fakeClangContents =
        [NSString stringWithFormat:@"#!/usr/bin/env bash\n"
                                   "if [[ \"${1:-}\" == \"-print-file-name=libtsan.so\" ]]; then\n"
                                   "  printf '%%s\\n' %@\n"
                                   "  exit 0\n"
                                   "fi\n"
                                   "exec /usr/bin/clang \"$@\"\n",
                                   [self shellQuoted:dummyTSAN]];
    XCTAssertTrue([self writeFile:fakeClang content:fakeClangContents]);
    XCTAssertTrue([self makeExecutableAtPath:fakeClang]);

    NSString *command = [NSString
        stringWithFormat:@"cd %@ && LD_PRELOAD='' PATH=%@:$PATH bash ./tools/ci/run_phase10m_thread_race_nightly.sh 2>&1",
                         [self shellQuoted:fixtureRoot],
                         [self shellQuoted:fakeBin]];
    int exitCode = 0;
    NSString *output = [self runShellCapture:command exitCode:&exitCode];

    XCTAssertEqual(77, exitCode, @"%@", output);
    XCTAssertTrue([output containsString:@"phase10m-thread-race: engine=tsan"], @"%@", output);
    XCTAssertTrue([output containsString:@"ci: phase10m thread-race nightly failed (tsan)"],
                  @"%@", output);

    NSString *artifactRoot =
        [fixtureRoot stringByAppendingPathComponent:@"build/sanitizers/phase10m_thread_race"];
    NSString *summary = [self readFile:[artifactRoot stringByAppendingPathComponent:@"summary.json"]];
    XCTAssertTrue([summary containsString:@"\"status\": \"fail\""], @"%@", summary);
    XCTAssertTrue([summary containsString:@"\"engine\": \"tsan\""], @"%@", summary);
    XCTAssertTrue([summary containsString:@"\"exit_code\": 77"], @"%@", summary);
    XCTAssertTrue([summary containsString:@"\"reason\": \"tsan_lane_failure\""], @"%@", summary);

    NSString *threadLog = [self readFile:[artifactRoot stringByAppendingPathComponent:@"thread_race.log"]];
    XCTAssertTrue([threadLog containsString:@"phase10m-thread-race: engine=tsan"], @"%@", threadLog);
    XCTAssertTrue([threadLog containsString:@"stub tsan failure"], @"%@", threadLog);
    XCTAssertTrue([threadLog containsString:@"ci: phase10m thread-race nightly failed (tsan)"],
                  @"%@", threadLog);

    NSString *tsanSummary =
        [self readFile:[artifactRoot stringByAppendingPathComponent:@"tsan/summary.json"]];
    XCTAssertTrue([tsanSummary containsString:@"\"exit_code\": 77"], @"%@", tsanSummary);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:fixtureRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:fakeBin error:nil];
  }
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

- (void)testWindowsPreviewWorkflowUsesCheckedInCLANG64EntryPoint {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workflow = [self
      readFile:[repoRoot stringByAppendingPathComponent:@".github/workflows/phase24-windows-preview.yml"]];
  NSString *script = [self
      readFile:[repoRoot stringByAppendingPathComponent:@"tools/ci/run_phase24_windows_preview.sh"]];

  XCTAssertTrue([workflow containsString:@"runs-on: [self-hosted, Windows, X64, arlen, msys2-clang64]"]);
  XCTAssertTrue([workflow containsString:@"scripts\\run_clang64.ps1 -InnerCommand \"bash ./tools/ci/run_phase24_windows_preview.sh\""]);
  XCTAssertTrue([script containsString:@"make -C \"$REPO_ROOT\" all"]);
  XCTAssertTrue([script containsString:@"make -C \"$REPO_ROOT\" phase24-windows-tests"]);
  XCTAssertTrue([script containsString:@"make -C \"$REPO_ROOT\" phase24-windows-db-smoke"]);
  XCTAssertTrue([script containsString:@"\"$REPO_ROOT/build/arlen\" doctor --json >\"$SMOKE_ROOT/doctor.json\""]);
  XCTAssertTrue([script containsString:@"ARLEN_FRAMEWORK_ROOT=\"$REPO_ROOT\" \"$REPO_ROOT/build/arlen\" boomhauer --no-watch --prepare-only"]);
  XCTAssertTrue([script containsString:@"ARLEN_FRAMEWORK_ROOT=\"$REPO_ROOT\" \"$REPO_ROOT/build/arlen\" routes >\"$SMOKE_ROOT/routes.txt\""]);
}

- (void)testWindowsPreviewDoctorAndRuntimeContractsStayExplicit {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *cli = [self readFile:[repoRoot stringByAppendingPathComponent:@"tools/arlen.m"]];
  NSString *shellDoctor = [self readFile:[repoRoot stringByAppendingPathComponent:@"bin/arlen-doctor"]];
  NSString *propane = [self readFile:[repoRoot stringByAppendingPathComponent:@"bin/propane"]];
  NSString *jobsWorker = [self readFile:[repoRoot stringByAppendingPathComponent:@"bin/jobs-worker"]];

  XCTAssertTrue([cli containsString:@"make phase24-windows-confidence"]);
  XCTAssertTrue([cli containsString:@"Native Windows does not support propane"]);
  XCTAssertTrue([cli containsString:@"Native Windows does not support the first-party jobs worker loop"]);
  XCTAssertTrue([cli containsString:@"DoctorConfiguredLibraryPath(@\"ARLEN_LIBPQ_LIBRARY\""]);
  XCTAssertTrue([cli containsString:@"DoctorConfiguredLibraryPath(@\"ARLEN_ODBC_LIBRARY\""]);
  XCTAssertTrue([shellDoctor containsString:@"detect_configured_library ARLEN_LIBPQ_LIBRARY"]);
  XCTAssertTrue([shellDoctor containsString:@"detect_configured_library ARLEN_ODBC_LIBRARY"]);
  XCTAssertTrue([shellDoctor containsString:@"add_check \"libodbc\""]);
  XCTAssertTrue([propane containsString:@"docs/WINDOWS_RUNTIME_STORY.md"]);
  XCTAssertTrue([jobsWorker containsString:@"docs/WINDOWS_RUNTIME_STORY.md"]);
}

- (void)testPerfHarnessSupportsPinnedBaselineAndPolicyRoots {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *script =
      [self readFile:[repoRoot stringByAppendingPathComponent:@"tests/performance/run_perf.sh"]];

  XCTAssertTrue([script containsString:
                            @"baseline_root=\"${ARLEN_PERF_BASELINE_ROOT:-tests/performance/"
                             @"baselines}\""]);
  XCTAssertTrue([script containsString:
                            @"policy_root=\"${ARLEN_PERF_POLICY_ROOT:-tests/performance/"
                             @"policies}\""]);
  XCTAssertTrue([script containsString:
                            @"baseline_file=\"${ARLEN_PERF_BASELINE:-${baseline_root}/"
                             @"${PROFILE_NAME}.json}\""]);
  XCTAssertTrue([script containsString:
                            @"policy_file=\"${ARLEN_PERF_POLICY:-${policy_root}/${PROFILE_NAME}."
                             @"json}\""]);
  XCTAssertTrue([script containsString:
                            @"if [[ ! -f \"$policy_file\" && -f \"${policy_root}/policy.json\" ]]; "
                             @"then"]);
}

- (void)testPerfGitHubWorkflowsPinSelfHostedBaselineRoot {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSArray<NSString *> *workflowPaths = @[
    @".github/workflows/phase3c-quality.yml",
    @".github/workflows/phase4-quality.yml",
  ];

  for (NSString *relativePath in workflowPaths) {
    NSString *workflow = [self readFile:[repoRoot stringByAppendingPathComponent:relativePath]];
    XCTAssertTrue([workflow containsString:@"ARLEN_PERF_BASELINE_ROOT: tests/performance/baselines/iep-apt"],
                  @"workflow should pin iep-apt perf baselines: %@", relativePath);
  }
}

- (void)testSanitizerWorkflowRaisesSelfHostedSoakRetryBudget {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workflow = [self
      readFile:[repoRoot stringByAppendingPathComponent:@".github/workflows/phase4-sanitizers.yml"]];

  XCTAssertTrue([workflow containsString:@"Run Phase 10M sanitizer matrix gate"]);
  XCTAssertTrue([workflow containsString:@"ARLEN_PERF_RETRY_COUNT: \"3\""]);
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
