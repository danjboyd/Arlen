#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNStorageCatalog.h"
#import "../shared/ALNTestSupport.h"

@interface StorageCatalogTests : XCTestCase
@end
@implementation StorageCatalogTests

- (NSDictionary *)stateWithObjects:(NSDictionary *)objects {
  return @{ @"version":@1, @"objectsByIdentifier":objects,
            @"objectIDsByCollection":@{@"files":[[objects allKeys] sortedArrayUsingSelector:@selector(compare:)]},
            @"uploadSessionsByIdentifier":@{}, @"nextSequence":@0, @"activityLog":@[] };
}

- (void)testLegacyImportIsDurableAndHappensOnlyOnce {
  NSString *directory = ALNTestTemporaryDirectory(@"storage-catalog");
  NSString *legacy = [directory stringByAppendingPathComponent:@"state.plist"];
  NSString *path = [legacy stringByAppendingString:@".sqlite3"];
  NSDictionary *original = [self stateWithObjects:@{ @"alice":@{ @"tokenNonce":@"alice-only", @"sizeBytes":@10 } }];
  XCTAssertTrue([original writeToFile:legacy atomically:YES]);
  NSError *error = nil;
  ALNStorageCatalog *catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:&error];
  XCTAssertNotNil(catalog, @"%@", error);
  XCTAssertEqualObjects(original, [catalog readStateWithError:&error]);
  XCTAssertTrue([@{} writeToFile:legacy atomically:YES]);
  catalog = nil;
  catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:&error];
  XCTAssertEqualObjects(original, [catalog readStateWithError:&error]);
}

- (void)testFailedMigrationCanBeRetriedWithoutPartialImport {
  NSString *directory = ALNTestTemporaryDirectory(@"storage-catalog");
  NSString *legacy = [directory stringByAppendingPathComponent:@"state.plist"];
  NSString *path = [legacy stringByAppendingString:@".sqlite3"];
  XCTAssertTrue([@"broken plist" writeToFile:legacy atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  NSError *error = nil;
  XCTAssertNil([[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:&error]);
  XCTAssertNotNil(error);
  NSDictionary *original = [self stateWithObjects:@{ @"bob":@{ @"tokenNonce":@"bob-only" } }];
  XCTAssertTrue([original writeToFile:legacy atomically:YES]);
  error = nil;
  ALNStorageCatalog *catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:&error];
  XCTAssertNotNil(catalog, @"%@", error);
  XCTAssertEqualObjects(original, [catalog readStateWithError:&error]);
}

- (void)testLargeCatalogMutationsWriteOnlyChangedRowsAndSurviveReopen {
  NSString *directory = ALNTestTemporaryDirectory(@"storage-catalog");
  NSString *legacy = [directory stringByAppendingPathComponent:@"state.plist"];
  NSString *path = [legacy stringByAppendingString:@".sqlite3"];
  NSError *error = nil;
  ALNStorageCatalog *catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:&error];
  NSMutableDictionary *objects = [NSMutableDictionary dictionary];
  for (NSUInteger i = 0; i < 5000; i++) objects[[NSString stringWithFormat:@"object-%06lu", (unsigned long)i]] = @{ @"owner":@"alice", @"sizeBytes":@12 };
  XCTAssertTrue([catalog writeState:[self stateWithObjects:objects] error:&error], @"%@", error);
  objects[@"object-002500"] = @{ @"owner":@"alice", @"sizeBytes":@13 };
  XCTAssertTrue([catalog writeState:[self stateWithObjects:objects] error:&error], @"%@", error);
  XCTAssertEqual((NSUInteger)1, catalog.lastWrittenRowCount);
  [objects removeObjectForKey:@"object-000000"];
  XCTAssertTrue([catalog writeState:[self stateWithObjects:objects] error:&error]);
  XCTAssertEqual((NSUInteger)2, catalog.lastWrittenRowCount);
  catalog = nil;
  catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:&error];
  XCTAssertEqualObjects([self stateWithObjects:objects], [catalog readStateWithError:&error]);
}

