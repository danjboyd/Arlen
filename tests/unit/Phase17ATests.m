#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNMigrationRunner.h"
#import "ALNSQLDialect.h"
#import "ALNSQLBuilder.h"

@interface Phase17AFakeDialect : NSObject <ALNSQLDialect>

@property(nonatomic, copy) NSString *dialectNameValue;

@end

@implementation Phase17AFakeDialect

- (instancetype)init {
  self = [super init];
  if (self) {
    _dialectNameValue = @"mssql";
  }
  return self;
}

- (NSString *)dialectName {
  return self.dialectNameValue ?: @"mssql";
}

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  return @{ @"dialect" : [self dialectName] ?: @"" };
}

- (NSDictionary *)compileBuilder:(ALNSQLBuilder *)builder error:(NSError **)error {
  return [builder build:error];
}

- (NSString *)migrationStateTableCreateSQLForTableName:(NSString *)tableName error:(NSError **)error {
  (void)error;
  return [NSString stringWithFormat:@"STATE CREATE %@", tableName ?: @""];
}

- (NSString *)migrationVersionsSelectSQLForTableName:(NSString *)tableName error:(NSError **)error {
  (void)error;
  return [NSString stringWithFormat:@"STATE SELECT %@", tableName ?: @""];
}

- (NSString *)migrationVersionInsertSQLForTableName:(NSString *)tableName error:(NSError **)error {
  (void)error;
  return [NSString stringWithFormat:@"STATE INSERT %@", tableName ?: @""];
}

@end

@interface Phase17AFakeAdapter : NSObject <ALNDatabaseAdapter, ALNDatabaseConnection>

@property(nonatomic, strong) id<ALNSQLDialect> sqlDialectImpl;
@property(nonatomic, strong) NSMutableOrderedSet<NSString *> *appliedVersions;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *commandLog;
@property(nonatomic, strong) NSMutableArray<NSString *> *executedStatements;

@end

@implementation Phase17AFakeAdapter

- (instancetype)init {
  self = [super init];
  if (self) {
    _appliedVersions = [[NSMutableOrderedSet alloc] init];
    _commandLog = [NSMutableArray array];
    _executedStatements = [NSMutableArray array];
  }
  return self;
}

- (NSString *)adapterName {
  return @"phase17a_fake";
}

- (id<ALNSQLDialect>)sqlDialect {
  return self.sqlDialectImpl;
}

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  return @{
    @"adapter" : @"phase17a_fake",
    @"dialect" : [[self.sqlDialectImpl dialectName] ?: @"" copy],
  };
}

- (id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError **)error {
  (void)error;
  return self;
}

- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection {
  (void)connection;
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  (void)parameters;
  (void)error;
  if ([sql hasPrefix:@"STATE SELECT "]) {
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    for (NSString *version in self.appliedVersions) {
      [rows addObject:@{ @"version" : version ?: @"" }];
    }
    return rows;
  }
  return @[];
}

- (NSDictionary *)executeQueryOne:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  return [[self executeQuery:sql parameters:parameters error:error] firstObject];
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  [self.commandLog addObject:@{
    @"sql" : sql ?: @"",
    @"parameters" : parameters ?: @[],
  }];
  if ([sql hasPrefix:@"STATE CREATE "]) {
    return 0;
  }
  if ([sql hasPrefix:@"STATE INSERT "]) {
    NSString *version =
        [[parameters firstObject] isKindOfClass:[NSString class]] ? [parameters firstObject] : @"";
    if ([version length] > 0) {
      [self.appliedVersions addObject:version];
    }
    return 1;
  }
  if ([sql rangeOfString:@"BROKEN" options:NSCaseInsensitiveSearch].location != NSNotFound) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase17ATests"
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"broken migration statement"
                               }];
    }
    return -1;
  }
  [self.executedStatements addObject:sql ?: @""];
  return 0;
}

- (BOOL)withTransactionUsingBlock:(BOOL (^)(id<ALNDatabaseConnection> connection,
                                            NSError **error))block
                            error:(NSError **)error {
  if (block == nil) {
    return NO;
  }
  NSArray<NSString *> *appliedSnapshot = [self.appliedVersions array];
  NSArray<NSString *> *statementSnapshot = [NSArray arrayWithArray:self.executedStatements];
  NSUInteger commandCountSnapshot = [self.commandLog count];

  NSError *blockError = nil;
  BOOL ok = block(self, &blockError);
  if (!ok) {
    self.appliedVersions = [[NSMutableOrderedSet alloc] initWithArray:appliedSnapshot];
    self.executedStatements = [statementSnapshot mutableCopy];
    while ([self.commandLog count] > commandCountSnapshot) {
      [self.commandLog removeLastObject];
    }
    if (error != NULL) {
      *error = blockError;
    }
    return NO;
  }
  return YES;
}

@end

@interface Phase17ATests : XCTestCase
@end

@implementation Phase17ATests

- (NSString *)temporaryDirectoryNamed:(NSString *)name {
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:
      @"arlen_phase17a_%@_%@",
      name ?: @"tmp",
      [[NSUUID UUID] UUIDString]]];
  NSError *error = nil;
  BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:path
                                           withIntermediateDirectories:YES
                                                            attributes:nil
                                                                 error:&error];
  XCTAssertTrue(created, @"%@", error);
  return path;
}

