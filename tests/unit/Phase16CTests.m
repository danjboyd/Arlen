#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <sys/stat.h>
#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNPlatform.h"
#import "ALNServices.h"
#import "ALNStorageModule.h"
#import "../shared/ALNTestSupport.h"

static NSInteger gPhase16CRemainingVariantFailures = 0;

@interface Phase16CGalleryCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation Phase16CGalleryCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"gallery";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Gallery",
    @"acceptedContentTypes" : @[ @"image/png" ],
    @"maxBytes" : @64,
    @"visibility" : @"private",
    @"retentionDays" : @1,
    @"variants" : @[
      @{ @"identifier" : @"thumb", @"contentType" : @"image/png", @"strategy" : @"transform" },
    ],
  };
}

- (NSDictionary *)storageModuleVariantRepresentationForObject:(NSDictionary *)objectRecord
                                            variantDefinition:(NSDictionary *)variantDefinition
                                                 originalData:(NSData *)originalData
                                             originalMetadata:(NSDictionary *)originalMetadata
                                                      runtime:(ALNStorageModuleRuntime *)runtime
                                                        error:(NSError **)error {
  (void)objectRecord;
  (void)variantDefinition;
  (void)originalMetadata;
  (void)runtime;
  if ([objectRecord[@"metadata"][@"failVariant"] respondsToSelector:@selector(boolValue)] &&
      [objectRecord[@"metadata"][@"failVariant"] boolValue] &&
      gPhase16CRemainingVariantFailures > 0) {
    gPhase16CRemainingVariantFailures -= 1;
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase16C"
                                   code:11
                               userInfo:@{ NSLocalizedDescriptionKey : @"expected transform failure" }];
    }
    return nil;
  }
  NSString *source = [[NSString alloc] initWithData:originalData encoding:NSUTF8StringEncoding] ?: @"";
  NSData *variantData = [[NSString stringWithFormat:@"THUMB:%@", [source uppercaseString]]
      dataUsingEncoding:NSUTF8StringEncoding];
  return @{
    @"data" : variantData ?: [NSData data],
    @"contentType" : @"image/png",
    @"metadata" : @{ @"generatedBy" : @"Phase16CGalleryCollection" },
  };
}

@end

@interface Phase16CCollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation Phase16CCollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16CGalleryCollection alloc] init] ];
}

@end

@interface Phase16CPlainCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation Phase16CPlainCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"plain";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{ @"title" : @"Plain", @"maxBytes" : @4096, @"visibility" : @"private" };
}

@end

@interface Phase16CPlainCollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation Phase16CPlainCollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16CGalleryCollection alloc] init], [[Phase16CPlainCollection alloc] init] ];
}

@end

@interface Phase16CTests : XCTestCase
@end

@implementation Phase16CTests

- (NSString *)temporaryDirectory {
  NSString *directory = ALNTestTemporaryDirectory(@"arlen-phase16c");
  XCTAssertNotNil(directory);
  return directory;
}

- (ALNApplication *)applicationWithStatePath:(NSString *)statePath
                               attachmentRoot:(NSString *)attachmentRoot {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[] },
      @"worker" : @{ @"retryDelaySeconds" : @0 },
    },
    @"storageModule" : @{
      @"collections" : @{ @"classes" : @[ @"Phase16CCollectionProvider" ] },
      @"persistence" : @{
        @"enabled" : @YES,
        @"path" : statePath ?: @"",
        @"backend" : @"plist",
      },
      @"uploadSessionTTLSeconds" : @1,
    },
  }];
  NSError *adapterError = nil;
  ALNFileSystemAttachmentAdapter *attachmentAdapter =
      [[ALNFileSystemAttachmentAdapter alloc] initWithRootDirectory:attachmentRoot
                                                        adapterName:@"phase16c_fs"
                                                              error:&adapterError];
  XCTAssertNotNil(attachmentAdapter);
  XCTAssertNil(adapterError);
  [app setAttachmentAdapter:attachmentAdapter];
  return app;
}

- (void)registerModulesForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNStorageModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (void)testObjectCatalogAndUploadSessionsPersistAcrossReconfigure {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];

  ALNApplication *app = [self applicationWithStatePath:statePath attachmentRoot:attachmentRoot];
  [self registerModulesForApplication:app];

  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *session = [runtime createUploadSessionForCollection:@"gallery"
                                                               name:@"avatar.png"
                                                        contentType:@"image/png"
                                                          sizeBytes:4
                                                           metadata:@{ @"width" : @8, @"height" : @6 }
                                                          expiresIn:60
                                                              error:&error];
  XCTAssertNotNil(session);
  XCTAssertNil(error);

  NSDictionary *stored = [runtime storeUploadData:[@"png!" dataUsingEncoding:NSUTF8StringEncoding]
                               forUploadSessionID:session[@"sessionID"]
                                            token:session[@"token"]
                                            error:&error];
  XCTAssertNotNil(stored);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@YES, stored[@"analysis"][@"previewable"]);
  XCTAssertEqualObjects(@8, stored[@"analysis"][@"dimensions"][@"width"]);
  XCTAssertEqual((NSUInteger)64, [stored[@"analysis"][@"checksumSHA256"] length]);

  ALNApplication *restarted = [self applicationWithStatePath:statePath attachmentRoot:attachmentRoot];
  [self registerModulesForApplication:restarted];

  runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSDictionary *restored = [runtime objectRecordForIdentifier:stored[@"objectID"] error:&error];
  XCTAssertNotNil(restored);
  XCTAssertNil(error);
  XCTAssertEqualObjects(stored[@"objectID"], restored[@"objectID"]);
  XCTAssertEqualObjects(@8, restored[@"analysis"][@"dimensions"][@"width"]);
  XCTAssertEqualObjects(@1, [runtime resolvedConfigSummary][@"uploadSessionCount"]);

  NSString *token = [runtime issueDownloadTokenForObjectID:stored[@"objectID"] expiresIn:60 error:&error];
  XCTAssertNotNil(token);
  NSDictionary *metadata = nil;
  NSData *downloaded = [runtime downloadDataForToken:token metadata:&metadata error:&error];
  XCTAssertEqualObjects(@"png!", [[NSString alloc] initWithData:downloaded encoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(stored[@"objectID"], metadata[@"object"][@"objectID"]);
}

- (void)testVariantGenerationUsesTransformHookAndPersistsActivity {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];

  ALNApplication *app = [self applicationWithStatePath:statePath attachmentRoot:attachmentRoot];
  [self registerModulesForApplication:app];

  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *stored = [runtime storeObjectInCollection:@"gallery"
                                                     name:@"photo.png"
                                              contentType:@"image/png"
                                                     data:[@"png!" dataUsingEncoding:NSUTF8StringEncoding]
                                                 metadata:@{}
                                                    error:&error];
  XCTAssertNotNil(stored);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"pending", stored[@"variantState"]);

  NSDictionary *workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);

  NSDictionary *record = [runtime objectRecordForIdentifier:stored[@"objectID"] error:&error];
  XCTAssertNotNil(record);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"ready", record[@"variantState"]);
  NSDictionary *variant = [record[@"variants"] firstObject];
  XCTAssertEqualObjects(@"ready", variant[@"status"]);
  XCTAssertTrue([variant[@"attachmentID"] isKindOfClass:[NSString class]]);

  NSDictionary *variantMetadata = nil;
  NSData *variantData =
      [app.attachmentAdapter attachmentDataForID:variant[@"attachmentID"] metadata:&variantMetadata error:&error];
  XCTAssertNotNil(variantData);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"THUMB:PNG!", [[NSString alloc] initWithData:variantData encoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(@"Phase16CGalleryCollection", variantMetadata[@"metadata"][@"generatedBy"]);

  ALNApplication *restarted = [self applicationWithStatePath:statePath attachmentRoot:attachmentRoot];
  [self registerModulesForApplication:restarted];
  runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSDictionary *summary = [runtime dashboardSummary];
  NSArray *recentActivity = [summary[@"recentActivity"] isKindOfClass:[NSArray class]] ? summary[@"recentActivity"] : @[];
  NSPredicate *predicate = [NSPredicate predicateWithFormat:@"event == %@", @"variant_ready"];
  XCTAssertEqual((NSUInteger)1, [[recentActivity filteredArrayUsingPredicate:predicate] count]);
}

