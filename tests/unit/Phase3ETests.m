#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNServices.h"

static NSInteger gPhase3EPluginDidStartCount = 0;
static NSInteger gPhase3EPluginDidStopCount = 0;

@interface Phase3EServicesPlugin : NSObject <ALNPlugin, ALNLifecycleHook>
@end

@implementation Phase3EServicesPlugin

- (NSString *)pluginName {
  return @"phase3e_services_plugin";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  (void)error;
  [application setJobsAdapter:[[ALNInMemoryJobAdapter alloc] initWithAdapterName:@"phase3e_jobs_adapter"]];
  [application setCacheAdapter:[[ALNInMemoryCacheAdapter alloc] initWithAdapterName:@"phase3e_cache_adapter"]];
  [application setLocalizationAdapter:[[ALNInMemoryLocalizationAdapter alloc] initWithAdapterName:@"phase3e_i18n_adapter"]];
  [application setMailAdapter:[[ALNInMemoryMailAdapter alloc] initWithAdapterName:@"phase3e_mail_adapter"]];
  [application setAttachmentAdapter:[[ALNInMemoryAttachmentAdapter alloc] initWithAdapterName:@"phase3e_attachment_adapter"]];

  id<ALNLocalizationAdapter> i18n = application.localizationAdapter;
  (void)[i18n registerTranslations:@{
    @"phase3e.hello" : @"Hello %{name}",
  }
                            locale:@"en"
                             error:NULL];
  (void)[i18n registerTranslations:@{
    @"phase3e.hello" : @"Hola %{name}",
  }
                            locale:@"es"
                             error:NULL];
  return YES;
}

- (void)applicationDidStart:(ALNApplication *)application {
  (void)application;
  gPhase3EPluginDidStartCount += 1;
}

- (void)applicationDidStop:(ALNApplication *)application {
  (void)application;
  gPhase3EPluginDidStopCount += 1;
}

@end

@interface Phase3EServicesController : ALNController
@end

@implementation Phase3EServicesController

- (id)probe:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;

  id<ALNJobAdapter> jobs = [self jobsAdapter];
  NSString *jobID = [jobs enqueueJobNamed:@"phase3e.probe"
                                  payload:@{
                                    @"source" : @"phase3e",
                                  }
                                  options:@{}
                                    error:&error];
  ALNJobEnvelope *leased = [jobs dequeueDueJobAt:[NSDate date] error:NULL];
  if (leased != nil) {
    (void)[jobs acknowledgeJobID:leased.jobID error:NULL];
  }

  id<ALNCacheAdapter> cache = [self cacheAdapter];
  (void)[cache setObject:@"cache-hit" forKey:@"phase3e.probe" ttlSeconds:30 error:NULL];
  NSString *cached = [cache objectForKey:@"phase3e.probe" atTime:[NSDate date] error:NULL];

  NSString *name = [self stringParamForName:@"name"] ?: @"Arlen";
  NSString *message = [self localizedStringForKey:@"phase3e.hello"
                                           locale:nil
                                   fallbackLocale:nil
                                     defaultValue:@"Hello %{name}"
                                        arguments:@{
                                          @"name" : name,
                                        }];

  id<ALNMailAdapter> mail = [self mailAdapter];
  ALNMailMessage *mailMessage = [[ALNMailMessage alloc] initWithFrom:@"noreply@example.test"
                                                                   to:@[ @"dev@example.test" ]
                                                                   cc:nil
                                                                  bcc:nil
                                                              subject:@"phase3e"
                                                             textBody:@"probe"
                                                             htmlBody:nil
                                                              headers:nil
                                                             metadata:nil];
  NSString *deliveryID = [mail deliverMessage:mailMessage error:NULL];

  id<ALNAttachmentAdapter> attachment = [self attachmentAdapter];
  NSData *attachmentData = [@"probe" dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  NSString *attachmentID = [attachment saveAttachmentNamed:@"phase3e.txt"
                                               contentType:@"text/plain"
                                                      data:attachmentData
                                                  metadata:nil
                                                     error:NULL];
  NSDictionary *attachmentMeta = nil;
  NSData *readData = [attachment attachmentDataForID:attachmentID ?: @""
                                            metadata:&attachmentMeta
                                               error:NULL];
  NSString *attachmentText =
      [[NSString alloc] initWithData:readData ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";

  return @{
    @"jobsAdapter" : [jobs adapterName] ?: @"",
    @"cacheAdapter" : [cache adapterName] ?: @"",
    @"i18nAdapter" : [[self localizationAdapter] adapterName] ?: @"",
    @"mailAdapter" : [mail adapterName] ?: @"",
    @"attachmentAdapter" : [attachment adapterName] ?: @"",
    @"message" : message ?: @"",
    @"cached" : cached ?: @"",
    @"jobID" : jobID ?: @"",
    @"dequeuedJobID" : leased.jobID ?: @"",
    @"deliveryID" : deliveryID ?: @"",
    @"attachmentID" : attachmentID ?: @"",
    @"attachmentText" : attachmentText ?: @"",
    @"attachmentSize" : attachmentMeta[@"sizeBytes"] ?: @(0),
    @"error" : error.localizedDescription ?: @"",
  };
}

@end

@interface Phase3EJobWorkerRuntime : NSObject <ALNJobWorkerRuntime>

@property(nonatomic, assign) ALNJobWorkerDisposition disposition;
@property(nonatomic, assign) NSUInteger callCount;
@property(nonatomic, assign) BOOL emitHandlerErrors;

- (instancetype)initWithDisposition:(ALNJobWorkerDisposition)disposition;

@end

@implementation Phase3EJobWorkerRuntime

- (instancetype)initWithDisposition:(ALNJobWorkerDisposition)disposition {
  self = [super init];
  if (self) {
    _disposition = disposition;
    _callCount = 0;
    _emitHandlerErrors = NO;
  }
  return self;
}

- (ALNJobWorkerDisposition)handleJob:(ALNJobEnvelope *)job error:(NSError **)error {
  self.callCount += 1;
  if (self.emitHandlerErrors && error != NULL) {
    *error = [NSError errorWithDomain:@"Phase3E.Tests"
                                 code:1
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   [NSString stringWithFormat:@"runtime failure for %@", job.name ?: @""]
                             }];
  }
  return self.disposition;
}

