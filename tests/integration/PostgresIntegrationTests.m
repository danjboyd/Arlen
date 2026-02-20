#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

@interface PostgresIntegrationTests : XCTestCase
@end

@implementation PostgresIntegrationTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
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
  NSMutableData *combined = [NSMutableData dataWithData:stdoutData ?: [NSData data]];
  if ([stderrData length] > 0) {
    [combined appendData:stderrData];
  }
  NSString *output = [[NSString alloc] initWithData:combined encoding:NSUTF8StringEncoding];
  return output ?: @"";
}

- (NSString *)createTempDirectory {
  NSString *templatePath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"arlen-pg-integration-XXXXXX"];
  const char *templateCString = [templatePath fileSystemRepresentation];
  char *buffer = strdup(templateCString);
  char *created = mkdtemp(buffer);
  NSString *result = created ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:created
                                                                                             length:strlen(created)]
                             : nil;
  free(buffer);
  return result;
}

- (nullable NSDictionary *)firstGeneratedClassContractFromHeader:(NSString *)header {
  if (![header isKindOfClass:[NSString class]] || [header length] == 0) {
    return nil;
  }

  NSError *interfaceError = nil;
  NSRegularExpression *interfaceRegex =
      [NSRegularExpression regularExpressionWithPattern:@"@interface\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*NSObject([\\s\\S]*?)@end"
                                                options:0
                                                  error:&interfaceError];
  if (interfaceRegex == nil || interfaceError != nil) {
    return nil;
  }

  NSError *methodError = nil;
  NSRegularExpression *methodRegex =
      [NSRegularExpression regularExpressionWithPattern:@"\\+ \\(NSString \\*\\)(column[A-Za-z0-9_]+);"
                                                options:0
                                                  error:&methodError];
  if (methodRegex == nil || methodError != nil) {
    return nil;
  }

  NSArray *matches = [interfaceRegex matchesInString:header options:0 range:NSMakeRange(0, [header length])];
  for (NSTextCheckingResult *match in matches) {
    if ([match numberOfRanges] < 3) {
      continue;
    }
    NSString *className = [header substringWithRange:[match rangeAtIndex:1]];
    NSString *body = [header substringWithRange:[match rangeAtIndex:2]];
    NSTextCheckingResult *methodMatch =
        [methodRegex firstMatchInString:body options:0 range:NSMakeRange(0, [body length])];
    if (methodMatch == nil || [methodMatch numberOfRanges] < 2) {
      continue;
    }
    NSString *columnMethod = [body substringWithRange:[methodMatch rangeAtIndex:1]];
    return @{
      @"className" : className,
      @"columnMethod" : columnMethod,
    };
  }

  return nil;
}

