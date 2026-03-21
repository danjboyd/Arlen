#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <arpa/inet.h>
#import <netinet/in.h>
#import <signal.h>
#import <stdlib.h>
#import <string.h>
#import <sys/socket.h>
#import <unistd.h>

#import "ALNTOTP.h"

@interface Phase13AuthAdminIntegrationTests : XCTestCase
@end

@implementation Phase13AuthAdminIntegrationTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

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

- (NSString *)shellQuoted:(NSString *)value {
  NSString *string = value ?: @"";
  return [NSString stringWithFormat:@"'%@'", [string stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"]];
}

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  NSString *templatePath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-XXXXXX", prefix ?: @"phase13"]];
  char *buffer = strdup([templatePath fileSystemRepresentation]);
  char *created = mkdtemp(buffer);
  NSString *result = created ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:created
                                                                                             length:strlen(created)]
                             : nil;
  free(buffer);
  return result;
}

- (NSString *)createTempFilePathWithPrefix:(NSString *)prefix suffix:(NSString *)suffix {
  NSString *fileName = [NSString stringWithFormat:@"%@-%@%@",
                                                  prefix ?: @"phase13",
                                                  [[NSUUID UUID] UUIDString],
                                                  suffix ?: @""];
  return [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
}

- (BOOL)writeFile:(NSString *)path content:(NSString *)content {
  NSString *directory = [path stringByDeletingLastPathComponent];
  NSError *error = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&error]) {
    XCTFail(@"failed creating %@: %@", directory, error.localizedDescription);
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

- (NSDictionary *)curlJSONAtPort:(int)port
                            path:(NSString *)path
                          method:(NSString *)method
                       cookieJar:(NSString *)cookieJar
                       csrfToken:(NSString *)csrfToken
                         payload:(nullable NSDictionary *)payload
                 followRedirects:(BOOL)followRedirects
                        exitCode:(int *)exitCode {
  NSString *payloadFile = nil;
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  [parts addObject:@"curl -sS"];
  if (followRedirects) {
    [parts addObject:@"-L"];
  }
  [parts addObject:@"-w '\\n%{http_code}'"];
  [parts addObject:[NSString stringWithFormat:@"-X %@", method ?: @"GET"]];
  [parts addObject:@"-H 'Accept: application/json'"];
  if ([cookieJar length] > 0) {
    NSString *quotedJar = [self shellQuoted:cookieJar];
    [parts addObject:[NSString stringWithFormat:@"-b %@", quotedJar]];
    [parts addObject:[NSString stringWithFormat:@"-c %@", quotedJar]];
  }
  if ([csrfToken length] > 0) {
    [parts addObject:[NSString stringWithFormat:@"-H 'X-CSRF-Token: %@'", csrfToken]];
  }
  if ([payload isKindOfClass:[NSDictionary class]]) {
    payloadFile = [self createTempFilePathWithPrefix:@"phase13-json" suffix:@".json"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
    XCTAssertTrue([self writeFile:payloadFile content:body]);
    [parts addObject:@"-H 'Content-Type: application/json'"];
    [parts addObject:[NSString stringWithFormat:@"--data-binary @%@", [self shellQuoted:payloadFile]]];
  }
  [parts addObject:[self shellQuoted:[NSString stringWithFormat:@"http://127.0.0.1:%d%@", port, path ?: @"/"]]];

  NSString *output = [self runShellCapture:[parts componentsJoinedByString:@" "] exitCode:exitCode];
  if ([payloadFile length] > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:payloadFile error:nil];
  }

  NSRange separator = [output rangeOfString:@"\n" options:NSBackwardsSearch];
  NSString *body = output;
  NSInteger statusCode = 0;
  if (separator.location != NSNotFound) {
    body = [output substringToIndex:separator.location];
    statusCode = [[output substringFromIndex:(separator.location + 1)] integerValue];
  }
  return @{
    @"body" : body ?: @"",
    @"status" : @(statusCode),
  };
}

- (NSDictionary *)curlTextAtPort:(int)port
                            path:(NSString *)path
                          method:(NSString *)method
                       cookieJar:(NSString *)cookieJar
                       csrfToken:(NSString *)csrfToken
                      formFields:(nullable NSDictionary *)formFields
                 followRedirects:(BOOL)followRedirects
                        exitCode:(int *)exitCode {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  [parts addObject:@"curl -sS"];
  if (followRedirects) {
    [parts addObject:@"-L"];
  }
  [parts addObject:@"-w '\\n%{http_code}'"];
  [parts addObject:[NSString stringWithFormat:@"-X %@", method ?: @"GET"]];
  if ([cookieJar length] > 0) {
    NSString *quotedJar = [self shellQuoted:cookieJar];
    [parts addObject:[NSString stringWithFormat:@"-b %@", quotedJar]];
    [parts addObject:[NSString stringWithFormat:@"-c %@", quotedJar]];
  }
  NSDictionary *fields = [formFields isKindOfClass:[NSDictionary class]] ? formFields : @{};
  NSMutableDictionary *mergedFields = [NSMutableDictionary dictionaryWithDictionary:fields];
  if ([csrfToken length] > 0) {
    mergedFields[@"csrf_token"] = csrfToken;
  }
  NSArray<NSString *> *sortedKeys = [[mergedFields allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in sortedKeys) {
    NSString *pair = [NSString stringWithFormat:@"%@=%@", key ?: @"", [mergedFields[key] description] ?: @""];
    [parts addObject:[NSString stringWithFormat:@"--data-urlencode %@", [self shellQuoted:pair]]];
  }
  [parts addObject:[self shellQuoted:[NSString stringWithFormat:@"http://127.0.0.1:%d%@", port, path ?: @"/"]]];

  NSString *output = [self runShellCapture:[parts componentsJoinedByString:@" "] exitCode:exitCode];
  NSRange separator = [output rangeOfString:@"\n" options:NSBackwardsSearch];
  NSString *body = output;
  NSInteger statusCode = 0;
  if (separator.location != NSNotFound) {
    body = [output substringToIndex:separator.location];
    statusCode = [[output substringFromIndex:(separator.location + 1)] integerValue];
  }
  return @{
    @"body" : body ?: @"",
    @"status" : @(statusCode),
  };
}

- (NSDictionary *)curlHeadersAtPort:(int)port
                               path:(NSString *)path
                          cookieJar:(NSString *)cookieJar
                      acceptJSON:(BOOL)acceptJSON
                           exitCode:(int *)exitCode {
  NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:@"curl -sS -D - -o /dev/null -w '\\n%{http_code}'"];
  if ([cookieJar length] > 0) {
    NSString *quotedJar = [self shellQuoted:cookieJar];
    [parts addObject:[NSString stringWithFormat:@"-b %@", quotedJar]];
    [parts addObject:[NSString stringWithFormat:@"-c %@", quotedJar]];
  }
  if (acceptJSON) {
    [parts addObject:@"-H 'Accept: application/json'"];
  }
  [parts addObject:[self shellQuoted:[NSString stringWithFormat:@"http://127.0.0.1:%d%@", port, path ?: @"/"]]];
  NSString *output = [self runShellCapture:[parts componentsJoinedByString:@" "] exitCode:exitCode];
  NSRange separator = [output rangeOfString:@"\n" options:NSBackwardsSearch];
  NSString *headers = output;
  NSInteger statusCode = 0;
  if (separator.location != NSNotFound) {
    headers = [output substringToIndex:separator.location];
    statusCode = [[output substringFromIndex:(separator.location + 1)] integerValue];
  }
  return @{
    @"headers" : headers ?: @"",
    @"status" : @(statusCode),
  };
}

- (NSString *)headerValueNamed:(NSString *)name fromHeaderBlock:(NSString *)headerBlock {
  NSString *needle = [[name ?: @"" lowercaseString] stringByAppendingString:@":"];
  for (NSString *line in [headerBlock componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *lower = [trimmed lowercaseString];
    if ([lower hasPrefix:needle]) {
      return [[trimmed substringFromIndex:[needle length]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
  }
  return @"";
}

- (BOOL)waitForServerOnPort:(int)port path:(NSString *)path {
  for (NSInteger attempt = 0; attempt < 50; attempt++) {
    int exitCode = 0;
    NSDictionary *response = [self curlJSONAtPort:port
                                             path:path
                                           method:@"GET"
                                        cookieJar:nil
                                        csrfToken:nil
                                          payload:nil
                                  followRedirects:NO
                                         exitCode:&exitCode];
    NSInteger statusCode = [response[@"status"] integerValue];
    if (exitCode == 0 && statusCode > 0) {
      return YES;
    }
    usleep(200000);
  }
  return NO;
}

- (NSString *)sqlScalar:(NSString *)sql dsn:(NSString *)dsn {
  int exitCode = 0;
  NSString *command = [NSString stringWithFormat:@"psql %@ -Atc %@",
                                                 [self shellQuoted:dsn],
                                                 [self shellQuoted:sql]];
  NSString *output = [self runShellCapture:command exitCode:&exitCode];
  XCTAssertEqual(0, exitCode, @"%@", output);
  return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (BOOL)deleteUserByEmail:(NSString *)email dsn:(NSString *)dsn {
  int exitCode = 0;
  NSString *sql = [NSString stringWithFormat:@"DELETE FROM auth_users WHERE lower(email) = lower('%@');",
                                                [email stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
  NSString *command = [NSString stringWithFormat:@"psql %@ -c %@ >/dev/null 2>&1",
                                                 [self shellQuoted:dsn],
                                                 [self shellQuoted:sql]];
  [self runShellCapture:command exitCode:&exitCode];
  return (exitCode == 0);
}

- (BOOL)writeLiteAppAtRoot:(NSString *)appRoot {
  return [self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                 content:@"#import <Foundation/Foundation.h>\n"
                         "#import \"ArlenServer.h\"\n"
                         "#import \"ALNAdminUIModule.h\"\n"
                         "#import \"ALNContext.h\"\n"
                         "#import \"ALNController.h\"\n\n"
                         "static NSMutableDictionary *Phase13OrderStore(void) {\n"
                         "  static NSMutableDictionary *store = nil;\n"
                         "  if (store == nil) {\n"
                         "    store = [@{\n"
                         "      @\"ord-100\" : [@{ @\"id\" : @\"ord-100\", @\"order_number\" : @\"100\", @\"status\" : @\"pending\", @\"owner_email\" : @\"buyer-one@example.test\", @\"total_cents\" : @1250 } mutableCopy],\n"
                         "      @\"ord-denied\" : [@{ @\"id\" : @\"ord-denied\", @\"order_number\" : @\"denied\", @\"status\" : @\"pending\", @\"owner_email\" : @\"buyer-two@example.test\", @\"total_cents\" : @777 } mutableCopy],\n"
                         "    } mutableCopy];\n"
                         "  }\n"
                         "  return store;\n"
                         "}\n\n"
                         "@interface Phase13AuthAdminOrdersResource : NSObject <ALNAdminUIResource>\n"
                         "@end\n\n"
                         "@implementation Phase13AuthAdminOrdersResource\n"
                         "- (NSString *)adminUIResourceIdentifier { return @\"orders\"; }\n"
                         "- (NSDictionary *)adminUIResourceMetadata {\n"
                         "  return @{ @\"label\" : @\"Orders\", @\"singularLabel\" : @\"Order\", @\"summary\" : @\"Example app-owned admin resource\", @\"identifierField\" : @\"id\", @\"primaryField\" : @\"order_number\", @\"fields\" : @[ @{ @\"name\" : @\"order_number\", @\"label\" : @\"Order\", @\"list\" : @YES, @\"detail\" : @YES }, @{ @\"name\" : @\"status\", @\"label\" : @\"Status\", @\"list\" : @YES, @\"detail\" : @YES, @\"editable\" : @YES }, @{ @\"name\" : @\"total_cents\", @\"label\" : @\"Total\", @\"kind\" : @\"integer\", @\"list\" : @YES, @\"detail\" : @YES }, @{ @\"name\" : @\"owner_email\", @\"label\" : @\"Owner\", @\"kind\" : @\"email\", @\"list\" : @YES, @\"detail\" : @YES } ], @\"filters\" : @[ @{ @\"name\" : @\"q\", @\"label\" : @\"Search\", @\"type\" : @\"search\" } ], @\"actions\" : @[ @{ @\"name\" : @\"mark_reviewed\", @\"label\" : @\"Mark reviewed\", @\"scope\" : @\"row\" } ] };\n"
                         "}\n"
                         "- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query limit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {\n"
                         "  (void)error;\n"
                         "  NSString *search = [(query ?: @\"\") lowercaseString];\n"
                         "  NSArray *keys = [[Phase13OrderStore() allKeys] sortedArrayUsingSelector:@selector(compare:)];\n"
                         "  NSMutableArray *records = [NSMutableArray array];\n"
                         "  for (NSString *key in keys) {\n"
                         "    NSDictionary *record = Phase13OrderStore()[key];\n"
                         "    NSString *haystack = [[NSString stringWithFormat:@\"%@ %@ %@\", record[@\"order_number\"] ?: @\"\", record[@\"status\"] ?: @\"\", record[@\"owner_email\"] ?: @\"\"] lowercaseString];\n"
                         "    if ([search length] > 0 && [haystack rangeOfString:search].location == NSNotFound) { continue; }\n"
                         "    [records addObject:[record copy]];\n"
                         "  }\n"
                         "  NSUInteger start = MIN(offset, [records count]);\n"
                         "  NSUInteger length = MIN(limit, ([records count] - start));\n"
                         "  return [records subarrayWithRange:NSMakeRange(start, length)];\n"
                         "}\n"
                         "- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier error:(NSError **)error {\n"
                         "  NSDictionary *record = [Phase13OrderStore()[identifier ?: @\"\"] copy];\n"
                         "  if (record == nil && error != NULL) { *error = [NSError errorWithDomain:@\"Phase13\" code:404 userInfo:@{ NSLocalizedDescriptionKey : @\"Order not found\" }]; }\n"
                         "  return record;\n"
                         "}\n"
                         "- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier parameters:(NSDictionary *)parameters error:(NSError **)error {\n"
                         "  NSMutableDictionary *record = Phase13OrderStore()[identifier ?: @\"\"];\n"
                         "  if (record == nil) { if (error != NULL) { *error = [NSError errorWithDomain:@\"Phase13\" code:404 userInfo:@{ NSLocalizedDescriptionKey : @\"Order not found\" }]; } return nil; }\n"
                         "  NSString *status = [parameters[@\"status\"] isKindOfClass:[NSString class]] ? parameters[@\"status\"] : @\"\";\n"
                         "  if ([status length] == 0) { if (error != NULL) { *error = [NSError errorWithDomain:@\"Phase13\" code:422 userInfo:@{ NSLocalizedDescriptionKey : @\"status is required\", @\"field\" : @\"status\" }]; } return nil; }\n"
                         "  record[@\"status\"] = status;\n"
                         "  return [record copy];\n"
                         "}\n"
                         "- (BOOL)adminUIResourceAllowsOperation:(NSString *)operation identifier:(NSString *)identifier context:(ALNContext *)context error:(NSError **)error {\n"
                         "  (void)context;\n"
                         "  if ([[operation lowercaseString] isEqualToString:@\"action:mark_reviewed\"] && [identifier isEqualToString:@\"ord-denied\"]) {\n"
                         "    if (error != NULL) { *error = [NSError errorWithDomain:@\"Phase13\" code:403 userInfo:@{ NSLocalizedDescriptionKey : @\"orders policy denied review for this record\" }]; }\n"
                         "    return NO;\n"
                         "  }\n"
                         "  return YES;\n"
                         "}\n"
                         "- (NSDictionary *)adminUIPerformActionNamed:(NSString *)actionName identifier:(NSString *)identifier parameters:(NSDictionary *)parameters error:(NSError **)error {\n"
                         "  (void)parameters;\n"
                         "  NSMutableDictionary *record = Phase13OrderStore()[identifier ?: @\"\"];\n"
                         "  if (record == nil) { if (error != NULL) { *error = [NSError errorWithDomain:@\"Phase13\" code:404 userInfo:@{ NSLocalizedDescriptionKey : @\"Order not found\" }]; } return nil; }\n"
                         "  if (![[actionName lowercaseString] isEqualToString:@\"mark_reviewed\"]) { if (error != NULL) { *error = [NSError errorWithDomain:@\"Phase13\" code:404 userInfo:@{ NSLocalizedDescriptionKey : @\"Action not found\" }]; } return nil; }\n"
                         "  record[@\"status\"] = @\"reviewed\";\n"
                         "  return @{ @\"record\" : [record copy], @\"message\" : @\"Order marked reviewed.\" };\n"
                         "}\n"
                         "@end\n\n"
                         "@interface Phase13AuthAdminOrdersProvider : NSObject <ALNAdminUIResourceProvider>\n"
                         "@end\n\n"
                         "@implementation Phase13AuthAdminOrdersProvider\n"
                         "- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime error:(NSError **)error {\n"
                         "  (void)runtime;\n"
                         "  (void)error;\n"
                         "  return @[ [[Phase13AuthAdminOrdersResource alloc] init] ];\n"
                         "}\n"
                         "@end\n\n"
                         "@interface Phase13AuthAdminController : ALNController\n"
                         "@end\n\n"
                         "@implementation Phase13AuthAdminController\n"
                         "- (id)home:(ALNContext *)ctx { (void)ctx; [self renderText:@\"home\\n\"]; return nil; }\n"
                         "@end\n\n"
                         "static void RegisterRoutes(ALNApplication *app) {\n"
                         "  [app registerRouteMethod:@\"GET\" path:@\"/\" name:@\"home\" controllerClass:[Phase13AuthAdminController class] action:@\"home\"];\n"
                         "}\n\n"
                         "int main(int argc, const char *argv[]) {\n"
                         "  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }\n"
                         "}\n"];
}

- (BOOL)writeBasicAppAtRoot:(NSString *)appRoot
               extraClasses:(NSString *)extraClasses
                   homeText:(NSString *)homeText {
  NSString *content =
      [NSString stringWithFormat:@"#import <Foundation/Foundation.h>\n"
                                 "#import \"ALNAuthModule.h\"\n"
                                 "#import \"ALNContext.h\"\n"
                                 "#import \"ALNController.h\"\n"
                                 "#import \"ArlenServer.h\"\n\n"
                                 "%@\n"
                                 "@interface Phase15AuthUIController : ALNController\n"
                                 "@end\n\n"
                                 "@implementation Phase15AuthUIController\n"
                                 "- (id)home:(ALNContext *)ctx { (void)ctx; [self renderText:@\"%@\\n\"]; return nil; }\n"
                                 "@end\n\n"
                                 "static void RegisterRoutes(ALNApplication *app) {\n"
                                 "  [app registerRouteMethod:@\"GET\" path:@\"/\" name:@\"home\" controllerClass:[Phase15AuthUIController class] action:@\"home\"];\n"
                                 "}\n\n"
                                 "int main(int argc, const char *argv[]) {\n"
                                 "  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }\n"
                                 "}\n",
                                 extraClasses ?: @"",
                                 homeText ?: @"ok"];
  return [self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"] content:content];
}

- (void)testAuthAndAdminModulesInstallMigrateAndServeSharedFlows {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *quotedRepoRoot = [self shellQuoted:repoRoot];
  NSString *quotedArlenBinary = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"build/arlen"]];
  NSString *quotedBoomhauer = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/boomhauer"]];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13-auth-admin"];
  NSString *cookieJar = [self createTempFilePathWithPrefix:@"phase13-cookie" suffix:@".txt"];
  NSString *serverLog = [self createTempFilePathWithPrefix:@"phase13-server" suffix:@".log"];
  NSString *localUUID = [[NSUUID UUID] UUIDString].lowercaseString;
  NSString *providerUUID = [[NSUUID UUID] UUIDString].lowercaseString;
  NSString *localAdminEmail = [NSString stringWithFormat:@"local-admin-%@@example.test", localUUID];
  NSString *providerAdminEmail = [NSString stringWithFormat:@"provider-admin-%@@example.test", providerUUID];
  NSString *localPassword = @"module-password-ok";
  NSString *resetPassword = @"module-password-reset";
  int port = [self randomPort];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSTask *server = nil;

  @try {
    NSString *configContents =
        [NSString stringWithFormat:@"{\n"
                                   "  host = \"127.0.0.1\";\n"
                                   "  port = %d;\n"
                                   "  session = {\n"
                                   "    enabled = YES;\n"
                                   "    secret = \"phase13-auth-admin-session-secret-0123456789abcdef\";\n"
                                   "  };\n"
                                   "  csrf = {\n"
                                   "    enabled = YES;\n"
                                   "    allowQueryParamFallback = YES;\n"
                                   "  };\n"
                                   "  database = {\n"
                                   "    connectionString = \"%@\";\n"
                                   "  };\n"
                                   "  authModule = {\n"
                                   "    bootstrapAdminEmails = (\"%@\", \"%@\");\n"
                                   "    providers = {\n"
                                   "      stub = {\n"
                                   "        enabled = YES;\n"
                                   "        email = \"%@\";\n"
                                   "        displayName = \"Provider Admin\";\n"
                                   "        clientSecret = \"auth-module-stub-provider-secret-0123456789abcdef\";\n"
                                   "      };\n"
                                   "    };\n"
                                   "  };\n"
                                   "  adminUI = {\n"
                                   "    resourceProviders = {\n"
                                   "      classes = (\"Phase13AuthAdminOrdersProvider\");\n"
                                   "    };\n"
                                   "  };\n"
                                   "}\n",
                                   port,
                                   [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""],
                                   localAdminEmail,
                                   providerAdminEmail,
                                   providerAdminEmail];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"] content:configContents]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeLiteAppAtRoot:appRoot]);

    int exitCode = 0;
    NSString *buildOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen eocc",
                                                         quotedRepoRoot]
                     exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", buildOutput);

    NSString *addAuth = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add auth --json",
        [self shellQuoted:appRoot], quotedRepoRoot, quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addAuth);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:addAuth][@"status"]);

    NSString *addAdmin = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add admin-ui --json",
        [self shellQuoted:appRoot], quotedRepoRoot, quotedArlenBinary]
                                       exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addAdmin);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:addAdmin][@"status"]);

    NSString *migrate = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && %@ module migrate --env development --json",
        [self shellQuoted:appRoot], quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", migrate);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:migrate][@"status"]);

    server = [[NSTask alloc] init];
    server.launchPath = @"/bin/bash";
    server.arguments = @[ @"-lc",
                          [NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ --no-watch --port %d >%@ 2>&1",
                                                     [self shellQuoted:appRoot],
                                                     quotedRepoRoot,
                                                     quotedBoomhauer,
                                                     port,
                                                     [self shellQuoted:serverLog]] ];
    [server launch];
    XCTAssertTrue([self waitForServerOnPort:port path:@"/auth/api/session"]);

    NSDictionary *sessionResponse = [self curlJSONAtPort:port
                                                    path:@"/auth/api/session"
                                                  method:@"GET"
                                               cookieJar:cookieJar
                                               csrfToken:nil
                                                 payload:nil
                                         followRedirects:NO
                                                exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [sessionResponse[@"status"] integerValue]);
    NSDictionary *sessionPayload = [self parseJSONDictionary:sessionResponse[@"body"]];
    NSString *csrfToken = [sessionPayload[@"csrf_token"] isKindOfClass:[NSString class]] ? sessionPayload[@"csrf_token"] : @"";
    XCTAssertTrue([csrfToken length] > 0);
    XCTAssertEqualObjects(@NO, sessionPayload[@"authenticated"]);

    NSDictionary *registerResponse = [self curlJSONAtPort:port
                                                     path:@"/auth/api/register"
                                                   method:@"POST"
                                                cookieJar:cookieJar
                                                csrfToken:csrfToken
                                                  payload:@{
                                                    @"email" : localAdminEmail,
                                                    @"display_name" : @"Local Admin",
                                                    @"password" : localPassword,
                                                  }
                                          followRedirects:NO
                                                 exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [registerResponse[@"status"] integerValue]);
    NSDictionary *registerPayload = [self parseJSONDictionary:registerResponse[@"body"]];
    XCTAssertEqualObjects(localAdminEmail, registerPayload[@"user"][@"email"]);
    XCTAssertEqualObjects(@YES, registerPayload[@"authenticated"]);

    NSDictionary *htmlAdminHeaders = [self curlHeadersAtPort:port
                                                        path:@"/admin"
                                                   cookieJar:cookieJar
                                                  acceptJSON:NO
                                                    exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)302, [htmlAdminHeaders[@"status"] integerValue]);
    NSString *location = [self headerValueNamed:@"Location" fromHeaderBlock:htmlAdminHeaders[@"headers"]];
    XCTAssertTrue([location containsString:@"/auth/mfa/totp"]);
    XCTAssertTrue([location containsString:@"return_to="]);

    NSDictionary *preStepUpAdmin = [self curlJSONAtPort:port
                                                   path:@"/admin/api/session"
                                                 method:@"GET"
                                              cookieJar:cookieJar
                                              csrfToken:nil
                                                payload:nil
                                        followRedirects:NO
                                               exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)403, [preStepUpAdmin[@"status"] integerValue]);
    XCTAssertTrue([preStepUpAdmin[@"body"] containsString:@"step_up_required"]);

    NSDictionary *totpEnrollmentPage = [self curlTextAtPort:port
                                                       path:@"/auth/mfa/totp?return_to=/admin"
                                                     method:@"GET"
                                                  cookieJar:cookieJar
                                                  csrfToken:nil
                                                 formFields:nil
                                            followRedirects:NO
                                                   exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [totpEnrollmentPage[@"status"] integerValue]);
    XCTAssertTrue([totpEnrollmentPage[@"body"] containsString:@"data-auth-mfa-flow=\"enrollment\""]);
    XCTAssertTrue([totpEnrollmentPage[@"body"] containsString:@"Manual setup key"]);
    XCTAssertTrue([totpEnrollmentPage[@"body"] containsString:@"auth_totp_qr.js"]);
    XCTAssertFalse([totpEnrollmentPage[@"body"] containsString:@"otpauth://"]);
    NSString *localSecret = [self sqlScalar:[NSString stringWithFormat:
        @"SELECT m.secret FROM auth_mfa_enrollments m JOIN auth_users u ON u.id = m.user_id "
         "WHERE lower(u.email) = lower('%@') ORDER BY m.id DESC LIMIT 1;",
        [localAdminEmail stringByReplacingOccurrencesOfString:@"'" withString:@"''"]]
                                  dsn:dsn];
    XCTAssertTrue([localSecret length] > 0);
    NSString *localCode = [ALNTOTP codeForSecret:localSecret atDate:[NSDate date] error:nil];
    XCTAssertTrue([localCode length] > 0);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *totpResponse = [self curlTextAtPort:port
                                                 path:@"/auth/mfa/totp/verify"
                                               method:@"POST"
                                            cookieJar:cookieJar
                                            csrfToken:csrfToken
                                           formFields:@{
                                             @"code" : localCode,
                                             @"return_to" : @"/admin",
                                           }
                                      followRedirects:NO
                                             exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [totpResponse[@"status"] integerValue]);
    XCTAssertTrue([totpResponse[@"body"] containsString:@"data-auth-mfa-flow=\"recovery_codes\""]);
    XCTAssertTrue([totpResponse[@"body"] containsString:@"Save Your Recovery Codes"]);

    NSDictionary *adminSession = [self curlJSONAtPort:port
                                                 path:@"/admin/api/session"
                                               method:@"GET"
                                            cookieJar:cookieJar
                                            csrfToken:nil
                                              payload:nil
                                      followRedirects:NO
                                             exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [adminSession[@"status"] integerValue]);
    NSDictionary *adminSessionPayload = [self parseJSONDictionary:adminSession[@"body"]];
    XCTAssertEqualObjects(@2, adminSessionPayload[@"session"][@"aal"]);

    NSDictionary *totpChallengePage = [self curlTextAtPort:port
                                                      path:@"/auth/mfa/totp?return_to=/admin"
                                                    method:@"GET"
                                                 cookieJar:cookieJar
                                                 csrfToken:nil
                                                formFields:nil
                                           followRedirects:NO
                                                  exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [totpChallengePage[@"status"] integerValue]);
    XCTAssertTrue([totpChallengePage[@"body"] containsString:@"data-auth-mfa-flow=\"challenge\""]);
    XCTAssertFalse([totpChallengePage[@"body"] containsString:@"Manual setup key"]);
    XCTAssertFalse([totpChallengePage[@"body"] containsString:@"otpauth://"]);

    NSDictionary *resourceCatalog = [self curlJSONAtPort:port
                                                    path:@"/admin/api/resources"
                                                  method:@"GET"
                                               cookieJar:cookieJar
                                               csrfToken:nil
                                                 payload:nil
                                         followRedirects:NO
                                                exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [resourceCatalog[@"status"] integerValue]);
    NSDictionary *resourceCatalogPayload = [self parseJSONDictionary:resourceCatalog[@"body"]];
    NSArray *resourceIdentifiers = [resourceCatalogPayload[@"resources"] valueForKey:@"identifier"];
    XCTAssertTrue([resourceIdentifiers containsObject:@"users"]);
    XCTAssertTrue([resourceIdentifiers containsObject:@"orders"]);

    NSDictionary *ordersMetadata = [self curlJSONAtPort:port
                                                   path:@"/admin/api/resources/orders"
                                                 method:@"GET"
                                              cookieJar:cookieJar
                                              csrfToken:nil
                                                payload:nil
                                        followRedirects:NO
                                               exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [ordersMetadata[@"status"] integerValue]);
    NSDictionary *ordersMetadataPayload = [self parseJSONDictionary:ordersMetadata[@"body"]];
    XCTAssertEqualObjects(@"Orders", ordersMetadataPayload[@"resource"][@"label"]);
    XCTAssertEqualObjects(@"mark_reviewed", ordersMetadataPayload[@"resource"][@"actions"][0][@"name"]);

    NSDictionary *ordersHTML = [self curlJSONAtPort:port
                                               path:@"/admin/resources/orders"
                                             method:@"GET"
                                          cookieJar:cookieJar
                                          csrfToken:nil
                                            payload:nil
                                    followRedirects:NO
                                           exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [ordersHTML[@"status"] integerValue]);
    XCTAssertTrue([ordersHTML[@"body"] containsString:@"Orders"]);

    NSDictionary *adminHTML = [self curlJSONAtPort:port
                                              path:@"/admin"
                                            method:@"GET"
                                         cookieJar:cookieJar
                                         csrfToken:nil
                                           payload:nil
                                   followRedirects:NO
                                          exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [adminHTML[@"status"] integerValue]);
    XCTAssertTrue([adminHTML[@"body"] containsString:@"Arlen Admin"]);

    NSString *encodedSubject =
        [registerPayload[@"subject"] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *adminUpdate = [self curlJSONAtPort:port
                                                path:[NSString stringWithFormat:@"/admin/api/users/%@", encodedSubject ?: @""]
                                              method:@"POST"
                                           cookieJar:cookieJar
                                           csrfToken:csrfToken
                                             payload:@{
                                               @"display_name" : @"Updated Local Admin",
                                             }
                                     followRedirects:NO
                                            exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [adminUpdate[@"status"] integerValue]);
    XCTAssertEqualObjects(@"Updated Local Admin", [self parseJSONDictionary:adminUpdate[@"body"]][@"item"][@"display_name"]);

    NSDictionary *ordersList = [self curlJSONAtPort:port
                                               path:@"/admin/api/resources/orders/items"
                                             method:@"GET"
                                          cookieJar:cookieJar
                                          csrfToken:nil
                                            payload:nil
                                    followRedirects:NO
                                           exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [ordersList[@"status"] integerValue]);
    XCTAssertEqual((NSUInteger)2, [[self parseJSONDictionary:ordersList[@"body"]][@"items"] count]);

    NSDictionary *ordersUpdate = [self curlJSONAtPort:port
                                                 path:@"/admin/api/resources/orders/items/ord-100"
                                               method:@"POST"
                                            cookieJar:cookieJar
                                            csrfToken:csrfToken
                                              payload:@{
                                                @"status" : @"packed",
                                              }
                                      followRedirects:NO
                                             exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [ordersUpdate[@"status"] integerValue]);
    XCTAssertEqualObjects(@"packed", [self parseJSONDictionary:ordersUpdate[@"body"]][@"item"][@"status"]);

    NSDictionary *ordersAction = [self curlJSONAtPort:port
                                                 path:@"/admin/api/resources/orders/items/ord-100/actions/mark_reviewed"
                                               method:@"POST"
                                            cookieJar:cookieJar
                                            csrfToken:csrfToken
                                              payload:@{}
                                      followRedirects:NO
                                             exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [ordersAction[@"status"] integerValue]);
    XCTAssertEqualObjects(@"reviewed", [self parseJSONDictionary:ordersAction[@"body"]][@"result"][@"record"][@"status"]);

    NSDictionary *deniedAction = [self curlJSONAtPort:port
                                                 path:@"/admin/api/resources/orders/items/ord-denied/actions/mark_reviewed"
                                               method:@"POST"
                                            cookieJar:cookieJar
                                            csrfToken:csrfToken
                                              payload:@{}
                                      followRedirects:NO
                                             exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)403, [deniedAction[@"status"] integerValue]);
    XCTAssertTrue([[self parseJSONDictionary:deniedAction[@"body"]][@"message"] length] > 0);

    NSString *verificationToken = [self sqlScalar:[NSString stringWithFormat:
        @"SELECT t.token FROM auth_verification_tokens t JOIN auth_users u ON u.id = t.user_id "
         "WHERE lower(u.email) = lower('%@') ORDER BY t.id DESC LIMIT 1;",
        [localAdminEmail stringByReplacingOccurrencesOfString:@"'" withString:@"''"]]
                                         dsn:dsn];
    XCTAssertTrue([verificationToken length] > 0);
    NSDictionary *verifyResponse = [self curlJSONAtPort:port
                                                   path:[NSString stringWithFormat:@"/auth/api/verify?token=%@", verificationToken]
                                                 method:@"GET"
                                              cookieJar:cookieJar
                                              csrfToken:nil
                                                payload:nil
                                        followRedirects:NO
                                               exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [verifyResponse[@"status"] integerValue]);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:verifyResponse[@"body"]][@"status"]);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *forgotResponse = [self curlJSONAtPort:port
                                                   path:@"/auth/api/password/forgot"
                                                 method:@"POST"
                                              cookieJar:cookieJar
                                              csrfToken:csrfToken
                                                payload:@{
                                                  @"email" : localAdminEmail,
                                                }
                                        followRedirects:NO
                                               exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [forgotResponse[@"status"] integerValue]);

    NSString *resetToken = [self sqlScalar:[NSString stringWithFormat:
        @"SELECT t.token FROM auth_password_reset_tokens t JOIN auth_users u ON u.id = t.user_id "
         "WHERE lower(u.email) = lower('%@') ORDER BY t.id DESC LIMIT 1;",
        [localAdminEmail stringByReplacingOccurrencesOfString:@"'" withString:@"''"]]
                                  dsn:dsn];
    XCTAssertTrue([resetToken length] > 0);
    NSDictionary *resetResponse = [self curlJSONAtPort:port
                                                  path:@"/auth/api/password/reset"
                                                method:@"POST"
                                             cookieJar:cookieJar
                                             csrfToken:csrfToken
                                               payload:@{
                                                 @"token" : resetToken,
                                                 @"password" : resetPassword,
                                               }
                                       followRedirects:NO
                                              exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [resetResponse[@"status"] integerValue]);
    XCTAssertEqualObjects(@YES, [self parseJSONDictionary:resetResponse[@"body"]][@"authenticated"]);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *logoutResponse = [self curlJSONAtPort:port
                                                   path:@"/auth/api/logout"
                                                 method:@"POST"
                                              cookieJar:cookieJar
                                              csrfToken:csrfToken
                                                payload:@{}
                                        followRedirects:NO
                                               exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [logoutResponse[@"status"] integerValue]);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *loginResponse = [self curlJSONAtPort:port
                                                  path:@"/auth/api/login"
                                                method:@"POST"
                                             cookieJar:cookieJar
                                             csrfToken:csrfToken
                                               payload:@{
                                                 @"email" : localAdminEmail,
                                                 @"password" : resetPassword,
                                               }
                                       followRedirects:NO
                                              exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [loginResponse[@"status"] integerValue]);
    XCTAssertEqualObjects(localAdminEmail, [self parseJSONDictionary:loginResponse[@"body"]][@"user"][@"email"]);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";
    (void)[self curlJSONAtPort:port
                          path:@"/auth/api/logout"
                        method:@"POST"
                     cookieJar:cookieJar
                     csrfToken:csrfToken
                       payload:@{}
               followRedirects:NO
                      exitCode:&exitCode];

    NSDictionary *providerStart = [self curlJSONAtPort:port
                                                  path:@"/auth/api/provider/stub/login?return_to=/admin/api/session"
                                                method:@"GET"
                                             cookieJar:cookieJar
                                             csrfToken:nil
                                               payload:nil
                                       followRedirects:NO
                                              exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [providerStart[@"status"] integerValue]);
    NSDictionary *providerStartPayload = [self parseJSONDictionary:providerStart[@"body"]];
    NSURL *authorizeURL = [NSURL URLWithString:providerStartPayload[@"authorize_url"]];
    NSString *authorizePath = [NSString stringWithFormat:@"%@%@",
                                                         authorizeURL.path ?: @"",
                                                         ([authorizeURL query] ?: @"").length > 0 ? [@"?" stringByAppendingString:[authorizeURL query]] : @""];
    NSDictionary *providerResponse = [self curlJSONAtPort:port
                                                     path:authorizePath
                                                   method:@"GET"
                                                cookieJar:cookieJar
                                                csrfToken:nil
                                                  payload:nil
                                          followRedirects:YES
                                                 exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [providerResponse[@"status"] integerValue]);
    NSDictionary *providerPayload = [self parseJSONDictionary:providerResponse[@"body"]];
    XCTAssertEqualObjects(providerAdminEmail, providerPayload[@"normalized_identity"][@"email"]);

    preStepUpAdmin = [self curlJSONAtPort:port
                                     path:@"/admin/api/session"
                                   method:@"GET"
                                cookieJar:cookieJar
                                csrfToken:nil
                                  payload:nil
                          followRedirects:NO
                                 exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)403, [preStepUpAdmin[@"status"] integerValue]);
    XCTAssertTrue([preStepUpAdmin[@"body"] containsString:@"step_up_required"]);

    NSDictionary *providerTOTPState = [self curlJSONAtPort:port
                                                      path:@"/auth/api/mfa/totp"
                                                    method:@"GET"
                                                 cookieJar:cookieJar
                                                 csrfToken:nil
                                                   payload:nil
                                           followRedirects:NO
                                                  exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [providerTOTPState[@"status"] integerValue]);
    NSDictionary *providerTOTPStatePayload = [self parseJSONDictionary:providerTOTPState[@"body"]];
    XCTAssertEqualObjects(@"enrollment", providerTOTPStatePayload[@"flow"][@"state"]);
    XCTAssertEqualObjects(@"totp", providerTOTPStatePayload[@"mfa"][@"factor"]);
    XCTAssertTrue([[providerTOTPStatePayload[@"mfa"][@"provisioning"][@"manual_entry_key"] description] length] > 0);
    XCTAssertTrue([[providerTOTPStatePayload[@"mfa"][@"provisioning"][@"otpauth_uri"] description] length] > 0);
    NSString *providerSecret = [self sqlScalar:[NSString stringWithFormat:
        @"SELECT m.secret FROM auth_mfa_enrollments m JOIN auth_users u ON u.id = m.user_id "
         "WHERE lower(u.email) = lower('%@') ORDER BY m.id DESC LIMIT 1;",
        [providerAdminEmail stringByReplacingOccurrencesOfString:@"'" withString:@"''"]]
                                     dsn:dsn];
    XCTAssertTrue([providerSecret length] > 0);
    NSString *providerCode = [ALNTOTP codeForSecret:providerSecret atDate:[NSDate date] error:nil];
    XCTAssertTrue([providerCode length] > 0);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    totpResponse = [self curlJSONAtPort:port
                                   path:@"/auth/api/mfa/totp/verify"
                                 method:@"POST"
                              cookieJar:cookieJar
                              csrfToken:csrfToken
                                payload:@{
                                  @"code" : providerCode,
                                }
                        followRedirects:NO
                               exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [totpResponse[@"status"] integerValue]);
    NSDictionary *providerVerifyPayload = [self parseJSONDictionary:totpResponse[@"body"]];
    XCTAssertEqualObjects(@"recovery_codes", providerVerifyPayload[@"flow"][@"state"]);
    XCTAssertEqualObjects(@YES, providerVerifyPayload[@"mfa"][@"recovery_codes_present"]);
    XCTAssertEqual((NSUInteger)6, [providerVerifyPayload[@"mfa"][@"recovery_codes"] count]);

    providerTOTPState = [self curlJSONAtPort:port
                                        path:@"/auth/api/mfa/totp"
                                      method:@"GET"
                                   cookieJar:cookieJar
                                   csrfToken:nil
                                     payload:nil
                             followRedirects:NO
                                    exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [providerTOTPState[@"status"] integerValue]);
    providerTOTPStatePayload = [self parseJSONDictionary:providerTOTPState[@"body"]];
    XCTAssertEqualObjects(@"challenge", providerTOTPStatePayload[@"flow"][@"state"]);
    XCTAssertEqual((NSUInteger)0, [providerTOTPStatePayload[@"mfa"][@"provisioning"] count]);

    adminSession = [self curlJSONAtPort:port
                                   path:@"/admin/api/session"
                                 method:@"GET"
                              cookieJar:cookieJar
                              csrfToken:nil
                                payload:nil
                        followRedirects:NO
                               exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [adminSession[@"status"] integerValue]);
    adminSessionPayload = [self parseJSONDictionary:adminSession[@"body"]];
    XCTAssertEqualObjects(providerAdminEmail, adminSessionPayload[@"session"][@"user"][@"email"]);
    XCTAssertEqualObjects(@2, adminSessionPayload[@"session"][@"aal"]);
  } @finally {
    if (server != nil && [server isRunning]) {
      kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    (void)[self deleteUserByEmail:localAdminEmail dsn:dsn];
    (void)[self deleteUserByEmail:providerAdminEmail dsn:dsn];
    [[NSFileManager defaultManager] removeItemAtPath:cookieJar error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:serverLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testAuthRegisterShowsActionableSetupGuidanceWhenModuleMigrationsAreMissing {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *quotedRepoRoot = [self shellQuoted:repoRoot];
  NSString *quotedArlenBinary = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"build/arlen"]];
  NSString *quotedBoomhauer = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/boomhauer"]];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13-auth-migrations-missing"];
  NSString *cookieJar = [self createTempFilePathWithPrefix:@"phase13-auth-migrations-cookie" suffix:@".txt"];
  NSString *serverLog = [self createTempFilePathWithPrefix:@"phase13-auth-migrations-server" suffix:@".log"];
  int port = [self randomPort];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSTask *server = nil;

  @try {
    NSString *configContents =
        [NSString stringWithFormat:@"{\n"
                                   "  host = \"127.0.0.1\";\n"
                                   "  port = %d;\n"
                                   "  session = {\n"
                                   "    enabled = YES;\n"
                                   "    secret = \"phase13-auth-migrations-missing-secret-0123456789abcdef\";\n"
                                   "  };\n"
                                   "  csrf = {\n"
                                   "    enabled = YES;\n"
                                   "    allowQueryParamFallback = YES;\n"
                                   "  };\n"
                                   "  database = {\n"
                                   "    connectionString = \"%@\";\n"
                                   "  };\n"
                                   "}\n",
                                   port,
                                   [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"] content:configContents]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeBasicAppAtRoot:appRoot extraClasses:nil homeText:@"phase13-auth-migrations-missing"]);

    int exitCode = 0;
    NSString *buildOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen eocc",
                                                         quotedRepoRoot]
                     exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", buildOutput);

    NSString *addAuth = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add auth --json",
        [self shellQuoted:appRoot], quotedRepoRoot, quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addAuth);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:addAuth][@"status"]);

    server = [[NSTask alloc] init];
    server.launchPath = @"/bin/bash";
    server.arguments = @[ @"-lc",
                          [NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ --no-watch --port %d >%@ 2>&1",
                                                     [self shellQuoted:appRoot],
                                                     quotedRepoRoot,
                                                     quotedBoomhauer,
                                                     port,
                                                     [self shellQuoted:serverLog]] ];
    [server launch];
    XCTAssertTrue([self waitForServerOnPort:port path:@"/auth/api/session"]);

    NSDictionary *sessionResponse = [self curlJSONAtPort:port
                                                    path:@"/auth/api/session"
                                                  method:@"GET"
                                               cookieJar:cookieJar
                                               csrfToken:nil
                                                 payload:nil
                                         followRedirects:NO
                                                exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    NSString *csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";
    XCTAssertTrue([csrfToken length] > 0);

    NSDictionary *registerResponse = [self curlTextAtPort:port
                                                     path:@"/auth/register"
                                                   method:@"POST"
                                                cookieJar:cookieJar
                                                csrfToken:csrfToken
                                               formFields:@{
                                                 @"email" : @"missing-migrations@example.test",
                                                 @"display_name" : @"Missing Migrations",
                                                 @"password" : @"module-password-ok",
                                               }
                                          followRedirects:NO
                                                 exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)422, [registerResponse[@"status"] integerValue]);
    XCTAssertTrue([registerResponse[@"body"] containsString:@"Auth module tables are missing."]);
    XCTAssertTrue([registerResponse[@"body"] containsString:@"./bin/arlen module migrate --env development"]);
    XCTAssertFalse([registerResponse[@"body"] containsString:@"query did not return rows"]);
  } @finally {
    if (server != nil && [server isRunning]) {
      kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    [[NSFileManager defaultManager] removeItemAtPath:cookieJar error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:serverLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testAuthModuleHidesAndUnregistersDisabledProviderAffordances {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *quotedRepoRoot = [self shellQuoted:repoRoot];
  NSString *quotedArlenBinary = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"build/arlen"]];
  NSString *quotedBoomhauer = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/boomhauer"]];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13-auth-disabled-provider"];
  NSString *cookieJar = [self createTempFilePathWithPrefix:@"phase13-disabled-provider-cookie" suffix:@".txt"];
  NSString *serverLog = [self createTempFilePathWithPrefix:@"phase13-disabled-provider-server" suffix:@".log"];
  int port = [self randomPort];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSTask *server = nil;

  @try {
    NSString *configContents =
        [NSString stringWithFormat:@"{\n"
                                   "  host = \"127.0.0.1\";\n"
                                   "  port = %d;\n"
                                   "  session = {\n"
                                   "    enabled = YES;\n"
                                   "    secret = \"phase13-auth-disabled-provider-session-secret-0123456789abcdef\";\n"
                                   "  };\n"
                                   "  csrf = {\n"
                                   "    enabled = YES;\n"
                                   "    allowQueryParamFallback = YES;\n"
                                   "  };\n"
                                   "  database = {\n"
                                   "    connectionString = \"%@\";\n"
                                   "  };\n"
                                   "  authModule = {\n"
                                   "    providers = {\n"
                                   "      stub = {\n"
                                   "        enabled = NO;\n"
                                   "      };\n"
                                   "    };\n"
                                   "  };\n"
                                   "}\n",
                                   port,
                                   [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"] content:configContents]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeLiteAppAtRoot:appRoot]);

    int exitCode = 0;
    NSString *buildOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen eocc",
                                                         quotedRepoRoot]
                     exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", buildOutput);

    NSString *addAuth = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add auth --json",
        [self shellQuoted:appRoot], quotedRepoRoot, quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addAuth);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:addAuth][@"status"]);

    server = [[NSTask alloc] init];
    server.launchPath = @"/bin/bash";
    server.arguments = @[ @"-lc",
                          [NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ --no-watch --port %d >%@ 2>&1",
                                                     [self shellQuoted:appRoot],
                                                     quotedRepoRoot,
                                                     quotedBoomhauer,
                                                     port,
                                                     [self shellQuoted:serverLog]] ];
    [server launch];
    XCTAssertTrue([self waitForServerOnPort:port path:@"/auth/api/session"]);

    NSDictionary *loginPage = [self curlJSONAtPort:port
                                              path:@"/auth/login"
                                            method:@"GET"
                                         cookieJar:cookieJar
                                         csrfToken:nil
                                           payload:nil
                                   followRedirects:NO
                                          exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [loginPage[@"status"] integerValue]);
    XCTAssertFalse([loginPage[@"body"] containsString:@"Continue with Stub OIDC"]);

    NSDictionary *sessionResponse = [self curlJSONAtPort:port
                                                    path:@"/auth/api/session"
                                                  method:@"GET"
                                               cookieJar:cookieJar
                                               csrfToken:nil
                                                 payload:nil
                                         followRedirects:NO
                                                exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [sessionResponse[@"status"] integerValue]);
    NSDictionary *sessionPayload = [self parseJSONDictionary:sessionResponse[@"body"]];
    XCTAssertEqualObjects((@[]), sessionPayload[@"login_providers"]);

    NSDictionary *providerStart = [self curlJSONAtPort:port
                                                  path:@"/auth/provider/stub/login"
                                                method:@"GET"
                                             cookieJar:cookieJar
                                             csrfToken:nil
                                               payload:nil
                                       followRedirects:NO
                                              exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)404, [providerStart[@"status"] integerValue]);

    NSDictionary *providerAPIStart = [self curlJSONAtPort:port
                                                     path:@"/auth/api/provider/stub/login"
                                                   method:@"GET"
                                                cookieJar:cookieJar
                                                csrfToken:nil
                                                  payload:nil
                                          followRedirects:NO
                                                 exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)404, [providerAPIStart[@"status"] integerValue]);
  } @finally {
    if (server != nil && [server isRunning]) {
      kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    [[NSFileManager defaultManager] removeItemAtPath:cookieJar error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:serverLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testAuthModuleHeadlessModeKeepsAPIAndProviderRoutesWhileSuppressingHTMLPages {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *quotedRepoRoot = [self shellQuoted:repoRoot];
  NSString *quotedArlenBinary = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"build/arlen"]];
  NSString *quotedBoomhauer = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/boomhauer"]];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase15-auth-headless"];
  NSString *cookieJar = [self createTempFilePathWithPrefix:@"phase15-auth-headless-cookie" suffix:@".txt"];
  NSString *serverLog = [self createTempFilePathWithPrefix:@"phase15-auth-headless-server" suffix:@".log"];
  int port = [self randomPort];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSTask *server = nil;

  @try {
    NSString *configContents =
        [NSString stringWithFormat:@"{\n"
                                   "  host = \"127.0.0.1\";\n"
                                   "  port = %d;\n"
                                   "  session = {\n"
                                   "    enabled = YES;\n"
                                   "    secret = \"phase15-auth-headless-session-secret-0123456789abcdef\";\n"
                                   "  };\n"
                                   "  csrf = {\n"
                                   "    enabled = YES;\n"
                                   "    allowQueryParamFallback = YES;\n"
                                   "  };\n"
                                   "  database = {\n"
                                   "    connectionString = \"%@\";\n"
                                   "  };\n"
                                   "  authModule = {\n"
                                   "    ui = {\n"
                                   "      mode = \"headless\";\n"
                                   "    };\n"
                                   "  };\n"
                                   "}\n",
                                   port,
                                   [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"] content:configContents]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeBasicAppAtRoot:appRoot extraClasses:nil homeText:@"phase15-headless"]);

    int exitCode = 0;
    NSString *buildOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen eocc",
                                                         quotedRepoRoot]
                     exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", buildOutput);

    NSString *addAuth = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add auth --json",
        [self shellQuoted:appRoot], quotedRepoRoot, quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addAuth);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:addAuth][@"status"]);

    server = [[NSTask alloc] init];
    server.launchPath = @"/bin/bash";
    server.arguments = @[ @"-lc",
                          [NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ --no-watch --port %d >%@ 2>&1",
                                                     [self shellQuoted:appRoot],
                                                     quotedRepoRoot,
                                                     quotedBoomhauer,
                                                     port,
                                                     [self shellQuoted:serverLog]] ];
    [server launch];
    XCTAssertTrue([self waitForServerOnPort:port path:@"/auth/api/session"]);

    NSDictionary *loginPage = [self curlJSONAtPort:port
                                              path:@"/auth/login"
                                            method:@"GET"
                                         cookieJar:cookieJar
                                         csrfToken:nil
                                           payload:nil
                                   followRedirects:NO
                                          exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)404, [loginPage[@"status"] integerValue]);

    NSDictionary *registerPage = [self curlJSONAtPort:port
                                                 path:@"/auth/register"
                                               method:@"GET"
                                            cookieJar:cookieJar
                                            csrfToken:nil
                                              payload:nil
                                      followRedirects:NO
                                             exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)404, [registerPage[@"status"] integerValue]);

    NSDictionary *sessionResponse = [self curlJSONAtPort:port
                                                    path:@"/auth/api/session"
                                                  method:@"GET"
                                               cookieJar:cookieJar
                                               csrfToken:nil
                                                 payload:nil
                                         followRedirects:NO
                                                exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [sessionResponse[@"status"] integerValue]);
    NSDictionary *sessionPayload = [self parseJSONDictionary:sessionResponse[@"body"]];
    XCTAssertEqualObjects(@"headless", sessionPayload[@"ui_mode"]);
    XCTAssertEqualObjects(@NO, sessionPayload[@"authenticated"]);

    NSDictionary *providerStart = [self curlJSONAtPort:port
                                                  path:@"/auth/api/provider/stub/login"
                                                method:@"GET"
                                             cookieJar:cookieJar
                                             csrfToken:nil
                                               payload:nil
                                       followRedirects:NO
                                              exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [providerStart[@"status"] integerValue]);
    NSDictionary *providerPayload = [self parseJSONDictionary:providerStart[@"body"]];
    XCTAssertTrue([[providerPayload[@"authorize_url"] description] containsString:@"/auth/api/provider/stub/authorize"]);
  } @finally {
    if (server != nil && [server isRunning]) {
      kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    [[NSFileManager defaultManager] removeItemAtPath:cookieJar error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:serverLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testAuthModuleFragmentsRenderInsideAppOwnedAccountSecurityPage {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *quotedRepoRoot = [self shellQuoted:repoRoot];
  NSString *quotedArlenBinary = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"build/arlen"]];
  NSString *quotedBoomhauer = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/boomhauer"]];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase18-auth-fragments"];
  NSString *cookieJar = [self createTempFilePathWithPrefix:@"phase18-auth-fragments-cookie" suffix:@".txt"];
  NSString *serverLog = [self createTempFilePathWithPrefix:@"phase18-auth-fragments-server" suffix:@".log"];
  NSString *userEmail = [NSString stringWithFormat:@"phase18-fragments-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSString *password = @"module-password-ok";
  int port = [self randomPort];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSTask *server = nil;

  @try {
    NSString *configContents =
        [NSString stringWithFormat:@"{\n"
                                   "  host = \"127.0.0.1\";\n"
                                   "  port = %d;\n"
                                   "  session = {\n"
                                   "    enabled = YES;\n"
                                   "    secret = \"phase18-auth-fragments-session-secret-0123456789abcdef\";\n"
                                   "  };\n"
                                   "  csrf = {\n"
                                   "    enabled = YES;\n"
                                   "    allowQueryParamFallback = YES;\n"
                                   "  };\n"
                                   "  database = {\n"
                                   "    connectionString = \"%@\";\n"
                                   "  };\n"
                                   "  authModule = {\n"
                                   "    ui = {\n"
                                   "      mode = \"module-ui\";\n"
                                   "    };\n"
                                   "    mfa = {\n"
                                   "      sms = {\n"
                                   "        enabled = YES;\n"
                                   "        allowPrimaryFactor = YES;\n"
                                   "        testVerificationCode = \"123456\";\n"
                                   "      };\n"
                                   "    };\n"
                                   "  };\n"
                                   "}\n",
                                   port,
                                   [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"] content:configContents]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"app_lite.m"]
                          content:@"#import <Foundation/Foundation.h>\n"
                                  "#import \"ALNAuthModule.h\"\n"
                                  "#import \"ALNContext.h\"\n"
                                  "#import \"ALNController.h\"\n"
                                  "#import \"ArlenServer.h\"\n\n"
                                  "@interface Phase18SecurityController : ALNController\n"
                                  "@end\n\n"
                                  "@implementation Phase18SecurityController\n"
                                  "- (id)home:(ALNContext *)ctx { (void)ctx; [self renderText:@\"phase18-home\\n\"]; return nil; }\n"
                                  "- (id)security:(ALNContext *)ctx {\n"
                                  "  NSError *error = nil;\n"
                                  "  NSDictionary *authContext = [[ALNAuthModuleRuntime sharedRuntime] mfaManagementFragmentContextForCurrentUserInContext:ctx\n"
                                  "                                                                                                                  returnTo:@\"/account/security\"\n"
                                  "                                                                                                                     error:&error];\n"
                                  "  if (authContext == nil) {\n"
                                  "    [self setStatus:401];\n"
                                  "    [self renderText:@\"authentication required\\n\"];\n"
                                  "    return nil;\n"
                                  "  }\n"
                                  "  NSMutableDictionary *renderContext = [NSMutableDictionary dictionaryWithDictionary:authContext ?: @{}];\n"
                                  "  renderContext[@\"csrfToken\"] = [self csrfToken] ?: @\"\";\n"
                                  "  if (![self renderTemplate:@\"account/security\" context:renderContext layout:nil error:&error]) {\n"
                                  "    [self setStatus:500];\n"
                                  "    [self renderText:[[error localizedDescription] ?: @\"render failed\" stringByAppendingString:@\"\\n\"]];\n"
                                  "  }\n"
                                  "  return nil;\n"
                                  "}\n"
                                  "@end\n\n"
                                  "static void RegisterRoutes(ALNApplication *app) {\n"
                                  "  [app registerRouteMethod:@\"GET\" path:@\"/\" name:@\"home\" controllerClass:[Phase18SecurityController class] action:@\"home\"];\n"
                                  "  [app registerRouteMethod:@\"GET\" path:@\"/account/security\" name:@\"account_security\" controllerClass:[Phase18SecurityController class] action:@\"security\"];\n"
                                  "}\n\n"
                                  "int main(int argc, const char *argv[]) {\n"
                                  "  @autoreleasepool { return ALNRunAppMain(argc, argv, &RegisterRoutes); }\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"templates/account/security.html.eoc"]
                          content:@"<section class=\"phase18-account-security\">\n"
                                  "  <h1>Account Security</h1>\n"
                                  "  <% if (!ALNEOCInclude(out, ctx, @\"modules/auth/fragments/mfa_factor_inventory_panel\", error)) { return nil; } %>\n"
                                  "  <% if ([[ctx objectForKey:@\"authTOTPNeedsEnrollment\"] boolValue]) { %>\n"
                                  "    <% if (!ALNEOCInclude(out, ctx, @\"modules/auth/fragments/mfa_enrollment_panel\", error)) { return nil; } %>\n"
                                  "  <% } %>\n"
                                  "  <% if ([[[ctx objectForKey:@\"authSMSState\"] objectForKey:@\"enabled\"] boolValue]) { %>\n"
                                  "    <% if (!ALNEOCInclude(out, ctx, @\"modules/auth/fragments/mfa_sms_enrollment_panel\", error)) { return nil; } %>\n"
                                  "  <% } %>\n"
                                  "</section>\n"]);

    int exitCode = 0;
    NSString *buildOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen eocc",
                                                         quotedRepoRoot]
                     exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", buildOutput);

    NSString *addAuth = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add auth --json",
        [self shellQuoted:appRoot], quotedRepoRoot, quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addAuth);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:addAuth][@"status"]);

    NSString *migrate = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && %@ module migrate --env development --json",
        [self shellQuoted:appRoot], quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", migrate);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:migrate][@"status"]);

    server = [[NSTask alloc] init];
    server.launchPath = @"/bin/bash";
    server.arguments = @[ @"-lc",
                          [NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ --no-watch --port %d >%@ 2>&1",
                                                     [self shellQuoted:appRoot],
                                                     quotedRepoRoot,
                                                     quotedBoomhauer,
                                                     port,
                                                     [self shellQuoted:serverLog]] ];
    [server launch];
    XCTAssertTrue([self waitForServerOnPort:port path:@"/auth/api/session"]);

    int curlExitCode = 0;
    NSDictionary *sessionResponse = [self curlJSONAtPort:port
                                                    path:@"/auth/api/session"
                                                  method:@"GET"
                                               cookieJar:cookieJar
                                               csrfToken:nil
                                                 payload:nil
                                         followRedirects:NO
                                                exitCode:&curlExitCode];
    XCTAssertEqual(0, curlExitCode);
    NSString *csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *registerResponse = [self curlJSONAtPort:port
                                                     path:@"/auth/api/register"
                                                   method:@"POST"
                                                cookieJar:cookieJar
                                                csrfToken:csrfToken
                                                  payload:@{
                                                    @"email" : userEmail,
                                                    @"display_name" : @"Phase18 Fragment User",
                                                    @"password" : password,
                                                  }
                                          followRedirects:NO
                                                 exitCode:&curlExitCode];
    XCTAssertEqual(0, curlExitCode);
    XCTAssertEqual((NSInteger)200, [registerResponse[@"status"] integerValue]);

    NSDictionary *securityPage = [self curlTextAtPort:port
                                                 path:@"/account/security"
                                               method:@"GET"
                                            cookieJar:cookieJar
                                            csrfToken:nil
                                           formFields:nil
                                      followRedirects:NO
                                             exitCode:&curlExitCode];
    XCTAssertEqual(0, curlExitCode);
    XCTAssertEqual((NSInteger)200, [securityPage[@"status"] integerValue]);
    XCTAssertTrue([securityPage[@"body"] containsString:@"Account Security"]);
    XCTAssertTrue([securityPage[@"body"] containsString:@"Authenticator app"]);
    XCTAssertTrue([securityPage[@"body"] containsString:@"SMS"]);
    XCTAssertTrue([securityPage[@"body"] containsString:@"Manual setup key"]);
    XCTAssertTrue([securityPage[@"body"] containsString:@"data-auth-mfa-flow=\"sms_manage\""]);

    NSString *secret = [self sqlScalar:[NSString stringWithFormat:
        @"SELECT m.secret FROM auth_mfa_enrollments m JOIN auth_users u ON u.id = m.user_id "
         "WHERE lower(u.email) = lower('%@') ORDER BY m.id DESC LIMIT 1;",
        [userEmail stringByReplacingOccurrencesOfString:@"'" withString:@"''"]]
                                  dsn:dsn];
    XCTAssertTrue([secret length] > 0);
    NSString *code = [ALNTOTP codeForSecret:secret atDate:[NSDate date] error:nil];
    XCTAssertTrue([code length] > 0);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&curlExitCode];
    XCTAssertEqual(0, curlExitCode);
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *verifyResponse = [self curlJSONAtPort:port
                                                   path:@"/auth/api/mfa/totp/verify"
                                                 method:@"POST"
                                              cookieJar:cookieJar
                                              csrfToken:csrfToken
                                                payload:@{
                                                  @"code" : code,
                                                  @"return_to" : @"/account/security",
                                                }
                                        followRedirects:NO
                                               exitCode:&curlExitCode];
    XCTAssertEqual(0, curlExitCode);
    XCTAssertEqual((NSInteger)200, [verifyResponse[@"status"] integerValue]);

    securityPage = [self curlTextAtPort:port
                                   path:@"/account/security"
                                 method:@"GET"
                              cookieJar:cookieJar
                              csrfToken:nil
                             formFields:nil
                        followRedirects:NO
                               exitCode:&curlExitCode];
    XCTAssertEqual(0, curlExitCode);
    XCTAssertEqual((NSInteger)200, [securityPage[@"status"] integerValue]);
    XCTAssertTrue([securityPage[@"body"] containsString:@"Authenticator app"]);
    XCTAssertTrue([securityPage[@"body"] containsString:@"SMS"]);
    XCTAssertFalse([securityPage[@"body"] containsString:@"Manual setup key"]);
  } @finally {
    if (server != nil && [server isRunning]) {
      kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    (void)[self deleteUserByEmail:userEmail dsn:dsn];
    [[NSFileManager defaultManager] removeItemAtPath:cookieJar error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:serverLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testAuthModuleHidesSMSSurfacesWhenDisabledByDefault {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *quotedRepoRoot = [self shellQuoted:repoRoot];
  NSString *quotedArlenBinary = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"build/arlen"]];
  NSString *quotedBoomhauer = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/boomhauer"]];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase18-auth-sms-disabled"];
  NSString *cookieJar = [self createTempFilePathWithPrefix:@"phase18-auth-sms-disabled-cookie" suffix:@".txt"];
  NSString *serverLog = [self createTempFilePathWithPrefix:@"phase18-auth-sms-disabled-server" suffix:@".log"];
  NSString *userEmail = [NSString stringWithFormat:@"phase18-sms-disabled-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSString *password = @"module-password-ok";
  int port = [self randomPort];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSTask *server = nil;

  @try {
    NSString *configContents =
        [NSString stringWithFormat:@"{\n"
                                   "  host = \"127.0.0.1\";\n"
                                   "  port = %d;\n"
                                   "  session = {\n"
                                   "    enabled = YES;\n"
                                   "    secret = \"phase18-auth-sms-disabled-session-secret-0123456789abcdef\";\n"
                                   "  };\n"
                                   "  csrf = {\n"
                                   "    enabled = YES;\n"
                                   "    allowQueryParamFallback = YES;\n"
                                   "  };\n"
                                   "  database = {\n"
                                   "    connectionString = \"%@\";\n"
                                   "  };\n"
                                   "}\n",
                                   port,
                                   [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"] content:configContents]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"] content:@"{}\n"]);
    XCTAssertTrue([self writeBasicAppAtRoot:appRoot extraClasses:nil homeText:@"phase18-sms-disabled"]);

    int exitCode = 0;
    NSString *buildOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen eocc",
                                                         quotedRepoRoot]
                     exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", buildOutput);

    NSString *addAuth = [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add auth --json",
                                                                        [self shellQuoted:appRoot],
                                                                        quotedRepoRoot,
                                                                        quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addAuth);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:addAuth][@"status"]);

    server = [[NSTask alloc] init];
    server.launchPath = @"/bin/bash";
    server.arguments = @[ @"-lc",
                          [NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ --no-watch --port %d >%@ 2>&1",
                                                     [self shellQuoted:appRoot],
                                                     quotedRepoRoot,
                                                     quotedBoomhauer,
                                                     port,
                                                     [self shellQuoted:serverLog]] ];
    [server launch];
    XCTAssertTrue([self waitForServerOnPort:port path:@"/auth/api/session"]);

    NSDictionary *sessionResponse = [self curlJSONAtPort:port
                                                    path:@"/auth/api/session"
                                                  method:@"GET"
                                               cookieJar:cookieJar
                                               csrfToken:nil
                                                 payload:nil
                                         followRedirects:NO
                                                exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    NSString *csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *registerResponse = [self curlJSONAtPort:port
                                                     path:@"/auth/api/register"
                                                   method:@"POST"
                                                cookieJar:cookieJar
                                                csrfToken:csrfToken
                                                  payload:@{
                                                    @"email" : userEmail,
                                                    @"display_name" : @"Phase 18 SMS Disabled",
                                                    @"password" : password,
                                                  }
                                          followRedirects:NO
                                                 exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [registerResponse[@"status"] integerValue]);

    NSDictionary *mfaResponse = [self curlJSONAtPort:port
                                                path:@"/auth/api/mfa"
                                              method:@"GET"
                                           cookieJar:cookieJar
                                           csrfToken:nil
                                             payload:nil
                                     followRedirects:NO
                                            exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [mfaResponse[@"status"] integerValue]);
    NSDictionary *mfaPayload = [self parseJSONDictionary:mfaResponse[@"body"]];
    XCTAssertEqualObjects(@NO, mfaPayload[@"policy"][@"sms"][@"enabled"]);
    XCTAssertEqualObjects(@"", mfaPayload[@"paths"][@"sms"]);
    XCTAssertEqual((NSUInteger)1, [mfaPayload[@"factors"] count]);

    NSDictionary *mfaPage = [self curlTextAtPort:port
                                            path:@"/auth/mfa"
                                          method:@"GET"
                                       cookieJar:cookieJar
                                       csrfToken:nil
                                      formFields:nil
                                 followRedirects:NO
                                        exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [mfaPage[@"status"] integerValue]);
    XCTAssertTrue([mfaPage[@"body"] containsString:@"Authenticator app"]);
    XCTAssertFalse([mfaPage[@"body"] containsString:@"SMS can be useful as a fallback"]);
    XCTAssertFalse([mfaPage[@"body"] containsString:@"data-auth-mfa-flow=\"sms_manage\""]);

    NSDictionary *missingSMSAPI = [self curlJSONAtPort:port
                                                  path:@"/auth/api/mfa/sms"
                                                method:@"GET"
                                             cookieJar:cookieJar
                                             csrfToken:nil
                                               payload:nil
                                       followRedirects:NO
                                              exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)404, [missingSMSAPI[@"status"] integerValue]);
  } @finally {
    if (server != nil && [server isRunning]) {
      kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    (void)[self deleteUserByEmail:userEmail dsn:dsn];
    [[NSFileManager defaultManager] removeItemAtPath:cookieJar error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:serverLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testAuthModuleSupportsSMSFactorManagementAndKeepsTOTPPreferred {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *quotedRepoRoot = [self shellQuoted:repoRoot];
  NSString *quotedArlenBinary = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"build/arlen"]];
  NSString *quotedBoomhauer = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/boomhauer"]];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase18-auth-sms-enabled"];
  NSString *cookieJar = [self createTempFilePathWithPrefix:@"phase18-auth-sms-enabled-cookie" suffix:@".txt"];
  NSString *serverLog = [self createTempFilePathWithPrefix:@"phase18-auth-sms-enabled-server" suffix:@".log"];
  NSString *userEmail = [NSString stringWithFormat:@"phase18-sms-enabled-%@@example.test", [[NSUUID UUID] UUIDString].lowercaseString];
  NSString *password = @"module-password-ok";
  NSString *smsCode = @"123456";
  NSString *phoneNumber = @"+15555550199";
  int port = [self randomPort];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSTask *server = nil;

  @try {
    NSString *configContents =
        [NSString stringWithFormat:@"{\n"
                                   "  host = \"127.0.0.1\";\n"
                                   "  port = %d;\n"
                                   "  session = {\n"
                                   "    enabled = YES;\n"
                                   "    secret = \"phase18-auth-sms-enabled-session-secret-0123456789abcdef\";\n"
                                   "  };\n"
                                   "  csrf = {\n"
                                   "    enabled = YES;\n"
                                   "    allowQueryParamFallback = YES;\n"
                                   "  };\n"
                                   "  database = {\n"
                                   "    connectionString = \"%@\";\n"
                                   "  };\n"
                                   "  authModule = {\n"
                                   "    mfa = {\n"
                                   "      sms = {\n"
                                   "        enabled = YES;\n"
                                   "        allowPrimaryFactor = YES;\n"
                                   "        testVerificationCode = \"%@\";\n"
                                   "      };\n"
                                   "    };\n"
                                   "  };\n"
                                   "}\n",
                                   port,
                                   [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""],
                                   smsCode];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"] content:configContents]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"] content:@"{}\n"]);
    XCTAssertTrue([self writeBasicAppAtRoot:appRoot extraClasses:nil homeText:@"phase18-sms-enabled"]);

    int exitCode = 0;
    NSString *buildOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen eocc",
                                                         quotedRepoRoot]
                     exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", buildOutput);

    NSString *addAuth = [self runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add auth --json",
                                                                        [self shellQuoted:appRoot],
                                                                        quotedRepoRoot,
                                                                        quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addAuth);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:addAuth][@"status"]);

    server = [[NSTask alloc] init];
    server.launchPath = @"/bin/bash";
    server.arguments = @[ @"-lc",
                          [NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ --no-watch --port %d >%@ 2>&1",
                                                     [self shellQuoted:appRoot],
                                                     quotedRepoRoot,
                                                     quotedBoomhauer,
                                                     port,
                                                     [self shellQuoted:serverLog]] ];
    [server launch];
    XCTAssertTrue([self waitForServerOnPort:port path:@"/auth/api/session"]);

    NSDictionary *sessionResponse = [self curlJSONAtPort:port
                                                    path:@"/auth/api/session"
                                                  method:@"GET"
                                               cookieJar:cookieJar
                                               csrfToken:nil
                                                 payload:nil
                                         followRedirects:NO
                                                exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    NSString *csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *registerResponse = [self curlJSONAtPort:port
                                                     path:@"/auth/api/register"
                                                   method:@"POST"
                                                cookieJar:cookieJar
                                                csrfToken:csrfToken
                                                  payload:@{
                                                    @"email" : userEmail,
                                                    @"display_name" : @"Phase 18 SMS Enabled",
                                                    @"password" : password,
                                                  }
                                          followRedirects:NO
                                                 exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [registerResponse[@"status"] integerValue]);

    NSDictionary *mfaPage = [self curlTextAtPort:port
                                            path:@"/auth/mfa"
                                          method:@"GET"
                                       cookieJar:cookieJar
                                       csrfToken:nil
                                      formFields:nil
                                 followRedirects:NO
                                        exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [mfaPage[@"status"] integerValue]);
    XCTAssertTrue([mfaPage[@"body"] containsString:@"Authenticator app"]);
    XCTAssertTrue([mfaPage[@"body"] containsString:@"SMS"]);
    XCTAssertTrue([mfaPage[@"body"] containsString:@"SMS can be useful as a fallback"]);

    NSDictionary *mfaState = [self curlJSONAtPort:port
                                             path:@"/auth/api/mfa"
                                           method:@"GET"
                                        cookieJar:cookieJar
                                        csrfToken:nil
                                          payload:nil
                                  followRedirects:NO
                                         exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [mfaState[@"status"] integerValue]);
    NSDictionary *mfaPayload = [self parseJSONDictionary:mfaState[@"body"]];
    XCTAssertEqualObjects(@YES, mfaPayload[@"policy"][@"sms"][@"enabled"]);
    XCTAssertEqualObjects(@"totp", mfaPayload[@"preferred_factor"]);
    XCTAssertEqualObjects(@YES, mfaPayload[@"mfa"][@"sms"][@"management_allowed"]);
    XCTAssertEqual((NSUInteger)2, [mfaPayload[@"factors"] count]);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *smsStart = [self curlJSONAtPort:port
                                             path:@"/auth/api/mfa/sms/start"
                                           method:@"POST"
                                        cookieJar:cookieJar
                                        csrfToken:csrfToken
                                          payload:@{
                                            @"phone_number" : phoneNumber,
                                            @"return_to" : @"/account/security",
                                          }
                                  followRedirects:NO
                                         exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [smsStart[@"status"] integerValue]);
    XCTAssertTrue([[self parseJSONDictionary:smsStart[@"body"]][@"message"] containsString:@"We sent a code"]);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *smsVerify = [self curlJSONAtPort:port
                                              path:@"/auth/api/mfa/sms/verify"
                                            method:@"POST"
                                         cookieJar:cookieJar
                                         csrfToken:csrfToken
                                           payload:@{
                                             @"code" : smsCode,
                                             @"return_to" : @"/account/security",
                                           }
                                   followRedirects:NO
                                          exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [smsVerify[@"status"] integerValue]);
    NSDictionary *smsVerifyPayload = [self parseJSONDictionary:smsVerify[@"body"]];
    XCTAssertEqualObjects(@"ok", smsVerifyPayload[@"status"]);
    XCTAssertEqualObjects(@"sms", smsVerifyPayload[@"flow"][@"factor"]);
    XCTAssertEqualObjects(@YES, smsVerifyPayload[@"enrollment_completed"]);

    NSDictionary *totpState = [self curlJSONAtPort:port
                                              path:@"/auth/api/mfa/totp"
                                            method:@"GET"
                                         cookieJar:cookieJar
                                         csrfToken:nil
                                           payload:nil
                                   followRedirects:NO
                                          exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [totpState[@"status"] integerValue]);
    NSDictionary *totpPayload = [self parseJSONDictionary:totpState[@"body"]];
    XCTAssertEqualObjects(@"enrollment", totpPayload[@"flow"][@"state"]);

    NSString *secret = [self sqlScalar:[NSString stringWithFormat:
        @"SELECT m.secret FROM auth_mfa_enrollments m JOIN auth_users u ON u.id = m.user_id "
         "WHERE lower(u.email) = lower('%@') AND m.type = 'totp' ORDER BY m.id DESC LIMIT 1;",
        [userEmail stringByReplacingOccurrencesOfString:@"'" withString:@"''"]]
                                  dsn:dsn];
    XCTAssertTrue([secret length] > 0);
    NSString *totpCode = [ALNTOTP codeForSecret:secret atDate:[NSDate date] error:nil];
    XCTAssertTrue([totpCode length] > 0);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *totpVerify = [self curlJSONAtPort:port
                                               path:@"/auth/api/mfa/totp/verify"
                                             method:@"POST"
                                          cookieJar:cookieJar
                                          csrfToken:csrfToken
                                            payload:@{
                                              @"code" : totpCode,
                                              @"return_to" : @"/account/security",
                                            }
                                    followRedirects:NO
                                           exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [totpVerify[@"status"] integerValue]);
    NSDictionary *totpVerifyPayload = [self parseJSONDictionary:totpVerify[@"body"]];
    XCTAssertEqualObjects(@"recovery_codes", totpVerifyPayload[@"flow"][@"state"]);
    XCTAssertEqualObjects(@YES, totpVerifyPayload[@"mfa"][@"recovery_codes_present"]);

    mfaState = [self curlJSONAtPort:port
                               path:@"/auth/api/mfa"
                             method:@"GET"
                          cookieJar:cookieJar
                          csrfToken:nil
                            payload:nil
                    followRedirects:NO
                           exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [mfaState[@"status"] integerValue]);
    mfaPayload = [self parseJSONDictionary:mfaState[@"body"]];
    XCTAssertEqualObjects(@"totp", mfaPayload[@"preferred_factor"]);
    XCTAssertTrue([mfaPayload[@"available_challenge_factors"] containsObject:@"totp"]);
    XCTAssertTrue([mfaPayload[@"available_challenge_factors"] containsObject:@"sms"]);
    XCTAssertEqualObjects(@YES, mfaPayload[@"mfa"][@"sms"][@"verified"]);

    NSDictionary *totpChallengePage = [self curlTextAtPort:port
                                                      path:@"/auth/mfa/totp?return_to=/account/security"
                                                    method:@"GET"
                                                 cookieJar:cookieJar
                                                 csrfToken:nil
                                                formFields:nil
                                           followRedirects:NO
                                                  exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [totpChallengePage[@"status"] integerValue]);
    XCTAssertTrue([totpChallengePage[@"body"] containsString:@"Use SMS instead"]);

    NSDictionary *smsChallengePage = [self curlTextAtPort:port
                                                     path:@"/auth/mfa/sms?return_to=/account/security"
                                                   method:@"GET"
                                                cookieJar:cookieJar
                                                csrfToken:nil
                                               formFields:nil
                                          followRedirects:NO
                                                 exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [smsChallengePage[@"status"] integerValue]);
    XCTAssertTrue([smsChallengePage[@"body"] containsString:@"Use authenticator app instead"]);

    sessionResponse = [self curlJSONAtPort:port
                                      path:@"/auth/api/session"
                                    method:@"GET"
                                 cookieJar:cookieJar
                                 csrfToken:nil
                                   payload:nil
                           followRedirects:NO
                                  exitCode:&exitCode];
    csrfToken = [self parseJSONDictionary:sessionResponse[@"body"]][@"csrf_token"] ?: @"";

    NSDictionary *smsRemove = [self curlJSONAtPort:port
                                              path:@"/auth/api/mfa/sms/remove"
                                            method:@"POST"
                                         cookieJar:cookieJar
                                         csrfToken:csrfToken
                                           payload:@{
                                             @"return_to" : @"/account/security",
                                           }
                                   followRedirects:NO
                                          exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [smsRemove[@"status"] integerValue]);
    XCTAssertTrue([[self parseJSONDictionary:smsRemove[@"body"]][@"message"] containsString:@"removed"]);

    mfaState = [self curlJSONAtPort:port
                               path:@"/auth/api/mfa"
                             method:@"GET"
                          cookieJar:cookieJar
                          csrfToken:nil
                            payload:nil
                    followRedirects:NO
                           exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [mfaState[@"status"] integerValue]);
    mfaPayload = [self parseJSONDictionary:mfaState[@"body"]];
    XCTAssertEqualObjects(@NO, mfaPayload[@"mfa"][@"sms"][@"enrolled"]);
    XCTAssertEqualObjects(@NO, mfaPayload[@"mfa"][@"sms"][@"verified"]);
  } @finally {
    if (server != nil && [server isRunning]) {
      kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    (void)[self deleteUserByEmail:userEmail dsn:dsn];
    [[NSFileManager defaultManager] removeItemAtPath:cookieJar error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:serverLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testAuthModuleModuleUIUsesAppLayoutHookAndPartialOverrides {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *quotedRepoRoot = [self shellQuoted:repoRoot];
  NSString *quotedArlenBinary = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"build/arlen"]];
  NSString *quotedBoomhauer = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/boomhauer"]];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase15-auth-module-ui"];
  NSString *cookieJar = [self createTempFilePathWithPrefix:@"phase15-auth-module-ui-cookie" suffix:@".txt"];
  NSString *serverLog = [self createTempFilePathWithPrefix:@"phase15-auth-module-ui-server" suffix:@".log"];
  int port = [self randomPort];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSTask *server = nil;

  @try {
    NSString *configContents =
        [NSString stringWithFormat:@"{\n"
                                   "  host = \"127.0.0.1\";\n"
                                   "  port = %d;\n"
                                   "  session = {\n"
                                   "    enabled = YES;\n"
                                   "    secret = \"phase15-auth-module-ui-session-secret-0123456789abcdef\";\n"
                                   "  };\n"
                                   "  csrf = {\n"
                                   "    enabled = YES;\n"
                                   "    allowQueryParamFallback = YES;\n"
                                   "  };\n"
                                   "  database = {\n"
                                   "    connectionString = \"%@\";\n"
                                   "  };\n"
                                   "  authModule = {\n"
                                   "    ui = {\n"
                                   "      mode = \"module-ui\";\n"
                                   "      layout = \"layouts/phase15_default_guest\";\n"
                                   "      contextClass = \"Phase15AuthUIIntegrationHook\";\n"
                                   "      partials = {\n"
                                   "        providerRow = \"auth/partials/custom_provider_row\";\n"
                                   "      };\n"
                                   "    };\n"
                                   "  };\n"
                                   "}\n",
                                   port,
                                   [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"] content:configContents]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeBasicAppAtRoot:appRoot
                               extraClasses:
                                           @"@interface Phase15AuthUIIntegrationHook : NSObject <ALNAuthModuleUIContextHook>\n"
                                            "@end\n\n"
                                            "@implementation Phase15AuthUIIntegrationHook\n"
                                            "- (NSString *)authModuleUILayoutForPage:(NSString *)pageIdentifier\n"
                                            "                          defaultLayout:(NSString *)defaultLayout\n"
                                            "                                context:(ALNContext *)context {\n"
                                            "  (void)defaultLayout;\n"
                                            "  (void)context;\n"
                                            "  if ([pageIdentifier isEqualToString:@\"login\"]) {\n"
                                            "    return @\"layouts/phase15_login_guest\";\n"
                                            "  }\n"
                                            "  return nil;\n"
                                            "}\n\n"
                                            "- (NSDictionary *)authModuleUIContextForPage:(NSString *)pageIdentifier\n"
                                            "                              defaultContext:(NSDictionary *)defaultContext\n"
                                            "                                     context:(ALNContext *)context {\n"
                                            "  (void)context;\n"
                                            "  NSMutableDictionary *uiContext = [NSMutableDictionary dictionaryWithDictionary:defaultContext ?: @{}];\n"
                                            "  uiContext[@\"brand_name\"] = @\"Phase15 Hook Brand\";\n"
                                            "  uiContext[@\"guest_subtitle\"] = [NSString stringWithFormat:@\"context:%@\", pageIdentifier ?: @\"\"];\n"
                                            "  return uiContext;\n"
                                            "}\n"
                                            "@end\n"
                                   homeText:@"phase15-module-ui"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"templates/layouts/phase15_default_guest.html.eoc"]
                          content:@"<!doctype html>\n"
                                  "<html lang=\"en\">\n"
                                  "  <body data-phase15-layout=\"default\">\n"
                                  "    <div class=\"phase15-brand\"><%= [ctx objectForKey:@\"brand_name\"] ?: @\"\" %></div>\n"
                                  "    <div class=\"phase15-subtitle\"><%= [ctx objectForKey:@\"guest_subtitle\"] ?: @\"\" %></div>\n"
                                  "    <%== [ctx objectForKey:@\"content\"] %>\n"
                                  "  </body>\n"
                                  "</html>\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"templates/layouts/phase15_login_guest.html.eoc"]
                          content:@"<!doctype html>\n"
                                  "<html lang=\"en\">\n"
                                  "  <body data-phase15-layout=\"hooked\">\n"
                                  "    <div class=\"phase15-brand\"><%= [ctx objectForKey:@\"brand_name\"] ?: @\"\" %></div>\n"
                                  "    <div class=\"phase15-subtitle\"><%= [ctx objectForKey:@\"guest_subtitle\"] ?: @\"\" %></div>\n"
                                  "    <%== [ctx objectForKey:@\"content\"] %>\n"
                                  "  </body>\n"
                                  "</html>\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"templates/auth/partials/custom_provider_row.html.eoc"]
                          content:@"<% NSDictionary *provider = [ctx objectForKey:@\"authProvider\"] ?: @{}; %>\n"
                                  "<a class=\"phase15-provider\" data-phase15-provider=\"<%= [provider objectForKey:@\"identifier\"] ?: @\"\" %>\" href=\"<%= [provider objectForKey:@\"loginPath\"] ?: @\"\" %>\"><%= [provider objectForKey:@\"ctaLabel\"] ?: @\"Continue\" %></a>\n"]);

    int exitCode = 0;
    NSString *buildOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen eocc",
                                                         quotedRepoRoot]
                     exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", buildOutput);

    NSString *addAuth = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add auth --json",
        [self shellQuoted:appRoot], quotedRepoRoot, quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addAuth);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:addAuth][@"status"]);

    server = [[NSTask alloc] init];
    server.launchPath = @"/bin/bash";
    server.arguments = @[ @"-lc",
                          [NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ --no-watch --port %d >%@ 2>&1",
                                                     [self shellQuoted:appRoot],
                                                     quotedRepoRoot,
                                                     quotedBoomhauer,
                                                     port,
                                                     [self shellQuoted:serverLog]] ];
    [server launch];
    XCTAssertTrue([self waitForServerOnPort:port path:@"/auth/api/session"]);

    NSDictionary *sessionResponse = [self curlJSONAtPort:port
                                                    path:@"/auth/api/session"
                                                  method:@"GET"
                                               cookieJar:cookieJar
                                               csrfToken:nil
                                                 payload:nil
                                         followRedirects:NO
                                                exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [sessionResponse[@"status"] integerValue]);
    NSDictionary *sessionPayload = [self parseJSONDictionary:sessionResponse[@"body"]];
    XCTAssertEqualObjects(@"module-ui", sessionPayload[@"ui_mode"]);

    NSDictionary *loginPage = [self curlJSONAtPort:port
                                              path:@"/auth/login"
                                            method:@"GET"
                                         cookieJar:cookieJar
                                         csrfToken:nil
                                           payload:nil
                                   followRedirects:NO
                                          exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [loginPage[@"status"] integerValue]);
    XCTAssertTrue([loginPage[@"body"] containsString:@"data-phase15-layout=\"hooked\""]);
    XCTAssertTrue([loginPage[@"body"] containsString:@"Phase15 Hook Brand"]);
    XCTAssertTrue([loginPage[@"body"] containsString:@"context:login"]);
    XCTAssertTrue([loginPage[@"body"] containsString:@"data-phase15-provider=\"stub\""]);
    XCTAssertTrue([loginPage[@"body"] containsString:@"auth-card"]);

    NSDictionary *registerPage = [self curlJSONAtPort:port
                                                 path:@"/auth/register"
                                               method:@"GET"
                                            cookieJar:cookieJar
                                            csrfToken:nil
                                              payload:nil
                                      followRedirects:NO
                                             exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [registerPage[@"status"] integerValue]);
    XCTAssertTrue([registerPage[@"body"] containsString:@"data-phase15-layout=\"default\""]);
    XCTAssertTrue([registerPage[@"body"] containsString:@"Phase15 Hook Brand"]);
    XCTAssertTrue([registerPage[@"body"] containsString:@"context:register"]);
  } @finally {
    if (server != nil && [server isRunning]) {
      kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    [[NSFileManager defaultManager] removeItemAtPath:cookieJar error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:serverLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testGeneratedAppUIAuthPagesRenderAfterEjectScaffold {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *quotedRepoRoot = [self shellQuoted:repoRoot];
  NSString *quotedArlenBinary = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"build/arlen"]];
  NSString *quotedBoomhauer = [self shellQuoted:[repoRoot stringByAppendingPathComponent:@"bin/boomhauer"]];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase18-generated-app-ui"];
  NSString *cookieJar = [self createTempFilePathWithPrefix:@"phase18-generated-app-ui-cookie" suffix:@".txt"];
  NSString *serverLog = [self createTempFilePathWithPrefix:@"phase18-generated-app-ui-server" suffix:@".log"];
  int port = [self randomPort];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSTask *server = nil;

  @try {
    NSString *configContents =
        [NSString stringWithFormat:@"{\n"
                                   "  host = \"127.0.0.1\";\n"
                                   "  port = %d;\n"
                                   "  session = {\n"
                                   "    enabled = YES;\n"
                                   "    secret = \"phase18-generated-auth-session-secret-0123456789abcdef\";\n"
                                   "  };\n"
                                   "  csrf = {\n"
                                   "    enabled = YES;\n"
                                   "    allowQueryParamFallback = YES;\n"
                                   "  };\n"
                                   "  database = {\n"
                                   "    connectionString = \"%@\";\n"
                                   "  };\n"
                                   "}\n",
                                   port,
                                   [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"] content:configContents]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeBasicAppAtRoot:appRoot extraClasses:nil homeText:@"phase18-generated-app-ui"]);

    int exitCode = 0;
    NSString *buildOutput =
        [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen eocc",
                                                         quotedRepoRoot]
                     exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", buildOutput);

    NSString *addAuth = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module add auth --json",
        [self shellQuoted:appRoot], quotedRepoRoot, quotedArlenBinary]
                                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", addAuth);
    XCTAssertEqualObjects(@"ok", [self parseJSONDictionary:addAuth][@"status"]);

    NSString *ejectAuth = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ module eject auth-ui --force --json",
        [self shellQuoted:appRoot], quotedRepoRoot, quotedArlenBinary]
                                        exitCode:&exitCode];
    XCTAssertEqual(0, exitCode, @"%@", ejectAuth);
    NSDictionary *ejectPayload = [self parseJSONDictionary:ejectAuth];
    XCTAssertEqualObjects(@"ok", ejectPayload[@"status"]);
    XCTAssertEqualObjects(@"eject", ejectPayload[@"workflow"]);
    XCTAssertTrue([ejectPayload[@"created_files"] containsObject:@"templates/auth/login.html.eoc"]);
    XCTAssertTrue([ejectPayload[@"created_files"] containsObject:@"templates/auth/partials/bodies/login_body.html.eoc"]);

    server = [[NSTask alloc] init];
    server.launchPath = @"/bin/bash";
    server.arguments = @[ @"-lc",
                          [NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@ --no-watch --port %d >%@ 2>&1",
                                                     [self shellQuoted:appRoot],
                                                     quotedRepoRoot,
                                                     quotedBoomhauer,
                                                     port,
                                                     [self shellQuoted:serverLog]] ];
    [server launch];
    XCTAssertTrue([self waitForServerOnPort:port path:@"/auth/api/session"]);

    NSDictionary *sessionResponse = [self curlJSONAtPort:port
                                                    path:@"/auth/api/session"
                                                  method:@"GET"
                                               cookieJar:cookieJar
                                               csrfToken:nil
                                                 payload:nil
                                         followRedirects:NO
                                                exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [sessionResponse[@"status"] integerValue]);
    NSDictionary *sessionPayload = [self parseJSONDictionary:sessionResponse[@"body"]];
    XCTAssertEqualObjects(@"generated-app-ui", sessionPayload[@"ui_mode"]);

    NSDictionary *loginPage = [self curlJSONAtPort:port
                                              path:@"/auth/login"
                                            method:@"GET"
                                         cookieJar:cookieJar
                                         csrfToken:nil
                                           payload:nil
                                   followRedirects:NO
                                          exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [loginPage[@"status"] integerValue]);
    XCTAssertFalse([loginPage[@"body"] containsString:@"render failed"]);
    XCTAssertFalse([loginPage[@"body"] containsString:@"Template not found"]);
    XCTAssertTrue([loginPage[@"body"] containsString:@"auth-card"]);

    NSDictionary *registerPage = [self curlJSONAtPort:port
                                                 path:@"/auth/register"
                                               method:@"GET"
                                            cookieJar:cookieJar
                                            csrfToken:nil
                                              payload:nil
                                      followRedirects:NO
                                             exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [registerPage[@"status"] integerValue]);
    XCTAssertFalse([registerPage[@"body"] containsString:@"render failed"]);
    XCTAssertFalse([registerPage[@"body"] containsString:@"Template not found"]);
    XCTAssertTrue([registerPage[@"body"] containsString:@"auth-card"]);
  } @finally {
    if (server != nil && [server isRunning]) {
      kill(server.processIdentifier, SIGTERM);
      [server waitUntilExit];
    }
    [[NSFileManager defaultManager] removeItemAtPath:cookieJar error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:serverLog error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

@end
