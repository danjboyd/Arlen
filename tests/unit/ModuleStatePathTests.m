#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"
#import "ALNSearchModule.h"
#import "ALNStorageModule.h"

// GitHub issue 76: relative module state paths must resolve against the app root,
// not the process working directory (`arlen jobs worker` runs from the framework).
@interface ModuleStatePathTests : XCTestCase
@property(nonatomic, copy) NSString *appRoot;
@end

@implementation ModuleStatePathTests

- (void)setUp {
  [super setUp];
  self.appRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                             [NSString stringWithFormat:@"arlen-module-state-%@",
                                                                        [[NSUUID UUID] UUIDString]]];
  [[NSFileManager defaultManager] createDirectoryAtPath:self.appRoot
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
}

- (void)tearDown {
  [[NSFileManager defaultManager] removeItemAtPath:self.appRoot error:NULL];
  [super tearDown];
}

- (void)testAppRootPathAndRelativeResolution {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{ @"appRoot" : self.appRoot }];
  XCTAssertEqualObjects([self.appRoot stringByStandardizingPath], [app appRootPath]);
  XCTAssertEqualObjects([[self.appRoot stringByAppendingPathComponent:@"var/state.plist"] stringByStandardizingPath],
                        [app pathRelativeToAppRoot:@"var/state.plist"]);
  XCTAssertEqualObjects(@"/srv/app/state.plist", [app pathRelativeToAppRoot:@"/srv/app/../app/state.plist"]);

  ALNApplication *noRoot = [[ALNApplication alloc] initWithConfig:@{}];
  NSString *expectedFallback = [[[NSProcessInfo processInfo] environment][@"ARLEN_APP_ROOT"] length] > 0
                                   ? [[[NSProcessInfo processInfo] environment][@"ARLEN_APP_ROOT"] stringByStandardizingPath]
                                   : [[NSFileManager defaultManager] currentDirectoryPath];
  XCTAssertEqualObjects(expectedFallback, [noRoot appRootPath]);
}

- (void)testModuleStatePathsResolveAgainstAppRootNotWorkingDirectory {
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  XCTAssertFalse([cwd isEqualToString:self.appRoot]);
  NSString *suffix = [[NSUUID UUID] UUIDString];
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"development",
    @"logFormat" : @"json",
    @"appRoot" : self.appRoot,
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[] },
      @"persistence" : @{ @"path" : [NSString stringWithFormat:@"var/module_state/jobs-%@.plist", suffix] },
    },
    @"storageModule" : @{ @"persistence" : @{ @"path" : [NSString stringWithFormat:@"var/module_state/storage-%@.plist", suffix] } },
    @"notificationsModule" : @{},
    @"searchModule" : @{},
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNStorageModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNSearchModule alloc] init] registerWithApplication:app error:&error], @"%@", error);

  NSString *root = [self.appRoot stringByStandardizingPath];
  NSDictionary *paths = @{
    @"jobs (configured)" : [[ALNJobsModuleRuntime sharedRuntime] valueForKey:@"persistencePath"] ?: @"",
    @"storage (configured)" : [[ALNStorageModuleRuntime sharedRuntime] valueForKey:@"statePath"] ?: @"",
    @"notifications (default)" : [[ALNNotificationsModuleRuntime sharedRuntime] valueForKey:@"statePath"] ?: @"",
    @"search (default)" : [[ALNSearchModuleRuntime sharedRuntime] valueForKey:@"statePath"] ?: @"",
  };
  for (NSString *label in paths) {
    NSString *path = paths[label];
    XCTAssertTrue([path hasPrefix:[root stringByAppendingString:@"/var/module_state/"]], @"%@ -> %@", label, path);
  }
  NSString *jobsFile = [NSString stringWithFormat:@"jobs-%@.plist", suffix];
  XCTAssertTrue([paths[@"jobs (configured)"] hasSuffix:jobsFile]);
  XCTAssertTrue([paths[@"search (default)"] hasSuffix:@"search-development.plist"], @"%@", paths[@"search (default)"]);
  NSString *cwdJobsPath = [[cwd stringByAppendingPathComponent:@"var/module_state"] stringByAppendingPathComponent:jobsFile];
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:cwdJobsPath]);
}

@end
