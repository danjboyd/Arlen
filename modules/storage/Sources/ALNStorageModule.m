#import "ALNStorageModule.h"

#import "../..//admin-ui/Sources/ALNAdminUIModule.h"
#import "../..//auth/Sources/ALNAuthModule.h"

#import "ALNDataCompat.h"
#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNSecurityPrimitives.h"

NSString *const ALNStorageModuleErrorDomain = @"Arlen.Modules.Storage.Error";

static NSString *const ALNStorageVariantJobIdentifier = @"storage.generate_variant";
static NSString *const ALNStorageCleanupJobIdentifier = @"storage.cleanup";
static NSUInteger const ALNStorageActivityLimit = 30;

static NSString *SMTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *SMLowerTrimmedString(id value) {
  return [[SMTrimmedString(value) lowercaseString] copy];
}

static NSDictionary *SMNormalizeDictionary(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static NSArray *SMNormalizeArray(id value) {
  return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static id SMPropertyListValue(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"";
  }
  if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
      [value isKindOfClass:[NSData class]] || [value isKindOfClass:[NSDate class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *items = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
      [items addObject:SMPropertyListValue(entry)];
    }
    return items;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (id rawKey in [(NSDictionary *)value allKeys]) {
      NSString *key = SMTrimmedString(rawKey);
      if ([key length] == 0) {
        continue;
      }
      dictionary[key] = SMPropertyListValue([(NSDictionary *)value objectForKey:rawKey]);
    }
    return dictionary;
  }
  return [value description] ?: @"";
}

static NSString *SMResolvedPersistencePath(ALNApplication *application, NSDictionary *moduleConfig) {
  NSDictionary *persistence = [moduleConfig[@"persistence"] isKindOfClass:[NSDictionary class]]
                                  ? moduleConfig[@"persistence"]
                                  : @{};
  BOOL enabled = ![persistence[@"enabled"] respondsToSelector:@selector(boolValue)] ||
                 [persistence[@"enabled"] boolValue];
  if (!enabled) {
    return @"";
  }
  NSString *configured = SMTrimmedString(persistence[@"path"]);
  if ([configured length] > 0) {
    if ([configured hasPrefix:@"/"]) {
      return configured;
    }
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath] ?: NSTemporaryDirectory();
    return [cwd stringByAppendingPathComponent:configured];
  }
  NSString *environment = SMLowerTrimmedString(application.environment);
  if ([environment isEqualToString:@"test"]) {
    return @"";
  }
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath] ?: NSTemporaryDirectory();
  return [cwd stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"var/module_state/storage-%@.plist",
                                              ([environment length] > 0) ? environment : @"development"]];
}

static NSDictionary *SMReadPropertyListAtPath(NSString *path, NSError **error) {
  NSString *statePath = SMTrimmedString(path);
  if ([statePath length] == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:statePath]) {
    return nil;
  }
  NSData *data = ALNDataReadFromFile(statePath, 0, error);
  if (data == nil) {
    return nil;
  }
  NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
  id object = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:error];
  return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static BOOL SMWritePropertyListAtPath(NSString *path, NSDictionary *payload, NSError **error) {
  NSString *statePath = SMTrimmedString(path);
  if ([statePath length] == 0) {
    return YES;
  }
  NSString *parent = [statePath stringByDeletingLastPathComponent];
  if ([parent length] > 0 &&
      ![[NSFileManager defaultManager] createDirectoryAtPath:parent
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:error]) {
    return NO;
  }
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:SMPropertyListValue(payload)
                                                            format:NSPropertyListBinaryFormat_v1_0
                                                           options:0
                                                             error:error];
  if (data == nil) {
    return NO;
  }
  return [data writeToFile:statePath options:NSDataWritingAtomic error:error];
}

static NSError *SMError(ALNStorageModuleErrorCode code, NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"storage module error";
  return [NSError errorWithDomain:ALNStorageModuleErrorDomain code:code userInfo:userInfo];
}

static NSString *SMPathJoin(NSString *prefix, NSString *suffix) {
  NSString *cleanPrefix = SMTrimmedString(prefix);
  if ([cleanPrefix length] == 0) {
    cleanPrefix = @"/storage";
  }
  if (![cleanPrefix hasPrefix:@"/"]) {
    cleanPrefix = [@"/" stringByAppendingString:cleanPrefix];
  }
  while ([cleanPrefix hasSuffix:@"/"] && [cleanPrefix length] > 1) {
    cleanPrefix = [cleanPrefix substringToIndex:([cleanPrefix length] - 1)];
  }
  NSString *cleanSuffix = SMTrimmedString(suffix);
  while ([cleanSuffix hasPrefix:@"/"]) {
    cleanSuffix = [cleanSuffix substringFromIndex:1];
  }
  if ([cleanSuffix length] == 0) {
    return cleanPrefix;
  }
  return [NSString stringWithFormat:@"%@/%@", cleanPrefix, cleanSuffix];
}

static NSString *SMConfiguredPath(NSDictionary *moduleConfig, NSString *key, NSString *defaultSuffix) {
  NSDictionary *paths = [moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"paths"] : @{};
  NSString *prefix = SMTrimmedString(paths[@"prefix"]);
  if ([prefix length] == 0) {
    prefix = @"/storage";
  }
  NSString *override = SMTrimmedString(paths[key]);
  if ([override hasPrefix:@"/"]) {
    return override;
  }
  if ([override length] > 0) {
    return SMPathJoin(prefix, override);
  }
  return SMPathJoin(prefix, defaultSuffix);
}

static NSString *SMQueryDecodeComponent(NSString *component) {
  NSString *withSpaces = [[component ?: @"" stringByReplacingOccurrencesOfString:@"+" withString:@" "]
      stringByRemovingPercentEncoding];
  return withSpaces ?: @"";
}

static NSDictionary *SMJSONParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  id object = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

static NSDictionary *SMFormParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  NSString *raw = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
  if ([raw length] == 0) {
    return @{};
  }
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  for (NSString *pair in [raw componentsSeparatedByString:@"&"]) {
    if ([pair length] == 0) {
      continue;
    }
    NSRange separator = [pair rangeOfString:@"="];
    NSString *name = (separator.location == NSNotFound) ? pair : [pair substringToIndex:separator.location];
    NSString *value = (separator.location == NSNotFound) ? @"" : [pair substringFromIndex:(separator.location + 1)];
    NSString *decodedName = SMQueryDecodeComponent(name);
    if ([decodedName length] == 0) {
      continue;
    }
    parameters[decodedName] = SMQueryDecodeComponent(value);
  }
  return parameters;
}

static NSString *SMPercentEncodedQueryComponent(NSString *value) {
  NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
  [allowed removeCharactersInString:@"&=+"];
  return [SMTrimmedString(value) stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static BOOL SMContentTypeMatches(NSString *candidate, NSString *allowedPattern) {
  NSString *type = SMLowerTrimmedString(candidate);
  NSString *pattern = SMLowerTrimmedString(allowedPattern);
  if ([pattern length] == 0 || [pattern isEqualToString:@"*/*"]) {
    return YES;
  }
  if ([pattern hasSuffix:@"/*"]) {
    NSString *prefix = [pattern substringToIndex:([pattern length] - 1)];
    return [type hasPrefix:prefix];
  }
  return [type isEqualToString:pattern];
}

static NSArray<NSString *> *SMNormalizedContentTypes(id rawValue) {
  NSMutableArray<NSString *> *types = [NSMutableArray array];
  for (id entry in SMNormalizeArray(rawValue)) {
    NSString *type = SMLowerTrimmedString(entry);
    if ([type length] == 0 || [types containsObject:type]) {
      continue;
    }
    [types addObject:type];
  }
  if ([types count] == 0) {
    [types addObject:@"*/*"];
  }
  return [NSArray arrayWithArray:types];
}

static NSArray<NSDictionary *> *SMNormalizedVariantDefinitions(id rawVariants) {
  NSMutableArray<NSDictionary *> *variants = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  NSArray *entries = [rawVariants isKindOfClass:[NSArray class]] ? rawVariants : @[];
  for (id entry in entries) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *identifier = SMLowerTrimmedString(entry[@"identifier"]);
    if ([identifier length] == 0 || [seen containsObject:identifier]) {
      continue;
    }
    [seen addObject:identifier];
    [variants addObject:@{
      @"identifier" : identifier,
      @"label" : ([SMTrimmedString(entry[@"label"]) length] > 0) ? SMTrimmedString(entry[@"label"]) : [identifier capitalizedString],
      @"contentType" : ([SMLowerTrimmedString(entry[@"contentType"]) length] > 0) ? SMLowerTrimmedString(entry[@"contentType"]) : @"application/octet-stream",
      @"strategy" : ([SMLowerTrimmedString(entry[@"strategy"]) length] > 0) ? SMLowerTrimmedString(entry[@"strategy"]) : @"copy",
      @"async" : @([entry[@"async"] respondsToSelector:@selector(boolValue)] ? [entry[@"async"] boolValue] : YES),
    }];
  }
  return [variants sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    return [SMTrimmedString(left[@"identifier"]) compare:SMTrimmedString(right[@"identifier"])];
  }];
}

static NSDictionary *SMTokenPayloadDecode(NSString *token, NSData *keyData, NSError **error) {
  NSArray<NSString *> *parts = [SMTrimmedString(token) componentsSeparatedByString:@"."];
  if ([parts count] != 2) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token format is invalid", nil);
    }
    return nil;
  }
  NSString *payloadPart = parts[0] ?: @"";
  NSString *signaturePart = parts[1] ?: @"";
  NSData *expectedDigest = ALNHMACSHA256([payloadPart dataUsingEncoding:NSUTF8StringEncoding], keyData ?: [NSData data]);
  NSString *expectedSignature = ALNBase64URLStringFromData(expectedDigest) ?: @"";
  NSData *expectedData = [expectedSignature dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  NSData *actualData = [signaturePart dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  if (!ALNConstantTimeDataEquals(expectedData, actualData)) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token signature was rejected", nil);
    }
    return nil;
  }
  NSData *payloadData = ALNDataFromBase64URLString(payloadPart);
  if (payloadData == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token payload could not be decoded", nil);
    }
    return nil;
  }
  id object = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:NULL];
  if (![object isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token payload is invalid", nil);
    }
    return nil;
  }
  return object;
}

static NSString *SMCreateSignedToken(NSDictionary *payload, NSData *keyData) {
  NSData *payloadData = [NSJSONSerialization dataWithJSONObject:(payload ?: @{}) options:0 error:NULL];
  NSString *payloadPart = ALNBase64URLStringFromData(payloadData ?: [NSData data]) ?: @"";
  NSData *digest = ALNHMACSHA256([payloadPart dataUsingEncoding:NSUTF8StringEncoding], keyData ?: [NSData data]);
  NSString *signaturePart = ALNBase64URLStringFromData(digest ?: [NSData data]) ?: @"";
  return [NSString stringWithFormat:@"%@.%@", payloadPart, signaturePart];
}