- (void)testFailedVariantRecoveryAndCleanupScheduleSurface {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];

  gPhase16CRemainingVariantFailures = 3;
  ALNApplication *app = [self applicationWithStatePath:statePath attachmentRoot:attachmentRoot];
  [self registerModulesForApplication:app];

  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *stored = [runtime storeObjectInCollection:@"gallery"
                                                     name:@"broken.png"
                                              contentType:@"image/png"
                                                     data:[@"png!" dataUsingEncoding:NSUTF8StringEncoding]
                                                 metadata:@{ @"failVariant" : @YES }
                                                    error:&error];
  XCTAssertNotNil(stored);
  XCTAssertNil(error);

  NSDictionary *workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);

  NSDictionary *failed = [runtime objectRecordForIdentifier:stored[@"objectID"] error:&error];
  XCTAssertNotNil(failed);
  XCTAssertEqualObjects(@"failed", failed[@"variantState"]);
  XCTAssertEqualObjects(@"failed", [failed[@"variants"] firstObject][@"status"]);

  gPhase16CRemainingVariantFailures = 0;
  NSDictionary *requeueSummary = [runtime queueVariantGenerationForObjectID:stored[@"objectID"] error:&error];
  XCTAssertNotNil(requeueSummary);
  XCTAssertNil(error);

  workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);

  NSDictionary *recovered = [runtime objectRecordForIdentifier:stored[@"objectID"] error:&error];
  XCTAssertNotNil(recovered);
  XCTAssertEqualObjects(@"ready", recovered[@"variantState"]);

  NSArray *schedules = [[ALNJobsModuleRuntime sharedRuntime] registeredSchedules];
  NSPredicate *schedulePredicate = [NSPredicate predicateWithFormat:@"identifier == %@", @"storage.cleanup.default"];
  XCTAssertEqual((NSUInteger)1, [[schedules filteredArrayUsingPredicate:schedulePredicate] count]);

  NSDate *future = [NSDate dateWithTimeIntervalSinceNow:(2 * 86400)];
  NSDictionary *schedulerSummary = [[ALNJobsModuleRuntime sharedRuntime] runSchedulerAt:future error:&error];
  XCTAssertNotNil(schedulerSummary);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@1, schedulerSummary[@"triggeredCount"]);
  NSArray *triggered = [schedulerSummary[@"triggered"] isKindOfClass:[NSArray class]] ? schedulerSummary[@"triggered"] : @[];
  XCTAssertEqualObjects(@"storage.cleanup.default", [triggered firstObject][@"schedule"]);
  XCTAssertEqualObjects(@"maintenance", [triggered firstObject][@"queue"]);

  NSString *cleanupJobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:@"storage.cleanup"
                                                                              payload:@{}
                                                                              options:@{
                                                                                @"queue" : @"maintenance",
                                                                                @"notBefore" : future,
                                                                              }
                                                                                error:&error];
  XCTAssertNotNil(cleanupJobID);
  XCTAssertNil(error);
  workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:future limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);

  NSDictionary *deleted = [runtime objectRecordForIdentifier:stored[@"objectID"] error:&error];
  XCTAssertNil(deleted);
  XCTAssertEqual((NSInteger)ALNStorageModuleErrorNotFound, error.code);

  NSDictionary *summary = [runtime dashboardSummary];
  XCTAssertEqualObjects(@YES, summary[@"attachmentAdapter"][@"capabilities"][@"scoped"]);
}

// Two runtimes on one state file stand in for two propane workers (or a
// worker and the jobs worker): separate memory, one shared catalog.
- (ALNStorageModuleRuntime *)workerRuntimeWithStatePath:(NSString *)statePath
                                         attachmentRoot:(NSString *)attachmentRoot
                                                 shared:(BOOL)shared {
  ALNApplication *app = [self applicationWithStatePath:statePath attachmentRoot:attachmentRoot];
  NSMutableDictionary *config = [app.config mutableCopy];
  NSMutableDictionary *storage = [config[@"storageModule"] mutableCopy];
  storage[@"signingSecret"] = @"phase16c-shared-worker-signing-secret-0123456789";
  config[@"storageModule"] = storage;
  ALNApplication *configured = [[ALNApplication alloc] initWithConfig:config];
  [configured setAttachmentAdapter:app.attachmentAdapter];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:configured error:&error]);
  XCTAssertNil(error);
  if (shared) {
    XCTAssertTrue([[[ALNStorageModule alloc] init] registerWithApplication:configured error:&error]);
    XCTAssertNil(error);
    return [ALNStorageModuleRuntime sharedRuntime];
  }
  ALNStorageModuleRuntime *runtime = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertTrue([runtime configureWithApplication:configured error:&error]);
  XCTAssertNil(error);
  return runtime;
}

- (NSDictionary *)storeObjectNamed:(NSString *)name
                              body:(NSString *)body
                         inRuntime:(ALNStorageModuleRuntime *)runtime {
  NSError *error = nil;
  NSDictionary *object = [runtime storeObjectInCollection:@"gallery"
                                                     name:name
                                              contentType:@"image/png"
                                                     data:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                 metadata:nil
                                                    error:&error];
  XCTAssertNotNil(object);
  XCTAssertNil(error);
  return object;
}

