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

- (void)testArlenSchemaCodegenTypedContractsCompileAndDecodeDeterministically {
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
      [[NSString stringWithFormat:@"phase5d_users_%@", [[NSUUID UUID] UUIDString]] lowercaseString];
  table = [table stringByReplacingOccurrencesOfString:@"-" withString:@"_"];

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
      [self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"CREATE TABLE %@(id TEXT NOT NULL, age INTEGER)\"",
                                                       [dsn UTF8String], table]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", createOutput);

  int buildCode = 0;
  NSString *buildOutput =
      [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                   exitCode:&buildCode];
  XCTAssertEqual(0, buildCode, @"%@", buildOutput);

  NSString *codegenCommand = [NSString stringWithFormat:
      @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen schema-codegen --env development --prefix ALNDB --typed-contracts --force",
      appRoot, repoRoot, repoRoot];
  NSString *codegenOutput = [self runShellCapture:codegenCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", codegenOutput);
  XCTAssertTrue([codegenOutput containsString:@"typed contracts: enabled"], @"%@", codegenOutput);

  NSString *manifestPath = [appRoot stringByAppendingPathComponent:@"db/schema/arlen_schema.json"];
  NSData *manifestData = [NSData dataWithContentsOfFile:manifestPath];
  XCTAssertNotNil(manifestData);
  NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:&error];
  XCTAssertNotNil(manifest);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@YES, manifest[@"typed_contracts"]);
  NSArray *tables = [manifest[@"tables"] isKindOfClass:[NSArray class]] ? manifest[@"tables"] : @[];
  XCTAssertTrue([tables count] > 0);
  NSDictionary *firstTable = [tables firstObject];
  NSString *className =
      [firstTable[@"class_name"] isKindOfClass:[NSString class]] ? firstTable[@"class_name"] : nil;
  NSString *rowClassName =
      [firstTable[@"row_class_name"] isKindOfClass:[NSString class]] ? firstTable[@"row_class_name"] : nil;
  NSString *insertClassName =
      [firstTable[@"insert_class_name"] isKindOfClass:[NSString class]] ? firstTable[@"insert_class_name"] : nil;
  XCTAssertNotNil(className);
  XCTAssertNotNil(rowClassName);
  XCTAssertNotNil(insertClassName);
  if (className == nil || rowClassName == nil || insertClassName == nil) {
    (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                           [dsn UTF8String], table]
                       exitCode:NULL];
    return;
  }

  NSString *implPath = [appRoot stringByAppendingPathComponent:@"src/Generated/ALNDBSchema.m"];
  NSString *smokeSourcePath = [appRoot stringByAppendingPathComponent:@"phase5d_typed_contracts_smoke.m"];
  NSString *smokeBinaryPath = [appRoot stringByAppendingPathComponent:@"phase5d_typed_contracts_smoke"];
  NSString *smokeSource =
      [NSString stringWithFormat:
                    @"#import <Foundation/Foundation.h>\n"
                     "#import \"ALNSQLBuilder.h\"\n"
                     "#import \"ALNDBSchema.h\"\n"
                     "\n"
                     "int main(void) {\n"
                     "  @autoreleasepool {\n"
                     "    %@ *insertValues = [[%@ alloc] init];\n"
                     "    insertValues.columnId = @\"u-1\";\n"
                     "    insertValues.columnAge = @42;\n"
                     "    NSError *error = nil;\n"
                     "    ALNSQLBuilder *builder = [%@ insertContract:insertValues];\n"
                     "    NSDictionary *built = [builder build:&error];\n"
                     "    if (built == nil || error != nil) {\n"
                     "      return 1;\n"
                     "    }\n"
                     "    %@ *decoded = [%@ decodeTypedRow:@{ @\"id\" : @\"u-1\", @\"age\" : @42 } error:&error];\n"
                     "    if (decoded == nil || error != nil) {\n"
                     "      return 2;\n"
                     "    }\n"
                     "    error = nil;\n"
                     "    decoded = [%@ decodeTypedRow:@{ @\"id\" : @42 } error:&error];\n"
                     "    if (decoded != nil || error == nil) {\n"
                     "      return 3;\n"
                     "    }\n"
                     "    if (![error.domain isEqualToString:ALNDBSchemaTypedDecodeErrorDomain]) {\n"
                     "      return 4;\n"
                     "    }\n"
                     "    fprintf(stdout, \"phase5d-typed-contracts-ok\\n\");\n"
                     "  }\n"
                     "  return 0;\n"
                     "}\n",
                    insertClassName, insertClassName, className, rowClassName, className, className];
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
  XCTAssertTrue([runOutput containsString:@"phase5d-typed-contracts-ok"], @"%@", runOutput);

  NSString *brokenSourcePath = [appRoot stringByAppendingPathComponent:@"phase5d_typed_contracts_broken.m"];
  NSString *brokenSource =
      [NSString stringWithFormat:
                    @"#import <Foundation/Foundation.h>\n"
                     "#import \"ALNDBSchema.h\"\n"
                     "\n"
                     "int main(void) {\n"
                     "  %@ *row = nil;\n"
                     "  id bad = row.fieldDoesNotExist;\n"
                     "  return (bad == nil) ? 0 : 1;\n"
                     "}\n",
                    rowClassName];
  XCTAssertTrue([brokenSource writeToFile:brokenSourcePath
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&error]);
  XCTAssertNil(error);

  NSString *brokenCompile = [NSString stringWithFormat:
      @"source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && clang $(gnustep-config --objc-flags) "
       "-fobjc-arc -I%@/src/Generated %@ %@ -o %@.broken $(gnustep-config --base-libs) -ldl -lcrypto",
      appRoot, brokenSourcePath, implPath, smokeBinaryPath];
  NSString *brokenCompileOutput = [self runShellCapture:brokenCompile exitCode:&code];
  XCTAssertNotEqual(0, code);
  XCTAssertTrue([brokenCompileOutput containsString:@"fieldDoesNotExist"], @"%@", brokenCompileOutput);

  (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                         [dsn UTF8String], table]
                     exitCode:NULL];
}

