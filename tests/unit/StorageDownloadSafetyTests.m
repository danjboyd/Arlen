#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <dispatch/dispatch.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNStorageModule.h"
#import "ALNStorageCatalog.h"
#import "ALNPlatform.h"
#import "../shared/ALNTestSupport.h"

@interface StorageSafetyThrowingCatalog : ALNStorageCatalog
@property(nonatomic) BOOL throwNextWrite;
@end
@implementation StorageSafetyThrowingCatalog
- (BOOL)writeState:(NSDictionary *)state error:(NSError **)error {
  if (self.throwNextWrite) {
    self.throwNextWrite = NO;
    [NSException raise:@"StorageCatalogFailure" format:@"intentional backend exception"];
  }
  return [super writeState:state error:error];
}
@end

@interface StorageDownloadSafetyFilesCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation StorageDownloadSafetyFilesCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"files";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Files",
    @"acceptedContentTypes" : @[
      @"text/html", @"image/svg+xml", @"image/png", @"application/pdf", @"video/mp4", @"text/plain"
    ],
    @"visibility" : @"private",
  };
}

@end

@interface StorageDownloadSafetyImagesCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation StorageDownloadSafetyImagesCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"images";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Images",
    @"acceptedContentTypes" : @[ @"image/*" ],
    @"visibility" : @"private",
  };
}

@end

@interface StorageDownloadSafetyAnyCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation StorageDownloadSafetyAnyCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"any";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{ @"title" : @"Any", @"visibility" : @"private" };
}

@end

@interface StorageDownloadSafetyCollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation StorageDownloadSafetyCollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    [[StorageDownloadSafetyFilesCollection alloc] init],
    [[StorageDownloadSafetyImagesCollection alloc] init],
    [[StorageDownloadSafetyAnyCollection alloc] init],
  ];
}

@end

@interface StorageDownloadSafetyTests : XCTestCase
@property(nonatomic, strong) ALNApplication *app;
@end

@implementation StorageDownloadSafetyTests

- (void)setUp {
  [super setUp];
  self.app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"storageModule" : @{
      @"collections" : @{ @"classes" : @[ @"StorageDownloadSafetyCollectionProvider" ] },
      @"downloadTokenTTLSeconds" : @60,
    },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:self.app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNStorageModule alloc] init] registerWithApplication:self.app error:&error]);
  XCTAssertNil(error);
}

- (void)tearDown {
  self.app = nil;
  [super tearDown];
}

- (ALNResponse *)downloadObjectNamed:(NSString *)name
                         contentType:(NSString *)contentType
                                body:(NSString *)body {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *object = [runtime storeObjectInCollection:@"files"
                                                     name:name
                                              contentType:contentType
                                                     data:[body dataUsingEncoding:NSUTF8StringEncoding]
                                                 metadata:nil
                                                    error:&error];
  XCTAssertNotNil(object, @"%@", error);
  NSString *token = [runtime issueDownloadTokenForObjectID:object[@"objectID"] expiresIn:60 error:&error];
  XCTAssertTrue([token length] > 0, @"%@", error);
  ALNRequest *request =
      [[ALNRequest alloc] initWithMethod:@"GET"
                                    path:[NSString stringWithFormat:@"/storage/api/download/%@", token ?: @""]
                             queryString:@""
                                 headers:@{}
                                    body:[NSData data]];
  ALNResponse *response = [self.app dispatchRequest:request];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  return response;
}

- (ALNStorageModuleRuntime *)persistentRuntimeAt:(NSString *)root backend:(NSString *)backend {
  self.app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test", @"appRoot" : root, @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"storageModule" : @{
      @"collections" : @{ @"classes" : @[ @"StorageDownloadSafetyCollectionProvider" ] },
      @"persistence" : @{ @"path" : @"state.plist", @"backend" : backend, @"lockTimeoutSeconds" : @0.1 },
    },
  }];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:self.app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNStorageModule alloc] init] registerWithApplication:self.app error:&error], @"%@", error);
  return [ALNStorageModuleRuntime sharedRuntime];
}

- (void)restoreApplication:(ALNApplication *)app {
  self.app = app;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:NULL]);
  XCTAssertTrue([[[ALNStorageModule alloc] init] registerWithApplication:app error:NULL]);
}