- (NSString *)downloadedBodyForToken:(NSString *)token inRuntime:(ALNStorageModuleRuntime *)runtime {
  NSError *error = nil;
  NSData *data = [runtime downloadDataForToken:token metadata:NULL error:&error];
  return (data != nil) ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

- (NSMutableDictionary *)stateAtPath:(NSString *)statePath {
  NSData *data = [NSData dataWithContentsOfFile:statePath];
  XCTAssertNotNil(data);
  id state = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListMutableContainersAndLeaves
                                                        format:NULL
                                                         error:NULL];
  XCTAssertTrue([state isKindOfClass:[NSMutableDictionary class]]);
  return state;
}

- (void)writeState:(NSDictionary *)state toPath:(NSString *)statePath {
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:state
                                                            format:NSPropertyListBinaryFormat_v1_0
                                                           options:0
                                                             error:NULL];
  XCTAssertNotNil(data);
  XCTAssertTrue([data writeToFile:statePath atomically:YES]);
}

- (void)testRuntimesSharingOneStateFileKeepDistinctObjectsTokensAndCatalog {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNStorageModuleRuntime *workerA = [self workerRuntimeWithStatePath:statePath attachmentRoot:attachmentRoot shared:YES];
  ALNStorageModuleRuntime *workerB = [self workerRuntimeWithStatePath:statePath attachmentRoot:attachmentRoot shared:NO];
  XCTAssertTrue(workerA != workerB);

  NSDictionary *alice = [self storeObjectNamed:@"alice-private.png" body:@"alice data" inRuntime:workerA];
  NSError *error = nil;
  NSString *aliceToken = [workerA issueDownloadTokenForObjectID:alice[@"objectID"] expiresIn:60 error:&error];
  XCTAssertNotNil(aliceToken);
  NSDictionary *bob = [self storeObjectNamed:@"bob.png" body:@"bob data" inRuntime:workerB];

  // IDs are random, not per-process counters, so the two workers never collide.
  XCTAssertNotEqualObjects(alice[@"objectID"], bob[@"objectID"]);
  XCTAssertTrue([alice[@"objectID"] hasPrefix:@"obj-"]);
  XCTAssertEqual((NSUInteger)36, [alice[@"objectID"] length]);
  XCTAssertNil(alice[@"tokenNonce"]);

  // Alice's token resolves to Alice's object on either worker.
  XCTAssertEqualObjects(@"alice data", [self downloadedBodyForToken:aliceToken inRuntime:workerA]);
  XCTAssertEqualObjects(@"alice data", [self downloadedBodyForToken:aliceToken inRuntime:workerB]);

  // Neither worker's write dropped the other's object.
  for (ALNStorageModuleRuntime *worker in @[ workerA, workerB ]) {
    NSArray *names = [[worker listObjectsForCollection:@"gallery" query:nil] valueForKey:@"name"];
    XCTAssertEqualObjects((@[ @"alice-private.png", @"bob.png" ]),
                          [names sortedArrayUsingSelector:@selector(compare:)]);
    XCTAssertNotNil([worker objectRecordForIdentifier:bob[@"objectID"] error:NULL]);
  }
  NSDictionary *state = [self stateAtPath:statePath];
  XCTAssertNotNil(state[@"objectsByIdentifier"][alice[@"objectID"]]);
  XCTAssertNotNil(state[@"objectsByIdentifier"][bob[@"objectID"]]);

  // An upload session opened on one worker completes on the other.
  NSDictionary *session = [workerA createUploadSessionForCollection:@"gallery"
                                                               name:@"carol.png"
                                                        contentType:@"image/png"
                                                          sizeBytes:5
                                                           metadata:nil
                                                          expiresIn:60
                                                              error:&error];
  XCTAssertNotNil(session);
  XCTAssertTrue([session[@"sessionID"] hasPrefix:@"upload-"]);
  NSDictionary *carol = [workerB storeUploadData:[@"carol" dataUsingEncoding:NSUTF8StringEncoding]
                              forUploadSessionID:session[@"sessionID"]
                                           token:session[@"token"]
                                           error:&error];
  XCTAssertNotNil(carol);
  XCTAssertNil(error);
  XCTAssertNotNil([workerA objectRecordForIdentifier:carol[@"objectID"] error:NULL]);

  // A delete on one worker is seen by the other, and the token stops working.
  XCTAssertTrue([workerB deleteObjectIdentifier:alice[@"objectID"] error:&error]);
  XCTAssertNil([workerA objectRecordForIdentifier:alice[@"objectID"] error:NULL]);
  XCTAssertNil([self downloadedBodyForToken:aliceToken inRuntime:workerA]);
  XCTAssertNotNil([workerA objectRecordForIdentifier:bob[@"objectID"] error:NULL]);
}

- (void)testDownloadTokenIsBoundToTheObjectNotJustItsIdentifier {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNStorageModuleRuntime *worker = [self workerRuntimeWithStatePath:statePath attachmentRoot:attachmentRoot shared:YES];
  NSDictionary *alice = [self storeObjectNamed:@"alice.png" body:@"alice data" inRuntime:worker];
  NSDictionary *bob = [self storeObjectNamed:@"bob.png" body:@"bob data" inRuntime:worker];
  NSString *aliceToken = [worker issueDownloadTokenForObjectID:alice[@"objectID"] expiresIn:60 error:NULL];
  XCTAssertEqualObjects(@"alice data", [self downloadedBodyForToken:aliceToken inRuntime:worker]);

  // Another process puts a different object under Alice's ID (what a reused
  // ID would do). Her token must not hand it out.
  NSMutableDictionary *state = [self stateAtPath:statePath];
  NSMutableDictionary *objects = state[@"objectsByIdentifier"];
  NSMutableDictionary *replacement = [objects[bob[@"objectID"]] mutableCopy];
  replacement[@"objectID"] = alice[@"objectID"];
  objects[alice[@"objectID"]] = replacement;
  [self writeState:state toPath:statePath];

  NSError *error = nil;
  XCTAssertNil([worker downloadDataForToken:aliceToken metadata:NULL error:&error]);
  XCTAssertNotNil(error);
}

- (void)testStateWrittenWithCounterIdentifiersStillLoadsAndIssuesTokens {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNStorageModuleRuntime *seed = [self workerRuntimeWithStatePath:statePath attachmentRoot:attachmentRoot shared:YES];
  NSDictionary *stored = [self storeObjectNamed:@"legacy.png" body:@"legacy" inRuntime:seed];

  // Rewrite the record the way the previous release stored it: a counter ID
  // and no token nonce.
  NSMutableDictionary *state = [self stateAtPath:statePath];
  NSMutableDictionary *record = [state[@"objectsByIdentifier"][stored[@"objectID"]] mutableCopy];
  [record removeObjectForKey:@"tokenNonce"];
  record[@"objectID"] = @"obj-1";
  state[@"objectsByIdentifier"] = [@{ @"obj-1" : record } mutableCopy];
  state[@"objectIDsByCollection"] = [@{ @"gallery" : [@[ @"obj-1" ] mutableCopy] } mutableCopy];
  state[@"nextSequence"] = @1;
  [self writeState:state toPath:statePath];

  ALNStorageModuleRuntime *upgraded = [self workerRuntimeWithStatePath:statePath attachmentRoot:attachmentRoot shared:YES];
  NSError *error = nil;
  XCTAssertNotNil([upgraded objectRecordForIdentifier:@"obj-1" error:&error]);
  NSString *token = [upgraded issueDownloadTokenForObjectID:@"obj-1" expiresIn:60 error:&error];
  XCTAssertNotNil(token);
  XCTAssertEqualObjects(@"legacy", [self downloadedBodyForToken:token inRuntime:upgraded]);
  NSDictionary *next = [self storeObjectNamed:@"next.png" body:@"next" inRuntime:upgraded];
  XCTAssertNotEqualObjects(@"obj-2", next[@"objectID"]);
  XCTAssertNotNil([upgraded objectRecordForIdentifier:@"obj-1" error:NULL]);
}