- (void)testArlenTypedSQLCodegenGeneratesTypedParameterAndResultHelpers {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectory];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSError *error = nil;
  XCTAssertTrue([[NSFileManager defaultManager]
                    createDirectoryAtPath:[appRoot stringByAppendingPathComponent:@"db/sql/typed"]
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error]);
  XCTAssertNil(error);

  NSString *queryPath = [appRoot stringByAppendingPathComponent:@"db/sql/typed/list_users_by_status.sql"];
  NSString *query =
      @"-- arlen:name list_users_by_status\n"
       "-- arlen:params status:text limit:int\n"
       "-- arlen:result id:text name:text\n"
       "SELECT id, name FROM users WHERE status = $1 LIMIT $2;\n";
  XCTAssertTrue([query writeToFile:queryPath
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:&error]);
  XCTAssertNil(error);

  int code = 0;
  NSString *buildOutput =
      [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", buildOutput);

  NSString *command = [NSString stringWithFormat:
      @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen typed-sql-codegen --force",
      appRoot, repoRoot, repoRoot];
  NSString *output = [self runShellCapture:command exitCode:&code];
  XCTAssertEqual(0, code, @"%@", output);
  XCTAssertTrue([output containsString:@"Generated typed SQL artifacts"], @"%@", output);

  NSString *headerPath = [appRoot stringByAppendingPathComponent:@"src/Generated/ALNDBTypedSQL.h"];
  NSString *implPath = [appRoot stringByAppendingPathComponent:@"src/Generated/ALNDBTypedSQL.m"];
  NSString *manifestPath = [appRoot stringByAppendingPathComponent:@"db/schema/arlen_typed_sql.json"];
  NSString *header = [NSString stringWithContentsOfFile:headerPath
                                               encoding:NSUTF8StringEncoding
                                                  error:&error];
  XCTAssertNotNil(header);
  XCTAssertNil(error);
  NSString *manifest = [NSString stringWithContentsOfFile:manifestPath
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
  XCTAssertNotNil(manifest);
  XCTAssertNil(error);
  XCTAssertTrue([header containsString:@"ALNDBTypedSQLListUsersByStatusRow"]);
  XCTAssertTrue([header containsString:@"parametersForListUsersByStatusWithStatus"]);
  XCTAssertTrue([manifest containsString:@"\"name\": \"list_users_by_status\""]);

  NSString *smokeSourcePath = [appRoot stringByAppendingPathComponent:@"phase5d_typed_sql_smoke.m"];
  NSString *smokeBinaryPath = [appRoot stringByAppendingPathComponent:@"phase5d_typed_sql_smoke"];
  NSString *smokeSource =
      @"#import <Foundation/Foundation.h>\n"
       "#import \"ALNDBTypedSQL.h\"\n"
       "\n"
       "int main(void) {\n"
       "  @autoreleasepool {\n"
       "    NSArray *params = [ALNDBTypedSQL parametersForListUsersByStatusWithStatus:@\"active\" limit:@3];\n"
       "    if ([params count] != 2) {\n"
       "      return 1;\n"
       "    }\n"
       "    NSError *error = nil;\n"
       "    ALNDBTypedSQLListUsersByStatusRow *row = [ALNDBTypedSQL decodeListUsersByStatusRow:@{ @\"id\" : @\"u1\", @\"name\" : @\"dan\" } error:&error];\n"
       "    if (row == nil || error != nil) {\n"
       "      return 2;\n"
       "    }\n"
       "    error = nil;\n"
       "    row = [ALNDBTypedSQL decodeListUsersByStatusRow:@{ @\"id\" : @1, @\"name\" : @\"dan\" } error:&error];\n"
       "    if (row != nil || error == nil) {\n"
       "      return 3;\n"
       "    }\n"
       "    if (![error.domain isEqualToString:ALNDBTypedSQLErrorDomain]) {\n"
       "      return 4;\n"
       "    }\n"
       "    fprintf(stdout, \"phase5d-typed-sql-ok\\n\");\n"
       "  }\n"
       "  return 0;\n"
       "}\n";
  XCTAssertTrue([smokeSource writeToFile:smokeSourcePath
                              atomically:YES
                                encoding:NSUTF8StringEncoding
                                   error:&error]);
  XCTAssertNil(error);

  NSString *compileCommand = [NSString stringWithFormat:
      @"source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && clang $(gnustep-config --objc-flags) "
       "-fobjc-arc -I%@/src/Generated %@ %@ -o %@ $(gnustep-config --base-libs) -ldl -lcrypto",
      appRoot, smokeSourcePath, implPath, smokeBinaryPath];
  NSString *compileOutput = [self runShellCapture:compileCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", compileOutput);

  NSString *runOutput = [self runShellCapture:[NSString stringWithFormat:@"%@", smokeBinaryPath]
                                     exitCode:&code];
  XCTAssertEqual(0, code, @"%@", runOutput);
  XCTAssertTrue([runOutput containsString:@"phase5d-typed-sql-ok"], @"%@", runOutput);

  NSString *brokenSourcePath = [appRoot stringByAppendingPathComponent:@"phase5d_typed_sql_broken.m"];
  NSString *brokenSource =
      @"#import <Foundation/Foundation.h>\n"
       "#import \"ALNDBTypedSQL.h\"\n"
       "int main(void) {\n"
       "  ALNDBTypedSQLListUsersByStatusRow *row = nil;\n"
       "  id x = row.fieldMissing;\n"
       "  return (x == nil) ? 0 : 1;\n"
       "}\n";
  XCTAssertTrue([brokenSource writeToFile:brokenSourcePath
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&error]);
  XCTAssertNil(error);

  NSString *brokenCompile = [NSString stringWithFormat:
      @"source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && clang $(gnustep-config --objc-flags) "
       "-fobjc-arc -I%@/src/Generated %@ %@ -o %@.broken $(gnustep-config --base-libs) -ldl -lcrypto",
      appRoot, brokenSourcePath, implPath, smokeBinaryPath];
  NSString *brokenOutput = [self runShellCapture:brokenCompile exitCode:&code];
  XCTAssertNotEqual(0, code);
  XCTAssertTrue([brokenOutput containsString:@"fieldMissing"], @"%@", brokenOutput);
}

- (void)testArlenMigrateCommandSupportsNamedDatabaseTargetsAndFailureRetry {
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

  NSString *primaryTable =
      [[NSString stringWithFormat:@"arlen_primary_%@", [[NSUUID UUID] UUIDString]] lowercaseString];
  primaryTable = [primaryTable stringByReplacingOccurrencesOfString:@"-" withString:@""];
  NSString *analyticsTable =
      [[NSString stringWithFormat:@"arlen_analytics_%@", [[NSUUID UUID] UUIDString]] lowercaseString];
  analyticsTable = [analyticsTable stringByReplacingOccurrencesOfString:@"-" withString:@""];

  NSError *error = nil;
  XCTAssertTrue([[NSFileManager defaultManager]
                    createDirectoryAtPath:[appRoot stringByAppendingPathComponent:@"config/environments"]
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[NSFileManager defaultManager]
                    createDirectoryAtPath:[appRoot stringByAppendingPathComponent:@"db/migrations/primary"]
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[NSFileManager defaultManager]
                    createDirectoryAtPath:[appRoot stringByAppendingPathComponent:@"db/migrations/analytics"]
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error]);
  XCTAssertNil(error);

  NSString *escapedDSN = [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  NSString *config =
      [NSString stringWithFormat:@"{\n"
                                 "  host = \"127.0.0.1\";\n"
                                 "  port = 3000;\n"
                                 "  database = {\n"
                                 "    connectionString = \"%@\";\n"
                                 "    poolSize = 2;\n"
                                 "  };\n"
                                 "  databases = {\n"
                                 "    primary = {\n"
                                 "      connectionString = \"%@\";\n"
                                 "      poolSize = 2;\n"
                                 "    };\n"
                                 "    analytics = {\n"
                                 "      connectionString = \"%@\";\n"
                                 "      poolSize = 2;\n"
                                 "    };\n"
                                 "  };\n"
                                 "}\n",
                                 escapedDSN, escapedDSN, escapedDSN];
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

  NSString *primaryMigration1 =
      [appRoot stringByAppendingPathComponent:@"db/migrations/primary/2026022301_create_primary_table.sql"];
  NSString *primarySQL1 =
      [NSString stringWithFormat:@"CREATE TABLE %@(id SERIAL PRIMARY KEY, value TEXT NOT NULL);\n"
                                 "INSERT INTO %@ (value) VALUES ('seed-1');\n",
                                 primaryTable, primaryTable];
  XCTAssertTrue([primarySQL1 writeToFile:primaryMigration1
                              atomically:YES
                                encoding:NSUTF8StringEncoding
                                   error:&error]);
  XCTAssertNil(error);

  NSString *primaryMigration2 =
      [appRoot stringByAppendingPathComponent:@"db/migrations/primary/2026022302_insert_primary_row.sql"];
  NSString *primarySQL2 =
      [NSString stringWithFormat:@"INSERT INTO %@ (value) VALUES ('seed-2');\n", primaryTable];
  XCTAssertTrue([primarySQL2 writeToFile:primaryMigration2
                              atomically:YES
                                encoding:NSUTF8StringEncoding
                                   error:&error]);
  XCTAssertNil(error);

  NSString *analyticsMigration1 =
      [appRoot stringByAppendingPathComponent:@"db/migrations/analytics/2026022301_create_analytics_table.sql"];
  NSString *analyticsSQL1 =
      [NSString stringWithFormat:@"CREATE TABLE %@(id SERIAL PRIMARY KEY, event_name TEXT NOT NULL);\n"
                                 "INSERT INTO %@ (event_name) VALUES ('opened');\n",
                                 analyticsTable, analyticsTable];
  XCTAssertTrue([analyticsSQL1 writeToFile:analyticsMigration1
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:&error]);
  XCTAssertNil(error);

  NSString *analyticsMigration2 =
      [appRoot stringByAppendingPathComponent:@"db/migrations/analytics/2026022302_bad_analytics_row.sql"];
  NSString *badAnalyticsSQL = [NSString stringWithFormat:@"INSER INTO %@ (event_name) VALUES ('broken');\n",
                                                         analyticsTable];
  XCTAssertTrue([badAnalyticsSQL writeToFile:analyticsMigration2
                                  atomically:YES
                                    encoding:NSUTF8StringEncoding
                                       error:&error]);
  XCTAssertNil(error);

  int code = 0;
  NSString *buildOutput =
      [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", buildOutput);

  NSString *primaryCommand = [NSString stringWithFormat:
      @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen migrate --env development --database primary",
      appRoot, repoRoot, repoRoot];
  NSString *primaryFirst = [self runShellCapture:primaryCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", primaryFirst);
  XCTAssertTrue([primaryFirst containsString:@"Database target: primary"], @"%@", primaryFirst);
  XCTAssertTrue([primaryFirst containsString:@"Applied migrations: 2"], @"%@", primaryFirst);

  NSString *primarySecond = [self runShellCapture:primaryCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", primarySecond);
  XCTAssertTrue([primarySecond containsString:@"Applied migrations: 0"], @"%@", primarySecond);

  NSString *analyticsCommand = [NSString stringWithFormat:
      @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen migrate --env development --database analytics",
      appRoot, repoRoot, repoRoot];
  NSString *analyticsFirst = [self runShellCapture:analyticsCommand exitCode:&code];
  XCTAssertNotEqual(0, code, @"%@", analyticsFirst);
  XCTAssertTrue([analyticsFirst containsString:@"arlen migrate:"], @"%@", analyticsFirst);

  NSString *primaryCountOutput =
      [self runShellCapture:[NSString stringWithFormat:@"psql %s -Atc \"SELECT COUNT(*) FROM %@\"",
                                                       [dsn UTF8String], primaryTable]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", primaryCountOutput);
  NSString *primaryCount =
      [primaryCountOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  XCTAssertEqualObjects(@"2", primaryCount);

  NSString *analyticsCountOutput =
      [self runShellCapture:[NSString stringWithFormat:@"psql %s -Atc \"SELECT COUNT(*) FROM %@\"",
                                                       [dsn UTF8String], analyticsTable]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", analyticsCountOutput);
  NSString *analyticsCount =
      [analyticsCountOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  XCTAssertEqualObjects(@"1", analyticsCount);

  NSString *goodAnalyticsSQL =
      [NSString stringWithFormat:@"INSERT INTO %@ (event_name) VALUES ('recovered');\n", analyticsTable];
  XCTAssertTrue([goodAnalyticsSQL writeToFile:analyticsMigration2
                                   atomically:YES
                                     encoding:NSUTF8StringEncoding
                                        error:&error]);
  XCTAssertNil(error);

  NSString *analyticsSecond = [self runShellCapture:analyticsCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", analyticsSecond);
  XCTAssertTrue([analyticsSecond containsString:@"Applied migrations: 1"], @"%@", analyticsSecond);

  NSString *analyticsThird = [self runShellCapture:analyticsCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", analyticsThird);
  XCTAssertTrue([analyticsThird containsString:@"Applied migrations: 0"], @"%@", analyticsThird);

  NSString *dryRunPrimary = [self runShellCapture:[primaryCommand stringByAppendingString:@" --dry-run"]
                                         exitCode:&code];
  XCTAssertEqual(0, code, @"%@", dryRunPrimary);
  XCTAssertTrue([dryRunPrimary containsString:@"Pending migrations: 0"], @"%@", dryRunPrimary);
  NSString *dryRunAnalytics = [self runShellCapture:[analyticsCommand stringByAppendingString:@" --dry-run"]
                                           exitCode:&code];
  XCTAssertEqual(0, code, @"%@", dryRunAnalytics);
  XCTAssertTrue([dryRunAnalytics containsString:@"Pending migrations: 0"], @"%@", dryRunAnalytics);

  NSString *primaryTrackingOutput =
      [self runShellCapture:[NSString stringWithFormat:@"psql %s -Atc \"SELECT COUNT(*) FROM arlen_schema_migrations__primary\"",
                                                       [dsn UTF8String]]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", primaryTrackingOutput);
  NSString *primaryTracking =
      [primaryTrackingOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  XCTAssertEqualObjects(@"2", primaryTracking);

  NSString *analyticsTrackingOutput =
      [self runShellCapture:[NSString stringWithFormat:@"psql %s -Atc \"SELECT COUNT(*) FROM arlen_schema_migrations__analytics\"",
                                                       [dsn UTF8String]]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", analyticsTrackingOutput);
  NSString *analyticsTracking =
      [analyticsTrackingOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  XCTAssertEqualObjects(@"2", analyticsTracking);

  (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                         [dsn UTF8String], primaryTable]
                     exitCode:NULL];
  (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                         [dsn UTF8String], analyticsTable]
                     exitCode:NULL];
  (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS arlen_schema_migrations__primary\" >/dev/null 2>&1",
                                                         [dsn UTF8String]]
                     exitCode:NULL];
  (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS arlen_schema_migrations__analytics\" >/dev/null 2>&1",
                                                         [dsn UTF8String]]
                     exitCode:NULL];
}

- (void)testArlenSchemaCodegenSupportsNamedDatabaseTargets {
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

  NSString *primaryTable =
      [[NSString stringWithFormat:@"arlen_codegen_primary_%@", [[NSUUID UUID] UUIDString]] lowercaseString];
  primaryTable = [primaryTable stringByReplacingOccurrencesOfString:@"-" withString:@""];
  NSString *analyticsTable =
      [[NSString stringWithFormat:@"arlen_codegen_analytics_%@", [[NSUUID UUID] UUIDString]] lowercaseString];
  analyticsTable = [analyticsTable stringByReplacingOccurrencesOfString:@"-" withString:@""];

  NSError *error = nil;
  XCTAssertTrue([[NSFileManager defaultManager]
                    createDirectoryAtPath:[appRoot stringByAppendingPathComponent:@"config/environments"]
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error]);
  XCTAssertNil(error);

  NSString *escapedDSN = [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  NSString *config =
      [NSString stringWithFormat:@"{\n"
                                 "  host = \"127.0.0.1\";\n"
                                 "  port = 3000;\n"
                                 "  database = {\n"
                                 "    connectionString = \"%@\";\n"
                                 "    poolSize = 2;\n"
                                 "  };\n"
                                 "  databases = {\n"
                                 "    primary = {\n"
                                 "      connectionString = \"%@\";\n"
                                 "      poolSize = 2;\n"
                                 "    };\n"
                                 "    analytics = {\n"
                                 "      connectionString = \"%@\";\n"
                                 "      poolSize = 2;\n"
                                 "    };\n"
                                 "  };\n"
                                 "}\n",
                                 escapedDSN, escapedDSN, escapedDSN];
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
  NSString *createPrimary =
      [self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"CREATE TABLE %@(id TEXT NOT NULL, value TEXT NOT NULL)\"",
                                                       [dsn UTF8String], primaryTable]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", createPrimary);
  NSString *createAnalytics =
      [self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"CREATE TABLE %@(id TEXT NOT NULL, event_name TEXT NOT NULL)\"",
                                                       [dsn UTF8String], analyticsTable]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", createAnalytics);

  NSString *buildOutput =
      [self runShellCapture:[NSString stringWithFormat:@"cd %@ && make arlen", repoRoot]
                   exitCode:&code];
  XCTAssertEqual(0, code, @"%@", buildOutput);

  NSString *analyticsCommand = [NSString stringWithFormat:
      @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen schema-codegen --env development --database analytics --force",
      appRoot, repoRoot, repoRoot];
  NSString *analyticsOutput = [self runShellCapture:analyticsCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", analyticsOutput);
  XCTAssertTrue([analyticsOutput containsString:@"database target: analytics"], @"%@", analyticsOutput);

  NSString *analyticsHeaderPath =
      [appRoot stringByAppendingPathComponent:@"src/Generated/analytics/ALNDBAnalyticsSchema.h"];
  NSString *analyticsManifestPath =
      [appRoot stringByAppendingPathComponent:@"db/schema/arlen_schema_analytics.json"];
  NSString *analyticsHeader = [NSString stringWithContentsOfFile:analyticsHeaderPath
                                                        encoding:NSUTF8StringEncoding
                                                           error:&error];
  XCTAssertNotNil(analyticsHeader);
  XCTAssertNil(error);
  NSString *analyticsManifest = [NSString stringWithContentsOfFile:analyticsManifestPath
                                                          encoding:NSUTF8StringEncoding
                                                             error:&error];
  XCTAssertNotNil(analyticsManifest);
  XCTAssertNil(error);
  XCTAssertTrue([analyticsManifest containsString:@"\"database_target\": \"analytics\""]);
  NSString *analyticsTableFragment = [NSString stringWithFormat:@"\"table\": \"%@\"", analyticsTable];
  XCTAssertTrue([analyticsManifest containsString:analyticsTableFragment]);

  NSString *analyticsOutput2 = [self runShellCapture:analyticsCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", analyticsOutput2);
  NSString *analyticsHeader2 = [NSString stringWithContentsOfFile:analyticsHeaderPath
                                                         encoding:NSUTF8StringEncoding
                                                            error:&error];
  XCTAssertNotNil(analyticsHeader2);
  XCTAssertNil(error);
  NSString *analyticsManifest2 = [NSString stringWithContentsOfFile:analyticsManifestPath
                                                           encoding:NSUTF8StringEncoding
                                                              error:&error];
  XCTAssertNotNil(analyticsManifest2);
  XCTAssertNil(error);
  XCTAssertEqualObjects(analyticsHeader, analyticsHeader2);
  XCTAssertEqualObjects(analyticsManifest, analyticsManifest2);

  NSString *primaryCommand = [NSString stringWithFormat:
      @"cd %@ && ARLEN_FRAMEWORK_ROOT=%@ %@/build/arlen schema-codegen --env development --database primary --force",
      appRoot, repoRoot, repoRoot];
  NSString *primaryOutput = [self runShellCapture:primaryCommand exitCode:&code];
  XCTAssertEqual(0, code, @"%@", primaryOutput);
  XCTAssertTrue([primaryOutput containsString:@"database target: primary"], @"%@", primaryOutput);

  NSString *primaryManifestPath =
      [appRoot stringByAppendingPathComponent:@"db/schema/arlen_schema_primary.json"];
  NSString *primaryManifest = [NSString stringWithContentsOfFile:primaryManifestPath
                                                        encoding:NSUTF8StringEncoding
                                                           error:&error];
  XCTAssertNotNil(primaryManifest);
  XCTAssertNil(error);
  XCTAssertTrue([primaryManifest containsString:@"\"database_target\": \"primary\""]);

  (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                         [dsn UTF8String], primaryTable]
                     exitCode:NULL];
  (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                         [dsn UTF8String], analyticsTable]
                     exitCode:NULL];
}

- (void)testDatabaseRouterReadWriteRoutingAcrossLiveAdapters {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *workRoot = [self createTempDirectory];
  XCTAssertNotNil(workRoot);
  if (workRoot == nil) {
    return;
  }

  NSString *table =
      [[NSString stringWithFormat:@"arlen_router_%@", [[NSUUID UUID] UUIDString]] lowercaseString];
  table = [table stringByReplacingOccurrencesOfString:@"-" withString:@""];

  NSString *sourcePath = [workRoot stringByAppendingPathComponent:@"phase5b_router_smoke.m"];
  NSString *binaryPath = [workRoot stringByAppendingPathComponent:@"phase5b_router_smoke"];
  NSString *escapedDSN = [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  NSString *escapedTable = [table stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

  NSString *source = [NSString stringWithFormat:
      @"#import <Foundation/Foundation.h>\n"
       "#import \"ALNDatabaseRouter.h\"\n"
       "#import \"ALNPg.h\"\n"
       "\n"
       "int main(void) {\n"
       "  @autoreleasepool {\n"
       "    NSString *dsn = @\"%@\";\n"
       "    NSString *table = @\"%@\";\n"
       "    NSError *error = nil;\n"
       "    ALNPg *reader = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:2 error:&error];\n"
       "    if (reader == nil || error != nil) {\n"
       "      fprintf(stderr, \"reader init failed\\n\");\n"
       "      return 1;\n"
       "    }\n"
       "    ALNPg *writer = [[ALNPg alloc] initWithConnectionString:dsn maxConnections:2 error:&error];\n"
       "    if (writer == nil || error != nil) {\n"
       "      fprintf(stderr, \"writer init failed\\n\");\n"
       "      return 2;\n"
       "    }\n"
       "    ALNDatabaseRouter *router = [[ALNDatabaseRouter alloc]\n"
       "      initWithTargets:@{ @\"reader\" : reader, @\"writer\" : writer }\n"
       "      defaultReadTarget:@\"reader\"\n"
       "      defaultWriteTarget:@\"writer\"\n"
       "      error:&error];\n"
       "    if (router == nil || error != nil) {\n"
       "      fprintf(stderr, \"router init failed\\n\");\n"
       "      return 3;\n"
       "    }\n"
       "\n"
       "    NSMutableArray<NSDictionary *> *events = [NSMutableArray array];\n"
       "    router.routingDiagnosticsListener = ^(NSDictionary<NSString *, id> *event) {\n"
       "      [events addObject:[NSDictionary dictionaryWithDictionary:event ?: @{}]];\n"
       "    };\n"
       "\n"
       "    NSInteger affected = [router executeCommand:[NSString stringWithFormat:@\"CREATE TABLE %%@ (id SERIAL PRIMARY KEY, value TEXT NOT NULL)\", table]\n"
       "                                        parameters:@[]\n"
       "                                             error:&error];\n"
       "    if (affected < 0 || error != nil) {\n"
       "      fprintf(stderr, \"create failed\\n\");\n"
       "      return 4;\n"
       "    }\n"
       "    affected = [router executeCommand:[NSString stringWithFormat:@\"INSERT INTO %%@ (value) VALUES ($1)\", table]\n"
       "                                 parameters:@[ @\"seed\" ]\n"
       "                                      error:&error];\n"
       "    if (affected != 1 || error != nil) {\n"
       "      fprintf(stderr, \"insert seed failed\\n\");\n"
       "      return 5;\n"
       "    }\n"
       "\n"
       "    NSArray<NSDictionary *> *rows = [router executeQuery:[NSString stringWithFormat:@\"SELECT COUNT(*) AS count FROM %%@\", table]\n"
       "                                                    parameters:@[]\n"
       "                                                         error:&error];\n"
       "    NSString *count = [[rows firstObject][@\"count\"] isKindOfClass:[NSString class]] ? [rows firstObject][@\"count\"] : @\"\";\n"
       "    if ([count isEqualToString:@\"1\"] == NO || error != nil) {\n"
       "      fprintf(stderr, \"initial read failed\\n\");\n"
       "      return 6;\n"
       "    }\n"
       "\n"
       "    NSDictionary *firstReadEvent = nil;\n"
       "    for (NSDictionary *event in events) {\n"
       "      NSString *operationClass = [event[@\"operation_class\"] isKindOfClass:[NSString class]] ? event[@\"operation_class\"] : @\"\";\n"
       "      if ([operationClass isEqualToString:@\"read\"]) {\n"
       "        firstReadEvent = event;\n"
       "        break;\n"
       "      }\n"
       "    }\n"
       "    NSString *firstTarget = [firstReadEvent[@\"selected_target\"] isKindOfClass:[NSString class]] ? firstReadEvent[@\"selected_target\"] : @\"\";\n"
       "    if ([firstTarget isEqualToString:@\"reader\"] == NO) {\n"
       "      fprintf(stderr, \"initial route target mismatch\\n\");\n"
       "      return 7;\n"
       "    }\n"
       "\n"
       "    router.readAfterWriteStickinessSeconds = 5;\n"
       "    NSDictionary *scope = @{ @\"stickiness_scope\" : @\"integration-scope-a\" };\n"
       "    affected = [router executeCommand:[NSString stringWithFormat:@\"INSERT INTO %%@ (value) VALUES ($1)\", table]\n"
       "                                 parameters:@[ @\"stickiness\" ]\n"
       "                             routingContext:scope\n"
       "                                      error:&error];\n"
       "    if (affected != 1 || error != nil) {\n"
       "      fprintf(stderr, \"stickiness write failed\\n\");\n"
       "      return 8;\n"
       "    }\n"
       "\n"
       "    rows = [router executeQuery:[NSString stringWithFormat:@\"SELECT COUNT(*) AS count FROM %%@\", table]\n"
       "                    parameters:@[]\n"
       "                routingContext:scope\n"
       "                         error:&error];\n"
       "    count = [[rows firstObject][@\"count\"] isKindOfClass:[NSString class]] ? [rows firstObject][@\"count\"] : @\"\";\n"
       "    if ([count isEqualToString:@\"2\"] == NO || error != nil) {\n"
       "      fprintf(stderr, \"sticky read failed\\n\");\n"
       "      return 9;\n"
       "    }\n"
       "\n"
       "    NSDictionary *stickyReadEvent = nil;\n"
       "    for (NSInteger idx = (NSInteger)[events count] - 1; idx >= 0; idx--) {\n"
       "      NSDictionary *event = events[(NSUInteger)idx];\n"
       "      NSString *operationClass = [event[@\"operation_class\"] isKindOfClass:[NSString class]] ? event[@\"operation_class\"] : @\"\";\n"
       "      if (![operationClass isEqualToString:@\"read\"]) {\n"
       "        continue;\n"
       "      }\n"
       "      NSString *scopeValue = [event[@\"stickiness_scope\"] isKindOfClass:[NSString class]] ? event[@\"stickiness_scope\"] : @\"\";\n"
       "      if ([scopeValue isEqualToString:@\"integration-scope-a\"]) {\n"
       "        stickyReadEvent = event;\n"
       "        break;\n"
       "      }\n"
       "    }\n"
       "    NSString *stickyTarget = [stickyReadEvent[@\"selected_target\"] isKindOfClass:[NSString class]] ? stickyReadEvent[@\"selected_target\"] : @\"\";\n"
       "    BOOL usedStickiness = [stickyReadEvent[@\"used_stickiness\"] boolValue];\n"
       "    if ([stickyTarget isEqualToString:@\"writer\"] == NO || !usedStickiness) {\n"
       "      fprintf(stderr, \"sticky route metadata mismatch\\n\");\n"
       "      return 10;\n"
       "    }\n"
       "\n"
       "    (void)[writer executeCommand:[NSString stringWithFormat:@\"DROP TABLE IF EXISTS %%@\", table]\n"
       "                        parameters:@[]\n"
       "                             error:NULL];\n"
       "    fprintf(stdout, \"phase5b-router-ok\\n\");\n"
       "  }\n"
       "  return 0;\n"
       "}\n",
      escapedDSN, escapedTable];

  NSError *writeError = nil;
  BOOL wrote = [source writeToFile:sourcePath
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:&writeError];
  XCTAssertTrue(wrote);
  XCTAssertNil(writeError);
  if (!wrote) {
    return;
  }

  NSString *compileCommand = [NSString stringWithFormat:
      @"source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && clang $(gnustep-config --objc-flags) "
       "-fobjc-arc -I%@/src/Arlen -I%@/src/Arlen/Data %@ %@/src/Arlen/Data/ALNDatabaseAdapter.m "
       "%@/src/Arlen/Data/ALNDatabaseRouter.m %@/src/Arlen/Data/ALNPg.m %@/src/Arlen/Data/ALNSQLBuilder.m "
       "%@/src/Arlen/Data/ALNPostgresSQLBuilder.m -o %@ $(gnustep-config --base-libs) -ldl -lcrypto",
      repoRoot,
      repoRoot,
      sourcePath,
      repoRoot,
      repoRoot,
      repoRoot,
      repoRoot,
      repoRoot,
      binaryPath];
  int compileCode = 0;
  NSString *compileOutput = [self runShellCapture:compileCommand exitCode:&compileCode];
  XCTAssertEqual(0, compileCode, @"%@", compileOutput);

  int runCode = 0;
  NSString *runOutput = [self runShellCapture:binaryPath exitCode:&runCode];
  XCTAssertEqual(0, runCode, @"%@", runOutput);
  XCTAssertTrue([runOutput containsString:@"phase5b-router-ok"], @"%@", runOutput);
}

@end
