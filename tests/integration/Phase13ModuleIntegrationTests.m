#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

@interface Phase13ModuleIntegrationTests : XCTestCase
@end

@implementation Phase13ModuleIntegrationTests

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  NSString *templatePath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-XXXXXX", prefix]];
  char *buffer = strdup([templatePath fileSystemRepresentation]);
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
    XCTFail(@"failed creating %@: %@", dir, error.localizedDescription);
    return NO;
  }
  if (![content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
    XCTFail(@"failed writing %@: %@", path, error.localizedDescription);
    return NO;
  }
  return YES;
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
  NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
  NSMutableData *combined = [NSMutableData dataWithData:stdoutData ?: [NSData data]];
  if ([stderrData length] > 0) {
    [combined appendData:stderrData];
  }
  NSString *output = [[NSString alloc] initWithData:combined encoding:NSUTF8StringEncoding];
  return output ?: @"";
}

- (NSDictionary *)parseJSONDictionary:(NSString *)output {
  NSString *trimmed = [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  XCTAssertNil(error, @"invalid JSON: %@\n%@", error.localizedDescription, output);
  XCTAssertTrue([payload isKindOfClass:[NSDictionary class]]);
  return payload ?: @{};
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
    NSString *buildOutput = [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen eocc",
                                                                             repoRoot]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSString *addAlpha = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen module add alpha --source %@ --json",
        appRoot, repoRoot, repoRoot, alphaSource]
                                      exitCode:&code];
    XCTAssertEqual(0, code, @"%@", addAlpha);
    NSDictionary *addAlphaPayload = [self parseJSONDictionary:addAlpha];
    XCTAssertEqualObjects(@"ok", addAlphaPayload[@"status"]);

    NSString *addBeta = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen module add beta --source %@ --json",
        appRoot, repoRoot, repoRoot, betaSource]
                                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", addBeta);

    NSString *listOutput = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module list --json",
        appRoot, repoRoot]
                                        exitCode:&code];
    XCTAssertEqual(0, code, @"%@", listOutput);
    NSDictionary *listPayload = [self parseJSONDictionary:listOutput];
    NSArray<NSDictionary *> *modules = listPayload[@"modules"];
    XCTAssertEqualObjects(@"alpha", modules[0][@"identifier"]);
    XCTAssertEqualObjects(@"beta", modules[1][@"identifier"]);

    NSString *doctorOutput = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module doctor --env development --json",
        appRoot, repoRoot]
                                          exitCode:&code];
    XCTAssertEqual(0, code, @"%@", doctorOutput);
    NSDictionary *doctorPayload = [self parseJSONDictionary:doctorOutput];
    XCTAssertEqualObjects(@"ok", doctorPayload[@"status"]);

    NSString *assetsOutput = [self runShellCapture:[NSString stringWithFormat:
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

    NSString *upgradeOutput = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module upgrade alpha --source %@ --json",
        appRoot, repoRoot, alphaV2Source]
                                           exitCode:&code];
    XCTAssertEqual(0, code, @"%@", upgradeOutput);
    NSDictionary *upgradePayload = [self parseJSONDictionary:upgradeOutput];
    XCTAssertEqualObjects(@"updated", upgradePayload[@"status"]);

    NSString *listOutput2 = [self runShellCapture:[NSString stringWithFormat:
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
    NSString *addJobsOutput = [self runShellCapture:[NSString stringWithFormat:
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
