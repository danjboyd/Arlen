#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNStorageModule.h"

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

@interface Phase16CTests : XCTestCase
@end

@implementation Phase16CTests

- (NSString *)temporaryDirectory {
  NSString *template =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"arlen-phase16c-XXXXXX"];
  const char *templateCString = [template fileSystemRepresentation];
  char *buffer = strdup(templateCString);
  XCTAssertNotEqual(buffer, NULL);
  char *created = mkdtemp(buffer);
  XCTAssertNotEqual(created, NULL);
  NSString *result = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:buffer
                                                                                  length:strlen(buffer)];
  free(buffer);
  return result;
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

@end