static NSDictionary *SMAnalyzeObjectData(NSString *name,
                                         NSString *contentType,
                                         NSData *data,
                                         NSDictionary *metadata,
                                         NSArray<NSDictionary *> *variants) {
  NSString *normalizedName = SMTrimmedString(name);
  NSString *normalizedContentType = ([SMLowerTrimmedString(contentType) length] > 0)
                                        ? SMLowerTrimmedString(contentType)
                                        : @"application/octet-stream";
  NSString *extension = [[[normalizedName pathExtension] lowercaseString] copy] ?: @"";
  BOOL previewable = [normalizedContentType hasPrefix:@"image/"] || [normalizedContentType isEqualToString:@"application/pdf"];
  NSMutableDictionary *analysis = [@{
    @"sizeBytes" : @([data length]),
    @"checksumSHA256" : ALNLowercaseHexStringFromData(ALNSHA256(data ?: [NSData data])) ?: @"",
    @"fileExtension" : extension ?: @"",
    @"previewable" : @(previewable),
    @"variantCapable" : @([(variants ?: @[]) count] > 0),
    @"contentType" : normalizedContentType,
  } mutableCopy];
  NSNumber *width = [metadata[@"width"] respondsToSelector:@selector(integerValue)] ? metadata[@"width"] : nil;
  NSNumber *height = [metadata[@"height"] respondsToSelector:@selector(integerValue)] ? metadata[@"height"] : nil;
  if (width != nil || height != nil) {
    analysis[@"dimensions"] = @{
      @"width" : width ?: @0,
      @"height" : height ?: @0,
    };
  }
  return [NSDictionary dictionaryWithDictionary:analysis];
}

static NSDictionary *SMAttachmentAdapterCapabilities(id<ALNAttachmentAdapter> adapter) {
  NSDictionary *capabilities =
      [adapter respondsToSelector:@selector(attachmentAdapterCapabilities)]
          ? [adapter attachmentAdapterCapabilities]
          : nil;
  if (![capabilities isKindOfClass:[NSDictionary class]]) {
    capabilities = @{};
  }
  NSMutableDictionary *normalized = [NSMutableDictionary dictionaryWithDictionary:@{
    @"temporaryDownloadURL" : @NO,
    @"readOnly" : @NO,
    @"scoped" : @NO,
    @"mirroring" : @NO,
  }];
  [normalized addEntriesFromDictionary:capabilities];
  return [NSDictionary dictionaryWithDictionary:normalized];
}

@interface ALNStorageModuleRuntime (JobSupport)

- (nullable NSDictionary *)runMaintenanceAt:(NSDate *)timestamp
                                      error:(NSError **)error;
- (nullable NSDictionary *)processVariantJobPayload:(NSDictionary *)payload
                                         jobContext:(NSDictionary *)jobContext
                                              error:(NSError **)error;

@end

@interface ALNStorageVariantJob : NSObject <ALNJobsJobDefinition>
@end

@implementation ALNStorageVariantJob

- (NSString *)jobsModuleJobIdentifier {
  return ALNStorageVariantJobIdentifier;
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Storage variant generation",
    @"description" : @"Generates first-party storage variants",
    @"queue" : @"default",
    @"maxAttempts" : @3,
    @"allowManualEnqueue" : @NO,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([SMTrimmedString(payload[@"objectID"]) length] == 0 || [SMTrimmedString(payload[@"variant"]) length] == 0) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed,
                       @"variant job requires objectID and variant",
                       nil);
    }
    return NO;
  }
  return YES;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  return ([[ALNStorageModuleRuntime sharedRuntime] processVariantJobPayload:payload
                                                                  jobContext:context
                                                                       error:error] != nil);
}

@end

@interface ALNStorageCleanupJob : NSObject <ALNJobsJobDefinition>
@end

@implementation ALNStorageCleanupJob

- (NSString *)jobsModuleJobIdentifier {
  return ALNStorageCleanupJobIdentifier;
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Storage cleanup",
    @"description" : @"Prunes expired upload sessions and retention-expired objects",
    @"queue" : @"maintenance",
    @"maxAttempts" : @2,
    @"allowManualEnqueue" : @NO,
    @"tags" : @[ @"storage", @"maintenance" ],
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  (void)payload;
  (void)error;
  return YES;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  NSDate *now = [context[@"scheduledAt"] isKindOfClass:[NSDate class]] ? context[@"scheduledAt"] : [NSDate date];
  id runtime = [ALNStorageModuleRuntime sharedRuntime];
  return ([runtime runMaintenanceAt:now error:error] != nil);
}

@end

@interface ALNStorageModuleRuntime ()

@property(nonatomic, strong, readwrite) ALNApplication *application;
@property(nonatomic, strong, readwrite) id<ALNAttachmentAdapter> attachmentAdapter;
@property(nonatomic, copy, readwrite) NSString *prefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, assign, readwrite) NSTimeInterval defaultUploadSessionTTLSeconds;
@property(nonatomic, assign, readwrite) NSTimeInterval defaultDownloadTokenTTLSeconds;
@property(nonatomic, assign) NSTimeInterval defaultCleanupIntervalSeconds;
@property(nonatomic, copy) NSDictionary *moduleConfig;
@property(nonatomic, strong) NSData *signingKeyData;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id<ALNStorageCollectionDefinition>> *collectionDefinitionsByIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *collectionMetadataByIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *objectIDsByCollection;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *objectsByIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *uploadSessionsByIdentifier;
@property(nonatomic, assign) NSUInteger nextSequence;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *activityLog;
@property(nonatomic, assign) BOOL persistenceEnabled;
@property(nonatomic, copy) NSString *statePath;

- (nullable NSDictionary *)normalizedCollectionMetadataForDefinition:(id<ALNStorageCollectionDefinition>)definition
                                                               error:(NSError **)error;
- (BOOL)registerCollectionDefinition:(id<ALNStorageCollectionDefinition>)definition
                              source:(NSString *)source
                               error:(NSError **)error;
- (nullable NSDictionary *)internalObjectRecordForIdentifier:(NSString *)objectID;
- (NSDictionary *)publicObjectRecordFromInternalRecord:(NSDictionary *)record;
- (NSArray<NSDictionary *> *)publicObjectRecordsFromIDs:(NSArray<NSString *> *)objectIDs;
- (nullable NSDictionary *)validatedTokenPayload:(NSString *)token
                                         purpose:(NSString *)purpose
                                   expectedField:(NSString *)expectedField
                                   expectedValue:(NSString *)expectedValue
                                           error:(NSError **)error;
- (BOOL)loadPersistedStateWithError:(NSError **)error;
- (BOOL)persistStateWithError:(NSError **)error;
- (void)recordActivityNamed:(NSString *)event details:(NSDictionary *)details;
- (NSUInteger)pruneExpiredUploadSessionsAt:(NSDate *)timestamp
                            recordActivity:(BOOL)recordActivity;
- (BOOL)deleteObjectIdentifier:(NSString *)objectID
                        reason:(NSString *)reason
                         error:(NSError **)error;
- (nullable NSDictionary *)runMaintenanceAt:(NSDate *)timestamp
                                       error:(NSError **)error;
- (nullable NSDictionary *)processVariantJobPayload:(NSDictionary *)payload
                                         jobContext:(NSDictionary *)jobContext
                                              error:(NSError **)error;

@end

@implementation ALNStorageModuleRuntime

