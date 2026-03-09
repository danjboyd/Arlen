#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

#import "ALNEOCTranspiler.h"
#import "ALNModuleSystem.h"

@interface Phase13BTests : XCTestCase
@end

@implementation Phase13BTests

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

- (void)testModuleAssetStagingPrefersAppOverrides {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13b-assets"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"config/modules.plist"]
                          content:@"{\n"
                                  "  modules = (\n"
                                  "    { identifier = \"demo\"; path = \"modules/demo\"; enabled = YES; }\n"
                                  "  );\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/demo/module.plist"]
                          content:@"{\n"
                                  "  identifier = \"demo\";\n"
                                  "  version = \"1.0.0\";\n"
                                  "  principalClass = \"Phase13AAlphaModule\";\n"
                                  "}\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/demo/Resources/Public/site.css"]
                          content:@"module-css\n"]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"public/modules/demo/site.css"]
                          content:@"app-css\n"]);

    NSString *outputDir = [appRoot stringByAppendingPathComponent:@"build/module_assets"];
    NSError *error = nil;
    NSArray<NSString *> *stagedFiles = nil;
    BOOL ok = [ALNModuleSystem stagePublicAssetsAtAppRoot:appRoot
                                                outputDir:outputDir
                                              stagedFiles:&stagedFiles
                                                    error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    XCTAssertTrue([stagedFiles containsObject:@"modules/demo/site.css"]);

    NSString *stagedPath = [outputDir stringByAppendingPathComponent:@"modules/demo/site.css"];
    NSString *contents = [NSString stringWithContentsOfFile:stagedPath
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    XCTAssertEqualObjects(@"app-css\n", contents);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testModuleTemplateLogicalPrefixMatchesAppOverrideNamespace {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *logicalPath =
      [transpiler logicalPathForTemplatePath:@"/tmp/modules/demo/Resources/Templates/users/index.html.eoc"
                                 templateRoot:@"/tmp/modules/demo/Resources/Templates"
                                logicalPrefix:@"modules/demo"];
  XCTAssertEqualObjects(@"modules/demo/users/index.html.eoc", logicalPath);
}

- (void)testPublicMountCollisionsAreDiagnosedDeterministically {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13b-collision"];
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
    NSString *alphaManifest =
        @"{\n"
         "  identifier = \"alpha\";\n"
         "  version = \"1.0.0\";\n"
         "  principalClass = \"Phase13AAlphaModule\";\n"
         "  publicMounts = (\n"
         "    { prefix = \"/shared\"; path = \"Resources/Public\"; }\n"
         "  );\n"
         "}\n";
    NSString *betaManifest =
        @"{\n"
         "  identifier = \"beta\";\n"
         "  version = \"1.0.0\";\n"
         "  principalClass = \"Phase13ABetaModule\";\n"
         "  publicMounts = (\n"
         "    { prefix = \"/shared\"; path = \"Resources/Public\"; }\n"
         "  );\n"
         "}\n";
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/alpha/module.plist"]
                          content:alphaManifest]);
    XCTAssertTrue([self writeFile:[appRoot stringByAppendingPathComponent:@"modules/beta/module.plist"]
                          content:betaManifest]);

    NSError *error = nil;
    NSArray *definitions = [ALNModuleSystem sortedModuleDefinitionsAtAppRoot:appRoot error:&error];
    XCTAssertNil(definitions);
    XCTAssertNotNil(error);
    XCTAssertTrue([[error localizedDescription] containsString:@"collision"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

@end
