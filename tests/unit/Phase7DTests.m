#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNServices.h"

@interface Phase7DFaultyMailAdapter : NSObject <ALNMailAdapter>

@property(nonatomic, assign) NSUInteger failuresBeforeSuccess;
@property(nonatomic, assign) NSUInteger attemptCount;
@property(nonatomic, strong) NSMutableArray *deliveries;

- (instancetype)initWithFailuresBeforeSuccess:(NSUInteger)failuresBeforeSuccess;

@end

@implementation Phase7DFaultyMailAdapter

- (instancetype)initWithFailuresBeforeSuccess:(NSUInteger)failuresBeforeSuccess {
  self = [super init];
  if (self) {
    _failuresBeforeSuccess = failuresBeforeSuccess;
    _attemptCount = 0;
    _deliveries = [NSMutableArray array];
  }
  return self;
}

- (NSString *)adapterName {
  return @"phase7d_faulty_mail";
}

- (NSString *)deliverMessage:(ALNMailMessage *)message error:(NSError **)error {
  self.attemptCount += 1;
  if (self.attemptCount <= self.failuresBeforeSuccess) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase7D.Tests"
                                   code:7001
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"mail delivery transient failure"
                               }];
    }
    return nil;
  }

  NSString *deliveryID = [NSString stringWithFormat:@"mail-fault-%lu", (unsigned long)self.attemptCount];
  [self.deliveries addObject:@{
    @"deliveryID" : deliveryID ?: @"",
    @"message" : [message dictionaryRepresentation] ?: @{},
  }];
  return deliveryID;
}

- (NSArray *)deliveriesSnapshot {
  return [NSArray arrayWithArray:self.deliveries];
}

- (void)reset {
  [self.deliveries removeAllObjects];
  self.attemptCount = 0;
}

@end

@interface Phase7DFaultyAttachmentAdapter : NSObject <ALNAttachmentAdapter>

@property(nonatomic, assign) NSUInteger failuresBeforeSuccess;
@property(nonatomic, assign) NSUInteger attemptCount;
@property(nonatomic, strong) NSMutableDictionary *entriesByID;

- (instancetype)initWithFailuresBeforeSuccess:(NSUInteger)failuresBeforeSuccess;

@end

@implementation Phase7DFaultyAttachmentAdapter

- (instancetype)initWithFailuresBeforeSuccess:(NSUInteger)failuresBeforeSuccess {
  self = [super init];
  if (self) {
    _failuresBeforeSuccess = failuresBeforeSuccess;
    _attemptCount = 0;
    _entriesByID = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSString *)adapterName {
  return @"phase7d_faulty_attachment";
}

- (NSString *)saveAttachmentNamed:(NSString *)name
                      contentType:(NSString *)contentType
                             data:(NSData *)data
                         metadata:(NSDictionary *)metadata
                            error:(NSError **)error {
  self.attemptCount += 1;
  if (self.attemptCount <= self.failuresBeforeSuccess) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase7D.Tests"
                                   code:7002
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"attachment save transient failure"
                               }];
    }
    return nil;
  }

  NSString *attachmentID = [NSString stringWithFormat:@"att-fault-%lu", (unsigned long)self.attemptCount];
  self.entriesByID[attachmentID] = @{
    @"attachmentID" : attachmentID ?: @"",
    @"name" : name ?: @"",
    @"contentType" : contentType ?: @"application/octet-stream",
    @"sizeBytes" : @([data length]),
    @"createdAt" : @([[NSDate date] timeIntervalSince1970]),
    @"metadata" : [metadata isKindOfClass:[NSDictionary class]] ? metadata : @{},
    @"data" : data ?: [NSData data],
  };
  return attachmentID;
}

- (NSData *)attachmentDataForID:(NSString *)attachmentID
                       metadata:(NSDictionary **)metadata
                          error:(NSError **)error {
  (void)error;
  NSDictionary *entry = [self.entriesByID[attachmentID] isKindOfClass:[NSDictionary class]]
                             ? self.entriesByID[attachmentID]
                             : nil;
  if (entry == nil) {
    return nil;
  }
  if (metadata != NULL) {
    *metadata = @{
      @"attachmentID" : entry[@"attachmentID"] ?: @"",
      @"name" : entry[@"name"] ?: @"",
      @"contentType" : entry[@"contentType"] ?: @"application/octet-stream",
      @"sizeBytes" : entry[@"sizeBytes"] ?: @(0),
      @"createdAt" : entry[@"createdAt"] ?: @(0),
      @"metadata" : entry[@"metadata"] ?: @{},
    };
  }
  return [entry[@"data"] isKindOfClass:[NSData class]] ? entry[@"data"] : nil;
}

