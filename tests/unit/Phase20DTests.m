#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDatabaseInspector.h"

@interface Phase20DFakeAdapter : NSObject <ALNDatabaseAdapter>

@property(nonatomic, copy) NSString *adapter;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *rowsToReturn;
@property(nonatomic, assign) NSInteger queryCount;

- (instancetype)initWithAdapterName:(NSString *)adapterName;

@end

@implementation Phase20DFakeAdapter

- (instancetype)initWithAdapterName:(NSString *)adapterName {
  self = [super init];
  if (self != nil) {
    _adapter = [adapterName copy] ?: @"";
    _rowsToReturn = @[];
    _queryCount = 0;
  }
  return self;
}

- (NSString *)adapterName {
  return self.adapter;
}

- (id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError **)error {
  (void)error;
  return nil;
}

- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection {
  (void)connection;
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  (void)sql;
  (void)parameters;
  if (error != NULL) {
    *error = nil;
  }
  self.queryCount += 1;
  return self.rowsToReturn;
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  (void)sql;
  (void)parameters;
  if (error != NULL) {
    *error = nil;
  }
  return 0;
}

- (BOOL)withTransactionUsingBlock:
            (BOOL (^)(id<ALNDatabaseConnection> connection, NSError **error))block
                            error:(NSError **)error {
  (void)block;
  if (error != NULL) {
    *error = nil;
  }
  return YES;
}

@end

@interface Phase20DTests : XCTestCase
@end

@implementation Phase20DTests

- (NSDictionary *)reflectionFixture {
  NSString *root = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *path = [root stringByAppendingPathComponent:@"tests/fixtures/phase20/postgres_reflection_contract.json"];
  NSData *data = [NSData dataWithContentsOfFile:path];
  XCTAssertNotNil(data);
  if (data == nil) {
    return @{};
  }

  NSError *error = nil;
  NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(fixture);
  return [fixture isKindOfClass:[NSDictionary class]] ? fixture : @{};
}

- (void)testPostgresInspectorNormalizesFixtureRows {
  NSDictionary *fixture = [self reflectionFixture];
  NSArray *rawRows = [fixture[@"raw_rows"] isKindOfClass:[NSArray class]] ? fixture[@"raw_rows"] : @[];
  NSArray *expected = [fixture[@"normalized_rows"] isKindOfClass:[NSArray class]] ? fixture[@"normalized_rows"] : @[];

  NSError *error = nil;
  NSArray *normalized = [ALNPostgresInspector normalizedColumnsFromInspectionRows:rawRows error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(expected, normalized);
}

- (void)testDatabaseInspectorRoutesPostgresAdaptersThroughNormalizedContract {
  NSDictionary *fixture = [self reflectionFixture];
  NSArray *rawRows = [fixture[@"raw_rows"] isKindOfClass:[NSArray class]] ? fixture[@"raw_rows"] : @[];
  NSArray *expected = [fixture[@"normalized_rows"] isKindOfClass:[NSArray class]] ? fixture[@"normalized_rows"] : @[];

  Phase20DFakeAdapter *adapter = [[Phase20DFakeAdapter alloc] initWithAdapterName:@"postgresql"];
  adapter.rowsToReturn = rawRows;

  NSError *error = nil;
  NSArray *normalized = [ALNDatabaseInspector inspectSchemaColumnsForAdapter:adapter error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)1, adapter.queryCount);
  XCTAssertEqualObjects(expected, normalized);
}

- (void)testDatabaseInspectorRejectsUnsupportedAdapters {
  Phase20DFakeAdapter *adapter = [[Phase20DFakeAdapter alloc] initWithAdapterName:@"sqlite"];

  NSError *error = nil;
  NSArray *normalized = [ALNDatabaseInspector inspectSchemaColumnsForAdapter:adapter error:&error];
  XCTAssertNil(normalized);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNDatabaseInspectorErrorDomain, error.domain);
  XCTAssertEqual((NSInteger)ALNDatabaseInspectorErrorUnsupportedAdapter, error.code);
}

@end
