#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <signal.h>
#import <unistd.h>
#import <stdlib.h>
#import <string.h>

@interface HTTPIntegrationTests : XCTestCase
@end

@implementation HTTPIntegrationTests

- (int)randomPort {
  return 32000 + (int)arc4random_uniform(2000);
}

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  NSString *templatePath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%@-XXXXXX", prefix ?: @"arlen"]];
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
  NSString *output = [[NSString alloc] initWithData:stdoutData
                                           encoding:NSUTF8StringEncoding];
  return output ?: @"";
}

- (NSString *)runPythonScript:(NSString *)script exitCode:(int *)exitCode {
  NSString *command = [NSString stringWithFormat:@"python3 - <<'PY'\n%@\nPY", script ?: @""];
  return [self runShellCapture:command exitCode:exitCode];
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

- (NSArray *)childProcessInfoForParent:(pid_t)parentPID {
  int exitCode = 0;
  NSString *command =
      [NSString stringWithFormat:@"ps -o pid= -o args= --ppid %d 2>/dev/null", (int)parentPID];
  NSString *output = [self runShellCapture:command exitCode:&exitCode];
  if (exitCode != 0 || [output length] == 0) {
    return @[];
  }

  NSMutableArray *info = [NSMutableArray array];
  NSArray *lines = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *line in lines) {
    NSString *trimmed =
        [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0) {
      continue;
    }

    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    NSInteger pid = 0;
    if (![scanner scanInteger:&pid] || pid <= 0) {
      continue;
    }
    NSString *args = @"";
    if ([scanner scanLocation] < [trimmed length]) {
      args = [[trimmed substringFromIndex:[scanner scanLocation]]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    [info addObject:@{
      @"pid" : @(pid),
      @"args" : args ?: @"",
    }];
  }
  return info;
}

- (pid_t)waitForChildPIDForParent:(pid_t)parentPID
                  containingToken:(NSString *)token
                         excluding:(pid_t)excludedPID
                         attempts:(NSInteger)attempts {
  NSString *needle = token ?: @"";
  for (NSInteger idx = 0; idx < attempts; idx++) {
    NSArray *info = [self childProcessInfoForParent:parentPID];
    for (NSDictionary *entry in info) {
      pid_t pid = (pid_t)[entry[@"pid"] intValue];
      NSString *args = [entry[@"args"] isKindOfClass:[NSString class]] ? entry[@"args"] : @"";
      if (pid > 0 && pid != excludedPID && [args containsString:needle]) {
        return pid;
      }
    }
    usleep(200000);
  }
  return (pid_t)0;
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
  NSString *body = @"";
  int localCurlCode = 1;
  for (NSInteger attempt = 0; attempt < 20; attempt++) {
    body = [self runShellCapture:formattedCurl exitCode:&localCurlCode];
    if (localCurlCode == 0) {
      break;
    }
    usleep(200000);
  }
  if (curlCode != NULL) {
    *curlCode = localCurlCode;
  }

  if (localCurlCode != 0 && [server isRunning]) {
    [server terminate];
  }
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

- (void)testReadinessAndLivenessEndpoints {
  NSString *ready = [self simpleRequestPath:@"/readyz"];
  NSString *live = [self simpleRequestPath:@"/livez"];
  XCTAssertEqualObjects(@"ready\n", ready);
  XCTAssertEqualObjects(@"live\n", live);
}

- (void)testClusterStatusEndpointAndHeaders {
  NSString *clusterEnv =
      @"ARLEN_CLUSTER_ENABLED=1 "
       "ARLEN_CLUSTER_NAME=alpha "
       "ARLEN_CLUSTER_NODE_ID=node-a "
       "ARLEN_CLUSTER_EXPECTED_NODES=3";

  int curlCode = 0;
  int serverCode = 0;
  NSString *body =
      [self requestWithServerEnv:clusterEnv
                     serverBinary:@"./build/boomhauer"
                        curlBody:@"curl -fsS http://127.0.0.1:%d/clusterz"
                        curlCode:&curlCode
                       serverCode:&serverCode];
  XCTAssertEqual(0, curlCode);
  XCTAssertEqual(0, serverCode);
  XCTAssertTrue([body containsString:@"\"ok\":true"] || [body containsString:@"\"ok\": true"]);
  XCTAssertTrue([body containsString:@"\"enabled\":true"] || [body containsString:@"\"enabled\": true"]);
  XCTAssertTrue([body containsString:@"\"name\":\"alpha\""] ||
                [body containsString:@"\"name\": \"alpha\""]);
  XCTAssertTrue([body containsString:@"\"node_id\":\"node-a\""] ||
                [body containsString:@"\"node_id\": \"node-a\""]);
  XCTAssertTrue([body containsString:@"\"expected_nodes\":3"] ||
                [body containsString:@"\"expected_nodes\": 3"]);
  XCTAssertTrue([body containsString:@"\"cluster_broadcast\":\"external_broker_required\""] ||
                [body containsString:@"\"cluster_broadcast\": \"external_broker_required\""]);

  NSString *headers =
      [self requestWithServerEnv:clusterEnv
                     serverBinary:@"./build/boomhauer"
                        curlBody:@"curl -sS -D - -o /dev/null http://127.0.0.1:%d/healthz"
                        curlCode:&curlCode
                       serverCode:&serverCode];
  XCTAssertEqual(0, curlCode);
  XCTAssertEqual(0, serverCode);
  XCTAssertTrue([headers containsString:@"X-Arlen-Cluster: alpha"]);
  XCTAssertTrue([headers containsString:@"X-Arlen-Node: node-a"]);
  XCTAssertTrue([headers containsString:@"X-Arlen-Worker-Pid:"]);
}

- (void)testClusterHeadersCanBeDisabled {
  int curlCode = 0;
  int serverCode = 0;
  NSString *headers =
      [self requestWithServerEnv:@"ARLEN_CLUSTER_EMIT_HEADERS=0 ARLEN_CLUSTER_NAME=alpha ARLEN_CLUSTER_NODE_ID=node-a"
                     serverBinary:@"./build/boomhauer"
                        curlBody:@"curl -sS -D - -o /dev/null http://127.0.0.1:%d/healthz"
                        curlCode:&curlCode
                       serverCode:&serverCode];
  XCTAssertEqual(0, curlCode);
  XCTAssertEqual(0, serverCode);
  XCTAssertFalse([headers containsString:@"X-Arlen-Cluster:"]);
  XCTAssertFalse([headers containsString:@"X-Arlen-Node:"]);
  XCTAssertFalse([headers containsString:@"X-Arlen-Worker-Pid:"]);
}

- (void)testPerformanceHeadersPresentByDefault {
  int curlCode = 0;
  int serverCode = 0;
  NSString *headers =
      [self requestWithServerEnv:nil
                     serverBinary:@"./build/boomhauer"
                        curlBody:@"curl -sS -D - -o /dev/null http://127.0.0.1:%d/healthz"
                        curlCode:&curlCode
                       serverCode:&serverCode];
  XCTAssertEqual(0, curlCode);
  XCTAssertEqual(0, serverCode);
  XCTAssertTrue([headers containsString:@"X-Arlen-Total-Ms:"]);
  XCTAssertTrue([headers containsString:@"X-Arlen-Parse-Ms:"]);
  XCTAssertTrue([headers containsString:@"X-Arlen-Response-Write-Ms:"]);
}

- (void)testPerformanceHeadersCanBeDisabled {
  int curlCode = 0;
  int serverCode = 0;
  NSString *headers =
      [self requestWithServerEnv:@"ARLEN_PERFORMANCE_LOGGING=0"
                     serverBinary:@"./build/boomhauer"
                        curlBody:@"curl -sS -D - -o /dev/null http://127.0.0.1:%d/healthz"
                        curlCode:&curlCode
                       serverCode:&serverCode];
  XCTAssertEqual(0, curlCode);
  XCTAssertEqual(0, serverCode);
  XCTAssertFalse([headers containsString:@"X-Arlen-Total-Ms:"]);
  XCTAssertFalse([headers containsString:@"X-Arlen-Parse-Ms:"]);
  XCTAssertFalse([headers containsString:@"X-Arlen-Response-Write-Ms:"]);
}

- (void)testImplicitJSONEndpoint {
  NSString *body = [self simpleRequestPath:@"/api/status"];
  XCTAssertTrue([body containsString:@"\"ok\""]);
  XCTAssertTrue([body containsString:@"\"server\""]);
}

- (void)testOpenAPIInteractiveDocsFlowAndRepresentativeAPIRoute {
  int port = [self randomPort];
  NSTask *server = [[NSTask alloc] init];
  server.launchPath = @"./build/boomhauer";
  server.arguments = @[ @"--port", [NSString stringWithFormat:@"%d", port] ];
  server.standardOutput = [NSPipe pipe];
  server.standardError = [NSPipe pipe];
  [server launch];

  @try {
    BOOL docsOK = NO;
    NSString *docsBody = [self requestPathWithRetries:@"/openapi"
                                                 port:port
                                             attempts:60
                                              success:&docsOK];
    XCTAssertTrue(docsOK);
    XCTAssertTrue([docsBody containsString:@"Arlen OpenAPI Explorer"]);
    XCTAssertTrue([docsBody containsString:@"Try It Out"]);
    XCTAssertTrue([docsBody containsString:@"fetch('/openapi.json')"]);

    BOOL specOK = NO;
    NSString *specBody = [self requestPathWithRetries:@"/openapi.json"
                                                 port:port
                                             attempts:60
                                              success:&specOK];
    XCTAssertTrue(specOK);
    XCTAssertTrue([specBody containsString:@"\"/api/status\""]);

    BOOL routeOK = NO;
    NSString *apiBody = [self requestPathWithRetries:@"/api/status"
                                                port:port
                                            attempts:60
                                             success:&routeOK];
    XCTAssertTrue(routeOK);
    XCTAssertTrue([apiBody containsString:@"\"ok\""]);

    BOOL viewerOK = NO;
    NSString *viewerBody = [self requestPathWithRetries:@"/openapi/viewer"
                                                   port:port
                                               attempts:60
                                                success:&viewerOK];
    XCTAssertTrue(viewerOK);
    XCTAssertTrue([viewerBody containsString:@"Arlen OpenAPI Viewer"]);
  } @finally {
    if ([server isRunning]) {
      (void)kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
  }
}

- (void)testOpenAPISwaggerDocsStyleAndDedicatedRoute {
  int port = [self randomPort];
  NSTask *server = [[NSTask alloc] init];
  server.launchPath = @"/bin/bash";
  server.arguments = @[
    @"-lc",
    [NSString stringWithFormat:@"ARLEN_OPENAPI_DOCS_UI_STYLE=swagger ./build/boomhauer --port %d", port]
  ];
  server.standardOutput = [NSPipe pipe];
  server.standardError = [NSPipe pipe];
  [server launch];

  @try {
    BOOL docsOK = NO;
    NSString *docsBody = [self requestPathWithRetries:@"/openapi"
                                                 port:port
                                             attempts:60
                                              success:&docsOK];
    XCTAssertTrue(docsOK);
    XCTAssertTrue([docsBody containsString:@"Arlen Swagger UI"]);
    XCTAssertTrue([docsBody containsString:@"Try It Out"]);
    XCTAssertTrue([docsBody containsString:@"fetch('/openapi.json')"]);

    BOOL swaggerOK = NO;
    NSString *swaggerBody = [self requestPathWithRetries:@"/openapi/swagger"
                                                    port:port
                                                attempts:60
                                                 success:&swaggerOK];
    XCTAssertTrue(swaggerOK);
    XCTAssertTrue([swaggerBody containsString:@"Arlen Swagger UI"]);
  } @finally {
    if ([server isRunning]) {
      (void)kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
  }
}

- (void)testPathParamEndpoint {
  NSString *body = [self simpleRequestPath:@"/api/echo/hank"];
  XCTAssertTrue([body containsString:@"\"name\""]);
  XCTAssertTrue([body containsString:@"hank"]);
}

- (void)testPhase3EServiceRoutesCacheAndI18n {
  NSString *cacheBody = [self simpleRequestPath:@"/services/cache?value=ok"];
  XCTAssertTrue([cacheBody containsString:@"\"ok\""]);
  XCTAssertTrue([cacheBody containsString:@"\"adapter\""]);
  XCTAssertTrue([cacheBody containsString:@"\"value\":\"ok\""] ||
                [cacheBody containsString:@"\"value\": \"ok\""]);

  NSString *i18nBody = [self simpleRequestPath:@"/services/i18n?locale=es"];
  XCTAssertTrue([i18nBody containsString:@"\"ok\""]);
  XCTAssertTrue([i18nBody containsString:@"Hola Arlen"]);
}

- (void)testPhase3EServiceRoutesJobsMailAndAttachment {
  NSString *jobsBody = [self simpleRequestPath:@"/services/jobs"];
  XCTAssertTrue([jobsBody containsString:@"\"enqueuedJobID\""]);
  XCTAssertTrue([jobsBody containsString:@"\"dequeuedJobID\""]);

  NSString *mailBody = [self simpleRequestPath:@"/services/mail"];
  XCTAssertTrue([mailBody containsString:@"\"deliveryID\""]);
  XCTAssertTrue([mailBody containsString:@"\"deliveries\""]);

  NSString *attachmentBody = [self simpleRequestPath:@"/services/attachments?content=phase3e"];
  XCTAssertTrue([attachmentBody containsString:@"\"attachmentID\""]);
  XCTAssertTrue([attachmentBody containsString:@"\"content\":\"phase3e\""] ||
                [attachmentBody containsString:@"\"content\": \"phase3e\""]);
}

- (void)testWebSocketEchoRouteRoundTrip {
  int port = [self randomPort];
  NSTask *server = [[NSTask alloc] init];
  server.launchPath = @"./build/boomhauer";
  server.arguments = @[ @"--port", [NSString stringWithFormat:@"%d", port] ];
  server.standardOutput = [NSPipe pipe];
  server.standardError = [NSPipe pipe];
  [server launch];

  @try {
    BOOL ready = NO;
    (void)[self requestPathWithRetries:@"/healthz" port:port attempts:60 success:&ready];
    XCTAssertTrue(ready);

    NSString *script = [NSString stringWithFormat:
                                         @"import base64, os, socket, struct\n"
                                         @"PORT=%d\n"
                                         @"def recv_exact(sock, size):\n"
                                         @"    data=b''\n"
                                         @"    while len(data)<size:\n"
                                         @"        chunk=sock.recv(size-len(data))\n"
                                         @"        if not chunk:\n"
                                         @"            raise RuntimeError('connection closed')\n"
                                         @"        data += chunk\n"
                                         @"    return data\n"
                                         @"def send_text(sock, text):\n"
                                         @"    payload=text.encode('utf-8')\n"
                                         @"    mask=os.urandom(4)\n"
                                         @"    header=bytearray([0x81])\n"
                                         @"    length=len(payload)\n"
                                         @"    if length <= 125:\n"
                                         @"        header.append(0x80 | length)\n"
                                         @"    elif length <= 65535:\n"
                                         @"        header.append(0x80 | 126)\n"
                                         @"        header.extend(struct.pack('!H', length))\n"
                                         @"    else:\n"
                                         @"        header.append(0x80 | 127)\n"
                                         @"        header.extend(struct.pack('!Q', length))\n"
                                         @"    masked=bytes(payload[i] ^ mask[i %% 4] for i in range(length))\n"
                                         @"    sock.sendall(bytes(header)+mask+masked)\n"
                                         @"def recv_text(sock):\n"
                                         @"    b1, b2 = recv_exact(sock, 2)\n"
                                         @"    opcode = b1 & 0x0F\n"
                                         @"    length = b2 & 0x7F\n"
                                         @"    masked = (b2 & 0x80) != 0\n"
                                         @"    if length == 126:\n"
                                         @"        length = struct.unpack('!H', recv_exact(sock, 2))[0]\n"
                                         @"    elif length == 127:\n"
                                         @"        length = struct.unpack('!Q', recv_exact(sock, 8))[0]\n"
                                         @"    mask_key = recv_exact(sock, 4) if masked else b''\n"
                                         @"    payload = recv_exact(sock, length)\n"
                                         @"    if masked:\n"
                                         @"        payload = bytes(payload[i] ^ mask_key[i %% 4] for i in range(length))\n"
                                         @"    if opcode != 0x1:\n"
                                         @"        raise RuntimeError('unexpected opcode %%d' %% opcode)\n"
                                         @"    return payload.decode('utf-8')\n"
                                         @"key = base64.b64encode(os.urandom(16)).decode('ascii')\n"
                                         @"req = (\n"
                                         @"    f'GET /ws/echo HTTP/1.1\\r\\n'\n"
                                         @"    f'Host: 127.0.0.1:{PORT}\\r\\n'\n"
                                         @"    'Upgrade: websocket\\r\\n'\n"
                                         @"    'Connection: Upgrade\\r\\n'\n"
                                         @"    f'Sec-WebSocket-Key: {key}\\r\\n'\n"
                                         @"    'Sec-WebSocket-Version: 13\\r\\n\\r\\n'\n"
                                         @").encode('utf-8')\n"
                                         @"sock = socket.create_connection(('127.0.0.1', PORT), timeout=5)\n"
                                         @"sock.sendall(req)\n"
                                         @"resp = sock.recv(4096).decode('utf-8', 'replace')\n"
                                         @"if '101 Switching Protocols' not in resp:\n"
                                         @"    raise RuntimeError(resp)\n"
                                         @"send_text(sock, 'hello-ws')\n"
                                         @"print(recv_text(sock))\n"
                                         @"sock.close()\n",
                                         port];
    int pyCode = 0;
    NSString *output = [self runPythonScript:script exitCode:&pyCode];
    XCTAssertEqual(0, pyCode);
    NSString *trimmed =
        [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    XCTAssertEqualObjects(@"hello-ws", trimmed);
  } @finally {
    if ([server isRunning]) {
      (void)kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
  }
}

- (void)testWebSocketChannelPubSubFanout {
  int port = [self randomPort];
  NSTask *server = [[NSTask alloc] init];
  server.launchPath = @"./build/boomhauer";
  server.arguments = @[ @"--port", [NSString stringWithFormat:@"%d", port] ];
  server.standardOutput = [NSPipe pipe];
  server.standardError = [NSPipe pipe];
  [server launch];

  @try {
    BOOL ready = NO;
    (void)[self requestPathWithRetries:@"/healthz" port:port attempts:60 success:&ready];
    XCTAssertTrue(ready);

    NSString *script = [NSString stringWithFormat:
                                         @"import base64, os, socket, struct\n"
                                         @"PORT=%d\n"
                                         @"def recv_exact(sock, size):\n"
                                         @"    data=b''\n"
                                         @"    while len(data)<size:\n"
                                         @"        chunk=sock.recv(size-len(data))\n"
                                         @"        if not chunk:\n"
                                         @"            raise RuntimeError('connection closed')\n"
                                         @"        data += chunk\n"
                                         @"    return data\n"
                                         @"def send_text(sock, text):\n"
                                         @"    payload=text.encode('utf-8')\n"
                                         @"    mask=os.urandom(4)\n"
                                         @"    header=bytearray([0x81])\n"
                                         @"    length=len(payload)\n"
                                         @"    if length <= 125:\n"
                                         @"        header.append(0x80 | length)\n"
                                         @"    elif length <= 65535:\n"
                                         @"        header.append(0x80 | 126)\n"
                                         @"        header.extend(struct.pack('!H', length))\n"
                                         @"    else:\n"
                                         @"        header.append(0x80 | 127)\n"
                                         @"        header.extend(struct.pack('!Q', length))\n"
                                         @"    masked=bytes(payload[i] ^ mask[i %% 4] for i in range(length))\n"
                                         @"    sock.sendall(bytes(header)+mask+masked)\n"
                                         @"def recv_text(sock):\n"
                                         @"    b1, b2 = recv_exact(sock, 2)\n"
                                         @"    opcode = b1 & 0x0F\n"
                                         @"    length = b2 & 0x7F\n"
                                         @"    masked = (b2 & 0x80) != 0\n"
                                         @"    if length == 126:\n"
                                         @"        length = struct.unpack('!H', recv_exact(sock, 2))[0]\n"
                                         @"    elif length == 127:\n"
                                         @"        length = struct.unpack('!Q', recv_exact(sock, 8))[0]\n"
                                         @"    mask_key = recv_exact(sock, 4) if masked else b''\n"
                                         @"    payload = recv_exact(sock, length)\n"
                                         @"    if masked:\n"
                                         @"        payload = bytes(payload[i] ^ mask_key[i %% 4] for i in range(length))\n"
                                         @"    if opcode != 0x1:\n"
                                         @"        raise RuntimeError('unexpected opcode %%d' %% opcode)\n"
                                         @"    return payload.decode('utf-8')\n"
                                         @"def ws_connect(path):\n"
                                         @"    key = base64.b64encode(os.urandom(16)).decode('ascii')\n"
                                         @"    req = (\n"
                                         @"      f'GET {path} HTTP/1.1\\r\\n'\n"
                                         @"      f'Host: 127.0.0.1:{PORT}\\r\\n'\n"
                                         @"      'Upgrade: websocket\\r\\n'\n"
                                         @"      'Connection: Upgrade\\r\\n'\n"
                                         @"      f'Sec-WebSocket-Key: {key}\\r\\n'\n"
                                         @"      'Sec-WebSocket-Version: 13\\r\\n\\r\\n'\n"
                                         @"    ).encode('utf-8')\n"
                                         @"    sock = socket.create_connection(('127.0.0.1', PORT), timeout=5)\n"
                                         @"    sock.sendall(req)\n"
                                         @"    resp = sock.recv(4096).decode('utf-8', 'replace')\n"
                                         @"    if '101 Switching Protocols' not in resp:\n"
                                         @"      raise RuntimeError(resp)\n"
                                         @"    return sock\n"
                                         @"ws1 = ws_connect('/ws/channel/alpha')\n"
                                         @"ws2 = ws_connect('/ws/channel/alpha')\n"
                                         @"send_text(ws1, 'fanout-message')\n"
                                         @"m1 = recv_text(ws1)\n"
                                         @"m2 = recv_text(ws2)\n"
                                         @"print(m1)\n"
                                         @"print(m2)\n"
                                         @"ws1.close(); ws2.close()\n",
                                         port];
    int pyCode = 0;
    NSString *output = [self runPythonScript:script exitCode:&pyCode];
    XCTAssertEqual(0, pyCode);
    NSArray *lines =
        [[output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    XCTAssertGreaterThanOrEqual([lines count], 2u);
    XCTAssertEqualObjects(@"fanout-message", lines[0]);
    XCTAssertEqualObjects(@"fanout-message", lines[1]);
  } @finally {
    if ([server isRunning]) {
      (void)kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
  }
}

- (void)testWebSocketFrameLengthBoundariesAndMalformedFrames {
  int port = [self randomPort];
  NSTask *server = [[NSTask alloc] init];
  server.launchPath = @"./build/boomhauer";
  server.arguments = @[ @"--port", [NSString stringWithFormat:@"%d", port] ];
  server.standardOutput = [NSPipe pipe];
  server.standardError = [NSPipe pipe];
  [server launch];

  @try {
    BOOL ready = NO;
    (void)[self requestPathWithRetries:@"/healthz" port:port attempts:60 success:&ready];
    XCTAssertTrue(ready);

    NSString *script = [NSString stringWithFormat:
                                         @"import base64, os, socket, struct\n"
                                         @"PORT=%d\n"
                                         @"MAX_PAYLOAD=1048576\n"
                                         @"def recv_exact(sock, size):\n"
                                         @"    data=b''\n"
                                         @"    while len(data)<size:\n"
                                         @"        chunk=sock.recv(size-len(data))\n"
                                         @"        if not chunk:\n"
                                         @"            raise RuntimeError('connection closed')\n"
                                         @"        data += chunk\n"
                                         @"    return data\n"
                                         @"def ws_connect(path):\n"
                                         @"    key = base64.b64encode(os.urandom(16)).decode('ascii')\n"
                                         @"    req = (\n"
                                         @"      f'GET {path} HTTP/1.1\\r\\n'\n"
                                         @"      f'Host: 127.0.0.1:{PORT}\\r\\n'\n"
                                         @"      'Upgrade: websocket\\r\\n'\n"
                                         @"      'Connection: Upgrade\\r\\n'\n"
                                         @"      f'Sec-WebSocket-Key: {key}\\r\\n'\n"
                                         @"      'Sec-WebSocket-Version: 13\\r\\n\\r\\n'\n"
                                         @"    ).encode('utf-8')\n"
                                         @"    sock = socket.create_connection(('127.0.0.1', PORT), timeout=4)\n"
                                         @"    sock.settimeout(4)\n"
                                         @"    sock.sendall(req)\n"
                                         @"    response = b''\n"
                                         @"    while b'\\r\\n\\r\\n' not in response:\n"
                                         @"      chunk = sock.recv(4096)\n"
                                         @"      if not chunk:\n"
                                         @"        break\n"
                                         @"      response += chunk\n"
                                         @"      if len(response) > 65536:\n"
                                         @"        break\n"
                                         @"    if b'101 Switching Protocols' not in response:\n"
                                         @"      raise RuntimeError(response.decode('utf-8', 'replace'))\n"
                                         @"    return sock\n"
                                         @"def send_text(sock, text):\n"
                                         @"    payload=text.encode('utf-8')\n"
                                         @"    mask=os.urandom(4)\n"
                                         @"    header=bytearray([0x81])\n"
                                         @"    length=len(payload)\n"
                                         @"    if length <= 125:\n"
                                         @"      header.append(0x80 | length)\n"
                                         @"    elif length <= 65535:\n"
                                         @"      header.append(0x80 | 126)\n"
                                         @"      header.extend(struct.pack('!H', length))\n"
                                         @"    else:\n"
                                         @"      header.append(0x80 | 127)\n"
                                         @"      header.extend(struct.pack('!Q', length))\n"
                                         @"    masked=bytes(payload[i] ^ mask[i %% 4] for i in range(length))\n"
                                         @"    sock.sendall(bytes(header)+mask+masked)\n"
                                         @"def recv_text(sock):\n"
                                         @"    b1, b2 = recv_exact(sock, 2)\n"
                                         @"    opcode = b1 & 0x0F\n"
                                         @"    length = b2 & 0x7F\n"
                                         @"    masked = (b2 & 0x80) != 0\n"
                                         @"    if length == 126:\n"
                                         @"      length = struct.unpack('!H', recv_exact(sock, 2))[0]\n"
                                         @"    elif length == 127:\n"
                                         @"      length = struct.unpack('!Q', recv_exact(sock, 8))[0]\n"
                                         @"    mask_key = recv_exact(sock, 4) if masked else b''\n"
                                         @"    payload = recv_exact(sock, length)\n"
                                         @"    if masked:\n"
                                         @"      payload = bytes(payload[i] ^ mask_key[i %% 4] for i in range(length))\n"
                                         @"    if opcode != 0x1:\n"
                                         @"      raise RuntimeError('unexpected opcode %%d' %% opcode)\n"
                                         @"    return payload.decode('utf-8')\n"
                                         @"def expect_closed(sock, label):\n"
                                         @"    sock.settimeout(2)\n"
                                         @"    try:\n"
                                         @"      data = sock.recv(64)\n"
                                         @"    except ConnectionResetError:\n"
                                         @"      print(f'{label}-closed')\n"
                                         @"      return\n"
                                         @"    except BrokenPipeError:\n"
                                         @"      print(f'{label}-closed')\n"
                                         @"      return\n"
                                         @"    except socket.timeout:\n"
                                         @"      raise RuntimeError(f'{label}-timeout')\n"
                                         @"    if data == b'':\n"
                                         @"      print(f'{label}-closed')\n"
                                         @"      return\n"
                                         @"    opcode = data[0] & 0x0F\n"
                                         @"    if opcode == 0x8:\n"
                                         @"      print(f'{label}-closed')\n"
                                         @"      return\n"
                                         @"    raise RuntimeError(f'{label}-unexpected-data')\n"
                                         @"for size in (125, 126, 65535, 65536):\n"
                                         @"    sock = ws_connect('/ws/echo')\n"
                                         @"    payload = 'x' * size\n"
                                         @"    send_text(sock, payload)\n"
                                         @"    echoed = recv_text(sock)\n"
                                         @"    if echoed != payload:\n"
                                         @"      raise RuntimeError(f'echo-mismatch-{size}')\n"
                                         @"    print(f'length-{size}-ok')\n"
                                         @"    sock.close()\n"
                                         @"oversized = ws_connect('/ws/echo')\n"
                                         @"oversized_header = bytearray([0x81, 0x80 | 127])\n"
                                         @"oversized_header.extend(struct.pack('!Q', MAX_PAYLOAD + 1))\n"
                                         @"oversized.sendall(bytes(oversized_header))\n"
                                         @"expect_closed(oversized, 'oversized')\n"
                                         @"oversized.close()\n"
                                         @"truncated = ws_connect('/ws/echo')\n"
                                         @"declared = 4096\n"
                                         @"partial = b'partial-payload'\n"
                                         @"mask = os.urandom(4)\n"
                                         @"frame = bytearray([0x81, 0x80 | 126])\n"
                                         @"frame.extend(struct.pack('!H', declared))\n"
                                         @"frame.extend(mask)\n"
                                         @"masked = bytes(partial[i] ^ mask[i %% 4] for i in range(len(partial)))\n"
                                         @"truncated.sendall(bytes(frame) + masked)\n"
                                         @"truncated.shutdown(socket.SHUT_WR)\n"
                                         @"expect_closed(truncated, 'truncated')\n"
                                         @"truncated.close()\n",
                                         port];

    int pyCode = 0;
    NSString *output = [self runPythonScript:script exitCode:&pyCode];
    XCTAssertEqual(0, pyCode);
    XCTAssertTrue([output containsString:@"length-125-ok"]);
    XCTAssertTrue([output containsString:@"length-126-ok"]);
    XCTAssertTrue([output containsString:@"length-65535-ok"]);
    XCTAssertTrue([output containsString:@"length-65536-ok"]);
    XCTAssertTrue([output containsString:@"oversized-closed"]);
    XCTAssertTrue([output containsString:@"truncated-closed"]);

    BOOL stillReady = NO;
    NSString *healthBody = [self requestPathWithRetries:@"/healthz"
                                                   port:port
                                               attempts:20
                                                success:&stillReady];
    XCTAssertTrue(stillReady);
    XCTAssertEqualObjects(@"ok\n", healthBody);
  } @finally {
    if ([server isRunning]) {
      (void)kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
  }
}

- (void)testSSETickerHandlesConcurrentRequests {
  int port = [self randomPort];
  NSTask *server = [[NSTask alloc] init];
  server.launchPath = @"./build/boomhauer";
  server.arguments = @[ @"--port", [NSString stringWithFormat:@"%d", port] ];
  server.standardOutput = [NSPipe pipe];
  server.standardError = [NSPipe pipe];
  [server launch];

  @try {
    BOOL ready = NO;
    (void)[self requestPathWithRetries:@"/healthz" port:port attempts:60 success:&ready];
    XCTAssertTrue(ready);

    NSString *script = [NSString stringWithFormat:
                                         @"import threading, urllib.request\n"
                                         @"PORT=%d\n"
                                         @"errors=[]\n"
                                         @"def worker(idx):\n"
                                         @"    try:\n"
                                         @"        with urllib.request.urlopen(f'http://127.0.0.1:{PORT}/sse/ticker?count=3', timeout=5) as res:\n"
                                         @"            body = res.read().decode('utf-8')\n"
                                         @"            ctype = res.headers.get('Content-Type', '')\n"
                                         @"            if 'text/event-stream' not in ctype:\n"
                                         @"                errors.append(f'bad content type {ctype}')\n"
                                         @"            if body.count('event: tick') < 3:\n"
                                         @"                errors.append(f'bad event count {idx}')\n"
                                         @"    except Exception as exc:\n"
                                         @"        errors.append(str(exc))\n"
                                         @"threads=[]\n"
                                         @"for i in range(6):\n"
                                         @"    t=threading.Thread(target=worker, args=(i,))\n"
                                         @"    t.start(); threads.append(t)\n"
                                         @"for t in threads:\n"
                                         @"    t.join()\n"
                                         @"if errors:\n"
                                         @"    raise RuntimeError('; '.join(errors))\n"
                                         @"print('ok')\n",
                                         port];
    int pyCode = 0;
    NSString *output = [self runPythonScript:script exitCode:&pyCode];
    XCTAssertEqual(0, pyCode);
    XCTAssertTrue([output containsString:@"ok"]);
  } @finally {
    if ([server isRunning]) {
      (void)kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
  }
}

- (void)testMountedApplicationCompositionRoutes {
  NSString *statusBody = [self simpleRequestPath:@"/embedded/status"];
  XCTAssertEqualObjects(@"embedded-ok\n", statusBody);

  NSString *apiBody = [self simpleRequestPath:@"/embedded/api/status"];
  XCTAssertTrue([apiBody containsString:@"\"mounted\""]);
  XCTAssertTrue([apiBody containsString:@"\"embedded-app\""]);
}

- (void)testStaticAssetEndpointInDevelopment {
  NSString *body = [self simpleRequestPath:@"/static/sample.txt"];
  XCTAssertEqualObjects(@"static ok\n", body);
}

- (void)testStaticMountCanonicalIndexRedirects {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *token = [[[NSUUID UUID] UUIDString] lowercaseString];
  NSString *relativeRoot = [NSString stringWithFormat:@"phase3f-static-%@",
                                                      [token stringByReplacingOccurrencesOfString:@"-"
                                                                                       withString:@""]];
  NSString *indexPath = [repoRoot stringByAppendingPathComponent:
                                    [NSString stringWithFormat:@"public/%@/docs/index.html", relativeRoot]];
  NSString *assetRoot = [indexPath stringByDeletingLastPathComponent];
  NSError *setupError = nil;
  BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:assetRoot
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&setupError];
  XCTAssertTrue(created);
  XCTAssertNil(setupError);
  XCTAssertTrue([@"phase3f-index\n" writeToFile:indexPath
                                     atomically:YES
                                       encoding:NSUTF8StringEncoding
                                          error:&setupError]);
  XCTAssertNil(setupError);

  @try {
    int curlCode = 0;
    int serverCode = 0;
    NSString *headersNoSlash = [self requestWithServerEnv:nil
                                              serverBinary:@"./build/boomhauer"
                                                 curlBody:[NSString stringWithFormat:
                                                                     @"curl -sS -D - -o /dev/null "
                                                                      "http://127.0.0.1:%%d/static/%@/docs",
                                                                      relativeRoot]
                                                 curlCode:&curlCode
                                                serverCode:&serverCode];
    XCTAssertEqual(0, curlCode);
    XCTAssertEqual(0, serverCode);
    XCTAssertTrue([headersNoSlash containsString:@" 301 "]);
    NSString *expectedNoSlashLocation =
        [NSString stringWithFormat:@"Location: /static/%@/docs/", relativeRoot];
    XCTAssertTrue([headersNoSlash containsString:expectedNoSlashLocation]);

    NSString *headersIndex = [self requestWithServerEnv:nil
                                            serverBinary:@"./build/boomhauer"
                                               curlBody:[NSString stringWithFormat:
                                                                   @"curl -sS -D - -o /dev/null "
                                                                    "http://127.0.0.1:%%d/static/%@/docs/index.html",
                                                                    relativeRoot]
                                               curlCode:&curlCode
                                              serverCode:&serverCode];
    XCTAssertEqual(0, curlCode);
    XCTAssertEqual(0, serverCode);
    XCTAssertTrue([headersIndex containsString:@" 301 "]);
    NSString *expectedIndexLocation =
        [NSString stringWithFormat:@"Location: /static/%@/docs/", relativeRoot];
    XCTAssertTrue([headersIndex containsString:expectedIndexLocation]);

    NSString *body = [self requestWithServerEnv:nil
                                    serverBinary:@"./build/boomhauer"
                                       curlBody:[NSString stringWithFormat:
                                                           @"curl -fsS http://127.0.0.1:%%d/static/%@/docs/",
                                                           relativeRoot]
                                       curlCode:&curlCode
                                      serverCode:&serverCode];
    XCTAssertEqual(0, curlCode);
    XCTAssertEqual(0, serverCode);
    XCTAssertEqualObjects(@"phase3f-index\n", body);
  } @finally {
    NSString *cleanupPath = [repoRoot stringByAppendingPathComponent:
                                        [NSString stringWithFormat:@"public/%@", relativeRoot]];
    (void)[[NSFileManager defaultManager] removeItemAtPath:cleanupPath error:nil];
  }
}

- (void)testStaticAllowlistBlocksAndAllowsConfiguredExtensions {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *token = [[[NSUUID UUID] UUIDString] lowercaseString];
  NSString *relativeRoot = [NSString stringWithFormat:@"phase3f-static-%@",
                                                      [token stringByReplacingOccurrencesOfString:@"-"
                                                                                       withString:@""]];
  NSString *assetDir = [repoRoot stringByAppendingPathComponent:
                                   [NSString stringWithFormat:@"public/%@", relativeRoot]];
  NSString *blockedPath = [assetDir stringByAppendingPathComponent:@"blocked.exe"];
  NSError *setupError = nil;
  BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:assetDir
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&setupError];
  XCTAssertTrue(created);
  XCTAssertNil(setupError);
  XCTAssertTrue([@"blocked\n" writeToFile:blockedPath
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&setupError]);
  XCTAssertNil(setupError);

  @try {
    int curlCode = 0;
    int serverCode = 0;
    NSString *statusBlocked = [self requestWithServerEnv:nil
                                             serverBinary:@"./build/boomhauer"
                                                curlBody:[NSString stringWithFormat:
                                                                    @"curl -sS -o /dev/null -w '%%{http_code}' "
                                                                     "http://127.0.0.1:%%d/static/%@/blocked.exe",
                                                                     relativeRoot]
                                                curlCode:&curlCode
                                               serverCode:&serverCode];
    XCTAssertEqual(0, curlCode);
    XCTAssertEqual(0, serverCode);
    XCTAssertEqualObjects(@"404",
                          [statusBlocked stringByTrimmingCharactersInSet:
                                               [NSCharacterSet whitespaceAndNewlineCharacterSet]]);

    NSString *statusAllowed = [self requestWithServerEnv:@"ARLEN_STATIC_ALLOW_EXTENSIONS=txt,exe"
                                             serverBinary:@"./build/boomhauer"
                                                curlBody:[NSString stringWithFormat:
                                                                    @"curl -sS -o /dev/null -w '%%{http_code}' "
                                                                     "http://127.0.0.1:%%d/static/%@/blocked.exe",
                                                                     relativeRoot]
                                                curlCode:&curlCode
                                               serverCode:&serverCode];
    XCTAssertEqual(0, curlCode);
    XCTAssertEqual(0, serverCode);
    XCTAssertEqualObjects(@"200",
                          [statusAllowed stringByTrimmingCharactersInSet:
                                              [NSCharacterSet whitespaceAndNewlineCharacterSet]]);

    NSString *body = [self requestWithServerEnv:@"ARLEN_STATIC_ALLOW_EXTENSIONS=txt,exe"
                                    serverBinary:@"./build/boomhauer"
                                       curlBody:[NSString stringWithFormat:
                                                           @"curl -fsS http://127.0.0.1:%%d/static/%@/blocked.exe",
                                                           relativeRoot]
                                       curlCode:&curlCode
                                      serverCode:&serverCode];
    XCTAssertEqual(0, curlCode);
    XCTAssertEqual(0, serverCode);
    XCTAssertEqualObjects(@"blocked\n", body);
  } @finally {
    (void)[[NSFileManager defaultManager] removeItemAtPath:assetDir error:nil];
  }
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

- (void)testContentLengthEdgeCasesRejectMalformedAndRespectLimit {
  int port = [self randomPort];
  NSTask *server = [[NSTask alloc] init];
  server.launchPath = @"/bin/bash";
  server.arguments = @[
    @"-lc",
    [NSString stringWithFormat:@"ARLEN_MAX_BODY_BYTES=16 ./build/boomhauer --port %d", port]
  ];
  server.standardOutput = [NSPipe pipe];
  server.standardError = [NSPipe pipe];
  [server launch];

  @try {
    BOOL ready = NO;
    (void)[self requestPathWithRetries:@"/healthz" port:port attempts:60 success:&ready];
    XCTAssertTrue(ready);

    NSString *script = [NSString stringWithFormat:
                                         @"import socket\n"
                                         @"PORT=%d\n"
                                         @"def read_status_line(request_bytes):\n"
                                         @"    sock = socket.create_connection(('127.0.0.1', PORT), timeout=3)\n"
                                         @"    sock.settimeout(3)\n"
                                         @"    sock.sendall(request_bytes)\n"
                                         @"    response = b''\n"
                                         @"    while b'\\r\\n' not in response:\n"
                                         @"      chunk = sock.recv(4096)\n"
                                         @"      if not chunk:\n"
                                         @"        break\n"
                                         @"      response += chunk\n"
                                         @"      if len(response) > 16384:\n"
                                         @"        break\n"
                                         @"    sock.close()\n"
                                         @"    if b'\\r\\n' not in response:\n"
                                         @"      raise RuntimeError('missing-status-line')\n"
                                         @"    return response.split(b'\\r\\n', 1)[0].decode('ascii', 'replace')\n"
                                         @"exact_limit = read_status_line(\n"
                                         @"    b'GET /healthz HTTP/1.1\\r\\n'\n"
                                         @"    b'Host: 127.0.0.1\\r\\n'\n"
                                         @"    b'Content-Length: 16\\r\\n'\n"
                                         @"    b'\\r\\n'\n"
                                         @"    b'1234567890abcdef'\n"
                                         @")\n"
                                         @"over_limit = read_status_line(\n"
                                         @"    b'GET /healthz HTTP/1.1\\r\\n'\n"
                                         @"    b'Host: 127.0.0.1\\r\\n'\n"
                                         @"    b'Content-Length: 17\\r\\n'\n"
                                         @"    b'\\r\\n'\n"
                                         @"    b'1234567890abcdefg'\n"
                                         @")\n"
                                         @"invalid = read_status_line(\n"
                                         @"    b'GET /healthz HTTP/1.1\\r\\n'\n"
                                         @"    b'Host: 127.0.0.1\\r\\n'\n"
                                         @"    b'Content-Length: abc\\r\\n'\n"
                                         @"    b'\\r\\n'\n"
                                         @")\n"
                                         @"huge = read_status_line(\n"
                                         @"    b'GET /healthz HTTP/1.1\\r\\n'\n"
                                         @"    b'Host: 127.0.0.1\\r\\n'\n"
                                         @"    b'Content-Length: 999999999999999999999999999\\r\\n'\n"
                                         @"    b'\\r\\n'\n"
                                         @")\n"
                                         @"print(exact_limit)\n"
                                         @"print(over_limit)\n"
                                         @"print(invalid)\n"
                                         @"print(huge)\n",
                                         port];

    int pyCode = 0;
    NSString *output = [self runPythonScript:script exitCode:&pyCode];
    XCTAssertEqual(0, pyCode);
    NSArray *lines =
        [[output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    XCTAssertGreaterThanOrEqual([lines count], 4u);
    XCTAssertTrue([lines[0] containsString:@" 200 "]);
    XCTAssertTrue([lines[1] containsString:@" 413 "]);
    XCTAssertTrue([lines[2] containsString:@" 400 "]);
    XCTAssertTrue([lines[3] containsString:@" 413 "]);
  } @finally {
    if ([server isRunning]) {
      (void)kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
  }
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

- (void)testAPIReferenceAppStatusAndSwaggerDocs {
  NSString *statusBody = [self requestPath:@"/api/reference/status"
                              serverBinary:@"./build/api-reference-server"
                                 envPrefix:@"ARLEN_APP_ROOT=examples/api_reference"];
  XCTAssertTrue([statusBody containsString:@"\"ok\""]);
  XCTAssertTrue([statusBody containsString:@"api_reference_server"]);

  NSString *docsBody = [self requestPath:@"/openapi"
                            serverBinary:@"./build/api-reference-server"
                               envPrefix:@"ARLEN_APP_ROOT=examples/api_reference"];
  XCTAssertTrue([docsBody containsString:@"Arlen Swagger UI"]);

  NSString *specBody = [self requestPath:@"/openapi.json"
                            serverBinary:@"./build/api-reference-server"
                               envPrefix:@"ARLEN_APP_ROOT=examples/api_reference"];
  XCTAssertTrue([specBody containsString:@"\"/api/reference/users/{id}\""]);
}

- (void)testAPIReferenceAppAuthEnforcesBearerScopeRoute {
  int curlCode = 0;
  int serverCode = 0;
  NSString *status =
      [self requestWithServerEnv:@"ARLEN_APP_ROOT=examples/api_reference"
                     serverBinary:@"./build/api-reference-server"
                        curlBody:@"curl -sS -o /dev/null -w '%%{http_code}' "
                                 "http://127.0.0.1:%d/api/reference/users/7"
                        curlCode:&curlCode
                       serverCode:&serverCode];
  XCTAssertEqual(0, curlCode);
  XCTAssertEqual(0, serverCode);
  XCTAssertEqualObjects(@"401",
                        [status stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
}

- (void)testGSWebMigrationSampleSideBySideRouteParity {
  NSString *legacyBody = [self requestPath:@"/legacy/users/42"
                              serverBinary:@"./build/migration-sample-server"
                                 envPrefix:@"ARLEN_APP_ROOT=examples/gsweb_migration"];
  NSString *arlenBody = [self requestPath:@"/arlen/users/42"
                             serverBinary:@"./build/migration-sample-server"
                                envPrefix:@"ARLEN_APP_ROOT=examples/gsweb_migration"];
  XCTAssertEqualObjects(legacyBody, arlenBody);
  XCTAssertEqualObjects(@"user:42\n", legacyBody);
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
                                              attempts:120
                                               success:&firstOK];
    XCTAssertTrue(firstOK);
    XCTAssertEqualObjects(@"ok\n", firstBody);

    XCTAssertEqual(0, kill(server.processIdentifier, SIGHUP));

    BOOL secondOK = NO;
    NSString *secondBody = [self requestPathWithRetries:@"/healthz"
                                                   port:port
                                               attempts:120
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
                                              attempts:120
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
                                               attempts:120
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

- (void)testPropaneClusterOverridesApplyToWorkers {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [repoRoot stringByAppendingPathComponent:@"examples/tech_demo"];
  int port = [self randomPort];
  NSString *pidFile = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"arlen-propane-cluster-%d.pid", port]];

  NSTask *server = [[NSTask alloc] init];
  server.launchPath = [repoRoot stringByAppendingPathComponent:@"bin/propane"];
  server.currentDirectoryPath = repoRoot;
  server.arguments = @[
    @"--workers",
    @"1",
    @"--host",
    @"127.0.0.1",
    @"--port",
    [NSString stringWithFormat:@"%d", port],
    @"--env",
    @"development",
    @"--pid-file",
    pidFile,
    @"--cluster-enabled",
    @"--cluster-name",
    @"phase3h-cluster",
    @"--cluster-node-id",
    @"phase3h-node",
    @"--cluster-expected-nodes",
    @"2",
  ];
  NSMutableDictionary *env =
      [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
  env[@"ARLEN_FRAMEWORK_ROOT"] = repoRoot;
  env[@"ARLEN_APP_ROOT"] = appRoot;
  server.environment = env;

  [server launch];

  @try {
    BOOL ready = NO;
    NSString *healthBody = [self requestPathWithRetries:@"/healthz"
                                                   port:port
                                               attempts:120
                                                success:&ready];
    XCTAssertTrue(ready);
    XCTAssertEqualObjects(@"ok\n", healthBody);

    BOOL clusterzReady = NO;
    NSString *clusterBody = [self requestPathWithRetries:@"/clusterz"
                                                    port:port
                                                attempts:120
                                                 success:&clusterzReady];
    XCTAssertTrue(clusterzReady);
    XCTAssertTrue([clusterBody containsString:@"\"enabled\":true"] ||
                  [clusterBody containsString:@"\"enabled\": true"]);
    XCTAssertTrue([clusterBody containsString:@"\"name\":\"phase3h-cluster\""] ||
                  [clusterBody containsString:@"\"name\": \"phase3h-cluster\""]);
    XCTAssertTrue([clusterBody containsString:@"\"node_id\":\"phase3h-node\""] ||
                  [clusterBody containsString:@"\"node_id\": \"phase3h-node\""]);
    XCTAssertTrue([clusterBody containsString:@"\"expected_nodes\":2"] ||
                  [clusterBody containsString:@"\"expected_nodes\": 2"]);

    BOOL headerSeen = NO;
    for (NSInteger attempt = 0; attempt < 40; attempt++) {
      int curlCode = 0;
      NSString *headers = [self runShellCapture:[NSString stringWithFormat:
                                                             @"curl -sS -D - -o /dev/null http://127.0.0.1:%d/healthz",
                                                             port]
                                        exitCode:&curlCode];
      if (curlCode == 0 &&
          [headers containsString:@"X-Arlen-Cluster: phase3h-cluster"] &&
          [headers containsString:@"X-Arlen-Node: phase3h-node"] &&
          [headers containsString:@"X-Arlen-Worker-Pid:"]) {
        headerSeen = YES;
        break;
      }
      usleep(200000);
    }
    XCTAssertTrue(headerSeen);

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

- (void)testPropaneSupervisesAsyncWorkersAndRespawnsOnCrash {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [repoRoot stringByAppendingPathComponent:@"examples/tech_demo"];
  int port = [self randomPort];
  NSString *pidFile = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[NSString stringWithFormat:@"arlen-propane-async-%d.pid", port]];

  NSTask *server = [[NSTask alloc] init];
  server.launchPath = [repoRoot stringByAppendingPathComponent:@"bin/propane"];
  server.currentDirectoryPath = repoRoot;
  server.arguments = @[
    @"--workers",
    @"1",
    @"--host",
    @"127.0.0.1",
    @"--port",
    [NSString stringWithFormat:@"%d", port],
    @"--env",
    @"development",
    @"--pid-file",
    pidFile,
    @"--job-worker-cmd",
    @"sleep 30",
    @"--job-worker-count",
    @"1",
    @"--job-worker-respawn-delay-ms",
    @"100",
  ];
  NSMutableDictionary *env =
      [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
  env[@"ARLEN_FRAMEWORK_ROOT"] = repoRoot;
  env[@"ARLEN_APP_ROOT"] = appRoot;
  server.environment = env;

  [server launch];

  @try {
    BOOL ready = NO;
    NSString *body = [self requestPathWithRetries:@"/healthz"
                                             port:port
                                         attempts:120
                                          success:&ready];
    XCTAssertTrue(ready);
    XCTAssertEqualObjects(@"ok\n", body);

    pid_t firstAsyncPID = [self waitForChildPIDForParent:server.processIdentifier
                                          containingToken:@"sleep 30"
                                                excluding:0
                                                 attempts:80];
    XCTAssertTrue(firstAsyncPID > 0);

    XCTAssertEqual(0, kill(firstAsyncPID, SIGKILL));

    pid_t replacementAsyncPID = [self waitForChildPIDForParent:server.processIdentifier
                                                containingToken:@"sleep 30"
                                                      excluding:firstAsyncPID
                                                       attempts:120];
    XCTAssertTrue(replacementAsyncPID > 0);
    XCTAssertNotEqual((int)firstAsyncPID, (int)replacementAsyncPID);

    BOOL secondReady = NO;
    NSString *secondBody = [self requestPathWithRetries:@"/healthz"
                                                   port:port
                                               attempts:120
                                                success:&secondReady];
    XCTAssertTrue(secondReady);
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

- (void)testBoomhauerWatchServesBuildErrorPageAndRecoversAfterFix {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"arlen-boomhauer-watch"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                        content:@"{\n"
                                "  host = \"127.0.0.1\";\n"
                                "  port = 3000;\n"
                                "  logFormat = \"text\";\n"
                                "  serveStatic = NO;\n"
                                "  performanceLogging = YES;\n"
                                "}\n"]);
  XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                        content:@"{\n  logFormat = \"text\";\n}\n"]);
  XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                        content:@"#import <Foundation/Foundation.h>\n"
                                "#import \"ArlenServer.h\"\n"
                                "@interface BrokenController : ALNController @end\n"
                                "@implementation BrokenController\n"
                                "- (id)index:(ALNContext *)ctx {\n"
                                "  (void)ctx\n"
                                "  [self renderText:@\"broken\\n\"];\n"
                                "  return nil;\n"
                                "}\n"
                                "@end\n"
                                "int main(int argc, const char *argv[]) {\n"
                                "  (void)argc; (void)argv; return 0;\n"
                                "}\n"]);

  int port = [self randomPort];
  NSTask *server = [[NSTask alloc] init];
  server.launchPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  server.currentDirectoryPath = appRoot;
  server.arguments = @[ @"--watch", @"--port", [NSString stringWithFormat:@"%d", port] ];
  NSMutableDictionary *env =
      [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
  env[@"ARLEN_FRAMEWORK_ROOT"] = repoRoot;
  env[@"ARLEN_APP_ROOT"] = appRoot;
  server.environment = env;
  server.standardOutput = [NSPipe pipe];
  server.standardError = [NSPipe pipe];
  [server launch];

  @try {
    BOOL errorPageSeen = NO;
    for (NSInteger attempt = 0; attempt < 80; attempt++) {
      int curlCode = 0;
      NSString *body = [self runShellCapture:[NSString stringWithFormat:@"curl -sS http://127.0.0.1:%d/", port]
                                    exitCode:&curlCode];
      if (curlCode == 0 && [body containsString:@"Boomhauer Build Failed"]) {
        errorPageSeen = YES;
        break;
      }
      usleep(250000);
    }
    XCTAssertTrue(errorPageSeen);

    int jsonCurlCode = 0;
    NSString *jsonBody = [self runShellCapture:[NSString stringWithFormat:
                                                   @"curl -sS -H 'Accept: application/json' http://127.0.0.1:%d/api/dev/build-error",
                                                   port]
                                      exitCode:&jsonCurlCode];
    XCTAssertEqual(0, jsonCurlCode);
    XCTAssertTrue([jsonBody containsString:@"dev_build_failed"]);
    XCTAssertTrue([jsonBody containsString:@"stage"]);

    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "#import <stdio.h>\n"
                                  "#import <stdlib.h>\n"
                                  "#import \"ArlenServer.h\"\n"
                                  "@interface LiteController : ALNController @end\n"
                                  "@implementation LiteController\n"
                                  "- (id)index:(ALNContext *)ctx {\n"
                                  "  (void)ctx;\n"
                                  "  [self renderText:@\"hello from lite mode\\n\"];\n"
                                  "  return nil;\n"
                                  "}\n"
                                  "@end\n"
                                  "static void PrintUsage(void) {\n"
                                  "  fprintf(stdout, \"Usage: boomhauer [--port <port>] [--host <addr>] [--env <env>] [--once] [--print-routes]\\\\n\");\n"
                                  "}\n"
                                  "int main(int argc, const char *argv[]) {\n"
                                  "  @autoreleasepool {\n"
                                  "    int portOverride = 0;\n"
                                  "    NSString *host = nil;\n"
                                  "    NSString *environment = @\"development\";\n"
                                  "    BOOL once = NO;\n"
                                  "    BOOL printRoutes = NO;\n"
                                  "    for (int idx = 1; idx < argc; idx++) {\n"
                                  "      NSString *arg = [NSString stringWithUTF8String:argv[idx]];\n"
                                  "      if ([arg isEqualToString:@\"--port\"]) {\n"
                                  "        if ((idx + 1) >= argc) { PrintUsage(); return 2; }\n"
                                  "        portOverride = atoi(argv[++idx]);\n"
                                  "      } else if ([arg isEqualToString:@\"--host\"]) {\n"
                                  "        if ((idx + 1) >= argc) { PrintUsage(); return 2; }\n"
                                  "        host = [NSString stringWithUTF8String:argv[++idx]];\n"
                                  "      } else if ([arg isEqualToString:@\"--env\"]) {\n"
                                  "        if ((idx + 1) >= argc) { PrintUsage(); return 2; }\n"
                                  "        environment = [NSString stringWithUTF8String:argv[++idx]];\n"
                                  "      } else if ([arg isEqualToString:@\"--once\"]) {\n"
                                  "        once = YES;\n"
                                  "      } else if ([arg isEqualToString:@\"--print-routes\"]) {\n"
                                  "        printRoutes = YES;\n"
                                  "      } else if ([arg isEqualToString:@\"--help\"] || [arg isEqualToString:@\"-h\"]) {\n"
                                  "        PrintUsage();\n"
                                  "        return 0;\n"
                                  "      } else {\n"
                                  "        fprintf(stderr, \"Unknown argument: %s\\\\n\", argv[idx]);\n"
                                  "        return 2;\n"
                                  "      }\n"
                                  "    }\n"
                                  "    NSString *appRootCurrent = [[NSFileManager defaultManager] currentDirectoryPath];\n"
                                  "    NSError *error = nil;\n"
                                  "    ALNApplication *app = [[ALNApplication alloc] initWithEnvironment:environment\n"
                                  "                                                           configRoot:appRootCurrent\n"
                                  "                                                                error:&error];\n"
                                  "    if (app == nil) {\n"
                                  "      fprintf(stderr, \"failed loading config: %s\\\\n\", [[error localizedDescription] UTF8String]);\n"
                                  "      return 1;\n"
                                  "    }\n"
                                  "    [app registerRouteMethod:@\"GET\" path:@\"/\" name:@\"home\" controllerClass:[LiteController class] action:@\"index\"];\n"
                                  "    ALNHTTPServer *server = [[ALNHTTPServer alloc] initWithApplication:app\n"
                                  "                                                        publicRoot:[appRootCurrent stringByAppendingPathComponent:@\"public\"]];\n"
                                  "    server.serverName = @\"boomhauer\";\n"
                                  "    if (printRoutes) { [server printRoutesToFile:stdout]; return 0; }\n"
                                  "    return [server runWithHost:host portOverride:portOverride once:once];\n"
                                  "  }\n"
                                  "}\n"]);

    BOOL recovered = NO;
    for (NSInteger attempt = 0; attempt < 240; attempt++) {
      int curlCode = 0;
      NSString *body = [self runShellCapture:[NSString stringWithFormat:@"curl -fsS http://127.0.0.1:%d/", port]
                                    exitCode:&curlCode];
      if (curlCode == 0 && [body containsString:@"hello from lite mode"]) {
        recovered = YES;
        break;
      }
      usleep(250000);
    }
    XCTAssertTrue(recovered);
  } @finally {
    if ([server isRunning]) {
      (void)kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

@end
