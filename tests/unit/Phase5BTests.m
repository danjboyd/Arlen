#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNDatabaseRouter.h"
#import "ALNPg.h"

@interface Phase5BFakeConnection : NSObject <ALNDatabaseConnection>

@property(nonatomic, assign) NSInteger commandCount;
@property(nonatomic, assign) NSInteger queryCount;

@end

@implementation Phase5BFakeConnection

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  (void)sql;
  (void)parameters;
  (void)error;
  self.queryCount += 1;
  return @[];
}

- (NSDictionary *)executeQueryOne:(NSString *)sql
                       parameters:(NSArray *)parameters
                            error:(NSError **)error {
  NSArray<NSDictionary *> *rows = [self executeQuery:sql parameters:parameters error:error];
  return [rows firstObject];
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  (void)sql;
  (void)parameters;
  (void)error;
  self.commandCount += 1;
  return 1;
}

@end

@interface Phase5BFakeAdapter : NSObject <ALNDatabaseAdapter>

@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *queryLog;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *commandLog;
@property(nonatomic, assign) BOOL failNextQuery;
@property(nonatomic, strong) NSError *nextQueryError;
@property(nonatomic, assign) NSInteger nextCommandResult;
@property(nonatomic, assign) BOOL transactionShouldSucceed;
@property(nonatomic, strong) NSError *transactionError;
@property(nonatomic, assign) NSInteger queryCount;
@property(nonatomic, assign) NSInteger commandCount;
@property(nonatomic, assign) NSInteger transactionCount;
@property(nonatomic, assign) NSInteger acquireCount;
@property(nonatomic, assign) NSInteger releaseCount;
@property(nonatomic, strong) NSArray<NSDictionary *> *rowsToReturn;

- (instancetype)initWithName:(NSString *)name;

@end

@implementation Phase5BFakeAdapter

- (instancetype)initWithName:(NSString *)name {
  self = [super init];
  if (self) {
    _name = [name copy] ?: @"";
    _queryLog = [NSMutableArray array];
    _commandLog = [NSMutableArray array];
    _failNextQuery = NO;
    _nextQueryError = nil;
    _nextCommandResult = 1;
    _transactionShouldSucceed = YES;
    _transactionError = nil;
    _queryCount = 0;
    _commandCount = 0;
    _transactionCount = 0;
    _acquireCount = 0;
    _releaseCount = 0;
    _rowsToReturn = @[ @{ @"ok" : @"1" } ];
  }
  return self;
}

- (NSString *)adapterName {
  return self.name;
}

- (id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError **)error {
  (void)error;
  self.acquireCount += 1;
  return [[Phase5BFakeConnection alloc] init];
}

- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection {
  (void)connection;
  self.releaseCount += 1;
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  self.queryCount += 1;
  [self.queryLog addObject:@{
    @"sql" : sql ?: @"",
    @"parameters" : parameters ?: @[],
  }];

  if (self.failNextQuery) {
    self.failNextQuery = NO;
    if (error != NULL) {
      *error = self.nextQueryError ?: [NSError errorWithDomain:@"Phase5BFakeAdapter"
                                                           code:101
                                                       userInfo:nil];
    }
    return nil;
  }
  return [NSArray arrayWithArray:self.rowsToReturn ?: @[]];
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  self.commandCount += 1;
  [self.commandLog addObject:@{
    @"sql" : sql ?: @"",
    @"parameters" : parameters ?: @[],
  }];
  if (self.nextCommandResult < 0 && error != NULL) {
    *error = [NSError errorWithDomain:@"Phase5BFakeAdapter" code:102 userInfo:nil];
  }
  return self.nextCommandResult;
}

- (BOOL)withTransactionUsingBlock:
            (BOOL (^)(id<ALNDatabaseConnection> connection,
                      NSError *_Nullable *_Nullable error))block
                            error:(NSError **)error {
  self.transactionCount += 1;
  if (block == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase5BFakeAdapter" code:103 userInfo:nil];
    }
    return NO;
  }

  Phase5BFakeConnection *connection = [[Phase5BFakeConnection alloc] init];
  NSError *blockError = nil;
  BOOL blockOK = block(connection, &blockError);
  if (!self.transactionShouldSucceed || !blockOK) {
    if (error != NULL) {
      *error = blockError ?: self.transactionError ?: [NSError errorWithDomain:@"Phase5BFakeAdapter"
                                                                           code:104
                                                                       userInfo:nil];
    }
    return NO;
  }
  return YES;
}

@end

@interface Phase5BTests : XCTestCase
@end

@implementation Phase5BTests