- (ALNApplication *)storageApplicationWithStatePath:(NSString *)statePath
                                   attachmentAdapter:(id<ALNAttachmentAdapter>)attachmentAdapter
                                         persistence:(NSDictionary *)persistence {
  return [self storageApplicationWithStatePath:statePath
                             attachmentAdapter:attachmentAdapter
                                   persistence:persistence
                                     overrides:nil];
}

- (ALNApplication *)storageApplicationWithStatePath:(NSString *)statePath
                                   attachmentAdapter:(id<ALNAttachmentAdapter>)attachmentAdapter
                                         persistence:(NSDictionary *)persistence
                                           overrides:(NSDictionary *)overrides {
  NSMutableDictionary *persistenceConfig = [@{ @"enabled" : @YES, @"path" : statePath ?: @"", @"backend" : @"plist" } mutableCopy];
  [persistenceConfig addEntriesFromDictionary:persistence ?: @{}];
  NSMutableDictionary *config = [@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[] },
      @"worker" : @{ @"retryDelaySeconds" : @0 },
    },
    @"storageModule" : @{
      @"collections" : @{ @"classes" : @[ @"Phase16CPlainCollectionProvider" ] },
      @"persistence" : persistenceConfig,
      @"signingSecret" : @"phase16c-shared-worker-signing-secret-0123456789",
    },
  } mutableCopy];
  [config addEntriesFromDictionary:overrides ?: @{}];
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:config];
  if (attachmentAdapter != nil) {
    [app setAttachmentAdapter:attachmentAdapter];
  }
  return app;
}

- (NSError *)configureRuntime:(ALNStorageModuleRuntime *)runtime withApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  error = nil;
  if (![runtime configureWithApplication:app error:&error]) {
    XCTAssertNotNil(error);
    return error ?: [NSError errorWithDomain:@"Phase16C" code:1 userInfo:nil];
  }
  return nil;
}

- (void)testPersistenceRefusesAProcessLocalAttachmentAdapter {
  NSString *statePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"storage-state.plist"];
  // Each worker numbering its own in-memory attachments is what let one
  // worker's catalog entry name another worker's bytes.
  ALNApplication *app = [self storageApplicationWithStatePath:statePath
                                            attachmentAdapter:[[ALNInMemoryAttachmentAdapter alloc] init]
                                                  persistence:nil];
  NSError *error = [self configureRuntime:[[ALNStorageModuleRuntime alloc] init] withApplication:app];
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNStorageModuleErrorInvalidConfiguration, error.code);
  XCTAssertEqualObjects(@"process_local_attachment_adapter", error.userInfo[@"reason"]);

  // Without persistence each process keeps its own catalog, so the in-memory
  // adapter stays allowed.
  ALNApplication *ephemeral = [self storageApplicationWithStatePath:statePath
                                                  attachmentAdapter:[[ALNInMemoryAttachmentAdapter alloc] init]
                                                        persistence:@{ @"enabled" : @NO }];
  XCTAssertNil([self configureRuntime:[[ALNStorageModuleRuntime alloc] init] withApplication:ephemeral]);
}

- (void)testPersistenceWithoutAnAdapterSharesFilesystemAttachmentsAcrossWorkers {
  NSString *statePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"storage-state.plist"];
  ALNApplication *appA = [self storageApplicationWithStatePath:statePath attachmentAdapter:nil persistence:nil];
  ALNApplication *appB = [self storageApplicationWithStatePath:statePath attachmentAdapter:nil persistence:nil];
  XCTAssertTrue(appA.usesDefaultAttachmentAdapter);
  ALNStorageModuleRuntime *workerA = [[ALNStorageModuleRuntime alloc] init];
  ALNStorageModuleRuntime *workerB = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:workerA withApplication:appA]);
  XCTAssertNil([self configureRuntime:workerB withApplication:appB]);
  XCTAssertTrue([(id)appA.attachmentAdapter isKindOfClass:[ALNFileSystemAttachmentAdapter class]]);
  XCTAssertTrue([(id)appB.attachmentAdapter isKindOfClass:[ALNFileSystemAttachmentAdapter class]]);
  NSString *attachmentRoot = [[statePath stringByDeletingPathExtension] stringByAppendingString:@"-attachments"];
  BOOL isDirectory = NO;
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:attachmentRoot isDirectory:&isDirectory]);
  XCTAssertTrue(isDirectory);

  // The original two-worker report: Alice stores on A, Bob on B, and Alice's
  // token is served by B.
  NSDictionary *alice = [self storeObjectNamed:@"alice-private.png" body:@"alice data" inRuntime:workerA];
  NSDictionary *bob = [self storeObjectNamed:@"bob.png" body:@"bob data" inRuntime:workerB];
  NSString *aliceToken = [workerA issueDownloadTokenForObjectID:alice[@"objectID"] expiresIn:60 error:NULL];
  XCTAssertEqualObjects(@"alice data", [self downloadedBodyForToken:aliceToken inRuntime:workerB]);
  XCTAssertEqualObjects(@"alice data", [self downloadedBodyForToken:aliceToken inRuntime:workerA]);

  // Deleting Bob's object on B leaves Alice's bytes alone.
  NSError *error = nil;
  XCTAssertTrue([workerB deleteObjectIdentifier:bob[@"objectID"] error:&error]);
  XCTAssertEqualObjects(@"alice data", [self downloadedBodyForToken:aliceToken inRuntime:workerA]);
  XCTAssertEqualObjects(@"alice data", [self downloadedBodyForToken:aliceToken inRuntime:workerB]);
}

