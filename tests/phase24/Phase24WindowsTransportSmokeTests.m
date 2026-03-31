#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNMSSQL.h"
#import "ALNPg.h"

@interface Phase24WindowsTransportSmokeTests : XCTestCase
@end

static NSString *Phase24TrimmedString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL Phase24PathExists(NSString *path) {
  return [[NSFileManager defaultManager] fileExistsAtPath:Phase24TrimmedString(path)];
}

static BOOL Phase24LibraryExistsOnPATH(NSArray<NSString *> *fileNames) {
  NSString *pathValue = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"];
  if (![pathValue isKindOfClass:[NSString class]] || [pathValue length] == 0) {
    return NO;
  }

  NSString *separator = [pathValue containsString:@";"] ? @";" : @":";
  NSArray<NSString *> *entries = [pathValue componentsSeparatedByString:separator];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  for (NSString *entry in entries) {
    NSString *directory = [Phase24TrimmedString(entry)
        stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
    if ([directory length] == 0) {
      continue;
    }
    for (NSString *fileName in fileNames ?: @[]) {
      NSString *candidate = [directory stringByAppendingPathComponent:fileName ?: @""];
      if ([fileManager fileExistsAtPath:candidate]) {
        return YES;
      }
    }
  }
  return NO;
}

static BOOL Phase24LibraryExpectedOnWindowsHost(NSString *environmentVariable,
                                                NSArray<NSString *> *absoluteCandidates,
                                                NSArray<NSString *> *pathCandidates) {
  NSString *configuredPath =
      Phase24TrimmedString([[[NSProcessInfo processInfo] environment] objectForKey:environmentVariable]);
  if ([configuredPath length] > 0) {
    if (Phase24PathExists(configuredPath)) {
      return YES;
    }
    return Phase24LibraryExistsOnPATH(@[ [configuredPath lastPathComponent] ]);
  }

  for (NSString *candidate in absoluteCandidates ?: @[]) {
    if (Phase24PathExists(candidate)) {
      return YES;
    }
  }
  return Phase24LibraryExistsOnPATH(pathCandidates);
}

@implementation Phase24WindowsTransportSmokeTests

- (void)testPostgresTransportLoadsBeforeConnectionFailure {
#if !ARLEN_WINDOWS_PREVIEW
  return;
#endif

  NSError *adapterError = nil;
  ALNPg *database = [[ALNPg alloc]
      initWithConnectionString:@"host=127.0.0.1 port=1 dbname=arlen_phase24_loader_test connect_timeout=1"
                 maxConnections:1
                          error:&adapterError];
  XCTAssertNotNil(database);
  XCTAssertNil(adapterError);
  if (database == nil) {
    return;
  }

  NSError *connectionError = nil;
  ALNPgConnection *connection = [database acquireConnection:&connectionError];
  XCTAssertNil(connection);
  XCTAssertNotNil(connectionError);
  XCTAssertEqualObjects(ALNPgErrorDomain, connectionError.domain);
  XCTAssertEqual((NSInteger)ALNPgErrorConnectionFailed, connectionError.code);

  NSString *detail =
      [connectionError.userInfo[@"detail"] isKindOfClass:[NSString class]] ? connectionError.userInfo[@"detail"] : @"";
  BOOL hostHasLibpq = Phase24LibraryExpectedOnWindowsHost(
      @"ARLEN_LIBPQ_LIBRARY",
      @[ @"C:/msys64/clang64/bin/libpq-5.dll", @"C:/msys64/clang64/bin/libpq.dll" ],
      @[ @"libpq-5.dll", @"libpq.dll" ]);
  if (hostHasLibpq) {
    XCTAssertFalse([detail containsString:@"libpq shared library not found"]);
    XCTAssertFalse([detail containsString:@"required libpq symbols missing"]);
  } else {
    XCTAssertTrue([detail containsString:@"libpq shared library not found"] ||
                  [detail containsString:@"required libpq symbols missing"]);
  }
}

- (void)testMSSQLODBCTransportLoadsBeforeConnectionFailure {
#if !ARLEN_WINDOWS_PREVIEW
  return;
#endif

  NSError *adapterError = nil;
  ALNMSSQL *database = [[ALNMSSQL alloc]
      initWithConnectionString:
          @"Driver={ODBC Driver 18 for SQL Server};Server=tcp:127.0.0.1,1;Uid=sa;Pwd=DefinitelyWrong123!;Encrypt=no;TrustServerCertificate=yes;Connection Timeout=1;LoginTimeout=1;"
                maxConnections:1
                         error:&adapterError];
  XCTAssertNotNil(database);
  XCTAssertNil(adapterError);
  if (database == nil) {
    return;
  }

  NSError *connectionError = nil;
  ALNMSSQLConnection *connection = [database acquireConnection:&connectionError];
  XCTAssertNil(connection);
  XCTAssertNotNil(connectionError);
  XCTAssertEqualObjects(ALNMSSQLErrorDomain, connectionError.domain);
  XCTAssertNotEqual((NSInteger)ALNMSSQLErrorTransportUnavailable, connectionError.code);

  NSString *detail =
      [connectionError.userInfo[@"detail"] isKindOfClass:[NSString class]] ? connectionError.userInfo[@"detail"] : @"";
  XCTAssertFalse([detail containsString:@"ODBC shared library not found"]);
  XCTAssertFalse([detail containsString:@"required ODBC symbols missing"]);
}

@end
