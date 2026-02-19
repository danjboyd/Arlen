#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>

#import "ALNAdapterConformance.h"
#import "ALNContext.h"
#import "ALNDisplayGroup.h"
#import "ALNGDL2Adapter.h"
#import "ALNLogger.h"
#import "ALNPageState.h"
#import "ALNPerf.h"
#import "ALNPg.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSQLBuilder.h"

@interface Phase3BFakeAdapter : NSObject <ALNDatabaseAdapter, ALNDatabaseConnection>

@property(nonatomic, copy) NSString *lastSQL;
@property(nonatomic, copy) NSArray *lastParameters;
@property(nonatomic, copy) NSArray *rowsToReturn;
@property(nonatomic, assign) NSInteger commandResult;

@end

@implementation Phase3BFakeAdapter

- (instancetype)init {
  self = [super init];
  if (self) {
    _lastSQL = @"";
    _lastParameters = @[];
    _rowsToReturn = @[];
    _commandResult = 1;
  }
  return self;
}

- (NSString *)adapterName {
  return @"fake";
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
  (void)error;
  self.lastSQL = sql ?: @"";
  self.lastParameters = parameters ?: @[];
  return self.rowsToReturn ?: @[];
}

- (NSDictionary *)executeQueryOne:(NSString *)sql
                       parameters:(NSArray *)parameters
                            error:(NSError **)error {
  NSArray *rows = [self executeQuery:sql parameters:parameters error:error];
  return [rows firstObject];
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  (void)error;
  self.lastSQL = sql ?: @"";
  self.lastParameters = parameters ?: @[];
  return self.commandResult;
}

- (BOOL)withTransactionUsingBlock:(BOOL (^)(id<ALNDatabaseConnection> connection,
                                            NSError **error))block
                            error:(NSError **)error {
  if (block == nil) {
    return NO;
  }
  NSError *blockError = nil;
  BOOL ok = block(self, &blockError);
  if (!ok && error != NULL) {
    *error = blockError;
  }
  return ok;
}

@end

@interface Phase3BTests : XCTestCase
@end

@implementation Phase3BTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (void)testSQLBuilderSelectSnapshot {
  ALNSQLBuilder *builder = [ALNSQLBuilder selectFrom:@"users"
                                             columns:@[ @"id", @"name" ]];
  [[builder whereField:@"tenant_id" equals:@7] whereField:@"name" operator:@"ilike" value:@"%bo%"];
  [[builder orderByField:@"name" descending:NO] limit:20];
  [builder offset:40];

  NSError *error = nil;
  NSDictionary *built = [builder build:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(built);
  XCTAssertEqualObjects(@"SELECT \"id\", \"name\" FROM \"users\" WHERE \"tenant_id\" = $1 AND \"name\" ILIKE $2 ORDER BY \"name\" ASC LIMIT 20 OFFSET 40",
                        built[@"sql"]);
  NSArray *expectedSelectParams = @[ @7, @"%bo%" ];
  XCTAssertEqualObjects(expectedSelectParams, built[@"parameters"]);
}

- (void)testSQLBuilderInsertUpdateDeleteSnapshots {
  NSError *error = nil;

  ALNSQLBuilder *insert = [ALNSQLBuilder insertInto:@"users"
                                             values:@{
                                               @"role" : @"admin",
                                               @"name" : @"hank",
                                             }];
  NSDictionary *insertBuilt = [insert build:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"INSERT INTO \"users\" (\"name\", \"role\") VALUES ($1, $2)",
                        insertBuilt[@"sql"]);
  NSArray *expectedInsertParams = @[ @"hank", @"admin" ];
  XCTAssertEqualObjects(expectedInsertParams, insertBuilt[@"parameters"]);

  ALNSQLBuilder *update = [ALNSQLBuilder updateTable:@"users"
                                              values:@{
                                                @"name" : @"dale",
                                              }];
  [[update whereField:@"id" equals:@9] whereField:@"tenant_id" equals:@22];
  NSDictionary *updateBuilt = [update build:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"UPDATE \"users\" SET \"name\" = $1 WHERE \"id\" = $2 AND \"tenant_id\" = $3",
                        updateBuilt[@"sql"]);
  NSArray *expectedUpdateParams = @[ @"dale", @9, @22 ];
  XCTAssertEqualObjects(expectedUpdateParams, updateBuilt[@"parameters"]);

  ALNSQLBuilder *deleteBuilder = [ALNSQLBuilder deleteFrom:@"users"];
  [[deleteBuilder whereField:@"role" equals:@"guest"] whereFieldIn:@"id" values:@[ @1, @2 ]];
  NSDictionary *deleteBuilt = [deleteBuilder build:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"DELETE FROM \"users\" WHERE \"role\" = $1 AND \"id\" IN ($2, $3)",
                        deleteBuilt[@"sql"]);
  NSArray *expectedDeleteParams = @[ @"guest", @1, @2 ];
  XCTAssertEqualObjects(expectedDeleteParams, deleteBuilt[@"parameters"]);
}

- (void)testDisplayGroupBuildsQueryForFilterSortAndBatch {
  Phase3BFakeAdapter *adapter = [[Phase3BFakeAdapter alloc] init];
  adapter.rowsToReturn = @[ @{ @"id" : @"3", @"name" : @"Peggy" } ];

  ALNDisplayGroup *group = [[ALNDisplayGroup alloc] initWithAdapter:adapter
                                                           tableName:@"users"];
  group.fetchFields = @[ @"id", @"name" ];
  [group setFilterValue:@44 forField:@"tenant_id"];
  [group addSortField:@"name" descending:NO];
  group.batchSize = 10;
  group.batchIndex = 2;

  NSError *error = nil;
  BOOL fetched = [group fetch:&error];
  XCTAssertTrue(fetched);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"SELECT \"id\", \"name\" FROM \"users\" WHERE \"tenant_id\" = $1 ORDER BY \"name\" ASC LIMIT 10 OFFSET 20",
                        adapter.lastSQL);
  NSArray *expectedDisplayGroupParams = @[ @44 ];
  XCTAssertEqualObjects(expectedDisplayGroupParams, adapter.lastParameters);
  XCTAssertEqual((NSUInteger)1, [group.objects count]);
  XCTAssertEqualObjects(@"Peggy", group.objects[0][@"name"]);
}