- (void)changeCatalogAt:(NSString *)path objectID:(NSString *)objectID backup:(NSString *)backup restore:(BOOL)restore {
  NSTask *task = [NSTask new];
  task.launchPath = ALNTestToolPath(@"python3");
  task.arguments = @[ @"-c", @"import sqlite3,sys,pathlib; c=sqlite3.connect(sys.argv[1]); key=sys.argv[2]; p=pathlib.Path(sys.argv[3]); old=c.execute(\"SELECT value FROM catalog WHERE kind='objects' AND key=?\",(key,)).fetchone()[0]; value=p.read_bytes() if sys.argv[4]=='restore' else b'broken-catalog-record'; p.write_bytes(old) if sys.argv[4]!='restore' else None; c.execute(\"UPDATE catalog SET value=? WHERE kind='objects' AND key=?\",(value,key)); c.commit(); c.close()",
    path, objectID, backup, restore ? @"restore" : @"corrupt" ];
  NSMutableDictionary *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
  [environment removeObjectForKey:@"LD_PRELOAD"];
  [environment removeObjectForKey:@"DYLD_INSERT_LIBRARIES"];
  task.environment = environment;
  [task launch];
  [task waitUntilExit];
  XCTAssertEqual(0, task.terminationStatus);
}

- (void)testCatalogReloadFailureDeniesCachedDownloadsAndRecoversAfterRepair {
  ALNApplication *original = self.app;
  for (NSString *backend in @[ @"sqlite", @"plist" ]) {
    NSString *root = ALNTestTemporaryDirectory(@"storage-read-failure");
    @try {
      ALNStorageModuleRuntime *runtime = [self persistentRuntimeAt:root backend:backend];
      NSError *error = nil;
      NSData *body = [@"private object" dataUsingEncoding:NSUTF8StringEncoding];
      NSDictionary *object = [runtime storeObjectInCollection:@"files" name:@"data.txt"
          contentType:@"text/plain" data:body metadata:nil error:&error];
      XCTAssertNotNil(object, @"%@", error);
      NSString *token = [runtime issueDownloadTokenForObjectID:object[@"objectID"] expiresIn:60 error:&error];
      XCTAssertEqualObjects(body, [runtime downloadDataForToken:token metadata:NULL error:&error]);
      NSFileHandle *handle = [runtime openDownloadFileForToken:token metadata:NULL error:&error];
      XCTAssertNotNil(handle, @"%@", error);
      [handle closeFile];
      NSString *state = [root stringByAppendingPathComponent:@"state.plist"];
      NSData *originalState = nil;
      NSString *backup = [root stringByAppendingPathComponent:@"record.backup"];
      if ([backend isEqualToString:@"sqlite"]) {
        [self changeCatalogAt:[state stringByAppendingString:@".sqlite3"] objectID:object[@"objectID"]
                      backup:backup restore:NO];
      } else {
        originalState = [NSData dataWithContentsOfFile:state];
        XCTAssertTrue([@"broken catalog" writeToFile:state atomically:YES encoding:NSUTF8StringEncoding error:&error]);
      }
      // Both buffered and pinned-file downloads must refuse the cached record,
      // including when the caller does not request an NSError.
      XCTAssertNil([runtime downloadDataForToken:token metadata:NULL error:NULL]);
      error = nil;
      handle = [runtime openDownloadFileForToken:token metadata:NULL error:&error];
      XCTAssertNil(handle);
      [handle closeFile];
      XCTAssertNotNil(error);
      XCTAssertEqual((NSUInteger)0, [[runtime listObjectsForCollection:@"files" query:nil] count]);
      XCTAssertNil([runtime objectRecordForIdentifier:object[@"objectID"] error:NULL]);
      XCTAssertNil([runtime issueDownloadTokenForObjectID:object[@"objectID"] expiresIn:60 error:NULL]);
      if ([backend isEqualToString:@"sqlite"]) {
        [self changeCatalogAt:[state stringByAppendingString:@".sqlite3"] objectID:object[@"objectID"]
                      backup:backup restore:YES];
      } else {
        XCTAssertTrue([originalState writeToFile:state atomically:YES]);
      }
      error = nil;
      XCTAssertEqualObjects(body, [runtime downloadDataForToken:token metadata:NULL error:&error]);
      XCTAssertNil(error);
    } @finally {
      [self restoreApplication:original];
      [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }
  }
}

- (void)testCatalogWriterExceptionReleasesLocksAndDiscardsUncommittedState {
  ALNApplication *original = self.app;
  NSString *root = ALNTestTemporaryDirectory(@"storage-write-exception");
  @try {
    ALNStorageModuleRuntime *runtime = [self persistentRuntimeAt:root backend:@"sqlite"];
    NSString *state = [root stringByAppendingPathComponent:@"state.plist"];
    StorageSafetyThrowingCatalog *catalog = [[StorageSafetyThrowingCatalog alloc]
        initWithPath:[state stringByAppendingString:@".sqlite3"] legacyPath:state error:NULL];
    XCTAssertNotNil(catalog);
    catalog.throwNextWrite = YES;
    [runtime setValue:catalog forKey:@"catalog"];
    BOOL caught = NO;
    @try {
      [runtime storeObjectInCollection:@"files" name:@"failed.txt" contentType:@"text/plain"
          data:[@"failed" dataUsingEncoding:NSUTF8StringEncoding] metadata:nil error:NULL];
    } @catch (NSException *exception) {
      caught = [exception.name isEqualToString:@"StorageCatalogFailure"];
    }
    XCTAssertTrue(caught);
    NSRecursiveLock *transactionLock = [runtime valueForKey:@"transactionLock"];
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    __block BOOL acquired = NO;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      acquired = [transactionLock tryLock];
      if (acquired) [transactionLock unlock];
      dispatch_semaphore_signal(finished);
    });
    long waited = dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    XCTAssertEqual((long)0, waited);
    if (waited == 0) XCTAssertTrue(acquired, @"a backend exception must release the recursive transaction guard");
    NSString *attachments = [root stringByAppendingPathComponent:@"state-attachments"];
    XCTAssertEqual((NSUInteger)0, [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:attachments error:NULL] count]);
    int descriptor = ALNPlatformOpenExclusiveLockWithTimeout([state stringByAppendingString:@".lock"], 0.1);
    XCTAssertGreaterThanOrEqual(descriptor, 0, @"a backend exception must release the shared writer lock");
    ALNPlatformReleaseExclusiveLock(descriptor);
    XCTAssertEqual((NSUInteger)0, [[runtime listObjectsForCollection:@"files" query:nil] count]);
    NSError *error = nil;
    XCTAssertNotNil([runtime storeObjectInCollection:@"files" name:@"next.txt" contentType:@"text/plain"
        data:[@"next" dataUsingEncoding:NSUTF8StringEncoding] metadata:nil error:&error], @"%@", error);
    XCTAssertEqual((NSUInteger)1, [[runtime listObjectsForCollection:@"files" query:nil] count]);
  } @finally {
    [self restoreApplication:original];
    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
  }
}

