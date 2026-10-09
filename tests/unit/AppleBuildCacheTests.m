#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "../ALNXCTestCompat.h"

#import "../shared/ALNTestSupport.h"

// Exercises tools/apple_build_cache.sh, which the Apple build scripts use to
// skip up-to-date objects and links. Runs under /bin/bash so macOS covers the
// bash 3.2 path.
@interface AppleBuildCacheTests : XCTestCase
@end

@implementation AppleBuildCacheTests

- (NSString *)runCacheScript:(NSString *)body {
  NSString *workDir = ALNTestTemporaryDirectory(@"apple-build-cache");
  XCTAssertNotNil(workDir);
  NSString *scriptPath = [workDir stringByAppendingPathComponent:@"scenario.sh"];
  NSString *script = [NSString stringWithFormat:@"set -u\n"
                                                @"source %@\n"
                                                @"cd %@\n"
                                                @"%@\n",
                                                ALNTestShellQuote(ALNTestPathFromRepoRoot(@"tools/apple_build_cache.sh")),
                                                ALNTestShellQuote(workDir), body];
  NSError *error = nil;
  XCTAssertTrue(ALNTestWriteUTF8File(scriptPath, script, &error), @"%@", error);
  int exitCode = 0;
  NSString *output =
      ALNTestRunShellCapture([NSString stringWithFormat:@"/bin/bash %@ 2>&1", ALNTestShellQuote(scriptPath)],
                             &exitCode);
  XCTAssertEqual(0, exitCode, @"%@", output);
  [[NSFileManager defaultManager] removeItemAtPath:workDir error:nil];
  return output ?: @"";
}

- (void)testObjectTracksSourceAndHeadersFromDepfile {
#if defined(__APPLE__)
  NSString *output = [self runCacheScript:
      @"printf '#define X 1\\n' > 'my h.h'\n"
      @"printf '#include \"my h.h\"\\nint f(void) { return X; }\\n' > a.c\n"
      @"check() { if aln_apple_object_is_current a.c a.o; then echo \"$1=current\"; else echo \"$1=stale\"; fi; }\n"
      @"check missing\n"
      @"cc -MMD -MF a.d -c a.c -o a.o\n"
      @"check built\n"
      @"sleep 0.01; touch 'my h.h'\n"
      @"check header-touched\n"
      @"cc -MMD -MF a.d -c a.c -o a.o\n"
      @"check rebuilt\n"
      @"sleep 0.01; touch a.c\n"
      @"check source-touched\n"
      @"cc -MMD -MF a.d -c a.c -o a.o\n"
      @"mv 'my h.h' other.h\n"
      @"check header-removed\n"];
  XCTAssertEqualObjects(@"missing=stale\n"
                        @"built=current\n"
                        @"header-touched=stale\n"
                        @"rebuilt=current\n"
                        @"source-touched=stale\n"
                        @"header-removed=stale\n",
                        output);
#endif
}

- (void)testLinkTracksInputMtimesAndInputList {
#if defined(__APPLE__)
  NSString *output = [self runCacheScript:
      @"check() { if aln_apple_link_is_current m out \"${@:2}\"; then echo \"$1=current\"; else echo \"$1=stale\"; fi; }\n"
      @"touch a.o b.o\n"
      @"check unlinked a.o b.o\n"
      @"sleep 0.01; touch out; aln_apple_record_link_inputs m a.o b.o\n"
      @"check linked a.o b.o\n"
      @"check input-dropped a.o\n"
      @"sleep 0.01; touch b.o\n"
      @"check input-touched a.o b.o\n"];
  XCTAssertEqualObjects(@"unlinked=stale\n"
                        @"linked=current\n"
                        @"input-dropped=stale\n"
                        @"input-touched=stale\n",
                        output);
#endif
}

- (void)testSDKPathIsTheSameForEverySDKAlias {
#if defined(__APPLE__)
  NSString *output = [self runCacheScript:
      @"sdk_dir=\"$(dirname \"$(aln_apple_sdk_path)\")\"\n"
      @"for sdk in \"$sdk_dir\"/MacOSX*.sdk; do SDKROOT=\"$sdk\" aln_apple_sdk_path; done | sort -u | wc -l | tr -d ' '\n"];
  XCTAssertEqualObjects(@"1\n", output);
#endif
}

- (void)testFingerprintChangeClearsObjectRoot {
#if defined(__APPLE__)
  NSString *output = [self runCacheScript:
      @"aln_apple_reset_on_flag_change obj clang -O0\n"
      @"touch obj/a.o\n"
      @"aln_apple_reset_on_flag_change obj clang -O0\n"
      @"[[ -f obj/a.o ]] && echo same-flags=kept\n"
      @"aln_apple_reset_on_flag_change obj clang -O2\n"
      @"[[ -f obj/a.o ]] || echo new-flags=cleared\n"];
  XCTAssertEqualObjects(@"same-flags=kept\nnew-flags=cleared\n", output);
#endif
}

@end