- (void)testDownloadRefusesAttachmentBytesThatDoNotMatchTheRecord {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNStorageModuleRuntime *worker = [self workerRuntimeWithStatePath:statePath attachmentRoot:attachmentRoot shared:NO];
  NSDictionary *alice = [self storeObjectNamed:@"alice.png" body:@"alice data" inRuntime:worker];
  NSString *aliceToken = [worker issueDownloadTokenForObjectID:alice[@"objectID"] expiresIn:60 error:NULL];
  XCTAssertEqualObjects(@"alice data", [self downloadedBodyForToken:aliceToken inRuntime:worker]);
  NSString *dataPath =
      [attachmentRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bin", alice[@"attachmentID"]]];
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:dataPath]);

  // Same length, other bytes (what a swapped attachment looks like), then a
  // different length.
  for (NSString *swapped in @[ @"bobby data", @"bob data" ]) {
    XCTAssertTrue([[swapped dataUsingEncoding:NSUTF8StringEncoding] writeToFile:dataPath atomically:YES]);
    NSError *error = nil;
    XCTAssertNil([worker downloadDataForToken:aliceToken metadata:NULL error:&error]);
    XCTAssertEqual((NSInteger)ALNStorageModuleErrorNotFound, error.code);
    error = nil;
    XCTAssertNil([worker openDownloadFileForToken:aliceToken metadata:NULL error:&error]);
    XCTAssertEqual((NSInteger)ALNStorageModuleErrorNotFound, error.code);
  }
  NSError *error = nil;
  NSDictionary *payload = @{ @"objectID" : alice[@"objectID"], @"variant" : @"thumb" };
  XCTAssertNil([worker processVariantJobPayload:payload error:&error]);
  XCTAssertEqual((NSInteger)ALNStorageModuleErrorNotFound, error.code);
}

- (void)testStateLockTimeoutFailsTheChangeInsteadOfWaitingForever {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSError *adapterError = nil;
  ALNFileSystemAttachmentAdapter *adapter =
      [[ALNFileSystemAttachmentAdapter alloc] initWithRootDirectory:[tempDir stringByAppendingPathComponent:@"attachments"]
                                                        adapterName:@"phase16c_fs"
                                                              error:&adapterError];
  XCTAssertNotNil(adapter);
  ALNApplication *app = [self storageApplicationWithStatePath:statePath
                                            attachmentAdapter:adapter
                                                  persistence:@{ @"lockTimeoutSeconds" : @0.3 }];
  ALNStorageModuleRuntime *worker = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:worker withApplication:app]);

  // Another holder (a hung worker) keeps the state lock.
  int held = ALNPlatformOpenExclusiveLock([statePath stringByAppendingString:@".lock"]);
  XCTAssertGreaterThanOrEqual(held, 0);
  NSDate *started = [NSDate date];
  NSError *error = nil;
  NSDictionary *object = [worker storeObjectInCollection:@"gallery"
                                                    name:@"late.png"
                                             contentType:@"image/png"
                                                    data:[@"late" dataUsingEncoding:NSUTF8StringEncoding]
                                                metadata:nil
                                                   error:&error];
  NSTimeInterval waited = -[started timeIntervalSinceNow];
  XCTAssertNil(object);
  XCTAssertEqual((NSInteger)ALNStorageModuleErrorStateBusy, error.code);
  XCTAssertGreaterThanOrEqual(waited, 0.25);
  XCTAssertLessThan(waited, 5.0);
  ALNPlatformReleaseExclusiveLock(held);

  XCTAssertNotNil([self storeObjectNamed:@"on-time.png" body:@"on time" inRuntime:worker]);
}

- (ALNFileSystemAttachmentAdapter *)filesystemAdapterAtPath:(NSString *)root {
  NSError *error = nil;
  ALNFileSystemAttachmentAdapter *adapter = [[ALNFileSystemAttachmentAdapter alloc] initWithRootDirectory:root
                                                                                              adapterName:@"phase16c_fs"
                                                                                                    error:&error];
  XCTAssertNotNil(adapter);
  XCTAssertNil(error);
  return adapter;
}

- (NSUInteger)attachmentFileCountAtPath:(NSString *)root {
  NSUInteger count = 0;
  for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL] ?: @[]) {
    if ([[name pathExtension] isEqualToString:@"bin"]) {
      count += 1;
    }
  }
  return count;
}

- (void)testConcurrentWritersOnOneStateFileAllSucceedPromptly {
  [self assertConcurrentWritersWithBackend:@"plist"];
}

- (void)testSQLiteConcurrentWritersPreserveEveryObject {
  [self assertConcurrentWritersWithBackend:@"sqlite"];
}

- (void)assertConcurrentWritersWithBackend:(NSString *)backend {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  const NSUInteger writers = 8;
  const NSUInteger perWriter = 50;
  NSMutableArray<ALNStorageModuleRuntime *> *runtimes = [NSMutableArray array];
  for (NSUInteger idx = 0; idx < writers; idx++) {
    // One runtime per writer: separate memory and lock descriptors, as
    // separate worker processes have.
    ALNApplication *app = [self storageApplicationWithStatePath:statePath
                                              attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                    persistence:@{ @"backend" : backend }];
    ALNStorageModuleRuntime *runtime = [[ALNStorageModuleRuntime alloc] init];
    XCTAssertNil([self configureRuntime:runtime withApplication:app]);
    [runtimes addObject:runtime];
  }

  NSLock *resultsLock = [[NSLock alloc] init];
  NSMutableArray<NSString *> *failures = [NSMutableArray array];
  dispatch_group_t group = dispatch_group_create();
  NSDate *started = [NSDate date];
  for (NSUInteger writer = 0; writer < writers; writer++) {
    ALNStorageModuleRuntime *runtime = runtimes[writer];
    dispatch_group_async(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      for (NSUInteger idx = 0; idx < perWriter; idx++) {
        NSError *error = nil;
        NSString *name = [NSString stringWithFormat:@"w%lu-%lu.txt", (unsigned long)writer, (unsigned long)idx];
        NSDictionary *object = [runtime storeObjectInCollection:@"plain"
                                                           name:name
                                                    contentType:@"text/plain"
                                                           data:[name dataUsingEncoding:NSUTF8StringEncoding]
                                                       metadata:nil
                                                          error:&error];
        if (object == nil) {
          [resultsLock lock];
          [failures addObject:[NSString stringWithFormat:@"%@: %@", name, error.localizedDescription ?: @"?"]];
          [resultsLock unlock];
        }
      }
    });
  }
  XCTAssertEqual(0L, dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(180 * NSEC_PER_SEC))));
  NSTimeInterval elapsed = -[started timeIntervalSinceNow];
  XCTAssertEqualObjects(@[], failures);
  XCTAssertLessThan(elapsed, 120.0);

  ALNApplication *reader = [self storageApplicationWithStatePath:statePath
                                               attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                     persistence:@{ @"backend" : backend }];
  ALNStorageModuleRuntime *check = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:check withApplication:reader]);
  XCTAssertEqual(writers * perWriter, [[check listObjectsForCollection:@"plain" query:nil] count]);
  XCTAssertEqual(writers * perWriter, [self attachmentFileCountAtPath:attachmentRoot]);
}

