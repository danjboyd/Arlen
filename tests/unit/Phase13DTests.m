#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

#import "ALNModuleSystem.h"

@interface Phase13DTests : XCTestCase
@end

@implementation Phase13DTests

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  NSString *templatePath =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-XXXXXX", prefix]];
  char *buffer = strdup([templatePath fileSystemRepresentation]);
  char *created = mkdtemp(buffer);
  NSString *result = created ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:created
                                                                                             length:strlen(created)]
                             : nil;
  free(buffer);
  return result;
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

@end
