#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <stdint.h>
#import <string.h>

#import "ALNAuthModule.h"
#import "ALNPg.h"

@interface ALNAuthModuleRuntime (AuthSchemaCacheTesting)
- (id)authSchemaFeaturesWithLogger:(id)logger error:(NSError **)error;
@end

// Script only the schema query. No server is needed for cache lifetime and
// retry controls; the original password-reset test covers the real Pg path.
@interface AuthSchemaProbeDatabase : ALNPg
@property(nonatomic, copy) NSDictionary *schemaRow;
@property(nonatomic, strong) NSError *probeError;
@property(nonatomic, assign) NSUInteger probeCount;
@end

@implementation AuthSchemaProbeDatabase
- (instancetype)init {
  self = [super init];
  if (self != nil) _schemaRow = @{ @"users" : @"t", @"stamp" : @"t", @"revoked" : @"t" };
  return self;
}
- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  (void)parameters;
  NSAssert([sql containsString:@"to_regclass('auth_users')"], @"unexpected query: %@", sql);
  self.probeCount += 1;
  if (self.probeError != nil) {
    if (error != NULL) *error = self.probeError;
    return nil;
  }
  return @[ self.schemaRow ];
}
@end

static uintptr_t AuthSchemaClassIdentity(id object) {
#if defined(GNUSTEP)
  // libobjc2's object_getClass deliberately skips hidden associated-object
  // classes. Its actual isa pointer must remain unchanged after publication.
  // Read sequentially: this assertion itself introduces no concurrent access.
  uintptr_t identity = 0;
  memcpy(&identity, (__bridge const void *)object, sizeof(identity));
  return identity;
#else
  // Apple may pack reference-count bits in isa; use its runtime class API.
  return (uintptr_t)(__bridge void *)object_getClass(object);
#endif
}

@interface AuthSchemaCacheTests : XCTestCase
@end

@implementation AuthSchemaCacheTests
- (ALNAuthModuleRuntime *)runtimeWithDatabase:(ALNPg *)database {
  ALNAuthModuleRuntime *runtime = [[ALNAuthModuleRuntime alloc] init];
  [runtime setValue:database forKey:@"database"];
  [runtime setValue:[[NSUUID UUID] UUIDString] forKey:@"environmentName"];
  return runtime;
}

- (void)testSchemaProbeDoesNotChangeSharedObjectClass {
  AuthSchemaProbeDatabase *database = [[AuthSchemaProbeDatabase alloc] init];
  ALNAuthModuleRuntime *runtime = [self runtimeWithDatabase:database];
  uintptr_t databaseClass = AuthSchemaClassIdentity(database);
  uintptr_t runtimeClass = AuthSchemaClassIdentity(runtime);
  id features = [runtime authSchemaFeaturesWithLogger:nil error:NULL];
  XCTAssertNotNil(features);
  XCTAssertEqual(databaseClass, AuthSchemaClassIdentity(database));
  XCTAssertEqual(runtimeClass, AuthSchemaClassIdentity(runtime));
  XCTAssertTrue(features == [runtime authSchemaFeaturesWithLogger:nil error:NULL]);
  XCTAssertEqual((NSUInteger)1, database.probeCount);
}

- (void)testConcurrentSchemaProbesReuseOneResult {
  AuthSchemaProbeDatabase *database = [[AuthSchemaProbeDatabase alloc] init];
  ALNAuthModuleRuntime *runtime = [self runtimeWithDatabase:database];
  NSMutableArray *results = [NSMutableArray array];
  NSLock *resultsLock = [[NSLock alloc] init];
  dispatch_apply(64, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
    (void)index;
    id features = [runtime authSchemaFeaturesWithLogger:nil error:NULL];
    [resultsLock lock];
    [results addObject:features ?: [NSNull null]];
    [resultsLock unlock];
  });
  XCTAssertEqual((NSUInteger)1, database.probeCount);
  XCTAssertEqual((NSUInteger)64, results.count);
  id first = results.firstObject;
  XCTAssertFalse(first == [NSNull null]);
  for (id features in results) XCTAssertTrue(first == features);
}

- (void)testMissingUsersTableRetriesUntilSchemaExists {
  AuthSchemaProbeDatabase *database = [[AuthSchemaProbeDatabase alloc] init];
  database.schemaRow = @{ @"users" : @"f", @"stamp" : @"f", @"revoked" : @"f" };
  ALNAuthModuleRuntime *runtime = [self runtimeWithDatabase:database];
  id first = [runtime authSchemaFeaturesWithLogger:nil error:NULL];
  id second = [runtime authSchemaFeaturesWithLogger:nil error:NULL];
  XCTAssertNotNil(first);
  XCTAssertFalse(first == second);
  XCTAssertEqualObjects(@NO, [first valueForKey:@"sessionStamp"]);
  XCTAssertEqualObjects(@NO, [first valueForKey:@"revokedSessions"]);
  XCTAssertEqual((NSUInteger)2, database.probeCount);
  database.schemaRow = @{ @"users" : @"t", @"stamp" : @"t", @"revoked" : @"t" };
  id ready = [runtime authSchemaFeaturesWithLogger:nil error:NULL];
  XCTAssertEqualObjects(@YES, [ready valueForKey:@"sessionStamp"]);
  XCTAssertEqualObjects(@YES, [ready valueForKey:@"revokedSessions"]);
  XCTAssertTrue(ready == [runtime authSchemaFeaturesWithLogger:nil error:NULL]);
  XCTAssertEqual((NSUInteger)3, database.probeCount);
}