@end

@interface Phase3ETests : XCTestCase
@end

@implementation Phase3ETests

- (void)setUp {
  [super setUp];
  gPhase3EPluginDidStartCount = 0;
  gPhase3EPluginDidStopCount = 0;
}

- (ALNApplication *)buildApp {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"apiOnly" : @(YES),
    @"openapi" : @{
      @"enabled" : @(NO),
      @"docsUIEnabled" : @(NO),
    },
    @"services" : @{
      @"i18n" : @{
        @"defaultLocale" : @"es",
        @"fallbackLocale" : @"en",
      },
    },
    @"plugins" : @{
      @"classes" : @[ @"Phase3EServicesPlugin" ],
    },
  }];
  [app registerRouteMethod:@"GET"
                      path:@"/services/probe"
                      name:@"phase3e_probe"
           controllerClass:[Phase3EServicesController class]
                    action:@"probe"];
  return app;
}

- (NSString *)redisTestURL {
  const char *value = getenv("ARLEN_REDIS_TEST_URL");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (NSString *)temporaryPathWithPrefix:(NSString *)prefix {
  NSString *baseDirectory = NSTemporaryDirectory();
  if ([baseDirectory length] == 0) {
    baseDirectory = @"/tmp";
  }
  NSString *normalizedPrefix = [prefix isKindOfClass:[NSString class]] && [prefix length] > 0 ? prefix : @"phase3e";
  NSString *name = [NSString stringWithFormat:@"%@-%@",
                                              normalizedPrefix,
                                              [[NSUUID UUID] UUIDString] ?: @"tmp"];
  return [baseDirectory stringByAppendingPathComponent:name];
}

- (NSUInteger)posixPermissionsAtPath:(NSString *)path {
  NSDictionary *attributes =
      [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
  return [attributes[NSFilePosixPermissions] unsignedIntegerValue] & 0777;
}

- (NSDictionary *)jsonFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id value = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:&error];
  if (error != nil || ![value isKindOfClass:[NSDictionary class]]) {
    XCTFail(@"expected JSON dictionary, error=%@", error.localizedDescription ?: @"");
  }
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

- (void)testPluginWiresAdaptersAndRunsCompatibilitySuites {
  ALNApplication *app = [self buildApp];
  XCTAssertEqual((NSUInteger)1, [app.plugins count]);
  XCTAssertEqualObjects(@"phase3e_jobs_adapter", [app.jobsAdapter adapterName]);
  XCTAssertEqualObjects(@"phase3e_cache_adapter", [app.cacheAdapter adapterName]);
  XCTAssertEqualObjects(@"phase3e_i18n_adapter", [app.localizationAdapter adapterName]);
  XCTAssertEqualObjects(@"phase3e_mail_adapter", [app.mailAdapter adapterName]);
  XCTAssertEqualObjects(@"phase3e_attachment_adapter", [app.attachmentAdapter adapterName]);

  NSError *startError = nil;
  XCTAssertTrue([app startWithError:&startError]);
  XCTAssertNil(startError);
  XCTAssertEqual((NSInteger)1, gPhase3EPluginDidStartCount);

  NSError *suiteError = nil;
  BOOL suiteOK = ALNRunServiceCompatibilitySuite(app.jobsAdapter,
                                                 app.cacheAdapter,
                                                 app.localizationAdapter,
                                                 app.mailAdapter,
                                                 app.attachmentAdapter,
                                                 &suiteError);
  XCTAssertTrue(suiteOK);
  XCTAssertNil(suiteError);

  [app shutdown];
  XCTAssertEqual((NSInteger)1, gPhase3EPluginDidStopCount);
}

- (void)testControllerServiceHelpersUseConfiguredDefaults {
  ALNApplication *app = [self buildApp];
  NSError *startError = nil;
  XCTAssertTrue([app startWithError:&startError]);
  XCTAssertNil(startError);

  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET"
                                                      path:@"/services/probe"
                                               queryString:@"name=Arlen"
                                                   headers:@{
                                                     @"accept" : @"application/json",
                                                   }
                                                      body:[NSData data]];
  ALNResponse *response = [app dispatchRequest:request];
  NSDictionary *payload = [self jsonFromResponse:response];

  XCTAssertEqual((NSInteger)200, response.statusCode);
  XCTAssertEqualObjects(@"phase3e_jobs_adapter", payload[@"jobsAdapter"]);
  XCTAssertEqualObjects(@"phase3e_cache_adapter", payload[@"cacheAdapter"]);
  XCTAssertEqualObjects(@"phase3e_i18n_adapter", payload[@"i18nAdapter"]);
  XCTAssertEqualObjects(@"phase3e_mail_adapter", payload[@"mailAdapter"]);
  XCTAssertEqualObjects(@"phase3e_attachment_adapter", payload[@"attachmentAdapter"]);
  XCTAssertEqualObjects(@"Hola Arlen", payload[@"message"]);
  XCTAssertEqualObjects(@"cache-hit", payload[@"cached"]);
  XCTAssertTrue([payload[@"jobID"] hasPrefix:@"job-"]);
  XCTAssertEqualObjects(payload[@"jobID"], payload[@"dequeuedJobID"]);
  XCTAssertTrue([payload[@"deliveryID"] hasPrefix:@"mail-"]);
  XCTAssertTrue([payload[@"attachmentID"] hasPrefix:@"att-"]);
  XCTAssertEqualObjects(@"probe", payload[@"attachmentText"]);

  [app shutdown];
}