+ (instancetype)sharedRuntime {
  static ALNStorageModuleRuntime *runtime = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    runtime = [[ALNStorageModuleRuntime alloc] init];
  });
  return runtime;
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _prefix = @"/storage";
    _apiPrefix = @"/storage/api";
    _defaultUploadSessionTTLSeconds = 900.0;
    _defaultDownloadTokenTTLSeconds = 300.0;
    _defaultCleanupIntervalSeconds = 300.0;
    _moduleConfig = @{};
    _signingKeyData = [@"storage-module-signing-secret" dataUsingEncoding:NSUTF8StringEncoding];
    _lock = [[NSLock alloc] init];
    _collectionDefinitionsByIdentifier = [NSMutableDictionary dictionary];
    _collectionMetadataByIdentifier = [NSMutableDictionary dictionary];
    _objectIDsByCollection = [NSMutableDictionary dictionary];
    _objectsByIdentifier = [NSMutableDictionary dictionary];
    _uploadSessionsByIdentifier = [NSMutableDictionary dictionary];
    _nextSequence = 0;
    _activityLog = [NSMutableArray array];
    _persistenceEnabled = NO;
    _statePath = @"";
  }
  return self;
}

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError **)error {
  if (application == nil || application.attachmentAdapter == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                       @"storage module requires an application with an attachment adapter",
                       nil);
    }
    return NO;
  }

  ALNJobsModuleRuntime *jobsRuntime = [ALNJobsModuleRuntime sharedRuntime];
  if (jobsRuntime.application == nil || jobsRuntime.jobsAdapter == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                       @"storage module requires the jobs module to be configured first",
                       nil);
    }
    return NO;
  }

  NSDictionary *moduleConfig =
      [application.config[@"storageModule"] isKindOfClass:[NSDictionary class]] ? application.config[@"storageModule"] : @{};
  NSString *signingSecret = SMTrimmedString(moduleConfig[@"signingSecret"]);

  [self.lock lock];
  self.application = application;
  self.attachmentAdapter = application.attachmentAdapter;
  self.moduleConfig = moduleConfig;
  self.prefix = SMConfiguredPath(moduleConfig, @"prefix", @"");
  self.apiPrefix = SMConfiguredPath(moduleConfig, @"apiPrefix", @"api");
  self.defaultUploadSessionTTLSeconds =
      [moduleConfig[@"uploadSessionTTLSeconds"] respondsToSelector:@selector(doubleValue)]
          ? [moduleConfig[@"uploadSessionTTLSeconds"] doubleValue]
          : 900.0;
  if (self.defaultUploadSessionTTLSeconds <= 0.0) {
    self.defaultUploadSessionTTLSeconds = 900.0;
  }
  self.defaultDownloadTokenTTLSeconds =
      [moduleConfig[@"downloadTokenTTLSeconds"] respondsToSelector:@selector(doubleValue)]
          ? [moduleConfig[@"downloadTokenTTLSeconds"] doubleValue]
          : 300.0;
  if (self.defaultDownloadTokenTTLSeconds <= 0.0) {
    self.defaultDownloadTokenTTLSeconds = 300.0;
  }
  NSDictionary *cleanupConfig =
      [moduleConfig[@"cleanup"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"cleanup"] : @{};
  self.defaultCleanupIntervalSeconds =
      [cleanupConfig[@"intervalSeconds"] respondsToSelector:@selector(doubleValue)]
          ? [cleanupConfig[@"intervalSeconds"] doubleValue]
          : 300.0;
  if (self.defaultCleanupIntervalSeconds <= 0.0) {
    self.defaultCleanupIntervalSeconds = 300.0;
  }
  self.signingKeyData = [[signingSecret length] > 0 ? signingSecret : @"storage-module-signing-secret"
      dataUsingEncoding:NSUTF8StringEncoding];
  [self.collectionDefinitionsByIdentifier removeAllObjects];
  [self.collectionMetadataByIdentifier removeAllObjects];
  [self.objectIDsByCollection removeAllObjects];
  [self.objectsByIdentifier removeAllObjects];
  [self.uploadSessionsByIdentifier removeAllObjects];
  [self.activityLog removeAllObjects];
  self.nextSequence = 0;
  self.statePath = SMResolvedPersistencePath(application, moduleConfig);
  self.persistenceEnabled = ([self.statePath length] > 0);
  [self.lock unlock];

  if (![self loadPersistedStateWithError:error]) {
    return NO;
  }

  if (![jobsRuntime registerSystemJobDefinition:[[ALNStorageVariantJob alloc] init] error:error]) {
    return NO;
  }
  if (![jobsRuntime registerSystemJobDefinition:[[ALNStorageCleanupJob alloc] init] error:error]) {
    return NO;
  }
  if (![jobsRuntime registerSystemScheduleDefinition:@{
        @"identifier" : @"storage.cleanup.default",
        @"job" : ALNStorageCleanupJobIdentifier,
        @"intervalSeconds" : @(self.defaultCleanupIntervalSeconds),
        @"queue" : @"maintenance",
      }
                                        error:error]) {
    return NO;
  }

  NSArray *providerClasses =
      [moduleConfig[@"collectionProviderClasses"] isKindOfClass:[NSArray class]]
          ? moduleConfig[@"collectionProviderClasses"]
          : ([moduleConfig[@"collections"] isKindOfClass:[NSDictionary class]] &&
                     [moduleConfig[@"collections"][@"classes"] isKindOfClass:[NSArray class]]
                 ? moduleConfig[@"collections"][@"classes"]
                 : @[]);
  for (id rawClassName in providerClasses) {
    NSString *className = SMTrimmedString(rawClassName);
    if ([className length] == 0) {
      continue;
    }
    Class klass = NSClassFromString(className);
    id provider = (klass != Nil) ? [[klass alloc] init] : nil;
    if (provider == nil || ![provider conformsToProtocol:@protocol(ALNStorageCollectionProvider)]) {
      if (error != NULL) {
        *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"storage collection provider %@ is invalid", className],
                         @{ @"class" : className ?: @"" });
      }
      return NO;
    }
    NSArray *definitions = [(id<ALNStorageCollectionProvider>)provider storageModuleCollectionsForRuntime:self error:error];
    if (definitions == nil && error != NULL && *error != NULL) {
      return NO;
    }
    for (id definition in definitions ?: @[]) {
      if (![self registerCollectionDefinition:definition source:className error:error]) {
        return NO;
      }
    }
  }
  [self.lock lock];
  NSSet *knownCollections = [NSSet setWithArray:[self.collectionMetadataByIdentifier allKeys]];
  NSArray *storedObjectIDs = [NSArray arrayWithArray:[self.objectsByIdentifier allKeys]];
  for (NSString *objectID in storedObjectIDs) {
    NSDictionary *record = [self.objectsByIdentifier[objectID] isKindOfClass:[NSDictionary class]]
                               ? self.objectsByIdentifier[objectID]
                               : nil;
    if (record == nil || ![knownCollections containsObject:SMLowerTrimmedString(record[@"collection"])]) {
      [self.objectsByIdentifier removeObjectForKey:objectID];
    }
  }
  NSArray *sessionIDs = [NSArray arrayWithArray:[self.uploadSessionsByIdentifier allKeys]];
  for (NSString *sessionID in sessionIDs) {
    NSDictionary *session = [self.uploadSessionsByIdentifier[sessionID] isKindOfClass:[NSDictionary class]]
                                ? self.uploadSessionsByIdentifier[sessionID]
                                : nil;
    if (session == nil || ![knownCollections containsObject:SMLowerTrimmedString(session[@"collection"])]) {
      [self.uploadSessionsByIdentifier removeObjectForKey:sessionID];
    }
  }
  for (NSString *collection in [NSArray arrayWithArray:[self.objectIDsByCollection allKeys]]) {
    if (![knownCollections containsObject:collection]) {
      [self.objectIDsByCollection removeObjectForKey:collection];
    }
  }
  [self.lock unlock];
  [self pruneExpiredUploadSessionsAt:[NSDate date] recordActivity:YES];
  if (![self persistStateWithError:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)loadPersistedStateWithError:(NSError **)error {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return YES;
  }
  NSError *readError = nil;
  NSDictionary *state = SMReadPropertyListAtPath(self.statePath, &readError);
  if (state == nil) {
    if (readError != nil && error != NULL) {
      *error = readError;
      return NO;
    }
    return YES;
  }
  [self.lock lock];
  NSDictionary *objects = [state[@"objectsByIdentifier"] isKindOfClass:[NSDictionary class]] ? state[@"objectsByIdentifier"] : @{};
  NSDictionary *sessions = [state[@"uploadSessionsByIdentifier"] isKindOfClass:[NSDictionary class]] ? state[@"uploadSessionsByIdentifier"] : @{};
  NSDictionary *objectIDsByCollection = [state[@"objectIDsByCollection"] isKindOfClass:[NSDictionary class]] ? state[@"objectIDsByCollection"] : @{};
  for (NSString *collection in objectIDsByCollection) {
    NSArray *objectIDs = [objectIDsByCollection[collection] isKindOfClass:[NSArray class]] ? objectIDsByCollection[collection] : @[];
    self.objectIDsByCollection[collection] = [NSMutableArray arrayWithArray:objectIDs];
  }
  [self.objectsByIdentifier addEntriesFromDictionary:objects];
  [self.uploadSessionsByIdentifier addEntriesFromDictionary:sessions];
  NSArray *activity = [state[@"activityLog"] isKindOfClass:[NSArray class]] ? state[@"activityLog"] : @[];
  [self.activityLog addObjectsFromArray:activity];
  self.nextSequence = [state[@"nextSequence"] respondsToSelector:@selector(unsignedIntegerValue)]
                          ? [state[@"nextSequence"] unsignedIntegerValue]
                          : self.nextSequence;
  [self.lock unlock];
  return YES;
}

- (BOOL)persistStateWithError:(NSError **)error {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return YES;
  }
  NSDictionary *payload = nil;
  [self.lock lock];
  NSMutableDictionary *objectIDsByCollection = [NSMutableDictionary dictionary];
  for (NSString *collection in self.objectIDsByCollection) {
    objectIDsByCollection[collection] = [[NSArray alloc] initWithArray:self.objectIDsByCollection[collection] ?: @[] copyItems:YES] ?: @[];
  }
  payload = @{
    @"version" : @1,
    @"nextSequence" : @(self.nextSequence),
    @"objectIDsByCollection" : objectIDsByCollection,
    @"objectsByIdentifier" : [NSDictionary dictionaryWithDictionary:self.objectsByIdentifier ?: @{}],
    @"uploadSessionsByIdentifier" : [NSDictionary dictionaryWithDictionary:self.uploadSessionsByIdentifier ?: @{}],
    @"activityLog" : [[NSArray alloc] initWithArray:self.activityLog copyItems:YES] ?: @[],
  };
  [self.lock unlock];
  return SMWritePropertyListAtPath(self.statePath, payload, error);
}

- (void)recordActivityNamed:(NSString *)event details:(NSDictionary *)details {
  [self.lock lock];
  [self.activityLog addObject:@{
    @"event" : SMLowerTrimmedString(event),
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
    @"details" : SMNormalizeDictionary(details),
  }];
  while ([self.activityLog count] > ALNStorageActivityLimit) {
    [self.activityLog removeObjectAtIndex:0];
  }
  [self.lock unlock];
}

- (NSUInteger)pruneExpiredUploadSessionsAt:(NSDate *)timestamp
                            recordActivity:(BOOL)recordActivity {
  NSDate *now = timestamp ?: [NSDate date];
  NSMutableArray<NSString *> *expired = [NSMutableArray array];
  [self.lock lock];
  for (NSString *sessionID in [self.uploadSessionsByIdentifier allKeys]) {
    NSDictionary *session = [self.uploadSessionsByIdentifier[sessionID] isKindOfClass:[NSDictionary class]]
                                ? self.uploadSessionsByIdentifier[sessionID]
                                : nil;
    if (session == nil || ![[session[@"status"] description] isEqualToString:@"pending"]) {
      continue;
    }
    NSTimeInterval expiresAt = [session[@"expiresAt"] respondsToSelector:@selector(doubleValue)]
                                   ? [session[@"expiresAt"] doubleValue]
                                   : 0.0;
    if (expiresAt > 0.0 && expiresAt <= [now timeIntervalSince1970]) {
      [expired addObject:sessionID];
    }
  }
  for (NSString *sessionID in expired) {
    [self.uploadSessionsByIdentifier removeObjectForKey:sessionID];
  }
  [self.lock unlock];
  if (recordActivity) {
    for (NSString *sessionID in expired) {
      [self recordActivityNamed:@"upload_session_expired" details:@{ @"sessionID" : sessionID ?: @"" }];
    }
  }
  if ([expired count] > 0) {
    (void)[self persistStateWithError:NULL];
  }
  return [expired count];
}

- (NSDictionary *)resolvedConfigSummary {
  [self pruneExpiredUploadSessionsAt:[NSDate date] recordActivity:NO];
  return @{
    @"prefix" : self.prefix ?: @"/storage",
    @"apiPrefix" : self.apiPrefix ?: @"/storage/api",
    @"uploadSessionTTLSeconds" : @(self.defaultUploadSessionTTLSeconds),
    @"downloadTokenTTLSeconds" : @(self.defaultDownloadTokenTTLSeconds),
    @"cleanupIntervalSeconds" : @(self.defaultCleanupIntervalSeconds),
    @"collections" : [self registeredCollections],
    @"objectCount" : @([[self listObjectsForCollection:nil query:nil] count]),
    @"uploadSessionCount" : @([self.uploadSessionsByIdentifier count]),
    @"activityCount" : @([self.activityLog count]),
    @"attachmentAdapter" : @{
      @"name" : (self.attachmentAdapter != nil) ? [self.attachmentAdapter adapterName] : @"",
      @"capabilities" : SMAttachmentAdapterCapabilities(self.attachmentAdapter),
    },
    @"persistenceEnabled" : @(self.persistenceEnabled),
    @"statePath" : self.statePath ?: @"",
  };
}

- (NSDictionary *)normalizedCollectionMetadataForDefinition:(id<ALNStorageCollectionDefinition>)definition
                                                      error:(NSError **)error {
  NSString *identifier = SMLowerTrimmedString([definition storageModuleCollectionIdentifier]);
  if ([identifier length] == 0) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration, @"storage collection identifier is required", nil);
    }
    return nil;
  }
  NSDictionary *rawMetadata = SMNormalizeDictionary([definition storageModuleCollectionMetadata]);
  NSUInteger maxBytes = [rawMetadata[@"maxBytes"] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? [rawMetadata[@"maxBytes"] unsignedIntegerValue]
                            : (5U * 1024U * 1024U);
  if (maxBytes == 0) {
    maxBytes = 5U * 1024U * 1024U;
  }
  NSArray<NSString *> *acceptedContentTypes = SMNormalizedContentTypes(rawMetadata[@"acceptedContentTypes"]);
  NSString *visibility = SMLowerTrimmedString(rawMetadata[@"visibility"]);
  if (![visibility isEqualToString:@"public"] && ![visibility isEqualToString:@"private"]) {
    visibility = @"private";
  }
  NSArray<NSDictionary *> *variants = SMNormalizedVariantDefinitions(rawMetadata[@"variants"]);
  return @{
    @"identifier" : identifier,
    @"title" : ([SMTrimmedString(rawMetadata[@"title"]) length] > 0) ? SMTrimmedString(rawMetadata[@"title"]) : [identifier capitalizedString],
    @"description" : SMTrimmedString(rawMetadata[@"description"]),
    @"acceptedContentTypes" : acceptedContentTypes ?: @[ @"*/*" ],
    @"maxBytes" : @(maxBytes),
    @"visibility" : visibility,
    @"retentionDays" : @([rawMetadata[@"retentionDays"] respondsToSelector:@selector(integerValue)] ? [rawMetadata[@"retentionDays"] integerValue] : 0),
    @"variants" : variants ?: @[],
    @"adminResourceIdentifier" : [NSString stringWithFormat:@"storage_%@", identifier],
  };
}

