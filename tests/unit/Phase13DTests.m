#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

#import "ALNModuleSystem.h"
#import "../shared/ALNTestSupport.h"

@interface Phase13DTests : XCTestCase
@end

@implementation Phase13DTests

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  return ALNTestTemporaryDirectory(prefix);
}

- (BOOL)writeFile:(NSString *)path content:(NSString *)content {
  NSError *error = nil;
  NSString *directory = [path stringByDeletingLastPathComponent];
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

- (NSString *)readFile:(NSString *)path {
  NSError *error = nil;
  NSString *contents =
      [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNotNil(contents, @"failed reading %@: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  return contents ?: @"";
}

- (void)testModuleConfigDefaultsAreMergedAndAppValuesWin {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13d-config"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"auth\"; path = \"modules/auth\"; enabled = YES; }\n"
                                  "  );\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/auth/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"auth\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"Phase13AAlphaModule\";\n"
                                  "  config = {\n"
                                  "    defaults = {\n"
                                  "      auth = { enabled = YES; issuer = \"module-issuer\"; };\n"
                                  "    };\n"
                                  "  };\n"
                                  "}\n"]);

    NSArray<NSDictionary *> *diagnostics = nil;
    NSDictionary *merged = [ALNModuleSystem configByApplyingModuleDefaultsToConfig:@{
      @"auth" : @{ @"enabled" : @(NO) },
      @"appRoot" : appRoot,
    }
                                                                   appRoot:appRoot
                                                                    strict:NO
                                                               diagnostics:&diagnostics
                                                                     error:NULL];
    XCTAssertEqualObjects(@(NO), merged[@"auth"][@"enabled"]);
    XCTAssertEqualObjects(@"module-issuer", merged[@"auth"][@"issuer"]);
    XCTAssertEqual(0u, (unsigned)[diagnostics count]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testRequiredConfigDiagnosticsAndMigrationOrderingAreDeterministic {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13d-required"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"alpha\"; path = \"modules/alpha\"; enabled = YES; },\n"
                                  "    { identifier = \"beta\"; path = \"modules/beta\"; enabled = YES; }\n"
                                  "  );\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"alpha\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"Phase13AAlphaModule\";\n"
                                  "  config = { requiredKeys = (\"session.secret\"); };\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/Migrations/001_alpha.sql"]
                          content:@"SELECT 1;\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/beta/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"beta\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"Phase13ABetaModule\";\n"
                                  "  dependencies = (\n"
                                  "    { identifier = \"alpha\"; version = \">= 1.0.0\"; }\n"
                                  "  );\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/beta/Migrations/001_beta.sql"]
                          content:@"SELECT 1;\n"]);

    NSArray<NSDictionary *> *diagnostics = nil;
    NSDictionary *merged = [ALNModuleSystem configByApplyingModuleDefaultsToConfig:@{ @"appRoot" : appRoot }
                                                                           appRoot:appRoot
                                                                            strict:NO
                                                                       diagnostics:&diagnostics
                                                                             error:NULL];
    XCTAssertNotNil(merged);
    XCTAssertTrue([[diagnostics valueForKey:@"code"] containsObject:@"module_required_config_missing"]);

    NSError *error = nil;
    NSArray<NSDictionary *> *plans = [ALNModuleSystem migrationPlansAtAppRoot:appRoot
                                                                        config:merged
                                                                         error:&error];
    XCTAssertNotNil(plans);
    XCTAssertNil(error);
    NSArray<NSString *> *identifiers = [plans valueForKey:@"identifier"];
    XCTAssertEqualObjects((@[ @"alpha", @"beta" ]), identifiers);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testDoctorDiagnosticsRemainAppendableAfterConfigMerge {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13d-doctor"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"alpha\"; path = \"modules/alpha\"; enabled = YES; },\n"
                                  "    { identifier = \"beta\"; path = \"modules/beta\"; enabled = YES; }\n"
                                  "  );\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"alpha\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"Phase13AAlphaModule\";\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/beta/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"beta\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"Phase13ABetaModule\";\n"
                                  "  dependencies = (\n"
                                  "    { identifier = \"alpha\"; version = \">= 1.0.0\"; }\n"
                                  "  );\n"
                                  "}\n"]);

    NSError *error = nil;
    NSArray<NSDictionary *> *diagnostics =
        [ALNModuleSystem doctorDiagnosticsAtAppRoot:appRoot
                                             config:@{ @"appRoot" : appRoot }
                                              error:&error];
    XCTAssertNotNil(diagnostics);
    XCTAssertNil(error);
    XCTAssertTrue([[diagnostics valueForKey:@"code"] containsObject:@"modules_loaded"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testFirstPartyModuleDefaultsUseRelativeAPIPathsAndDoctorDoesNotCrash {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13d-first-party-doctor"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    NSArray<NSString *> *moduleIDs = @[ @"auth", @"admin-ui", @"jobs", @"notifications" ];
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    for (NSString *moduleID in moduleIDs) {
      [entries addObject:[NSString stringWithFormat:@"    { identifier = \"%@\"; path = \"modules/%@\"; enabled = YES; }",
                                                    moduleID, moduleID]];
      NSString *sourcePath =
          [repoRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"modules/%@/module.plist", moduleID]];
      NSString *targetPath =
          [appRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"modules/%@/module.plist", moduleID]];
      XCTAssertTrue([self writeFile:targetPath content:[self readFile:sourcePath]]);
    }

    NSString *modulesConfig = [NSString stringWithFormat:@"{\n"
                                                           "  modules = (\n"
                                                           "%@\n"
                                                           "  );\n"
                                                           "}\n",
                                                           [entries componentsJoinedByString:@",\n"]];
    NSString *modulesConfigPath = [appRoot stringByAppendingPathComponent:@"config/modules.plist"];
    XCTAssertTrue([self writeFile:modulesConfigPath content:modulesConfig]);

    NSArray<NSDictionary *> *diagnostics = nil;
    NSDictionary *merged = [ALNModuleSystem configByApplyingModuleDefaultsToConfig:@{
      @"appRoot" : appRoot,
      @"session" : @{ @"secret" : @"phase13d-secret" },
      @"database" : @{ @"connectionString" : @"postgres://phase13d:test@localhost/phase13d" },
    }
                                                                   appRoot:appRoot
                                                                    strict:NO
                                                               diagnostics:&diagnostics
                                                                     error:NULL];
    XCTAssertNotNil(merged);
    XCTAssertEqualObjects(@"api", merged[@"authModule"][@"paths"][@"apiPrefix"]);
    XCTAssertEqualObjects(@"api", merged[@"adminUI"][@"paths"][@"apiPrefix"]);
    XCTAssertEqualObjects(@"api", merged[@"jobsModule"][@"paths"][@"apiPrefix"]);
    XCTAssertEqualObjects(@"api", merged[@"notificationsModule"][@"paths"][@"apiPrefix"]);

    NSError *__autoreleasing error = nil;
    NSArray<NSDictionary *> *doctorDiagnostics =
        [ALNModuleSystem doctorDiagnosticsAtAppRoot:appRoot
                                             config:merged
                                              error:&error];
    XCTAssertNotNil(doctorDiagnostics);
    XCTAssertNil(error);
    XCTAssertTrue([[doctorDiagnostics valueForKey:@"code"] containsObject:@"modules_loaded"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testDoctorFlagsAuthModuleWithSessionsOnAndCSRFOff {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13d-auth-csrf"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/auth/module.plist"]
                          content:[self readFile:[repoRoot stringByAppendingPathComponent:@"modules/auth/module.plist"]]]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"auth\"; path = \"modules/auth\"; enabled = YES; }\n"
                                  "  );\n"
                                  "}\n"]);
    NSDictionary *session = @{ @"enabled" : @YES, @"secret" : @"phase13d-secret-0123456789abcdef0123" };
    NSDictionary *(^diagnosticFor)(NSDictionary *) = ^NSDictionary *(NSDictionary *config) {
      NSMutableDictionary *full = [NSMutableDictionary dictionaryWithDictionary:config];
      full[@"appRoot"] = appRoot;
      full[@"session"] = session;
      for (NSDictionary *entry in [ALNModuleSystem doctorDiagnosticsAtAppRoot:appRoot config:full error:NULL]) {
        if ([entry[@"code"] isEqualToString:@"module_csrf_disabled"]) {
          return entry;
        }
      }
      return nil;
    };

    NSDictionary *pinnedOff = diagnosticFor(@{ @"csrf" : @{ @"enabled" : @NO } });
    XCTAssertEqualObjects(@"error", pinnedOff[@"status"]);
    XCTAssertEqualObjects(@"auth", pinnedOff[@"module"]);
    XCTAssertEqualObjects(@"csrf.enabled", pinnedOff[@"key_path"]);

    XCTAssertNil(diagnosticFor(@{ @"csrf" : @{ @"enabled" : @YES } }));
    XCTAssertNil(diagnosticFor(@{}));

    NSDictionary *optedOut = diagnosticFor(@{
      @"csrf" : @{ @"enabled" : @NO },
      @"authModule" : @{ @"allowWithoutCSRF" : @YES },
    });
    XCTAssertEqualObjects(@"warning", optedOut[@"status"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testCompatibilityChecksFailClosed {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13d-compat"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"future\"; path = \"modules/future\"; enabled = YES; }\n"
                                  "  );\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/future/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"future\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"Phase13AAlphaModule\";\n"
                                  "  compatibility = { arlenVersion = \">= 9.0.0\"; };\n"
                                  "}\n"]);

    NSError *error = nil;
    NSArray *definitions = [ALNModuleSystem sortedModuleDefinitionsAtAppRoot:appRoot error:&error];
    XCTAssertNil(definitions);
    XCTAssertNotNil(error);
    XCTAssertTrue([[error localizedDescription] containsString:@"requires Arlen"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testAuthOptionalJobsDependencySupportsAuthOnlyAndAuthWithJobsDoctor {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  for (NSArray<NSString *> *moduleIDs in @[ @[ @"auth" ], @[ @"jobs", @"auth" ] ]) {
    NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13d-auth-jobs-doctor"];
    XCTAssertNotNil(appRoot);
    if (appRoot == nil) continue;
    @try {
      NSMutableArray<NSString *> *entries = [NSMutableArray array];
      for (NSString *identifier in moduleIDs) {
        NSString *source = [repoRoot stringByAppendingPathComponent:
            [NSString stringWithFormat:@"modules/%@/module.plist", identifier]];
        NSString *target = [appRoot stringByAppendingPathComponent:
            [NSString stringWithFormat:@"modules/%@/module.plist", identifier]];
        XCTAssertTrue([self writeFile:target content:[self readFile:source]]);
        [entries addObject:[NSString stringWithFormat:
            @"{ identifier = \"%@\"; path = \"modules/%@\"; enabled = YES; }", identifier, identifier]];
      }
      NSString *registry = [NSString stringWithFormat:@"{ modules = ( %@ ); }", [entries componentsJoinedByString:@", "]];
      XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"] content:registry]);
      NSError *error = nil;
      NSArray<ALNModuleDefinition *> *definitions = [ALNModuleSystem sortedModuleDefinitionsAtAppRoot:appRoot error:&error];
      XCTAssertNotNil(definitions, @"%@", error);
      XCTAssertEqualObjects(moduleIDs, [definitions valueForKey:@"identifier"]);
      NSArray<NSDictionary *> *doctor = [ALNModuleSystem doctorDiagnosticsAtAppRoot:appRoot
                                                                            config:@{ @"appRoot" : appRoot }
                                                                             error:&error];
      XCTAssertNotNil(doctor, @"%@", error);
      XCTAssertTrue([[doctor valueForKey:@"code"] containsObject:@"modules_loaded"]);
      XCTAssertFalse([[doctor valueForKey:@"code"] containsObject:@"module_validation_failed"]);
    } @finally {
      [[NSFileManager defaultManager] removeItemAtPath:appRoot error:NULL];
    }
  }
}

@end
