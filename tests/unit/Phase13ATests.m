#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

#import "ALNApplication.h"
#import "ALNModuleSystem.h"

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

@end