- (void)testPageStatePersistsAcrossHelperInstances {
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET"
                                                      path:@"/"
                                               queryString:@""
                                                   headers:@{}
                                                      body:[NSData data]];
  ALNResponse *response = [[ALNResponse alloc] init];
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  ALNPerfTrace *trace = [[ALNPerfTrace alloc] initWithEnabled:NO];
  ALNContext *context = [[ALNContext alloc] initWithRequest:request
                                                   response:response
                                                     params:@{}
                                                     stash:[NSMutableDictionary dictionary]
                                                     logger:logger
                                                  perfTrace:trace
                                                  routeName:@""
                                             controllerName:@""
                                                 actionName:@""];
  context.stash[ALNContextPageStateEnabledStashKey] = @(YES);

  ALNPageState *editor = [context pageStateForKey:@"UserEditor"];
  [editor setValue:@"draft-123" forKey:@"draftID"];
  [editor setValue:@(3) forKey:@"step"];

  ALNPageState *editorAgain = [context pageStateForKey:@"UserEditor"];
  XCTAssertEqualObjects(@"draft-123", [editorAgain valueForKey:@"draftID"]);
  XCTAssertEqualObjects(@3, [editorAgain valueForKey:@"step"]);
  XCTAssertEqualObjects(@(YES), context.stash[ALNContextSessionDirtyStashKey]);

  [editorAgain clear];
  XCTAssertNil([[context pageStateForKey:@"UserEditor"] valueForKey:@"draftID"]);
}

- (void)testPageStateCompatibilityDisabledByDefaultUsesTransientStore {
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET"
                                                      path:@"/"
                                               queryString:@""
                                                   headers:@{}
                                                      body:[NSData data]];
  ALNResponse *response = [[ALNResponse alloc] init];
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  ALNPerfTrace *trace = [[ALNPerfTrace alloc] initWithEnabled:NO];
  ALNContext *context = [[ALNContext alloc] initWithRequest:request
                                                   response:response
                                                     params:@{}
                                                      stash:[NSMutableDictionary dictionary]
                                                     logger:logger
                                                  perfTrace:trace
                                                  routeName:@""
                                             controllerName:@""
                                                 actionName:@""];

  ALNPageState *state = [context pageStateForKey:@"Wizard"];
  [state setValue:@"temp" forKey:@"token"];

  XCTAssertEqualObjects(@"temp", [[context pageStateForKey:@"Wizard"] valueForKey:@"token"]);
  XCTAssertNil(context.stash[ALNContextSessionDirtyStashKey]);
}

- (void)testAdapterConformanceHarnessForPgAndGDL2CompatibilityAdapter {
  NSString *dsn = [self pgTestDSN];
  if ([dsn length] == 0) {
    return;
  }

  NSError *error = nil;
  ALNPg *pg = [[ALNPg alloc] initWithConnectionString:dsn
                                        maxConnections:2
                                                 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(pg);
  if (pg == nil) {
    return;
  }

  NSDictionary *pgReport = ALNAdapterConformanceReport(pg, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@(YES), pgReport[@"success"]);

  ALNGDL2Adapter *gdl2 = [[ALNGDL2Adapter alloc] initWithFallbackAdapter:pg];
  NSDictionary *gdl2Report = ALNAdapterConformanceReport(gdl2, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@(YES), gdl2Report[@"success"]);
  XCTAssertEqualObjects(@"gdl2", gdl2Report[@"adapter"]);
}

@end
