#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <arpa/inet.h>
#import <netinet/in.h>
#import <stdlib.h>
#import <string.h>
#import <sys/socket.h>

#import "../shared/ALNTestSupport.h"

@interface DeploymentIntegrationTests : XCTestCase
@end

@implementation DeploymentIntegrationTests

- (int)randomPort {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd >= 0) {
    int port = 0;
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;

    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) == 0) {
      socklen_t length = sizeof(address);
      if (getsockname(fd, (struct sockaddr *)&address, &length) == 0) {
        port = (int)ntohs(address.sin_port);
      }
    }

    close(fd);
    if (port > 0) {
      return port;
    }
  }

  return 34000 + (int)arc4random_uniform(2000);
}

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  NSString *templatePath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-XXXXXX", prefix]];
  const char *templateCString = [templatePath fileSystemRepresentation];
  char *buffer = strdup(templateCString);
  char *created = mkdtemp(buffer);
  NSString *result = created ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:created
                                                                                             length:strlen(created)]
                             : nil;
  free(buffer);
  return result;
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

- (NSString *)runShellCapture:(NSString *)command exitCode:(int *)exitCode {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"/bin/bash";
  task.arguments = @[ @"-lc", command ];
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
  NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
  NSString *stdoutText = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
  NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
  return [stdoutText stringByAppendingString:stderrText];
}

- (NSString *)runEOCCCaptureAtRepoRoot:(NSString *)repoRoot
                              workRoot:(NSString *)workRoot
                             arguments:(NSString *)arguments
                              exitCode:(int *)exitCode {
  NSString *gnuHome = [workRoot stringByAppendingPathComponent:@"gnu-home"];
  NSString *command = [NSString stringWithFormat:
      @"mkdir -p %@/GNUstep/Defaults/.lck && cd %@ && "
       "export HOME=%@ GNUSTEP_USER_DIR=%@/GNUstep GNUSTEP_USER_ROOT=%@/GNUstep "
       "GNUSTEP_USER_DEFAULTS_DIR=%@/GNUstep/Defaults && ./build/eocc %@",
      gnuHome, repoRoot, gnuHome, gnuHome, gnuHome, gnuHome, arguments];
  return [self runShellCapture:command exitCode:exitCode];
}

- (NSDictionary *)parseJSONDictionaryFromOutput:(NSString *)output context:(NSString *)context {
  NSString *trimmed =
      [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  XCTAssertTrue([trimmed length] > 0, @"%@ output was empty", context);
  if ([trimmed length] == 0) {
    return @{};
  }

  NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  XCTAssertNil(error, @"%@ produced invalid JSON: %@\n%@", context, error.localizedDescription, output);
  XCTAssertTrue([parsed isKindOfClass:[NSDictionary class]], @"%@ expected JSON object output\n%@", context, output);
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    return @{};
  }
  return parsed;
}

- (NSString *)shellQuoted:(NSString *)value {
  NSString *safeValue = value ?: @"";
  return [NSString stringWithFormat:@"'%@'",
                                    [safeValue stringByReplacingOccurrencesOfString:@"'"
                                                                            withString:@"'\"'\"'"]];
}

- (NSString *)gnustepSourceCommandForRepoRoot:(NSString *)repoRoot {
  return ALNTestGNUstepSourceCommandForRepoRoot(repoRoot);
}

- (NSString *)runMakeAtRepoRoot:(NSString *)repoRoot
                         target:(NSString *)target
                       exitCode:(int *)exitCode {
  NSString *command = [NSString stringWithFormat:
      @"%@ && cd %@ && make %@",
      [self gnustepSourceCommandForRepoRoot:repoRoot], [self shellQuoted:repoRoot], target ?: @""];
  return [self runShellCapture:command exitCode:exitCode];
}

- (NSString *)runMakeDryRunAtRepoRoot:(NSString *)repoRoot
                               target:(NSString *)target
                          touchingPath:(NSString *)path
                              exitCode:(int *)exitCode {
  NSString *command = [NSString stringWithFormat:
      @"set -euo pipefail && cd %@ && "
       "path=%@ && original_mtime=$(stat -c %%Y \"$path\") && "
       "restore() { touch -d \"@$original_mtime\" \"$path\"; }; "
       "trap restore EXIT && "
       "touch \"$path\" && make -n %@",
      [self shellQuoted:repoRoot], [self shellQuoted:path], target ?: @""];
  return [self runShellCapture:command exitCode:exitCode];
}

- (void)testFrameworkSourceTouchRebuildsOneObjectArchiveAndDependentLinks {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *frameworkSource = [repoRoot stringByAppendingPathComponent:@"src/Arlen/MVC/View/ALNView.m"];
  int code = 0;
  NSString *buildOutput = [self runMakeAtRepoRoot:repoRoot target:@"build-tests" exitCode:&code];
  XCTAssertEqual(0, code, @"%@", buildOutput);

  NSString *dryRun =
      [self runMakeDryRunAtRepoRoot:repoRoot
                             target:@"build-tests"
                        touchingPath:frameworkSource
                            exitCode:&code];
  NSString *archiveCommand =
      [NSString stringWithFormat:@"ar rcs %@/build/lib/libArlenFramework.a", repoRoot];
  NSString *frameworkCompileCommand = [NSString
      stringWithFormat:@"-c src/Arlen/MVC/View/ALNView.m -o %@/build/obj/src/Arlen/MVC/View/ALNView.o",
                       repoRoot];
  NSString *generatedIndexCompileCommand = [NSString
      stringWithFormat:@"-c build/gen/templates/index.html.eoc.m -o %@/build/obj/build/gen/templates/index.html.eoc.o",
                       repoRoot];
  NSString *unitCompileCommand = [NSString
      stringWithFormat:@"-c tests/unit/BuildPolicyTests.m -o %@/build/obj/tests/unit/BuildPolicyTests.o",
                       repoRoot];
  XCTAssertEqual(0, code, @"%@", dryRun);
  XCTAssertTrue([dryRun containsString:frameworkCompileCommand], @"%@", dryRun);
  XCTAssertTrue([dryRun containsString:archiveCommand], @"%@", dryRun);
  XCTAssertTrue([dryRun containsString:@"build/tests/ArlenUnitTests.xctest/ArlenUnitTests"], @"%@", dryRun);
  XCTAssertTrue([dryRun containsString:@"build/tests/ArlenIntegrationTests.xctest/ArlenIntegrationTests"],
                @"%@", dryRun);
  XCTAssertFalse([dryRun containsString:generatedIndexCompileCommand], @"%@", dryRun);
  XCTAssertFalse([dryRun containsString:unitCompileCommand], @"%@", dryRun);
}

- (void)testTemplateTouchRetranspilesOneGeneratedObjectAndDependentLinks {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *templatePath = [repoRoot stringByAppendingPathComponent:@"templates/index.html.eoc"];
  int code = 0;
  NSString *buildOutput = [self runMakeAtRepoRoot:repoRoot target:@"build-tests" exitCode:&code];
  XCTAssertEqual(0, code, @"%@", buildOutput);

  NSString *dryRun =
      [self runMakeDryRunAtRepoRoot:repoRoot
                             target:@"build-tests"
                        touchingPath:templatePath
                            exitCode:&code];
  NSString *transpileCommand = [NSString stringWithFormat:
      @"%@/build/eocc --template-root %@/templates "
       "--output-dir %@/build/gen/templates "
      "--manifest %@/build/gen/templates/manifest.json",
      repoRoot, repoRoot, repoRoot, repoRoot];
  NSString *generatedIndexCompileCommand = [NSString
      stringWithFormat:@"-c build/gen/templates/index.html.eoc.m -o %@/build/obj/build/gen/templates/index.html.eoc.o",
                       repoRoot];
  NSString *generatedLayoutCompileCommand = [NSString
      stringWithFormat:@"-c build/gen/templates/layouts/main.html.eoc.m -o %@/build/obj/build/gen/templates/layouts/main.html.eoc.o",
                       repoRoot];
  NSString *frameworkCompileCommand = [NSString
      stringWithFormat:@"-c src/Arlen/MVC/View/ALNView.m -o %@/build/obj/src/Arlen/MVC/View/ALNView.o",
                       repoRoot];
  XCTAssertEqual(0, code, @"%@", dryRun);
  XCTAssertTrue([dryRun containsString:transpileCommand], @"%@", dryRun);
  XCTAssertTrue([dryRun containsString:generatedIndexCompileCommand], @"%@", dryRun);
  XCTAssertFalse([dryRun containsString:generatedLayoutCompileCommand], @"%@",
                 dryRun);
  XCTAssertFalse([dryRun containsString:frameworkCompileCommand], @"%@", dryRun);
  XCTAssertTrue([dryRun containsString:@"build/tests/ArlenUnitTests.xctest/ArlenUnitTests"], @"%@", dryRun);
  XCTAssertTrue([dryRun containsString:@"build/tests/ArlenIntegrationTests.xctest/ArlenIntegrationTests"],
                @"%@", dryRun);
}

- (void)testUnitTestTouchDoesNotRebuildFrameworkOrIntegrationBundle {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *unitTestPath = [repoRoot stringByAppendingPathComponent:@"tests/unit/BuildPolicyTests.m"];
  int code = 0;
  NSString *buildOutput = [self runMakeAtRepoRoot:repoRoot target:@"build-tests" exitCode:&code];
  XCTAssertEqual(0, code, @"%@", buildOutput);

  NSString *dryRun =
      [self runMakeDryRunAtRepoRoot:repoRoot
                             target:@"build-tests"
                        touchingPath:unitTestPath
                            exitCode:&code];
  NSString *frameworkArchiveCommand =
      [NSString stringWithFormat:@"ar rcs %@/build/lib/libArlenFramework.a", repoRoot];
  NSString *unitCompileCommand = [NSString
      stringWithFormat:@"-c tests/unit/BuildPolicyTests.m -o %@/build/obj/tests/unit/BuildPolicyTests.o",
                       repoRoot];
  XCTAssertEqual(0, code, @"%@", dryRun);
  XCTAssertTrue([dryRun containsString:unitCompileCommand], @"%@", dryRun);
  XCTAssertTrue([dryRun containsString:@"build/tests/ArlenUnitTests.xctest/ArlenUnitTests"], @"%@", dryRun);
  XCTAssertFalse([dryRun containsString:@"build/tests/ArlenIntegrationTests.xctest/ArlenIntegrationTests"],
                 @"%@", dryRun);
  XCTAssertFalse([dryRun containsString:frameworkArchiveCommand], @"%@", dryRun);
  XCTAssertFalse([dryRun containsString:@"/build/eocc --template-root"], @"%@", dryRun);
}

