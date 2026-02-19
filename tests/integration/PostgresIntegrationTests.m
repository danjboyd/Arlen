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

@end