- (NSDictionary *)attachmentMetadataForID:(NSString *)attachmentID error:(NSError **)error {
  NSDictionary *metadata = nil;
  (void)[self attachmentDataForID:attachmentID metadata:&metadata error:error];
  return metadata;
}

- (BOOL)deleteAttachmentID:(NSString *)attachmentID error:(NSError **)error {
  (void)error;
  if (self.entriesByID[attachmentID] == nil) {
    return NO;
  }
  [self.entriesByID removeObjectForKey:attachmentID];
  return YES;
}

- (NSArray *)listAttachmentMetadata {
  NSMutableArray *rows = [NSMutableArray array];
  NSArray *sorted = [[self.entriesByID allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *attachmentID in sorted) {
    NSDictionary *entry = [self.entriesByID[attachmentID] isKindOfClass:[NSDictionary class]]
                               ? self.entriesByID[attachmentID]
                               : nil;
    if (entry == nil) {
      continue;
    }
    [rows addObject:@{
      @"attachmentID" : entry[@"attachmentID"] ?: @"",
      @"name" : entry[@"name"] ?: @"",
      @"contentType" : entry[@"contentType"] ?: @"application/octet-stream",
      @"sizeBytes" : entry[@"sizeBytes"] ?: @(0),
      @"createdAt" : entry[@"createdAt"] ?: @(0),
      @"metadata" : entry[@"metadata"] ?: @{},
    }];
  }
  return rows;
}

- (void)reset {
  [self.entriesByID removeAllObjects];
  self.attemptCount = 0;
}

@end

@interface Phase7DTests : XCTestCase
@end

@implementation Phase7DTests

- (NSString *)repoRoot {
  return [[NSFileManager defaultManager] currentDirectoryPath];
}

- (NSString *)absolutePathForRelativePath:(NSString *)relativePath {
  return [[self repoRoot] stringByAppendingPathComponent:(relativePath ?: @"")];
}

- (NSString *)temporaryPathWithPrefix:(NSString *)prefix {
  NSString *baseDirectory = NSTemporaryDirectory();
  if ([baseDirectory length] == 0) {
    baseDirectory = @"/tmp";
  }
  NSString *name = [NSString stringWithFormat:@"%@-%@",
                                              prefix ?: @"phase7d",
                                              [[NSUUID UUID] UUIDString] ?: @"tmp"];
  return [baseDirectory stringByAppendingPathComponent:name];
}

- (ALNMailMessage *)sampleMailMessage {
  return [[ALNMailMessage alloc] initWithFrom:@"noreply@example.test"
                                           to:@[ @"ops@example.test" ]
                                           cc:nil
                                          bcc:nil
                                      subject:@"phase7d"
                                     textBody:@"retry"
                                     htmlBody:nil
                                      headers:nil
                                     metadata:nil];
}

- (NSDictionary *)loadJSONFileAtRelativePath:(NSString *)relativePath {
  NSString *path = [self absolutePathForRelativePath:relativePath];
  NSData *data = [NSData dataWithContentsOfFile:path];
  XCTAssertNotNil(data, @"missing fixture: %@", relativePath);
  if (data == nil) {
    return @{};
  }

  NSError *jsonError = nil;
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  XCTAssertNil(jsonError, @"invalid JSON in %@", relativePath);
  XCTAssertNotNil(payload, @"invalid JSON object in %@", relativePath);
  return [payload isKindOfClass:[NSDictionary class]] ? payload : @{};
}

- (NSSet<NSString *> *)testMethodNamesForFile:(NSString *)relativePath {
  NSString *absolutePath = [self absolutePathForRelativePath:relativePath];
  NSString *source = [NSString stringWithContentsOfFile:absolutePath
                                                encoding:NSUTF8StringEncoding
                                                   error:nil];
  XCTAssertNotNil(source, @"missing test source: %@", relativePath);
  if (source == nil) {
    return [NSSet set];
  }

  NSRegularExpression *regex =
      [NSRegularExpression regularExpressionWithPattern:@"-\\s*\\(void\\)\\s*(test[A-Za-z0-9_]+)\\s*\\{"
                                                options:0
                                                  error:nil];
  XCTAssertNotNil(regex);
  if (regex == nil) {
    return [NSSet set];
  }

  NSArray<NSTextCheckingResult *> *matches =
      [regex matchesInString:source options:0 range:NSMakeRange(0, [source length])];
  NSMutableSet<NSString *> *names = [NSMutableSet setWithCapacity:[matches count]];
  for (NSTextCheckingResult *match in matches) {
    NSRange range = [match rangeAtIndex:1];
    if (range.location == NSNotFound || range.length == 0) {
      continue;
    }
    [names addObject:[source substringWithRange:range]];
  }
  return [NSSet setWithSet:names];
}

- (void)assertTestReference:(NSDictionary *)reference
                      cache:(NSMutableDictionary<NSString *, NSSet<NSString *> *> *)cache {
  NSString *file = [reference[@"file"] isKindOfClass:[NSString class]] ? reference[@"file"] : @"";
  NSString *test = [reference[@"test"] isKindOfClass:[NSString class]] ? reference[@"test"] : @"";
  XCTAssertTrue([file length] > 0);
  XCTAssertTrue([test length] > 0);
  if ([file length] == 0 || [test length] == 0) {
    return;
  }

  NSString *absolutePath = [self absolutePathForRelativePath:file];
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:absolutePath], @"missing referenced file: %@", file);
  if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath]) {
    return;
  }

  NSSet<NSString *> *methods = cache[file];
  if (methods == nil) {
    methods = [self testMethodNamesForFile:file];
    cache[file] = methods ?: [NSSet set];
  }
  XCTAssertTrue([methods containsObject:test], @"missing referenced test '%@' in %@", test, file);
}