- (void)testHTMLDownloadIsSandboxedAttachment {
  ALNResponse *response = [self downloadObjectNamed:@"page.html"
                                        contentType:@"text/html"
                                               body:@"<script>alert(1)</script>"];
  XCTAssertEqualObjects(@"attachment; filename=\"page.html\"",
                        [response headerForName:@"Content-Disposition"]);
  XCTAssertEqualObjects(@"sandbox", [response headerForName:@"Content-Security-Policy"]);
  XCTAssertEqualObjects(@"nosniff", [response headerForName:@"X-Content-Type-Options"]);
}

- (void)testSVGDownloadIsSandboxedAttachment {
  ALNResponse *response = [self downloadObjectNamed:@"logo.svg"
                                        contentType:@"image/svg+xml"
                                               body:@"<svg xmlns=\"http://www.w3.org/2000/svg\"/>"];
  XCTAssertEqualObjects(@"attachment; filename=\"logo.svg\"",
                        [response headerForName:@"Content-Disposition"]);
  XCTAssertEqualObjects(@"sandbox", [response headerForName:@"Content-Security-Policy"]);
  XCTAssertEqualObjects(@"nosniff", [response headerForName:@"X-Content-Type-Options"]);
}

- (void)testPlainTextDownloadIsAttachment {
  ALNResponse *response = [self downloadObjectNamed:@"notes.txt" contentType:@"text/plain" body:@"hi"];
  XCTAssertTrue([[response headerForName:@"Content-Disposition"] hasPrefix:@"attachment;"]);
  XCTAssertEqualObjects(@"sandbox", [response headerForName:@"Content-Security-Policy"]);
}

- (void)testPNGDownloadIsInline {
  ALNResponse *response = [self downloadObjectNamed:@"photo.png" contentType:@"image/png" body:@"png!"];
  XCTAssertEqualObjects(@"image/png", [response headerForName:@"Content-Type"]);
  XCTAssertEqualObjects(@"inline; filename=\"photo.png\"",
                        [response headerForName:@"Content-Disposition"]);
  XCTAssertEqualObjects(@"sandbox", [response headerForName:@"Content-Security-Policy"]);
  XCTAssertEqualObjects(@"nosniff", [response headerForName:@"X-Content-Type-Options"]);
}

