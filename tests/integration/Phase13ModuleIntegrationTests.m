#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "../ALNXCTestCompat.h"

#import "../shared/ALNTestSupport.h"

@interface Phase13ModuleIntegrationTests : XCTestCase
@property(nonatomic, copy) NSString *warningGNUstepConfigPath;
@end

@implementation Phase13ModuleIntegrationTests

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  return ALNTestTemporaryDirectory(prefix);
}

- (BOOL)writeFile:(NSString *)path content:(NSString *)content {
  NSError *error = nil;
  if (!ALNTestWriteUTF8File(path, content, &error)) {
    XCTFail(@"failed writing %@: %@", path, error.localizedDescription);
    return NO;
  }
  return YES;
}

// Kept with the test's results (saved only if the test fails).
- (NSString *)runShellCapture:(NSString *)command exitCode:(int *)exitCode {
  int status = 0;
  NSString *output = [self runShellCaptureUnattached:command exitCode:&status];
  if (exitCode != NULL) {
    *exitCode = status;
  }
  ALNTestAttachCommandOutput(self, command, output, status);
  return output;
}

- (NSString *)runShellCaptureUnattached:(NSString *)command exitCode:(int *)exitCode {
  return ALNTestRunShellCapture(command, exitCode);
}

// Runs a `--json` command and returns its stdout, the JSON payload. stderr is
// kept out of it: gnustep-base writes warnings there, such as unknown
// GNUstep.conf keys (issue #130). The attachment records both streams.
- (NSString *)runJSONCommand:(NSString *)command exitCode:(int *)exitCode {
  NSDictionary *result = ALNTestRunShellCaptureStreams(command);
  int status = [result[@"status"] intValue];
  if (exitCode != NULL) {
    *exitCode = status;
  }
  NSString *standardOutput = result[@"stdout"] ?: @"";
  NSString *standardError = result[@"stderr"] ?: @"";
  ALNTestAttachCommandOutput(self, command,
                             [NSString stringWithFormat:@"%@\n[stderr]\n%@", standardOutput, standardError], status);
  return standardOutput;
}

// A copy of the host's GNUstep.conf plus a key gnustep-base does not know, so
// every `arlen module` run here writes gnustep-base's "Configuration contains
// unknown keys" warning to stderr, as hosts with a newer gnustep-make than
// gnustep-base do (issue #130). nil if the host has no GNUstep.conf to copy.
- (NSString *)warningGNUstepConfig {
  if (self.warningGNUstepConfigPath != nil) {
    return self.warningGNUstepConfigPath;
  }
  NSString *hostConfig = ALNTestEnvironmentString(@"GNUSTEP_CONFIG_FILE") ?: @"/etc/GNUstep/GNUstep.conf";
  NSString *contents = [NSString stringWithContentsOfFile:hostConfig encoding:NSUTF8StringEncoding error:NULL];
  NSString *directory = contents != nil ? [self createTempDirectoryWithPrefix:@"phase13-gnustep-conf"] : nil;
  if (directory == nil) {
    return nil;
  }
  NSString *path = [directory stringByAppendingPathComponent:@"GNUstep.conf"];
  if (![self writeFile:path content:[contents stringByAppendingString:@"\nARLEN_TEST_UNKNOWN_CONFIG_KEY=1\n"]]) {
    return nil;
  }
  // gnustep-base ignores a config file that anyone but its owner can write.
  if (![[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions : @0644 } ofItemAtPath:path error:NULL]) {
    return nil;
  }
  self.warningGNUstepConfigPath = path;
  return path;
}

- (NSDictionary *)parseJSONDictionary:(NSString *)output {
  NSError *error = nil;
  NSDictionary *payload = ALNTestJSONDictionaryFromString(output, &error);
  XCTAssertNil(error, @"invalid JSON: %@\n%@", error.localizedDescription, output);
  XCTAssertTrue([payload isKindOfClass:[NSDictionary class]]);
  return payload ?: @{};
}

- (NSString *)buildToolsCommandForRepoRoot:(NSString *)repoRoot {
  return [NSString stringWithFormat:@"%@ && cd %@ && make arlen eocc",
                                    ALNTestGNUstepSourceCommandForRepoRoot(repoRoot),
                                    ALNTestShellQuote(repoRoot)];
}