- (BOOL)registerCollectionDefinition:(id<ALNStorageCollectionDefinition>)definition
                              source:(NSString *)source
                               error:(NSError **)error {
  if (definition == nil || ![definition conformsToProtocol:@protocol(ALNStorageCollectionDefinition)]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                       @"storage collection definition must conform to ALNStorageCollectionDefinition",
                       nil);
    }
    return NO;
  }
  NSDictionary *metadata = [self normalizedCollectionMetadataForDefinition:definition error:error];
  if (metadata == nil) {
    return NO;
  }
  NSString *identifier = metadata[@"identifier"] ?: @"";
  NSMutableDictionary *storedMetadata = [NSMutableDictionary dictionaryWithDictionary:metadata];
  storedMetadata[@"source"] = SMTrimmedString(source);
  [self.lock lock];
  if (self.collectionDefinitionsByIdentifier[identifier] != nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"duplicate storage collection %@", identifier],
                       @{ @"identifier" : identifier });
    }
    return NO;
  }
  self.collectionDefinitionsByIdentifier[identifier] = definition;
  self.collectionMetadataByIdentifier[identifier] = [NSDictionary dictionaryWithDictionary:storedMetadata];
  if (![self.objectIDsByCollection[identifier] isKindOfClass:[NSMutableArray class]]) {
    self.objectIDsByCollection[identifier] = [NSMutableArray array];
  }
  [self.lock unlock];
  return YES;
}

- (NSArray<NSDictionary *> *)registeredCollections {
  [self.lock lock];
  NSArray<NSString *> *keys = [[self.collectionMetadataByIdentifier allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray *collections = [NSMutableArray array];
  for (NSString *identifier in keys) {
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:self.collectionMetadataByIdentifier[identifier] ?: @{}];
    metadata[@"objectCount"] = @([self.objectIDsByCollection[identifier] count]);
    [collections addObject:[NSDictionary dictionaryWithDictionary:metadata]];
  }
  [self.lock unlock];
  return [NSArray arrayWithArray:collections];
}

- (NSDictionary *)collectionMetadataForIdentifier:(NSString *)identifier {
  NSString *collectionID = SMLowerTrimmedString(identifier);
  [self.lock lock];
  NSDictionary *metadata = self.collectionMetadataByIdentifier[collectionID];
  NSUInteger objectCount = [self.objectIDsByCollection[collectionID] count];
  [self.lock unlock];
  if (metadata == nil) {
    return nil;
  }
  NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithDictionary:metadata];
  copy[@"objectCount"] = @(objectCount);
  return [NSDictionary dictionaryWithDictionary:copy];
}

- (NSDictionary *)internalObjectRecordForIdentifier:(NSString *)objectID {
  return self.objectsByIdentifier[SMTrimmedString(objectID)];
}

- (NSDictionary *)publicObjectRecordFromInternalRecord:(NSDictionary *)record {
  NSString *collection = SMLowerTrimmedString(record[@"collection"]);
  NSString *objectID = SMTrimmedString(record[@"objectID"]);
  NSMutableDictionary *publicRecord = [NSMutableDictionary dictionaryWithDictionary:record ?: @{}];
  publicRecord[@"paths"] = @{
    @"html" : SMPathJoin(self.prefix, [NSString stringWithFormat:@"collections/%@/objects/%@", collection, objectID]),
    @"api" : SMPathJoin(self.apiPrefix, [NSString stringWithFormat:@"collections/%@/objects/%@", collection, objectID]),
    @"download_token" : SMPathJoin(self.apiPrefix, [NSString stringWithFormat:@"collections/%@/objects/%@/download-token", collection, objectID]),
  };
  return [NSDictionary dictionaryWithDictionary:publicRecord];
}

- (NSArray<NSDictionary *> *)publicObjectRecordsFromIDs:(NSArray<NSString *> *)objectIDs {
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *objectID in objectIDs ?: @[]) {
    NSDictionary *record = [self internalObjectRecordForIdentifier:objectID];
    if ([record isKindOfClass:[NSDictionary class]]) {
      [records addObject:[self publicObjectRecordFromInternalRecord:record]];
    }
  }
  [records sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSNumber *leftSequence = [left[@"sequence"] respondsToSelector:@selector(integerValue)] ? left[@"sequence"] : @0;
    NSNumber *rightSequence = [right[@"sequence"] respondsToSelector:@selector(integerValue)] ? right[@"sequence"] : @0;
    return [rightSequence compare:leftSequence];
  }];
  return [NSArray arrayWithArray:records];
}

- (NSArray<NSDictionary *> *)listObjectsForCollection:(NSString *)collection
                                                query:(NSString *)query {
  NSString *collectionID = SMLowerTrimmedString(collection);
  NSString *search = SMLowerTrimmedString(query);
  [self.lock lock];
  NSArray<NSString *> *objectIDs = nil;
  if ([collectionID length] > 0) {
    objectIDs = [NSArray arrayWithArray:self.objectIDsByCollection[collectionID] ?: @[]];
  } else {
    objectIDs = [[self.objectsByIdentifier allKeys] sortedArrayUsingSelector:@selector(compare:)];
  }
  [self.lock unlock];
  NSArray<NSDictionary *> *records = [self publicObjectRecordsFromIDs:objectIDs];
  if ([search length] == 0) {
    return records;
  }
  NSMutableArray *filtered = [NSMutableArray array];
  for (NSDictionary *record in records) {
    if ([SMLowerTrimmedString(record[@"name"]) containsString:search] ||
        [SMLowerTrimmedString(record[@"collection"]) containsString:search] ||
        [SMLowerTrimmedString(record[@"contentType"]) containsString:search] ||
        [SMTrimmedString(record[@"objectID"]) containsString:search]) {
      [filtered addObject:record];
    }
  }
  return [NSArray arrayWithArray:filtered];
}

- (NSDictionary *)objectRecordForIdentifier:(NSString *)objectID
                                      error:(NSError **)error {
  NSString *normalizedObjectID = SMTrimmedString(objectID);
  [self.lock lock];
  NSDictionary *record = self.objectsByIdentifier[normalizedObjectID];
  [self.lock unlock];
  if (record == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"storage object %@ was not found", normalizedObjectID ?: @""],
                       @{ @"objectID" : normalizedObjectID ?: @"" });
    }
    return nil;
  }
  return [self publicObjectRecordFromInternalRecord:record];
}

- (BOOL)validateCollection:(NSString *)collection
                      name:(NSString *)name
               contentType:(NSString *)contentType
                 sizeBytes:(NSUInteger)sizeBytes
                  metadata:(NSDictionary *)metadata
                     error:(NSError **)error {
  NSString *collectionID = SMLowerTrimmedString(collection);
  NSDictionary *collectionMetadata = [self collectionMetadataForIdentifier:collectionID];
  id<ALNStorageCollectionDefinition> definition = self.collectionDefinitionsByIdentifier[collectionID];
  if (collectionMetadata == nil || definition == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"storage collection %@ was not found", collectionID ?: @""],
                       @{ @"collection" : collectionID ?: @"" });
    }
    return NO;
  }
  NSString *normalizedName = SMTrimmedString(name);
  if ([normalizedName length] == 0) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed, @"object name is required", @{ @"field" : @"name" });
    }
    return NO;
  }
  NSString *normalizedContentType = SMLowerTrimmedString(contentType);
  if ([normalizedContentType length] == 0) {
    normalizedContentType = @"application/octet-stream";
  }
  BOOL contentTypeAllowed = NO;
  for (NSString *allowed in (collectionMetadata[@"acceptedContentTypes"] ?: @[])) {
    if (SMContentTypeMatches(normalizedContentType, allowed)) {
      contentTypeAllowed = YES;
      break;
    }
  }
  if (!contentTypeAllowed) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed,
                       @"content type is not allowed for this collection",
                       @{ @"field" : @"contentType", @"collection" : collectionID ?: @"" });
    }
    return NO;
  }
  NSUInteger maxBytes = [collectionMetadata[@"maxBytes"] unsignedIntegerValue];
  if (sizeBytes > maxBytes) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed,
                       @"object exceeds the collection size limit",
                       @{ @"field" : @"sizeBytes", @"collection" : collectionID ?: @"" });
    }
    return NO;
  }
  if ([definition respondsToSelector:@selector(storageModuleValidateObjectNamed:contentType:sizeBytes:metadata:runtime:error:)]) {
    return [definition storageModuleValidateObjectNamed:normalizedName
                                            contentType:normalizedContentType
                                              sizeBytes:sizeBytes
                                               metadata:(metadata ?: @{})
                                                runtime:self
                                                  error:error];
  }
  return YES;
}

- (NSDictionary *)createUploadSessionForCollection:(NSString *)collection
                                              name:(NSString *)name
                                       contentType:(NSString *)contentType
                                         sizeBytes:(NSUInteger)sizeBytes
                                          metadata:(NSDictionary *)metadata
                                         expiresIn:(NSTimeInterval)expiresIn
                                             error:(NSError **)error {
  [self pruneExpiredUploadSessionsAt:[NSDate date] recordActivity:YES];
  if (![self validateCollection:collection
                           name:name
                    contentType:contentType
                      sizeBytes:sizeBytes
                       metadata:(metadata ?: @{})
                          error:error]) {
    return nil;
  }
  NSTimeInterval ttl = (expiresIn > 0.0) ? expiresIn : self.defaultUploadSessionTTLSeconds;
  [self.lock lock];
  self.nextSequence += 1;
  NSString *sessionID = [NSString stringWithFormat:@"upload-%lu", (unsigned long)self.nextSequence];
  NSDictionary *session = @{
    @"sessionID" : sessionID,
    @"collection" : SMLowerTrimmedString(collection),
    @"name" : SMTrimmedString(name),
    @"contentType" : ([SMLowerTrimmedString(contentType) length] > 0) ? SMLowerTrimmedString(contentType) : @"application/octet-stream",
    @"sizeBytes" : @(sizeBytes),
    @"metadata" : SMNormalizeDictionary(metadata),
    @"createdAt" : @([[NSDate date] timeIntervalSince1970]),
    @"expiresAt" : @([[NSDate dateWithTimeIntervalSinceNow:ttl] timeIntervalSince1970]),
    @"status" : @"pending",
  };
  self.uploadSessionsByIdentifier[sessionID] = session;
  [self.lock unlock];
  [self recordActivityNamed:@"upload_session_created"
                    details:@{
                      @"sessionID" : sessionID ?: @"",
                      @"collection" : SMLowerTrimmedString(collection),
                      @"name" : SMTrimmedString(name),
                    }];
  if (![self persistStateWithError:error]) {
    return nil;
  }
  NSString *token = SMCreateSignedToken(@{
    @"purpose" : @"upload",
    @"sessionID" : sessionID,
    @"collection" : SMLowerTrimmedString(collection),
    @"exp" : session[@"expiresAt"] ?: @0,
  }, self.signingKeyData);
  return @{
    @"sessionID" : sessionID,
    @"collection" : session[@"collection"] ?: @"",
    @"name" : session[@"name"] ?: @"",
    @"contentType" : session[@"contentType"] ?: @"application/octet-stream",
    @"sizeBytes" : session[@"sizeBytes"] ?: @0,
    @"expiresAt" : session[@"expiresAt"] ?: @0,
    @"token" : token ?: @"",
    @"uploadPath" : SMPathJoin(self.apiPrefix, [NSString stringWithFormat:@"upload-sessions/%@/upload", sessionID]),
  };
}

