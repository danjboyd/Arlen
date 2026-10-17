#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

#import "ALNModuleSystem.h"
#import "../shared/ALNTestSupport.h"

@interface Phase13CTests : XCTestCase
@end

@implementation Phase13CTests

- (NSString *)createTempDirectoryWithPrefix:(NSString *)prefix {
  return ALNTestTemporaryDirectory(prefix);
}

- (void)testModulesLockDocumentIsSortedDeterministically {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13c-lock"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    NSError *error = nil;
    BOOL ok = [ALNModuleSystem writeModulesLockDocument:@{
      @"modules" : @[
        @{ @"identifier" : @"gamma", @"path" : @"modules/gamma", @"enabled" : @(YES) },
        @{ @"identifier" : @"alpha", @"path" : @"modules/alpha", @"enabled" : @(YES) },
        @{ @"identifier" : @"beta", @"path" : @"modules/beta", @"enabled" : @(YES) },
      ]
    }
                                                appRoot:appRoot
                                                  error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);

    NSArray<NSDictionary *> *records = [ALNModuleSystem installedModuleRecordsAtAppRoot:appRoot error:&error];
    XCTAssertNotNil(records);
    XCTAssertNil(error);
    NSArray<NSString *> *identifiers = [records valueForKey:@"identifier"];
    XCTAssertEqualObjects((@[ @"alpha", @"beta", @"gamma" ]), identifiers);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

- (void)testInstalledModuleRecordsNormalizePathsAndEnabledFlags {
  NSString *appRoot = [self createTempDirectoryWithPrefix:@"phase13c-records"];
  XCTAssertNotNil(appRoot);
  if (appRoot == nil) {
    return;
  }

  @try {
    NSError *error = nil;
    BOOL ok = [ALNModuleSystem writeModulesLockDocument:@{
      @"modules" : @[
        @{ @"identifier" : @"auth", @"enabled" : @(YES), @"version" : @"1.0.0" },
      ]
    }
                                                appRoot:appRoot
                                                  error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);

    NSArray<NSDictionary *> *records = [ALNModuleSystem installedModuleRecordsAtAppRoot:appRoot error:&error];
    XCTAssertEqual(1u, (unsigned)[records count]);
    NSDictionary *record = records[0];
    XCTAssertEqualObjects(@"modules/auth", record[@"path"]);
    XCTAssertEqualObjects(@"auth", record[@"identifier"]);
    XCTAssertEqualObjects(@"1.0.0", record[@"version"]);
    XCTAssertEqualObjects(@(YES), record[@"enabled"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:appRoot error:nil];
  }
}

@end
