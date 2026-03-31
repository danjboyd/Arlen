#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNMSSQL.h"
#import "ALNPg.h"

@interface Phase24WindowsTransportSmokeTests : XCTestCase
@end

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
  XCTAssertFalse([detail containsString:@"libpq shared library not found"]);
  XCTAssertFalse([detail containsString:@"required libpq symbols missing"]);
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