- (void)testJobWorkerAcknowledgesSuccessfulJobs {
  ALNInMemoryJobAdapter *adapter = [[ALNInMemoryJobAdapter alloc] initWithAdapterName:@"phase3e_worker_ack"];
  XCTAssertNotNil([adapter enqueueJobNamed:@"job.a" payload:@{} options:@{} error:NULL]);
  XCTAssertNotNil([adapter enqueueJobNamed:@"job.b" payload:@{} options:@{} error:NULL]);

  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:adapter];
  worker.maxJobsPerRun = 10;
  worker.retryDelaySeconds = 0;
  Phase3EJobWorkerRuntime *runtime =
      [[Phase3EJobWorkerRuntime alloc] initWithDisposition:ALNJobWorkerDispositionAcknowledge];

  NSError *error = nil;
  ALNJobWorkerRunSummary *summary = [worker runDueJobsAt:[NSDate date] runtime:runtime error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(summary);
  XCTAssertEqual((NSUInteger)2, summary.leasedCount);
  XCTAssertEqual((NSUInteger)2, summary.acknowledgedCount);
  XCTAssertEqual((NSUInteger)0, summary.retriedCount);
  XCTAssertEqual((NSUInteger)0, summary.handlerErrorCount);
  XCTAssertFalse(summary.reachedRunLimit);
  XCTAssertEqual((NSUInteger)2, runtime.callCount);
  XCTAssertEqual((NSUInteger)0, [[adapter pendingJobsSnapshot] count]);
  XCTAssertEqual((NSUInteger)0, [[adapter deadLetterJobsSnapshot] count]);
}