- (void)testArlenMigrateCommandAppliesPendingMigrations {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectory];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSString *table =
      [[NSString stringWithFormat:@"arlen_cli_%@", [[NSUUID UUID] UUIDString]] lowercaseString];
  table = [table stringByReplacingOccurrencesOfString:@"-" withString:@""];

  NSError *error = nil;
  XCTAssertTrue([[NSFileManager defaultManager]
                    createDirectoryAtPath:[appRoot stringByAppendingPathComponent:@"config/environments"]
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[NSFileManager defaultManager]
                    createDirectoryAtPath:[appRoot stringByAppendingPathComponent:@"db/migrations"]
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error]);
  XCTAssertNil(error);

  NSString *config =
      [NSString stringWithFormat:@"{\n"
                                 "  host = \"127.0.0.1\";\n"
                                 "  port = 3000;\n"
                                 "  database = {\n"
                                 "    connectionString = \"%@\";\n"
                                 "    poolSize = 2;\n"
                                 "  };\n"
                                 "}\n",
                                 [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
  XCTAssertTrue([config writeToFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([@"{}\n" writeToFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&error]);
  XCTAssertNil(error);

  NSString *migrationPath = [appRoot stringByAppendingPathComponent:@"db/migrations/2026021801_create_table.sql"];
  NSString *migrationSQL =
      [NSString stringWithFormat:@"CREATE TABLE %@(id SERIAL PRIMARY KEY, name TEXT);\n"
                                 "INSERT INTO %@ (name) VALUES ('boomhauer');\n",
                                 table, table];
  XCTAssertTrue([migrationSQL writeToFile:migrationPath
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&error]);
  XCTAssertNil(error);

  int buildCode = 0;
  NSString *buildOutput =
      [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                   exitCode:&buildCode];
  XCTAssertEqual(0, buildCode, @"%@", buildOutput);

  int firstCode = 0;
  NSString *firstOutput = [self
      runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                "migrate --env development",
                                                appRoot, repoRoot, repoRoot]
             exitCode:&firstCode];
  XCTAssertEqual(0, firstCode, @"%@", firstOutput);
  XCTAssertTrue([firstOutput containsString:@"Applied migrations: 1"], @"%@", firstOutput);

  int secondCode = 0;
  NSString *secondOutput = [self
      runShellCapture:[NSString stringWithFormat:@"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen "
                                                "migrate --env development",
                                                appRoot, repoRoot, repoRoot]
             exitCode:&secondCode];
  XCTAssertEqual(0, secondCode, @"%@", secondOutput);
  XCTAssertTrue([secondOutput containsString:@"Applied migrations: 0"], @"%@", secondOutput);

  int countCode = 0;
  NSString *countOutput =
      [self runShellCapture:[NSString stringWithFormat:@"psql %s -Atc \"SELECT COUNT(*) FROM %@\"",
                                                       [dsn UTF8String], table]
                   exitCode:&countCode];
  XCTAssertEqual(0, countCode, @"%@", countOutput);
  NSString *trimmed =
      [countOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  XCTAssertEqualObjects(@"1", trimmed);

  (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                         [dsn UTF8String], table]
                     exitCode:NULL];
}

- (void)testArlenSchemaCodegenGeneratesTypedHelpers {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectory];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSString *table =
      [[NSString stringWithFormat:@"arlen_codegen_%@", [[NSUUID UUID] UUIDString]] lowercaseString];
  table = [table stringByReplacingOccurrencesOfString:@"-" withString:@""];

  NSError *error = nil;
  XCTAssertTrue([[NSFileManager defaultManager]
                    createDirectoryAtPath:[appRoot stringByAppendingPathComponent:@"config/environments"]
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error]);
  XCTAssertNil(error);

  NSString *config =
      [NSString stringWithFormat:@"{\n"
                                 "  host = \"127.0.0.1\";\n"
                                 "  port = 3000;\n"
                                 "  database = {\n"
                                 "    connectionString = \"%@\";\n"
                                 "    poolSize = 2;\n"
                                 "  };\n"
                                 "}\n",
                                 [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
  XCTAssertTrue([config writeToFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([@"{}\n" writeToFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&error]);
  XCTAssertNil(error);

  int code = 0;
  NSString *createOutput =
      [self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"CREATE TABLE %@(id TEXT NOT NULL, created_at TEXT NOT NULL)\"",
                                                       [dsn UTF8String], table]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", createOutput);

  int buildCode = 0;
  NSString *buildOutput =
      [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                   exitCode:&buildCode];
  XCTAssertEqual(0, buildCode, @"%@", buildOutput);

  NSString *codegenCommand = [NSString stringWithFormat:
      @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen schema-codegen --env development --prefix ALNDB",
      appRoot, repoRoot, repoRoot];
  NSString *firstOutput = [self runShellCapture:codegenCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", firstOutput);
  XCTAssertTrue([firstOutput containsString:@"Generated typed schema artifacts"]);

  NSString *headerPath = [appRoot stringByAppendingPathComponent:@"src/Generated/ALNDBSchema.h"];
  NSString *implPath = [appRoot stringByAppendingPathComponent:@"src/Generated/ALNDBSchema.m"];
  NSString *manifestPath = [appRoot stringByAppendingPathComponent:@"db/schema/arlen_schema.json"];
  NSString *header = [NSString stringWithContentsOfFile:headerPath
                                               encoding:NSUTF8StringEncoding
                                                  error:&error];
  XCTAssertNotNil(header);
  XCTAssertNil(error);
  NSString *implementation = [NSString stringWithContentsOfFile:implPath
                                                       encoding:NSUTF8StringEncoding
                                                          error:&error];
  XCTAssertNotNil(implementation);
  XCTAssertNil(error);
  NSString *manifest = [NSString stringWithContentsOfFile:manifestPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
  XCTAssertNotNil(manifest);
  XCTAssertNil(error);

  XCTAssertTrue([header containsString:@"Generated by arlen schema-codegen"]);
  XCTAssertTrue([implementation containsString:@"Generated by arlen schema-codegen"]);
  XCTAssertTrue([manifest containsString:@"\"class_prefix\": \"ALNDB\""]);
  NSString *manifestTableFragment = [NSString stringWithFormat:@"\"table\": \"%@\"", table];
  XCTAssertTrue([manifest containsString:manifestTableFragment]);

  NSDictionary *contract = [self firstGeneratedClassContractFromHeader:header];
  XCTAssertNotNil(contract);
  NSString *className = [contract[@"className"] isKindOfClass:[NSString class]] ? contract[@"className"] : nil;
  NSString *columnMethod =
      [contract[@"columnMethod"] isKindOfClass:[NSString class]] ? contract[@"columnMethod"] : nil;
  XCTAssertNotNil(className);
  XCTAssertNotNil(columnMethod);
  if (className == nil || columnMethod == nil) {
    (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                           [dsn UTF8String], table]
                       exitCode:NULL];
    return;
  }

  NSString *smokeSourcePath = [appRoot stringByAppendingPathComponent:@"schema_codegen_smoke.m"];
  NSString *smokeBinaryPath = [appRoot stringByAppendingPathComponent:@"schema_codegen_smoke"];
  NSString *smokeSource =
      [NSString stringWithFormat:
                    @"#import <Foundation/Foundation.h>\n"
                     "#import \"ALNSQLBuilder.h\"\n"
                     "#import \"ALNDBSchema.h\"\n"
                     "\n"
                     "int main(int argc, const char *argv[]) {\n"
                     "  (void)argc;\n"
                     "  (void)argv;\n"
                     "  @autoreleasepool {\n"
                     "    ALNSQLBuilder *builder = [%@ selectAll];\n"
                     "    [builder whereField:[%@ %@] equals:@\"probe\"];\n"
                     "    NSError *error = nil;\n"
                     "    NSDictionary *built = [builder build:&error];\n"
                     "    if (built == nil || error != nil) {\n"
                     "      return 1;\n"
                     "    }\n"
                     "    NSArray *params = [built[@\"parameters\"] isKindOfClass:[NSArray class]] ? built[@\"parameters\"] : @[];\n"
                     "    if ([params count] != 1) {\n"
                     "      return 2;\n"
                     "    }\n"
                     "    NSString *sql = [built[@\"sql\"] isKindOfClass:[NSString class]] ? built[@\"sql\"] : @\"\";\n"
                     "    if ([sql length] == 0) {\n"
                     "      return 3;\n"
                     "    }\n"
                     "    fprintf(stdout, \"%%s\\n\", [sql UTF8String]);\n"
                     "  }\n"
                     "  return 0;\n"
                     "}\n",
                    className, className, columnMethod];
  XCTAssertTrue([smokeSource writeToFile:smokeSourcePath
                              atomically:YES
                                encoding:NSUTF8StringEncoding
                                   error:&error]);
  XCTAssertNil(error);

  NSString *compileCommand = [NSString stringWithFormat:
      @"source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && clang $(gnustep-config --objc-flags) "
       "-fobjc-arc -I%@/src/Arlen -I%@/src/Arlen/Data -I%@/src/Generated %@ %@ %@/src/Arlen/Data/ALNSQLBuilder.m "
       "-o %@ $(gnustep-config --base-libs) -ldl -lcrypto",
      repoRoot, repoRoot, appRoot, smokeSourcePath, implPath, repoRoot, smokeBinaryPath];
  NSString *compileOutput = [self runShellCapture:compileCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", compileOutput);

  NSString *runOutput = [self runShellCapture:[NSString stringWithFormat:@"%@", smokeBinaryPath]
                                     exitCode:&code];
  XCTAssertEqual(0, code, @"%@", runOutput);
  XCTAssertTrue([runOutput containsString:@"SELECT"]);
  XCTAssertTrue([runOutput containsString:@"WHERE"]);
  XCTAssertTrue([runOutput containsString:@"$1"]);

  NSString *secondOutput = [self runShellCapture:codegenCommand exitCode:&code];
  XCTAssertNotEqual(0, code);
  XCTAssertTrue([secondOutput containsString:@"File exists"], @"%@", secondOutput);

  NSString *forcedOutput = [self runShellCapture:[codegenCommand stringByAppendingString:@" --force"]
                                        exitCode:&code];
  XCTAssertEqual(0, code, @"%@", forcedOutput);

  (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                         [dsn UTF8String], table]
                     exitCode:NULL];
}

@end