- (void)testConcurrentFirstStartImportsOneCatalog {
  NSString *directory = ALNTestTemporaryDirectory(@"storage-catalog");
  NSString *legacy = [directory stringByAppendingPathComponent:@"state.plist"];
  NSString *path = [legacy stringByAppendingString:@".sqlite3"];
  NSDictionary *original = [self stateWithObjects:@{ @"alice":@{ @"tokenNonce":@"alice-only" } }];
  XCTAssertTrue([original writeToFile:legacy atomically:YES]);
  NSLock *lock = [[NSLock alloc] init];
  NSMutableArray *failures = [NSMutableArray array];
  dispatch_apply(8, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
    (void)index;
    @autoreleasepool {
      NSError *error = nil;
      ALNStorageCatalog *catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:&error];
      NSDictionary *actual = [catalog readStateWithError:&error];
      if (![actual isEqual:original]) { [lock lock]; [failures addObject:error ?: @"state mismatch"]; [lock unlock]; }
    }
  });
  XCTAssertEqual((NSUInteger)0, failures.count, @"%@", failures);
}
- (void)testFailedWriteRollsBackAndKeepsErrorAlive {
  NSString *directory = ALNTestTemporaryDirectory(@"storage-catalog");
  NSString *legacy = [directory stringByAppendingPathComponent:@"state.plist"];
  NSString *path = [legacy stringByAppendingString:@".sqlite3"];
  NSError *error = nil;
  ALNStorageCatalog *catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:&error];
  NSDictionary *original = [self stateWithObjects:@{ @"alice":@{ @"tokenNonce":@"alice-only" } }];
  XCTAssertTrue([catalog writeState:original error:&error]);
  NSDictionary *invalid = [self stateWithObjects:@{ @"alice":@{ @"tokenNonce":@"changed" }, @"bad":@{ @"value":[[NSObject alloc] init] } }];
  XCTAssertFalse([catalog writeState:invalid error:&error]);
  XCTAssertNotNil(error.localizedDescription);
  XCTAssertEqualObjects(original, [catalog readStateWithError:NULL]);
  catalog = nil;
  catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:NULL];
  XCTAssertEqualObjects(original, [catalog readStateWithError:NULL]);
}

- (void)testInterruptedMigrationLeavesNoPartialCatalog {
#if defined(__linux__)
  NSString *directory = ALNTestTemporaryDirectory(@"storage-catalog");
  NSString *legacy = [directory stringByAppendingPathComponent:@"state.plist"];
  NSString *path = [legacy stringByAppendingString:@".sqlite3"];
  NSDictionary *original = [self stateWithObjects:@{ @"alice":@{ @"tokenNonce":@"alice-only" } }];
  XCTAssertTrue([original writeToFile:legacy atomically:YES]);
  NSTask *child = [[NSTask alloc] init];
  child.launchPath = @"/usr/bin/python3";
  child.arguments = @[ @"-c", @"import sqlite3,sys,os; c=sqlite3.connect(sys.argv[1]); c.execute('BEGIN IMMEDIATE'); c.execute('CREATE TABLE catalog(kind TEXT NOT NULL,key TEXT NOT NULL,value BLOB NOT NULL,PRIMARY KEY(kind,key))'); c.execute(\"INSERT INTO catalog VALUES('meta','root',?)\",(b'partial',)); os._exit(7)", path ];
  [child launch]; [child waitUntilExit];
  XCTAssertEqual(7, child.terminationStatus);
  NSError *error = nil;
  ALNStorageCatalog *catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:&error];
  XCTAssertNotNil(catalog, @"%@", error);
  XCTAssertEqualObjects(original, [catalog readStateWithError:&error]);
#else
  XCTSkip(@"process-interruption fixture uses Linux system Python sqlite3");
#endif
}

- (void)testMalformedLegacyCatalogFailsWithoutImporting {
  NSString *directory = ALNTestTemporaryDirectory(@"storage-catalog");
  NSString *legacy = [directory stringByAppendingPathComponent:@"state.plist"];
  NSDictionary *malformed = @{ @"objectsByIdentifier":@42 };
  XCTAssertTrue([malformed writeToFile:legacy atomically:YES]);
  NSError *error = nil;
  XCTAssertNil([[ALNStorageCatalog alloc] initWithPath:[legacy stringByAppendingString:@".sqlite3"] legacyPath:legacy error:&error]);
  XCTAssertNotNil(error.localizedDescription);
}

- (void)testMutableNestedInputDoesNotAliasCommittedSnapshot {
  NSString *directory = ALNTestTemporaryDirectory(@"storage-catalog");
  NSString *legacy = [directory stringByAppendingPathComponent:@"state.plist"];
  NSString *path = [legacy stringByAppendingString:@".sqlite3"];
  ALNStorageCatalog *catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:NULL];
  NSMutableDictionary *metadata = [@{ @"label":@"before" } mutableCopy];
  NSDictionary *state = [self stateWithObjects:@{ @"alice":@{ @"metadata":metadata } }];
  XCTAssertTrue([catalog writeState:state error:NULL]);
  metadata[@"label"] = @"after";
  XCTAssertTrue([catalog writeState:state error:NULL]);
  XCTAssertEqual((NSUInteger)1, catalog.lastWrittenRowCount);
  catalog = nil;
  catalog = [[ALNStorageCatalog alloc] initWithPath:path legacyPath:legacy error:NULL];
  XCTAssertEqualObjects(state, [catalog readStateWithError:NULL]);
}

@end
