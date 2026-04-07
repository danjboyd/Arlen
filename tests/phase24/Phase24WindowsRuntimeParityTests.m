#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>
#import <unistd.h>

@interface Phase24WindowsRuntimeParityTests : XCTestCase
@end

@implementation Phase24WindowsRuntimeParityTests

- (NSString *)resolvedBashLaunchPath {
  NSString *override = [[[NSProcessInfo processInfo] environment] objectForKey:@"ARLEN_BASH_PATH"];
  NSArray<NSString *> *candidates = @[
    [override isKindOfClass:[NSString class]] ? override : @"",
    @"C:/msys64/usr/bin/bash.exe",
    @"C:/msys64/usr/bin/bash",
    @"/usr/bin/bash",
    @"/bin/bash",
  ];
  for (NSString *candidate in candidates) {
    if ([candidate length] == 0) {
      continue;
    }
    if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
      return candidate;
    }
  }
  return @"C:/msys64/usr/bin/bash.exe";
}

- (int)randomPort {
  return 35000 + (int)(rand() % 2000);
}

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  NSString *root = [[self repoRoot] stringByAppendingPathComponent:@"build/phase24-temp"];
  NSError *rootError = nil;
  BOOL rootCreated = [[NSFileManager defaultManager] createDirectoryAtPath:root
                                               withIntermediateDirectories:YES
                                                                attributes:nil
                                                                     error:&rootError];
  XCTAssertTrue(rootCreated, @"failed creating temp root %@: %@", root, rootError.localizedDescription);
  XCTAssertNil(rootError);
  if (!rootCreated || rootError != nil) {
    return nil;
  }

  NSString *path = [root stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",
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
  NSString *directory = [path stringByDeletingLastPathComponent];
  NSError *error = nil;
  BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&error];
  XCTAssertTrue(created, @"failed creating directory %@: %@", directory, error.localizedDescription);
  XCTAssertNil(error);
  if (!created || error != nil) {
    return NO;
  }

  BOOL wrote = [[content isKindOfClass:[NSString class]] ? content : @""
      writeToFile:path
       atomically:YES
         encoding:NSUTF8StringEncoding
            error:&error];
  XCTAssertTrue(wrote, @"failed writing %@: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  return wrote;
}

- (NSString *)shellQuoted:(NSString *)value {
  NSString *safeValue = value ?: @"";
  return [NSString stringWithFormat:@"'%@'",
                                    [safeValue stringByReplacingOccurrencesOfString:@"'"
                                                                            withString:@"'\"'\"'"]];
}

- (NSString *)runShellCapture:(NSString *)command exitCode:(int *)exitCode {
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = [self resolvedBashLaunchPath];
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
  NSString *stdoutText = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding] ?: @"";
  NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
  return [stdoutText stringByAppendingString:stderrText];
}

- (NSString *)requestPathWithRetries:(NSString *)path
                                port:(int)port
                            attempts:(NSInteger)attempts
                             success:(BOOL *)success {
  NSString *body = @"";
  for (NSInteger attempt = 0; attempt < attempts; attempt++) {
    int curlCode = 0;
    NSString *command =
        [NSString stringWithFormat:@"curl -fsS --connect-timeout 1 --max-time 1 http://127.0.0.1:%d%@",
                                   port,
                                   path ?: @"/"];
    body = [self runShellCapture:command exitCode:&curlCode];
    if (curlCode == 0) {
      if (success != NULL) {
        *success = YES;
      }
      return body;
    }
    usleep(250000);
  }
  if (success != NULL) {
    *success = NO;
  }
  return body;
}

- (NSString *)capturedOutputFromPipe:(NSPipe *)pipe {
  if (pipe == nil) {
    return @"";
  }
  NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  return output ?: @"";
}