- (void)testModuleCLIAndBuildWorkflow {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13-module-app"];
  NSString *modulesRoot = [self createTempDirectoryWithPrefix:@"phase13-module-src"];
  NSString *releaseRoot = [self createTempDirectoryWithPrefix:@"phase13-module-release"];
  XCTAssertNotNil(appRoot);
  XCTAssertNotNil(modulesRoot);
  XCTAssertNotNil(releaseRoot);
  if (appRoot == nil || modulesRoot == nil || releaseRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n"
                                  "  host = \"127.0.0.1\";\n"
                                  "  port = 3000;\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "#import \"ArlenServer.h\"\n"
                                  "#import \"ALNContext.h\"\n"
                                  "#import \"ALNController.h\"\n\n"
                                  "@interface Phase13LiteController : ALNController\n"
                                  "@end\n\n"
                                  "@implementation Phase13LiteController\n"
                                  "- (id)index:(ALNContext *)ctx { (void)ctx; [self renderText:@\"ok\\n\"]; return nil; }\n"
                                  "@end\n\n"
                                  "static void RegisterRoutes(ALNApplication *app) {\n"
                                  "  [app registerRouteMethod:@\"GET\" path:@\"/\" name:@\"home\" controllerClass:[Phase13LiteController class] action:@\"index\"];\n"
                                  "}\n\n"
                                  "int main(int argc, const char *argv[]) {\n"
                                  "  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"public/modules/alpha/site.css"]
                          content:@"app-override\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"templates/modules/alpha/dashboard/index.html.eoc"]
                          content:@"<p>app override</p>\n"]);

    NSString *alphaSource = [modulesRoot stringByAppendingPathComponent:@"alpha-v1"];
    NSString *betaSource = [modulesRoot stringByAppendingPathComponent:@"beta-v1"];
    NSString *alphaV2Source = [modulesRoot stringByAppendingPathComponent:@"alpha-v2"];

    NSString *alphaClassSource =
        @"#import <Foundation/Foundation.h>\n"
         "#import \"ALNApplication.h\"\n"
         "#import \"ALNModuleSystem.h\"\n\n"
         "@interface AlphaModule : NSObject <ALNModule>\n"
         "@end\n\n"
         "@implementation AlphaModule\n"
         "- (NSString *)moduleIdentifier { return @\"alpha\"; }\n"
         "- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error { (void)application; (void)error; return YES; }\n"
         "@end\n";
    NSString *betaClassSource =
        @"#import <Foundation/Foundation.h>\n"
         "#import \"ALNApplication.h\"\n"
         "#import \"ALNModuleSystem.h\"\n\n"
         "@interface BetaModule : NSObject <ALNModule>\n"
         "@end\n\n"
         "@implementation BetaModule\n"
         "- (NSString *)moduleIdentifier { return @\"beta\"; }\n"
         "- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error { (void)application; (void)error; return YES; }\n"
         "@end\n";

    XCTAssertTrue([self writeFile:[alphaSource stringByAppendingPathComponent:@"module.plist"]
                          content:@"{\n"
                                  "  identifier = \"alpha\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"AlphaModule\";\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[alphaSource stringByAppendingPathComponent:@"Sources/AlphaModule.m"]
                          content:alphaClassSource]);
    XCTAssertTrue([self writeFile:[alphaSource stringByAppendingPathComponent:@"Resources/Public/site.css"]
                          content:@"module-alpha\n"]);
    XCTAssertTrue([self writeFile:[alphaSource stringByAppendingPathComponent:@"Resources/Templates/dashboard/index.html.eoc"]
                          content:@"<p>alpha module</p>\n"]);

    XCTAssertTrue([self writeFile:[betaSource stringByAppendingPathComponent:@"module.plist"]
                          content:@"{\n"
                                  "  identifier = \"beta\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"BetaModule\";\n"
                                  "  dependencies = (\n"
                                  "    { identifier = \"alpha\"; version = \">= 1.0.0\"; }\n"
                                  "  );\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[betaSource stringByAppendingPathComponent:@"Sources/BetaModule.m"]
                          content:betaClassSource]);
    XCTAssertTrue([self writeFile:[betaSource stringByAppendingPathComponent:@"Resources/Public/beta.css"]
                          content:@"module-beta\n"]);

    XCTAssertTrue([self writeFile:[alphaV2Source stringByAppendingPathComponent:@"module.plist"]
                          content:@"{\n"
                                  "  identifier = \"alpha\";\n"
                                  "  version = \"2.0.0\";\n"
                                  "  principalClass = \"AlphaModule\";\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[alphaV2Source stringByAppendingPathComponent:@"Sources/AlphaModule.m"]
                          content:alphaClassSource]);
    XCTAssertTrue([self writeFile:[alphaV2Source stringByAppendingPathComponent:@"Resources/Public/site.css"]
                          content:@"module-alpha-v2\n"]);

    int code = 0;
    NSString *buildOutput = [self runShellCapture:[self buildToolsCommandForRepoRoot:repoRoot]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSString *addAlpha = [self runJSONCommand:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen module add alpha --source %@ --json",
        appRoot, repoRoot, repoRoot, alphaSource]
                                      exitCode:&code];
    XCTAssertEqual(0, code, @"%@", addAlpha);
    NSDictionary *addAlphaPayload = [self parseJSONDictionary:addAlpha];
    XCTAssertEqualObjects(@"ok", addAlphaPayload[@"status"]);

    NSString *addBeta = [self runJSONCommand:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen module add beta --source %@ --json",
        appRoot, repoRoot, repoRoot, betaSource]
                                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", addBeta);

    NSString *listOutput = [self runJSONCommand:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module list --json",
        appRoot, repoRoot]
                                        exitCode:&code];
    XCTAssertEqual(0, code, @"%@", listOutput);
    NSDictionary *listPayload = [self parseJSONDictionary:listOutput];
    NSArray<NSDictionary *> *modules = listPayload[@"modules"];
    XCTAssertEqualObjects(@"alpha", modules[0][@"identifier"]);
    XCTAssertEqualObjects(@"beta", modules[1][@"identifier"]);

    NSString *doctorOutput = [self runJSONCommand:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module doctor --env development --json",
        appRoot, repoRoot]
                                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", doctorOutput);
    NSDictionary *doctorPayload = [self parseJSONDictionary:doctorOutput];
    XCTAssertEqualObjects(@"ok", doctorPayload[@"status"]);

    NSString *assetsOutput = [self runJSONCommand:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module assets --output-dir build/module_assets --json",
        appRoot, repoRoot]
                                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", assetsOutput);
    NSString *stagedAssetPath = [appRoot stringByAppendingPathComponent:@"build/module_assets/modules/alpha/site.css"];
    NSString *stagedAssetContents = [NSString stringWithContentsOfFile:stagedAssetPath
                                                              encoding:NSUTF8StringEncoding
                                                                 error:nil];
    XCTAssertEqualObjects(@"app-override\n", stagedAssetContents);

    NSString *prepareOutput = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/bin/boomhauer --prepare-only",
        appRoot, repoRoot, repoRoot]
                                           exitCode:&code];
    XCTAssertEqual(0, code, @"%@", prepareOutput);

    NSString *upgradeOutput = [self runJSONCommand:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module upgrade alpha --source %@ --json",
        appRoot, repoRoot, alphaV2Source]
                                           exitCode:&code];
    XCTAssertEqual(0, code, @"%@", upgradeOutput);
    NSDictionary *upgradePayload = [self parseJSONDictionary:upgradeOutput];
    XCTAssertEqualObjects(@"updated", upgradePayload[@"status"]);

    NSString *listOutput2 = [self runJSONCommand:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module list --json",
        appRoot, repoRoot]
                                         exitCode:&code];
    NSDictionary *listPayload2 = [self parseJSONDictionary:listOutput2];
    XCTAssertEqualObjects(@"2.0.0", listPayload2[@"modules"][0][@"version"]);

    NSString *releaseCommand = [NSString stringWithFormat:
        @"%s/tools/deploy/build_release.sh --app-root %s --framework-root %s --releases-dir %s --release-id phase13 --allow-missing-certification",
        [repoRoot UTF8String], [appRoot UTF8String], [repoRoot UTF8String], [releaseRoot UTF8String]];
    NSString *releaseOutput = [self runShellCapture:releaseCommand exitCode:&code];
    XCTAssertEqual(0, code, @"%@", releaseOutput);
    NSString *releaseModulePath =
        [releaseRoot stringByAppendingPathComponent:@"phase13/app/modules/alpha/module.plist"];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:releaseModulePath]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:modulesRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:releaseRoot error:nil];
  }
}

