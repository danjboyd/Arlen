#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNDatabaseTestSupport.h"
#import "../shared/ALNTestSupport.h"

@interface Phase13ModulePostgresIntegrationTests : XCTestCase
@end

@implementation Phase13ModulePostgresIntegrationTests

- (NSString *)pgTestDSN {
  return ALNTestEnvironmentString(@"ARLEN_PG_TEST_DSN");
}

- (NSString *)requiredPGTestDSNForSelector:(SEL)selector {
  return ALNTestRequiredEnvironmentString(
      @"ARLEN_PG_TEST_DSN",
      NSStringFromClass([self class]),
      NSStringFromSelector(selector),
      @"set ARLEN_PG_TEST_DSN to run PostgreSQL module integration coverage");
}

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  return ALNTestTemporaryDirectory(prefix);
}

- (BOOL)writeFile:(NSString *)path content:(NSString *)content {
  NSError *error = nil;
  if (!ALNTestWriteUTF8File(path, content, &error)) {
    XCTFail(@"failed writing %@: %@", path, error.localizedDescription);
    return NO;
  }
  return YES;
}

- (NSString *)runShellCapture:(NSString *)command exitCode:(int *)exitCode {
  return ALNTestRunShellCapture(command, exitCode);
}

- (NSDictionary *)parseJSONDictionary:(NSString *)output {
  NSError *error = nil;
  NSDictionary *payload = ALNTestJSONDictionaryFromString(output, &error);
  XCTAssertNil(error, @"invalid JSON: %@\n%@", error.localizedDescription, output);
  return payload ?: @{};
}

