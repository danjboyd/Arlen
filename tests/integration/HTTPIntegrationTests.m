#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <signal.h>
#import <unistd.h>

@interface HTTPIntegrationTests : XCTestCase
@end

@implementation HTTPIntegrationTests

- (int)randomPort {
  return 32000 + (int)arc4random_uniform(2000);
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
  NSString *output = [[NSString alloc] initWithData:stdoutData
                                           encoding:NSUTF8StringEncoding];
  return output ?: @"";
}

- (NSString *)requestPathWithRetries:(NSString *)path
                                port:(int)port
                            attempts:(NSInteger)attempts
                             success:(BOOL *)success {
  NSString *body = @"";
  for (NSInteger attempt = 0; attempt < attempts; attempt++) {
    int curlCode = 0;
    NSString *command =
        [NSString stringWithFormat:@"curl -fsS http://127.0.0.1:%d%@", port, path ?: @"/"];
    body = [self runShellCapture:command exitCode:&curlCode];
    if (curlCode == 0) {
      if (success != NULL) {
        *success = YES;
      }
      return body;
    }
    usleep(200000);
  }
  if (success != NULL) {
    *success = NO;
  }
  return body;
}

- (NSArray *)childPIDsForParent:(pid_t)parentPID {
  int exitCode = 0;
  NSString *command =
      [NSString stringWithFormat:@"ps -o pid= --ppid %d 2>/dev/null", (int)parentPID];
  NSString *output = [self runShellCapture:command exitCode:&exitCode];
  if (exitCode != 0 || [output length] == 0) {
    return @[];
  }

  NSMutableArray *pids = [NSMutableArray array];
  NSArray *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *line in lines) {
    NSString *trimmed =
        [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0) {
      continue;
    }
    NSInteger value = [trimmed integerValue];
    if (value > 0) {
      [pids addObject:@(value)];
    }
  }
  return pids;
}

- (NSArray *)waitForChildPIDsForParent:(pid_t)parentPID
                          minimumCount:(NSUInteger)minimumCount
                              attempts:(NSInteger)attempts {
  NSArray *last = @[];
  for (NSInteger idx = 0; idx < attempts; idx++) {
    last = [self childPIDsForParent:parentPID];
    if ([last count] >= minimumCount) {
      return last;
    }
    usleep(200000);
  }
  return last;
}

- (NSString *)requestWithServerEnv:(NSString *)envPrefix
                       serverBinary:(NSString *)serverBinary
                          curlBody:(NSString *)curlCommand
                          curlCode:(int *)curlCode
                         serverCode:(int *)serverCode {
  int port = [self randomPort];
  NSString *prefix = ([envPrefix length] > 0) ? [NSString stringWithFormat:@"%@ ", envPrefix] : @"";
  NSString *binary = ([serverBinary length] > 0) ? serverBinary : @"./build/boomhauer";
  NSString *serverCmd = [NSString stringWithFormat:@"%@%@ --port %d --once", prefix, binary, port];

  NSTask *server = [[NSTask alloc] init];
  server.launchPath = @"/bin/bash";
  server.arguments = @[ @"-lc", serverCmd ];
  server.standardOutput = [NSPipe pipe];
  server.standardError = [NSPipe pipe];
  [server launch];

  usleep(250000);
  NSString *formattedCurl = [NSString stringWithFormat:curlCommand, port];
  NSString *body = [self runShellCapture:formattedCurl exitCode:curlCode];

  [server waitUntilExit];
  if (serverCode != NULL) {
    *serverCode = server.terminationStatus;
  }
  return body;
}

- (NSString *)simpleRequestPath:(NSString *)path {
  return [self requestPath:path serverBinary:@"./build/boomhauer" envPrefix:nil];
}

- (NSString *)requestPath:(NSString *)path serverBinary:(NSString *)serverBinary {
  return [self requestPath:path serverBinary:serverBinary envPrefix:nil];
}

- (NSString *)requestPath:(NSString *)path
             serverBinary:(NSString *)serverBinary
                envPrefix:(NSString *)envPrefix {
  int curlCode = 0;
  int serverCode = 0;
  NSString *body =
      [self requestWithServerEnv:envPrefix
                     serverBinary:serverBinary
                        curlBody:[NSString stringWithFormat:@"curl -fsS http://127.0.0.1:%%d%@", path]
                        curlCode:&curlCode
                       serverCode:&serverCode];
  XCTAssertEqual(0, curlCode);
  XCTAssertEqual(0, serverCode);
  return body;
}

- (void)testRootEndpointRendersHTML {
  NSString *body = [self simpleRequestPath:@"/"];
  XCTAssertTrue([body containsString:@"Arlen EOC Dev Server"]);
  XCTAssertTrue([body containsString:@"render pipeline ok"]);
}

- (void)testHealthEndpoint {
  NSString *body = [self simpleRequestPath:@"/healthz"];
  XCTAssertEqualObjects(@"ok\n", body);
}

