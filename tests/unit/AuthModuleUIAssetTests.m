#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNAuthModule.h"

// GitHub issue 51: module-ui assets must be reachable under the module's own
// paths.prefix so a path-scoped reverse proxy can serve them.
@interface AuthModuleUIAssetTests : XCTestCase
@end

@implementation AuthModuleUIAssetTests

- (ALNApplication *)applicationWithAuthConfig:(NSDictionary *)authConfig mountModuleAssets:(BOOL)mountModuleAssets {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logLevel" : @"error",
    @"csrf" : @{ @"enabled" : @NO },
    @"database" : @{ @"connectionString" : @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
    @"authModule" : authConfig,
  }];
  if (mountModuleAssets) {
    // The module loader mounts Resources/Public here before registerWithApplication:.
    NSString *publicPath = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent:@"modules/auth/Resources/Public"];
    XCTAssertTrue([app mountStaticDirectory:publicPath atPrefix:@"/modules/auth" allowExtensions:nil]);
  }
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  return app;
}

// Static mounts are served by the HTTP server ahead of dispatch, so check the mount table.
- (NSString *)directoryMountedAt:(NSString *)prefix app:(ALNApplication *)app {
  for (NSDictionary *mount in app.staticMounts) {
    if ([mount[@"prefix"] isEqual:prefix]) {
      return mount[@"directory"];
    }
  }
  return nil;
}

- (void)testModuleUIAssetsAreServedAndLinkedUnderThePathPrefix {
  ALNApplication *app = [self applicationWithAuthConfig:@{ @"paths" : @{ @"prefix" : @"/context/auth" } }
                                     mountModuleAssets:YES];
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  XCTAssertEqualObjects(@"/context/auth/assets", runtime.uiAssetPrefix);
  XCTAssertEqualObjects(@"/context/auth/assets/auth.css", [runtime authUIAssetPathForFilename:@"auth.css"]);
  XCTAssertEqualObjects(@"/context/auth/assets/auth_totp_qr.js", [runtime authUIAssetPathForFilename:@"auth_totp_qr.js"]);
  NSString *moduleDirectory = [self directoryMountedAt:@"/modules/auth" app:app];
  XCTAssertNotNil(moduleDirectory);
  // Same files under the prefix; /modules/auth stays mounted for existing apps and cached pages.
  XCTAssertEqualObjects(moduleDirectory, [self directoryMountedAt:@"/context/auth/assets" app:app]);
  XCTAssertTrue([[NSFileManager defaultManager]
      fileExistsAtPath:[moduleDirectory stringByAppendingPathComponent:@"auth_totp_qr.js"]]);
}

- (void)testDefaultPrefixServesAssetsUnderAuthAssets {
  ALNApplication *app = [self applicationWithAuthConfig:@{} mountModuleAssets:YES];
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  XCTAssertEqualObjects(@"/auth/assets/auth.css", [runtime authUIAssetPathForFilename:@"auth.css"]);
  XCTAssertNotNil([self directoryMountedAt:@"/auth/assets" app:app]);
}

- (void)testWithoutTheModulePublicMountAssetPathsStayOnModulesAuth {
  ALNApplication *app = [self applicationWithAuthConfig:@{ @"paths" : @{ @"prefix" : @"/context/auth" } }
                                     mountModuleAssets:NO];
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  XCTAssertEqualObjects(@"/modules/auth/auth.css", [runtime authUIAssetPathForFilename:@"auth.css"]);
  XCTAssertNil([self directoryMountedAt:@"/context/auth/assets" app:app]);
}

@end