- (NSDictionary *)storeObjectInCollection:(NSString *)collection
                                     name:(NSString *)name
                              contentType:(NSString *)contentType
                                     data:(NSData *)data
                                 metadata:(NSDictionary *)metadata
                                    error:(NSError **)error {
  NSUInteger sizeBytes = [data isKindOfClass:[NSData class]] ? [data length] : 0;
  if (![self validateCollection:collection
                           name:name
                    contentType:contentType
                      sizeBytes:sizeBytes
                       metadata:(metadata ?: @{})
                          error:error]) {
    return nil;
  }
  NSString *attachmentID = [self.attachmentAdapter saveAttachmentNamed:SMTrimmedString(name)
                                                           contentType:([SMLowerTrimmedString(contentType) length] > 0) ? SMLowerTrimmedString(contentType) : @"application/octet-stream"
                                                                  data:data ?: [NSData data]
                                                              metadata:metadata
                                                                 error:error];
  if ([attachmentID length] == 0) {
    if (error != NULL && *error == NULL) {
      *error = SMError(ALNStorageModuleErrorPersistenceFailed, @"object data could not be persisted", nil);
    }
    return nil;
  }
  NSDictionary *collectionMetadata = [self collectionMetadataForIdentifier:collection] ?: @{};
  NSArray<NSDictionary *> *variantDefinitions = collectionMetadata[@"variants"] ?: @[];
  NSMutableArray *variants = [NSMutableArray array];
  for (NSDictionary *variant in variantDefinitions) {
    [variants addObject:[@{
      @"identifier" : SMTrimmedString(variant[@"identifier"]),
      @"label" : SMTrimmedString(variant[@"label"]),
      @"contentType" : SMTrimmedString(variant[@"contentType"]),
      @"strategy" : SMTrimmedString(variant[@"strategy"]),
      @"status" : @"pending",
      @"error" : @"",
      @"attachmentID" : @"",
      @"sizeBytes" : @0,
    } mutableCopy]];
  }
  NSDictionary *analysis = SMAnalyzeObjectData(name, contentType, data ?: [NSData data], metadata ?: @{}, variantDefinitions);

  NSDictionary *record = nil;
  [self.lock lock];
  self.nextSequence += 1;
  NSString *objectID = [NSString stringWithFormat:@"obj-%lu", (unsigned long)self.nextSequence];
  record = @{
    @"objectID" : objectID,
    @"sequence" : @(self.nextSequence),
    @"collection" : SMLowerTrimmedString(collection),
    @"name" : SMTrimmedString(name),
    @"contentType" : ([SMLowerTrimmedString(contentType) length] > 0) ? SMLowerTrimmedString(contentType) : @"application/octet-stream",
    @"sizeBytes" : @(sizeBytes),
    @"visibility" : collectionMetadata[@"visibility"] ?: @"private",
    @"attachmentID" : attachmentID ?: @"",
    @"metadata" : SMNormalizeDictionary(metadata),
    @"analysis" : analysis ?: @{},
    @"createdAt" : @([[NSDate date] timeIntervalSince1970]),
    @"variantState" : ([variants count] > 0) ? @"pending" : @"none",
    @"variants" : [NSArray arrayWithArray:variants],
  };
  self.objectsByIdentifier[objectID] = record;
  NSMutableArray *collectionIDs = self.objectIDsByCollection[SMLowerTrimmedString(collection)];
  if (![collectionIDs isKindOfClass:[NSMutableArray class]]) {
    collectionIDs = [NSMutableArray array];
    self.objectIDsByCollection[SMLowerTrimmedString(collection)] = collectionIDs;
  }
  [collectionIDs addObject:objectID];
  [self.lock unlock];
  [self recordActivityNamed:@"object_stored"
                    details:@{
                      @"objectID" : record[@"objectID"] ?: @"",
                      @"collection" : record[@"collection"] ?: @"",
                      @"name" : record[@"name"] ?: @"",
                    }];
  if (![self persistStateWithError:error]) {
    return nil;
  }

  if ([variants count] > 0) {
    (void)[self queueVariantGenerationForObjectID:record[@"objectID"] error:NULL];
  }
  return [self publicObjectRecordFromInternalRecord:record];
}

- (NSDictionary *)validatedTokenPayload:(NSString *)token
                                purpose:(NSString *)purpose
                          expectedField:(NSString *)expectedField
                          expectedValue:(NSString *)expectedValue
                                  error:(NSError **)error {
  NSDictionary *payload = SMTokenPayloadDecode(token, self.signingKeyData, error);
  if (payload == nil) {
    return nil;
  }
  if (![SMTrimmedString(payload[@"purpose"]) isEqualToString:SMTrimmedString(purpose)]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token purpose was rejected", nil);
    }
    return nil;
  }
  NSTimeInterval expiry = [payload[@"exp"] respondsToSelector:@selector(doubleValue)] ? [payload[@"exp"] doubleValue] : 0.0;
  if (expiry <= [[NSDate date] timeIntervalSince1970]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token expired", nil);
    }
    return nil;
  }
  if ([SMTrimmedString(expectedField) length] > 0 &&
      ![SMTrimmedString(payload[expectedField]) isEqualToString:SMTrimmedString(expectedValue)]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token payload does not match the requested target", nil);
    }
    return nil;
  }
  return payload;
}

- (NSDictionary *)storeUploadData:(NSData *)data
                  forUploadSessionID:(NSString *)sessionID
                               token:(NSString *)token
                               error:(NSError **)error {
  NSString *normalizedSessionID = SMTrimmedString(sessionID);
  [self pruneExpiredUploadSessionsAt:[NSDate date] recordActivity:YES];
  NSDictionary *tokenPayload = [self validatedTokenPayload:token
                                                   purpose:@"upload"
                                             expectedField:@"sessionID"
                                             expectedValue:normalizedSessionID
                                                     error:error];
  if (tokenPayload == nil) {
    return nil;
  }
  [self.lock lock];
  NSDictionary *session = self.uploadSessionsByIdentifier[normalizedSessionID];
  [self.lock unlock];
  if (session == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"upload session %@ was not found", normalizedSessionID ?: @""],
                       @{ @"sessionID" : normalizedSessionID ?: @"" });
    }
    return nil;
  }
  if ([[session[@"status"] description] isEqualToString:@"complete"]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed, @"upload session has already been completed", nil);
    }
    return nil;
  }
  NSUInteger expectedSize = [session[@"sizeBytes"] respondsToSelector:@selector(unsignedIntegerValue)]
                                ? [session[@"sizeBytes"] unsignedIntegerValue]
                                : 0;
  if (expectedSize > 0 && [data length] != expectedSize) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed,
                       @"upload data does not match the signed session size",
                       @{ @"field" : @"sizeBytes" });
    }
    return nil;
  }
  NSDictionary *object = [self storeObjectInCollection:session[@"collection"]
                                                  name:session[@"name"]
                                           contentType:session[@"contentType"]
                                                  data:data
                                              metadata:session[@"metadata"]
                                                 error:error];
  if (object == nil) {
    return nil;
  }
  [self.lock lock];
  NSMutableDictionary *updatedSession = [NSMutableDictionary dictionaryWithDictionary:session];
  updatedSession[@"status"] = @"complete";
  updatedSession[@"objectID"] = object[@"objectID"] ?: @"";
  self.uploadSessionsByIdentifier[normalizedSessionID] = [NSDictionary dictionaryWithDictionary:updatedSession];
  [self.lock unlock];
  [self recordActivityNamed:@"upload_session_completed"
                    details:@{
                      @"sessionID" : normalizedSessionID ?: @"",
                      @"objectID" : object[@"objectID"] ?: @"",
                    }];
  if (![self persistStateWithError:error]) {
    return nil;
  }
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:object];
  result[@"sessionID"] = normalizedSessionID;
  return [NSDictionary dictionaryWithDictionary:result];
}

- (NSString *)issueDownloadTokenForObjectID:(NSString *)objectID
                                  expiresIn:(NSTimeInterval)expiresIn
                                      error:(NSError **)error {
  NSDictionary *record = [self objectRecordForIdentifier:objectID error:error];
  if (record == nil) {
    return nil;
  }
  NSTimeInterval ttl = (expiresIn > 0.0) ? expiresIn : self.defaultDownloadTokenTTLSeconds;
  return SMCreateSignedToken(@{
    @"purpose" : @"download",
    @"objectID" : record[@"objectID"] ?: @"",
    @"exp" : @([[NSDate dateWithTimeIntervalSinceNow:ttl] timeIntervalSince1970]),
  }, self.signingKeyData);
}

- (NSDictionary *)payloadForDownloadToken:(NSString *)token
                                    error:(NSError **)error {
  return [self validatedTokenPayload:token purpose:@"download" expectedField:nil expectedValue:nil error:error];
}

- (NSData *)downloadDataForToken:(NSString *)token
                        metadata:(NSDictionary **)metadata
                           error:(NSError **)error {
  NSDictionary *payload = [self validatedTokenPayload:token
                                              purpose:@"download"
                                        expectedField:nil
                                        expectedValue:nil
                                                error:error];
  if (payload == nil) {
    return nil;
  }
  NSDictionary *record = [self objectRecordForIdentifier:payload[@"objectID"] error:error];
  if (record == nil) {
    return nil;
  }
  NSDictionary *adapterMetadata = nil;
  NSData *data = [self.attachmentAdapter attachmentDataForID:record[@"attachmentID"] metadata:&adapterMetadata error:error];
  if (data == nil) {
    return nil;
  }
  if (metadata != NULL) {
    NSMutableDictionary *combined = [NSMutableDictionary dictionaryWithDictionary:adapterMetadata ?: @{}];
    combined[@"object"] = record;
    *metadata = [NSDictionary dictionaryWithDictionary:combined];
  }
  return data;
}

- (BOOL)deleteObjectIdentifier:(NSString *)objectID
                         error:(NSError **)error {
  return [self deleteObjectIdentifier:objectID reason:@"manual" error:error];
}

- (BOOL)deleteObjectIdentifier:(NSString *)objectID
                        reason:(NSString *)reason
                         error:(NSError **)error {
  NSString *normalizedObjectID = SMTrimmedString(objectID);
  [self.lock lock];
  NSDictionary *record = self.objectsByIdentifier[normalizedObjectID];
  [self.lock unlock];
  if (record == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"storage object %@ was not found", normalizedObjectID ?: @""],
                       @{ @"objectID" : normalizedObjectID ?: @"" });
    }
    return NO;
  }
  NSMutableArray<NSString *> *attachmentIDs = [NSMutableArray array];
  if ([SMTrimmedString(record[@"attachmentID"]) length] > 0) {
    [attachmentIDs addObject:record[@"attachmentID"]];
  }
  for (NSDictionary *variant in (record[@"variants"] ?: @[])) {
    NSString *attachmentID = SMTrimmedString(variant[@"attachmentID"]);
    if ([attachmentID length] > 0) {
      [attachmentIDs addObject:attachmentID];
    }
  }
  for (NSString *attachmentID in attachmentIDs) {
    (void)[self.attachmentAdapter deleteAttachmentID:attachmentID error:NULL];
  }
  [self.lock lock];
  [self.objectsByIdentifier removeObjectForKey:normalizedObjectID];
  NSMutableArray *collectionIDs = self.objectIDsByCollection[SMLowerTrimmedString(record[@"collection"])];
  [collectionIDs removeObject:normalizedObjectID];
  [self.lock unlock];
  [self recordActivityNamed:@"object_deleted"
                    details:@{
                      @"objectID" : normalizedObjectID ?: @"",
                      @"collection" : SMLowerTrimmedString(record[@"collection"]),
                      @"reason" : SMLowerTrimmedString(reason),
                    }];
  return [self persistStateWithError:error];
}