- (void)testFailedCatalogWriteRemovesTheAttachmentItWrote {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNApplication *app = [self storageApplicationWithStatePath:statePath
                                            attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                  persistence:@{ @"lockTimeoutSeconds" : @0.2 }];
  ALNStorageModuleRuntime *worker = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:worker withApplication:app]);
  XCTAssertNotNil([self storeObjectNamed:@"kept.png" body:@"kept" inRuntime:worker]);
  NSUInteger before = [self attachmentFileCountAtPath:attachmentRoot];
  XCTAssertEqual((NSUInteger)1, before);

  int held = ALNPlatformOpenExclusiveLock([statePath stringByAppendingString:@".lock"]);
  XCTAssertGreaterThanOrEqual(held, 0);
  NSError *error = nil;
  XCTAssertNil([worker storeObjectInCollection:@"plain"
                                          name:@"lost.txt"
                                   contentType:@"text/plain"
                                          data:[@"lost" dataUsingEncoding:NSUTF8StringEncoding]
                                      metadata:nil
                                         error:&error]);
  XCTAssertEqual((NSInteger)ALNStorageModuleErrorStateBusy, error.code);
  ALNPlatformReleaseExclusiveLock(held);
  XCTAssertEqual(before, [self attachmentFileCountAtPath:attachmentRoot]);
}

- (void)testDeleteLeavesAttachmentBytesThatBelongToAnotherObject {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNStorageModuleRuntime *worker = [self workerRuntimeWithStatePath:statePath attachmentRoot:attachmentRoot shared:NO];
  NSDictionary *alice = [self storeObjectNamed:@"alice.png" body:@"alice-bytes!" inRuntime:worker];
  NSDictionary *bob = [self storeObjectNamed:@"bob.png" body:@"bobby-bytes!" inRuntime:worker];

  // Point Alice's record at Bob's attachment: same size, other bytes.
  NSMutableDictionary *state = [self stateAtPath:statePath];
  state[@"objectsByIdentifier"][alice[@"objectID"]][@"attachmentID"] = bob[@"attachmentID"];
  [self writeState:state toPath:statePath];

  NSError *error = nil;
  XCTAssertTrue([worker deleteObjectIdentifier:alice[@"objectID"] error:&error]);
  NSString *bobPath = [attachmentRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bin", bob[@"attachmentID"]]];
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:bobPath]);
  NSString *bobToken = [worker issueDownloadTokenForObjectID:bob[@"objectID"] expiresIn:60 error:NULL];
  XCTAssertEqualObjects(@"bobby-bytes!", [self downloadedBodyForToken:bobToken inRuntime:worker]);

  // A delete of an object whose bytes are its own still removes them.
  XCTAssertTrue([worker deleteObjectIdentifier:bob[@"objectID"] error:&error]);
  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:bobPath]);
}

#if !defined(_WIN32)
- (void)testStateFileIsOwnerOnlyWhateverTheUmask {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  mode_t previous = umask(0);
  ALNStorageModuleRuntime *worker =
      [self workerRuntimeWithStatePath:statePath
                        attachmentRoot:[tempDir stringByAppendingPathComponent:@"attachments"]
                                shared:NO];
  [self storeObjectNamed:@"private.png" body:@"private" inRuntime:worker];
  umask(previous);
  struct stat info;
  XCTAssertEqual(0, stat([statePath fileSystemRepresentation], &info));
  XCTAssertEqual((mode_t)0600, (mode_t)(info.st_mode & 0777));
  NSArray *leftovers = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:tempDir error:NULL]
      filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF ENDSWITH '.tmp'"]];
  XCTAssertEqualObjects(@[], leftovers);
}
#endif

- (void)testStartupCompletesWhenTheStateLockIsBusy {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNStorageModuleRuntime *seed = [self workerRuntimeWithStatePath:statePath attachmentRoot:attachmentRoot shared:NO];
  NSDictionary *stored = [self storeObjectNamed:@"seed.png" body:@"seed" inRuntime:seed];

  int held = ALNPlatformOpenExclusiveLock([statePath stringByAppendingString:@".lock"]);
  XCTAssertGreaterThanOrEqual(held, 0);
  ALNApplication *app = [self storageApplicationWithStatePath:statePath
                                            attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                  persistence:@{
                                                    @"lockTimeoutSeconds" : @0.1,
                                                    @"startupLockTimeoutSeconds" : @0.3,
                                                  }];
  ALNStorageModuleRuntime *starting = [[ALNStorageModuleRuntime alloc] init];
  // A busy lock while other workers serve requests must not fail startup.
  XCTAssertNil([self configureRuntime:starting withApplication:app]);
  ALNPlatformReleaseExclusiveLock(held);
  XCTAssertNotNil([starting objectRecordForIdentifier:stored[@"objectID"] error:NULL]);
}

- (void)testUnsharedStateWithSeveralWorkersIsReported {
  NSString *statePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"storage-state.plist"];
  ALNApplication *app = [self storageApplicationWithStatePath:statePath
                                            attachmentAdapter:nil
                                                  persistence:@{ @"enabled" : @NO }
                                                    overrides:@{
                                                      @"environment" : @"production",
                                                      @"propaneAccessories" : @{ @"workerCount" : @4 },
                                                    }];
  ALNStorageModuleRuntime *runtime = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:runtime withApplication:app]);
  NSArray *codes = [[runtime resolvedConfigSummary][@"warnings"] valueForKey:@"code"];
  XCTAssertEqualObjects(@[ @"storage_unshared_state" ], codes);

  ALNApplication *single = [self storageApplicationWithStatePath:statePath
                                               attachmentAdapter:nil
                                                     persistence:@{ @"enabled" : @NO }
                                                       overrides:@{
                                                         @"environment" : @"production",
                                                         @"propaneAccessories" : @{ @"workerCount" : @1 },
                                                       }];
  ALNStorageModuleRuntime *singleRuntime = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:singleRuntime withApplication:single]);
  XCTAssertEqualObjects(@[], [singleRuntime resolvedConfigSummary][@"warnings"]);
}

- (void)writeStateForObjects:(NSUInteger)count
                     likeRecord:(NSDictionary *)template
                     collection:(NSString *)collection
                         toPath:(NSString *)statePath
                         format:(NSPropertyListFormat)format {
  NSMutableDictionary *objects = [NSMutableDictionary dictionary];
  NSMutableArray *ids = [NSMutableArray array];
  for (NSUInteger idx = 0; idx < count; idx++) {
    NSString *objectID = [NSString stringWithFormat:@"obj-%032lx", (unsigned long)(idx + 1)];
    NSMutableDictionary *record = [template mutableCopy];
    record[@"objectID"] = objectID;
    record[@"sequence"] = @(idx + 1);
    record[@"name"] = [NSString stringWithFormat:@"bulk-%lu.txt", (unsigned long)idx];
    objects[objectID] = record;
    [ids addObject:objectID];
  }
  NSDictionary *state = @{
    @"version" : @1,
    @"nextSequence" : @(count),
    @"objectIDsByCollection" : @{ collection : ids },
    @"objectsByIdentifier" : objects,
    @"uploadSessionsByIdentifier" : @{},
    @"activityLog" : @[],
  };
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:state format:format options:0 error:NULL];
  XCTAssertNotNil(data);
  XCTAssertTrue([data writeToFile:statePath atomically:YES]);
}