- (void)testJobWorkerRetriesFailedJobsUntilDeadLettered {
  ALNInMemoryJobAdapter *adapter = [[ALNInMemoryJobAdapter alloc] initWithAdapterName:@"phase3e_worker_retry"];
  XCTAssertNotNil([adapter enqueueJobNamed:@"job.retry"
                                   payload:@{}
                                   options:@{
                                     @"maxAttempts" : @2
                                   }
                                     error:NULL]);

  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:adapter];
  worker.maxJobsPerRun = 1;
  worker.retryDelaySeconds = 0;
  Phase3EJobWorkerRuntime *runtime =
      [[Phase3EJobWorkerRuntime alloc] initWithDisposition:ALNJobWorkerDispositionRetry];
  runtime.emitHandlerErrors = YES;

  NSError *firstError = nil;
  ALNJobWorkerRunSummary *firstRun = [worker runDueJobsAt:[NSDate date] runtime:runtime error:&firstError];
  XCTAssertNil(firstError);
  XCTAssertNotNil(firstRun);
  XCTAssertEqual((NSUInteger)1, firstRun.leasedCount);
  XCTAssertEqual((NSUInteger)0, firstRun.acknowledgedCount);
  XCTAssertEqual((NSUInteger)1, firstRun.retriedCount);
  XCTAssertEqual((NSUInteger)1, firstRun.handlerErrorCount);
  XCTAssertTrue(firstRun.reachedRunLimit);
  XCTAssertEqual((NSUInteger)1, [[adapter pendingJobsSnapshot] count]);
  XCTAssertEqual((NSUInteger)0, [[adapter deadLetterJobsSnapshot] count]);

  NSError *secondError = nil;
  ALNJobWorkerRunSummary *secondRun = [worker runDueJobsAt:[NSDate date] runtime:runtime error:&secondError];
  XCTAssertNil(secondError);
  XCTAssertNotNil(secondRun);
  XCTAssertEqual((NSUInteger)1, secondRun.leasedCount);
  XCTAssertEqual((NSUInteger)0, secondRun.acknowledgedCount);
  XCTAssertEqual((NSUInteger)1, secondRun.retriedCount);
  XCTAssertEqual((NSUInteger)1, secondRun.handlerErrorCount);
  XCTAssertTrue(secondRun.reachedRunLimit);
  XCTAssertEqual((NSUInteger)0, [[adapter pendingJobsSnapshot] count]);
  XCTAssertEqual((NSUInteger)1, [[adapter deadLetterJobsSnapshot] count]);
}