- (ALNDatabaseRouter *)routerWithRead:(id<ALNDatabaseAdapter>)readAdapter
                                write:(id<ALNDatabaseAdapter>)writeAdapter {
  NSError *error = nil;
  ALNDatabaseRouter *router = [[ALNDatabaseRouter alloc]
      initWithTargets:@{
        @"reader" : readAdapter,
        @"writer" : writeAdapter,
      }
      defaultReadTarget:@"reader"
      defaultWriteTarget:@"writer"
      error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(router);
  return router;
}

- (void)testRoutingSelectsReadAndWriteTargetsDeterministically {
  Phase5BFakeAdapter *reader = [[Phase5BFakeAdapter alloc] initWithName:@"reader"];
  Phase5BFakeAdapter *writer = [[Phase5BFakeAdapter alloc] initWithName:@"writer"];
  ALNDatabaseRouter *router = [self routerWithRead:reader write:writer];
  XCTAssertNotNil(router);
  if (router == nil) {
    return;
  }

  NSMutableArray<NSDictionary *> *events = [NSMutableArray array];
  router.routingDiagnosticsListener = ^(NSDictionary<NSString *,id> *event) {
    [events addObject:[NSDictionary dictionaryWithDictionary:event ?: @{}]];
  };

  NSDictionary *context = @{
    ALNDatabaseRoutingContextTenantKey : @"tenant-a",
    ALNDatabaseRoutingContextShardKey : @"s1",
  };

  NSError *error = nil;
  NSString *resolvedA = [router resolveTargetForOperationClass:ALNDatabaseRouteOperationClassRead
                                                 routingContext:context
                                                          error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"reader", resolvedA);

  NSString *resolvedB = [router resolveTargetForOperationClass:ALNDatabaseRouteOperationClassRead
                                                 routingContext:context
                                                          error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(resolvedA, resolvedB);

  NSArray<NSDictionary *> *rows = [router executeQuery:@"SELECT 1"
                                            parameters:@[]
                                        routingContext:context
                                                 error:&error];
  XCTAssertNotNil(rows);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)1, reader.queryCount);
  XCTAssertEqual((NSInteger)0, writer.queryCount);

  NSInteger affected = [router executeCommand:@"UPDATE widgets SET v = $1"
                                    parameters:@[ @"x" ]
                                routingContext:context
                                         error:&error];
  XCTAssertEqual((NSInteger)1, affected);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)1, writer.commandCount);
  XCTAssertEqual((NSInteger)0, reader.commandCount);

  XCTAssertEqual((NSUInteger)2, [events count]);
  NSDictionary *readEvent = events[0];
  NSDictionary *writeEvent = events[1];
  XCTAssertEqualObjects(@"route", readEvent[ALNDatabaseRouterEventStageKey]);
  XCTAssertEqualObjects(@"read", readEvent[ALNDatabaseRouterEventOperationClassKey]);
  XCTAssertEqualObjects(@"reader", readEvent[ALNDatabaseRouterEventSelectedTargetKey]);
  XCTAssertEqualObjects(@"tenant-a", readEvent[ALNDatabaseRouterEventTenantKey]);
  XCTAssertEqualObjects(@"s1", readEvent[ALNDatabaseRouterEventShardKey]);
  XCTAssertEqualObjects(@"write", writeEvent[ALNDatabaseRouterEventOperationClassKey]);
  XCTAssertEqualObjects(@"writer", writeEvent[ALNDatabaseRouterEventSelectedTargetKey]);
}

- (void)testReadAfterWriteStickinessRespectsBoundedScope {
  Phase5BFakeAdapter *reader = [[Phase5BFakeAdapter alloc] initWithName:@"reader"];
  Phase5BFakeAdapter *writer = [[Phase5BFakeAdapter alloc] initWithName:@"writer"];
  ALNDatabaseRouter *router = [self routerWithRead:reader write:writer];
  XCTAssertNotNil(router);
  if (router == nil) {
    return;
  }

  router.readAfterWriteStickinessSeconds = 60;
  NSError *error = nil;
  NSDictionary *scopeA = @{ ALNDatabaseRoutingContextStickinessScopeKey : @"tenant-a" };
  NSDictionary *scopeB = @{ ALNDatabaseRoutingContextStickinessScopeKey : @"tenant-b" };

  NSInteger affected = [router executeCommand:@"INSERT INTO widgets(v) VALUES ($1)"
                                    parameters:@[ @"a" ]
                                routingContext:scopeA
                                         error:&error];
  XCTAssertEqual((NSInteger)1, affected);
  XCTAssertNil(error);

  NSArray<NSDictionary *> *rowsA = [router executeQuery:@"SELECT * FROM widgets"
                                             parameters:@[]
                                         routingContext:scopeA
                                                  error:&error];
  XCTAssertNotNil(rowsA);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)1, writer.queryCount);
  XCTAssertEqual((NSInteger)0, reader.queryCount);

  NSArray<NSDictionary *> *rowsB = [router executeQuery:@"SELECT * FROM widgets"
                                             parameters:@[]
                                         routingContext:scopeB
                                                  error:&error];
  XCTAssertNotNil(rowsB);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)1, reader.queryCount);

  router.readAfterWriteStickinessSeconds = 0;
  NSArray<NSDictionary *> *rowsAAfterDisable = [router executeQuery:@"SELECT * FROM widgets"
                                                         parameters:@[]
                                                     routingContext:scopeA
                                                              error:&error];
  XCTAssertNotNil(rowsAAfterDisable);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)2, reader.queryCount);
}