- (void)testInMemoryJobAdapterIdempotencyKeyDeduplicatesUntilAcknowledged {
  ALNInMemoryJobAdapter *adapter = [[ALNInMemoryJobAdapter alloc] initWithAdapterName:@"phase7d_idempotent_memory"];

  NSString *firstID = [adapter enqueueJobNamed:@"phase7d.invoice"
                                       payload:@{ @"invoice" : @"42" }
                                       options:@{ @"idempotencyKey" : @"tenant-a:invoice:42" }
                                         error:NULL];
  NSString *duplicateID = [adapter enqueueJobNamed:@"phase7d.invoice"
                                           payload:@{ @"invoice" : @"42" }
                                           options:@{ @"idempotencyKey" : @"tenant-a:invoice:42" }
                                             error:NULL];
  XCTAssertEqualObjects(firstID, duplicateID);
  XCTAssertEqual((NSUInteger)1, [[adapter pendingJobsSnapshot] count]);

  ALNJobEnvelope *lease = [adapter dequeueDueJobAt:[NSDate date] error:NULL];
  XCTAssertEqualObjects(firstID, lease.jobID);
  XCTAssertTrue([adapter acknowledgeJobID:lease.jobID error:NULL]);

  NSString *afterAckID = [adapter enqueueJobNamed:@"phase7d.invoice"
                                          payload:@{ @"invoice" : @"42" }
                                          options:@{ @"idempotencyKey" : @"tenant-a:invoice:42" }
                                            error:NULL];
  XCTAssertNotNil(afterAckID);
  XCTAssertFalse([afterAckID isEqualToString:firstID]);
}

