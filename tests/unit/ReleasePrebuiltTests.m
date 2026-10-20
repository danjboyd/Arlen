#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNTestSupport.h"

// Exercises tools/release_prebuilt.sh: bin/arlen and bin/boomhauer trust a
// release archive's prebuilt framework (no build/obj) only while
// build/.release-prebuilt matches the tree and the toolchain. Runs on every
// platform with a stand-in gnustep-cli state file.
@interface ReleasePrebuiltTests : XCTestCase
@end

@implementation ReleasePrebuiltTests

- (NSString *)runScenario:(NSString *)body {
  NSString *workDir = ALNTestTemporaryDirectory(@"release-prebuilt");
  XCTAssertNotNil(workDir);
  NSString *scriptPath = [workDir stringByAppendingPathComponent:@"scenario.sh"];
  NSString *script = [NSString stringWithFormat:@"set -u\n"
                                                @"source %@\n"
                                                @"cd %@\n"
                                                @"export ARLEN_TOOLCHAIN_STATE_FILE=\"$PWD/cli-state.json\"\n"
                                                @"state() { printf '{\\n  \"toolchain_version\":  \"%%s\",\\n  \"toolchain_artifact_sha256\":  \"%%s\"\\n}\\n' \"$1\" \"$2\" > cli-state.json; }\n"
                                                @"%@\n",
                                                ALNTestShellQuote(ALNTestPathFromRepoRoot(@"tools/release_prebuilt.sh")),
                                                ALNTestShellQuote(workDir), body];
  NSError *error = nil;
  XCTAssertTrue(ALNTestWriteUTF8File(scriptPath, script, &error), @"%@", error);
  int exitCode = 0;
  NSString *output =
      ALNTestRunShellCapture([NSString stringWithFormat:@"bash %@ 2>&1", ALNTestShellQuote(scriptPath)], &exitCode);
  XCTAssertEqual(0, exitCode, @"%@", output);
  [[NSFileManager defaultManager] removeItemAtPath:workDir error:nil];
  return output ?: @"";
}

- (void)testManifestTrustsMatchingTreeAndToolchainOnly {
  NSString *output = [self runScenario:
      @"mkdir -p src build/lib; echo one > src/a.m; touch build/arlen.exe build/lib/libArlenFramework.a\n"
      @"state 0.1.0 aaa\n"
      @"check() { if aln_release_prebuilt_is_current . build/arlen.exe build/lib/libArlenFramework.a 2>/dev/null; then echo \"$1=trusted\"; else echo \"$1=rebuild\"; fi; }\n"
      @"check no-manifest\n"
      @"aln_release_write_manifest .\n"
      @"grep -c '^toolchain=0.1.0$' build/.release-prebuilt\n"
      @"check matching\n"
      @"state 0.1.1 aaa\n"
      @"check toolchain-moved\n"
      @"[[ -f build/.release-prebuilt ]] || echo stale-manifest=removed\n"
      @"state 0.1.0 aaa; aln_release_write_manifest .\n"
      @"echo two > src/a.m\n"
      @"check source-edited\n"
      @"echo one > src/a.m\n"
      @"check source-restored\n"
      @"aln_release_write_manifest .; rm build/arlen.exe\n"
      @"check output-missing\n"];
  XCTAssertEqualObjects(@"no-manifest=rebuild\n"
                        @"1\n"
                        @"matching=trusted\n"
                        @"toolchain-moved=rebuild\n"
                        @"stale-manifest=removed\n"
                        @"source-edited=rebuild\n"
                        @"source-restored=rebuild\n"
                        @"output-missing=rebuild\n",
                        output);
}

// A toolchain republished under the same version only warns.
- (void)testToolchainChecksumChangeWarnsButStaysTrusted {
  NSString *output = [self runScenario:
      @"mkdir -p src build; echo one > src/a.m; touch build/arlen.exe\n"
      @"state 0.1.0 aaa; aln_release_write_manifest .\n"
      @"state 0.1.0 bbb\n"
      @"if aln_release_prebuilt_is_current . build/arlen.exe 2>warning.txt; then echo trusted; fi\n"
      @"grep -q 'toolchain artifact aaa; this toolchain is bbb' warning.txt && echo warned\n"];
  XCTAssertEqualObjects(@"trusted\nwarned\n", output);
}

// The check fails closed: with no SHA-256 tool or no toolchain version, no
// manifest is written and none is trusted (empty used to equal empty).
- (void)testMissingHasherOrToolchainVersionIsNeverTrusted {
  NSString *output = [self runScenario:
      @"mkdir -p src build tools-only; echo one > src/a.m; touch build/arlen.exe\n"
      @"for tool in find sort tr xargs awk sed head rm mkdir; do cp \"$(command -v $tool)\" tools-only/ 2>/dev/null || ln -s \"$(command -v $tool)\" tools-only/$tool; done\n"
      @"check() { if aln_release_prebuilt_is_current . build/arlen.exe 2>/dev/null; then echo \"$1=trusted\"; else echo \"$1=rebuild\"; fi; }\n"
      @"state 0.1.0 aaa\n"
      @"( PATH=\"$PWD/tools-only\"; aln_release_write_manifest . 2>/dev/null ) && echo wrote-without-hasher || echo no-hasher=refused\n"
      @"printf 'source_digest=\\ntoolchain=0.1.0\\nbuild_flags=%s\\n' \"$(aln_release_build_flags)\" > build/.release-prebuilt\n"
      @"( PATH=\"$PWD/tools-only\"; check empty-digest-no-hasher )\n"
      @"export ARLEN_TOOLCHAIN_STATE_FILE=\"$PWD/missing.json\"\n"
      @"aln_release_write_manifest . 2>/dev/null && echo wrote-without-toolchain || echo no-toolchain=refused\n"
      @"printf 'source_digest=%s\\ntoolchain=\\nbuild_flags=%s\\n' \"$(aln_release_source_digest .)\" \"$(aln_release_build_flags)\" > build/.release-prebuilt\n"
      @"check empty-toolchain\n"];
  XCTAssertEqualObjects(@"no-hasher=refused\n"
                        @"empty-digest-no-hasher=rebuild\n"
                        @"no-toolchain=refused\n"
                        @"empty-toolchain=rebuild\n",
                        output);
}

// The build-flag environment the GNUmakefile sentinel tracks is part of the
// manifest: an app built with ARLEN_ENABLE_LLHTTP=1 must not reuse a library
// built without it.
- (void)testBuildFlagChangeIsStale {
  NSString *output = [self runScenario:
      @"mkdir -p src build; echo one > src/a.m; touch build/arlen.exe\n"
      @"state 0.1.0 aaa; unset ARLEN_ENABLE_LLHTTP; aln_release_write_manifest .\n"
      @"if ARLEN_ENABLE_LLHTTP=1 aln_release_prebuilt_is_current . build/arlen.exe; then echo llhttp=trusted; else echo llhttp=rebuild; fi\n"];
  XCTAssertEqualObjects(@"llhttp=rebuild\n", output);
}

- (void)testUnixInstallerPreservesWorkingReleaseAndConfiguresPath {
#if defined(_WIN32)
  XCTSkip(@"Unix installer; Windows uses install.ps1");
#else
  int exitCode = 0;
  NSString *output = ALNTestRunShellCapture(
      [NSString stringWithFormat:@"bash %@ 2>&1",
       ALNTestShellQuote(ALNTestPathFromRepoRoot(@"tools/release/test_install.sh"))], &exitCode);
  XCTAssertEqual(0, exitCode, @"%@", output);
#endif
}

@end
