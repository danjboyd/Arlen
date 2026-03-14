#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <arpa/inet.h>
#import <netinet/in.h>
#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <sys/socket.h>
#import <unistd.h>

@interface BrowserErrorAuditTests : XCTestCase
@end

@implementation BrowserErrorAuditTests

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

  return 32000 + (int)arc4random_uniform(20000);
}

- (NSString *)repoRoot {
  return [[NSFileManager defaultManager] currentDirectoryPath];
}

- (NSString *)auditOutputRoot {
  NSString *configured =
      [[[NSProcessInfo processInfo] environment] objectForKey:@"ARLEN_BROWSER_ERROR_AUDIT_OUTPUT_DIR"];
  if ([configured length] > 0) {
    return configured;
  }
  return [[self.repoRoot stringByAppendingPathComponent:@"build"]
      stringByAppendingPathComponent:@"browser-error-audit"];
}

- (NSString *)fixturePath:(NSString *)name {
  return [[self.repoRoot stringByAppendingPathComponent:@"tests/fixtures/browser_errors"]
      stringByAppendingPathComponent:name ?: @""];
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

- (NSString *)createTempFilePathWithPrefix:(NSString *)prefix suffix:(NSString *)suffix {
  NSString *fileName = [NSString stringWithFormat:@"%@-%@%@",
                                                  prefix ?: @"arlen",
                                                  [[NSUUID UUID] UUIDString],
                                                  suffix ?: @""];
  return [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
}

- (BOOL)ensureDirectoryAtPath:(NSString *)path {
  NSError *error = nil;
  BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error];
  if (!ok) {
    XCTFail(@"failed creating directory %@: %@", path, error.localizedDescription);
  }
  return ok;
}

- (BOOL)writeFile:(NSString *)path content:(NSString *)content {
  NSString *dir = [path stringByDeletingLastPathComponent];
  if (![self ensureDirectoryAtPath:dir]) {
    return NO;
  }
  NSError *error = nil;
  BOOL ok = [content writeToFile:path
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:&error];
  if (!ok) {
    XCTFail(@"failed writing file %@: %@", path, error.localizedDescription);
  }
  return ok;
}

- (BOOL)writeData:(NSData *)data toPath:(NSString *)path {
  NSString *dir = [path stringByDeletingLastPathComponent];
  if (![self ensureDirectoryAtPath:dir]) {
    return NO;
  }
  BOOL ok = [[NSFileManager defaultManager] createFileAtPath:path
                                                    contents:data ?: [NSData data]
                                                  attributes:nil];
  if (!ok) {
    XCTFail(@"failed writing file %@", path);
  }
  return ok;
}

- (NSString *)loadFixtureTextNamed:(NSString *)name {
  NSString *path = [self fixturePath:name];
  NSError *error = nil;
  NSString *content = [NSString stringWithContentsOfFile:path
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
  if (content == nil) {
    XCTFail(@"failed loading fixture %@: %@", path, error.localizedDescription);
  }
  return content ?: @"";
}

- (NSDictionary *)loadFixtureManifest {
  NSString *path = [self fixturePath:@"browser_error_scenarios.json"];
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (data == nil) {
    XCTFail(@"failed reading fixture %@", path);
    return @{};
  }

  NSError *error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (![object isKindOfClass:[NSDictionary class]] || error != nil) {
    XCTFail(@"failed parsing fixture %@: %@", path, error.localizedDescription);
    return @{};
  }
  return (NSDictionary *)object;
}

- (NSString *)shellQuote:(NSString *)value {
  NSString *escaped = [value ?: @"" stringByReplacingOccurrencesOfString:@"'"
                                                              withString:@"'\"'\"'"];
  return [NSString stringWithFormat:@"'%@'", escaped];
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
  NSMutableData *combined = [NSMutableData data];
  if ([stdoutData length] > 0) {
    [combined appendData:stdoutData];
  }
  if ([stderrData length] > 0) {
    [combined appendData:stderrData];
  }
  NSString *output = [[NSString alloc] initWithData:combined encoding:NSUTF8StringEncoding];
  if (output == nil && [combined length] > 0) {
    output = [[NSString alloc] initWithData:combined encoding:NSISOLatin1StringEncoding];
  }
  return output ?: @"";
}

- (NSString *)decodedStringFromData:(NSData *)data {
  if (data == nil) {
    return @"";
  }
  NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (text == nil) {
    text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
  }
  return text ?: @"";
}

- (NSDictionary *)parseHeaderBlock:(NSString *)headerText {
  NSString *normalized = [[headerText ?: @"" stringByReplacingOccurrencesOfString:@"\r\n"
                                                                       withString:@"\n"]
      stringByReplacingOccurrencesOfString:@"\r"
                                withString:@"\n"];
  NSArray *blocks = [normalized componentsSeparatedByString:@"\n\n"];
  NSString *selected = @"";
  for (NSString *block in blocks) {
    NSString *trimmed =
        [block stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] > 0) {
      selected = trimmed;
    }
  }

  NSMutableDictionary *headers = [NSMutableDictionary dictionary];
  NSString *statusLine = @"";
  NSArray *lines = [selected componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSUInteger idx = 0; idx < [lines count]; idx++) {
    NSString *line = lines[idx];
    if (idx == 0) {
      statusLine = line ?: @"";
      continue;
    }
    NSRange separator = [line rangeOfString:@":"];
    if (separator.location == NSNotFound) {
      continue;
    }
    NSString *name = [[[line substringToIndex:separator.location]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
    NSString *value = [[line substringFromIndex:separator.location + 1]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([name length] > 0) {
      headers[name] = value ?: @"";
    }
  }

  return @{
    @"status_line" : statusLine ?: @"",
    @"header_block" : selected ?: @"",
    @"headers" : headers
  };
}

- (NSDictionary *)captureURL:(NSString *)url headers:(NSDictionary *)headers {
  NSString *headerPath = [self createTempFilePathWithPrefix:@"browser-error-audit-headers" suffix:@".txt"];
  NSString *bodyPath = [self createTempFilePathWithPrefix:@"browser-error-audit-body" suffix:@".bin"];
  NSMutableString *command = [NSMutableString
      stringWithFormat:@"curl -sS --max-time 10 -D %@ -o %@ ",
                       [self shellQuote:headerPath], [self shellQuote:bodyPath]];

  NSArray *sortedHeaderNames = [[headers allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *name in sortedHeaderNames) {
    NSString *line = [NSString stringWithFormat:@"%@: %@", name, headers[name] ?: @""];
    [command appendFormat:@"-H %@ ", [self shellQuote:line]];
  }
  [command appendFormat:@"%@ -w 'STATUS:%%{http_code}\nCTYPE:%%{content_type}\n'",
                        [self shellQuote:url]];

  int exitCode = 0;
  NSString *trailer = [self runShellCapture:command exitCode:&exitCode];
  NSData *headerData = [NSData dataWithContentsOfFile:headerPath];
  NSData *bodyData = [NSData dataWithContentsOfFile:bodyPath];
  [[NSFileManager defaultManager] removeItemAtPath:headerPath error:nil];
  [[NSFileManager defaultManager] removeItemAtPath:bodyPath error:nil];

  NSInteger status = 0;
  NSString *contentType = @"";
  NSArray *trailerLines =
      [trailer componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  for (NSString *line in trailerLines) {
    if ([line hasPrefix:@"STATUS:"]) {
      status = [[line substringFromIndex:7] integerValue];
    } else if ([line hasPrefix:@"CTYPE:"]) {
      contentType = [line substringFromIndex:6] ?: @"";
    }
  }

  NSString *headerText = [self decodedStringFromData:headerData];
  NSDictionary *parsedHeaders = [self parseHeaderBlock:headerText];
  if ([contentType length] == 0) {
    NSString *headerContentType = [parsedHeaders[@"headers"][@"content-type"] isKindOfClass:[NSString class]]
                                      ? parsedHeaders[@"headers"][@"content-type"]
                                      : @"";
    contentType = headerContentType ?: @"";
  }

  return @{
    @"url" : url ?: @"",
    @"curl_exit_code" : @(exitCode),
    @"status" : @(status),
    @"content_type" : contentType ?: @"",
    @"header_block" : parsedHeaders[@"header_block"] ?: @"",
    @"status_line" : parsedHeaders[@"status_line"] ?: @"",
    @"headers" : parsedHeaders[@"headers"] ?: @{},
    @"body_data" : bodyData ?: [NSData data],
    @"body_text" : [self decodedStringFromData:bodyData],
    @"curl_output" : trailer ?: @""
  };
}

- (NSString *)serverLogExcerptAtPath:(NSString *)path {
  NSString *text = [self decodedStringFromData:[NSData dataWithContentsOfFile:path]];
  if ([text length] <= 2000) {
    return text ?: @"";
  }
  return [text substringFromIndex:[text length] - 2000];
}

- (NSDictionary *)launchBoomhauerAtAppRoot:(NSString *)appRoot
                                  repoRoot:(NSString *)repoRoot
                                     watch:(BOOL)watch
                               environment:(NSString *)environment
                                  extraEnv:(NSDictionary *)extraEnv
                         readinessPath:(NSString *)readinessPath
                          readinessAccept:(NSString *)readinessAccept
                           readinessStatus:(NSInteger)readinessStatus
                      readinessBodyContains:(NSString *)readinessBodyContains
                                   issues:(NSMutableArray *)issues {
  int port = [self randomPort];
  NSString *logPath = [self createTempFilePathWithPrefix:@"browser-error-audit-server" suffix:@".log"];
  [[NSFileManager defaultManager] createFileAtPath:logPath contents:[NSData data] attributes:nil];
  NSFileHandle *logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];

  NSTask *server = [[NSTask alloc] init];
  server.launchPath = [repoRoot stringByAppendingPathComponent:@"bin/boomhauer"];
  server.currentDirectoryPath = appRoot;
  NSMutableArray *arguments = [NSMutableArray array];
  [arguments addObject:(watch ? @"--watch" : @"--no-watch")];
  [arguments addObject:@"--port"];
  [arguments addObject:[NSString stringWithFormat:@"%d", port]];
  if ([environment length] > 0) {
    [arguments addObject:@"--env"];
    [arguments addObject:environment];
  }
  server.arguments = arguments;

  NSMutableDictionary *env =
      [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
  env[@"ARLEN_FRAMEWORK_ROOT"] = repoRoot ?: @"";
  env[@"ARLEN_APP_ROOT"] = appRoot ?: @"";
  for (NSString *key in extraEnv) {
    env[key] = extraEnv[key];
  }
  server.environment = env;
  server.standardOutput = logHandle;
  server.standardError = logHandle;

  @try {
    [server launch];
  } @catch (NSException *exception) {
    [issues addObject:[NSString stringWithFormat:@"failed launching boomhauer: %@",
                                                 exception.reason ?: exception.name]];
    if (logHandle != nil) {
      [logHandle closeFile];
    }
    return @{
      @"failed" : @(YES),
      @"issues" : issues ?: @[],
      @"log_path" : logPath ?: @"",
      @"app_root" : appRoot ?: @""
    };
  }

  NSDictionary *handle = @{
    @"task" : server,
    @"port" : @(port),
    @"base_url" : [NSString stringWithFormat:@"http://127.0.0.1:%d", port],
    @"log_path" : logPath ?: @"",
    @"log_handle" : logHandle ?: [NSNull null],
    @"app_root" : appRoot ?: @"",
    @"failed" : @(NO)
  };

  BOOL ready = NO;
  NSDictionary *lastCapture = nil;
  NSDictionary *headers =
      ([readinessAccept length] > 0) ? @{ @"Accept" : readinessAccept } : @{};
  for (NSInteger attempt = 0; attempt < 240; attempt++) {
    NSString *url = [NSString stringWithFormat:@"http://127.0.0.1:%d%@", port, readinessPath ?: @"/"];
    lastCapture = [self captureURL:url headers:headers];
    NSString *body = [lastCapture[@"body_text"] isKindOfClass:[NSString class]]
                         ? lastCapture[@"body_text"]
                         : @"";
    NSInteger status = [lastCapture[@"status"] respondsToSelector:@selector(integerValue)]
                           ? [lastCapture[@"status"] integerValue]
                           : 0;
    if ([lastCapture[@"curl_exit_code"] integerValue] == 0 && status == readinessStatus &&
        ([readinessBodyContains length] == 0 || [body containsString:readinessBodyContains])) {
      ready = YES;
      break;
    }
    usleep(250000);
  }

  if (!ready) {
    NSString *logExcerpt = [self serverLogExcerptAtPath:logPath];
    NSString *statusLine = [lastCapture[@"status_line"] isKindOfClass:[NSString class]]
                               ? lastCapture[@"status_line"]
                               : @"";
    [issues addObject:[NSString stringWithFormat:
                                    @"server did not reach readiness for %@ %@ (last status line: %@)",
                                    environment ?: @"development",
                                    readinessPath ?: @"/",
                                    statusLine]];
    if ([logExcerpt length] > 0) {
      [issues addObject:[NSString stringWithFormat:@"server log tail:\n%@", logExcerpt]];
    }
    return @{
      @"failed" : @(YES),
      @"issues" : issues ?: @[],
      @"log_path" : logPath ?: @"",
      @"app_root" : appRoot ?: @"",
      @"task" : server
    };
  }

  return handle;
}

- (void)stopServerHandle:(NSDictionary *)handle {
  NSTask *task = [handle[@"task"] isKindOfClass:[NSTask class]] ? handle[@"task"] : nil;
  if (task != nil && [task isRunning]) {
    (void)kill(task.processIdentifier, SIGTERM);
    for (NSInteger attempt = 0; attempt < 20 && [task isRunning]; attempt++) {
      usleep(100000);
    }
    if ([task isRunning]) {
      (void)kill(task.processIdentifier, SIGKILL);
    }
    [task waitUntilExit];
  }

  NSFileHandle *logHandle =
      [handle[@"log_handle"] isKindOfClass:[NSFileHandle class]] ? handle[@"log_handle"] : nil;
  [logHandle closeFile];

  NSString *appRoot = [handle[@"app_root"] isKindOfClass:[NSString class]] ? handle[@"app_root"] : nil;
  if ([appRoot length] > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (BOOL)writeAuditConfigAtRoot:(NSString *)appRoot {
  BOOL ok = YES;
  ok = ok && [self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                     content:@"{\n"
                             "  host = \"127.0.0.1\";\n"
                             "  port = 3000;\n"
                             "  logFormat = \"text\";\n"
                             "  serveStatic = NO;\n"
                             "  performanceLogging = YES;\n"
                             "}\n"];
  ok = ok && [self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                     content:@"{\n  logFormat = \"text\";\n}\n"];
  ok = ok && [self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/production.plist"]
                     content:@"{\n  logFormat = \"json\";\n}\n"];
  return ok;
}

- (NSDictionary *)startRuntimeContextForEnvironment:(NSString *)environment
                                           repoRoot:(NSString *)repoRoot
                                             issues:(NSMutableArray *)issues {
  NSString *appRoot = [self createTempDirectoryWithPrefix:
                                  [NSString stringWithFormat:@"arlen-browser-error-%@",
                                                             environment ?: @"development"]];
  if (appRoot == nil) {
    [issues addObject:@"failed creating temporary app root"];
    return @{ @"failed" : @(YES), @"issues" : issues ?: @[] };
  }

  if (![self writeAuditConfigAtRoot:appRoot]) {
    [issues addObject:@"failed writing app configuration"];
    return @{ @"failed" : @(YES), @"issues" : issues ?: @[], @"app_root" : appRoot ?: @"" };
  }

  NSString *appSource = [self loadFixtureTextNamed:@"runtime_audit_app_lite.m.txt"];
  if (![self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"] content:appSource]) {
    [issues addObject:@"failed writing runtime audit app source"];
    return @{ @"failed" : @(YES), @"issues" : issues ?: @[], @"app_root" : appRoot ?: @"" };
  }

  return [self launchBoomhauerAtAppRoot:appRoot
                               repoRoot:repoRoot
                                  watch:NO
                            environment:environment
                               extraEnv:@{}
                          readinessPath:@"/ok"
                       readinessAccept:@"text/plain"
                        readinessStatus:200
                   readinessBodyContains:@"ok"
                                issues:issues];
}

- (NSDictionary *)startBuildFailureContextForMode:(NSString *)mode
                                         repoRoot:(NSString *)repoRoot
                                           issues:(NSMutableArray *)issues {
  NSString *appRoot =
      [self createTempDirectoryWithPrefix:[NSString stringWithFormat:@"arlen-browser-build-%@",
                                                                     mode ?: @"error"]];
  if (appRoot == nil) {
    [issues addObject:@"failed creating temporary watch-mode app root"];
    return @{ @"failed" : @(YES), @"issues" : issues ?: @[] };
  }

  if (![self writeAuditConfigAtRoot:appRoot]) {
    [issues addObject:@"failed writing watch-mode app configuration"];
    return @{ @"failed" : @(YES), @"issues" : issues ?: @[], @"app_root" : appRoot ?: @"" };
  }

  NSString *appSource = [self loadFixtureTextNamed:@"simple_ok_app_lite.m.txt"];
  if ([mode isEqualToString:@"objc"]) {
    appSource = [appSource stringByReplacingOccurrencesOfString:@"ALNController"
                                                     withString:@"ALNControxxer"];
  }
  if (![self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"] content:appSource]) {
    [issues addObject:@"failed writing watch-mode app source"];
    return @{ @"failed" : @(YES), @"issues" : issues ?: @[], @"app_root" : appRoot ?: @"" };
  }

  if ([mode isEqualToString:@"eoc"]) {
    NSString *brokenTemplate = @"<% NSString *word = @\"broken\"; %><%= word %\n";
    if (![self writeFile:[appRoot stringByAppendingPathComponent:@"templates/index.html.eoc"]
                 content:brokenTemplate]) {
      [issues addObject:@"failed writing broken EOC fixture"];
      return @{ @"failed" : @(YES), @"issues" : issues ?: @[], @"app_root" : appRoot ?: @"" };
    }
  }

  return [self launchBoomhauerAtAppRoot:appRoot
                               repoRoot:repoRoot
                                  watch:YES
                            environment:@"development"
                               extraEnv:@{
                                 @"ARLEN_BOOMHAUER_BUILD_ERROR_RETRY_SECONDS" : @"1",
                                 @"ARLEN_BOOMHAUER_BUILD_ERROR_AUTO_REFRESH_SECONDS" : @"2",
                               }
                          readinessPath:@"/"
                       readinessAccept:@"text/html"
                        readinessStatus:500
                   readinessBodyContains:@"Boomhauer Build Failed"
                                issues:issues];
}

- (NSDictionary *)sharedRuntimeContextForEnvironment:(NSString *)environment
                                            repoRoot:(NSString *)repoRoot
                                            contexts:(NSMutableDictionary *)contexts {
  NSString *key = [NSString stringWithFormat:@"runtime:%@", environment ?: @"development"];
  NSDictionary *existing = [contexts[key] isKindOfClass:[NSDictionary class]] ? contexts[key] : nil;
  if (existing != nil) {
    return existing;
  }

  NSMutableArray *issues = [NSMutableArray array];
  NSDictionary *handle = [self startRuntimeContextForEnvironment:environment
                                                        repoRoot:repoRoot
                                                          issues:issues];
  contexts[key] = handle ?: @{ @"failed" : @(YES), @"issues" : issues ?: @[] };
  return contexts[key];
}

- (void)stopSharedContexts:(NSDictionary *)contexts {
  for (NSDictionary *handle in [contexts allValues]) {
    [self stopServerHandle:handle];
  }
}

- (NSString *)escapeHTML:(NSString *)value {
  NSString *escaped = value ?: @"";
  escaped = [escaped stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
  escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
  return escaped;
}

- (NSString *)sanitizeHTMLForPreview:(NSString *)html {
  NSError *error = nil;
  NSRegularExpression *regex =
      [NSRegularExpression regularExpressionWithPattern:@"<meta[^>]+http-equiv=['\"]refresh['\"][^>]*>"
                                                options:NSRegularExpressionCaseInsensitive
                                                  error:&error];
  if (regex == nil || error != nil) {
    return html ?: @"";
  }
  return [regex stringByReplacingMatchesInString:html ?: @""
                                         options:0
                                           range:NSMakeRange(0, [html length])
                                    withTemplate:@""];
}

- (NSString *)isoTimestampNow {
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
  return [formatter stringFromDate:[NSDate date]] ?: @"";
}

- (NSString *)prettyPrintedJSONStringFromData:(NSData *)data {
  if (data == nil) {
    return @"";
  }
  NSError *error = nil;
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (object == nil || error != nil) {
    return [self decodedStringFromData:data];
  }
  NSData *pretty = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
  if (pretty == nil || error != nil) {
    return [self decodedStringFromData:data];
  }
  return [self decodedStringFromData:pretty];
}

- (NSString *)rawFileExtensionForContentType:(NSString *)contentType {
  NSString *normalized = [contentType lowercaseString] ?: @"";
  if ([normalized containsString:@"html"]) {
    return @"html";
  }
  if ([normalized containsString:@"json"]) {
    return @"json";
  }
  return @"txt";
}

- (NSString *)presentationKindForContentType:(NSString *)contentType {
  NSString *normalized = [contentType lowercaseString] ?: @"";
  if ([normalized containsString:@"html"]) {
    return @"html";
  }
  if ([normalized containsString:@"json"]) {
    return @"json";
  }
  if ([normalized containsString:@"text/plain"]) {
    return @"text";
  }
  if ([normalized length] == 0) {
    return @"unknown";
  }
  return @"other";
}

- (NSString *)presentationLabelForKind:(NSString *)kind {
  if ([kind isEqualToString:@"html"]) {
    return @"First-class HTML";
  }
  if ([kind isEqualToString:@"json"]) {
    return @"Raw JSON";
  }
  if ([kind isEqualToString:@"text"]) {
    return @"Raw Text";
  }
  if ([kind isEqualToString:@"other"]) {
    return @"Other";
  }
  return @"Unknown";
}

- (NSString *)bodySummary:(NSString *)body {
  NSString *trimmed =
      [body ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return @"(empty body)";
  }
  NSString *singleLine = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]
      componentsJoinedByString:@" "];
  if ([singleLine length] > 140) {
    return [[singleLine substringToIndex:140] stringByAppendingString:@"..."];
  }
  return singleLine;
}

- (NSString *)renderListItems:(NSArray *)items {
  NSMutableString *html = [NSMutableString string];
  for (NSString *item in items) {
    [html appendFormat:@"<li>%@</li>", [self escapeHTML:item ?: @""]];
  }
  return html;
}

- (NSString *)reviewPageHTMLForScenario:(NSDictionary *)scenario
                                capture:(NSDictionary *)capture
                                 issues:(NSArray *)issues
                              rawFile:(NSString *)rawFile
                           previewFile:(NSString *)previewFile
                          headersFile:(NSString *)headersFile
                        serverLogFile:(NSString *)serverLogFile
                           extraFiles:(NSArray *)extraFiles
                            prettyBody:(NSString *)prettyBody {
  NSString *title = [scenario[@"title"] isKindOfClass:[NSString class]] ? scenario[@"title"] : @"Scenario";
  NSString *description =
      [scenario[@"description"] isKindOfClass:[NSString class]] ? scenario[@"description"] : @"";
  NSString *sourceSurface =
      [scenario[@"source_surface"] isKindOfClass:[NSString class]] ? scenario[@"source_surface"] : @"";
  NSString *contentType =
      [capture[@"content_type"] isKindOfClass:[NSString class]] ? capture[@"content_type"] : @"";
  NSInteger status = [capture[@"status"] respondsToSelector:@selector(integerValue)]
                         ? [capture[@"status"] integerValue]
                         : 0;
  NSString *presentationKind = [self presentationKindForContentType:contentType];
  NSString *presentationLabel = [self presentationLabelForKind:presentationKind];
  NSArray *reviewFocus = [scenario[@"review_focus"] isKindOfClass:[NSArray class]] ? scenario[@"review_focus"] : @[];

  NSMutableString *extrasHTML = [NSMutableString string];
  for (NSDictionary *file in extraFiles) {
    NSString *label = [file[@"label"] isKindOfClass:[NSString class]] ? file[@"label"] : @"Artifact";
    NSString *path = [file[@"path"] isKindOfClass:[NSString class]] ? file[@"path"] : @"";
    if ([path length] > 0) {
      [extrasHTML appendFormat:@"<li><a href='%@'>%@</a></li>",
                              [self escapeHTML:path],
                              [self escapeHTML:label]];
    }
  }

  NSMutableString *bodySection = [NSMutableString string];
  if ([presentationKind isEqualToString:@"html"] && [previewFile length] > 0) {
    [bodySection appendFormat:@"<div class='preview-frame'><iframe src='%@' title='Scenario preview'></iframe></div>",
                            [self escapeHTML:previewFile]];
  } else {
    [bodySection appendFormat:@"<pre class='body-preview'>%@</pre>",
                            [self escapeHTML:prettyBody ?: @""]];
  }

  NSString *statusClass = ([issues count] == 0) ? @"pass" : @"warn";
  NSMutableString *html = [NSMutableString string];
  [html appendString:@"<!doctype html><html><head><meta charset='utf-8'>"];
  [html appendFormat:@"<title>%@</title>", [self escapeHTML:title]];
  [html appendString:@"<style>"
                      ":root{--bg:#f4efe7;--panel:#fffaf2;--ink:#241b14;--muted:#6d5b4a;--line:#dcccb6;--accent:#b4472f;--accent-soft:#f3dfd7;--good:#2d6a4f;--warn:#965d11;}"
                      "body{margin:0;font-family:'IBM Plex Mono',Menlo,Consolas,monospace;background:linear-gradient(180deg,#efe4d4 0%,#f7f3ed 60%,#f4efe7 100%);color:var(--ink);}"
                      "main{max-width:1200px;margin:0 auto;padding:32px 24px 48px;display:grid;gap:20px;}"
                      "header{display:grid;gap:8px;}"
                      "h1,h2{font-family:'Iowan Old Style',Georgia,serif;margin:0;line-height:1.1;}"
                      "h1{font-size:42px;}h2{font-size:20px;}"
                      ".lede{max-width:72ch;color:var(--muted);font-size:15px;}"
                      ".card{background:var(--panel);border:1px solid var(--line);border-radius:18px;padding:18px 20px;box-shadow:0 12px 32px rgba(74,53,33,.08);}"
                      ".meta{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;}"
                      ".metric{background:#fff;border:1px solid var(--line);border-radius:14px;padding:12px 14px;}"
                      ".metric .label{display:block;color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.08em;margin-bottom:6px;}"
                      ".metric .value{font-size:15px;word-break:break-word;}"
                      ".badge{display:inline-flex;align-items:center;gap:8px;padding:6px 10px;border-radius:999px;font-size:12px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;}"
                      ".badge.pass{background:#e0f1e8;color:var(--good);} .badge.warn{background:#f7ead2;color:var(--warn);}"
                      ".actions a{display:inline-block;margin-right:12px;color:var(--accent);text-decoration:none;font-weight:700;}"
                      "ul{margin:10px 0 0 18px;padding:0;display:grid;gap:8px;}"
                      "pre{margin:0;white-space:pre-wrap;word-break:break-word;background:#fff;border:1px solid var(--line);border-radius:14px;padding:16px;overflow:auto;}"
                      ".preview-frame{border:1px solid var(--line);border-radius:18px;overflow:hidden;background:#fff;height:720px;}"
                      "iframe{display:block;width:100%;height:100%;border:0;background:#fff;}"
                      ".issue-list li{color:#7f321f;}"
                      ".subtle{color:var(--muted);font-size:13px;}"
                      "</style></head><body><main>"];
  [html appendFormat:@"<header><div><a href='../index.html'>Back to audit index</a></div><h1>%@</h1><p class='lede'>%@</p></header>",
                     [self escapeHTML:title],
                     [self escapeHTML:description]];
  [html appendFormat:@"<section class='card'><div class='badge %@'>%@</div>"
                     "<div class='meta' style='margin-top:14px;'>"
                     "<div class='metric'><span class='label'>Scenario ID</span><span class='value'>%@</span></div>"
                     "<div class='metric'><span class='label'>Status</span><span class='value'>%ld</span></div>"
                     "<div class='metric'><span class='label'>Content Type</span><span class='value'>%@</span></div>"
                     "<div class='metric'><span class='label'>Presentation</span><span class='value'>%@</span></div>"
                     "<div class='metric'><span class='label'>Surface</span><span class='value'>%@</span></div>"
                     "</div></section>",
                     statusClass,
                     [self escapeHTML:([issues count] == 0 ? @"Contract Matched" : @"Needs Review")],
                     [self escapeHTML:scenario[@"id"] ?: @""],
                     (long)status,
                     [self escapeHTML:contentType],
                     [self escapeHTML:presentationLabel],
                     [self escapeHTML:sourceSurface]];

  [html appendString:@"<section class='card'><h2>Review Focus</h2><ul>"];
  [html appendString:[self renderListItems:reviewFocus]];
  [html appendString:@"</ul></section>"];

  [html appendString:@"<section class='card'><h2>Artifacts</h2><div class='actions'>"];
  if ([rawFile length] > 0) {
    [html appendFormat:@"<a href='%@'>Open Raw Response</a>", [self escapeHTML:rawFile]];
  }
  if ([headersFile length] > 0) {
    [html appendFormat:@"<a href='%@'>Open Response Headers</a>", [self escapeHTML:headersFile]];
  }
  if ([serverLogFile length] > 0) {
    [html appendFormat:@"<a href='%@'>Open Server Log</a>", [self escapeHTML:serverLogFile]];
  }
  [html appendString:@"</div>"];
  if ([extrasHTML length] > 0) {
    [html appendFormat:@"<div class='subtle' style='margin-top:12px;'>Supplemental captures</div><ul>%@</ul>", extrasHTML];
  }
  [html appendString:@"</section>"];

  [html appendString:@"<section class='card'><h2>Browser Review</h2>"];
  [html appendString:bodySection];
  [html appendString:@"</section>"];

  [html appendString:@"<section class='card'><h2>Observed Issues</h2>"];
  if ([issues count] == 0) {
    [html appendString:@"<p class='subtle'>No automated contract mismatches were detected for this scenario.</p>"];
  } else {
    [html appendFormat:@"<ul class='issue-list'>%@</ul>", [self renderListItems:issues]];
  }
  [html appendString:@"</section>"];

  [html appendString:@"</main></body></html>"];
  return html;
}

- (NSString *)indexHTMLForManifest:(NSDictionary *)manifest results:(NSArray *)results {
  NSString *title = [manifest[@"title"] isKindOfClass:[NSString class]] ? manifest[@"title"] : @"Browser Error Audit";
  NSArray *checklist =
      [manifest[@"review_checklist"] isKindOfClass:[NSArray class]] ? manifest[@"review_checklist"] : @[];
  NSMutableString *cards = [NSMutableString string];
  for (NSDictionary *result in results) {
    NSString *presentationKind =
        [result[@"presentation_kind"] isKindOfClass:[NSString class]] ? result[@"presentation_kind"] : @"";
    NSString *presentationLabel = [self presentationLabelForKind:presentationKind];
    BOOL passed = [result[@"passed"] boolValue];
    NSString *reviewPath = [result[@"review_path"] isKindOfClass:[NSString class]] ? result[@"review_path"] : @"";
    NSString *rawPath = [result[@"raw_path"] isKindOfClass:[NSString class]] ? result[@"raw_path"] : @"";
    NSString *summary = [result[@"body_summary"] isKindOfClass:[NSString class]] ? result[@"body_summary"] : @"";
    [cards appendFormat:
               @"<article class='card'>"
                "<div class='card-top'><span class='badge %@'>%@</span><span class='muted'>%ld</span></div>"
                "<h2>%@</h2>"
                "<p class='muted'>%@</p>"
                "<div class='meta'>"
                "<div><span class='label'>Surface</span><span class='value'>%@</span></div>"
                "<div><span class='label'>Content Type</span><span class='value'>%@</span></div>"
                "<div><span class='label'>Presentation</span><span class='value'>%@</span></div>"
                "</div>"
                "<p class='summary'>%@</p>"
                "<div class='links'><a href='%@'>Open Review</a><a href='%@'>Open Raw</a></div>"
                "</article>",
               (passed ? @"pass" : @"warn"),
               [self escapeHTML:(passed ? @"Contract Matched" : @"Needs Review")],
               (long)[result[@"status"] integerValue],
               [self escapeHTML:result[@"title"] ?: @""],
               [self escapeHTML:result[@"description"] ?: @""],
               [self escapeHTML:result[@"source_surface"] ?: @""],
               [self escapeHTML:result[@"content_type"] ?: @""],
               [self escapeHTML:presentationLabel],
               [self escapeHTML:summary],
               [self escapeHTML:reviewPath],
               [self escapeHTML:rawPath]];
  }

  NSMutableString *html = [NSMutableString string];
  [html appendString:@"<!doctype html><html><head><meta charset='utf-8'>"];
  [html appendFormat:@"<title>%@</title>", [self escapeHTML:title]];
  [html appendString:@"<style>"
                      ":root{--bg:#f4efe7;--panel:#fffaf2;--ink:#241b14;--muted:#6d5b4a;--line:#dcccb6;--accent:#b4472f;--accent-soft:#f3dfd7;--good:#2d6a4f;--warn:#965d11;}"
                      "body{margin:0;font-family:'IBM Plex Mono',Menlo,Consolas,monospace;background:radial-gradient(circle at top left,#f9efe1 0%,#f4efe7 40%,#efe6da 100%);color:var(--ink);}"
                      "main{max-width:1240px;margin:0 auto;padding:36px 24px 56px;display:grid;gap:20px;}"
                      "header{display:grid;gap:10px;max-width:78ch;}h1,h2{font-family:'Iowan Old Style',Georgia,serif;margin:0;line-height:1.05;}h1{font-size:48px;}h2{font-size:24px;}"
                      ".lede{color:var(--muted);font-size:15px;line-height:1.6;}"
                      ".card{background:rgba(255,250,242,.92);border:1px solid var(--line);border-radius:20px;padding:18px 20px;box-shadow:0 16px 42px rgba(74,53,33,.08);}"
                      ".card-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px;}"
                      ".checklist{display:grid;gap:8px;margin:0;padding-left:18px;}"
                      ".badge{display:inline-flex;align-items:center;padding:6px 10px;border-radius:999px;font-size:12px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;}"
                      ".badge.pass{background:#e0f1e8;color:var(--good);} .badge.warn{background:#f7ead2;color:var(--warn);}"
                      ".card-top{display:flex;justify-content:space-between;align-items:center;gap:12px;margin-bottom:12px;}"
                      ".meta{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin:14px 0;}"
                      ".label{display:block;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.08em;margin-bottom:4px;}"
                      ".value{display:block;font-size:13px;word-break:break-word;}"
                      ".summary{min-height:54px;color:var(--ink);}"
                      ".muted{color:var(--muted);font-size:13px;}"
                      ".links a{margin-right:12px;color:var(--accent);text-decoration:none;font-weight:700;}"
                      "</style></head><body><main>"];
  [html appendFormat:@"<header><h1>%@</h1><p class='lede'>This gallery captures a browser-reviewable sampling of Arlen build-time and runtime error surfaces. Each card links to a scenario review page plus the raw response body so you can judge usefulness, correctness, and presentation quality without recreating the failure manually.</p><p class='muted'>Generated at %@</p></header>",
                     [self escapeHTML:title],
                     [self escapeHTML:[self isoTimestampNow]]];
  [html appendString:@"<section class='card'><h2>Review Checklist</h2><ul class='checklist'>"];
  [html appendString:[self renderListItems:checklist]];
  [html appendString:@"</ul></section>"];
  [html appendFormat:@"<section class='card'><h2>Scenario Gallery</h2><div class='card-grid'>%@</div></section>",
                     cards];
  [html appendString:@"</main></body></html>"];
  return html;
}

- (NSDictionary *)writeArtifactsForScenario:(NSDictionary *)scenario
                                    capture:(NSDictionary *)capture
                                   issuesIn:(NSArray *)issuesIn
                                outputRoot:(NSString *)outputRoot
                               serverLogPath:(NSString *)serverLogPath
                                extraArtifacts:(NSArray *)extraArtifacts {
  NSMutableArray *issues = [NSMutableArray arrayWithArray:issuesIn ?: @[]];
  NSString *scenarioID = [scenario[@"id"] isKindOfClass:[NSString class]] ? scenario[@"id"] : @"scenario";
  NSString *title = [scenario[@"title"] isKindOfClass:[NSString class]] ? scenario[@"title"] : scenarioID;
  NSString *description =
      [scenario[@"description"] isKindOfClass:[NSString class]] ? scenario[@"description"] : @"";
  NSString *sourceSurface =
      [scenario[@"source_surface"] isKindOfClass:[NSString class]] ? scenario[@"source_surface"] : @"";

  NSString *scenarioDir = [outputRoot stringByAppendingPathComponent:scenarioID];
  [self ensureDirectoryAtPath:scenarioDir];

  NSInteger expectedStatus = [scenario[@"expected_status"] respondsToSelector:@selector(integerValue)]
                                 ? [scenario[@"expected_status"] integerValue]
                                 : 0;
  NSString *expectedContentType =
      [scenario[@"expected_content_type_prefix"] isKindOfClass:[NSString class]]
          ? scenario[@"expected_content_type_prefix"]
          : @"";
  NSArray *expectedBodyContains =
      [scenario[@"expected_body_contains"] isKindOfClass:[NSArray class]]
          ? scenario[@"expected_body_contains"]
          : @[];

  NSInteger status = [capture[@"status"] respondsToSelector:@selector(integerValue)]
                         ? [capture[@"status"] integerValue]
                         : 0;
  NSString *contentType =
      [capture[@"content_type"] isKindOfClass:[NSString class]] ? capture[@"content_type"] : @"";
  NSString *bodyText = [capture[@"body_text"] isKindOfClass:[NSString class]] ? capture[@"body_text"] : @"";
  NSData *bodyData = [capture[@"body_data"] isKindOfClass:[NSData class]] ? capture[@"body_data"] : [NSData data];

  if (expectedStatus > 0 && status != expectedStatus) {
    [issues addObject:[NSString stringWithFormat:@"expected status %ld but captured %ld",
                                                 (long)expectedStatus,
                                                 (long)status]];
  }
  if ([expectedContentType length] > 0 &&
      [[contentType lowercaseString] rangeOfString:[expectedContentType lowercaseString]].location == NSNotFound) {
    [issues addObject:[NSString stringWithFormat:@"expected content type prefix %@ but captured %@",
                                                 expectedContentType,
                                                 contentType]];
  }
  for (NSString *needle in expectedBodyContains) {
    if ([bodyText rangeOfString:needle].location == NSNotFound) {
      [issues addObject:[NSString stringWithFormat:@"body did not contain expected text: %@", needle]];
    }
  }
  if ([capture[@"curl_exit_code"] integerValue] != 0) {
    [issues addObject:[NSString stringWithFormat:@"curl exited with code %@",
                                                 capture[@"curl_exit_code"]]];
  }

  NSString *rawExtension = [self rawFileExtensionForContentType:contentType];
  NSString *rawFileName = [NSString stringWithFormat:@"response.raw.%@", rawExtension];
  NSString *rawPath = [scenarioDir stringByAppendingPathComponent:rawFileName];
  [self writeData:bodyData toPath:rawPath];

  NSString *headersFileName = @"response.headers.txt";
  NSString *headersPath = [scenarioDir stringByAppendingPathComponent:headersFileName];
  [self writeFile:headersPath content:capture[@"header_block"] ?: @""];

  NSString *previewFileName = @"";
  NSString *previewPath = @"";
  if ([[contentType lowercaseString] containsString:@"html"]) {
    previewFileName = @"response.preview.html";
    previewPath = [scenarioDir stringByAppendingPathComponent:previewFileName];
    [self writeFile:previewPath content:[self sanitizeHTMLForPreview:bodyText]];
  }

  NSString *serverLogFileName = @"";
  if ([serverLogPath length] > 0 &&
      [[NSFileManager defaultManager] fileExistsAtPath:serverLogPath]) {
    serverLogFileName = @"server.log.txt";
    NSString *scenarioLogPath = [scenarioDir stringByAppendingPathComponent:serverLogFileName];
    NSData *serverLogData = [NSData dataWithContentsOfFile:serverLogPath];
    [self writeData:serverLogData toPath:scenarioLogPath];
  }

  NSMutableArray *writtenExtraFiles = [NSMutableArray array];
  for (NSDictionary *artifact in extraArtifacts) {
    NSString *filename = [artifact[@"filename"] isKindOfClass:[NSString class]] ? artifact[@"filename"] : @"artifact.txt";
    NSData *data = [artifact[@"data"] isKindOfClass:[NSData class]] ? artifact[@"data"] : [NSData data];
    NSString *path = [scenarioDir stringByAppendingPathComponent:filename];
    [self writeData:data toPath:path];
    [writtenExtraFiles addObject:@{
      @"label" : [artifact[@"label"] isKindOfClass:[NSString class]] ? artifact[@"label"] : filename,
      @"path" : filename
    }];
  }

  NSString *prettyBody = [[contentType lowercaseString] containsString:@"json"]
                             ? [self prettyPrintedJSONStringFromData:bodyData]
                             : bodyText;
  NSString *reviewHTML = [self reviewPageHTMLForScenario:scenario
                                                 capture:capture
                                                  issues:issues
                                                 rawFile:rawFileName
                                              previewFile:previewFileName
                                             headersFile:headersFileName
                                           serverLogFile:serverLogFileName
                                              extraFiles:writtenExtraFiles
                                               prettyBody:prettyBody];
  NSString *reviewPath = [scenarioDir stringByAppendingPathComponent:@"review.html"];
  [self writeFile:reviewPath content:reviewHTML];

  NSString *presentationKind = [self presentationKindForContentType:contentType];
  NSDictionary *result = @{
    @"id" : scenarioID ?: @"",
    @"title" : title ?: @"",
    @"description" : description ?: @"",
    @"source_surface" : sourceSurface ?: @"",
    @"request" : [scenario[@"request"] isKindOfClass:[NSDictionary class]] ? scenario[@"request"] : @{},
    @"status" : @(status),
    @"content_type" : contentType ?: @"",
    @"presentation_kind" : presentationKind ?: @"unknown",
    @"body_summary" : [self bodySummary:prettyBody],
    @"passed" : @([issues count] == 0),
    @"issues" : issues ?: @[],
    @"raw_path" : [NSString stringWithFormat:@"%@/%@", scenarioID, rawFileName],
    @"review_path" : [NSString stringWithFormat:@"%@/review.html", scenarioID],
    @"preview_path" : ([previewFileName length] > 0)
                          ? [NSString stringWithFormat:@"%@/%@", scenarioID, previewFileName]
                          : @"",
    @"headers_path" : [NSString stringWithFormat:@"%@/%@", scenarioID, headersFileName],
    @"server_log_path" : ([serverLogFileName length] > 0)
                             ? [NSString stringWithFormat:@"%@/%@", scenarioID, serverLogFileName]
                             : @"",
    @"extra_files" : writtenExtraFiles ?: @[],
  };

  NSDictionary *captureRecord = @{
    @"generated_at" : [self isoTimestampNow],
    @"scenario" : scenario ?: @{},
    @"result" : result,
    @"response" : @{
      @"url" : [capture[@"url"] isKindOfClass:[NSString class]] ? capture[@"url"] : @"",
      @"status_line" : [capture[@"status_line"] isKindOfClass:[NSString class]] ? capture[@"status_line"] : @"",
      @"status" : @(status),
      @"content_type" : contentType ?: @"",
      @"headers" : [capture[@"headers"] isKindOfClass:[NSDictionary class]] ? capture[@"headers"] : @{},
      @"curl_exit_code" : capture[@"curl_exit_code"] ?: @0,
      @"body_summary" : [self bodySummary:prettyBody],
    }
  };

  NSError *jsonError = nil;
  NSData *captureData = [NSJSONSerialization dataWithJSONObject:captureRecord
                                                        options:NSJSONWritingPrettyPrinted
                                                          error:&jsonError];
  if (captureData != nil && jsonError == nil) {
    [self writeData:captureData toPath:[scenarioDir stringByAppendingPathComponent:@"capture.json"]];
  } else {
    [issues addObject:[NSString stringWithFormat:@"failed encoding capture.json: %@",
                                                 jsonError.localizedDescription ?: @"unknown"]];
  }

  return result;
}

- (NSDictionary *)resultForRuntimeScenario:(NSDictionary *)scenario
                                   repoRoot:(NSString *)repoRoot
                                   contexts:(NSMutableDictionary *)contexts
                                  outputRoot:(NSString *)outputRoot {
  NSString *environment =
      [scenario[@"environment"] isKindOfClass:[NSString class]] ? scenario[@"environment"] : @"development";
  NSDictionary *context = [self sharedRuntimeContextForEnvironment:environment
                                                          repoRoot:repoRoot
                                                          contexts:contexts];
  NSMutableArray *issues = [NSMutableArray array];
  NSArray *contextIssues = [context[@"issues"] isKindOfClass:[NSArray class]] ? context[@"issues"] : @[];
  [issues addObjectsFromArray:contextIssues];
  if ([context[@"failed"] boolValue]) {
    return [self writeArtifactsForScenario:scenario
                                   capture:@{}
                                  issuesIn:issues
                               outputRoot:outputRoot
                              serverLogPath:[context[@"log_path"] isKindOfClass:[NSString class]] ? context[@"log_path"] : @""
                               extraArtifacts:@[]];
  }

  NSString *baseURL = [context[@"base_url"] isKindOfClass:[NSString class]] ? context[@"base_url"] : @"";
  NSDictionary *request = [scenario[@"request"] isKindOfClass:[NSDictionary class]] ? scenario[@"request"] : @{};
  NSString *path = [request[@"path"] isKindOfClass:[NSString class]] ? request[@"path"] : @"/";
  NSString *accept = [request[@"accept"] isKindOfClass:[NSString class]] ? request[@"accept"] : @"text/html";
  NSDictionary *capture = [self captureURL:[NSString stringWithFormat:@"%@%@", baseURL, path]
                                   headers:@{ @"Accept" : accept }];
  return [self writeArtifactsForScenario:scenario
                                 capture:capture
                                issuesIn:issues
                             outputRoot:outputRoot
                            serverLogPath:[context[@"log_path"] isKindOfClass:[NSString class]] ? context[@"log_path"] : @""
                             extraArtifacts:@[]];
}

- (NSDictionary *)resultForBuildFailureScenario:(NSDictionary *)scenario
                                        repoRoot:(NSString *)repoRoot
                                      outputRoot:(NSString *)outputRoot {
  NSMutableArray *issues = [NSMutableArray array];
  NSString *mode = [scenario[@"build_failure_mode"] isKindOfClass:[NSString class]]
                       ? scenario[@"build_failure_mode"]
                       : @"objc";
  NSDictionary *context = [self startBuildFailureContextForMode:mode
                                                       repoRoot:repoRoot
                                                         issues:issues];
  NSDictionary *capture = @{};
  NSMutableArray *extraArtifacts = [NSMutableArray array];

  @try {
    if (![context[@"failed"] boolValue]) {
      NSString *baseURL =
          [context[@"base_url"] isKindOfClass:[NSString class]] ? context[@"base_url"] : @"";
      NSDictionary *request = [scenario[@"request"] isKindOfClass:[NSDictionary class]] ? scenario[@"request"] : @{};
      NSString *path = [request[@"path"] isKindOfClass:[NSString class]] ? request[@"path"] : @"/";
      NSString *accept = [request[@"accept"] isKindOfClass:[NSString class]] ? request[@"accept"] : @"text/html";
      capture = [self captureURL:[NSString stringWithFormat:@"%@%@", baseURL, path]
                         headers:@{ @"Accept" : accept }];

      NSDictionary *jsonCapture = [self captureURL:[NSString stringWithFormat:@"%@/api/dev/build-error", baseURL]
                                           headers:@{ @"Accept" : @"application/json" }];
      NSData *jsonBody = [jsonCapture[@"body_data"] isKindOfClass:[NSData class]]
                             ? jsonCapture[@"body_data"]
                             : [NSData data];
      [extraArtifacts addObject:@{
        @"label" : @"Supplemental build-error JSON",
        @"filename" : @"build-error.json",
        @"data" : jsonBody
      }];
    }
  } @finally {
    [self stopServerHandle:context];
  }

  [issues addObjectsFromArray:[context[@"issues"] isKindOfClass:[NSArray class]] ? context[@"issues"] : @[]];
  return [self writeArtifactsForScenario:scenario
                                 capture:capture
                                issuesIn:issues
                             outputRoot:outputRoot
                            serverLogPath:[context[@"log_path"] isKindOfClass:[NSString class]] ? context[@"log_path"] : @""
                             extraArtifacts:extraArtifacts];
}

- (NSDictionary *)resultForScenario:(NSDictionary *)scenario
                            repoRoot:(NSString *)repoRoot
                            contexts:(NSMutableDictionary *)contexts
                           outputRoot:(NSString *)outputRoot {
  NSString *mode = [scenario[@"mode"] isKindOfClass:[NSString class]] ? scenario[@"mode"] : @"";
  if ([mode isEqualToString:@"runtime_capture"]) {
    return [self resultForRuntimeScenario:scenario
                                  repoRoot:repoRoot
                                  contexts:contexts
                                 outputRoot:outputRoot];
  }
  if ([mode isEqualToString:@"boomhauer_watch_compile_failure"]) {
    return [self resultForBuildFailureScenario:scenario
                                       repoRoot:repoRoot
                                     outputRoot:outputRoot];
  }

  return [self writeArtifactsForScenario:scenario
                                 capture:@{}
                                issuesIn:@[ [NSString stringWithFormat:@"unknown scenario mode: %@", mode] ]
                             outputRoot:outputRoot
                            serverLogPath:nil
                             extraArtifacts:@[]];
}

- (void)testGenerateBrowserErrorAuditArtifacts {
  NSDictionary *manifest = [self loadFixtureManifest];
  NSArray *scenarios = [manifest[@"scenarios"] isKindOfClass:[NSArray class]] ? manifest[@"scenarios"] : @[];
  NSString *outputRoot = self.auditOutputRoot;

  [[NSFileManager defaultManager] removeItemAtPath:outputRoot error:nil];
  XCTAssertTrue([self ensureDirectoryAtPath:outputRoot]);

  NSMutableDictionary *contexts = [NSMutableDictionary dictionary];
  NSMutableArray *results = [NSMutableArray array];
  @try {
    for (NSDictionary *scenario in scenarios) {
      [results addObject:[self resultForScenario:scenario
                                         repoRoot:self.repoRoot
                                         contexts:contexts
                                        outputRoot:outputRoot]];
    }
  } @finally {
    [self stopSharedContexts:contexts];
  }

  NSString *indexHTML = [self indexHTMLForManifest:manifest results:results];
  XCTAssertTrue([self writeFile:[outputRoot stringByAppendingPathComponent:@"index.html"] content:indexHTML]);

  NSDictionary *summary = @{
    @"schema" : @"browser_error_audit_manifest_v1",
    @"generated_at" : [self isoTimestampNow],
    @"scenario_count" : @([results count]),
    @"results" : results ?: @[]
  };
  NSError *error = nil;
  NSData *summaryData = [NSJSONSerialization dataWithJSONObject:summary
                                                        options:NSJSONWritingPrettyPrinted
                                                          error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([self writeData:summaryData toPath:[outputRoot stringByAppendingPathComponent:@"manifest.json"]]);

  NSMutableArray *failingScenarios = [NSMutableArray array];
  for (NSDictionary *result in results) {
    if (![result[@"passed"] boolValue]) {
      [failingScenarios addObject:result[@"id"] ?: @"unknown"];
    }
  }

  XCTAssertTrue([[NSFileManager defaultManager]
                    fileExistsAtPath:[outputRoot stringByAppendingPathComponent:@"index.html"]]);
  XCTAssertTrue([[NSFileManager defaultManager]
                    fileExistsAtPath:[outputRoot stringByAppendingPathComponent:@"manifest.json"]]);

  if ([failingScenarios count] > 0) {
    XCTFail(@"browser error audit found contract mismatches for %@. Review %@.",
            [failingScenarios componentsJoinedByString:@", "],
            [outputRoot stringByAppendingPathComponent:@"index.html"]);
  }
}

@end