- (NSString *)arlenModuleCommand:(NSString *)arguments
                        appRoot:(NSString *)appRoot
                       repoRoot:(NSString *)repoRoot
                  frameworkRoot:(NSString *)frameworkRoot {
  NSString *config = [self warningGNUstepConfig];
  NSString *configAssignment =
      config != nil ? [NSString stringWithFormat:@"GNUSTEP_CONFIG_FILE=%@ ", ALNTestShellQuote(config)] : @"";
  return [NSString stringWithFormat:@"cd %@ && %@ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen module %@",
                                    ALNTestShellQuote(appRoot),
                                    configAssignment,
                                    ALNTestShellQuote(frameworkRoot),
                                    ALNTestShellQuote(repoRoot),
                                    arguments];
}

- (NSArray<NSString *> *)diagnosticCodesInDoctorPayload:(NSDictionary *)payload module:(NSString *)module {
  NSMutableArray<NSString *> *codes = [NSMutableArray array];
  for (NSDictionary *entry in payload[@"diagnostics"] ?: @[]) {
    if ([entry[@"module"] isEqualToString:module]) {
      [codes addObject:entry[@"code"] ?: @""];
    }
  }
  return codes;
}

// GitHub issue 106: upgrade keeps the app's enabled flag and stamps copied files
// with the install time, so incremental builds recompile them.
- (void)testModuleUpgradeKeepsEnabledFlagAndStampsCopiedFiles {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13-module-enabled-app"];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"phase13-module-enabled-src"];
  XCTAssertNotNil(appRoot);
  XCTAssertNotNil(workRoot);
  if (appRoot == nil || workRoot == nil) {
    return;
  }
  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n  host = \"127.0.0.1\";\n  port = 3000;\n}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    NSString *frameworkRoot = [workRoot stringByAppendingPathComponent:@"framework"];
    NSString *source = [frameworkRoot stringByAppendingPathComponent:@"modules/alpha"];
    NSString *sourceFile = [source stringByAppendingPathComponent:@"Sources/AlphaModule.m"];
    NSString *installedFile = [appRoot stringByAppendingPathComponent:@"modules/alpha/Sources/AlphaModule.m"];
    NSString *lockPath = [appRoot stringByAppendingPathComponent:@"config/modules.plist"];
    XCTAssertTrue([self writeFile:[source stringByAppendingPathComponent:@"module.plist"]
                          content:@"{\n  identifier = \"alpha\";\n  version = \"1.0.0\";\n  principalClass = \"AlphaModule\";\n}\n"]);
    XCTAssertTrue([self writeFile:sourceFile content:@"// release 1\n"]);

    int code = 0;
    NSString *buildOutput = [self runShellCapture:[self buildToolsCommandForRepoRoot:repoRoot] exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);
    NSString *output = [self runJSONCommand:[self arlenModuleCommand:[NSString stringWithFormat:@"add alpha --source %@ --json",
                                                                                                ALNTestShellQuote(source)]
                                                              appRoot:appRoot
                                                             repoRoot:repoRoot
                                                        frameworkRoot:frameworkRoot]
                                    exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);

    // The app disables the module, as InvitoContext does for mcp.
    NSMutableDictionary *lock = [[NSDictionary dictionaryWithContentsOfFile:lockPath] mutableCopy];
    NSMutableArray *modules = [lock[@"modules"] mutableCopy];
    NSMutableDictionary *alpha = [modules[0] mutableCopy];
    alpha[@"enabled"] = @"0";
    modules[0] = alpha;
    lock[@"modules"] = modules;
    XCTAssertTrue([lock writeToFile:lockPath atomically:YES]);

    // A newer release whose files carry an old checkout mtime.
    XCTAssertTrue([self writeFile:[source stringByAppendingPathComponent:@"module.plist"]
                          content:@"{\n  identifier = \"alpha\";\n  version = \"2.0.0\";\n  principalClass = \"AlphaModule\";\n}\n"]);
    XCTAssertTrue([self writeFile:sourceFile content:@"// release 2\n"]);
    NSDate *old = [NSDate dateWithTimeIntervalSince1970:1577836800];  // 2020-01-01
    for (NSString *file in @[ sourceFile, [source stringByAppendingPathComponent:@"module.plist"] ]) {
      XCTAssertTrue([[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate : old } ofItemAtPath:file error:NULL]);
    }

    NSDate *beforeUpgrade = [NSDate dateWithTimeIntervalSinceNow:-2];
    output = [self runJSONCommand:[self arlenModuleCommand:[NSString stringWithFormat:@"upgrade alpha --source %@ --json",
                                                                                      ALNTestShellQuote(source)]
                                                    appRoot:appRoot
                                                   repoRoot:repoRoot
                                              frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertEqualObjects(@"updated", [self parseJSONDictionary:output][@"status"], @"%@", output);

    NSDictionary *upgraded = [NSDictionary dictionaryWithContentsOfFile:lockPath][@"modules"][0];
    XCTAssertEqualObjects(@"2.0.0", upgraded[@"version"]);
    XCTAssertFalse([upgraded[@"enabled"] boolValue], @"%@", upgraded);
    XCTAssertEqualObjects(@"// release 2\n", [NSString stringWithContentsOfFile:installedFile encoding:NSUTF8StringEncoding error:NULL]);
    NSDate *installedAt = [[NSFileManager defaultManager] attributesOfItemAtPath:installedFile error:NULL][NSFileModificationDate];
    XCTAssertTrue([installedAt compare:beforeUpgrade] != NSOrderedAscending, @"%@ vs %@", installedAt, beforeUpgrade);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testModuleUpgradeDetectsSameVersionContentChanges {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13-module-digest-app"];
  NSString *workRoot = [self createTempDirectoryWithPrefix:@"phase13-module-digest-src"];
  XCTAssertNotNil(appRoot);
  XCTAssertNotNil(workRoot);
  if (appRoot == nil || workRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n  host = \"127.0.0.1\";\n  port = 3000;\n}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);

    // The fake framework checkout doubles as the upgrade source, like vendor/Arlen/modules/<name>.
    NSString *frameworkRoot = [workRoot stringByAppendingPathComponent:@"framework"];
    NSString *source = [frameworkRoot stringByAppendingPathComponent:@"modules/alpha"];
    NSString *sourceFile = [source stringByAppendingPathComponent:@"Sources/AlphaModule.m"];
    NSString *installedFile = [appRoot stringByAppendingPathComponent:@"modules/alpha/Sources/AlphaModule.m"];
    XCTAssertTrue([self writeFile:[source stringByAppendingPathComponent:@"module.plist"]
                          content:@"{\n  identifier = \"alpha\";\n  version = \"1.0.0\";\n  principalClass = \"AlphaModule\";\n}\n"]);
    XCTAssertTrue([self writeFile:sourceFile content:@"// release 1\n"]);

    int code = 0;
    NSString *buildOutput = [self runShellCapture:[self buildToolsCommandForRepoRoot:repoRoot] exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSString *upgrade = [NSString stringWithFormat:@"upgrade alpha --source %@ --json", ALNTestShellQuote(source)];
    NSString *forcedUpgrade =
        [NSString stringWithFormat:@"upgrade alpha --source %@ --force --json", ALNTestShellQuote(source)];

    NSString *output = [self runJSONCommand:[self arlenModuleCommand:[NSString stringWithFormat:@"add alpha --source %@ --json",
                                                                                                ALNTestShellQuote(source)]
                                                              appRoot:appRoot
                                                             repoRoot:repoRoot
                                                        frameworkRoot:frameworkRoot]
                                    exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    NSDictionary *payload = [self parseJSONDictionary:output];
    NSString *digestV1 = payload[@"contentDigest"];
    XCTAssertTrue([digestV1 hasPrefix:@"sha256:"], @"%@", output);
    NSDictionary *lock = [NSDictionary dictionaryWithContentsOfFile:
        [appRoot stringByAppendingPathComponent:@"config/modules.plist"]];
    XCTAssertEqualObjects(digestV1, lock[@"modules"][0][@"contentDigest"]);

    // Unchanged source: a genuine no-op.
    output = [self runJSONCommand:[self arlenModuleCommand:upgrade appRoot:appRoot repoRoot:repoRoot frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertEqualObjects(@"noop", [self parseJSONDictionary:output][@"status"]);

    // Issue 54: upstream sources change but version stays 1.0.0.
    XCTAssertTrue([self writeFile:sourceFile content:@"// release 2 security fix\n"]);
    output = [self runJSONCommand:[self arlenModuleCommand:@"doctor --json" appRoot:appRoot repoRoot:repoRoot frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertTrue([[self diagnosticCodesInDoctorPayload:[self parseJSONDictionary:output] module:@"alpha"]
                      containsObject:@"module_framework_copy_differs"], @"%@", output);

    output = [self runJSONCommand:[self arlenModuleCommand:upgrade appRoot:appRoot repoRoot:repoRoot frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    payload = [self parseJSONDictionary:output];
    XCTAssertEqualObjects(@"updated", payload[@"status"]);
    XCTAssertEqualObjects(@"content_changed", payload[@"reason"]);
    XCTAssertEqualObjects(@"// release 2 security fix\n",
                          [NSString stringWithContentsOfFile:installedFile encoding:NSUTF8StringEncoding error:NULL]);

    // A locally edited vendored copy is never overwritten without --force.
    XCTAssertTrue([self writeFile:installedFile content:@"// local patch\n"]);
    XCTAssertTrue([self writeFile:sourceFile content:@"// release 3\n"]);
    output = [self runJSONCommand:[self arlenModuleCommand:@"doctor --json" appRoot:appRoot repoRoot:repoRoot frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertTrue([[self diagnosticCodesInDoctorPayload:[self parseJSONDictionary:output] module:@"alpha"]
                      containsObject:@"module_locally_modified"], @"%@", output);

    output = [self runJSONCommand:[self arlenModuleCommand:upgrade appRoot:appRoot repoRoot:repoRoot frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertEqual(1, code, @"%@", output);
    payload = [self parseJSONDictionary:output];
    XCTAssertEqualObjects(@"error", payload[@"status"]);
    XCTAssertEqualObjects(@"content_differs", payload[@"error"][@"code"]);
    XCTAssertEqualObjects(@YES, payload[@"locally_modified"]);
    XCTAssertEqualObjects((@[ @"Sources/AlphaModule.m" ]), payload[@"differing_files"]);
    XCTAssertEqualObjects(@"// local patch\n",
                          [NSString stringWithContentsOfFile:installedFile encoding:NSUTF8StringEncoding error:NULL]);

    // `module add` at the same version also refuses to silently keep stale files.
    output = [self runJSONCommand:[self arlenModuleCommand:[NSString stringWithFormat:@"add alpha --source %@ --json",
                                                                                      ALNTestShellQuote(source)]
                                                    appRoot:appRoot
                                                   repoRoot:repoRoot
                                              frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertEqual(1, code, @"%@", output);
    XCTAssertEqualObjects(@"module_already_installed", [self parseJSONDictionary:output][@"error"][@"code"]);

    output = [self runJSONCommand:[self arlenModuleCommand:forcedUpgrade appRoot:appRoot repoRoot:repoRoot frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    payload = [self parseJSONDictionary:output];
    XCTAssertEqualObjects(@"updated", payload[@"status"]);
    XCTAssertEqualObjects(@"forced", payload[@"reason"]);
    XCTAssertEqualObjects(@"// release 3\n",
                          [NSString stringWithContentsOfFile:installedFile encoding:NSUTF8StringEncoding error:NULL]);

    // Locks written before contentDigest existed cannot prove the copy is unedited.
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n  modules = (\n    { identifier = \"alpha\"; path = \"modules/alpha\"; version = \"1.0.0\"; enabled = YES; }\n  );\n}\n"]);
    output = [self runJSONCommand:[self arlenModuleCommand:@"doctor --json" appRoot:appRoot repoRoot:repoRoot frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertTrue([[self diagnosticCodesInDoctorPayload:[self parseJSONDictionary:output] module:@"alpha"]
                      containsObject:@"module_content_untracked"], @"%@", output);

    XCTAssertTrue([self writeFile:sourceFile content:@"// release 4\n"]);
    output = [self runJSONCommand:[self arlenModuleCommand:upgrade appRoot:appRoot repoRoot:repoRoot frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertEqual(1, code, @"%@", output);
    payload = [self parseJSONDictionary:output];
    XCTAssertEqualObjects(@"content_differs", payload[@"error"][@"code"]);
    XCTAssertEqualObjects(@NO, payload[@"locally_modified"]);

    output = [self runJSONCommand:[self arlenModuleCommand:forcedUpgrade appRoot:appRoot repoRoot:repoRoot frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    output = [self runJSONCommand:[self arlenModuleCommand:@"doctor --json" appRoot:appRoot repoRoot:repoRoot frameworkRoot:frameworkRoot]
                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", output);
    XCTAssertEqualObjects(@[], [self diagnosticCodesInDoctorPayload:[self parseJSONDictionary:output] module:@"alpha"],
                          @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:workRoot error:nil];
  }
}

- (void)testBoomhauerIgnoresStaleGeneratedModuleSourcesOutsideCurrentTemplateInventory {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13-stale-generated-module-app"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n"
                                  "  host = \"127.0.0.1\";\n"
                                  "  port = 3000;\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "#import \"ArlenServer.h\"\n"
                                  "#import \"ALNContext.h\"\n"
                                  "#import \"ALNController.h\"\n\n"
                                  "@interface Phase13StaleTemplateController : ALNController\n"
                                  "@end\n\n"
                                  "@implementation Phase13StaleTemplateController\n"
                                  "- (id)index:(ALNContext *)ctx { (void)ctx; [self renderText:@\"ok\\n\"]; return nil; }\n"
                                  "@end\n\n"
                                  "static void RegisterRoutes(ALNApplication *app) {\n"
                                  "  [app registerRouteMethod:@\"GET\" path:@\"/\" name:@\"home\" controllerClass:[Phase13StaleTemplateController class] action:@\"index\"];\n"
                                  "}\n\n"
                                  "int main(int argc, const char *argv[]) {\n"
                                  "  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/demo/Resources/Templates/dashboard/index.html.eoc"]
                          content:@"<section>module dashboard</section>\n"]);

    int code = 0;
    NSString *buildOutput = [self runShellCapture:[self buildToolsCommandForRepoRoot:repoRoot]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSString *prepareCommand = [NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/bin/boomhauer --prepare-only",
        appRoot, repoRoot, repoRoot];
    NSString *firstPrepareOutput = [self runShellCapture:prepareCommand exitCode:&code];
    XCTAssertEqual(0, code, @"%@", firstPrepareOutput);

    NSString *currentGeneratedPath =
        [appRoot stringByAppendingPathComponent:@".boomhauer/build/gen/templates/modules/demo/dashboard/index.html.eoc.m"];
    NSString *staleGeneratedPath =
        [appRoot stringByAppendingPathComponent:@".boomhauer/build/gen/templates/modules/demo/modules/demo/dashboard/index.html.eoc.m"];
    NSError *readError = nil;
    NSString *generatedSource = [NSString stringWithContentsOfFile:currentGeneratedPath
                                                          encoding:NSUTF8StringEncoding
                                                             error:&readError];
    XCTAssertNotNil(generatedSource, @"%@", readError.localizedDescription ?: @"missing generated source");
    XCTAssertNil(readError);
    if (generatedSource == nil) {
      return;
    }
    XCTAssertTrue([self writeFile:staleGeneratedPath content:generatedSource ?: @""]);

    NSString *secondPrepareOutput = [self runShellCapture:prepareCommand exitCode:&code];
    XCTAssertEqual(0, code, @"%@", secondPrepareOutput);

    NSString *appMakefilePath = [appRoot stringByAppendingPathComponent:@".boomhauer/build/AppGNUmakefile"];
    readError = nil;
    NSString *appMakefile = [NSString stringWithContentsOfFile:appMakefilePath
                                                      encoding:NSUTF8StringEncoding
                                                         error:&readError];
    XCTAssertNotNil(appMakefile);
    XCTAssertNil(readError);
    XCTAssertTrue([appMakefile containsString:currentGeneratedPath], @"%@", appMakefile ?: @"");
    XCTAssertFalse([appMakefile containsString:staleGeneratedPath], @"%@", appMakefile ?: @"");
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testJobsWorkerCLIExecutesQueuedJobFromAppRoot {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13-jobs-worker-app"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n"
                                  "  host = \"127.0.0.1\";\n"
                                  "  port = 3000;\n"
                                  "  jobsModule = {\n"
                                  "    providers = { classes = (\"Phase13JobsWorkerProvider\"); };\n"
                                  "    persistence = { enabled = NO; path = \"\"; };\n"
                                  "  };\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "#import \"ArlenServer.h\"\n"
                                  "#import \"ALNJobsModule.h\"\n\n"
                                  "@interface Phase13JobsWorkerJob : NSObject <ALNJobsJobDefinition>\n"
                                  "@end\n\n"
                                  "@implementation Phase13JobsWorkerJob\n"
                                  "- (NSString *)jobsModuleJobIdentifier { return @\"phase13.jobs_worker\"; }\n"
                                  "- (NSDictionary *)jobsModuleJobMetadata { return @{ @\"title\" : @\"Phase13 Jobs Worker\" }; }\n"
                                  "- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {\n"
                                  "  if ([payload[@\"markerPath\"] isKindOfClass:[NSString class]] && [payload[@\"markerPath\"] length] > 0) { return YES; }\n"
                                  "  if (error != NULL) {\n"
                                  "    *error = [NSError errorWithDomain:@\"Phase13JobsWorker\" code:1 userInfo:@{ NSLocalizedDescriptionKey : @\"markerPath is required\" }];\n"
                                  "  }\n"
                                  "  return NO;\n"
                                  "}\n"
                                  "- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {\n"
                                  "  (void)context;\n"
                                  "  NSError *writeError = nil;\n"
                                  "  BOOL ok = [@\"worker-ok\\n\" writeToFile:payload[@\"markerPath\"] atomically:YES encoding:NSUTF8StringEncoding error:&writeError];\n"
                                  "  if (!ok && error != NULL) { *error = writeError; }\n"
                                  "  return ok;\n"
                                  "}\n"
                                  "@end\n\n"
                                  "@interface Phase13JobsWorkerProvider : NSObject <ALNJobsJobProvider>\n"
                                  "@end\n\n"
                                  "@implementation Phase13JobsWorkerProvider\n"
                                  "- (NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime error:(NSError **)error {\n"
                                  "  (void)runtime; (void)error; return @[ [[Phase13JobsWorkerJob alloc] init] ];\n"
                                  "}\n"
                                  "@end\n\n"
                                  "static void RegisterRoutes(ALNApplication *app) {\n"
                                  "  (void)app;\n"
                                  "  NSString *markerPath = [[[NSProcessInfo processInfo] environment] objectForKey:@\"PHASE13_QUEUE_JOB_ON_BOOT\"];\n"
                                  "  if ([markerPath length] > 0) {\n"
                                  "    [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:@\"phase13.jobs_worker\"\n"
                                  "                                                       payload:@{ @\"markerPath\" : markerPath }\n"
                                  "                                                       options:nil\n"
                                  "                                                         error:NULL];\n"
                                  "  }\n"
                                  "}\n\n"
                                  "int main(int argc, const char *argv[]) {\n"
                                  "  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }\n"
                                  "}\n"]);

    int code = 0;
    NSString *addJobsOutput = [self runJSONCommand:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen module add jobs --json",
        appRoot, repoRoot, repoRoot]
                                           exitCode:&code];
    XCTAssertEqual(0, code, @"%@", addJobsOutput);

    NSString *markerPath = [appRoot stringByAppendingPathComponent:@"tmp/jobs-worker-marker.txt"];
    NSError *directoryError = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:[markerPath stringByDeletingLastPathComponent]
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&directoryError],
                  @"%@", directoryError.localizedDescription);
    NSString *workerOutput = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && PHASE13_QUEUE_JOB_ON_BOOT='%@' ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen jobs worker --env development --once --limit 1",
        appRoot, markerPath, repoRoot, repoRoot]
                                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", workerOutput);

    NSString *markerContents = [NSString stringWithContentsOfFile:markerPath
                                                         encoding:NSUTF8StringEncoding
                                                            error:nil];
    XCTAssertEqualObjects(@"worker-ok\n", markerContents);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

@end
