#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "ALNNotificationsCatalog.h"
#import "../shared/ALNTestSupport.h"
#import "../shared/ALNTestWait.h"

@interface NotificationsCatalogTests : XCTestCase
@end
@implementation NotificationsCatalogTests

- (NSDictionary *)stateWithEntries:(NSArray *)entries {
  return @{ @"version":@1, @"nextEntrySequence":@0, @"outboxEntries":@[],
            @"inboxByRecipient":@{@"alice":entries}, @"preferencesByRecipient":@{}, @"recentFanoutEvents":@[] };
}

- (NSString *)legacyPath {
  return [ALNTestTemporaryDirectory(@"notifications-catalog") stringByAppendingPathComponent:@"state.plist"];
}

- (ALNNotificationsCatalog *)catalogAt:(NSString *)legacy {
  NSError *error = nil;
  ALNNotificationsCatalog *catalog = [[ALNNotificationsCatalog alloc]
      initWithPath:[legacy stringByAppendingString:@".sqlite3"] legacyPath:legacy error:&error];
  XCTAssertNotNil(catalog, @"%@", error);
  return catalog;
}

- (void)testBinaryLegacyImportIsDurableAndHappensOnlyOnce {
  NSString *legacy = [self legacyPath];
  NSDictionary *original = [self stateWithEntries:@[@{@"entryID":@"original", @"read":@NO}]];
  NSData *binary = [NSPropertyListSerialization dataWithPropertyList:original format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
  XCTAssertTrue([binary writeToFile:legacy atomically:YES]);
  ALNNotificationsCatalog *catalog = [self catalogAt:legacy];
  XCTAssertEqualObjects(original, [catalog readStateWithError:NULL]);
  XCTAssertEqualObjects(binary, [NSData dataWithContentsOfFile:legacy]);
  XCTAssertTrue([@{} writeToFile:legacy atomically:YES]);
  catalog = nil;
  catalog = [self catalogAt:legacy];
  XCTAssertEqualObjects(original, [catalog readStateWithError:NULL]);
}

- (void)testFailedMigrationCanBeRetriedWithoutPartialImport {
  NSString *legacy = [self legacyPath];
  XCTAssertTrue([@"broken plist" writeToFile:legacy atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
  NSError *error = nil;
  XCTAssertNil([[ALNNotificationsCatalog alloc] initWithPath:[legacy stringByAppendingString:@".sqlite3"] legacyPath:legacy error:&error]);
  XCTAssertNotNil(error.localizedDescription);
  NSDictionary *original = [self stateWithEntries:@[@{@"entryID":@"retry"}]];
  XCTAssertTrue([original writeToFile:legacy atomically:YES]);
  XCTAssertEqualObjects(original, [[self catalogAt:legacy] readStateWithError:NULL]);
}

- (void)testSingleEntryUpdateWritesConstantBytesAsCatalogGrows {
  NSUInteger smallBytes = 0;
  for (NSNumber *count in @[@100, @5000]) {
    NSString *legacy = [self legacyPath];
    ALNNotificationsCatalog *catalog = [self catalogAt:legacy];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSUInteger i = 0; i < count.unsignedIntegerValue; i++) {
      [entries addObject:@{@"entryID":[NSString stringWithFormat:@"entry-%06lu", (unsigned long)i], @"read":@NO, @"body":@"notification payload"}];
    }
    XCTAssertTrue([catalog writeState:[self stateWithEntries:entries] error:NULL]);
    NSMutableDictionary *changed = [entries[50] mutableCopy];
    changed[@"read"] = @YES;
    entries[50] = changed;
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    XCTAssertTrue([catalog writeState:[self stateWithEntries:entries] error:NULL]);
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - start;
    XCTAssertEqual((NSUInteger)1, catalog.lastWrittenRowCount);
    NSUInteger bytes = catalog.lastWrittenByteCount;
    if (smallBytes == 0) smallBytes = bytes;
    XCTAssertEqual(smallBytes, bytes);
    XCTAssertEqualObjects([self stateWithEntries:entries], [catalog readStateWithError:NULL]);
    XCTAssertEqual((NSUInteger)0, catalog.lastReadRowCount);
    NSLog(@"notification_incremental entries=%@ changed_rows=%lu serialized_bytes=%lu update_seconds=%.6f unchanged_read_rows=%lu", count, (unsigned long)catalog.lastWrittenRowCount, (unsigned long)bytes, elapsed, (unsigned long)catalog.lastReadRowCount);
    NSTimeInterval baselineStart = [NSDate timeIntervalSinceReferenceDate];
    NSData *wholePlist = [NSPropertyListSerialization dataWithPropertyList:[self stateWithEntries:entries]
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    XCTAssertNotNil(wholePlist);
    XCTAssertTrue([wholePlist writeToFile:[legacy stringByAppendingString:@".baseline"] options:NSDataWritingAtomic error:NULL]);
    NSTimeInterval baselineElapsed = [NSDate timeIntervalSinceReferenceDate] - baselineStart;
    XCTAssertGreaterThan(wholePlist.length, bytes);
    NSLog(@"notification_whole_plist_baseline entries=%@ serialized_bytes=%lu serialize_and_write_seconds=%.6f", count, (unsigned long)wholePlist.length, baselineElapsed);
    // Trimming the oldest item must not renumber and rewrite retained rows.
    [entries removeObjectAtIndex:0];
    [entries addObject:@{@"entryID":@"new-tail", @"read":@NO}];
    XCTAssertTrue([catalog writeState:[self stateWithEntries:entries] error:NULL]);
    XCTAssertEqual((NSUInteger)2, catalog.lastWrittenRowCount);
    XCTAssertTrue([catalog writeState:[self stateWithEntries:entries] error:NULL]);
    XCTAssertEqual((NSUInteger)0, catalog.lastWrittenRowCount);
    catalog = nil;
    XCTAssertEqualObjects([self stateWithEntries:entries], [[self catalogAt:legacy] readStateWithError:NULL]);
  }
}

- (void)testPeerCommitInvalidatesReadCacheAndPreservesPreferenceRemoval {
  NSString *legacy = [self legacyPath];
  ALNNotificationsCatalog *first = [self catalogAt:legacy];
  ALNNotificationsCatalog *second = [self catalogAt:legacy];
  NSMutableDictionary *state = [[first readStateWithError:NULL] mutableCopy];
  state[@"preferencesByRecipient"] = @{@"alice":@{@"digest":@{@"email":@NO}}};
  XCTAssertTrue([first writeState:state error:NULL]);
  XCTAssertEqualObjects(state, [second readStateWithError:NULL]);
  XCTAssertGreaterThan(second.lastReadRowCount, (NSUInteger)0);
  [second readStateWithError:NULL];
  XCTAssertEqual((NSUInteger)0, second.lastReadRowCount);
  state[@"preferencesByRecipient"] = @{@"alice":@{}};
  XCTAssertTrue([second writeState:state error:NULL]);
  XCTAssertEqual((NSUInteger)1, second.lastWrittenRowCount);
  XCTAssertEqualObjects(state, [first readStateWithError:NULL]);
}

- (void)testInvalidWriteRollsBackAndMutableInputCannotAliasSnapshot {
  NSString *legacy = [self legacyPath];
  ALNNotificationsCatalog *catalog = [self catalogAt:legacy];
  NSMutableDictionary *metadata = [@{@"label":@"before"} mutableCopy];
  NSDictionary *state = [self stateWithEntries:@[@{@"entryID":@"one", @"metadata":metadata}]];
  XCTAssertTrue([catalog writeState:state error:NULL]);
  metadata[@"label"] = @"after";
  XCTAssertTrue([catalog writeState:state error:NULL]);
  XCTAssertEqual((NSUInteger)1, catalog.lastWrittenRowCount);
  NSError *error = nil;
  NSDictionary *invalid = [self stateWithEntries:@[@{@"entryID":@"one", @"bad":[[NSObject alloc] init]}]];
  XCTAssertFalse([catalog writeState:invalid error:&error]);
  XCTAssertNotNil(error.localizedDescription);
  XCTAssertEqualObjects(state, [catalog readStateWithError:NULL]);
  catalog = nil;
  XCTAssertEqualObjects(state, [[self catalogAt:legacy] readStateWithError:NULL]);
}

- (void)testDuplicateIdentifiersAndMalformedLegacyShapesFailClosed {
  for (NSDictionary *invalid in @[
      @{@"inboxByRecipient":@42},
      @{@"version":@2},
      @{@"outboxEntries":@[@{@"entryID":@"duplicate"}, @{@"entryID":@"duplicate"}]},
      @{@"outboxEntries":@[@{@"entryID":@""}]},
      @{@"preferencesByRecipient":@{@"alice":@[]}}]) {
    NSString *legacy = [self legacyPath];
    XCTAssertTrue([invalid writeToFile:legacy atomically:YES]);
    NSError *error = nil;
    XCTAssertNil([[ALNNotificationsCatalog alloc] initWithPath:[legacy stringByAppendingString:@".sqlite3"] legacyPath:legacy error:&error]);
    XCTAssertNotNil(error.localizedDescription);
  }
}

- (void)testInterruptedMigrationLeavesNoPartialCatalog {
  NSString *legacy = [self legacyPath];
  NSString *path = [legacy stringByAppendingString:@".sqlite3"];
  NSDictionary *original = [self stateWithEntries:@[@{@"entryID":@"recovered"}]];
  XCTAssertTrue([original writeToFile:legacy atomically:YES]);
  NSTask *child = [[NSTask alloc] init];
  child.launchPath = ALNTestToolPath(@"python3");
  child.arguments = @[@"-c", @"import sqlite3,sys,os; c=sqlite3.connect(sys.argv[1]); c.execute('BEGIN IMMEDIATE'); c.execute('CREATE TABLE catalog(kind TEXT NOT NULL,key TEXT NOT NULL,value BLOB NOT NULL,PRIMARY KEY(kind,key))'); c.execute(\"INSERT INTO catalog VALUES('meta','root',?)\",(b'partial',)); os._exit(7)", path];
  [child launch];
  BOOL exited = ALNTestWaitForTaskExit(child, 15.0);
  XCTAssertTrue(exited);
  if (!exited) [child terminate];
  else XCTAssertEqual(7, child.terminationStatus);
  XCTAssertEqualObjects(original, [[self catalogAt:legacy] readStateWithError:NULL]);
}

- (void)testCorruptPeerRecordFailsClosedWithoutStaleCacheOrLegacyReimport {
  NSString *legacy = [self legacyPath];
  NSDictionary *original = [self stateWithEntries:@[@{@"entryID":@"original"}]];
  XCTAssertTrue([original writeToFile:legacy atomically:YES]);
  ALNNotificationsCatalog *catalog = [self catalogAt:legacy];
  XCTAssertEqualObjects(original, [catalog readStateWithError:NULL]);
  NSTask *child = [[NSTask alloc] init];
  child.launchPath = ALNTestToolPath(@"python3");
  child.arguments = @[@"-c", @"import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute(\"UPDATE catalog SET value=? WHERE kind='meta'\",(b'corrupt',)); c.commit()", catalog.path];
  [child launch];
  BOOL exited = ALNTestWaitForTaskExit(child, 15.0);
  XCTAssertTrue(exited);
  if (!exited) [child terminate];
  else XCTAssertEqual(0, child.terminationStatus);
  NSError *error = nil;
  XCTAssertNil([catalog readStateWithError:&error]);
  XCTAssertNotNil(error.localizedDescription);
  catalog = nil;
  error = nil;
  XCTAssertNil([[ALNNotificationsCatalog alloc] initWithPath:[legacy stringByAppendingString:@".sqlite3"] legacyPath:legacy error:&error]);
  XCTAssertNotNil(error.localizedDescription);
}

- (void)testRetentionChurnReusesPagesAndKeepsOnlyRetainedRows {
  NSString *legacy = [self legacyPath];
  ALNNotificationsCatalog *catalog = [self catalogAt:legacy];
  NSMutableArray *entries = [NSMutableArray array];
  for (NSUInteger i = 0; i < 200; i++) {
    [entries addObject:@{@"entryID":[NSString stringWithFormat:@"entry-%06lu", (unsigned long)i], @"body":@"retained"}];
  }
  XCTAssertTrue([catalog writeState:[self stateWithEntries:entries] error:NULL]);
  unsigned long long initialBytes = [[[NSFileManager defaultManager] attributesOfItemAtPath:catalog.path error:NULL][NSFileSize] unsignedLongLongValue];
  for (NSUInteger i = 200; i < 700; i++) {
    [entries removeObjectAtIndex:0];
    [entries addObject:@{@"entryID":[NSString stringWithFormat:@"entry-%06lu", (unsigned long)i], @"body":@"retained"}];
    XCTAssertTrue([catalog writeState:[self stateWithEntries:entries] error:NULL]);
    XCTAssertEqual((NSUInteger)2, catalog.lastWrittenRowCount);
  }
  unsigned long long finalBytes = [[[NSFileManager defaultManager] attributesOfItemAtPath:catalog.path error:NULL][NSFileSize] unsignedLongLongValue];
  // B-tree splits can reserve extra pages, but history must not accumulate.
  XCTAssertLessThanOrEqual(finalBytes, initialBytes * 2 + 65536);
  catalog = nil;
  catalog = [self catalogAt:legacy];
  XCTAssertEqual((NSUInteger)201, catalog.lastReadRowCount);
  XCTAssertEqualObjects([self stateWithEntries:entries], [catalog readStateWithError:NULL]);
  NSLog(@"notification_retention retained=200 rotations=500 initial_bytes=%llu final_bytes=%llu rows=201", initialBytes, finalBytes);
}

- (void)testConcurrentFirstStartImportsOneCatalog {
  NSString *legacy = [self legacyPath];
  NSDictionary *original = [self stateWithEntries:@[@{@"entryID":@"original"}]];
  XCTAssertTrue([original writeToFile:legacy atomically:YES]);
  NSLock *lock = [[NSLock alloc] init];
  NSMutableArray *failures = [NSMutableArray array];
  dispatch_apply(8, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t index) {
    (void)index;
    @autoreleasepool {
      NSError *error = nil;
      ALNNotificationsCatalog *catalog = [[ALNNotificationsCatalog alloc]
          initWithPath:[legacy stringByAppendingString:@".sqlite3"] legacyPath:legacy error:&error];
      NSDictionary *actual = [catalog readStateWithError:&error];
      if (![actual isEqual:original]) {
        [lock lock]; [failures addObject:error ?: @"state mismatch"]; [lock unlock];
      }
    }
  });
  XCTAssertEqual((NSUInteger)0, failures.count, @"%@", failures);
}

@end
