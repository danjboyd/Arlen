#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

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

@end
