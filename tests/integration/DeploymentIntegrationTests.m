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
                                                   "--framework-root %s --releases-dir %s --release-id rel1",
                                                  [repoRoot UTF8String], [appRoot UTF8String],
                                                  [repoRoot UTF8String], [releasesDir UTF8String]]
                                    exitCode:&code];
    XCTAssertEqual(0, code, @"%@", build1);

    NSString *build2 = [self runShellCapture:[NSString stringWithFormat:
                                                  @"%s/tools/deploy/build_release.sh --app-root %s "
                                                   "--framework-root %s --releases-dir %s --release-id rel2",
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

@end