- (void)testProbeErrorsRemainUncachedAndKeepDatabaseFailure {
  AuthSchemaProbeDatabase *database = [[AuthSchemaProbeDatabase alloc] init];
  database.probeError = [NSError errorWithDomain:ALNPgErrorDomain code:1
                                       userInfo:@{ NSLocalizedDescriptionKey : @"connection unavailable" }];
  ALNAuthModuleRuntime *runtime = [self runtimeWithDatabase:database];
  for (NSUInteger i = 0; i < 2; i++) {
    NSError *error = nil;
    XCTAssertNil([runtime authSchemaFeaturesWithLogger:nil error:&error]);
    XCTAssertEqualObjects(database.probeError, error);
  }
  XCTAssertEqual((NSUInteger)2, database.probeCount);
  database.probeError = [NSError errorWithDomain:ALNPgErrorDomain code:2
                                       userInfo:@{ ALNPgErrorSQLStateKey : @"42P01",
                                                   NSLocalizedDescriptionKey : @"auth_users missing" }];
  NSError *schemaError = nil;
  XCTAssertNil([runtime authSchemaFeaturesWithLogger:nil error:&schemaError]);
  XCTAssertEqualObjects(ALNAuthModuleErrorDomain, schemaError.domain);
  XCTAssertEqual((NSInteger)ALNAuthModuleErrorInvalidConfiguration, schemaError.code);
  XCTAssertEqualObjects(database.probeError, schemaError.userInfo[NSUnderlyingErrorKey]);
  database.probeError = nil;
  id features = [runtime authSchemaFeaturesWithLogger:nil error:NULL];
  XCTAssertNotNil(features);
  XCTAssertTrue(features == [runtime authSchemaFeaturesWithLogger:nil error:NULL]);
  XCTAssertEqual((NSUInteger)4, database.probeCount);
}

- (void)testDatabaseReplacementAndRemovalInvalidateCachedFeatures {
  AuthSchemaProbeDatabase *first = [[AuthSchemaProbeDatabase alloc] init];
  AuthSchemaProbeDatabase *second = [[AuthSchemaProbeDatabase alloc] init];
  second.schemaRow = @{ @"users" : @"t", @"stamp" : @"f", @"revoked" : @"f" };
  ALNAuthModuleRuntime *runtime = [self runtimeWithDatabase:first];
  id oldFeatures = [runtime authSchemaFeaturesWithLogger:nil error:NULL];
  [runtime setValue:second forKey:@"database"];
  id newFeatures = [runtime authSchemaFeaturesWithLogger:nil error:NULL];
  XCTAssertFalse(oldFeatures == newFeatures);
  XCTAssertEqualObjects(@NO, [newFeatures valueForKey:@"sessionStamp"]);
  XCTAssertEqualObjects(@NO, [newFeatures valueForKey:@"revokedSessions"]);
  XCTAssertEqual((NSUInteger)1, second.probeCount);
  [runtime setValue:nil forKey:@"database"];
  XCTAssertNil([runtime authSchemaFeaturesWithLogger:nil error:NULL]);
  [runtime setValue:second forKey:@"database"];
  XCTAssertFalse(newFeatures == [runtime authSchemaFeaturesWithLogger:nil error:NULL]);
  XCTAssertEqual((NSUInteger)2, second.probeCount);
}

- (void)testRuntimeCachesAreIndependentAndReleaseReplacedDatabase {
  ALNAuthModuleRuntime *runtime = [[ALNAuthModuleRuntime alloc] init];
  __weak ALNPg *oldDatabase = nil;
  @autoreleasepool {
    AuthSchemaProbeDatabase *database = [[AuthSchemaProbeDatabase alloc] init];
    oldDatabase = database;
    [runtime setValue:database forKey:@"database"];
    id first = [runtime authSchemaFeaturesWithLogger:nil error:NULL];
    ALNAuthModuleRuntime *other = [self runtimeWithDatabase:database];
    XCTAssertFalse(first == [other authSchemaFeaturesWithLogger:nil error:NULL]);
    XCTAssertEqual((NSUInteger)2, database.probeCount);
    [runtime setValue:[[AuthSchemaProbeDatabase alloc] init] forKey:@"database"];
    XCTAssertNotNil([runtime authSchemaFeaturesWithLogger:nil error:NULL]);
  }
  XCTAssertNil(oldDatabase);
}
@end