- (void)testDeclaredContentTypeMustBeASingleMediaType {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSData *data = [@"<script>alert(1)</script>" dataUsingEncoding:NSUTF8StringEncoding];
  for (NSString *declared in @[
         @"application/pdf;x=,text/html", @"video/mp4,text/html", @"application/pdf, text/html",
         @"application/pdf; name=\"a,b\"", @"application/pdf;\ttext/html", @"application/pdf\r\nX-Evil: 1",
         @"application/pdf; x", @"application/pdf; =v", @"application/pdf/x", @"application", @"application/pdf;;",
         @"image/pngé"
       ]) {
    NSError *error = nil;
    XCTAssertNil([runtime storeObjectInCollection:@"files" name:@"f" contentType:declared data:data metadata:nil error:&error],
                 @"%@", declared);
    XCTAssertEqualObjects(@"contentType", error.userInfo[@"field"], @"%@", declared);
    error = nil;
    XCTAssertNil([runtime createUploadSessionForCollection:@"files"
                                                      name:@"f"
                                               contentType:declared
                                                 sizeBytes:4
                                                  metadata:nil
                                                 expiresIn:60
                                                     error:&error],
                 @"%@", declared);
  }
}

- (void)testDownloadSendsOnlyTheNormalizedMediaType {
  ALNResponse *text = [self downloadObjectNamed:@"notes.txt" contentType:@"Text/Plain; Charset=UTF-8; x=1" body:@"hi"];
  XCTAssertEqualObjects(@"text/plain; charset=utf-8", [text headerForName:@"Content-Type"]);
  XCTAssertEqualObjects(@"sandbox", [text headerForName:@"Content-Security-Policy"]);

  ALNResponse *pdf = [self downloadObjectNamed:@"guide.pdf" contentType:@"application/PDF; version=1" body:@"%PDF"];
  XCTAssertEqualObjects(@"application/pdf", [pdf headerForName:@"Content-Type"]);
  XCTAssertEqualObjects(@"inline; filename=\"guide.pdf\"", [pdf headerForName:@"Content-Disposition"]);
}

- (void)testPDFAndVideoDownloadsAreInline {
  ALNResponse *pdf = [self downloadObjectNamed:@"guide.pdf" contentType:@"application/pdf" body:@"%PDF"];
  XCTAssertEqualObjects(@"inline; filename=\"guide.pdf\"", [pdf headerForName:@"Content-Disposition"]);
  XCTAssertEqualObjects(@"nosniff", [pdf headerForName:@"X-Content-Type-Options"]);
  XCTAssertNotEqualObjects(@"sandbox", [pdf headerForName:@"Content-Security-Policy"]);

  ALNResponse *video = [self downloadObjectNamed:@"clip.mp4" contentType:@"video/mp4" body:@"mp4"];
  XCTAssertEqualObjects(@"inline; filename=\"clip.mp4\"", [video headerForName:@"Content-Disposition"]);
  XCTAssertEqualObjects(@"sandbox", [video headerForName:@"Content-Security-Policy"]);
}

- (void)testDownloadFilenameIsSanitized {
  ALNResponse *response = [self downloadObjectNamed:@"../résumé \"final\".html"
                                        contentType:@"text/html"
                                               body:@"x"];
  NSString *disposition = [response headerForName:@"Content-Disposition"];
  XCTAssertEqualObjects(@"attachment; filename=\"r_sum___final_.html\"; "
                        @"filename*=UTF-8''r%C3%A9sum%C3%A9%20%22final%22.html",
                        disposition);
}

- (void)testWildcardImageCollectionRejectsSVG {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSData *data = [@"<svg/>" dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  XCTAssertNil([runtime storeObjectInCollection:@"images"
                                           name:@"logo.svg"
                                    contentType:@"image/svg+xml"
                                           data:data
                                       metadata:nil
                                          error:&error]);
  XCTAssertNotNil(error);

  error = nil;
  XCTAssertNil([runtime createUploadSessionForCollection:@"images"
                                                    name:@"logo.svg"
                                             contentType:@"image/svg+xml"
                                               sizeBytes:6
                                                metadata:nil
                                               expiresIn:60
                                                   error:&error]);
  XCTAssertNotNil(error);

  error = nil;
  XCTAssertNotNil([runtime storeObjectInCollection:@"images"
                                              name:@"photo.png"
                                       contentType:@"image/png"
                                              data:[@"png!" dataUsingEncoding:NSUTF8StringEncoding]
                                          metadata:nil
                                             error:&error],
                  @"%@", error);
}

- (void)testDefaultCollectionRejectsHTMLAndSVGButAcceptsOtherTypes {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  NSData *data = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
  for (NSString *type in @[ @"text/html", @"text/html; charset=utf-8", @"image/svg+xml", @"application/xhtml+xml" ]) {
    NSError *error = nil;
    XCTAssertNil([runtime storeObjectInCollection:@"any" name:@"f" contentType:type data:data metadata:nil error:&error],
                 @"%@", type);
    XCTAssertNotNil(error, @"%@", type);
  }
  NSError *error = nil;
  XCTAssertNotNil([runtime storeObjectInCollection:@"any"
                                              name:@"f.json"
                                       contentType:@"application/json"
                                              data:data
                                          metadata:nil
                                             error:&error],
                  @"%@", error);
}

@end
