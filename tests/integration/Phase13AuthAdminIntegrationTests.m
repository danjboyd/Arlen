#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <signal.h>
#import <stdlib.h>
#import <string.h>
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

    (void)[self curlJSONAtPort:port
                          path:@"/auth/api/mfa/totp"
                        method:@"GET"
                     cookieJar:cookieJar
                     csrfToken:nil
                       payload:nil
               followRedirects:NO
                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
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

    NSDictionary *totpResponse = [self curlJSONAtPort:port
                                                 path:@"/auth/api/mfa/totp/verify"
                                               method:@"POST"
                                            cookieJar:cookieJar
                                            csrfToken:csrfToken
                                              payload:@{
                                                @"code" : localCode,
                                              }
                                      followRedirects:NO
                                             exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
    XCTAssertEqual((NSInteger)200, [totpResponse[@"status"] integerValue]);
    NSDictionary *totpPayload = [self parseJSONDictionary:totpResponse[@"body"]];
    XCTAssertEqualObjects(@2, totpPayload[@"aal"]);

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

    (void)[self curlJSONAtPort:port
                          path:@"/auth/api/mfa/totp"
                        method:@"GET"
                     cookieJar:cookieJar
                     csrfToken:nil
                       payload:nil
               followRedirects:NO
                      exitCode:&exitCode];
    XCTAssertEqual(0, exitCode);
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

@end