- (void)testJobWorkerRespectsRunLimit {
  ALNInMemoryJobAdapter *adapter = [[ALNInMemoryJobAdapter alloc] initWithAdapterName:@"phase3e_worker_limit"];
  XCTAssertNotNil([adapter enqueueJobNamed:@"job.1" payload:@{} options:@{} error:NULL]);
  XCTAssertNotNil([adapter enqueueJobNamed:@"job.2" payload:@{} options:@{} error:NULL]);
  XCTAssertNotNil([adapter enqueueJobNamed:@"job.3" payload:@{} options:@{} error:NULL]);

  ALNJobWorker *worker = [[ALNJobWorker alloc] initWithJobsAdapter:adapter];
  worker.maxJobsPerRun = 2;
  worker.retryDelaySeconds = 0;
  Phase3EJobWorkerRuntime *runtime =
      [[Phase3EJobWorkerRuntime alloc] initWithDisposition:ALNJobWorkerDispositionAcknowledge];

  NSError *error = nil;
  ALNJobWorkerRunSummary *summary = [worker runDueJobsAt:[NSDate date] runtime:runtime error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(summary);
  XCTAssertEqual((NSUInteger)2, summary.leasedCount);
  XCTAssertEqual((NSUInteger)2, summary.acknowledgedCount);
  XCTAssertEqual((NSUInteger)0, summary.retriedCount);
  XCTAssertTrue(summary.reachedRunLimit);
  XCTAssertEqual((NSUInteger)1, [[adapter pendingJobsSnapshot] count]);
}

- (void)testRedisCacheAdapterRejectsInvalidURL {
  NSError *error = nil;
  ALNRedisCacheAdapter *adapter = [[ALNRedisCacheAdapter alloc] initWithURLString:@"http://localhost:6379/0"
                                                                         namespace:@"arlen:test:invalid"
                                                                       adapterName:@"redis_invalid"
                                                                             error:&error];
  XCTAssertNil(adapter);
  XCTAssertNotNil(error);
}

- (void)testRedisCacheAdapterConformanceSuiteWhenConfigured {
  NSString *url = [self redisTestURL];
  if ([url length] == 0) {
    return;
  }

  NSString *namespacePrefix =
      [NSString stringWithFormat:@"arlen:test:%@", [[NSUUID UUID] UUIDString] ?: @"phase3e"];
  NSError *adapterError = nil;
  ALNRedisCacheAdapter *adapter = [[ALNRedisCacheAdapter alloc] initWithURLString:url
                                                                         namespace:namespacePrefix
                                                                       adapterName:@"redis_test_cache"
                                                                             error:&adapterError];
  XCTAssertNotNil(adapter);
  XCTAssertNil(adapterError);
  if (adapter == nil) {
    return;
  }

  NSError *suiteError = nil;
  BOOL suiteOK = ALNRunCacheAdapterConformanceSuite(adapter, &suiteError);
  XCTAssertTrue(suiteOK);
  XCTAssertNil(suiteError);
  (void)[adapter clearWithError:NULL];
}

- (void)testFileSystemAttachmentAdapterRejectsEmptyRoot {
  NSError *error = nil;
  ALNFileSystemAttachmentAdapter *adapter =
      [[ALNFileSystemAttachmentAdapter alloc] initWithRootDirectory:@""
                                                        adapterName:@"fs_invalid"
                                                              error:&error];
  XCTAssertNil(adapter);
  XCTAssertNotNil(error);
}

- (void)testFileSystemAttachmentAdapterConformanceSuite {
  NSString *rootPath = [self temporaryPathWithPrefix:@"arlen-phase3e-attachments"];
  NSError *adapterError = nil;
  ALNFileSystemAttachmentAdapter *adapter =
      [[ALNFileSystemAttachmentAdapter alloc] initWithRootDirectory:rootPath
                                                        adapterName:@"filesystem_test_attachment"
                                                              error:&adapterError];
  XCTAssertNotNil(adapter);
  XCTAssertNil(adapterError);
  if (adapter == nil) {
    return;
  }

  NSError *suiteError = nil;
  BOOL suiteOK = ALNRunAttachmentAdapterConformanceSuite(adapter, &suiteError);
  XCTAssertTrue(suiteOK);
  XCTAssertNil(suiteError);
  XCTAssertEqual((NSUInteger)0, [[adapter listAttachmentMetadata] count]);
  (void)[[NSFileManager defaultManager] removeItemAtPath:rootPath error:NULL];
}

- (void)testFileSystemAttachmentAdapterRejectsInvalidIDsAndSymlinkEscapes {
  NSString *rootPath = [self temporaryPathWithPrefix:@"arlen-phase3e-attachments"];
  NSError *adapterError = nil;
  ALNFileSystemAttachmentAdapter *adapter =
      [[ALNFileSystemAttachmentAdapter alloc] initWithRootDirectory:rootPath
                                                        adapterName:@"filesystem_test_attachment"
                                                              error:&adapterError];
  XCTAssertNotNil(adapter);
  XCTAssertNil(adapterError);
  if (adapter == nil) {
    return;
  }

  NSError *invalidError = nil;
  XCTAssertNil([adapter attachmentMetadataForID:@"../outside" error:&invalidError]);
  XCTAssertNotNil(invalidError);
  XCTAssertEqual((NSInteger)568, invalidError.code);

  NSError *absolutePathError = nil;
  XCTAssertNil([adapter attachmentMetadataForID:@"/tmp/outside" error:&absolutePathError]);
  XCTAssertNotNil(absolutePathError);
  XCTAssertEqual((NSInteger)568, absolutePathError.code);

  NSString *outsideRoot = [self temporaryPathWithPrefix:@"arlen-phase3e-outside"];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:outsideRoot
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:NULL]);
  NSString *outsideDataPath = [outsideRoot stringByAppendingPathComponent:@"outside.bin"];
  NSString *outsideMetadataPath = [outsideRoot stringByAppendingPathComponent:@"outside.plist"];
  NSData *outsideData = [@"outside-secret" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertTrue([outsideData writeToFile:outsideDataPath atomically:YES]);
  NSData *outsideMetadata =
      [NSPropertyListSerialization dataWithPropertyList:@{
        @"attachmentID" : @"att-0123456789abcdef0123456789abcdef",
        @"name" : @"outside.txt",
        @"contentType" : @"text/plain",
        @"sizeBytes" : @([outsideData length]),
        @"createdAt" : @([[NSDate date] timeIntervalSince1970]),
        @"metadata" : @{},
      }
                                                 format:NSPropertyListBinaryFormat_v1_0
                                                options:0
                                                  error:NULL];
  XCTAssertNotNil(outsideMetadata);
  XCTAssertTrue([outsideMetadata writeToFile:outsideMetadataPath atomically:YES]);

  NSString *symlinkID = @"att-0123456789abcdef0123456789abcdef";
  NSString *linkedDataPath =
      [rootPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bin", symlinkID]];
  NSString *linkedMetadataPath =
      [rootPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", symlinkID]];
  XCTAssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:linkedDataPath
                                                     withDestinationPath:outsideDataPath
                                                                   error:NULL]);
  XCTAssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:linkedMetadataPath
                                                     withDestinationPath:outsideMetadataPath
                                                                   error:NULL]);

  NSError *symlinkError = nil;
  XCTAssertNil([adapter attachmentDataForID:symlinkID metadata:NULL error:&symlinkError]);
  XCTAssertNotNil(symlinkError);
  XCTAssertTrue(symlinkError.code == 569 || symlinkError.code == 570);

  (void)[[NSFileManager defaultManager] removeItemAtPath:outsideRoot error:NULL];
  (void)[[NSFileManager defaultManager] removeItemAtPath:rootPath error:NULL];
}