- (NSString *)readTextFile:(NSString *)path {
  NSError *error = nil;
  NSString *contents = [NSString stringWithContentsOfFile:path
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
  if (contents == nil || error != nil) {
    return @"";
  }
  return contents;
}

- (void)terminateWindowsProcessesContaining:(NSString *)needle {
#if defined(_WIN32)
  NSString *safeNeedle =
      [[needle ?: @"" stringByReplacingOccurrencesOfString:@"'" withString:@"''"] copy];
  if ([safeNeedle length] == 0) {
    return;
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = @"C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe";
  task.arguments = @[
    @"-NoProfile",
    @"-Command",
    [NSString stringWithFormat:
                  @"$needle = '%@'; "
                   "Get-CimInstance Win32_Process | "
                   "Where-Object { $_.CommandLine -like ('*' + $needle + '*') } | "
                   "ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }",
                  safeNeedle]
  ];
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *exception) {
    (void)exception;
  }
#else
  (void)needle;
#endif
}

- (BOOL)sendSignalNamed:(NSString *)signalName toPID:(int)pid {
  int exitCode = 0;
  NSString *output = [self runShellCapture:[NSString stringWithFormat:@"kill -%s %d",
                                                                      [(signalName ?: @"TERM") UTF8String],
                                                                      pid]
                                  exitCode:&exitCode];
  if (exitCode == 0) {
    return YES;
  }
  NSString *message = [output lowercaseString];
  if ([message containsString:@"no such process"]) {
    return NO;
  }
  XCTFail(@"%@", output);
  return NO;
}

- (void)terminateTask:(NSTask *)task preferredSignalName:(NSString *)signalName {
  if (task == nil) {
    return;
  }

  int pid = task.processIdentifier;
  if (pid <= 0) {
    return;
  }

  if ([task isRunning]) {
    (void)[self sendSignalNamed:signalName toPID:pid];
  }
  for (NSInteger attempt = 0; attempt < 10 && [task isRunning]; attempt++) {
    usleep(100000);
  }
#if defined(_WIN32)
  NSTask *killer = [[NSTask alloc] init];
  killer.launchPath = @"C:/Windows/System32/taskkill.exe";
  killer.arguments = @[ @"/T", @"/F", @"/PID", [NSString stringWithFormat:@"%d", pid] ];
  @try {
    [killer launch];
    [killer waitUntilExit];
  } @catch (NSException *exception) {
    (void)exception;
  }
#else
  if ([task isRunning]) {
    (void)[self sendSignalNamed:@"KILL" toPID:task.processIdentifier];
  }
  for (NSInteger attempt = 0; attempt < 10 && [task isRunning]; attempt++) {
    usleep(100000);
  }
#endif
  @try {
    [task waitUntilExit];
  } @catch (NSException *exception) {
    (void)exception;
  }
}

- (NSString *)repoRoot {
  return [[NSFileManager defaultManager] currentDirectoryPath];
}

- (NSString *)arlenToolPath {
  return [[self repoRoot] stringByAppendingPathComponent:@"build/arlen"];
}

- (NSString *)scaffoldLiteAppAtPath:(NSString *)appRoot {
  NSString *repoRoot = [self repoRoot];
  int exitCode = 0;
  NSString *output = [self runShellCapture:[NSString stringWithFormat:
      @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ new %@ --lite --force",
      [self shellQuoted:repoRoot],
      [self shellQuoted:repoRoot],
      [self shellQuoted:[self arlenToolPath]],
      [self shellQuoted:appRoot]]
                                  exitCode:&exitCode];
  XCTAssertEqual(0, exitCode, @"%@", output);
  return output;
}

- (void)testBoomhauerWatchRecoversFromBuildFailure {
#if !ARLEN_WINDOWS_PREVIEW
  return;
#endif

  NSString *repoRoot = [self repoRoot];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"arlen-phase24-watch"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSTask *server = nil;
  int port = [self randomPort];
  NSString *serverLogPath = [appRoot stringByAppendingPathComponent:@".phase24-watch.log"];
  @try {
    (void)[self scaffoldLiteAppAtPath:appRoot];

    NSString *appSourcePath = [appRoot stringByAppendingPathComponent:@"app_lite.m"];
    NSError *readError = nil;
    NSString *originalSource =
        [NSString stringWithContentsOfFile:appSourcePath encoding:NSUTF8StringEncoding error:&readError];
    XCTAssertNotNil(originalSource);
    XCTAssertNil(readError);
    if (originalSource == nil) {
      return;
    }

    NSString *brokenSource = [originalSource stringByAppendingString:@"\n#error WATCH_BUILD_TOGGLE\n"];
    XCTAssertTrue([self writeFile:appSourcePath content:brokenSource]);

    server = [[NSTask alloc] init];
    server.launchPath = [self resolvedBashLaunchPath];
    server.arguments = @[ @"-lc",
                          [NSString stringWithFormat:
                                        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ ARLEN_APP_ROOT=%@ ARLEN_BOOMHAUER_BUILD_ERROR_RETRY_SECONDS=1 ARLEN_BOOMHAUER_BUILD_ERROR_AUTO_REFRESH_SECONDS=1 %@ --watch --port %d >%@ 2>&1",
                                        [self shellQuoted:appRoot],
                                        [self shellQuoted:repoRoot],
                                        [self shellQuoted:appRoot],
                                        [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/boomhauer"]],
                                        port,
                                        [self shellQuoted:serverLogPath]] ];
    server.currentDirectoryPath = repoRoot;
    [server launch];

    BOOL errorServerReady = NO;
    NSString *healthBody = [self requestPathWithRetries:@"/healthz"
                                                   port:port
                                               attempts:180
                                                success:&errorServerReady];
    XCTAssertTrue(errorServerReady, @"server log:\n%@",
                  [self readTextFile:serverLogPath]);
    XCTAssertEqualObjects(@"degraded\n", healthBody);

    BOOL errorPageSeen = NO;
    for (NSInteger attempt = 0; attempt < 30; attempt++) {
      int curlCode = 0;
      NSString *body =
          [self runShellCapture:[NSString stringWithFormat:@"curl -sS --connect-timeout 1 --max-time 1 http://127.0.0.1:%d/",
                                                            port]
                       exitCode:&curlCode];
      if (curlCode == 0 && [body containsString:@"Boomhauer Build Failed"]) {
        XCTAssertTrue([body containsString:@"WATCH_BUILD_TOGGLE"], @"%@", body);
        XCTAssertTrue([body containsString:@"http-equiv='refresh'"], @"%@", body);
        XCTAssertTrue([body containsString:@"Boomhauer retries automatically every 1 seconds"],
                      @"%@", body);
        errorPageSeen = YES;
        break;
      }
      usleep(250000);
    }
    XCTAssertTrue(errorPageSeen, @"server log:\n%@",
                  [self readTextFile:serverLogPath]);

    BOOL jsonSeen = NO;
    for (NSInteger attempt = 0; attempt < 60; attempt++) {
      int curlCode = 0;
      NSString *jsonBody = [self
          runShellCapture:[NSString stringWithFormat:
                                              @"curl -sS --connect-timeout 1 --max-time 1 -H 'Accept: application/json' http://127.0.0.1:%d/api/dev/build-error",
                                              port]
                 exitCode:&curlCode];
      if (curlCode == 0 && [jsonBody containsString:@"dev_build_failed"] &&
          [jsonBody containsString:@"auto_retry_seconds"] &&
          [jsonBody containsString:@"recovery_hint"]) {
        jsonSeen = YES;
        break;
      }
      usleep(250000);
    }
    XCTAssertTrue(jsonSeen, @"server log:\n%@",
                  [self readTextFile:serverLogPath]);

    XCTAssertTrue([self writeFile:appSourcePath content:originalSource]);

    BOOL recovered = NO;
    for (NSInteger attempt = 0; attempt < 120; attempt++) {
      int curlCode = 0;
      NSString *body =
          [self runShellCapture:[NSString stringWithFormat:@"curl -fsS --connect-timeout 1 --max-time 1 http://127.0.0.1:%d/",
                                                            port]
                       exitCode:&curlCode];
      if (curlCode == 0 && [body containsString:@"hello from lite mode"]) {
        recovered = YES;
        break;
      }
      usleep(250000);
    }
    XCTAssertTrue(recovered, @"server log:\n%@",
                  [self readTextFile:serverLogPath]);
  } @finally {
    [self terminateTask:server preferredSignalName:@"TERM"];
    [self terminateWindowsProcessesContaining:[appRoot lastPathComponent]];
    [self terminateWindowsProcessesContaining:[NSString stringWithFormat:@"--port %d", port]];
    for (NSInteger attempt = 0; attempt < 20; attempt++) {
      if (![[NSFileManager defaultManager] fileExistsAtPath:appRoot]) {
        break;
      }
      if ([[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil]) {
        break;
      }
      usleep(100000);
    }
    [[NSFileManager defaultManager] removeItemAtPath:serverLogPath error:nil];
  }
}

- (void)testJobsWorkerRunsQueuedJobViaCLI {
#if !ARLEN_WINDOWS_PREVIEW
  return;
#endif

  NSString *repoRoot = [self repoRoot];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"arlen-phase24-jobs"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    (void)[self scaffoldLiteAppAtPath:appRoot];

    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:@"{\n"
                                  "  host = \"127.0.0.1\";\n"
                                  "  port = 3000;\n"
                                  "  jobsModule = {\n"
                                  "    providers = { classes = (\"Phase24JobsWorkerProvider\"); };\n"
                                  "    persistence = { enabled = NO; path = \"\"; };\n"
                                  "  };\n"
                                  "}\n"]);

    NSString *appSource =
        @"#import <Foundation/Foundation.h>\n"
         "#import <stdio.h>\n"
         "#import \"ArlenServer.h\"\n"
         "#import \"ALNJobsModule.h\"\n\n"
         "@interface Phase24JobsWorkerJob : NSObject <ALNJobsJobDefinition>\n"
         "@end\n\n"
         "@implementation Phase24JobsWorkerJob\n"
         "- (NSString *)jobsModuleJobIdentifier { return @\"phase24.jobs_worker\"; }\n"
         "- (NSDictionary *)jobsModuleJobMetadata { return @{ @\"title\" : @\"Phase24 Jobs Worker\" }; }\n"
         "- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {\n"
         "  if ([payload[@\"markerPath\"] isKindOfClass:[NSString class]] && [payload[@\"markerPath\"] length] > 0) { return YES; }\n"
         "  if (error != NULL) {\n"
         "    *error = [NSError errorWithDomain:@\"Phase24JobsWorker\" code:1 userInfo:@{ NSLocalizedDescriptionKey : @\"markerPath is required\" }];\n"
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
         "@interface Phase24JobsWorkerProvider : NSObject <ALNJobsJobProvider>\n"
         "@end\n\n"
         "@implementation Phase24JobsWorkerProvider\n"
         "- (NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime error:(NSError **)error {\n"
         "  (void)runtime; (void)error; return @[ [[Phase24JobsWorkerJob alloc] init] ];\n"
         "}\n"
         "@end\n\n"
         "static void RegisterRoutes(ALNApplication *app) {\n"
         "  (void)app;\n"
         "  NSString *markerPath = [[[NSProcessInfo processInfo] environment] objectForKey:@\"PHASE24_QUEUE_JOB_ON_BOOT\"];\n"
         "  if ([markerPath length] > 0) {\n"
         "    NSError *enqueueError = nil;\n"
         "    NSString *jobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:@\"phase24.jobs_worker\"\n"
         "                                                                        payload:@{ @\"markerPath\" : markerPath }\n"
         "                                                                        options:nil\n"
         "                                                                          error:&enqueueError];\n"
         "    if ([jobID length] == 0) {\n"
         "      fprintf(stderr, \"phase24 jobs enqueue failed: %s\\n\", [[enqueueError localizedDescription] UTF8String]);\n"
         "      exit(1);\n"
         "    }\n"
         "  }\n"
         "}\n\n"
         "int main(int argc, const char *argv[]) {\n"
         "  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }\n"
         "}\n";
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"] content:appSource]);

    int exitCode = 0;
    NSString *addJobsOutput = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add jobs --json",
        [self shellQuoted:appRoot],
        [self shellQuoted:repoRoot],
        [self shellQuoted:[self arlenToolPath]]]
                                          exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addJobsOutput);

    NSString *markerPath = [appRoot stringByAppendingPathComponent:@"tmp/jobs-worker-marker.txt"];
    NSError *directoryError = nil;
    BOOL created = [[NSFileManager defaultManager]
        createDirectoryAtPath:[markerPath stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES
                       attributes:nil
                            error:&directoryError];
    XCTAssertTrue(created, @"%@", directoryError.localizedDescription);
    XCTAssertNil(directoryError);

    NSString *workerOutput = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && PHASE24_QUEUE_JOB_ON_BOOT=%@ ARLEN_FRAMEWORK_ROOT=%@ %@ jobs worker --env development --once --limit 1",
        [self shellQuoted:appRoot],
        [self shellQuoted:markerPath],
        [self shellQuoted:repoRoot],
        [self shellQuoted:[self arlenToolPath]]]
                                           exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", workerOutput);

    NSString *markerContents = nil;
    for (NSInteger attempt = 0; attempt < 40; attempt++) {
      markerContents = [NSString stringWithContentsOfFile:markerPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
      if ([markerContents isEqualToString:@"worker-ok\n"]) {
        break;
      }
      usleep(250000);
    }
    XCTAssertEqualObjects(@"worker-ok\n", markerContents, @"%@", workerOutput);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testPropaneServesRequestsAndHandlesReloadSignal {
#if !ARLEN_WINDOWS_PREVIEW
  return;
#endif

  NSString *repoRoot = [self repoRoot];
  NSString *appRoot = [repoRoot stringByAppendingPathComponent:@"examples/tech_demo"];
  NSString *runtimeRoot = [self createTempDirectoryWithPrefix:@"arlen-phase24-propane"];
  int port = [self randomPort];
  NSString *pidFile = [runtimeRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"manager-%d.pid", port]];
  NSString *lifecycleLog =
      [runtimeRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"manager-%d.log", port]];
  NSString *serverLogPath = [runtimeRoot stringByAppendingPathComponent:@"server.log"];
  NSTask *server = [[NSTask alloc] init];
  server.launchPath = [self resolvedBashLaunchPath];
  server.currentDirectoryPath = repoRoot;
  server.arguments = @[ @"-lc",
                        [NSString stringWithFormat:
                                      @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ ARLEN_APP_ROOT=%@ ARLEN_CLUSTER_EMIT_HEADERS=1 ARLEN_PROPANE_LIFECYCLE_LOG=%@ %@ --workers 2 --host 127.0.0.1 --port %d --env development --pid-file %@ >%@ 2>&1",
                                      [self shellQuoted:repoRoot],
                                      [self shellQuoted:repoRoot],
                                      [self shellQuoted:appRoot],
                                      [self shellQuoted:lifecycleLog],
                                      [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/propane"]],
                                      port,
                                      [self shellQuoted:pidFile],
                                      [self shellQuoted:serverLogPath]] ];
  [server launch];

  @try {
    BOOL ready = NO;
    NSString *firstBody = [self requestPathWithRetries:@"/healthz" port:port attempts:180 success:&ready];
    XCTAssertTrue(ready, @"server log:\n%@",
                  [self readTextFile:serverLogPath]);
    XCTAssertEqualObjects(@"ok\n", firstBody);

    NSError *pidReadError = nil;
    NSString *managerPIDText = [NSString stringWithContentsOfFile:pidFile
                                                         encoding:NSUTF8StringEncoding
                                                            error:&pidReadError];
    XCTAssertNotNil(managerPIDText);
    XCTAssertNil(pidReadError);
    int managerPID = [[managerPIDText ?: @"0"
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] intValue];
    XCTAssertTrue(managerPID > 0);

    XCTAssertTrue([self sendSignalNamed:@"HUP" toPID:managerPID],
                  @"server log:\n%@",
                  [self readTextFile:serverLogPath]);

    BOOL reloaded = NO;
    NSString *secondBody = [self requestPathWithRetries:@"/healthz" port:port attempts:180 success:&reloaded];
    XCTAssertTrue(reloaded, @"server log:\n%@",
                  [self readTextFile:serverLogPath]);
    XCTAssertEqualObjects(@"ok\n", secondBody);

    XCTAssertTrue([self sendSignalNamed:@"TERM" toPID:managerPID],
                  @"server log:\n%@",
                  [self readTextFile:serverLogPath]);
    for (NSInteger attempt = 0; attempt < 60 && [server isRunning]; attempt++) {
      usleep(100000);
    }
    if ([server isRunning]) {
      [self terminateTask:server preferredSignalName:@"TERM"];
    } else {
      [server waitUntilExit];
    }
    XCTAssertEqual(0, server.terminationStatus, @"server log:\n%@",
                   [self readTextFile:serverLogPath]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:pidFile]);

    NSError *readError = nil;
    NSString *lifecycle =
        [NSString stringWithContentsOfFile:lifecycleLog encoding:NSUTF8StringEncoding error:&readError];
    XCTAssertNotNil(lifecycle);
    XCTAssertNil(readError);
    XCTAssertTrue([lifecycle containsString:@"event=manager_reload_requested"], @"%@", lifecycle);
    XCTAssertTrue([lifecycle containsString:@"event=manager_reload_completed"], @"%@", lifecycle);
    XCTAssertTrue([lifecycle containsString:@"event=manager_stopped"], @"%@", lifecycle);
  } @finally {
    if ([server isRunning]) {
      [self terminateTask:server preferredSignalName:@"TERM"];
    }
    [[NSFileManager defaultManager] removeItemAtPath:pidFile error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:lifecycleLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:serverLogPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:runtimeRoot error:nil];
  }
}

@end