- (void)testLargeCatalogWritesStayWellUnderTheLockTimeout {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNApplication *seedApp = [self storageApplicationWithStatePath:statePath
                                                attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                      persistence:nil];
  ALNStorageModuleRuntime *seed = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:seed withApplication:seedApp]);
  NSDictionary *template = [self storeObjectInRuntime:seed named:@"template.txt" body:@"template"];
  NSDictionary *storedTemplate = [self stateAtPath:statePath][@"objectsByIdentifier"][template[@"objectID"]];
  XCTAssertNotNil(storedTemplate);

  [self writeStateForObjects:5000
                  likeRecord:storedTemplate
                  collection:@"plain"
                      toPath:statePath
                      format:NSPropertyListXMLFormat_v1_0];
  ALNApplication *app = [self storageApplicationWithStatePath:statePath
                                            attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                  persistence:nil];
  ALNStorageModuleRuntime *runtime = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:runtime withApplication:app]);
  XCTAssertEqual((NSUInteger)5000, [[runtime listObjectsForCollection:@"plain" query:nil] count]);

  // One store rewrites the whole 5,000-object catalog under the lock.
  NSDate *started = [NSDate date];
  XCTAssertNotNil([self storeObjectInRuntime:runtime named:@"one-more.txt" body:@"one more"]);
  NSTimeInterval elapsed = -[started timeIntervalSinceNow];
  XCTAssertLessThan(elapsed, 3.0);
  NSData *written = [NSData dataWithContentsOfFile:statePath];
  XCTAssertTrue([[[NSString alloc] initWithData:[written subdataWithRange:NSMakeRange(0, 5)]
                                       encoding:NSUTF8StringEncoding] isEqualToString:@"<?xml"]);
  XCTAssertEqual((NSUInteger)5001, [[[self stateAtPath:statePath][@"objectsByIdentifier"] allKeys] count]);
}

- (void)testBinaryStateFilesFromEarlierReleasesStillLoad {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNApplication *seedApp = [self storageApplicationWithStatePath:statePath
                                                attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                      persistence:nil];
  ALNStorageModuleRuntime *seed = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:seed withApplication:seedApp]);
  NSDictionary *template = [self storeObjectInRuntime:seed named:@"template.txt" body:@"template"];
  NSDictionary *storedTemplate = [self stateAtPath:statePath][@"objectsByIdentifier"][template[@"objectID"]];
  [self writeStateForObjects:20
                  likeRecord:storedTemplate
                  collection:@"plain"
                      toPath:statePath
                      format:NSPropertyListBinaryFormat_v1_0];

  ALNApplication *app = [self storageApplicationWithStatePath:statePath
                                            attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                  persistence:nil];
  ALNStorageModuleRuntime *runtime = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:runtime withApplication:app]);
  XCTAssertEqual((NSUInteger)20, [[runtime listObjectsForCollection:@"plain" query:nil] count]);
}

- (NSDictionary *)storeObjectInRuntime:(ALNStorageModuleRuntime *)runtime named:(NSString *)name body:(NSString *)body {
  NSError *error = nil;
  NSDictionary *object = [runtime storeObjectInCollection:@"plain"
                                                     name:name
                                              contentType:@"text/plain"
                                                     data:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                 metadata:nil
                                                    error:&error];
  XCTAssertNotNil(object);
  XCTAssertNil(error);
  return object;
}

- (void)testReadsDoNotWaitForTheStateLock {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNStorageModuleRuntime *workerA = [[ALNStorageModuleRuntime alloc] init];
  ALNStorageModuleRuntime *workerB = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:workerA
                      withApplication:[self storageApplicationWithStatePath:statePath
                                                          attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                                persistence:nil]]);
  XCTAssertNil([self configureRuntime:workerB
                      withApplication:[self storageApplicationWithStatePath:statePath
                                                          attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                                persistence:nil]]);
  NSDictionary *alice = [self storeObjectInRuntime:workerA named:@"alice.txt" body:@"alice data"];
  NSString *aliceToken = [workerA issueDownloadTokenForObjectID:alice[@"objectID"] expiresIn:60 error:NULL];
  // B writes, so A's copy is stale, then another holder keeps the lock.
  NSDictionary *bob = [self storeObjectInRuntime:workerB named:@"bob.txt" body:@"bob data"];
  int held = ALNPlatformOpenExclusiveLock([statePath stringByAppendingString:@".lock"]);
  XCTAssertGreaterThanOrEqual(held, 0);

  NSDate *started = [NSDate date];
  XCTAssertEqualObjects(@"alice data", [self downloadedBodyForToken:aliceToken inRuntime:workerA]);
  XCTAssertNotNil([workerA objectRecordForIdentifier:bob[@"objectID"] error:NULL]);
  NSString *bobToken = [workerA issueDownloadTokenForObjectID:bob[@"objectID"] expiresIn:60 error:NULL];
  XCTAssertEqualObjects(@"bob data", [self downloadedBodyForToken:bobToken inRuntime:workerA]);
  XCTAssertLessThan(-[started timeIntervalSinceNow], 1.0);
  ALNPlatformReleaseExclusiveLock(held);
}

- (void)testStartupRemovesStaleTemporaryStateFiles {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  ALNStorageModuleRuntime *seed = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:seed
                      withApplication:[self storageApplicationWithStatePath:statePath
                                                          attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                                persistence:nil]]);
  [self storeObjectInRuntime:seed named:@"kept.txt" body:@"kept"];

  // Left by a process killed between writing and renaming its state file.
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *stale = [statePath stringByAppendingString:@".0123456789abcdef.tmp"];
  NSString *fresh = [statePath stringByAppendingString:@".fedcba9876543210.tmp"];
  NSString *unrelated = [tempDir stringByAppendingPathComponent:@"other.plist.0123456789abcdef.tmp"];
  for (NSString *path in @[ stale, fresh, unrelated ]) {
    XCTAssertTrue([[@"partial" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:NO]);
  }
  NSDate *old = [NSDate dateWithTimeIntervalSinceNow:-120];
  XCTAssertTrue([fileManager setAttributes:@{ NSFileModificationDate : old } ofItemAtPath:stale error:NULL]);
  XCTAssertTrue([fileManager setAttributes:@{ NSFileModificationDate : old } ofItemAtPath:unrelated error:NULL]);

  ALNStorageModuleRuntime *restarted = [[ALNStorageModuleRuntime alloc] init];
  XCTAssertNil([self configureRuntime:restarted
                      withApplication:[self storageApplicationWithStatePath:statePath
                                                          attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                                persistence:nil]]);
  XCTAssertFalse([fileManager fileExistsAtPath:stale]);
  XCTAssertTrue([fileManager fileExistsAtPath:fresh]);
  XCTAssertTrue([fileManager fileExistsAtPath:unrelated]);
  XCTAssertEqual((NSUInteger)1, [[restarted listObjectsForCollection:@"plain" query:nil] count]);
}