- (NSDictionary *)runMaintenanceAt:(NSDate *)timestamp
                              error:(NSError **)error {
  NSDate *now = timestamp ?: [NSDate date];
  NSUInteger expiredSessions = [self pruneExpiredUploadSessionsAt:now recordActivity:YES];
  NSArray *objects = [self listObjectsForCollection:nil query:nil];
  NSUInteger deletedObjects = 0;
  for (NSDictionary *record in objects) {
    NSString *collectionID = SMLowerTrimmedString(record[@"collection"]);
    NSDictionary *collection = [self collectionMetadataForIdentifier:collectionID] ?: @{};
    NSInteger retentionDays = [collection[@"retentionDays"] respondsToSelector:@selector(integerValue)]
                                  ? [collection[@"retentionDays"] integerValue]
                                  : 0;
    if (retentionDays <= 0) {
      continue;
    }
    NSTimeInterval createdAt = [record[@"createdAt"] respondsToSelector:@selector(doubleValue)]
                                   ? [record[@"createdAt"] doubleValue]
                                   : 0.0;
    if (createdAt <= 0.0) {
      continue;
    }
    NSTimeInterval retentionAge = (NSTimeInterval)retentionDays * 86400.0;
    if ((createdAt + retentionAge) > [now timeIntervalSince1970]) {
      continue;
    }
    NSError *deleteError = nil;
    if ([self deleteObjectIdentifier:record[@"objectID"] reason:@"retention_expired" error:&deleteError]) {
      deletedObjects += 1;
    } else if (error != NULL && *error == nil) {
      *error = deleteError;
    }
  }
  NSDictionary *summary = @{
    @"expiredUploadSessions" : @(expiredSessions),
    @"deletedObjects" : @(deletedObjects),
    @"timestamp" : @([now timeIntervalSince1970]),
  };
  [self recordActivityNamed:@"maintenance_completed" details:summary];
  if (![self persistStateWithError:error]) {
    return nil;
  }
  return summary;
}

- (NSDictionary *)queueVariantGenerationForObjectID:(NSString *)objectID
                                              error:(NSError **)error {
  NSDictionary *record = [self objectRecordForIdentifier:objectID error:error];
  if (record == nil) {
    return nil;
  }
  NSArray *variants = [record[@"variants"] isKindOfClass:[NSArray class]] ? record[@"variants"] : @[];
  if ([variants count] == 0) {
    return @{ @"objectID" : record[@"objectID"] ?: @"", @"queuedCount" : @0, @"status" : @"no_variants" };
  }
  NSMutableArray *resetVariants = [NSMutableArray array];
  for (NSDictionary *variant in variants) {
    NSMutableDictionary *mutableVariant = [NSMutableDictionary dictionaryWithDictionary:variant];
    mutableVariant[@"status"] = @"pending";
    mutableVariant[@"error"] = @"";
    [resetVariants addObject:mutableVariant];
  }
  NSMutableDictionary *mutableRecord = [NSMutableDictionary dictionaryWithDictionary:record];
  mutableRecord[@"variants"] = [NSArray arrayWithArray:resetVariants];
  mutableRecord[@"variantState"] = @"pending";
  [self.lock lock];
  self.objectsByIdentifier[record[@"objectID"]] = [NSDictionary dictionaryWithDictionary:mutableRecord];
  [self.lock unlock];
  NSUInteger queuedCount = 0;
  for (NSDictionary *variant in variants) {
    NSString *variantID = SMTrimmedString(variant[@"identifier"]);
    if ([variantID length] == 0) {
      continue;
    }
    NSError *jobError = nil;
    NSString *jobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:ALNStorageVariantJobIdentifier
                                                                         payload:@{ @"objectID" : record[@"objectID"] ?: @"", @"variant" : variantID }
                                                                         options:@{ @"queue" : @"default", @"source" : @"storage" }
                                                                           error:&jobError];
    if ([jobID length] > 0) {
      queuedCount += 1;
    } else if (error != NULL && *error == nil) {
      *error = jobError;
    }
  }
  NSDictionary *summary = @{ @"objectID" : record[@"objectID"] ?: @"", @"queuedCount" : @(queuedCount), @"status" : @"queued" };
  [self recordActivityNamed:@"variant_generation_queued"
                    details:@{
                      @"objectID" : record[@"objectID"] ?: @"",
                      @"queuedCount" : @(queuedCount),
                    }];
  (void)[self persistStateWithError:NULL];
  return summary;
}

- (NSDictionary *)processVariantJobPayload:(NSDictionary *)payload
                                     error:(NSError **)error {
  return [self processVariantJobPayload:payload jobContext:@{} error:error];
}

- (NSDictionary *)processVariantJobPayload:(NSDictionary *)payload
                                 jobContext:(NSDictionary *)jobContext
                                      error:(NSError **)error {
  NSString *objectID = SMTrimmedString(payload[@"objectID"]);
  NSString *variantID = SMLowerTrimmedString(payload[@"variant"]);
  [self.lock lock];
  NSDictionary *record = self.objectsByIdentifier[objectID];
  [self.lock unlock];
  if (record == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound, @"storage object was not found", @{ @"objectID" : objectID ?: @"" });
    }
    return nil;
  }
  NSDictionary *originalMetadata = nil;
  NSData *data = [self.attachmentAdapter attachmentDataForID:record[@"attachmentID"] metadata:&originalMetadata error:error];
  if (data == nil) {
    return nil;
  }
  NSString *collectionID = SMLowerTrimmedString(record[@"collection"]);
  id<ALNStorageCollectionDefinition> definition = self.collectionDefinitionsByIdentifier[collectionID];
  NSMutableArray *updatedVariants = [NSMutableArray array];
  BOOL found = NO;
  NSString *generatedAttachmentID = nil;
  NSError *processingError = nil;
  for (NSDictionary *variant in (record[@"variants"] ?: @[])) {
    NSMutableDictionary *mutableVariant = [NSMutableDictionary dictionaryWithDictionary:variant];
    if ([SMLowerTrimmedString(variant[@"identifier"]) isEqualToString:variantID]) {
      found = YES;
      NSData *variantData = data;
      NSString *variantContentType = ([SMLowerTrimmedString(variant[@"contentType"]) length] > 0)
                                         ? SMLowerTrimmedString(variant[@"contentType"])
                                         : SMLowerTrimmedString(record[@"contentType"]);
      NSDictionary *variantMetadata = @{
        @"sourceObjectID" : objectID ?: @"",
        @"variant" : variantID ?: @"",
      };
      if (definition != nil &&
          [definition respondsToSelector:@selector(storageModuleVariantRepresentationForObject:variantDefinition:originalData:originalMetadata:runtime:error:)]) {
        NSDictionary *representation =
            [definition storageModuleVariantRepresentationForObject:[self publicObjectRecordFromInternalRecord:record]
                                                 variantDefinition:variant
                                                      originalData:data
                                                  originalMetadata:originalMetadata ?: @{}
                                                           runtime:self
                                                             error:&processingError];
        if ([representation isKindOfClass:[NSDictionary class]]) {
          NSData *candidateData = [representation[@"data"] isKindOfClass:[NSData class]] ? representation[@"data"] : nil;
          if (candidateData != nil) {
            variantData = candidateData;
          }
          NSString *candidateContentType = SMLowerTrimmedString(representation[@"contentType"]);
          if ([candidateContentType length] > 0) {
            variantContentType = candidateContentType;
          }
          NSDictionary *candidateMetadata = [representation[@"metadata"] isKindOfClass:[NSDictionary class]]
                                                ? representation[@"metadata"]
                                                : nil;
          if (candidateMetadata != nil) {
            NSMutableDictionary *mergedMetadata = [NSMutableDictionary dictionaryWithDictionary:variantMetadata];
            [mergedMetadata addEntriesFromDictionary:candidateMetadata];
            variantMetadata = mergedMetadata;
          }
        } else if (representation == nil && processingError != nil) {
          mutableVariant[@"status"] = @"failed";
          mutableVariant[@"error"] = processingError.localizedDescription ?: @"variant generation failed";
        }
      }
      if (processingError == nil) {
        generatedAttachmentID = [self.attachmentAdapter saveAttachmentNamed:[NSString stringWithFormat:@"%@-%@", record[@"name"] ?: @"object", variantID]
                                                                contentType:variantContentType
                                                                       data:variantData
                                                                   metadata:variantMetadata
                                                                      error:&processingError];
        if ([generatedAttachmentID length] == 0) {
          mutableVariant[@"status"] = @"failed";
          mutableVariant[@"error"] = processingError.localizedDescription ?: @"variant generation failed";
        }
      }
      if (processingError == nil) {
        mutableVariant[@"status"] = @"ready";
        mutableVariant[@"attachmentID"] = generatedAttachmentID;
        mutableVariant[@"sizeBytes"] = @([variantData length]);
        mutableVariant[@"generatedAt"] = @([[NSDate date] timeIntervalSince1970]);
        mutableVariant[@"error"] = @"";
      }
    }
    [updatedVariants addObject:mutableVariant];
  }
  if (!found) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"variant %@ was not found", variantID ?: @""],
                       @{ @"variant" : variantID ?: @"" });
    }
    return nil;
  }
  BOOL allReady = YES;
  BOOL anyFailed = NO;
  for (NSDictionary *variant in updatedVariants) {
    if (![SMTrimmedString(variant[@"status"]) isEqualToString:@"ready"]) {
      allReady = NO;
    }
    if ([SMTrimmedString(variant[@"status"]) isEqualToString:@"failed"]) {
      anyFailed = YES;
    }
  }
  NSMutableDictionary *updatedRecord = [NSMutableDictionary dictionaryWithDictionary:record];
  updatedRecord[@"variants"] = [NSArray arrayWithArray:updatedVariants];
  updatedRecord[@"variantState"] = allReady ? @"ready" : (anyFailed ? @"failed" : @"pending");
  updatedRecord[@"analysis"] = SMAnalyzeObjectData(updatedRecord[@"name"],
                                                   updatedRecord[@"contentType"],
                                                   data ?: [NSData data],
                                                   updatedRecord[@"metadata"] ?: @{},
                                                   updatedVariants);
  [self.lock lock];
  self.objectsByIdentifier[objectID] = [NSDictionary dictionaryWithDictionary:updatedRecord];
  [self.lock unlock];
  NSUInteger attempt = [jobContext[@"attempt"] respondsToSelector:@selector(unsignedIntegerValue)]
                           ? [jobContext[@"attempt"] unsignedIntegerValue]
                           : 1;
  NSUInteger maxAttempts = [jobContext[@"maxAttempts"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? [jobContext[@"maxAttempts"] unsignedIntegerValue]
                               : 1;
  if (processingError != nil) {
    [self recordActivityNamed:@"variant_failed"
                      details:@{
                        @"objectID" : objectID ?: @"",
                        @"variant" : variantID ?: @"",
                        @"attempt" : @(attempt),
                        @"maxAttempts" : @(maxAttempts),
                        @"error" : processingError.localizedDescription ?: @"variant generation failed",
                      }];
    (void)[self persistStateWithError:NULL];
    if (error != NULL) {
      *error = processingError;
    }
    return nil;
  }
  NSDictionary *summary = @{
    @"objectID" : objectID ?: @"",
    @"variant" : variantID ?: @"",
    @"status" : @"ready",
    @"attachmentID" : generatedAttachmentID ?: @"",
  };
  [self recordActivityNamed:@"variant_ready"
                    details:@{
                      @"objectID" : objectID ?: @"",
                      @"variant" : variantID ?: @"",
                    }];
  if (![self persistStateWithError:error]) {
    return nil;
  }
  return summary;
}

- (NSDictionary *)dashboardSummary {
  [self pruneExpiredUploadSessionsAt:[NSDate date] recordActivity:NO];
  NSArray *collections = [self registeredCollections];
  NSArray *allObjects = [self listObjectsForCollection:nil query:nil];
  NSUInteger pendingVariantCount = 0;
  for (NSDictionary *record in allObjects) {
    for (NSDictionary *variant in (record[@"variants"] ?: @[])) {
      if ([SMTrimmedString(variant[@"status"]) isEqualToString:@"pending"]) {
        pendingVariantCount += 1;
      }
    }
  }
  return @{
    @"cards" : @[
      @{ @"label" : @"Collections", @"value" : @([collections count]) },
      @{ @"label" : @"Objects", @"value" : @([allObjects count]) },
      @{ @"label" : @"Upload sessions", @"value" : @([self.uploadSessionsByIdentifier count]) },
      @{ @"label" : @"Pending variants", @"value" : @(pendingVariantCount) },
      @{ @"label" : @"Activity", @"value" : @([self.activityLog count]) },
    ],
    @"collections" : collections ?: @[],
    @"attachmentAdapter" : @{
      @"name" : (self.attachmentAdapter != nil) ? [self.attachmentAdapter adapterName] : @"",
      @"capabilities" : SMAttachmentAdapterCapabilities(self.attachmentAdapter),
    },
    @"recentObjects" : ([allObjects count] > 5) ? [allObjects subarrayWithRange:NSMakeRange(0, 5)] : allObjects,
    @"recentActivity" : ([[NSArray alloc] initWithArray:self.activityLog copyItems:YES] ?: @[]),
  };
}

@end

@interface ALNStorageModuleController : ALNController

@property(nonatomic, strong) ALNStorageModuleRuntime *runtime;
@property(nonatomic, strong) ALNAuthModuleRuntime *authRuntime;

- (BOOL)requireStorageHTML:(ALNContext *)ctx;

@end

@interface ALNStorageAdminResource : NSObject <ALNAdminUIResource>

@property(nonatomic, strong) ALNStorageModuleRuntime *runtime;

- (instancetype)initWithRuntime:(ALNStorageModuleRuntime *)runtime;

@end

@interface ALNStorageAdminResourceProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation ALNStorageModuleController

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _runtime = [ALNStorageModuleRuntime sharedRuntime];
    _authRuntime = [ALNAuthModuleRuntime sharedRuntime];
  }
  return self;
}