- (void)testRouteTargetResolverSupportsTenantAndShardHints {
  Phase5BFakeAdapter *readEast = [[Phase5BFakeAdapter alloc] initWithName:@"read-east"];
  Phase5BFakeAdapter *readWest = [[Phase5BFakeAdapter alloc] initWithName:@"read-west"];
  Phase5BFakeAdapter *writer = [[Phase5BFakeAdapter alloc] initWithName:@"writer"];

  NSError *error = nil;
  ALNDatabaseRouter *router = [[ALNDatabaseRouter alloc]
      initWithTargets:@{
        @"read_east" : readEast,
        @"read_west" : readWest,
        @"writer" : writer,
      }
      defaultReadTarget:@"read_east"
      defaultWriteTarget:@"writer"
      error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(router);
  if (router == nil) {
    return;
  }

  router.routeTargetResolver = ^NSString *(ALNDatabaseRouteOperationClass operationClass,
                                           NSDictionary<NSString *,id> *routingContext,
                                           NSString *defaultTarget) {
    if (operationClass != ALNDatabaseRouteOperationClassRead) {
      return defaultTarget;
    }
    NSString *shard = [routingContext[ALNDatabaseRoutingContextShardKey] isKindOfClass:[NSString class]]
                          ? routingContext[ALNDatabaseRoutingContextShardKey]
                          : @"";
    if ([shard isEqualToString:@"west"]) {
      return @"read_west";
    }
    NSString *tenant = [routingContext[ALNDatabaseRoutingContextTenantKey] isKindOfClass:[NSString class]]
                           ? routingContext[ALNDatabaseRoutingContextTenantKey]
                           : @"";
    if ([tenant isEqualToString:@"primary-write"]) {
      return @"writer";
    }
    return defaultTarget;
  };

  NSDictionary *westContext = @{
    ALNDatabaseRoutingContextTenantKey : @"tenant-a",
    ALNDatabaseRoutingContextShardKey : @"west",
  };

  NSString *target1 = [router resolveTargetForOperationClass:ALNDatabaseRouteOperationClassRead
                                               routingContext:westContext
                                                        error:&error];
  NSString *target2 = [router resolveTargetForOperationClass:ALNDatabaseRouteOperationClassRead
                                               routingContext:westContext
                                                        error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"read_west", target1);
  XCTAssertEqualObjects(target1, target2);

  NSArray<NSDictionary *> *rows = [router executeQuery:@"SELECT * FROM widgets"
                                            parameters:@[]
                                        routingContext:westContext
                                                 error:&error];
  XCTAssertNotNil(rows);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)1, readWest.queryCount);
  XCTAssertEqual((NSInteger)0, readEast.queryCount);

  NSDictionary *writeHint = @{ ALNDatabaseRoutingContextTenantKey : @"primary-write" };
  rows = [router executeQuery:@"SELECT * FROM widgets"
                   parameters:@[]
               routingContext:writeHint
                        error:&error];
  XCTAssertNotNil(rows);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)1, writer.queryCount);
}

- (void)testReadFallbackToWriteTargetOnReadFailure {
  Phase5BFakeAdapter *reader = [[Phase5BFakeAdapter alloc] initWithName:@"reader"];
  Phase5BFakeAdapter *writer = [[Phase5BFakeAdapter alloc] initWithName:@"writer"];
  writer.rowsToReturn = @[ @{ @"value" : @"from-writer" } ];
  reader.failNextQuery = YES;
  reader.nextQueryError = [NSError errorWithDomain:ALNPgErrorDomain
                                               code:ALNPgErrorPoolExhausted
                                           userInfo:@{ NSLocalizedDescriptionKey : @"pool exhausted" }];

  ALNDatabaseRouter *router = [self routerWithRead:reader write:writer];
  XCTAssertNotNil(router);
  if (router == nil) {
    return;
  }

  NSMutableArray<NSDictionary *> *events = [NSMutableArray array];
  router.routingDiagnosticsListener = ^(NSDictionary<NSString *,id> *event) {
    [events addObject:[NSDictionary dictionaryWithDictionary:event ?: @{}]];
  };

  NSError *error = nil;
  NSArray<NSDictionary *> *rows = [router executeQuery:@"SELECT 1"
                                            parameters:@[]
                                        routingContext:nil
                                                 error:&error];
  XCTAssertNotNil(rows);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [rows count]);
  XCTAssertEqualObjects(@"from-writer", rows[0][@"value"]);
  XCTAssertEqual((NSInteger)1, reader.queryCount);
  XCTAssertEqual((NSInteger)1, writer.queryCount);

  XCTAssertEqual((NSUInteger)2, [events count]);
  NSDictionary *fallbackEvent = events[1];
  XCTAssertEqualObjects(@"fallback", fallbackEvent[ALNDatabaseRouterEventStageKey]);
  XCTAssertEqualObjects(@"reader", fallbackEvent[ALNDatabaseRouterEventSelectedTargetKey]);
  XCTAssertEqualObjects(@"writer", fallbackEvent[ALNDatabaseRouterEventFallbackTargetKey]);
  XCTAssertEqualObjects(ALNPgErrorDomain, fallbackEvent[ALNDatabaseRouterEventErrorDomainKey]);
  XCTAssertEqual(ALNPgErrorPoolExhausted,
                 [fallbackEvent[ALNDatabaseRouterEventErrorCodeKey] integerValue]);
}

