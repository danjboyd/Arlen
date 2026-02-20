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

@end