- (void)testFileJobAdapterConformanceSuite {
  NSString *rootPath = [self temporaryPathWithPrefix:@"arlen-phase3f-jobs"];
  NSString *storagePath = [rootPath stringByAppendingPathComponent:@"jobs/state.plist"];
  NSError *adapterError = nil;
  ALNFileJobAdapter *adapter = [[ALNFileJobAdapter alloc] initWithStoragePath:storagePath
                                                                   adapterName:@"file_test_jobs"
                                                                         error:&adapterError];
  XCTAssertNotNil(adapter);
  XCTAssertNil(adapterError);
  if (adapter == nil) {
    return;
  }

  NSError *suiteError = nil;
  BOOL suiteOK = ALNRunJobAdapterConformanceSuite(adapter, &suiteError);
  XCTAssertTrue(suiteOK);
  XCTAssertNil(suiteError);
  XCTAssertEqual((NSUInteger)0, [[adapter pendingJobsSnapshot] count]);
  XCTAssertEqual((NSUInteger)0, [[adapter deadLetterJobsSnapshot] count]);
  (void)[[NSFileManager defaultManager] removeItemAtPath:rootPath error:NULL];
}

- (void)testFileMailAdapterConformanceSuite {
  NSString *rootPath = [self temporaryPathWithPrefix:@"arlen-phase3f-mail"];
  NSError *adapterError = nil;
  ALNFileMailAdapter *adapter = [[ALNFileMailAdapter alloc] initWithStorageDirectory:rootPath
                                                                          adapterName:@"file_test_mail"
                                                                                error:&adapterError];
  XCTAssertNotNil(adapter);
  XCTAssertNil(adapterError);
  if (adapter == nil) {
    return;
  }

  NSError *suiteError = nil;
  BOOL suiteOK = ALNRunMailAdapterConformanceSuite(adapter, &suiteError);
  XCTAssertTrue(suiteOK);
  XCTAssertNil(suiteError);
  XCTAssertEqual((NSUInteger)0, [[adapter deliveriesSnapshot] count]);
  (void)[[NSFileManager defaultManager] removeItemAtPath:rootPath error:NULL];
}