- (void)testTransactionFailureDoesNotActivateStickinessButSuccessDoes {
  Phase5BFakeAdapter *reader = [[Phase5BFakeAdapter alloc] initWithName:@"reader"];
  Phase5BFakeAdapter *writer = [[Phase5BFakeAdapter alloc] initWithName:@"writer"];
  ALNDatabaseRouter *router = [self routerWithRead:reader write:writer];
  XCTAssertNotNil(router);
  if (router == nil) {
    return;
  }
  router.readAfterWriteStickinessSeconds = 30;

  NSDictionary *scopeA = @{ ALNDatabaseRoutingContextStickinessScopeKey : @"tenant-a" };
  NSError *error = nil;

  writer.transactionShouldSucceed = NO;
  writer.transactionError = [NSError errorWithDomain:@"Phase5BTests"
                                                code:9001
                                            userInfo:nil];
  BOOL failed = [router withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> connection,
                                                         NSError *__autoreleasing  _Nullable *blockError) {
    (void)connection;
    if (blockError != NULL) {
      *blockError = [NSError errorWithDomain:@"Phase5BTests"
                                        code:9002
                                    userInfo:nil];
    }
    return NO;
  }
                               routingContext:scopeA
                                        error:&error];
  XCTAssertFalse(failed);
  XCTAssertNotNil(error);

  error = nil;
  NSArray<NSDictionary *> *afterFailedTx =
      [router executeQuery:@"SELECT * FROM widgets"
                parameters:@[]
            routingContext:scopeA
                     error:&error];
  XCTAssertNotNil(afterFailedTx);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)1, reader.queryCount);
  XCTAssertEqual((NSInteger)0, writer.queryCount);

  writer.transactionShouldSucceed = YES;
  writer.transactionError = nil;
  error = nil;
  BOOL succeeded = [router withTransactionUsingBlock:^BOOL(id<ALNDatabaseConnection> connection,
                                                            NSError *__autoreleasing  _Nullable *blockError) {
    (void)connection;
    (void)blockError;
    return YES;
  }
                                  routingContext:scopeA
                                           error:&error];
  XCTAssertTrue(succeeded);
  XCTAssertNil(error);

  error = nil;
  NSArray<NSDictionary *> *afterSuccessfulTx =
      [router executeQuery:@"SELECT * FROM widgets"
                parameters:@[]
            routingContext:scopeA
                     error:&error];
  XCTAssertNotNil(afterSuccessfulTx);
  XCTAssertNil(error);
  XCTAssertEqual((NSInteger)1, writer.queryCount);
}

- (void)testUnknownResolverTargetFailsDeterministically {
  Phase5BFakeAdapter *reader = [[Phase5BFakeAdapter alloc] initWithName:@"reader"];
  Phase5BFakeAdapter *writer = [[Phase5BFakeAdapter alloc] initWithName:@"writer"];
  ALNDatabaseRouter *router = [self routerWithRead:reader write:writer];
  XCTAssertNotNil(router);
  if (router == nil) {
    return;
  }

  router.routeTargetResolver = ^NSString *(ALNDatabaseRouteOperationClass operationClass,
                                           NSDictionary<NSString *,id> *routingContext,
                                           NSString *defaultTarget) {
    (void)operationClass;
    (void)routingContext;
    (void)defaultTarget;
    return @"does_not_exist";
  };

  NSError *error = nil;
  NSArray<NSDictionary *> *rows = [router executeQuery:@"SELECT 1"
                                            parameters:@[]
                                        routingContext:nil
                                                 error:&error];
  XCTAssertNil(rows);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNDatabaseRouterErrorDomain, error.domain);
  XCTAssertEqual((NSInteger)ALNDatabaseRouterErrorUnknownTarget, error.code);
}

@end
