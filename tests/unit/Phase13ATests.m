#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

#import "ALNApplication.h"
#import "ALNConfig.h"
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

// The error Phase13AFailingModule returns; tests replace it to cover the
// config-key spellings modules use.
static NSError *Phase13AFailingModuleError = nil;

static NSError *Phase13ADefaultFailingModuleError(void) {
  return [NSError errorWithDomain:@"Phase13AFailingModule"
                             code:7
                         userInfo:@{
                           NSLocalizedDescriptionKey : @"beta.secret is required",
                           @"key_path" : @"beta.secret",
                         }];
}

@interface Phase13AFailingModule : NSObject <ALNModule>
@end

@implementation Phase13AFailingModule

- (NSString *)moduleIdentifier {
  return @"beta";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  (void)application;
  if (error != NULL) {
    *error = Phase13AFailingModuleError ?: Phase13ADefaultFailingModuleError();
  }
  return NO;
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


- (NSString *)writeAppWithFailingMiddleModule {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13a-load-failure"];
  if (appRoot == nil) {
    return nil;
  }
  BOOL ok = [self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                    content:@"{\n"
                            "  modules = (\n"
                            "    { identifier = \"alpha\"; path = \"modules/alpha\"; enabled = YES; },\n"
                            "    { identifier = \"beta\"; path = \"modules/beta\"; enabled = YES; },\n"
                            "    { identifier = \"gamma\"; path = \"modules/gamma\"; enabled = YES; }\n"
                            "  );\n"
                            "}\n"];
  ok = ok && [self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/module.plist"]
                     content:@"{ identifier = \"alpha\"; version = \"1.0.0\"; principalClass = \"Phase13AAlphaModule\"; }\n"];
  ok = ok && [self writeFile:[appRoot stringByAppendingPathComponent:@"modules/beta/module.plist"]
                     content:@"{ identifier = \"beta\"; version = \"1.0.0\"; principalClass = \"Phase13AFailingModule\";\n"
                              "  dependencies = ( { identifier = \"alpha\"; version = \">= 1.0.0\"; } ); }\n"];
  ok = ok && [self writeFile:[appRoot stringByAppendingPathComponent:@"modules/gamma/module.plist"]
                     content:@"{ identifier = \"gamma\"; version = \"1.0.0\"; principalClass = \"Phase13AGammaModule\";\n"
                              "  dependencies = ( { identifier = \"beta\"; version = \">= 1.0.0\"; } ); }\n"];
  if (!ok) {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
    return nil;
  }
  return appRoot;
}

- (void)testModuleLoadFailureNamesTheModuleAndRefusesStartupOutsideDevelopment {
  NSString *appRoot = [self writeAppWithFailingMiddleModule];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    for (NSString *environment in @[ @"production", @"staging" ]) {
      ALNApplication *application = [[ALNApplication alloc] initWithConfig:@{
        @"appRoot" : appRoot,
        @"environment" : environment,
        @"logFormat" : @"json",
      }];
      NSError *loadError = application.moduleLoadError;
      XCTAssertNotNil(loadError, @"%@", environment);
      XCTAssertEqualObjects(ALNModuleSystemErrorDomain, loadError.domain);
      XCTAssertEqualObjects(@"beta", loadError.userInfo[@"module"]);
      XCTAssertEqualObjects(@"beta.secret", loadError.userInfo[@"key_path"]);
      XCTAssertEqualObjects((@[ @"beta", @"gamma" ]), loadError.userInfo[@"not_loaded"]);
      XCTAssertTrue([loadError.localizedDescription containsString:@"module beta failed to load"]);
      XCTAssertTrue([loadError.localizedDescription containsString:@"beta.secret is required"]);
      XCTAssertEqualObjects((@[ @"alpha" ]), [application.modules valueForKey:@"moduleIdentifier"]);
      XCTAssertTrue([application moduleLoadErrorPreventsStartup], @"%@", environment);

      NSError *startError = nil;
      XCTAssertFalse([application startWithError:&startError], @"%@", environment);
      XCTAssertEqualObjects(@"beta", startError.userInfo[@"module"]);
      XCTAssertFalse(application.isStarted);
    }
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testModuleLoadFailureKeepsDevelopmentAndTestServing {
  NSString *appRoot = [self writeAppWithFailingMiddleModule];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    for (NSString *environment in @[ @"development", @"test", @"Development", @" TEST " ]) {
      ALNApplication *application = [[ALNApplication alloc] initWithConfig:@{
        @"appRoot" : appRoot,
        @"environment" : environment,
        @"logFormat" : @"json",
      }];
      XCTAssertNotNil(application.moduleLoadError, @"%@", environment);
      XCTAssertEqualObjects(@"beta", application.moduleLoadError.userInfo[@"module"]);
      XCTAssertFalse([application moduleLoadErrorPreventsStartup], @"%@", environment);
      NSError *startError = nil;
      XCTAssertTrue([application startWithError:&startError], @"%@: %@", environment, startError);
    }
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testDoctorWarnsWhenAppConfigDisablesSessionsAModuleNeeds {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13a-sessions-doctor"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{ modules = ( { identifier = \"alpha\"; path = \"modules/alpha\"; enabled = YES; } ); }\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/module.plist"]
                          content:@"{ identifier = \"alpha\"; version = \"1.0.0\"; principalClass = \"Phase13AAlphaModule\";\n"
                                  "  config = { defaults = { session = { enabled = YES; }; }; }; }\n"]);

    NSArray<NSDictionary *> *(^codes)(NSDictionary *) = ^NSArray<NSDictionary *> *(NSDictionary *config) {
      NSArray<NSDictionary *> *diagnostics =
          [ALNModuleSystem doctorDiagnosticsAtAppRoot:appRoot config:config error:NULL] ?: @[];
      return [diagnostics filteredArrayUsingPredicate:
                              [NSPredicate predicateWithFormat:@"code == %@", @"module_sessions_disabled"]];
    };

    NSArray<NSDictionary *> *pinned = codes(@{ @"session" : @{ @"enabled" : @NO } });
    XCTAssertEqual((NSUInteger)1, [pinned count]);
    XCTAssertEqualObjects(@"warning", pinned.firstObject[@"status"]);
    XCTAssertEqualObjects(@"alpha", pinned.firstObject[@"module"]);
    XCTAssertEqual((NSUInteger)0, [codes(@{ @"session" : @{ @"enabled" : @YES } }) count]);
    XCTAssertEqual((NSUInteger)0, [codes(@{}) count]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}


- (void)testEnvironmentClassifierIgnoresCaseAndWhitespace {
  XCTAssertEqual(ALNEnvironmentKindDevelopment, ALNEnvironmentKindForName(@"development"));
  XCTAssertEqual(ALNEnvironmentKindDevelopment, ALNEnvironmentKindForName(@"Development"));
  XCTAssertEqual(ALNEnvironmentKindDevelopment, ALNEnvironmentKindForName(@" DEVELOPMENT\n"));
  XCTAssertEqual(ALNEnvironmentKindTest, ALNEnvironmentKindForName(@"Test"));
  XCTAssertEqual(ALNEnvironmentKindProduction, ALNEnvironmentKindForName(@"production"));
  XCTAssertEqual(ALNEnvironmentKindProduction, ALNEnvironmentKindForName(@"staging"));
  XCTAssertEqual(ALNEnvironmentKindProduction, ALNEnvironmentKindForName(@"dev"));
  XCTAssertEqual(ALNEnvironmentKindProduction, ALNEnvironmentKindForName(@""));
  XCTAssertEqual(ALNEnvironmentKindProduction, ALNEnvironmentKindForName(nil));
  XCTAssertTrue(ALNEnvironmentIsDevelopmentLike(@"Development"));
  XCTAssertTrue(ALNEnvironmentIsDevelopmentLike(@"test"));
  XCTAssertFalse(ALNEnvironmentIsDevelopmentLike(@"Production"));
  XCTAssertFalse(ALNEnvironmentIsDevelopmentLike(@"preview"));
}

- (void)testModuleLoadFailureFindsTheConfigKeyWhateverItIsCalled {
  NSString *appRoot = [self writeAppWithFailingMiddleModule];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  NSError *nested = [NSError errorWithDomain:@"Inner" code:1 userInfo:@{ @"key_path" : @"beta.inner" }];
  NSArray<NSArray *> *cases = @[
    @[ @{ NSLocalizedDescriptionKey : @"bad value", @"config_key" : @"storageModule.signingSecret" },
       @"storageModule.signingSecret" ],
    @[ @{ NSLocalizedDescriptionKey : @"bad value", @"keyPath" : @"beta.camel" }, @"beta.camel" ],
    @[ @{ NSLocalizedDescriptionKey : @"bad value", @"Config-Path" : @"beta.scanned" }, @"beta.scanned" ],
    @[ @{ NSLocalizedDescriptionKey : @"bad value", NSUnderlyingErrorKey : nested }, @"beta.inner" ],
  ];
  @try {
    for (NSArray *testCase in cases) {
      Phase13AFailingModuleError = [NSError errorWithDomain:@"Phase13AFailingModule" code:8 userInfo:testCase[0]];
      ALNApplication *application = [[ALNApplication alloc] initWithConfig:@{
        @"appRoot" : appRoot,
        @"environment" : @"production",
        @"logFormat" : @"json",
      }];
      NSError *loadError = application.moduleLoadError;
      XCTAssertEqualObjects(testCase[1], loadError.userInfo[@"key_path"]);
      NSString *expected = [NSString stringWithFormat:@"(config key %@)", testCase[1]];
      XCTAssertTrue([loadError.localizedDescription containsString:expected], @"%@", loadError.localizedDescription);
    }

    Phase13AFailingModuleError = [NSError errorWithDomain:@"Phase13AFailingModule"
                                                     code:9
                                                 userInfo:@{ NSLocalizedDescriptionKey : @"no key here" }];
    ALNApplication *application = [[ALNApplication alloc] initWithConfig:@{
      @"appRoot" : appRoot,
      @"environment" : @"production",
      @"logFormat" : @"json",
    }];
    XCTAssertNil(application.moduleLoadError.userInfo[@"key_path"]);
    XCTAssertEqualObjects(@"module beta failed to load: no key here", application.moduleLoadError.localizedDescription);
  } @finally {
    Phase13AFailingModuleError = nil;
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

@end