- (NSDictionary *)requestParameters {
  NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:self.context.request.queryParams ?: @{}];
  NSString *contentType = [[[self headerValueForName:@"content-type"] lowercaseString] componentsSeparatedByString:@";"][0];
  NSDictionary *bodyParameters = @{};
  if ([contentType containsString:@"application/json"]) {
    bodyParameters = SMJSONParametersFromBody(self.context.request.body);
  } else if ([contentType containsString:@"application/x-www-form-urlencoded"]) {
    bodyParameters = SMFormParametersFromBody(self.context.request.body);
  }
  [parameters addEntriesFromDictionary:bodyParameters ?: @{}];
  return parameters;
}

- (NSString *)storageReturnPathForContext:(ALNContext *)ctx {
  NSString *path = ctx.request.path ?: @"/";
  NSString *query = SMTrimmedString(ctx.request.queryString);
  if ([query length] > 0) {
    return [NSString stringWithFormat:@"%@?%@", path, query];
  }
  return path;
}

- (NSDictionary *)pageContextWithTitle:(NSString *)title
                               heading:(NSString *)heading
                               message:(NSString *)message
                                errors:(NSArray *)errors
                                 extra:(NSDictionary *)extra {
  NSMutableDictionary *context = [NSMutableDictionary dictionary];
  context[@"pageTitle"] = title ?: @"Arlen Storage";
  context[@"pageHeading"] = heading ?: context[@"pageTitle"];
  context[@"message"] = message ?: @"";
  context[@"errors"] = [errors isKindOfClass:[NSArray class]] ? errors : @[];
  context[@"storagePrefix"] = self.runtime.prefix ?: @"/storage";
  context[@"storageAPIPrefix"] = self.runtime.apiPrefix ?: @"/storage/api";
  context[@"authLoginPath"] = [self.authRuntime loginPath] ?: @"/auth/login";
  context[@"authLogoutPath"] = [self.authRuntime logoutPath] ?: @"/auth/logout";
  context[@"csrfToken"] = [self csrfToken] ?: @"";
  context[@"summary"] = [self.runtime dashboardSummary] ?: @{};
  if ([extra isKindOfClass:[NSDictionary class]]) {
    [context addEntriesFromDictionary:extra];
  }
  return context;
}

- (BOOL)requireStorageHTML:(ALNContext *)ctx {
  NSString *returnTo = [self storageReturnPathForContext:ctx];
  if ([[ctx authSubject] length] == 0) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime loginPath] ?: @"/auth/login",
                                                    SMPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  if (![self.authRuntime isAdminContext:ctx error:NULL]) {
    [self setStatus:403];
    [self renderTemplate:@"modules/storage/result/index"
                 context:[self pageContextWithTitle:@"Storage Access"
                                            heading:@"Access denied"
                                            message:@"You do not have the operator/admin role required for storage."
                                             errors:nil
                                              extra:nil]
                  layout:@"modules/storage/layouts/main"
                   error:NULL];
    return NO;
  }
  if ([ctx authAssuranceLevel] < 2) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime totpPath] ?: @"/auth/mfa/totp",
                                                    SMPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  return YES;
}

- (id)dashboard:(ALNContext *)ctx {
  (void)ctx;
  [self renderTemplate:@"modules/storage/dashboard/index"
               context:[self pageContextWithTitle:@"Storage"
                                          heading:@"Storage"
                                          message:@""
                                           errors:nil
                                            extra:nil]
                layout:@"modules/storage/layouts/main"
                 error:NULL];
  return nil;
}

- (id)collectionIndex:(ALNContext *)ctx {
  NSString *collection = [self stringParamForName:@"collection"] ?: @"";
  NSDictionary *metadata = [self.runtime collectionMetadataForIdentifier:collection];
  if (metadata == nil) {
    [self setStatus:404];
    [self renderTemplate:@"modules/storage/result/index"
                 context:[self pageContextWithTitle:@"Storage"
                                            heading:@"Collection not found"
                                            message:@"The requested storage collection does not exist."
                                             errors:nil
                                              extra:@{
                                                @"resultActionPath" : self.runtime.prefix ?: @"/storage",
                                                @"resultActionLabel" : @"Back to storage",
                                              }]
                  layout:@"modules/storage/layouts/main"
                   error:NULL];
    return nil;
  }
  [self renderTemplate:@"modules/storage/collections/index"
               context:[self pageContextWithTitle:metadata[@"title"]
                                          heading:metadata[@"title"]
                                          message:@""
                                           errors:nil
                                            extra:@{
                                              @"collection" : metadata,
                                              @"objects" : [self.runtime listObjectsForCollection:collection query:[self queryValueForName:@"q"]] ?: @[],
                                              @"query" : [self queryValueForName:@"q"] ?: @"",
                                            }]
                layout:@"modules/storage/layouts/main"
                 error:NULL];
  return nil;
}

- (id)objectDetail:(ALNContext *)ctx {
  NSString *collection = [self stringParamForName:@"collection"] ?: @"";
  NSError *error = nil;
  NSDictionary *record = [self.runtime objectRecordForIdentifier:[self stringParamForName:@"objectID"] ?: @"" error:&error];
  if (record == nil || ![SMLowerTrimmedString(record[@"collection"]) isEqualToString:SMLowerTrimmedString(collection)]) {
    [self setStatus:404];
    [self renderTemplate:@"modules/storage/result/index"
                 context:[self pageContextWithTitle:@"Storage"
                                            heading:@"Object not found"
                                            message:error.localizedDescription ?: @"The requested object could not be found."
                                             errors:nil
                                              extra:@{
                                                @"resultActionPath" : SMPathJoin(self.runtime.prefix, [NSString stringWithFormat:@"collections/%@", collection]),
                                                @"resultActionLabel" : @"Back to collection",
                                              }]
                  layout:@"modules/storage/layouts/main"
                   error:NULL];
    return nil;
  }
  [self renderTemplate:@"modules/storage/objects/show"
               context:[self pageContextWithTitle:record[@"name"]
                                          heading:record[@"name"]
                                          message:@""
                                           errors:nil
                                            extra:@{
                                              @"object" : record,
                                            }]
                layout:@"modules/storage/layouts/main"
                 error:NULL];
  return nil;
}

- (id)deleteObjectHTML:(ALNContext *)ctx {
  NSError *error = nil;
  BOOL ok = [self.runtime deleteObjectIdentifier:[self stringParamForName:@"objectID"] ?: @"" error:&error];
  if (!ok) {
    [self setStatus:422];
    [self renderTemplate:@"modules/storage/result/index"
                 context:[self pageContextWithTitle:@"Storage"
                                            heading:@"Delete failed"
                                            message:error.localizedDescription ?: @"Delete failed."
                                             errors:nil
                                              extra:@{
                                                @"resultActionPath" : self.runtime.prefix ?: @"/storage",
                                                @"resultActionLabel" : @"Back to storage",
                                              }]
                  layout:@"modules/storage/layouts/main"
                   error:NULL];
    return nil;
  }
  [self redirectTo:SMPathJoin(self.runtime.prefix, [NSString stringWithFormat:@"collections/%@", [self stringParamForName:@"collection"] ?: @""]) status:302];
  return nil;
}

- (id)regenerateVariantsHTML:(ALNContext *)ctx {
  (void)[self.runtime queueVariantGenerationForObjectID:[self stringParamForName:@"objectID"] ?: @"" error:NULL];
  [self redirectTo:SMPathJoin(self.runtime.prefix,
                              [NSString stringWithFormat:@"collections/%@/objects/%@",
                                                         [self stringParamForName:@"collection"] ?: @"",
                                                         [self stringParamForName:@"objectID"] ?: @""]) status:302];
  return nil;
}

- (id)apiCollections:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"collections" : [self.runtime registeredCollections] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiObjects:(ALNContext *)ctx {
  NSString *collection = [self stringParamForName:@"collection"] ?: @"";
  [self renderJSONEnvelopeWithData:@{
    @"collection" : [self.runtime collectionMetadataForIdentifier:collection] ?: @{},
    @"objects" : [self.runtime listObjectsForCollection:collection query:[self queryValueForName:@"q"]] ?: @[],
  } meta:nil error:NULL];
  return nil;
}