- (void)testModuleMigrateAppliesAndUpgradesNamespacedMigrations {
  NSString *dsn = [self requiredPGTestDSNForSelector:_cmd];
  if (dsn == nil) {
    return;
  }

  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13-module-pg"];
  NSString *tableAlpha =
      [[[NSString stringWithFormat:@"phase13_alpha_%@", [[NSUUID UUID] UUIDString]] lowercaseString]
          stringByReplacingOccurrencesOfString:@"-" withString:@""];
  NSString *tableBeta =
      [[[NSString stringWithFormat:@"phase13_beta_%@", [[NSUUID UUID] UUIDString]] lowercaseString]
          stringByReplacingOccurrencesOfString:@"-" withString:@""];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    NSString *configContents =
        [NSString stringWithFormat:@"{\n"
                                   "  host = \"127.0.0.1\";\n"
                                   "  port = 3000;\n"
                                   "  database = {\n"
                                   "    connectionString = \"%@\";\n"
                                   "    poolSize = 2;\n"
                                   "  };\n"
                                   "}\n",
                                   [dsn stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/app.plist"]
                          content:configContents]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/environments/development.plist"]
                          content:@"{}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"alpha\"; path = \"modules/alpha\"; enabled = YES; },\n"
                                  "    { identifier = \"beta\"; path = \"modules/beta\"; enabled = YES; }\n"
                                  "  );\n"
                                  "}\n"]);

    NSString *moduleClass =
        @"#import <Foundation/Foundation.h>\n"
         "#import \"ALNApplication.h\"\n"
         "#import \"ALNModuleSystem.h\"\n\n"
         "@interface AlphaModule : NSObject <ALNModule>\n"
         "@end\n\n"
         "@implementation AlphaModule\n"
         "- (NSString *)moduleIdentifier { return @\"alpha\"; }\n"
         "- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error { (void)application; (void)error; return YES; }\n"
         "@end\n\n"
         "@interface BetaModule : NSObject <ALNModule>\n"
         "@end\n\n"
         "@implementation BetaModule\n"
         "- (NSString *)moduleIdentifier { return @\"beta\"; }\n"
         "- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error { (void)application; (void)error; return YES; }\n"
         "@end\n";

    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"alpha\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"AlphaModule\";\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/Sources/AlphaModule.m"]
                          content:moduleClass]);
    NSString *alphaMigrationSQL =
        [NSString stringWithFormat:@"CREATE TABLE %@ (id SERIAL PRIMARY KEY, name TEXT);\n", tableAlpha];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/Migrations/001_alpha.sql"]
                          content:alphaMigrationSQL]);

    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/beta/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"beta\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"BetaModule\";\n"
                                  "  dependencies = (\n"
                                  "    { identifier = \"alpha\"; version = \">= 1.0.0\"; }\n"
                                  "  );\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/beta/Sources/BetaModule.m"]
                          content:moduleClass]);
    NSString *betaMigrationSQL =
        [NSString stringWithFormat:@"CREATE TABLE %@ (id SERIAL PRIMARY KEY, value TEXT);\n", tableBeta];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/beta/Migrations/001_beta.sql"]
                          content:betaMigrationSQL]);

    int code = 0;
    NSString *buildOutput = [self runShellCapture:[NSString stringWithFormat:@"cd %@ && source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh && make arlen",
                                                                             repoRoot]
                                         exitCode:&code];
    XCTAssertEqual(0, code, @"%@", buildOutput);

    NSString *dryRun = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module migrate --env development --dry-run --json",
        appRoot, repoRoot]
                                   exitCode:&code];
    XCTAssertEqual(0, code, @"%@", dryRun);
    NSDictionary *dryRunPayload = [self parseJSONDictionary:dryRun];
    XCTAssertEqual(2u, (unsigned)[dryRunPayload[@"files"] count]);

    NSString *firstRun = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module migrate --env development --json",
        appRoot, repoRoot]
                                    exitCode:&code];
    XCTAssertEqual(0, code, @"%@", firstRun);
    NSDictionary *firstPayload = [self parseJSONDictionary:firstRun];
    XCTAssertEqual(2u, (unsigned)[firstPayload[@"files"] count]);

    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"alpha\";\n"
                                  "  version = \"1.1.0\";\n"
                                  "  principalClass = \"AlphaModule\";\n"
                                  "}\n"]);
    NSString *alphaUpgradeSQL =
        [NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN note TEXT;\n", tableAlpha];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/Migrations/002_alpha_upgrade.sql"]
                          content:alphaUpgradeSQL]);

    NSString *secondRun = [self runShellCapture:[NSString stringWithFormat:
        @"cd %@ && %@/build/arlen module migrate --env development --json",
        appRoot, repoRoot]
                                     exitCode:&code];
    XCTAssertEqual(0, code, @"%@", secondRun);
    NSDictionary *secondPayload = [self parseJSONDictionary:secondRun];
    XCTAssertEqual(1u, (unsigned)[secondPayload[@"files"] count]);
    XCTAssertTrue([secondPayload[@"files"][0] containsString:@"alpha:002_alpha_upgrade.sql"]);

    NSString *countAlpha = [self runShellCapture:[NSString stringWithFormat:@"psql %s -Atc \"SELECT COUNT(*) FROM %@\"",
                                                                             [dsn UTF8String], tableAlpha]
                                        exitCode:&code];
    XCTAssertEqual(0, code, @"%@", countAlpha);
    XCTAssertEqualObjects(@"0", [countAlpha stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);

    NSString *migrationVersions = [self runShellCapture:[NSString stringWithFormat:
        @"psql %s -Atc \"SELECT version FROM arlen_schema_migrations ORDER BY version\"",
        [dsn UTF8String]]
                                             exitCode:&code];
    XCTAssertEqual(0, code, @"%@", migrationVersions);
    XCTAssertTrue([migrationVersions containsString:@"alpha::001_alpha"]);
    XCTAssertTrue([migrationVersions containsString:@"alpha::002_alpha_upgrade"]);
    XCTAssertTrue([migrationVersions containsString:@"beta::001_beta"]);
  } @finally {
    (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                           [dsn UTF8String], tableAlpha]
                       exitCode:NULL];
    (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DROP TABLE IF EXISTS %@\" >/dev/null 2>&1",
                                                           [dsn UTF8String], tableBeta]
                       exitCode:NULL];
    (void)[self runShellCapture:[NSString stringWithFormat:@"psql %s -c \"DELETE FROM arlen_schema_migrations WHERE version LIKE 'alpha::%%' OR version LIKE 'beta::%%'\" >/dev/null 2>&1",
                                                           [dsn UTF8String]]
                       exitCode:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

@end