- (void)testFileJobAdapterIdempotencyKeyPersistsAcrossAdapterReload {
  NSString *rootPath = [self temporaryPathWithPrefix:@"arlen-phase7d-jobs"];
  NSString *storagePath = [rootPath stringByAppendingPathComponent:@"jobs/state.plist"];

  NSError *adapterError = nil;
  ALNFileJobAdapter *firstAdapter = [[ALNFileJobAdapter alloc] initWithStoragePath:storagePath
                                                                        adapterName:@"phase7d_file_jobs"
                                                                              error:&adapterError];
  XCTAssertNotNil(firstAdapter);
  XCTAssertNil(adapterError);
  if (firstAdapter == nil) {
    return;
  }

  NSString *firstID = [firstAdapter enqueueJobNamed:@"phase7d.invoice"
                                            payload:@{ @"invoice" : @"99" }
                                            options:@{ @"idempotencyKey" : @"tenant-a:invoice:99" }
                                              error:NULL];
  NSString *duplicateID = [firstAdapter enqueueJobNamed:@"phase7d.invoice"
                                                payload:@{ @"invoice" : @"99" }
                                                options:@{ @"idempotencyKey" : @"tenant-a:invoice:99" }
                                                  error:NULL];
  XCTAssertEqualObjects(firstID, duplicateID);

  ALNFileJobAdapter *reloadedAdapter = [[ALNFileJobAdapter alloc] initWithStoragePath:storagePath
                                                                           adapterName:@"phase7d_file_jobs_reloaded"
                                                                                 error:&adapterError];
  XCTAssertNotNil(reloadedAdapter);
  XCTAssertNil(adapterError);
  if (reloadedAdapter == nil) {
    return;
  }

  NSString *duplicateAfterReloadID = [reloadedAdapter enqueueJobNamed:@"phase7d.invoice"
                                                               payload:@{ @"invoice" : @"99" }
                                                               options:@{ @"idempotencyKey" : @"tenant-a:invoice:99" }
                                                                 error:NULL];
  XCTAssertEqualObjects(firstID, duplicateAfterReloadID);

  ALNJobEnvelope *lease = [reloadedAdapter dequeueDueJobAt:[NSDate date] error:NULL];
  XCTAssertEqualObjects(firstID, lease.jobID);
  XCTAssertTrue([reloadedAdapter acknowledgeJobID:lease.jobID error:NULL]);

  NSString *afterAckID = [reloadedAdapter enqueueJobNamed:@"phase7d.invoice"
                                                  payload:@{ @"invoice" : @"99" }
                                                  options:@{ @"idempotencyKey" : @"tenant-a:invoice:99" }
                                                    error:NULL];
  XCTAssertNotNil(afterAckID);
  XCTAssertFalse([afterAckID isEqualToString:firstID]);

  (void)[[NSFileManager defaultManager] removeItemAtPath:rootPath error:NULL];
}

- (void)testCacheConformanceSuiteCoversPersistenceAndNilRemovalSemantics {
  ALNInMemoryCacheAdapter *adapter = [[ALNInMemoryCacheAdapter alloc] initWithAdapterName:@"phase7d_cache"];
  NSError *suiteError = nil;
  BOOL ok = ALNRunCacheAdapterConformanceSuite(adapter, &suiteError);
  XCTAssertTrue(ok);
  XCTAssertNil(suiteError);
}

- (void)testRetryingMailAdapterRetriesToSuccess {
  Phase7DFaultyMailAdapter *base = [[Phase7DFaultyMailAdapter alloc] initWithFailuresBeforeSuccess:2];
  ALNRetryingMailAdapter *retrying = [[ALNRetryingMailAdapter alloc] initWithBaseAdapter:base];
  retrying.maxAttempts = 3;
  retrying.retryDelaySeconds = 0;

  NSError *error = nil;
  NSString *deliveryID = [retrying deliverMessage:[self sampleMailMessage] error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"mail-fault-3", deliveryID);
  XCTAssertEqual((NSUInteger)3, base.attemptCount);
  XCTAssertEqual((NSUInteger)1, [[retrying deliveriesSnapshot] count]);
}

- (void)testRetryingMailAdapterReturnsDeterministicErrorWhenExhausted {
  Phase7DFaultyMailAdapter *base = [[Phase7DFaultyMailAdapter alloc] initWithFailuresBeforeSuccess:8];
  ALNRetryingMailAdapter *retrying = [[ALNRetryingMailAdapter alloc] initWithBaseAdapter:base];
  retrying.maxAttempts = 3;
  retrying.retryDelaySeconds = 0;

  NSError *error = nil;
  NSString *deliveryID = [retrying deliverMessage:[self sampleMailMessage] error:&error];
  XCTAssertNil(deliveryID);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNServiceErrorDomain, error.domain);
  XCTAssertEqual((NSInteger)4311, error.code);
  XCTAssertEqualObjects(@3, error.userInfo[@"attempt_count"]);
  XCTAssertEqual((NSUInteger)3, base.attemptCount);
}