- (void)testFileBackedServiceAdaptersPersistPrivatePermissions {
  NSString *attachmentRoot = [self temporaryPathWithPrefix:@"arlen-phase3e-attachment-perms"];
  ALNFileSystemAttachmentAdapter *attachmentAdapter =
      [[ALNFileSystemAttachmentAdapter alloc] initWithRootDirectory:attachmentRoot
                                                        adapterName:@"filesystem_test_attachment"
                                                              error:NULL];
  XCTAssertNotNil(attachmentAdapter);
  NSString *attachmentID = [attachmentAdapter saveAttachmentNamed:@"note.txt"
                                                     contentType:@"text/plain"
                                                            data:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]
                                                        metadata:nil
                                                           error:NULL];
  XCTAssertTrue([attachmentID hasPrefix:@"att-"]);
  NSString *attachmentDataPath =
      [attachmentRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.bin", attachmentID]];
  NSString *attachmentMetadataPath =
      [attachmentRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", attachmentID]];
  XCTAssertEqual((NSUInteger)0700, [self posixPermissionsAtPath:attachmentRoot]);
  XCTAssertEqual((NSUInteger)0600, [self posixPermissionsAtPath:attachmentDataPath]);
  XCTAssertEqual((NSUInteger)0600, [self posixPermissionsAtPath:attachmentMetadataPath]);

  NSString *jobsRoot = [self temporaryPathWithPrefix:@"arlen-phase3e-job-perms"];
  NSString *storagePath = [jobsRoot stringByAppendingPathComponent:@"jobs/state.plist"];
  ALNFileJobAdapter *jobAdapter = [[ALNFileJobAdapter alloc] initWithStoragePath:storagePath
                                                                      adapterName:@"file_test_jobs"
                                                                            error:NULL];
  XCTAssertNotNil(jobAdapter);
  XCTAssertEqual((NSUInteger)0700, [self posixPermissionsAtPath:[storagePath stringByDeletingLastPathComponent]]);
  XCTAssertEqual((NSUInteger)0600, [self posixPermissionsAtPath:storagePath]);

  NSString *mailRoot = [self temporaryPathWithPrefix:@"arlen-phase3e-mail-perms"];
  ALNFileMailAdapter *mailAdapter = [[ALNFileMailAdapter alloc] initWithStorageDirectory:mailRoot
                                                                              adapterName:@"file_test_mail"
                                                                                    error:NULL];
  XCTAssertNotNil(mailAdapter);
  ALNMailMessage *message = [[ALNMailMessage alloc] initWithFrom:@"sender@example.com"
                                                              to:@[ @"dest@example.com" ]
                                                              cc:nil
                                                             bcc:nil
                                                         subject:@"hello"
                                                        textBody:@"body"
                                                        htmlBody:@""
                                                         headers:nil
                                                        metadata:nil];
  NSString *deliveryID = [mailAdapter deliverMessage:message error:NULL];
  XCTAssertTrue([deliveryID hasPrefix:@"mail-"]);
  NSString *deliveryPath =
      [mailRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", deliveryID]];
  XCTAssertEqual((NSUInteger)0700, [self posixPermissionsAtPath:mailRoot]);
  XCTAssertEqual((NSUInteger)0600, [self posixPermissionsAtPath:deliveryPath]);

  (void)[[NSFileManager defaultManager] removeItemAtPath:attachmentRoot error:NULL];
  (void)[[NSFileManager defaultManager] removeItemAtPath:jobsRoot error:NULL];
  (void)[[NSFileManager defaultManager] removeItemAtPath:mailRoot error:NULL];
}

@end