- (void)testCompileTimeFeatureFlagsCanDisableYYJSONAndLLHTTP {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-feature-toggle-smoke"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    NSString *sourcePath = [workRoot stringByAppendingPathComponent:@"main.m"];
    NSString *binaryPath = [workRoot stringByAppendingPathComponent:@"feature-toggle-smoke"];
    XCTAssertTrue([self writeFile:sourcePath
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "#import \"ALNJSONSerialization.h\"\n"
                                  "#import \"ALNRequest.h\"\n"
                                  "#include <stdlib.h>\n"
                                  "\n"
                                  "int main(int argc, const char *argv[]) {\n"
                                  "  (void)argc;\n"
                                  "  (void)argv;\n"
                                  "  @autoreleasepool {\n"
                                  "    [ALNJSONSerialization resetBackendForTesting];\n"
                                  "    unsetenv(\"ARLEN_HTTP_PARSER_BACKEND\");\n"
                                  "    fprintf(stdout,\n"
                                  "            \"json_available=%d json_backend=%s yyjson_version=%s\\n\",\n"
                                  "            [ALNJSONSerialization isYYJSONAvailable] ? 1 : 0,\n"
                                  "            [[ALNJSONSerialization backendName] UTF8String],\n"
                                  "            [[ALNJSONSerialization yyjsonVersion] UTF8String]);\n"
                                  "    fprintf(stdout,\n"
                                  "            \"llhttp_available=%d parser_backend=%s llhttp_version=%s\\n\",\n"
                                  "            [ALNRequest isLLHTTPAvailable] ? 1 : 0,\n"
                                  "            [[ALNRequest resolvedParserBackendName] UTF8String],\n"
                                  "            [[ALNRequest llhttpVersion] UTF8String]);\n"
                                  "  }\n"
                                  "  return 0;\n"
                                  "}\n"]);

    int code = 0;
    NSString *compileOutput = [self runShellCapture:[NSString stringWithFormat:
        @"%@ && clang $(gnustep-config --objc-flags) "
         "-fobjc-arc -DARLEN_ENABLE_YYJSON=0 -DARLEN_ENABLE_LLHTTP=0 "
         "-I%@/src/Arlen -I%@/src/Arlen/HTTP -I%@/src/Arlen/Support "
         "%@ %@/src/Arlen/Support/ALNJSONSerialization.m %@/src/Arlen/HTTP/ALNRequest.m "
         "-o %@ $(gnustep-config --base-libs) -ldl -lcrypto",
        [self gnustepSourceCommandForRepoRoot:repoRoot], repoRoot, repoRoot, repoRoot, sourcePath, repoRoot, repoRoot, binaryPath]
                                       exitCode:&code];
    XCTAssertEqual(0, code, @"%@", compileOutput);

    NSString *runOutput = [self runShellCapture:binaryPath exitCode:&code];
    XCTAssertEqual(0, code, @"%@", runOutput);
    XCTAssertTrue([runOutput containsString:@"json_available=0"], @"%@", runOutput);
    XCTAssertTrue([runOutput containsString:@"json_backend=foundation"], @"%@", runOutput);
    XCTAssertTrue([runOutput containsString:@"yyjson_version=disabled"], @"%@", runOutput);
    XCTAssertTrue([runOutput containsString:@"llhttp_available=0"], @"%@", runOutput);
    XCTAssertTrue([runOutput containsString:@"parser_backend=legacy"], @"%@", runOutput);
    XCTAssertTrue([runOutput containsString:@"llhttp_version=disabled"], @"%@", runOutput);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testArlenUmbrellaHeaderCompilesAgainstTrackedSourceTreeOnly {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-umbrella-header-smoke"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    NSString *exportRoot = [workRoot stringByAppendingPathComponent:@"tracked-export"];
    NSString *sourcePath = [workRoot stringByAppendingPathComponent:@"umbrella-header-smoke.m"];
    XCTAssertTrue([self writeFile:sourcePath
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "#import \"Arlen.h\"\n"
                                  "int main(int argc, const char *argv[]) {\n"
                                  "  (void)argc;\n"
                                  "  (void)argv;\n"
                                  "  return 0;\n"
                                  "}\n"]);

    int code = 0;
    NSString *compileOutput = [self runShellCapture:[NSString stringWithFormat:
        @"set -euo pipefail && "
         "repo_root='%@' && export_root='%@' && source_path='%@' && "
         "rm -rf \"$export_root\" && mkdir -p \"$export_root\" && "
         "cd \"$repo_root\" && "
         "git ls-files -z src/Arlen modules/*/Sources | while IFS= read -r -d '' path; do "
         "  mkdir -p \"$export_root/$(dirname \"$path\")\"; "
         "  cp \"$path\" \"$export_root/$path\"; "
         "done && "
         "%@ && "
         "include_flags=\"-I$export_root/src/Arlen\" && "
         "for dir in \"$export_root\"/src/Arlen/* \"$export_root\"/modules/*/Sources; do "
         "  if [ -d \"$dir\" ]; then include_flags=\"$include_flags -I$dir\"; fi; "
         "done && "
         "clang $(gnustep-config --objc-flags) -fobjc-arc -fsyntax-only $include_flags \"$source_path\"",
        repoRoot, exportRoot, sourcePath, [self gnustepSourceCommandForRepoRoot:repoRoot]]
                                       exitCode:&code];
    XCTAssertEqual(0, code, @"%@", compileOutput);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testReleaseBuildActivateAndRollbackScripts {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"arlen-release-app"];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-release-work"];
  XCTAssertNotNil(appRoot);
  XCTAssertNotNil(workRoot);
  if (appRoot == nil || workRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n"
                                  "  host = \"127.0.0.1\";\n"
                                  "  port = 3000;\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/production.plist"]
                          content:@"{\n  logFormat = \"json\";\n}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "int main(int argc, const char *argv[]) { (void)argc; (void)argv; return 0; }\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"public/health.txt"]
                          content:@"ok\n"]);

    NSString *releasesDir = [workRoot stringByAppendingPathComponent:@"releases"];

    int code = 0;
    NSString *build1 = [self runShellCapture:[NSString stringWithFormat:
                                                  @"%s/tools/deploy/build_release.sh --app-root %s "
                                                   "--framework-root %s --releases-dir %s --release-id rel1 "
                                                   "--allow-missing-certification",
                                                  [repoRoot UTF8String], [appRoot UTF8String],
                                                  [repoRoot UTF8String], [releasesDir UTF8String]]
                                    exitCode:&code];
    XCTAssertEqual(0, code, @"%@", build1);

    NSString *build2 = [self runShellCapture:[NSString stringWithFormat:
                                                  @"%s/tools/deploy/build_release.sh --app-root %s "
                                                   "--framework-root %s --releases-dir %s --release-id rel2 "
                                                   "--allow-missing-certification",
                                                  [repoRoot UTF8String], [appRoot UTF8String],
                                                  [repoRoot UTF8String], [releasesDir UTF8String]]
                                    exitCode:&code];
    XCTAssertEqual(0, code, @"%@", build2);

    NSString *activate2 = [self runShellCapture:[NSString stringWithFormat:
                                                     @"%s/tools/deploy/activate_release.sh "
                                                      "--releases-dir %s --release-id rel2",
                                                     [repoRoot UTF8String], [releasesDir UTF8String]]
                                       exitCode:&code];
    XCTAssertEqual(0, code, @"%@", activate2);

    NSString *rollback = [self runShellCapture:[NSString stringWithFormat:
                                                    @"%s/tools/deploy/rollback_release.sh "
                                                     "--releases-dir %s",
                                                    [repoRoot UTF8String], [releasesDir UTF8String]]
                                      exitCode:&code];
    XCTAssertEqual(0, code, @"%@", rollback);

    NSString *currentTarget = [self runShellCapture:[NSString stringWithFormat:@"readlink -f %s/current",
                                                                               [releasesDir UTF8String]]
                                           exitCode:&code];
    XCTAssertEqual(0, code, @"%@", currentTarget);
    NSString *trimmed =
        [currentTarget stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertTrue([trimmed hasSuffix:@"/rel1"]);

    NSString *metadataFile =
        [releasesDir stringByAppendingPathComponent:@"rel1/metadata/release.env"];
    BOOL metadataExists = [[NSFileManager defaultManager] fileExistsAtPath:metadataFile];
    XCTAssertTrue(metadataExists);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testReleaseSmokeScriptValidatesDeployRunbook {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"arlen-smoke-app"];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-smoke-work"];
  XCTAssertNotNil(appRoot);
  XCTAssertNotNil(workRoot);
  if (appRoot == nil || workRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n"
                                  "  host = \"127.0.0.1\";\n"
                                  "  port = 3000;\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/production.plist"]
                          content:@"{\n  logFormat = \"json\";\n}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "int main(int argc, const char *argv[]) { (void)argc; (void)argv; return 0; }\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"public/health.txt"]
                          content:@"ok\n"]);

    int code = 0;
    int port = [self randomPort];
    NSString *smokeOutput = [self runShellCapture:[NSString stringWithFormat:
                                                       @"%s/tools/deploy/smoke_release.sh "
                                                        "--app-root %s "
                                                        "--framework-root %s "
                                                        "--work-dir %s "
                                                        "--port %d "
                                                        "--release-a smoke-1 "
                                                        "--release-b smoke-2",
                                                       [repoRoot UTF8String], [appRoot UTF8String],
                                                       [repoRoot UTF8String], [workRoot UTF8String], port]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", smokeOutput);
    XCTAssertTrue([smokeOutput containsString:@"release smoke passed"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testArlenGeneratePluginPresetsCreateServiceTemplates {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-plugin-presets"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *buildOutput = [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSString *newOutput = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "new PresetApp --full",
                                                  workRoot, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", newOutput);

    NSString *appRoot = [workRoot stringByAppendingPathComponent:@"PresetApp"];
    NSString *generateRedis = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "generate plugin RedisCache --preset redis-cache",
                                                  appRoot, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", generateRedis);

    NSString *generateQueue = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "generate plugin QueueJobs --preset queue-jobs",
                                                  appRoot, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", generateQueue);

    NSString *generateSMTP = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "generate plugin SmtpMail --preset smtp-mail",
                                                  appRoot, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", generateSMTP);

    NSError *readError = nil;
    NSString *redisPlugin =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"src/Plugins/RedisCachePlugin.m"]
                                  encoding:NSUTF8StringEncoding
                                     error:&readError];
    XCTAssertNil(readError);
    XCTAssertTrue([redisPlugin containsString:@"ARLEN_REDIS_URL"]);
    XCTAssertTrue([redisPlugin containsString:@"setCacheAdapter"]);
    XCTAssertTrue([redisPlugin containsString:@"ALNRedisCacheAdapter"]);

    readError = nil;
    NSString *queuePlugin =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"src/Plugins/QueueJobsPlugin.m"]
                                  encoding:NSUTF8StringEncoding
                                     error:&readError];
    XCTAssertNil(readError);
    XCTAssertTrue([queuePlugin containsString:@"ALNJobWorker"]);
    XCTAssertTrue([queuePlugin containsString:@"setJobsAdapter"]);
    XCTAssertTrue([queuePlugin containsString:@"runDueJobsAt"]);

    readError = nil;
    NSString *smtpPlugin =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"src/Plugins/SmtpMailPlugin.m"]
                                  encoding:NSUTF8StringEncoding
                                     error:&readError];
    XCTAssertNil(readError);
    XCTAssertTrue([smtpPlugin containsString:@"ARLEN_SMTP_HOST"]);
    XCTAssertTrue([smtpPlugin containsString:@"setMailAdapter"]);

    readError = nil;
    NSString *configContents =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                                  encoding:NSUTF8StringEncoding
                                     error:&readError];
    XCTAssertNil(readError);
    XCTAssertTrue([configContents containsString:@"RedisCachePlugin"]);
    XCTAssertTrue([configContents containsString:@"QueueJobsPlugin"]);
    XCTAssertTrue([configContents containsString:@"SmtpMailPlugin"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testArlenGenerateEndpointWiresCompilableImportsForFullAndLiteScaffolds {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-generate-endpoint-imports"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *buildOutput = [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSArray<NSDictionary *> *cases = @[
      @{
        @"name" : @"DocsFull",
        @"mode" : @"--full",
        @"bootstrap" : @"src/main.m",
      },
      @{
        @"name" : @"DocsLite",
        @"mode" : @"--lite",
        @"bootstrap" : @"app_lite.m",
      },
    ];

    for (NSDictionary *caseInfo in cases) {
      NSString *appName = caseInfo[@"name"];
      NSString *mode = caseInfo[@"mode"];
      NSString *bootstrapPath = caseInfo[@"bootstrap"];

      NSString *newOutput =
          [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen new %@ %@ --json",
                                                        workRoot, repoRoot, repoRoot, appName, mode]
                       exitCode:&code];
      XCTAssertEqual(0, code, @"%@", newOutput);

      NSString *appRoot = [workRoot stringByAppendingPathComponent:appName];
      NSString *generateOutput =
          [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                        "generate endpoint Hello --route /hello --template --json",
                                                        appRoot, repoRoot, repoRoot]
                       exitCode:&code];
      XCTAssertEqual(0, code, @"%@", generateOutput);

      NSError *readError = nil;
      NSString *bootstrapSource =
          [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:bootstrapPath]
                                    encoding:NSUTF8StringEncoding
                                       error:&readError];
      XCTAssertNotNil(bootstrapSource);
      XCTAssertNil(readError);
      XCTAssertTrue([bootstrapSource containsString:@"#import \"Controllers/HelloController.h\""]);
      XCTAssertTrue([bootstrapSource containsString:@"controllerClass:[HelloController class]"]);

      NSString *prepareOutput =
          [self runShellCapture:[NSString stringWithFormat:
                                              @"%@ && "
                                               "cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen boomhauer --prepare-only",
                                              [self gnustepSourceCommandForRepoRoot:repoRoot], appRoot, repoRoot, repoRoot]
                       exitCode:&code];
      XCTAssertEqual(0, code, @"%@", prepareOutput);
    }
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testArlenGenerateFrontendStartersAreDeterministicAndDeployPackaged {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-frontend-starters"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *buildOutput = [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSString *newA = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "new FrontendA --full",
                                                  workRoot, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", newA);

    NSString *newB = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "new FrontendB --full",
                                                  workRoot, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", newB);

    NSString *appA = [workRoot stringByAppendingPathComponent:@"FrontendA"];
    NSString *appB = [workRoot stringByAppendingPathComponent:@"FrontendB"];

    NSString *generateAVanilla = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "generate frontend Dashboard --preset vanilla-spa",
                                                  appA, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", generateAVanilla);

    NSString *generateAProgressive = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "generate frontend Portal --preset progressive-mpa",
                                                  appA, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", generateAProgressive);

    NSString *generateBVanilla = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "generate frontend Dashboard --preset vanilla-spa",
                                                  appB, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", generateBVanilla);

    NSString *generateBProgressive = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "generate frontend Portal --preset progressive-mpa",
                                                  appB, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", generateBProgressive);

    NSString *invalidPreset = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "generate frontend Broken --preset unsupported",
                                                  appA, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(2, code, @"%@", invalidPreset);
    XCTAssertTrue([invalidPreset containsString:@"unsupported --preset"]);

    NSString *hashA = [self runShellCapture:[NSString stringWithFormat:
                                                 @"cd %@ && find public/frontend -type f -print0 | "
                                                  "sort -z | xargs -0 sha256sum",
                                                 appA]
                                   exitCode:&code];
    XCTAssertEqual(0, code, @"%@", hashA);
    NSString *hashB = [self runShellCapture:[NSString stringWithFormat:
                                                 @"cd %@ && find public/frontend -type f -print0 | "
                                                  "sort -z | xargs -0 sha256sum",
                                                 appB]
                                   exitCode:&code];
    XCTAssertEqual(0, code, @"%@", hashB);
    XCTAssertEqualObjects(hashA, hashB);

    BOOL vanillaManifestExists =
        [[NSFileManager defaultManager]
            fileExistsAtPath:[appA stringByAppendingPathComponent:
                                       @"public/frontend/dashboard/starter_manifest.json"]];
    BOOL progressiveManifestExists =
        [[NSFileManager defaultManager]
            fileExistsAtPath:[appA stringByAppendingPathComponent:
                                       @"public/frontend/portal/starter_manifest.json"]];
    XCTAssertTrue(vanillaManifestExists);
    XCTAssertTrue(progressiveManifestExists);

    NSString *releasesDir = [workRoot stringByAppendingPathComponent:@"releases"];
    NSString *releaseBuild = [self
        runShellCapture:[NSString stringWithFormat:
                                      @"%s/tools/deploy/build_release.sh --app-root %s "
                                       "--framework-root %s --releases-dir %s --release-id frontend-1 "
                                       "--allow-missing-certification",
                                      [repoRoot UTF8String], [appA UTF8String], [repoRoot UTF8String],
                                      [releasesDir UTF8String]]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", releaseBuild);

    NSString *releaseVanilla =
        [releasesDir stringByAppendingPathComponent:@"frontend-1/app/public/frontend/dashboard/index.html"];
    NSString *releaseProgressive =
        [releasesDir stringByAppendingPathComponent:@"frontend-1/app/public/frontend/portal/index.html"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:releaseVanilla]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:releaseProgressive]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testArlenGenerateSearchScaffoldRegistersProviderAndBuilds {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-search-scaffold"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *buildOutput = [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSString *newApp = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "new SearchPlayground --full",
                                                  workRoot, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", newApp);

    NSString *appRoot = [workRoot stringByAppendingPathComponent:@"SearchPlayground"];
    NSString *installJobs = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "module add jobs --json",
                                                  appRoot, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", installJobs);
    NSDictionary *jobsJSON = [self parseJSONDictionaryFromOutput:installJobs context:@"module add jobs --json"];
    XCTAssertEqualObjects(@"ok", jobsJSON[@"status"]);

    NSString *installSearch = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "module add search --json",
                                                  appRoot, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", installSearch);
    NSDictionary *searchJSON = [self parseJSONDictionaryFromOutput:installSearch context:@"module add search --json"];
    XCTAssertEqualObjects(@"ok", searchJSON[@"status"]);

    NSString *generateOutput = [self
        runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "generate search Catalog --json",
                                                  appRoot, repoRoot, repoRoot]
               exitCode:&code];
    XCTAssertEqual(0, code, @"%@", generateOutput);
    NSDictionary *generateJSON = [self parseJSONDictionaryFromOutput:generateOutput
                                                             context:@"generate search --json"];
    XCTAssertEqualObjects(@"ok", generateJSON[@"status"]);
    XCTAssertEqualObjects(@"search", generateJSON[@"generator"]);
    XCTAssertTrue([generateJSON[@"generated_files"] containsObject:@"src/Search/CatalogSearchProvider.h"]);
    XCTAssertTrue([generateJSON[@"generated_files"] containsObject:@"src/Search/CatalogSearchProvider.m"]);
    XCTAssertTrue([generateJSON[@"generated_files"] containsObject:@"docs/search/catalog_search.md"]);
    XCTAssertTrue([generateJSON[@"modified_files"] containsObject:@"config/app.plist"]);

    NSString *providerImpl =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"src/Search/CatalogSearchProvider.m"]
                                  encoding:NSUTF8StringEncoding
                                     error:nil];
    XCTAssertTrue([providerImpl containsString:@"searchModulePublicResultForDocument"]);
    XCTAssertTrue([providerImpl containsString:@"queryModes"]);

    NSString *guide =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"docs/search/catalog_search.md"]
                                  encoding:NSUTF8StringEncoding
                                     error:nil];
    XCTAssertTrue([guide containsString:@"ALNPostgresSearchEngine"]);
    XCTAssertTrue([guide containsString:@"ALNMeilisearchSearchEngine"]);
    XCTAssertTrue([guide containsString:@"ALNOpenSearchSearchEngine"]);

    NSString *appConfig =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                                  encoding:NSUTF8StringEncoding
                                     error:nil];
    XCTAssertTrue([appConfig containsString:@"CatalogSearchProvider"]);

    NSString *doctorOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                  "module doctor --json",
                                                  appRoot, repoRoot, repoRoot]
                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", doctorOutput);

    NSString *prepareOutput =
        [self runShellCapture:[NSString stringWithFormat:
                                            @"%@ && cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                             "boomhauer --prepare-only",
                                            [self gnustepSourceCommandForRepoRoot:repoRoot], appRoot, repoRoot,
                                            repoRoot]
                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", prepareOutput);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testAgentJSONWorkflowContractsCoverScaffoldBuildCheckAndDeploy {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-agent-dx"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *buildOutput = [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSString *newOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                      "new AgentDX --full --json",
                                                      workRoot, repoRoot, repoRoot]
                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", newOutput);
    NSDictionary *newPayload = [self parseJSONDictionaryFromOutput:newOutput context:@"arlen new --json"];
    XCTAssertEqualObjects(@"phase7g-agent-dx-contracts-v1", newPayload[@"version"]);
    XCTAssertEqualObjects(@"new", newPayload[@"command"]);
    XCTAssertEqualObjects(@"scaffold", newPayload[@"workflow"]);
    XCTAssertEqualObjects(@"ok", newPayload[@"status"]);
    NSArray *createdFiles = [newPayload[@"created_files"] isKindOfClass:[NSArray class]]
                                ? newPayload[@"created_files"]
                                : @[];
    XCTAssertTrue([createdFiles containsObject:@"config/app.plist"]);
    XCTAssertTrue([createdFiles containsObject:@"templates/layouts/main.html.eoc"]);
    XCTAssertTrue([createdFiles containsObject:@"templates/partials/_nav.html.eoc"]);
    XCTAssertTrue([createdFiles containsObject:@"templates/partials/_feature.html.eoc"]);

    NSString *appRoot = [workRoot stringByAppendingPathComponent:@"AgentDX"];
    NSError *readError = nil;
    NSString *scaffoldIndex =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"templates/index.html.eoc"]
                                  encoding:NSUTF8StringEncoding
                                     error:&readError];
    XCTAssertNotNil(scaffoldIndex);
    XCTAssertNil(readError);
    XCTAssertTrue([scaffoldIndex containsString:@"<%@ layout \"layouts/main\" %>"]);
    XCTAssertTrue([scaffoldIndex containsString:@"<%@ render \"partials/_feature\" collection:$items as:\"item\" %>"]);

    NSString *scaffoldLayout =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"templates/layouts/main.html.eoc"]
                                  encoding:NSUTF8StringEncoding
                                     error:&readError];
    XCTAssertNotNil(scaffoldLayout);
    XCTAssertNil(readError);
    XCTAssertTrue([scaffoldLayout containsString:@"<%@ include \"partials/_nav\" %>"]);
    XCTAssertTrue([scaffoldLayout containsString:@"<%@ yield %>"]);

    NSString *scaffoldNav =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"templates/partials/_nav.html.eoc"]
                                  encoding:NSUTF8StringEncoding
                                     error:&readError];
    XCTAssertNotNil(scaffoldNav);
    XCTAssertNil(readError);
    XCTAssertTrue([scaffoldNav containsString:@"<a href=\"/static/health.txt\">Health</a>"]);

    NSString *generateOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                      "generate endpoint AgentStatus --route /agent/status "
                                                      "--method GET --action status --api --json",
                                                      appRoot, repoRoot, repoRoot]
                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", generateOutput);
    NSDictionary *generatePayload =
        [self parseJSONDictionaryFromOutput:generateOutput context:@"arlen generate --json"];
    XCTAssertEqualObjects(@"generate", generatePayload[@"command"]);
    XCTAssertEqualObjects(@"ok", generatePayload[@"status"]);
    NSArray *generatedFiles = [generatePayload[@"generated_files"] isKindOfClass:[NSArray class]]
                                  ? generatePayload[@"generated_files"]
                                  : @[];
    XCTAssertTrue([generatedFiles containsObject:@"src/Controllers/AgentStatusController.h"]);
    XCTAssertTrue([generatedFiles containsObject:@"src/Controllers/AgentStatusController.m"]);
    NSString *generatedController =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"src/Controllers/AgentStatusController.m"]
                                  encoding:NSUTF8StringEncoding
                                     error:&readError];
    XCTAssertNotNil(generatedController);
    XCTAssertNil(readError);
    XCTAssertTrue([generatedController containsString:@"#import \"ALNRequest.h\""]);
    NSArray *modifiedFiles = [generatePayload[@"modified_files"] isKindOfClass:[NSArray class]]
                                 ? generatePayload[@"modified_files"]
                                 : @[];
    XCTAssertTrue([modifiedFiles containsObject:@"src/main.m"]);

    NSString *htmlGenerateOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                      "generate endpoint AgentPage --route /agent/page "
                                                      "--template pages/agent_page --json",
                                                      appRoot, repoRoot, repoRoot]
                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", htmlGenerateOutput);
    NSDictionary *htmlGeneratePayload =
        [self parseJSONDictionaryFromOutput:htmlGenerateOutput context:@"arlen generate html endpoint --json"];
    XCTAssertEqualObjects(@"generate", htmlGeneratePayload[@"command"]);
    XCTAssertEqualObjects(@"ok", htmlGeneratePayload[@"status"]);
    NSArray *htmlGeneratedFiles = [htmlGeneratePayload[@"generated_files"] isKindOfClass:[NSArray class]]
                                      ? htmlGeneratePayload[@"generated_files"]
                                      : @[];
    XCTAssertTrue([htmlGeneratedFiles containsObject:@"templates/pages/agent_page.html.eoc"]);

    NSString *generatedTemplate =
        [NSString stringWithContentsOfFile:[appRoot stringByAppendingPathComponent:@"templates/pages/agent_page.html.eoc"]
                                  encoding:NSUTF8StringEncoding
                                     error:&readError];
    XCTAssertNotNil(generatedTemplate);
    XCTAssertNil(readError);
    XCTAssertTrue([generatedTemplate containsString:@"<%@ layout \"layouts/main\" %>"]);

    NSString *prepareOutput =
        [self runShellCapture:[NSString stringWithFormat:
                                            @"%@ && "
                                             "cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen boomhauer --prepare-only",
                                            [self gnustepSourceCommandForRepoRoot:repoRoot], appRoot, repoRoot, repoRoot]
                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", prepareOutput);

    NSString *invalidGenerateOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                      "generate endpoint MissingRoute --json",
                                                      appRoot, repoRoot, repoRoot]
                     exitCode:&code];
    XCTAssertEqual(2, code, @"%@", invalidGenerateOutput);
    NSDictionary *invalidPayload =
        [self parseJSONDictionaryFromOutput:invalidGenerateOutput
                                    context:@"arlen generate missing route --json"];
    XCTAssertEqualObjects(@"error", invalidPayload[@"status"]);
    NSDictionary *errorObject = [invalidPayload[@"error"] isKindOfClass:[NSDictionary class]]
                                    ? invalidPayload[@"error"]
                                    : @{};
    XCTAssertEqualObjects(@"missing_route", errorObject[@"code"]);
    NSDictionary *fixit =
        [errorObject[@"fixit"] isKindOfClass:[NSDictionary class]] ? errorObject[@"fixit"] : @{};
    NSString *fixitExample = [fixit[@"example"] isKindOfClass:[NSString class]] ? fixit[@"example"] : @"";
    XCTAssertTrue([fixitExample containsString:@"--route"]);

    NSString *buildPlanOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                      "build --dry-run --json",
                                                      appRoot, repoRoot, repoRoot]
                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildPlanOutput);
    NSDictionary *buildPlan = [self parseJSONDictionaryFromOutput:buildPlanOutput context:@"arlen build --json"];
    XCTAssertEqualObjects(@"build", buildPlan[@"command"]);
    XCTAssertEqualObjects(@"planned", buildPlan[@"status"]);
    XCTAssertEqualObjects(@"all", buildPlan[@"make_target"]);

    NSString *checkPlanOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                      "check --dry-run --json",
                                                      appRoot, repoRoot, repoRoot]
                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", checkPlanOutput);
    NSDictionary *checkPlan = [self parseJSONDictionaryFromOutput:checkPlanOutput context:@"arlen check --json"];
    XCTAssertEqualObjects(@"check", checkPlan[@"command"]);
    XCTAssertEqualObjects(@"planned", checkPlan[@"status"]);
    XCTAssertEqualObjects(@"check", checkPlan[@"make_target"]);

    NSString *deployPlanOutput =
        [self runShellCapture:[NSString stringWithFormat:
                                            @"%s/tools/deploy/build_release.sh --app-root %s "
                                             "--framework-root %s --releases-dir %s --release-id agent-dx-1 "
                                             "--allow-missing-certification --dry-run --json",
                                            [repoRoot UTF8String], [appRoot UTF8String],
                                            [repoRoot UTF8String],
                                            [[workRoot stringByAppendingPathComponent:@"releases"] UTF8String]]
                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", deployPlanOutput);
    NSDictionary *deployPlan =
        [self parseJSONDictionaryFromOutput:deployPlanOutput context:@"build_release.sh --json"];
    XCTAssertEqualObjects(@"phase7g-agent-dx-contracts-v1", deployPlan[@"version"]);
    XCTAssertEqualObjects(@"deploy.build_release", deployPlan[@"workflow"]);
    XCTAssertEqualObjects(@"planned", deployPlan[@"status"]);
    XCTAssertEqualObjects(@"agent-dx-1", deployPlan[@"release_id"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testSmokeRenderOutputsComposedLayoutPartialsAndEscapedItems {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];

  int code = 0;
  NSString *buildOutput =
      [self runShellCapture:[NSString stringWithFormat:@"%@ && cd %@ && make smoke-render",
                                                      [self gnustepSourceCommandForRepoRoot:repoRoot],
                                                      repoRoot]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", buildOutput);

  NSString *renderOutput =
      [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ./build/eoc-smoke-render", repoRoot]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", renderOutput);
  XCTAssertTrue([renderOutput containsString:@"<title>EOC Smoke Test</title>"], @"%@", renderOutput);
  XCTAssertTrue([renderOutput containsString:@"<nav>"], @"%@", renderOutput);
  XCTAssertTrue([renderOutput containsString:@"<a href=\"/about\">About</a>"], @"%@", renderOutput);
  XCTAssertTrue([renderOutput containsString:@"<li>alpha</li>"], @"%@", renderOutput);
  XCTAssertTrue([renderOutput containsString:@"gamma &lt;unsafe&gt;"], @"%@", renderOutput);
  XCTAssertTrue([renderOutput containsString:@"<p class=\"template-note\">template:multiline-ok</p>"],
                @"%@", renderOutput);
}

- (void)testEOCCEmitsDeterministicLintDiagnosticsForUnguardedInclude {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-eocc-lint"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    NSString *templateRoot = [workRoot stringByAppendingPathComponent:@"templates"];
    NSString *outputRoot = [workRoot stringByAppendingPathComponent:@"generated"];
    NSString *partialsRoot = [templateRoot stringByAppendingPathComponent:@"partials"];

    XCTAssertTrue([self writeFile:[partialsRoot stringByAppendingPathComponent:@"_nav.html.eoc"]
                          content:@"<nav>ok</nav>\n"]);
    XCTAssertTrue([self writeFile:[templateRoot stringByAppendingPathComponent:@"lint_unguarded_include.html.eoc"]
                          content:@"<main>\n"
                                  "<% ALNEOCInclude(out, ctx, @\"partials/_nav.html.eoc\", error); %>\n"
                                  "</main>\n"]);
    XCTAssertTrue([self writeFile:[templateRoot stringByAppendingPathComponent:@"lint_guarded_include.html.eoc"]
                          content:@"<main>\n"
                                  "<% if (!ALNEOCInclude(out, ctx, @\"partials/_nav.html.eoc\", error)) { return nil; } %>\n"
                                  "</main>\n"]);

    int code = 0;
    NSString *output = [self runEOCCCaptureAtRepoRoot:repoRoot
                                             workRoot:workRoot
                                            arguments:[NSString stringWithFormat:
                                                                  @"--template-root %@ --output-dir %@ %@ %@",
                                                                  templateRoot,
                                                                  outputRoot,
                                                                  [templateRoot
                                                                      stringByAppendingPathComponent:@"lint_unguarded_include.html.eoc"],
                                                                  [templateRoot
                                                                      stringByAppendingPathComponent:@"lint_guarded_include.html.eoc"]]
                                             exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"code=unguarded_include"], @"%@", output);
    XCTAssertTrue([output containsString:@"path=lint_unguarded_include.html.eoc line=2 column=4"],
                  @"%@", output);
    XCTAssertFalse([output containsString:@"path=lint_guarded_include.html.eoc"], @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testEOCCRemovesStaleOutputWhenLogicalDestinationChanges {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-eocc-stale-output"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    NSString *templateRoot = [workRoot stringByAppendingPathComponent:@"templates"];
    NSString *outputRoot = [workRoot stringByAppendingPathComponent:@"generated"];
    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSString *templatePath = [templateRoot stringByAppendingPathComponent:@"auth/login.html.eoc"];
    NSString *legacyOutputPath = [outputRoot stringByAppendingPathComponent:@"legacy/auth/login.html.eoc.m"];
    NSString *currentOutputPath = [outputRoot stringByAppendingPathComponent:@"current/auth/login.html.eoc.m"];

    XCTAssertTrue([self writeFile:templatePath content:@"<p>login</p>\n"]);

    int code = 0;
    NSString *firstOutput = [self runEOCCCaptureAtRepoRoot:repoRoot
                                                  workRoot:workRoot
                                                 arguments:[NSString stringWithFormat:
                                                                       @"--template-root %@ --output-dir %@ --manifest %@ --logical-prefix legacy %@",
                                                                       templateRoot,
                                                                       outputRoot,
                                                                       manifestPath,
                                                                       templatePath]
                                                  exitCode:&code];
    XCTAssertEqual(0, code, @"%@", firstOutput);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:legacyOutputPath]);

    NSString *secondOutput = [self runEOCCCaptureAtRepoRoot:repoRoot
                                                   workRoot:workRoot
                                                  arguments:[NSString stringWithFormat:
                                                                        @"--template-root %@ --output-dir %@ --manifest %@ --logical-prefix current %@",
                                                                        templateRoot,
                                                                        outputRoot,
                                                                        manifestPath,
                                                                        templatePath]
                                                   exitCode:&code];
    XCTAssertEqual(0, code, @"%@", secondOutput);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:legacyOutputPath],
                   @"%@", secondOutput);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:currentOutputPath],
                  @"%@", secondOutput);
    XCTAssertTrue([secondOutput containsString:@"removed 1"], @"%@", secondOutput);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testEOCCRejectsUnknownStaticCompositionDependency {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-eocc-missing-dependency"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    NSString *templateRoot = [workRoot stringByAppendingPathComponent:@"templates"];
    NSString *outputRoot = [workRoot stringByAppendingPathComponent:@"generated"];

    XCTAssertTrue([self writeFile:[templateRoot stringByAppendingPathComponent:@"missing_dep.html.eoc"]
                          content:@"<%@ include \"partials/_missing\" %>\n"]);

    int code = 0;
    NSString *output = [self runEOCCCaptureAtRepoRoot:repoRoot
                                             workRoot:workRoot
                                            arguments:[NSString stringWithFormat:
                                                                  @"--template-root %@ --output-dir %@ %@",
                                                                  templateRoot,
                                                                  outputRoot,
                                                                  [templateRoot stringByAppendingPathComponent:@"missing_dep.html.eoc"]]
                                             exitCode:&code];
    XCTAssertEqual(1, code, @"%@", output);
    XCTAssertTrue([output containsString:@"Unknown static EOC include: partials/_missing.html.eoc"],
                  @"%@", output);
    XCTAssertTrue([output containsString:@"path=missing_dep.html.eoc line=1 column=4"],
                  @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testEOCCRejectsStaticCompositionCycles {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-eocc-cycle"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    NSString *templateRoot = [workRoot stringByAppendingPathComponent:@"templates"];
    NSString *outputRoot = [workRoot stringByAppendingPathComponent:@"generated"];

    XCTAssertTrue([self writeFile:[templateRoot stringByAppendingPathComponent:@"a.html.eoc"]
                          content:@"<%@ include \"b\" %>\n"]);
    XCTAssertTrue([self writeFile:[templateRoot stringByAppendingPathComponent:@"b.html.eoc"]
                          content:@"<%@ include \"a\" %>\n"]);

    int code = 0;
    NSString *output = [self runEOCCCaptureAtRepoRoot:repoRoot
                                             workRoot:workRoot
                                            arguments:[NSString stringWithFormat:
                                                                  @"--template-root %@ --output-dir %@ %@ %@",
                                                                  templateRoot,
                                                                  outputRoot,
                                                                  [templateRoot stringByAppendingPathComponent:@"a.html.eoc"],
                                                                  [templateRoot stringByAppendingPathComponent:@"b.html.eoc"]]
                                             exitCode:&code];
    XCTAssertEqual(1, code, @"%@", output);
    XCTAssertTrue([output containsString:
                               @"Static EOC composition cycle detected: a.html.eoc -> b.html.eoc -> a.html.eoc"],
                  @"%@", output);
    XCTAssertTrue([output containsString:@"path=b.html.eoc line=1 column=4"], @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testEOCCEmitsCompositionSlotWarnings {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-eocc-slot-warnings"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    NSString *templateRoot = [workRoot stringByAppendingPathComponent:@"templates"];
    NSString *outputRoot = [workRoot stringByAppendingPathComponent:@"generated"];

    XCTAssertTrue([self writeFile:[templateRoot stringByAppendingPathComponent:@"layouts/application.html.eoc"]
                          content:@"<main><%@ yield %></main>\n"]);
    XCTAssertTrue([self writeFile:[templateRoot stringByAppendingPathComponent:@"pages/show.html.eoc"]
                          content:@"<%@ layout \"layouts/application\" %>\n"
                                  "<%@ slot \"sidebar\" %>nav<%@ endslot %>\n"
                                  "<p>body</p>\n"]);
    XCTAssertTrue([self writeFile:[templateRoot stringByAppendingPathComponent:@"pages/orphan.html.eoc"]
                          content:@"<%@ slot \"sidebar\" %>nav<%@ endslot %>\n"]);

    int code = 0;
    NSString *output = [self runEOCCCaptureAtRepoRoot:repoRoot
                                             workRoot:workRoot
                                            arguments:[NSString stringWithFormat:
                                                                  @"--template-root %@ --output-dir %@ %@ %@ %@",
                                                                  templateRoot,
                                                                  outputRoot,
                                                                  [templateRoot stringByAppendingPathComponent:@"layouts/application.html.eoc"],
                                                                  [templateRoot stringByAppendingPathComponent:@"pages/show.html.eoc"],
                                                                  [templateRoot stringByAppendingPathComponent:@"pages/orphan.html.eoc"]]
                                             exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"code=unused_slot_fill"], @"%@", output);
    XCTAssertTrue([output containsString:@"path=pages/show.html.eoc line=2 column=4"], @"%@", output);
    XCTAssertTrue([output containsString:@"code=slot_without_layout"], @"%@", output);
    XCTAssertTrue([output containsString:@"path=pages/orphan.html.eoc line=1 column=4"], @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testPhase5EConfidenceArtifactGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase5e-confidence"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
        @"cd %@ && python3 ./tools/ci/generate_phase5e_confidence_artifacts.py "
         "--repo-root %@ --output-dir %@",
        repoRoot, repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"phase5e-confidence: generated artifacts"], @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSString *adapterPath =
        [outputRoot stringByAppendingPathComponent:@"adapter_capability_matrix_snapshot.json"];
    NSString *conformancePath =
        [outputRoot stringByAppendingPathComponent:@"sql_builder_conformance_summary.json"];
    NSString *markdownPath =
        [outputRoot stringByAppendingPathComponent:@"phase5e_release_confidence.md"];

    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"phase5e-confidence-v1", manifest[@"version"]);

    NSData *adapterData = [NSData dataWithContentsOfFile:adapterPath];
    XCTAssertNotNil(adapterData);
    NSDictionary *adapterSnapshot =
        [NSJSONSerialization JSONObjectWithData:adapterData options:0 error:&error];
    XCTAssertNotNil(adapterSnapshot);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"phase5e-confidence-v1", adapterSnapshot[@"version"]);
    XCTAssertTrue([adapterSnapshot[@"adapter_count"] integerValue] >= 2);

    NSData *conformanceData = [NSData dataWithContentsOfFile:conformancePath];
    XCTAssertNotNil(conformanceData);
    NSDictionary *conformanceSummary =
        [NSJSONSerialization JSONObjectWithData:conformanceData options:0 error:&error];
    XCTAssertNotNil(conformanceSummary);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"phase5e-confidence-v1", conformanceSummary[@"version"]);
    XCTAssertTrue([conformanceSummary[@"scenario_count"] integerValue] > 0);

    NSString *markdown =
        [NSString stringWithContentsOfFile:markdownPath encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNotNil(markdown);
    XCTAssertNil(error);
    XCTAssertTrue([markdown containsString:@"# Phase 5E Release Confidence Summary"]);
    XCTAssertTrue([markdown containsString:@"Adapter Capability Snapshot"]);
    XCTAssertTrue([markdown containsString:@"SQL Builder Conformance Summary"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase9HSanitizerSuppressionValidatorAcceptsFixture {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];

  int code = 0;
  NSString *output = [self runShellCapture:[NSString stringWithFormat:
                                                        @"cd %@ && python3 ./tools/ci/check_sanitizer_suppressions.py "
                                                         "--fixture tests/fixtures/sanitizers/phase9h_suppressions.json",
                                                        repoRoot]
                                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", output);
  XCTAssertTrue([output containsString:@"sanitizer-suppressions: ok"], @"%@", output);
}

- (void)testPhase9HSanitizerSuppressionValidatorRejectsExpiredSuppression {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-phase9h-suppressions"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    NSString *fixturePath = [workRoot stringByAppendingPathComponent:@"suppressions.json"];
    XCTAssertTrue([self writeFile:fixturePath
                          content:@"{\n"
                                  "  \"version\": \"phase9h-suppression-registry-v1\",\n"
                                  "  \"lastUpdated\": \"2026-02-25\",\n"
                                  "  \"suppressions\": [\n"
                                  "    {\n"
                                  "      \"id\": \"tsan-expired-001\",\n"
                                  "      \"status\": \"active\",\n"
                                  "      \"sanitizer\": \"thread\",\n"
                                  "      \"owner\": \"runtime-core\",\n"
                                  "      \"reason\": \"temporary suppression for triage\",\n"
                                  "      \"introducedOn\": \"2020-01-01\",\n"
                                  "      \"expiresOn\": \"2020-01-15\"\n"
                                  "    }\n"
                                  "  ]\n"
                                  "}\n"]);

    int code = 0;
    NSString *output = [self runShellCapture:[NSString stringWithFormat:
                                                          @"cd %@ && python3 ./tools/ci/check_sanitizer_suppressions.py "
                                                           "--fixture %@",
                                                          repoRoot, fixturePath]
                                     exitCode:&code];
    XCTAssertNotEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"validation failed"], @"%@", output);
    XCTAssertTrue([output containsString:@"suppression expired on 2020-01-15"], @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testPhase9HSanitizerConfidenceArtifactGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase9h-confidence"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
        @"cd %@ && python3 ./tools/ci/generate_phase9h_sanitizer_confidence_artifacts.py "
         "--repo-root %@ --output-dir %@ --blocking-status pass --tsan-status skipped",
        repoRoot, repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"phase9h-sanitizers: generated artifacts"], @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSString *laneStatusPath = [outputRoot stringByAppendingPathComponent:@"sanitizer_lane_status.json"];
    NSString *matrixPath =
        [outputRoot stringByAppendingPathComponent:@"sanitizer_matrix_summary.json"];
    NSString *suppressionPath =
        [outputRoot stringByAppendingPathComponent:@"sanitizer_suppression_summary.json"];
    NSString *markdownPath =
        [outputRoot stringByAppendingPathComponent:@"phase9h_sanitizer_confidence.md"];

    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"phase9h-sanitizer-confidence-v1", manifest[@"version"]);

    NSData *laneStatusData = [NSData dataWithContentsOfFile:laneStatusPath];
    XCTAssertNotNil(laneStatusData);
    NSDictionary *laneStatus =
        [NSJSONSerialization JSONObjectWithData:laneStatusData options:0 error:&error];
    XCTAssertNotNil(laneStatus);
    XCTAssertNil(error);
    NSDictionary *laneStatuses = laneStatus[@"lane_statuses"];
    XCTAssertEqualObjects(@"pass", laneStatuses[@"asan_ubsan_blocking"]);
    XCTAssertEqualObjects(@"skipped", laneStatuses[@"tsan_experimental"]);

    NSData *matrixData = [NSData dataWithContentsOfFile:matrixPath];
    XCTAssertNotNil(matrixData);
    NSDictionary *matrixSummary =
        [NSJSONSerialization JSONObjectWithData:matrixData options:0 error:&error];
    XCTAssertNotNil(matrixSummary);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"phase9h-sanitizer-confidence-v1", matrixSummary[@"version"]);
    XCTAssertTrue([matrixSummary[@"lanes"] count] >= 2);

    NSData *suppressionData = [NSData dataWithContentsOfFile:suppressionPath];
    XCTAssertNotNil(suppressionData);
    NSDictionary *suppressionSummary =
        [NSJSONSerialization JSONObjectWithData:suppressionData options:0 error:&error];
    XCTAssertNotNil(suppressionSummary);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"phase9h-sanitizer-confidence-v1", suppressionSummary[@"version"]);
    XCTAssertEqual(4, [suppressionSummary[@"active_count"] integerValue]);

    NSString *markdown =
        [NSString stringWithContentsOfFile:markdownPath encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNotNil(markdown);
    XCTAssertNil(error);
    XCTAssertTrue([markdown containsString:@"# Phase 9H Sanitizer Confidence Summary"]);
    XCTAssertTrue([markdown containsString:@"Lane Status"]);
    XCTAssertTrue([markdown containsString:@"Suppression Summary"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase9IFaultInjectionHarnessProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase9i-confidence"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
        @"cd %@ && ARLEN_PHASE9I_OUTPUT_DIR=%@ ARLEN_PHASE9I_ITERS=1 "
         "ARLEN_PHASE9I_MODES=concurrent ARLEN_PHASE9I_SEED=4242 "
         "bash ./tools/ci/run_phase9i_fault_injection.sh",
        repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"phase9i-fault-injection: generated artifacts"], @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSString *resultsPath = [outputRoot stringByAppendingPathComponent:@"fault_injection_results.json"];
    NSString *markdownPath =
        [outputRoot stringByAppendingPathComponent:@"phase9i_fault_injection_summary.md"];

    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"phase9i-fault-injection-v1", manifest[@"version"]);

    NSData *resultsData = [NSData dataWithContentsOfFile:resultsPath];
    XCTAssertNotNil(resultsData);
    NSDictionary *resultsPayload =
        [NSJSONSerialization JSONObjectWithData:resultsData options:0 error:&error];
    XCTAssertNotNil(resultsPayload);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"phase9i-fault-injection-v1", resultsPayload[@"version"]);
    NSDictionary *summary = resultsPayload[@"summary"];
    XCTAssertNotNil(summary);
    XCTAssertEqual(0, [summary[@"failed"] integerValue]);
    XCTAssertTrue([summary[@"total"] integerValue] > 0);
    NSDictionary *seamCounts = summary[@"seam_counts"];
    XCTAssertTrue([seamCounts[@"http_parser_dispatcher"] integerValue] > 0);
    XCTAssertTrue([seamCounts[@"websocket_handshake_lifecycle"] integerValue] > 0);
    XCTAssertTrue([seamCounts[@"runtime_stop_start_boundary"] integerValue] > 0);

    NSString *markdown =
        [NSString stringWithContentsOfFile:markdownPath encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNotNil(markdown);
    XCTAssertNil(error);
    XCTAssertTrue([markdown containsString:@"# Phase 9I Fault Injection Summary"]);
    XCTAssertTrue([markdown containsString:@"Scenario Matrix"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase9IFaultInjectionSeedReplayIsDeterministic {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputA = [self createTempDirectoryWithPrefix:@"arlen-phase9i-seed-a"];
  NSString *outputB = [self createTempDirectoryWithPrefix:@"arlen-phase9i-seed-b"];
  XCTAssertNotNil(outputA);
  XCTAssertNotNil(outputB);
  if (outputA == nil || outputB == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
        @"cd %@ && make boomhauer && "
         "python3 ./tools/ci/runtime_fault_injection.py --repo-root %@ --binary ./build/boomhauer "
         "--output-dir %@ --seed 777 --iterations 2 --modes concurrent --scenarios socket_churn_burst && "
         "python3 ./tools/ci/runtime_fault_injection.py --repo-root %@ --binary ./build/boomhauer "
         "--output-dir %@ --seed 777 --iterations 2 --modes concurrent --scenarios socket_churn_burst",
        repoRoot, repoRoot, outputA, repoRoot, outputB];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSError *error = nil;
    NSData *resultsDataA =
        [NSData dataWithContentsOfFile:[outputA stringByAppendingPathComponent:@"fault_injection_results.json"]];
    NSData *resultsDataB =
        [NSData dataWithContentsOfFile:[outputB stringByAppendingPathComponent:@"fault_injection_results.json"]];
    XCTAssertNotNil(resultsDataA);
    XCTAssertNotNil(resultsDataB);
    NSDictionary *payloadA =
        [NSJSONSerialization JSONObjectWithData:resultsDataA options:0 error:&error];
    XCTAssertNotNil(payloadA);
    XCTAssertNil(error);
    NSDictionary *payloadB =
        [NSJSONSerialization JSONObjectWithData:resultsDataB options:0 error:&error];
    XCTAssertNotNil(payloadB);
    XCTAssertNil(error);

    NSArray *rowsA = [payloadA[@"results"] isKindOfClass:[NSArray class]] ? payloadA[@"results"] : @[];
    NSArray *rowsB = [payloadB[@"results"] isKindOfClass:[NSArray class]] ? payloadB[@"results"] : @[];
    XCTAssertEqual([rowsA count], [rowsB count]);

    NSMutableArray *seedsA = [NSMutableArray array];
    NSMutableArray *seedsB = [NSMutableArray array];
    for (id value in rowsA) {
      NSDictionary *row = [value isKindOfClass:[NSDictionary class]] ? value : @{};
      [seedsA addObject:row[@"seed"] ?: [NSNull null]];
    }
    for (id value in rowsB) {
      NSDictionary *row = [value isKindOfClass:[NSDictionary class]] ? value : @{};
      [seedsB addObject:row[@"seed"] ?: [NSNull null]];
    }

    XCTAssertEqualObjects(seedsA, seedsB);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputA error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:outputB error:nil];
  }
}

- (void)testPhase9JReleaseCertificationGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *fixtureRoot = [self createTempDirectoryWithPrefix:@"arlen-phase9j-fixtures"];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase9j-output"];
  XCTAssertNotNil(fixtureRoot);
  XCTAssertNotNil(outputRoot);
  if (fixtureRoot == nil || outputRoot == nil) {
    return;
  }

  @try {
    NSString *phase5eDir = [fixtureRoot stringByAppendingPathComponent:@"phase5e"];
    NSString *phase9hDir = [fixtureRoot stringByAppendingPathComponent:@"phase9h"];
    NSString *phase9iDir = [fixtureRoot stringByAppendingPathComponent:@"phase9i"];

    XCTAssertTrue([self writeFile:[phase5eDir stringByAppendingPathComponent:@"manifest.json"]
                          content:@"{\n"
                                  "  \"version\": \"phase5e-confidence-v1\"\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[phase5eDir stringByAppendingPathComponent:@"adapter_capability_matrix_snapshot.json"]
                          content:@"{\n"
                                  "  \"version\": \"phase5e-confidence-v1\",\n"
                                  "  \"adapter_count\": 2\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[phase5eDir stringByAppendingPathComponent:@"sql_builder_conformance_summary.json"]
                          content:@"{\n"
                                  "  \"version\": \"phase5e-confidence-v1\",\n"
                                  "  \"scenario_count\": 6\n"
                                  "}\n"]);

    XCTAssertTrue([self writeFile:[phase9hDir stringByAppendingPathComponent:@"sanitizer_lane_status.json"]
                          content:@"{\n"
                                  "  \"version\": \"phase9h-sanitizer-confidence-v1\",\n"
                                  "  \"lane_statuses\": {\n"
                                  "    \"asan_ubsan_blocking\": \"pass\",\n"
                                  "    \"tsan_experimental\": \"skipped\"\n"
                                  "  }\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[phase9hDir stringByAppendingPathComponent:@"sanitizer_suppression_summary.json"]
                          content:@"{\n"
                                  "  \"version\": \"phase9h-sanitizer-confidence-v1\",\n"
                                  "  \"active_count\": 0,\n"
                                  "  \"resolved_count\": 1,\n"
                                  "  \"expiring_soon\": 0\n"
                                  "}\n"]);

    XCTAssertTrue([self writeFile:[phase9iDir stringByAppendingPathComponent:@"fault_injection_results.json"]
                          content:@"{\n"
                                  "  \"version\": \"phase9i-fault-injection-v1\",\n"
                                  "  \"summary\": {\n"
                                  "    \"failed\": 0,\n"
                                  "    \"total\": 8,\n"
                                  "    \"seam_counts\": {\n"
                                  "      \"http_parser_dispatcher\": 3,\n"
                                  "      \"websocket_handshake_lifecycle\": 3,\n"
                                  "      \"runtime_stop_start_boundary\": 2\n"
                                  "    }\n"
                                  "  }\n"
                                  "}\n"]);

    int code = 0;
    NSString *command = [NSString stringWithFormat:
        @"cd %@ && python3 ./tools/ci/generate_phase9j_release_certification_pack.py "
         "--repo-root %@ --output-dir %@ --release-id rc-test-001 "
         "--phase5e-dir %@ --phase9h-dir %@ --phase9i-dir %@",
        repoRoot, repoRoot, outputRoot, phase5eDir, phase9hDir, phase9iDir];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"phase9j-certification: generated artifacts"], @"%@", output);

    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:[outputRoot stringByAppendingPathComponent:@"manifest.json"]];
    XCTAssertNotNil(manifestData);
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"phase9j-release-certification-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"certified", manifest[@"status"]);

    NSData *summaryData =
        [NSData dataWithContentsOfFile:[outputRoot stringByAppendingPathComponent:@"certification_summary.json"]];
    XCTAssertNotNil(summaryData);
    NSDictionary *summary = [NSJSONSerialization JSONObjectWithData:summaryData options:0 error:&error];
    XCTAssertNotNil(summary);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"certified", summary[@"status"]);
    NSDictionary *gateSummary = summary[@"gate_summary"];
    XCTAssertEqual(0, [gateSummary[@"blocking_failed"] integerValue]);

    NSString *markdown =
        [NSString stringWithContentsOfFile:[outputRoot stringByAppendingPathComponent:@"phase9j_release_certification.md"]
                                  encoding:NSUTF8StringEncoding
                                     error:&error];
    XCTAssertNotNil(markdown);
    XCTAssertNil(error);
    XCTAssertTrue([markdown containsString:@"# Phase 9J Release Certification"]);
    XCTAssertTrue([markdown containsString:@"Known-Risk Register"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:fixtureRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase9JReleaseCertificationGeneratorRejectsStaleRiskRegister {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *fixtureRoot = [self createTempDirectoryWithPrefix:@"arlen-phase9j-stale-fixtures"];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase9j-stale-output"];
  XCTAssertNotNil(fixtureRoot);
  XCTAssertNotNil(outputRoot);
  if (fixtureRoot == nil || outputRoot == nil) {
    return;
  }

  @try {
    NSString *phase5eDir = [fixtureRoot stringByAppendingPathComponent:@"phase5e"];
    NSString *phase9hDir = [fixtureRoot stringByAppendingPathComponent:@"phase9h"];
    NSString *phase9iDir = [fixtureRoot stringByAppendingPathComponent:@"phase9i"];
    NSString *riskPath = [fixtureRoot stringByAppendingPathComponent:@"known_risks.json"];

    XCTAssertTrue([self writeFile:[phase5eDir stringByAppendingPathComponent:@"manifest.json"]
                          content:@"{\n"
                                  "  \"version\": \"phase5e-confidence-v1\"\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[phase9hDir stringByAppendingPathComponent:@"sanitizer_lane_status.json"]
                          content:@"{\n"
                                  "  \"version\": \"phase9h-sanitizer-confidence-v1\",\n"
                                  "  \"lane_statuses\": {\n"
                                  "    \"asan_ubsan_blocking\": \"pass\",\n"
                                  "    \"tsan_experimental\": \"pass\"\n"
                                  "  }\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[phase9iDir stringByAppendingPathComponent:@"fault_injection_results.json"]
                          content:@"{\n"
                                  "  \"version\": \"phase9i-fault-injection-v1\",\n"
                                  "  \"summary\": {\n"
                                  "    \"failed\": 0,\n"
                                  "    \"total\": 5,\n"
                                  "    \"seam_counts\": {\n"
                                  "      \"http_parser_dispatcher\": 2,\n"
                                  "      \"websocket_handshake_lifecycle\": 2,\n"
                                  "      \"runtime_stop_start_boundary\": 1\n"
                                  "    }\n"
                                  "  }\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:riskPath
                          content:@"{\n"
                                  "  \"version\": \"phase9j-known-risk-register-v1\",\n"
                                  "  \"lastUpdated\": \"2020-01-01\",\n"
                                  "  \"risks\": [\n"
                                  "    {\n"
                                  "      \"id\": \"old-risk\",\n"
                                  "      \"title\": \"stale register entry\",\n"
                                  "      \"status\": \"active\",\n"
                                  "      \"owner\": \"runtime-core\",\n"
                                  "      \"targetDate\": \"2026-03-01\"\n"
                                  "    }\n"
                                  "  ]\n"
                                  "}\n"]);

    int code = 0;
    NSString *command = [NSString stringWithFormat:
        @"cd %@ && python3 ./tools/ci/generate_phase9j_release_certification_pack.py "
         "--repo-root %@ --output-dir %@ --release-id rc-test-stale "
         "--phase5e-dir %@ --phase9h-dir %@ --phase9i-dir %@ --risk-register %@",
        repoRoot, repoRoot, outputRoot, phase5eDir, phase9hDir, phase9iDir, riskPath];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertNotEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"known-risk register is stale"], @"%@", output);

    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:[outputRoot stringByAppendingPathComponent:@"manifest.json"]];
    XCTAssertNotNil(manifestData);
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"incomplete", manifest[@"status"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:fixtureRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testBuildReleaseRequiresPhase9JCertificationByDefault {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"arlen-phase9j-release-app"];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-phase9j-release-work"];
  XCTAssertNotNil(appRoot);
  XCTAssertNotNil(workRoot);
  if (appRoot == nil || workRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n"
                                  "  host = \"127.0.0.1\";\n"
                                  "  port = 3000;\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/production.plist"]
                          content:@"{\n  logFormat = \"json\";\n}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "int main(int argc, const char *argv[]) { (void)argc; (void)argv; return 0; }\n"]);

    NSString *releasesDir = [workRoot stringByAppendingPathComponent:@"releases"];
    NSString *missingManifest = [workRoot stringByAppendingPathComponent:@"missing/manifest.json"];
    NSString *certManifest = [workRoot stringByAppendingPathComponent:@"cert/manifest.json"];
    NSString *jsonPerfManifest = [workRoot stringByAppendingPathComponent:@"json/manifest.json"];
    XCTAssertTrue([self writeFile:certManifest
                          content:@"{\n"
                                  "  \"version\": \"phase9j-release-certification-v1\",\n"
                                  "  \"status\": \"certified\",\n"
                                  "  \"release_id\": \"rc-unit\",\n"
                                  "  \"artifacts\": []\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:jsonPerfManifest
                          content:@"{\n"
                                  "  \"version\": \"phase10e-json-performance-v1\",\n"
                                  "  \"status\": \"pass\",\n"
                                  "  \"artifacts\": []\n"
                                  "}\n"]);

    int code = 0;
    NSString *missingOutput = [self runShellCapture:[NSString stringWithFormat:
                                                         @"%s/tools/deploy/build_release.sh "
                                                          "--app-root %s --framework-root %s --releases-dir %s "
                                                          "--release-id missing-cert --certification-manifest %s "
                                                          "--json-performance-manifest %s "
                                                          "--dry-run",
                                                         [repoRoot UTF8String], [appRoot UTF8String],
                                                         [repoRoot UTF8String], [releasesDir UTF8String],
                                                         [missingManifest UTF8String],
                                                         [jsonPerfManifest UTF8String]]
                                           exitCode:&code];
    XCTAssertNotEqual(0, code, @"%@", missingOutput);
    XCTAssertTrue([missingOutput containsString:@"missing Phase 9J certification manifest"], @"%@", missingOutput);

    NSString *passingOutput = [self runShellCapture:[NSString stringWithFormat:
                                                         @"%s/tools/deploy/build_release.sh "
                                                          "--app-root %s --framework-root %s --releases-dir %s "
                                                          "--release-id with-cert --certification-manifest %s "
                                                          "--json-performance-manifest %s "
                                                          "--dry-run --json",
                                                         [repoRoot UTF8String], [appRoot UTF8String],
                                                         [repoRoot UTF8String], [releasesDir UTF8String],
                                                         [certManifest UTF8String],
                                                         [jsonPerfManifest UTF8String]]
                                           exitCode:&code];
    XCTAssertEqual(0, code, @"%@", passingOutput);
    NSDictionary *payload = [self parseJSONDictionaryFromOutput:passingOutput context:@"build_release dry-run json"];
    XCTAssertEqualObjects(@"planned", payload[@"status"]);
    XCTAssertEqualObjects(@"certified", payload[@"certification_status"]);
    XCTAssertEqualObjects(@"pass", payload[@"json_performance_status"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testPhase10EJSONPerformanceGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10e-confidence"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    NSString *thresholdsPath = [outputRoot stringByAppendingPathComponent:@"thresholds.json"];
    XCTAssertTrue([self writeFile:thresholdsPath
                          content:@"{\n"
                                  "  \"version\": \"phase10e-json-performance-thresholds-v1\",\n"
                                  "  \"decode_ops_ratio_min\": 0.0,\n"
                                  "  \"encode_ops_ratio_min\": 0.0,\n"
                                  "  \"decode_p95_ratio_max\": 999.0,\n"
                                  "  \"encode_p95_ratio_max\": 999.0,\n"
                                  "  \"decode_expected_improvement_ratio_min\": 0.0,\n"
                                  "  \"decode_expected_improvement_fixture_count\": 0\n"
                                  "}\n"]);

    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10E_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10E_THRESHOLDS=%@ "
                                       "ARLEN_PHASE10E_ITERATIONS=120 ARLEN_PHASE10E_WARMUP=20 "
                                       "bash ./tools/ci/run_phase10e_json_performance.sh",
                                      repoRoot, outputRoot, thresholdsPath];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase10e-json-performance-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"json_backend_delta_summary.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase10e_json_performance.md"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10GDispatchPerformanceGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10g-confidence"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    NSString *thresholdsPath = [outputRoot stringByAppendingPathComponent:@"thresholds.json"];
    XCTAssertTrue([self writeFile:thresholdsPath
                          content:@"{\n"
                                  "  \"version\": \"phase10g-dispatch-thresholds-v1\",\n"
                                  "  \"ops_ratio_min\": 0.0,\n"
                                  "  \"p95_ratio_max\": 999.0\n"
                                  "}\n"]);

    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10G_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10G_THRESHOLDS=%@ "
                                       "ARLEN_PHASE10G_ITERATIONS=8000 ARLEN_PHASE10G_WARMUP=800 "
                                       "bash ./tools/ci/run_phase10g_dispatch_performance.sh",
                                      repoRoot, outputRoot, thresholdsPath];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase10g-dispatch-performance-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"dispatch_delta_summary.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase10g_dispatch_performance.md"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10HHTTPParsePerformanceGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10h-confidence"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    NSString *thresholdsPath = [outputRoot stringByAppendingPathComponent:@"thresholds.json"];
    XCTAssertTrue([self writeFile:thresholdsPath
                          content:@"{\n"
                                  "  \"version\": \"phase10h-http-parse-thresholds-v1\",\n"
                                  "  \"parse_ops_ratio_min\": 0.0,\n"
                                  "  \"parse_p95_ratio_max\": 999.0,\n"
                                  "  \"parse_expected_improvement_ratio_min\": 0.0,\n"
                                  "  \"parse_expected_improvement_fixture_count\": 0\n"
                                  "}\n"]);

    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10H_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10H_THRESHOLDS=%@ "
                                       "ARLEN_PHASE10H_ITERATIONS=300 ARLEN_PHASE10H_WARMUP=40 "
                                       "bash ./tools/ci/run_phase10h_http_parse_performance.sh",
                                      repoRoot, outputRoot, thresholdsPath];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase10h-http-parse-performance-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"http_parser_delta_summary.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase10h_http_parse_performance.md"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10LRouteMatchInvestigationGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10l-confidence"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    NSString *thresholdsPath = [outputRoot stringByAppendingPathComponent:@"thresholds.json"];
    XCTAssertTrue([self writeFile:thresholdsPath
                          content:@"{\n"
                                  "  \"version\": \"phase10l-route-match-thresholds-v1\",\n"
                                  "  \"min_ops_per_sec_default\": 0.0,\n"
                                  "  \"max_p95_us_default\": 9999999.0,\n"
                                  "  \"min_ops_per_sec_by_scenario\": {\n"
                                  "    \"static_hit\": 0.0,\n"
                                  "    \"param_hit\": 0.0,\n"
                                  "    \"wildcard_hit\": 0.0,\n"
                                  "    \"miss\": 0.0\n"
                                  "  },\n"
                                  "  \"max_p95_us_by_scenario\": {\n"
                                  "    \"static_hit\": 9999999.0,\n"
                                  "    \"param_hit\": 9999999.0,\n"
                                  "    \"wildcard_hit\": 9999999.0,\n"
                                  "    \"miss\": 9999999.0\n"
                                  "  }\n"
                                  "}\n"]);

    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10L_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10L_THRESHOLDS=%@ "
                                       "ARLEN_PHASE10L_ROUTE_COUNT=1800 "
                                       "ARLEN_PHASE10L_ITERATIONS=300 ARLEN_PHASE10L_WARMUP=40 "
                                       "ARLEN_PHASE10L_ROUNDS=2 ARLEN_PHASE10L_CAPTURE_FLAMEGRAPH=0 "
                                       "bash ./tools/ci/run_phase10l_route_match_investigation.sh",
                                      repoRoot, outputRoot, thresholdsPath];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase10l-route-match-investigation-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"route_match_threshold_eval.json"]);
    XCTAssertTrue([artifacts containsObject:@"flamegraph_capture_status.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase10l_route_match_investigation.md"]);

    NSString *flamegraphStatusPath = [outputRoot stringByAppendingPathComponent:@"flamegraph_capture_status.json"];
    NSData *flamegraphStatusData = [NSData dataWithContentsOfFile:flamegraphStatusPath];
    XCTAssertNotNil(flamegraphStatusData);
    if (flamegraphStatusData == nil) {
      return;
    }
    NSDictionary *flamegraphStatus =
        [NSJSONSerialization JSONObjectWithData:flamegraphStatusData options:0 error:&error];
    XCTAssertNotNil(flamegraphStatus);
    XCTAssertNil(error);
    if (![flamegraphStatus isKindOfClass:[NSDictionary class]]) {
      return;
    }
    XCTAssertEqualObjects(@(NO), flamegraphStatus[@"captured"]);
    XCTAssertEqualObjects(@"disabled", flamegraphStatus[@"reason"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10MBackendParityMatrixGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10m-backend-parity"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10M_PARITY_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10M_MATRIX_COMBOS=1:1 "
                                       "bash ./tools/ci/run_phase10m_backend_parity_matrix.sh",
                                      repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase10m-backend-parity-matrix-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"backend_parity_summary.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase10m_backend_parity_matrix.md"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10MProtocolAdversarialProbeProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10m-protocol-adversarial"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10M_PROTOCOL_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10M_PROTOCOL_BACKENDS=llhttp,legacy "
                                       "bash ./tools/ci/run_phase10m_protocol_adversarial.sh",
                                      repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase10m-protocol-adversarial-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"protocol_adversarial_results.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase10m_protocol_adversarial.md"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase11ProtocolAdversarialProbeProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase11-protocol-adversarial"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE11_PROTOCOL_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE11_PROTOCOL_BACKENDS=llhttp "
                                       "bash ./tools/ci/run_phase11_protocol_adversarial.sh",
                                      repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase11-protocol-adversarial-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"protocol_adversarial_results.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase11_protocol_adversarial.md"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase11ProtocolFuzzAndLiveProbeProduceExpectedPacks {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *fuzzOutputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase11-protocol-fuzz"];
  NSString *liveOutputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase11-live-adversarial"];
  XCTAssertNotNil(fuzzOutputRoot);
  XCTAssertNotNil(liveOutputRoot);
  if (fuzzOutputRoot == nil || liveOutputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *fuzzCommand = [NSString stringWithFormat:
                                          @"cd %@ && ARLEN_PHASE11_FUZZ_OUTPUT_DIR=%@ "
                                           "ARLEN_PHASE11_FUZZ_BACKENDS=llhttp "
                                           "bash ./tools/ci/run_phase11_protocol_fuzz.sh",
                                          repoRoot, fuzzOutputRoot];
    NSString *fuzzOutput = [self runShellCapture:fuzzCommand exitCode:&code];
    XCTAssertEqual(0, code, @"%@", fuzzOutput);

    NSString *fuzzManifestPath = [fuzzOutputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSError *error = nil;
    NSData *fuzzManifestData = [NSData dataWithContentsOfFile:fuzzManifestPath];
    XCTAssertNotNil(fuzzManifestData);
    if (fuzzManifestData == nil) {
      return;
    }
    NSDictionary *fuzzManifest =
        [NSJSONSerialization JSONObjectWithData:fuzzManifestData options:0 error:&error];
    XCTAssertNotNil(fuzzManifest);
    XCTAssertNil(error);
    if (![fuzzManifest isKindOfClass:[NSDictionary class]]) {
      return;
    }
    XCTAssertEqualObjects(@"phase11-protocol-fuzz-v1", fuzzManifest[@"version"]);
    XCTAssertEqualObjects(@"pass", fuzzManifest[@"status"]);
    NSArray *fuzzArtifacts =
        [fuzzManifest[@"artifacts"] isKindOfClass:[NSArray class]] ? fuzzManifest[@"artifacts"] : @[];
    XCTAssertTrue([fuzzArtifacts containsObject:@"protocol_fuzz_results.json"]);
    XCTAssertTrue([fuzzArtifacts containsObject:@"phase11_protocol_fuzz.md"]);

    NSString *liveCommand = [NSString stringWithFormat:
                                          @"cd %@ && ARLEN_PHASE11_LIVE_OUTPUT_DIR=%@ "
                                           "ARLEN_PHASE11_LIVE_MODES=serialized "
                                           "ARLEN_PHASE11_LIVE_ROUNDS=1 "
                                           "ARLEN_WEBSOCKET_READ_TIMEOUT_MS=200 "
                                           "bash ./tools/ci/run_phase11_live_adversarial.sh",
                                          repoRoot, liveOutputRoot];
    NSString *liveOutput = [self runShellCapture:liveCommand exitCode:&code];
    XCTAssertEqual(0, code, @"%@", liveOutput);

    NSString *liveManifestPath = [liveOutputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSData *liveManifestData = [NSData dataWithContentsOfFile:liveManifestPath];
    XCTAssertNotNil(liveManifestData);
    if (liveManifestData == nil) {
      return;
    }
    NSDictionary *liveManifest =
        [NSJSONSerialization JSONObjectWithData:liveManifestData options:0 error:&error];
    XCTAssertNotNil(liveManifest);
    XCTAssertNil(error);
    if (![liveManifest isKindOfClass:[NSDictionary class]]) {
      return;
    }
    XCTAssertEqualObjects(@"phase11-live-adversarial-v1", liveManifest[@"version"]);
    XCTAssertEqualObjects(@"pass", liveManifest[@"status"]);
    NSArray *liveArtifacts =
        [liveManifest[@"artifacts"] isKindOfClass:[NSArray class]] ? liveManifest[@"artifacts"] : @[];
    XCTAssertTrue([liveArtifacts containsObject:@"live_adversarial_results.json"]);
    XCTAssertTrue([liveArtifacts containsObject:@"phase11_live_adversarial.md"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:fuzzOutputRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:liveOutputRoot error:nil];
  }
}

- (void)testPhase11SanitizerMatrixProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase11-sanitizers"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE11_SANITIZER_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE11_PROTOCOL_BACKENDS=llhttp "
                                       "ARLEN_PHASE11_FUZZ_BACKENDS=llhttp "
                                       "ARLEN_PHASE11_LIVE_MODES=serialized "
                                       "ARLEN_PHASE11_LIVE_ROUNDS=1 "
                                       "ARLEN_WEBSOCKET_READ_TIMEOUT_MS=200 "
                                       "bash ./tools/ci/run_phase11_sanitizer_matrix.sh",
                                      repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSError *error = nil;
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase11-sanitizer-matrix-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"sanitizer_lane_status.json"]);
    XCTAssertTrue([artifacts containsObject:@"sanitizer_matrix_summary.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase11_sanitizer_matrix.md"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10MSyscallFaultInjectionHarnessProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10m-syscall-faults"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10M_SYSCALL_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10M_SYSCALL_MODES=serialized "
                                       "ARLEN_PHASE10M_SYSCALL_SCENARIOS=syscall_writev_eagain_keepalive,syscall_sendfile_fallback_keepalive "
                                       "bash ./tools/ci/run_phase10m_syscall_fault_injection.sh",
                                      repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"phase9i-fault-injection: generated artifacts"], @"%@", output);

    NSString *resultsPath = [outputRoot stringByAppendingPathComponent:@"fault_injection_results.json"];
    NSData *resultsData = [NSData dataWithContentsOfFile:resultsPath];
    XCTAssertNotNil(resultsData);
    if (resultsData == nil) {
      return;
    }
    NSError *error = nil;
    NSDictionary *resultsPayload = [NSJSONSerialization JSONObjectWithData:resultsData options:0 error:&error];
    XCTAssertNotNil(resultsPayload);
    XCTAssertNil(error);
    if (![resultsPayload isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase9i-fault-injection-v1", resultsPayload[@"version"]);
    XCTAssertEqualObjects(@"phase10m-syscall-fault-scenarios-v1", resultsPayload[@"scenario_fixture_version"]);
    NSDictionary *summary = [resultsPayload[@"summary"] isKindOfClass:[NSDictionary class]]
                                ? resultsPayload[@"summary"]
                                : @{};
    XCTAssertEqualObjects(@0, summary[@"failed"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10MSyscallFaultInjectionConcurrentKeepAliveScenarioPasses {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10m-syscall-concurrent"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10M_SYSCALL_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10M_SYSCALL_MODES=concurrent "
                                       "ARLEN_PHASE10M_SYSCALL_SCENARIOS=syscall_writev_eagain_keepalive "
                                       "bash ./tools/ci/run_phase10m_syscall_fault_injection.sh",
                                      repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *resultsPath = [outputRoot stringByAppendingPathComponent:@"fault_injection_results.json"];
    NSData *resultsData = [NSData dataWithContentsOfFile:resultsPath];
    XCTAssertNotNil(resultsData);
    if (resultsData == nil) {
      return;
    }

    NSError *error = nil;
    NSDictionary *resultsPayload = [NSJSONSerialization JSONObjectWithData:resultsData options:0 error:&error];
    XCTAssertNotNil(resultsPayload);
    XCTAssertNil(error);
    if (![resultsPayload isKindOfClass:[NSDictionary class]]) {
      return;
    }

    NSDictionary *summary = [resultsPayload[@"summary"] isKindOfClass:[NSDictionary class]]
                                ? resultsPayload[@"summary"]
                                : @{};
    XCTAssertEqualObjects(@0, summary[@"failed"]);

    NSArray *results = [resultsPayload[@"results"] isKindOfClass:[NSArray class]] ? resultsPayload[@"results"] : @[];
    XCTAssertEqual((NSUInteger)1, [results count]);
    NSDictionary *row = [results[0] isKindOfClass:[NSDictionary class]] ? results[0] : @{};
    XCTAssertEqualObjects(@"pass", row[@"status"]);
    XCTAssertEqualObjects(@"concurrent", row[@"mode"]);
    XCTAssertEqualObjects(@"syscall_writev_eagain_keepalive", row[@"scenario_id"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10MAllocationFaultInjectionHarnessProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10m-allocation-faults"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10M_ALLOC_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10M_ALLOC_MODES=serialized "
                                       "ARLEN_PHASE10M_ALLOC_ITERS=1 "
                                       "ARLEN_PHASE10M_ALLOC_SCENARIOS=alloc_read_state_realloc_once,alloc_parser_headername_malloc_once,alloc_response_serialize_once "
                                       "bash ./tools/ci/run_phase10m_allocation_fault_injection.sh",
                                      repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *resultsPath = [outputRoot stringByAppendingPathComponent:@"fault_injection_results.json"];
    NSData *resultsData = [NSData dataWithContentsOfFile:resultsPath];
    XCTAssertNotNil(resultsData);
    if (resultsData == nil) {
      return;
    }

    NSError *error = nil;
    NSDictionary *resultsPayload = [NSJSONSerialization JSONObjectWithData:resultsData options:0 error:&error];
    XCTAssertNotNil(resultsPayload);
    XCTAssertNil(error);
    if (![resultsPayload isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase9i-fault-injection-v1", resultsPayload[@"version"]);
    XCTAssertEqualObjects(@"phase10m-allocation-fault-scenarios-v1",
                          resultsPayload[@"scenario_fixture_version"]);
    NSDictionary *summary = [resultsPayload[@"summary"] isKindOfClass:[NSDictionary class]]
                                ? resultsPayload[@"summary"]
                                : @{};
    XCTAssertEqualObjects(@0, summary[@"failed"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10MLongRunSoakGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10m-soak"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    NSString *thresholdsPath = [outputRoot stringByAppendingPathComponent:@"soak-thresholds.json"];
    XCTAssertTrue([self writeFile:thresholdsPath
                          content:@"{\n"
                                  "  \"version\": \"phase10m-soak-thresholds-v1\",\n"
                                  "  \"modes\": [\"concurrent\", \"serialized\"],\n"
                                  "  \"requestsPerMode\": 80,\n"
                                  "  \"sampleEveryRequests\": 20,\n"
                                  "  \"restartCycles\": 1,\n"
                                  "  \"maxRequestFailures\": 2,\n"
                                  "  \"maxRssDeltaKB\": 131072,\n"
                                  "  \"maxFDDelta\": 96,\n"
                                  "  \"maxSocketFDDelta\": 96\n"
                                  "}\n"]);

    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10M_SOAK_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10M_SOAK_THRESHOLDS=%@ "
                                       "bash ./tools/ci/run_phase10m_soak.sh",
                                      repoRoot, outputRoot, thresholdsPath];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }

    NSError *error = nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase10m-soak-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"soak_results.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase10m_soak_summary.md"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10MChaosRestartGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10m-chaos-restart"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    NSString *thresholdsPath = [outputRoot stringByAppendingPathComponent:@"chaos-thresholds.json"];
    XCTAssertTrue([self writeFile:thresholdsPath
                          content:@"{\n"
                                  "  \"version\": \"phase10m-chaos-restart-thresholds-v1\",\n"
                                  "  \"workers\": 2,\n"
                                  "  \"churnCycles\": 1,\n"
                                  "  \"loadThreads\": 2,\n"
                                  "  \"loadDurationSeconds\": 2,\n"
                                  "  \"startupTimeoutSeconds\": 60,\n"
                                  "  \"cycleReadinessTimeoutSeconds\": 20,\n"
                                  "  \"maxNon200Responses\": 8,\n"
                                  "  \"maxLoadErrors\": 8,\n"
                                  "  \"allowedManagerExitCodes\": [0, -15],\n"
                                  "  \"requiredLifecycleTokens\": [\n"
                                  "    \"event=manager_started\",\n"
                                  "    \"event=worker_started\",\n"
                                  "    \"event=manager_reload_requested\",\n"
                                  "    \"signal=HUP\",\n"
                                  "    \"event=manager_shutdown_requested\",\n"
                                  "    \"signal=TERM\",\n"
                                  "    \"event=http_worker_stopped\",\n"
                                  "    \"event=manager_stopped\"\n"
                                  "  ]\n"
                                  "}\n"]);

    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10M_CHAOS_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10M_CHAOS_THRESHOLDS=%@ "
                                       "bash ./tools/ci/run_phase10m_chaos_restart.sh",
                                      repoRoot, outputRoot, thresholdsPath];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }

    NSError *error = nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase10m-chaos-restart-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"chaos_restart_results.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase10m_chaos_restart.md"]);
    XCTAssertTrue([artifacts containsObject:@"phase10m_chaos_lifecycle.log"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10MStaticAnalysisGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10m-static-analysis"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10M_STATIC_ANALYSIS_OUTPUT_DIR=%@ "
                                       "bash ./tools/ci/run_phase10m_static_analysis.sh",
                                      repoRoot, outputRoot];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }

    NSError *error = nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase10m-static-analysis-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"static_analysis_results.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase10m_static_analysis.md"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testPhase10MBlobThroughputGeneratorProducesExpectedPack {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *outputRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10m-blob-throughput"];
  XCTAssertNotNil(outputRoot);
  if (outputRoot == nil) {
    return;
  }

  @try {
    NSString *thresholdsPath = [outputRoot stringByAppendingPathComponent:@"blob-thresholds.json"];
    XCTAssertTrue([self writeFile:thresholdsPath
                          content:@"{\n"
                                  "  \"version\": \"phase10m-blob-throughput-thresholds-v1\",\n"
                                  "  \"scenario_names\": {\n"
                                  "    \"legacy_e2e\": \"blob_legacy_string_e2e\",\n"
                                  "    \"binary_e2e\": \"blob_binary_e2e\",\n"
                                  "    \"binary_sendfile\": \"blob_binary_sendfile\"\n"
                                  "  },\n"
                                  "  \"binary_vs_legacy\": {\n"
                                  "    \"min_req_per_sec_ratio\": 0.0,\n"
                                  "    \"max_p95_ratio\": 9999999.0\n"
                                  "  },\n"
                                  "  \"sendfile_vs_binary\": {\n"
                                  "    \"min_req_per_sec_ratio\": 0.0,\n"
                                  "    \"max_p95_ratio\": 9999999.0\n"
                                  "  },\n"
                                  "  \"min_req_per_sec\": {\n"
                                  "    \"blob_binary_e2e\": 0.0,\n"
                                  "    \"blob_binary_sendfile\": 0.0\n"
                                  "  },\n"
                                  "  \"max_p95_ms\": {\n"
                                  "    \"blob_binary_e2e\": 9999999.0,\n"
                                  "    \"blob_binary_sendfile\": 9999999.0\n"
                                  "  }\n"
                                  "}\n"]);

    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10M_BLOB_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10M_BLOB_THRESHOLDS=%@ "
                                       "ARLEN_PHASE10M_BLOB_CONCURRENCY=4 "
                                       "ARLEN_PHASE10M_BLOB_REPEATS=1 "
                                       "ARLEN_PHASE10M_BLOB_REQUESTS=20 "
                                       "bash ./tools/ci/run_phase10m_blob_throughput.sh",
                                      repoRoot, outputRoot, thresholdsPath];
    NSString *output = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    NSString *manifestPath = [outputRoot stringByAppendingPathComponent:@"manifest.json"];
    NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
    XCTAssertNotNil(manifestData);
    if (manifestData == nil) {
      return;
    }

    NSError *error = nil;
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
    XCTAssertNotNil(manifest);
    XCTAssertNil(error);
    if (![manifest isKindOfClass:[NSDictionary class]]) {
      return;
    }

    XCTAssertEqualObjects(@"phase10m-blob-throughput-v1", manifest[@"version"]);
    XCTAssertEqualObjects(@"pass", manifest[@"status"]);
    NSArray *artifacts = [manifest[@"artifacts"] isKindOfClass:[NSArray class]] ? manifest[@"artifacts"] : @[];
    XCTAssertTrue([artifacts containsObject:@"phase10m_blob_throughput_eval.json"]);
    XCTAssertTrue([artifacts containsObject:@"phase10m_blob_throughput.md"]);
    XCTAssertTrue([artifacts containsObject:@"phase10m_blob_perf_report.json"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  }
}

- (void)testRuntimeJSONAbstractionCheckScriptPasses {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  int code = 0;
  NSString *output = [self runShellCapture:[NSString stringWithFormat:
                                                @"cd %@ && python3 ./tools/ci/check_runtime_json_abstraction.py --repo-root %@",
                                                repoRoot, repoRoot]
                                  exitCode:&code];
  XCTAssertEqual(0, code, @"%@", output);
  XCTAssertTrue([output containsString:@"runtime JSON abstraction check passed"], @"%@", output);
}

- (void)testArlenConfigJSONOutputIsDeterministicAcrossRuns {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-config-json-deterministic"];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  @try {
    NSString *appRoot = [workRoot stringByAppendingPathComponent:@"ConfigDeterministicApp"];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n"
                                  "  port = 3010;\n"
                                  "  host = \"127.0.0.1\";\n"
                                  "  logFormat = \"json\";\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{\n"
                                  "  requestDispatchMode = \"serialized\";\n"
                                  "}\n"]);

    int code = 0;
    NSString *buildOutput = [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen config --env development --json",
                                      appRoot, repoRoot, repoRoot];
    NSString *outputA = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", outputA);
    NSString *outputB = [self runShellCapture:command exitCode:&code];
    XCTAssertEqual(0, code, @"%@", outputB);

    NSString *trimmedA =
        [outputA stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *trimmedB =
        [outputB stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertEqualObjects(trimmedA, trimmedB);

    NSDictionary *payload = [self parseJSONDictionaryFromOutput:outputA context:@"arlen config --json"];
    XCTAssertEqualObjects(@"127.0.0.1", payload[@"host"]);
    XCTAssertEqual((NSInteger)3010, [payload[@"port"] integerValue]);
    XCTAssertEqualObjects(@"serialized", payload[@"requestDispatchMode"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testBuildReleaseRequiresPhase10EJSONPerformanceEvidenceByDefault {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10e-release-app"];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"arlen-phase10e-release-work"];
  XCTAssertNotNil(appRoot);
  XCTAssertNotNil(workRoot);
  if (appRoot == nil || workRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n"
                                  "  host = \"127.0.0.1\";\n"
                                  "  port = 3000;\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/production.plist"]
                          content:@"{\n  logFormat = \"json\";\n}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "int main(int argc, const char *argv[]) { (void)argc; (void)argv; return 0; }\n"]);

    NSString *releasesDir = [workRoot stringByAppendingPathComponent:@"releases"];
    NSString *certManifest = [workRoot stringByAppendingPathComponent:@"cert/manifest.json"];
    NSString *missingJSONPerfManifest = [workRoot stringByAppendingPathComponent:@"missing-json/manifest.json"];
    XCTAssertTrue([self writeFile:certManifest
                          content:@"{\n"
                                  "  \"version\": \"phase9j-release-certification-v1\",\n"
                                  "  \"status\": \"certified\",\n"
                                  "  \"release_id\": \"rc-unit\",\n"
                                  "  \"artifacts\": []\n"
                                  "}\n"]);

    int code = 0;
    NSString *output = [self runShellCapture:[NSString stringWithFormat:
                                                  @"%s/tools/deploy/build_release.sh "
                                                   "--app-root %s --framework-root %s --releases-dir %s "
                                                   "--release-id missing-json-perf --certification-manifest %s "
                                                   "--json-performance-manifest %s "
                                                   "--dry-run",
                                                  [repoRoot UTF8String], [appRoot UTF8String],
                                                  [repoRoot UTF8String], [releasesDir UTF8String],
                                                  [certManifest UTF8String],
                                                  [missingJSONPerfManifest UTF8String]]
                                    exitCode:&code];
    XCTAssertNotEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"missing Phase 10E JSON performance manifest"], @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

@end
