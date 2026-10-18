#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

#import "ALNApplication.h"
#import "ALNModuleSystem.h"
#import "../shared/ALNTestSupport.h"

@interface Phase13AAlphaModule : NSObject <ALNModule>
@end

@implementation Phase13AAlphaModule

- (NSString *)moduleIdentifier {
  return @"alpha";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  (void)application;
  (void)error;
  return YES;
}

@end

@interface Phase13ABetaModule : NSObject <ALNModule>
@end

@implementation Phase13ABetaModule

- (NSString *)moduleIdentifier {
  return @"beta";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  (void)application;
  (void)error;
  return YES;
}

@end

@interface Phase13AGammaModule : NSObject <ALNModule>
@end

@implementation Phase13AGammaModule

- (NSString *)moduleIdentifier {
  return @"gamma";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  (void)application;
  (void)error;
  return YES;
}

@end

@interface Phase13ANotAModule : NSObject
@end

@implementation Phase13ANotAModule
@end

@interface Phase13ATests : XCTestCase
@end

@implementation Phase13ATests

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

- (void)testManifestParsingRejectsMalformedMetadata {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13a-bad-manifest"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"broken\"; path = \"modules/broken\"; enabled = YES; }\n"
                                  "  );\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/broken/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"broken\";\n"
                                  "  version = \"not-a-version\";\n"
                                  "}\n"]);

    NSError *error = nil;
    NSArray *definitions = [ALNModuleSystem moduleDefinitionsAtAppRoot:appRoot error:&error];
    XCTAssertNil(definitions);
    XCTAssertNotNil(error);
    XCTAssertTrue([[error localizedDescription] containsString:@"semantic version"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testDependencyOrderingIsDeterministic {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13a-order"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"gamma\"; path = \"modules/gamma\"; enabled = YES; },\n"
                                  "    { identifier = \"beta\"; path = \"modules/beta\"; enabled = YES; },\n"
                                  "    { identifier = \"alpha\"; path = \"modules/alpha\"; enabled = YES; }\n"
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
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/gamma/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"gamma\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"Phase13AGammaModule\";\n"
                                  "}\n"]);

    NSError *error = nil;
    NSArray<ALNModuleDefinition *> *definitions =
        [ALNModuleSystem sortedModuleDefinitionsAtAppRoot:appRoot error:&error];
    XCTAssertNotNil(definitions);
    XCTAssertNil(error);
    NSArray<NSString *> *identifiers = [definitions valueForKey:@"identifier"];
    XCTAssertEqualObjects((@[ @"alpha", @"beta", @"gamma" ]), identifiers);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testDuplicateModuleIdentifiersFailClosed {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13a-duplicate"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"alpha\"; path = \"modules/alpha-a\"; enabled = YES; },\n"
                                  "    { identifier = \"alpha\"; path = \"modules/alpha-b\"; enabled = YES; }\n"
                                  "  );\n"
                                  "}\n"]);
    NSString *manifest =
        @"{\n"
         "  identifier = \"alpha\";\n"
         "  version = \"1.0.0\";\n"
         "  principalClass = \"Phase13AAlphaModule\";\n"
         "}\n";
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha-a/module.plist"]
                          content:manifest]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha-b/module.plist"]
                          content:manifest]);

    NSError *error = nil;
    NSArray *definitions = [ALNModuleSystem sortedModuleDefinitionsAtAppRoot:appRoot error:&error];
    XCTAssertNil(definitions);
    XCTAssertNotNil(error);
    XCTAssertTrue([[error localizedDescription] containsString:@"duplicate"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testPrincipalClassProtocolValidationFailsClosed {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13a-protocol"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"alpha\"; path = \"modules/alpha\"; enabled = YES; }\n"
                                  "  );\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"alpha\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"Phase13ANotAModule\";\n"
                                  "}\n"]);

    ALNApplication *application = [[ALNApplication alloc] initWithConfig:@{
      @"appRoot" : appRoot,
      @"environment" : @"test",
    }];
    NSError *error = nil;
    NSArray *modules = [ALNModuleSystem loadModulesForApplication:application error:&error];
    XCTAssertNil(modules);
    XCTAssertNotNil(error);
    XCTAssertTrue([[error localizedDescription] containsString:@"ALNModule"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testContentDigestTracksFileContentsAndPaths {
  NSString *root = [self createTempDirectoryWithPrefix:@"phase13a-digest"];
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }

  @try {
    NSString *moduleRoot = [root stringByAppendingPathComponent:@"alpha"];
    XCTAssertTrue([self writeFile:[moduleRoot stringByAppendingPathComponent:@"module.plist"]
                          content:@"{ identifier = \"alpha\"; version = \"1.0.0\"; }\n"]);
    XCTAssertTrue([self writeFile:[moduleRoot stringByAppendingPathComponent:@"Sources/Alpha.m"]
                          content:@"// v1\n"]);

    NSError *error = nil;
    NSDictionary<NSString *, NSString *> *files =
        [ALNModuleSystem contentFileDigestsForModuleAtPath:moduleRoot error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects((@[ @"Sources/Alpha.m", @"module.plist" ]),
                          [[files allKeys] sortedArrayUsingSelector:@selector(compare:)]);

    NSString *original = [ALNModuleSystem contentDigestForModuleAtPath:moduleRoot error:&error];
    XCTAssertTrue([original hasPrefix:@"sha256:"]);
    XCTAssertEqualObjects(original, [ALNModuleSystem contentDigestForModuleAtPath:moduleRoot error:NULL]);

    XCTAssertTrue([self writeFile:[moduleRoot stringByAppendingPathComponent:@".DS_Store"] content:@"noise\n"]);
    XCTAssertEqualObjects(original, [ALNModuleSystem contentDigestForModuleAtPath:moduleRoot error:NULL]);

    XCTAssertTrue([self writeFile:[moduleRoot stringByAppendingPathComponent:@"Sources/Alpha.m"]
                          content:@"// v2\n"]);
    NSString *changed = [ALNModuleSystem contentDigestForModuleAtPath:moduleRoot error:NULL];
    XCTAssertNotEqualObjects(original, changed);

    XCTAssertTrue([[NSFileManager defaultManager] moveItemAtPath:[moduleRoot stringByAppendingPathComponent:@"Sources/Alpha.m"]
                                                          toPath:[moduleRoot stringByAppendingPathComponent:@"Sources/Beta.m"]
                                                           error:NULL]);
    XCTAssertNotEqualObjects(changed, [ALNModuleSystem contentDigestForModuleAtPath:moduleRoot error:NULL]);

    XCTAssertNil([ALNModuleSystem contentDigestForModuleAtPath:[root stringByAppendingPathComponent:@"missing"]
                                                         error:&error]);
    XCTAssertNotNil(error);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
  }
}

- (void)testModulesLockPreservesContentDigest {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13a-lock-digest"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    NSError *error = nil;
    NSDictionary *document = @{
      @"modules" : @[
        @{ @"identifier" : @"alpha", @"version" : @"1.0.0", @"contentDigest" : @"sha256:abc" },
        @{ @"identifier" : @"beta", @"version" : @"1.0.0" },
      ]
    };
    BOOL written = [ALNModuleSystem writeModulesLockDocument:document appRoot:appRoot error:&error];
    XCTAssertTrue(written, @"%@", error);
    NSArray<NSDictionary *> *records = [ALNModuleSystem installedModuleRecordsAtAppRoot:appRoot error:&error];
    XCTAssertEqual((NSUInteger)2, [records count]);
    XCTAssertEqualObjects(@"sha256:abc", records[0][@"contentDigest"]);
    XCTAssertEqualObjects(@"", records[1][@"contentDigest"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testFrameworkCopyDiagnosticsReportOutdatedAndChangedVendoredModules {
  NSString *root = [self createTempDirectoryWithPrefix:@"phase13a-outdated"];
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }

  @try {
    NSString *appRoot = [root stringByAppendingPathComponent:@"app"];
    NSString *frameworkRoot = [root stringByAppendingPathComponent:@"framework"];
    NSString *vendored = [appRoot stringByAppendingPathComponent:@"modules/alpha"];
    NSString *upstream = [frameworkRoot stringByAppendingPathComponent:@"modules/alpha"];
    NSString *manifest = @"{ identifier = \"alpha\"; version = \"%@\"; principalClass = \"Phase13AAlphaModule\"; }\n";
    NSString *manifest100 = [NSString stringWithFormat:manifest, @"1.0.0"];
    NSString *manifest120 = [NSString stringWithFormat:manifest, @"1.2.0"];
    NSString *manifest130 = [NSString stringWithFormat:manifest, @"1.3.0"];
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{ modules = ( { identifier = \"alpha\"; path = \"modules/alpha\"; enabled = YES; } ); }\n"]);
    XCTAssertTrue([self writeFile:[vendored stringByAppendingPathComponent:@"module.plist"]
                          content:manifest100]);
    XCTAssertTrue([self writeFile:[vendored stringByAppendingPathComponent:@"Sources/Alpha.m"] content:@"// v1\n"]);
    XCTAssertTrue([self writeFile:[upstream stringByAppendingPathComponent:@"module.plist"]
                          content:manifest100]);
    XCTAssertTrue([self writeFile:[upstream stringByAppendingPathComponent:@"Sources/Alpha.m"] content:@"// v1\n"]);

    // Same version, same files: nothing to report.
    XCTAssertEqualObjects(@[], [ALNModuleSystem frameworkCopyDiagnosticsAtAppRoot:appRoot
                                                                    frameworkRoot:frameworkRoot
                                                                   compareContent:YES]);
    // No framework root known: nothing to compare against.
    XCTAssertEqualObjects(@[], [ALNModuleSystem frameworkCopyDiagnosticsAtAppRoot:appRoot
                                                                    frameworkRoot:@""
                                                                   compareContent:YES]);

    // Same version, different files: only the content comparison reports it.
    XCTAssertTrue([self writeFile:[upstream stringByAppendingPathComponent:@"Sources/Alpha.m"] content:@"// v1 fix\n"]);
    NSArray<NSDictionary *> *diagnostics = [ALNModuleSystem frameworkCopyDiagnosticsAtAppRoot:appRoot
                                                                                frameworkRoot:frameworkRoot
                                                                               compareContent:YES];
    XCTAssertEqual((NSUInteger)1, [diagnostics count]);
    XCTAssertEqualObjects(@"module_framework_copy_differs", [diagnostics firstObject][@"code"]);
    XCTAssertEqualObjects(@[], [ALNModuleSystem frameworkCopyDiagnosticsAtAppRoot:appRoot
                                                                    frameworkRoot:frameworkRoot
                                                                   compareContent:NO]);

    // A newer framework version is outdated, with or without the file comparison.
    XCTAssertTrue([self writeFile:[upstream stringByAppendingPathComponent:@"module.plist"]
                          content:manifest120]);
    for (NSNumber *compareContent in @[ @YES, @NO ]) {
      diagnostics = [ALNModuleSystem frameworkCopyDiagnosticsAtAppRoot:appRoot
                                                         frameworkRoot:frameworkRoot
                                                        compareContent:[compareContent boolValue]];
      XCTAssertEqual((NSUInteger)1, [diagnostics count]);
      NSDictionary *entry = [diagnostics firstObject];
      XCTAssertEqualObjects(@"module_outdated", entry[@"code"]);
      XCTAssertEqualObjects(@"warning", entry[@"status"]);
      XCTAssertEqualObjects(@"alpha", entry[@"module"]);
      XCTAssertTrue([entry[@"message"] containsString:@"1.0.0"], @"%@", entry);
      XCTAssertTrue([entry[@"message"] containsString:@"1.2.0"], @"%@", entry);
      XCTAssertTrue([entry[@"detail"] containsString:@"arlen module upgrade alpha"], @"%@", entry);
      XCTAssertTrue([entry[@"detail"] containsString:@"arlen module migrate"], @"%@", entry);
    }

    // A framework copy with a pre-release suffix is not a valid manifest, so it is skipped, not compared.
    NSString *manifestPrerelease = [NSString stringWithFormat:manifest, @"9.0.0-rc1"];
    XCTAssertTrue([self writeFile:[upstream stringByAppendingPathComponent:@"module.plist"] content:manifestPrerelease]);
    XCTAssertEqualObjects(@[], [ALNModuleSystem frameworkCopyDiagnosticsAtAppRoot:appRoot
                                                                    frameworkRoot:frameworkRoot
                                                                   compareContent:YES]);
    XCTAssertTrue([self writeFile:[upstream stringByAppendingPathComponent:@"module.plist"] content:manifest120]);

    // A vendored copy newer than the framework's is not outdated.
    XCTAssertTrue([self writeFile:[vendored stringByAppendingPathComponent:@"module.plist"]
                          content:manifest130]);
    XCTAssertEqualObjects(@[], [ALNModuleSystem frameworkCopyDiagnosticsAtAppRoot:appRoot
                                                                    frameworkRoot:frameworkRoot
                                                                   compareContent:NO]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
  }
}

- (void)testDoctorReportsLocallyModifiedVendoredModule {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13a-local-edit"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    NSString *vendored = [appRoot stringByAppendingPathComponent:@"modules/alpha"];
    XCTAssertTrue([self writeFile:[vendored stringByAppendingPathComponent:@"module.plist"]
                          content:@"{ identifier = \"alpha\"; version = \"1.0.0\"; principalClass = \"Phase13AAlphaModule\"; }\n"]);
    XCTAssertTrue([self writeFile:[vendored stringByAppendingPathComponent:@"Sources/Alpha.m"] content:@"// v1\n"]);
    NSString *digest = [ALNModuleSystem contentDigestForModuleAtPath:vendored error:NULL];
    XCTAssertTrue([digest hasPrefix:@"sha256:"]);
    NSError *error = nil;
    NSDictionary *lock = @{
      @"modules" : @[ @{ @"identifier" : @"alpha", @"path" : @"modules/alpha", @"enabled" : @YES, @"contentDigest" : digest } ]
    };
    XCTAssertTrue([ALNModuleSystem writeModulesLockDocument:lock appRoot:appRoot error:&error], @"%@", error);

    NSArray<NSString *> * (^codes)(void) = ^NSArray<NSString *> * {
      NSMutableArray<NSString *> *found = [NSMutableArray array];
      for (NSDictionary *entry in [ALNModuleSystem doctorDiagnosticsAtAppRoot:appRoot config:@{} error:NULL] ?: @[]) {
        if ([entry[@"module"] isEqualToString:@"alpha"]) {
          [found addObject:entry[@"code"] ?: @""];
        }
      }
      return found;
    };
    XCTAssertFalse([codes() containsObject:@"module_locally_modified"]);
    XCTAssertTrue([self writeFile:[vendored stringByAppendingPathComponent:@"Sources/Alpha.m"] content:@"// local patch\n"]);
    XCTAssertTrue([codes() containsObject:@"module_locally_modified"], @"%@", codes());
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

@end