- (void)testRetryingAttachmentAdapterRetriesToSuccess {
  Phase7DFaultyAttachmentAdapter *base =
      [[Phase7DFaultyAttachmentAdapter alloc] initWithFailuresBeforeSuccess:1];
  ALNRetryingAttachmentAdapter *retrying =
      [[ALNRetryingAttachmentAdapter alloc] initWithBaseAdapter:base];
  retrying.maxAttempts = 2;
  retrying.retryDelaySeconds = 0;

  NSError *error = nil;
  NSData *data = [@"phase7d" dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  NSString *attachmentID = [retrying saveAttachmentNamed:@"phase7d.txt"
                                             contentType:@"text/plain"
                                                    data:data
                                                metadata:@{ @"scope" : @"test" }
                                                   error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"att-fault-2", attachmentID);
  XCTAssertEqual((NSUInteger)2, base.attemptCount);

  NSDictionary *metadata = nil;
  NSData *readBack = [retrying attachmentDataForID:attachmentID metadata:&metadata error:NULL];
  XCTAssertEqualObjects(data, readBack);
  XCTAssertEqualObjects(@"phase7d.txt", metadata[@"name"]);
}

- (void)testRetryingAttachmentAdapterReturnsDeterministicErrorWhenExhausted {
  Phase7DFaultyAttachmentAdapter *base =
      [[Phase7DFaultyAttachmentAdapter alloc] initWithFailuresBeforeSuccess:4];
  ALNRetryingAttachmentAdapter *retrying =
      [[ALNRetryingAttachmentAdapter alloc] initWithBaseAdapter:base];
  retrying.maxAttempts = 3;
  retrying.retryDelaySeconds = 0;

  NSError *error = nil;
  NSString *attachmentID = [retrying saveAttachmentNamed:@"phase7d.txt"
                                             contentType:@"text/plain"
                                                    data:[@"phase7d" dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]
                                                metadata:nil
                                                   error:&error];
  XCTAssertNil(attachmentID);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNServiceErrorDomain, error.domain);
  XCTAssertEqual((NSInteger)564, error.code);
  XCTAssertEqualObjects(@3, error.userInfo[@"attempt_count"]);
  XCTAssertEqual((NSUInteger)3, base.attemptCount);
}

- (void)testServiceDurabilityContractFixtureSchemaAndTestCoverage {
  NSDictionary *fixture =
      [self loadJSONFileAtRelativePath:@"tests/fixtures/phase7d/service_durability_contracts.json"];
  XCTAssertEqualObjects(@"phase7d-service-durability-contracts-v1", fixture[@"version"]);

  NSArray<NSDictionary *> *contracts =
      [fixture[@"contracts"] isKindOfClass:[NSArray class]] ? fixture[@"contracts"] : @[];
  XCTAssertTrue([contracts count] > 0);

  NSSet *allowedKinds = [NSSet setWithArray:@[ @"unit", @"integration", @"long_run" ]];
  NSMutableSet<NSString *> *ids = [NSMutableSet setWithCapacity:[contracts count]];
  NSMutableDictionary<NSString *, NSSet<NSString *> *> *methodCache = [NSMutableDictionary dictionary];

  for (NSDictionary *contract in contracts) {
    NSString *contractID = [contract[@"id"] isKindOfClass:[NSString class]] ? contract[@"id"] : @"";
    NSString *claim = [contract[@"claim"] isKindOfClass:[NSString class]] ? contract[@"claim"] : @"";
    XCTAssertTrue([contractID length] > 0);
    XCTAssertTrue([claim length] > 0);
    XCTAssertFalse([ids containsObject:contractID], @"duplicate contract id: %@", contractID);
    [ids addObject:contractID];

    NSArray<NSString *> *sourceDocs =
        [contract[@"source_docs"] isKindOfClass:[NSArray class]] ? contract[@"source_docs"] : @[];
    XCTAssertTrue([sourceDocs count] > 0);
    for (id rawDocPath in sourceDocs) {
      NSString *docPath = [rawDocPath isKindOfClass:[NSString class]] ? rawDocPath : @"";
      XCTAssertTrue([docPath length] > 0);
      if ([docPath length] == 0) {
        continue;
      }
      NSString *absoluteDocPath = [self absolutePathForRelativePath:docPath];
      XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:absoluteDocPath], @"missing source doc: %@", docPath);
    }

    NSArray<NSDictionary *> *verification =
        [contract[@"verification"] isKindOfClass:[NSArray class]] ? contract[@"verification"] : @[];
    XCTAssertTrue([verification count] > 0, @"contract '%@' has no verification", contractID);
    for (NSDictionary *reference in verification) {
      NSString *kind = [reference[@"kind"] isKindOfClass:[NSString class]] ? reference[@"kind"] : @"";
      XCTAssertTrue([allowedKinds containsObject:kind], @"unsupported verification kind: %@", kind);
      [self assertTestReference:reference cache:methodCache];
    }
  }
}

@end
