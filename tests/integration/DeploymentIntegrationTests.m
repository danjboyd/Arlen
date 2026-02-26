#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

@interface DeploymentIntegrationTests : XCTestCase
@end

@implementation DeploymentIntegrationTests

- (int)randomPort {
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

- (void)testBoomhauerBuildCompilePathEnforcesARC {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *scriptPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];

  NSError *error = nil;
  NSString *script =
      [NSString stringWithContentsOfFile:scriptPath encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNotNil(script);
  XCTAssertNil(error);
  if (script == nil || error != nil) {
    return;
  }

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
                                       "--framework-root %s --releases-dir %s --release-id frontend-1",
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

    NSString *appRoot = [workRoot stringByAppendingPathComponent:@"AgentDX"];
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
    NSArray *modifiedFiles = [generatePayload[@"modified_files"] isKindOfClass:[NSArray class]]
                                 ? generatePayload[@"modified_files"]
                                 : @[];
    XCTAssertTrue([modifiedFiles containsObject:@"src/main.m"]);

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
    NSDictionary *error = [invalidPayload[@"error"] isKindOfClass:[NSDictionary class]]
                              ? invalidPayload[@"error"]
                              : @{};
    XCTAssertEqualObjects(@"missing_route", error[@"code"]);
    NSDictionary *fixit = [error[@"fixit"] isKindOfClass:[NSDictionary class]] ? error[@"fixit"] : @{};
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
                                             "--dry-run --json",
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
    NSString *output =
        [self runShellCapture:[NSString stringWithFormat:
                                            @"cd %@ && ./build/eocc --template-root %@ --output-dir %@ %@ %@",
                                            repoRoot,
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
    XCTAssertEqual(0, [suppressionSummary[@"active_count"] integerValue]);

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
    int code = 0;
    NSString *command = [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_PHASE10E_OUTPUT_DIR=%@ "
                                       "ARLEN_PHASE10E_ITERATIONS=120 ARLEN_PHASE10E_WARMUP=20 "
                                       "bash ./tools/ci/run_phase10e_json_performance.sh",
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