- (id)apiObjectDetail:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  NSDictionary *record = [self.runtime objectRecordForIdentifier:[self stringParamForName:@"objectID"] ?: @"" error:&error];
  if (record == nil) {
    [self setStatus:404];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Object not found" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"object" : record } meta:nil error:NULL];
  return nil;
}

- (id)apiCreateUploadSession:(ALNContext *)ctx {
  (void)ctx;
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *session = [self.runtime createUploadSessionForCollection:SMTrimmedString(parameters[@"collection"])
                                                                    name:SMTrimmedString(parameters[@"name"])
                                                             contentType:SMLowerTrimmedString(parameters[@"contentType"])
                                                               sizeBytes:[parameters[@"sizeBytes"] respondsToSelector:@selector(unsignedIntegerValue)] ? [parameters[@"sizeBytes"] unsignedIntegerValue] : 0
                                                                metadata:SMNormalizeDictionary(parameters[@"metadata"])
                                                               expiresIn:[parameters[@"expiresIn"] respondsToSelector:@selector(doubleValue)] ? [parameters[@"expiresIn"] doubleValue] : 0.0
                                                                   error:&error];
  if (session == nil) {
    [self setStatus:(error.code == ALNStorageModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Upload session failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:session meta:nil error:NULL];
  return nil;
}

- (id)apiUpload:(ALNContext *)ctx {
  (void)ctx;
  NSString *token = [self headerValueForName:@"x-upload-token"] ?: [self queryValueForName:@"token"] ?: @"";
  NSError *error = nil;
  NSDictionary *object = [self.runtime storeUploadData:self.context.request.body ?: [NSData data]
                                    forUploadSessionID:[self stringParamForName:@"sessionID"] ?: @""
                                                 token:token
                                                 error:&error];
  if (object == nil) {
    [self setStatus:(error.code == ALNStorageModuleErrorNotFound || error.code == ALNStorageModuleErrorTokenRejected) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Upload failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"object" : object } meta:nil error:NULL];
  return nil;
}

- (id)apiIssueDownloadToken:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSString *token = [self.runtime issueDownloadTokenForObjectID:[self stringParamForName:@"objectID"] ?: @""
                                                      expiresIn:[parameters[@"expiresIn"] respondsToSelector:@selector(doubleValue)] ? [parameters[@"expiresIn"] doubleValue] : 0.0
                                                          error:&error];
  if ([token length] == 0) {
    [self setStatus:(error.code == ALNStorageModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Download token failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{
    @"token" : token,
    @"downloadPath" : SMPathJoin(self.runtime.apiPrefix, [NSString stringWithFormat:@"download/%@", token]),
  } meta:nil error:NULL];
  return nil;
}

- (id)apiDownload:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  NSDictionary *metadata = nil;
  NSData *data = [self.runtime downloadDataForToken:[self stringParamForName:@"token"] ?: @"" metadata:&metadata error:&error];
  if (data == nil) {
    [self setStatus:(error.code == ALNStorageModuleErrorTokenRejected || error.code == ALNStorageModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Download failed" } error:NULL];
    return nil;
  }
  NSString *contentType = SMTrimmedString(metadata[@"object"][@"contentType"]);
  [self renderData:data contentType:([contentType length] > 0) ? contentType : @"application/octet-stream"];
  return nil;
}

- (id)apiDeleteObject:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  BOOL ok = [self.runtime deleteObjectIdentifier:[self stringParamForName:@"objectID"] ?: @"" error:&error];
  if (!ok) {
    [self setStatus:(error.code == ALNStorageModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Delete failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"deleted" : @YES } meta:nil error:NULL];
  return nil;
}

- (id)apiRegenerateVariants:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  NSDictionary *summary = [self.runtime queueVariantGenerationForObjectID:[self stringParamForName:@"objectID"] ?: @"" error:&error];
  if (summary == nil) {
    [self setStatus:(error.code == ALNStorageModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Variant queue failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:summary meta:nil error:NULL];
  return nil;
}

@end

@implementation ALNStorageAdminResource

- (instancetype)initWithRuntime:(ALNStorageModuleRuntime *)runtime {
  self = [super init];
  if (self != nil) {
    _runtime = runtime;
  }
  return self;
}

- (NSString *)adminUIResourceIdentifier {
  return @"storage_objects";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Storage Objects",
    @"singularLabel" : @"Storage Object",
    @"summary" : @"Inspect uploaded objects, metadata, download-token paths, and variant state.",
    @"identifierField" : @"objectID",
    @"primaryField" : @"name",
    @"legacyPath" : @"storage/objects",
    @"fields" : @[
      @{ @"name" : @"name", @"label" : @"Name", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"collection", @"label" : @"Collection", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"contentType", @"label" : @"Content Type", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"sizeBytes", @"label" : @"Size", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"visibility", @"label" : @"Visibility", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"variantState", @"label" : @"Variants", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"objectID", @"label" : @"Object ID", @"list" : @NO, @"detail" : @YES },
    ],
    @"filters" : @[ @{ @"name" : @"q", @"label" : @"Search", @"type" : @"search", @"placeholder" : @"name, collection, type" } ],
    @"actions" : @[
      @{ @"name" : @"delete", @"label" : @"Delete", @"scope" : @"row", @"method" : @"POST" },
      @{ @"name" : @"regenerate_variants", @"label" : @"Regenerate variants", @"scope" : @"row", @"method" : @"POST" },
    ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  (void)error;
  NSArray *records = [self.runtime listObjectsForCollection:nil query:query];
  if (offset >= [records count]) {
    return @[];
  }
  NSUInteger sliceLength = MIN(limit, [records count] - offset);
  return [records subarrayWithRange:NSMakeRange(offset, sliceLength)];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  return [self.runtime objectRecordForIdentifier:identifier error:error];
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  (void)identifier;
  (void)parameters;
  if (error != NULL) {
    *error = SMError(ALNStorageModuleErrorValidationFailed, @"storage objects are not directly editable", nil);
  }
  return nil;
}

- (NSDictionary *)adminUIDashboardSummaryWithError:(NSError **)error {
  (void)error;
  NSDictionary *summary = [self.runtime dashboardSummary];
  return @{ @"cards" : summary[@"cards"] ?: @[] };
}

- (NSDictionary *)adminUIPerformActionNamed:(NSString *)actionName
                                 identifier:(NSString *)identifier
                                 parameters:(NSDictionary *)parameters
                                      error:(NSError **)error {
  (void)parameters;
  NSString *normalizedAction = SMLowerTrimmedString(actionName);
  if ([normalizedAction isEqualToString:@"delete"]) {
    if (![self.runtime deleteObjectIdentifier:identifier error:error]) {
      return nil;
    }
    return @{ @"record" : @{}, @"message" : @"Storage object deleted." };
  }
  if ([normalizedAction isEqualToString:@"regenerate_variants"]) {
    NSDictionary *summary = [self.runtime queueVariantGenerationForObjectID:identifier error:error];
    return (summary != nil) ? @{ @"record" : [self.runtime objectRecordForIdentifier:identifier error:NULL] ?: @{}, @"message" : @"Variant generation queued." }
                            : nil;
  }
  if (error != NULL) {
    *error = SMError(ALNStorageModuleErrorNotFound,
                     [NSString stringWithFormat:@"unknown storage action %@", normalizedAction ?: @""],
                     @{ @"action" : normalizedAction ?: @"" });
  }
  return nil;
}

@end

@implementation ALNStorageAdminResourceProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[ALNStorageAdminResource alloc] initWithRuntime:[ALNStorageModuleRuntime sharedRuntime]] ];
}

@end

@implementation ALNStorageModule

- (NSString *)moduleIdentifier {
  return @"storage";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  if (![runtime configureWithApplication:application error:error]) {
    return NO;
  }

  [application beginRouteGroupWithPrefix:runtime.prefix guardAction:@"requireStorageHTML" formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/"
                              name:@"storage_dashboard"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"dashboard"];
  [application registerRouteMethod:@"GET"
                              path:@"/collections/:collection"
                              name:@"storage_collection"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"collectionIndex"];
  [application registerRouteMethod:@"GET"
                              path:@"/collections/:collection/objects/:objectID"
                              name:@"storage_object"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"objectDetail"];
  [application registerRouteMethod:@"POST"
                              path:@"/collections/:collection/objects/:objectID/delete"
                              name:@"storage_object_delete_html"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"deleteObjectHTML"];
  [application registerRouteMethod:@"POST"
                              path:@"/collections/:collection/objects/:objectID/regenerate-variants"
                              name:@"storage_object_regenerate_variants_html"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"regenerateVariantsHTML"];
  [application endRouteGroup];

  [application beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:nil formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/collections"
                              name:@"storage_api_collections"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiCollections"];
  [application registerRouteMethod:@"GET"
                              path:@"/collections/:collection/objects"
                              name:@"storage_api_objects"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiObjects"];
  [application registerRouteMethod:@"GET"
                              path:@"/collections/:collection/objects/:objectID"
                              name:@"storage_api_object_detail"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiObjectDetail"];
  [application registerRouteMethod:@"POST"
                              path:@"/upload-sessions"
                              name:@"storage_api_upload_sessions"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiCreateUploadSession"];
  [application registerRouteMethod:@"POST"
                              path:@"/upload-sessions/:sessionID/upload"
                              name:@"storage_api_upload"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiUpload"];
  [application registerRouteMethod:@"POST"
                              path:@"/collections/:collection/objects/:objectID/download-token"
                              name:@"storage_api_download_token"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiIssueDownloadToken"];
  [application registerRouteMethod:@"GET"
                              path:@"/download/:token"
                              name:@"storage_api_download"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiDownload"];
  [application registerRouteMethod:@"POST"
                              path:@"/collections/:collection/objects/:objectID/delete"
                              name:@"storage_api_delete"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiDeleteObject"];
  [application registerRouteMethod:@"POST"
                              path:@"/collections/:collection/objects/:objectID/regenerate-variants"
                              name:@"storage_api_regenerate_variants"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiRegenerateVariants"];
  [application endRouteGroup];

  NSArray *adminRoutes = @[
    @"storage_api_collections",
    @"storage_api_objects",
    @"storage_api_object_detail",
    @"storage_api_upload_sessions",
    @"storage_api_upload",
    @"storage_api_download_token",
    @"storage_api_delete",
    @"storage_api_regenerate_variants",
  ];
  for (NSString *routeName in adminRoutes) {
    [application configureRouteNamed:routeName
                       requestSchema:nil
                      responseSchema:nil
                             summary:@"Storage module API"
                         operationID:routeName
                                tags:@[ @"storage" ]
                      requiredScopes:nil
                       requiredRoles:@[ @"admin" ]
                     includeInOpenAPI:YES
                                error:NULL];
    [application configureAuthAssuranceForRouteNamed:routeName
                           minimumAuthAssuranceLevel:2
                     maximumAuthenticationAgeSeconds:0
                                          stepUpPath:[[ALNAuthModuleRuntime sharedRuntime] totpPath] ?: @"/auth/mfa/totp"
                                               error:NULL];
  }
  [application configureRouteNamed:@"storage_api_download"
                     requestSchema:nil
                    responseSchema:nil
                           summary:@"Storage download token route"
                       operationID:@"storage_api_download"
                              tags:@[ @"storage" ]
                    requiredScopes:nil
                     requiredRoles:nil
                   includeInOpenAPI:YES
                              error:NULL];
  return YES;
}

@end