- (void)testImplicitJSONEndpoint {
  NSString *body = [self simpleRequestPath:@"/api/status"];
  XCTAssertTrue([body containsString:@"\"ok\""]);
  XCTAssertTrue([body containsString:@"\"server\""]);
}

- (void)testPathParamEndpoint {
  NSString *body = [self simpleRequestPath:@"/api/echo/hank"];
  XCTAssertTrue([body containsString:@"\"name\""]);
  XCTAssertTrue([body containsString:@"hank"]);
}

- (void)testStaticAssetEndpointInDevelopment {
  NSString *body = [self simpleRequestPath:@"/static/sample.txt"];
  XCTAssertEqualObjects(@"static ok\n", body);
}

- (void)testHeaderLimitReturns431 {
  int curlCode = 0;
  int serverCode = 0;
  NSString *status =
      [self requestWithServerEnv:@"ARLEN_MAX_HEADER_BYTES=80"
                     serverBinary:@"./build/boomhauer"
                        curlBody:@"big=$(head -c 120 </dev/zero | tr '\\0' 'a'); "
                                 "curl -sS -o /dev/null -w '%%{http_code}' -H \"X-Big: ${big}\" "
                                 "http://127.0.0.1:%d/healthz"
                        curlCode:&curlCode
                       serverCode:&serverCode];
  XCTAssertEqual(0, curlCode);
  XCTAssertEqual(0, serverCode);
  XCTAssertEqualObjects(@"431", [status stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
}

- (void)testBodyLimitReturns413 {
  int curlCode = 0;
  int serverCode = 0;
  NSString *status =
      [self requestWithServerEnv:@"ARLEN_MAX_BODY_BYTES=16"
                     serverBinary:@"./build/boomhauer"
                        curlBody:@"payload=$(head -c 64 </dev/zero | tr '\\0' 'b'); "
                                 "curl -sS -o /dev/null -w '%%{http_code}' -X POST --data \"${payload}\" "
                                 "http://127.0.0.1:%d/healthz"
                        curlCode:&curlCode
                       serverCode:&serverCode];
  XCTAssertEqual(0, curlCode);
  XCTAssertEqual(0, serverCode);
  XCTAssertEqualObjects(@"413", [status stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
}

- (void)testTrustedProxyMetadata {
  int curlCode = 0;
  int serverCode = 0;
  NSString *body =
      [self requestWithServerEnv:@"ARLEN_TRUSTED_PROXY=1"
                     serverBinary:@"./build/boomhauer"
                        curlBody:@"curl -fsS -H 'X-Forwarded-For: 203.0.113.9' "
                                 "-H 'X-Forwarded-Proto: https' "
                                 "http://127.0.0.1:%d/api/request-meta"
                        curlCode:&curlCode
                       serverCode:&serverCode];
  XCTAssertEqual(0, curlCode);
  XCTAssertEqual(0, serverCode);
  XCTAssertTrue([body containsString:@"203.0.113.9"]);
  XCTAssertTrue([body containsString:@"\"scheme\""]);
  XCTAssertTrue([body containsString:@"https"]);
}

- (void)testTechDemoLandingPageRendersLayoutAndContent {
  NSString *body = [self requestPath:@"/tech-demo"
                        serverBinary:@"./build/tech-demo-server"
                           envPrefix:@"ARLEN_APP_ROOT=examples/tech_demo"];
  XCTAssertTrue([body containsString:@"Arlen Technology Demo"]);
  XCTAssertTrue([body containsString:@"Phase 1 capabilities in one page"]);
  XCTAssertTrue([body containsString:@"/tech-demo/dashboard"]);
}

- (void)testTechDemoUserRouteShowsParams {
  NSString *body = [self requestPath:@"/tech-demo/users/peggy?flag=admin"
                        serverBinary:@"./build/tech-demo-server"
                           envPrefix:@"ARLEN_APP_ROOT=examples/tech_demo"];
  XCTAssertTrue([body containsString:@"User from path param"]);
  XCTAssertTrue([body containsString:@"peggy"]);
  XCTAssertTrue([body containsString:@"admin"]);
}

- (void)testTechDemoImplicitJSONArray {
  NSString *body = [self requestPath:@"/tech-demo/api/catalog"
                        serverBinary:@"./build/tech-demo-server"
                           envPrefix:@"ARLEN_APP_ROOT=examples/tech_demo"];
  XCTAssertTrue([body containsString:@"widget-100"]);
  XCTAssertTrue([body containsString:@"Foundation Widget"]);
}

- (void)testTechDemoImplicitJSONDictionary {
  NSString *body = [self requestPath:@"/tech-demo/api/summary?view=full"
                        serverBinary:@"./build/tech-demo-server"
                           envPrefix:@"ARLEN_APP_ROOT=examples/tech_demo"];
  XCTAssertTrue([body containsString:@"\"framework\""]);
  XCTAssertTrue([body containsString:@"Arlen"]);
  XCTAssertTrue([body containsString:@"\"query\""]);
}

- (void)testPropaneServesRequestsAndHandlesReloadSignal {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [repoRoot stringByAppendingPathComponent:@"examples/tech_demo"];
  int port = [self randomPort];
  NSString *pidFile =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"arlen-propane-%d.pid", port]];

  NSTask *server = [[NSTask alloc] init];
  server.launchPath = [repoRoot stringByAppendingPathComponent:@"bin/propane"];
  server.currentDirectoryPath = repoRoot;
  server.arguments = @[
    @"--workers",
    @"2",
    @"--host",
    @"127.0.0.1",
    @"--port",
    [NSString stringWithFormat:@"%d", port],
    @"--env",
    @"development",
    @"--pid-file",
    pidFile
  ];
  NSMutableDictionary *env =
      [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
  env[@"ARLEN_FRAMEWORK_ROOT"] = repoRoot;
  env[@"ARLEN_APP_ROOT"] = appRoot;
  server.environment = env;

  [server launch];

  @try {
    BOOL firstOK = NO;
    NSString *firstBody = [self requestPathWithRetries:@"/healthz"
                                                  port:port
                                              attempts:60
                                               success:&firstOK];
    XCTAssertTrue(firstOK);
    XCTAssertEqualObjects(@"ok\n", firstBody);

    XCTAssertEqual(0, kill(server.processIdentifier, SIGHUP));

    BOOL secondOK = NO;
    NSString *secondBody = [self requestPathWithRetries:@"/healthz"
                                                   port:port
                                               attempts:60
                                                success:&secondOK];
    XCTAssertTrue(secondOK);
    XCTAssertEqualObjects(@"ok\n", secondBody);

    XCTAssertEqual(0, kill(server.processIdentifier, SIGTERM));
    [server waitUntilExit];
    XCTAssertEqual(0, server.terminationStatus);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:pidFile]);
  } @finally {
    if ([server isRunning]) {
      (void)kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    [[NSFileManager defaultManager] removeItemAtPath:pidFile error:nil];
  }
}

- (void)testPropaneRespawnsWorkerAfterCrash {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [repoRoot stringByAppendingPathComponent:@"examples/tech_demo"];
  int port = [self randomPort];
  NSString *pidFile =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"arlen-propane-respawn-%d.pid", port]];

  NSTask *server = [[NSTask alloc] init];
  server.launchPath = [repoRoot stringByAppendingPathComponent:@"bin/propane"];
  server.currentDirectoryPath = repoRoot;
  server.arguments = @[
    @"--workers",
    @"2",
    @"--host",
    @"127.0.0.1",
    @"--port",
    [NSString stringWithFormat:@"%d", port],
    @"--env",
    @"development",
    @"--pid-file",
    pidFile
  ];
  NSMutableDictionary *env =
      [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
  env[@"ARLEN_FRAMEWORK_ROOT"] = repoRoot;
  env[@"ARLEN_APP_ROOT"] = appRoot;
  server.environment = env;

  [server launch];

  @try {
    BOOL firstOK = NO;
    NSString *firstBody = [self requestPathWithRetries:@"/healthz"
                                                  port:port
                                              attempts:60
                                               success:&firstOK];
    XCTAssertTrue(firstOK);
    XCTAssertEqualObjects(@"ok\n", firstBody);

    NSArray *initialWorkers =
        [self waitForChildPIDsForParent:server.processIdentifier minimumCount:2 attempts:60];
    XCTAssertGreaterThanOrEqual([initialWorkers count], 2u);
    pid_t killedPID = (pid_t)[initialWorkers[0] intValue];
    XCTAssertEqual(0, kill(killedPID, SIGKILL));

    BOOL respawned = NO;
    for (NSInteger attempt = 0; attempt < 80; attempt++) {
      NSArray *workers = [self childPIDsForParent:server.processIdentifier];
      BOOL killedStillPresent = NO;
      for (NSNumber *candidate in workers) {
        if ([candidate intValue] == (int)killedPID) {
          killedStillPresent = YES;
          break;
        }
      }
      if ([workers count] >= 2 && !killedStillPresent) {
        respawned = YES;
        break;
      }
      usleep(200000);
    }
    XCTAssertTrue(respawned);

    BOOL secondOK = NO;
    NSString *secondBody = [self requestPathWithRetries:@"/healthz"
                                                   port:port
                                               attempts:60
                                                success:&secondOK];
    XCTAssertTrue(secondOK);
    XCTAssertEqualObjects(@"ok\n", secondBody);

    XCTAssertEqual(0, kill(server.processIdentifier, SIGTERM));
    [server waitUntilExit];
    XCTAssertEqual(0, server.terminationStatus);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:pidFile]);
  } @finally {
    if ([server isRunning]) {
      (void)kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    [[NSFileManager defaultManager] removeItemAtPath:pidFile error:nil];
  }
}

- (void)testTechDemoStaticAssetFromExampleTree {
  NSString *body = [self requestPath:@"/static/tech_demo.css"
                        serverBinary:@"./build/tech-demo-server"
                           envPrefix:@"ARLEN_APP_ROOT=examples/tech_demo"];
  XCTAssertTrue([body containsString:@":root"]);
  XCTAssertTrue([body containsString:@"--bg"]);
}

@end