- (void)testDownloadsDuringConcurrentWritesReturnTheRightBytesOrNotFound {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"storage-state.plist"];
  NSString *attachmentRoot = [tempDir stringByAppendingPathComponent:@"attachments"];
  NSMutableArray<ALNStorageModuleRuntime *> *runtimes = [NSMutableArray array];
  for (NSUInteger idx = 0; idx < 4; idx++) {
    ALNStorageModuleRuntime *runtime = [[ALNStorageModuleRuntime alloc] init];
    XCTAssertNil([self configureRuntime:runtime
                        withApplication:[self storageApplicationWithStatePath:statePath
                                                            attachmentAdapter:[self filesystemAdapterAtPath:attachmentRoot]
                                                                  persistence:nil]]);
    [runtimes addObject:runtime];
  }
  NSLock *shared = [[NSLock alloc] init];
  NSMutableArray<NSArray *> *issued = [NSMutableArray array];  // @[ token, expected body ]
  __block NSUInteger mismatches = 0;
  __block NSUInteger served = 0;
  __block BOOL writing = YES;
  dispatch_group_t writers = dispatch_group_create();
  dispatch_group_t readers = dispatch_group_create();
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

  // Two writers store and delete objects; two readers download whatever
  // tokens exist. Bodies differ but share a length, so only the checksum
  // tells them apart.
  for (NSUInteger writer = 0; writer < 2; writer++) {
    ALNStorageModuleRuntime *runtime = runtimes[writer];
    dispatch_group_async(writers, queue, ^{
      for (NSUInteger idx = 0; idx < 60; idx++) {
        NSString *body = [NSString stringWithFormat:@"w%lu-body-%04lu", (unsigned long)writer, (unsigned long)idx];
        NSDictionary *object = [runtime storeObjectInCollection:@"plain"
                                                           name:body
                                                    contentType:@"text/plain"
                                                           data:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                       metadata:nil
                                                          error:NULL];
        if (object == nil) {
          continue;
        }
        NSString *token = [runtime issueDownloadTokenForObjectID:object[@"objectID"] expiresIn:120 error:NULL];
        if (token != nil) {
          [shared lock];
          [issued addObject:@[ token, body ]];
          [shared unlock];
        }
        if (idx % 3 == 0) {
          (void)[runtime deleteObjectIdentifier:object[@"objectID"] error:NULL];
        }
      }
    });
  }
  for (NSUInteger reader = 2; reader < 4; reader++) {
    ALNStorageModuleRuntime *runtime = runtimes[reader];
    dispatch_group_async(readers, queue, ^{
      NSUInteger idx = 0;
      for (;;) {
        [shared lock];
        BOOL keepGoing = writing;
        NSArray *pick = ([issued count] > 0) ? issued[(idx * 7 + reader) % [issued count]] : nil;
        [shared unlock];
        idx += 1;
        if (pick != nil) {
          NSData *data = [runtime downloadDataForToken:pick[0] metadata:NULL error:NULL];
          if (data != nil) {
            NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [shared lock];
            served += 1;
            if (![body isEqualToString:pick[1]]) {
              mismatches += 1;
            }
            [shared unlock];
          }
        }
        if (!keepGoing) {
          break;
        }
      }
    });
  }
  // Stop the readers once the writers are done.
  XCTAssertEqual(0L, dispatch_group_wait(writers, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(180 * NSEC_PER_SEC))));
  [shared lock];
  writing = NO;
  [shared unlock];
  XCTAssertEqual(0L, dispatch_group_wait(readers, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC))));
  XCTAssertEqual((NSUInteger)0, mismatches);
  XCTAssertGreaterThan(served, (NSUInteger)0);
}

- (void)testStreamingDownloadPinsVerifiedBytesAcrossPathReplacement {
  NSString *directory = [self temporaryDirectory];
  NSString *root = [directory stringByAppendingPathComponent:@"attachments"];
  ALNStorageModuleRuntime *runtime = [self workerRuntimeWithStatePath:[directory stringByAppendingPathComponent:@"state.plist"] attachmentRoot:root shared:NO];
  NSDictionary *object = [self storeObjectNamed:@"alice.png" body:@"alice data" inRuntime:runtime];
  NSString *token = [runtime issueDownloadTokenForObjectID:object[@"objectID"] expiresIn:60 error:NULL];
  NSError *error = nil;
  NSDictionary *metadata = nil;
  NSFileHandle *handle = [runtime openDownloadFileForToken:token metadata:&metadata error:&error];
  XCTAssertNotNil(handle, @"%@", error);
  XCTAssertEqualObjects(object[@"objectID"], metadata[@"object"][@"objectID"]);
  NSString *path = [root stringByAppendingPathComponent:[object[@"attachmentID"] stringByAppendingString:@".bin"]];
  XCTAssertTrue(ALNTestReplaceFilePath([@"bobby data" dataUsingEncoding:NSUTF8StringEncoding], path));
  XCTAssertEqualObjects(@"alice data", [[NSString alloc] initWithData:[handle readDataToEndOfFile] encoding:NSUTF8StringEncoding]);
  [handle closeFile];
  XCTAssertNil([runtime openDownloadFileForToken:token metadata:NULL error:&error]);
  XCTAssertEqual((NSInteger)ALNStorageModuleErrorNotFound, error.code);
}

- (void)testVariantSourceLimitRejectsBeforeMaterializingBytes {
  NSString *directory = [self temporaryDirectory];
  ALNApplication *base = [self applicationWithStatePath:[directory stringByAppendingPathComponent:@"state.plist"] attachmentRoot:[directory stringByAppendingPathComponent:@"attachments"]];
  NSMutableDictionary *config = [base.config mutableCopy];
  NSMutableDictionary *storage = [config[@"storageModule"] mutableCopy];
  storage[@"maxVariantInputBytes"] = @4;
  config[@"storageModule"] = storage;
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:config];
  [app setAttachmentAdapter:base.attachmentAdapter];
  ALNStorageModuleRuntime *runtime = [[ALNStorageModuleRuntime alloc] init];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertTrue([runtime configureWithApplication:app error:&error], @"%@", error);
  NSDictionary *object = [self storeObjectNamed:@"large.png" body:@"12345" inRuntime:runtime];
  error = nil;
  NSDictionary *payload = @{ @"objectID" : object[@"objectID"], @"variant" : @"thumb" };
  XCTAssertNil([runtime processVariantJobPayload:payload error:&error]);
  XCTAssertEqual((NSInteger)ALNStorageModuleErrorValidationFailed, error.code);
}

@end