- (void)testMigrationRunnerUsesGenericAdapterContractAndMSSQLGoBatchNormalization {
  NSString *root = [self temporaryDirectoryNamed:@"go"];
  NSString *migrationPath = [root stringByAppendingPathComponent:@"001_create_users.sql"];
  NSString *sql = @"CREATE TABLE users (id INT)\nGO\nINSERT INTO users (id) VALUES (1);\n";
  XCTAssertTrue([sql writeToFile:migrationPath
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil]);

  Phase17AFakeDialect *dialect = [[Phase17AFakeDialect alloc] init];
  dialect.dialectNameValue = @"mssql";
  Phase17AFakeAdapter *adapter = [[Phase17AFakeAdapter alloc] init];
  adapter.sqlDialectImpl = dialect;

  NSError *error = nil;
  NSArray<NSString *> *pending =
      [ALNMigrationRunner pendingMigrationFilesAtPath:root
                                             database:adapter
                                       databaseTarget:@"analytics"
                                    versionNamespace:@"alpha"
                                               error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [pending count]);

  NSArray<NSString *> *appliedFiles = nil;
  BOOL ok = [ALNMigrationRunner applyMigrationsAtPath:root
                                             database:adapter
                                       databaseTarget:@"analytics"
                                    versionNamespace:@"alpha"
                                               dryRun:NO
                                         appliedFiles:&appliedFiles
                                                error:&error];
  XCTAssertTrue(ok, @"%@", error);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [appliedFiles count]);
  XCTAssertEqualObjects(@"alpha::001_create_users",
                        [[adapter.appliedVersions array] firstObject]);

  NSArray<NSString *> *executed = [NSArray arrayWithArray:adapter.executedStatements];
  XCTAssertEqual((NSUInteger)2, [executed count]);
  XCTAssertEqualObjects(@"CREATE TABLE users (id INT)\n", executed[0]);
  XCTAssertEqualObjects(@"\nINSERT INTO users (id) VALUES (1)", executed[1]);

  NSDictionary *createEntry = [adapter.commandLog firstObject];
  XCTAssertEqualObjects(@"STATE CREATE arlen_schema_migrations__analytics", createEntry[@"sql"]);
  NSDictionary *insertEntry = [adapter.commandLog lastObject];
  XCTAssertEqualObjects(@"STATE INSERT arlen_schema_migrations__analytics", insertEntry[@"sql"]);
}

- (void)testMigrationRunnerExecutesMultipleTopLevelStatementsForGenericDialects {
  NSString *root = [self temporaryDirectoryNamed:@"multi"];
  NSString *migrationPath = [root stringByAppendingPathComponent:@"001_bootstrap.sql"];
  NSString *sql =
      @"CREATE EXTENSION IF NOT EXISTS pg_trgm;\n"
       "CREATE TABLE example (id INT PRIMARY KEY, body TEXT);\n"
       "INSERT INTO example (id, body) VALUES (1, $$semi;colon$$);\n";
  XCTAssertTrue([sql writeToFile:migrationPath
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil]);

  Phase17AFakeDialect *dialect = [[Phase17AFakeDialect alloc] init];
  dialect.dialectNameValue = @"postgres";
  Phase17AFakeAdapter *adapter = [[Phase17AFakeAdapter alloc] init];
  adapter.sqlDialectImpl = dialect;

  NSError *error = nil;
  NSArray<NSString *> *appliedFiles = nil;
  BOOL ok = [ALNMigrationRunner applyMigrationsAtPath:root
                                             database:adapter
                                       databaseTarget:@"default"
                                    versionNamespace:nil
                                               dryRun:NO
                                         appliedFiles:&appliedFiles
                                                error:&error];
  XCTAssertTrue(ok, @"%@", error);
  XCTAssertNil(error);
  XCTAssertEqualObjects((@[ migrationPath ]), appliedFiles);
  XCTAssertEqualObjects((@[ @"001_bootstrap" ]), [adapter.appliedVersions array]);

  NSArray<NSString *> *executed = [NSArray arrayWithArray:adapter.executedStatements];
  XCTAssertEqual((NSUInteger)3, [executed count]);
  XCTAssertEqualObjects(@"CREATE EXTENSION IF NOT EXISTS pg_trgm", executed[0]);
  XCTAssertEqualObjects(@"\nCREATE TABLE example (id INT PRIMARY KEY, body TEXT)", executed[1]);
  XCTAssertEqualObjects(@"\nINSERT INTO example (id, body) VALUES (1, $$semi;colon$$)", executed[2]);
}

- (void)testMigrationRunnerRejectsSaveTransactionStatementsForGenericDialects {
  NSString *root = [self temporaryDirectoryNamed:@"forbidden"];
  NSString *migrationPath = [root stringByAppendingPathComponent:@"001_bad.sql"];
  NSString *sql = @"SAVE TRANSACTION before_work;\nCREATE TABLE users (id INT);\n";
  XCTAssertTrue([sql writeToFile:migrationPath
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:nil]);

  Phase17AFakeDialect *dialect = [[Phase17AFakeDialect alloc] init];
  Phase17AFakeAdapter *adapter = [[Phase17AFakeAdapter alloc] init];
  adapter.sqlDialectImpl = dialect;

  NSError *error = nil;
  NSArray<NSString *> *appliedFiles = nil;
  BOOL ok = [ALNMigrationRunner applyMigrationsAtPath:root
                                             database:adapter
                                       databaseTarget:@"default"
                                    versionNamespace:nil
                                               dryRun:NO
                                         appliedFiles:&appliedFiles
                                                error:&error];
  XCTAssertFalse(ok);
  XCTAssertNil(appliedFiles);
  XCTAssertNotNil(error);
  XCTAssertTrue([[error localizedDescription]
      containsString:@"failed applying migration 001_bad.sql"]);
  NSString *detail =
      [error.userInfo[@"detail"] isKindOfClass:[NSString class]] ? error.userInfo[@"detail"] : @"";
  XCTAssertTrue([detail containsString:@"top-level transaction control statement detected: SAVE TRAN"]);
}

@end
