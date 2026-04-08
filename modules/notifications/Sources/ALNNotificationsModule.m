#import "ALNNotificationsModule.h"

#import "../../admin-ui/Sources/ALNAdminUIModule.h"
#import "../../auth/Sources/ALNAuthModule.h"

#import "ALNDataCompat.h"
#import "ALNApplication.h"
#import "ALNController.h"
#import "ALNContext.h"
#import "ALNRequest.h"
#import "ALNRealtime.h"

NSString *const ALNNotificationsModuleErrorDomain = @"Arlen.Modules.Notifications.Error";

static NSString *const ALNNotificationsDispatchJobIdentifier = @"notifications.dispatch";

static NSString *NMTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *NMLowerTrimmedString(id value) {
  return [[NMTrimmedString(value) lowercaseString] copy];
}

static NSDictionary *NMNormalizeDictionary(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static NSArray *NMNormalizeArray(id value) {
  return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static id NMPropertyListValue(id value) {
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
      [items addObject:NMPropertyListValue(entry)];
    }
    return items;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (id rawKey in [(NSDictionary *)value allKeys]) {
      NSString *key = NMTrimmedString(rawKey);
      if ([key length] == 0) {
        continue;
      }
      dictionary[key] = NMPropertyListValue([(NSDictionary *)value objectForKey:rawKey]);
    }
    return dictionary;
  }
  return [value description] ?: @"";
}

static NSString *NMResolvedPersistencePath(ALNApplication *application, NSDictionary *moduleConfig) {
  NSDictionary *persistence = [moduleConfig[@"persistence"] isKindOfClass:[NSDictionary class]]
                                  ? moduleConfig[@"persistence"]
                                  : @{};
  BOOL enabled = ![persistence[@"enabled"] respondsToSelector:@selector(boolValue)] ||
                 [persistence[@"enabled"] boolValue];
  if (!enabled) {
    return @"";
  }
  NSString *configured = NMTrimmedString(persistence[@"path"]);
  if ([configured length] > 0) {
    if ([configured hasPrefix:@"/"]) {
      return configured;
    }
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath] ?: NSTemporaryDirectory();
    return [cwd stringByAppendingPathComponent:configured];
  }
  NSString *environment = NMLowerTrimmedString(application.environment);
  if ([environment isEqualToString:@"test"]) {
    return @"";
  }
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath] ?: NSTemporaryDirectory();
  return [cwd stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"var/module_state/notifications-%@.plist",
                                              ([environment length] > 0) ? environment : @"development"]];
}

static NSDictionary *NMReadPropertyListAtPath(NSString *path, NSError **error) {
  NSString *statePath = NMTrimmedString(path);
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

static BOOL NMWritePropertyListAtPath(NSString *path, NSDictionary *payload, NSError **error) {
  NSString *statePath = NMTrimmedString(path);
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
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:NMPropertyListValue(payload)
                                                            format:NSPropertyListBinaryFormat_v1_0
                                                           options:0
                                                             error:error];
  if (data == nil) {
    return NO;
  }
  return [data writeToFile:statePath options:NSDataWritingAtomic error:error];
}

static NSString *NMFanoutChannelForRecipient(NSString *recipient) {
  NSString *normalized = NMTrimmedString(recipient);
  if ([normalized length] == 0) {
    return @"notifications.inbox";
  }
  return [NSString stringWithFormat:@"notifications.inbox.%@", normalized];
}

static NSDictionary *NMNormalizedInboxEntry(id value) {
  NSDictionary *entry = [value isKindOfClass:[NSDictionary class]] ? value : @{};
  id rawReadAt = entry[@"readAt"];
  NSNumber *readAt = nil;
  if ([rawReadAt isKindOfClass:[NSDate class]]) {
    readAt = @([(NSDate *)rawReadAt timeIntervalSince1970]);
  } else if ([rawReadAt respondsToSelector:@selector(doubleValue)]) {
    double readAtSeconds = [rawReadAt doubleValue];
    if (readAtSeconds > 0.0) {
      readAt = @(readAtSeconds);
    }
  }
  BOOL read = [entry[@"read"] respondsToSelector:@selector(boolValue)] ? [entry[@"read"] boolValue] : NO;
  if (!read && readAt != nil) {
    read = YES;
  }

  NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
  normalized[@"entryID"] = NMTrimmedString(entry[@"entryID"]);
  normalized[@"notification"] = NMTrimmedString(entry[@"notification"]);
  normalized[@"recipient"] = NMTrimmedString(entry[@"recipient"]);
  normalized[@"timestamp"] = [entry[@"timestamp"] respondsToSelector:@selector(doubleValue)]
                                 ? @([entry[@"timestamp"] doubleValue])
                                 : @(0);
  normalized[@"title"] = NMTrimmedString(entry[@"title"]);
  normalized[@"body"] = NMTrimmedString(entry[@"body"]);
  normalized[@"metadata"] = NMNormalizeDictionary(entry[@"metadata"]);
  normalized[@"read"] = @(read);
  if (readAt != nil) {
    normalized[@"readAt"] = readAt;
  }
  return normalized;
}

static NSDictionary *NMInboxSummary(NSString *recipient, NSArray<NSDictionary *> *entries) {
  NSUInteger unreadCount = 0;
  for (NSDictionary *entry in entries ?: @[]) {
    if (![entry[@"read"] boolValue]) {
      unreadCount += 1;
    }
  }
  return @{
    @"recipient" : NMTrimmedString(recipient),
    @"entries" : entries ?: @[],
    @"totalCount" : @([entries count]),
    @"unreadCount" : @(unreadCount),
  };
}

static NSError *NMError(ALNNotificationsModuleErrorCode code, NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"notifications module error";
  return [NSError errorWithDomain:ALNNotificationsModuleErrorDomain code:code userInfo:userInfo];
}

static NSString *NMPathJoin(NSString *prefix, NSString *suffix) {
  NSString *cleanPrefix = NMTrimmedString(prefix);
  if ([cleanPrefix length] == 0) {
    cleanPrefix = @"/notifications";
  }
  if (![cleanPrefix hasPrefix:@"/"]) {
    cleanPrefix = [@"/" stringByAppendingString:cleanPrefix];
  }
  while ([cleanPrefix hasSuffix:@"/"] && [cleanPrefix length] > 1) {
    cleanPrefix = [cleanPrefix substringToIndex:([cleanPrefix length] - 1)];
  }
  NSString *cleanSuffix = NMTrimmedString(suffix);
  while ([cleanSuffix hasPrefix:@"/"]) {
    cleanSuffix = [cleanSuffix substringFromIndex:1];
  }
  if ([cleanSuffix length] == 0) {
    return cleanPrefix;
  }
  return [NSString stringWithFormat:@"%@/%@", cleanPrefix, cleanSuffix];
}

static NSString *NMConfiguredPath(NSDictionary *moduleConfig, NSString *key, NSString *defaultSuffix) {
  NSDictionary *paths = [moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"paths"] : @{};
  NSString *prefix = NMTrimmedString(paths[@"prefix"]);
  if ([prefix length] == 0) {
    prefix = @"/notifications";
  }
  NSString *override = NMTrimmedString(paths[key]);
  if ([override hasPrefix:@"/"]) {
    return override;
  }
  if ([override length] > 0) {
    return NMPathJoin(prefix, override);
  }
  return NMPathJoin(prefix, defaultSuffix);
}

static NSString *NMQueryDecodeComponent(NSString *component) {
  NSString *withSpaces = [[component ?: @"" stringByReplacingOccurrencesOfString:@"+" withString:@" "]
      stringByRemovingPercentEncoding];
  return withSpaces ?: @"";
}

static NSDictionary *NMJSONParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  id object = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

static NSDictionary *NMFormParametersFromBody(NSData *body) {
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
    NSString *decodedName = NMQueryDecodeComponent(name);
    if ([decodedName length] == 0) {
      continue;
    }
    parameters[decodedName] = NMQueryDecodeComponent(value);
  }
  return parameters;
}

static NSString *NMPercentEncodedQueryComponent(NSString *value) {
  NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
  [allowed removeCharactersInString:@"&=+"];
  return [NMTrimmedString(value) stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSArray<NSString *> *NMNormalizedChannelArray(id rawValue) {
  NSMutableArray<NSString *> *channels = [NSMutableArray array];
  for (id rawChannel in NMNormalizeArray(rawValue)) {
    NSString *channel = NMLowerTrimmedString(rawChannel);
    if ([channel length] == 0 || [channels containsObject:channel]) {
      continue;
    }
    [channels addObject:channel];
  }
  return channels;
}

static NSDictionary *NMNormalizedRetryBackoff(id rawValue) {
  NSDictionary *rawBackoff = [rawValue isKindOfClass:[NSDictionary class]] ? rawValue : @{};
  NSString *strategy = NMLowerTrimmedString(rawBackoff[@"strategy"]);
  if (![strategy isEqualToString:@"linear"] && ![strategy isEqualToString:@"exponential"]) {
    strategy = @"fixed";
  }
  NSTimeInterval baseSeconds = [rawBackoff[@"baseSeconds"] respondsToSelector:@selector(doubleValue)]
                                   ? [rawBackoff[@"baseSeconds"] doubleValue]
                                   : 5.0;
  if (baseSeconds < 0.0) {
    baseSeconds = 0.0;
  }
  double multiplier = [rawBackoff[@"multiplier"] respondsToSelector:@selector(doubleValue)]
                          ? [rawBackoff[@"multiplier"] doubleValue]
                          : 2.0;
  if (multiplier < 1.0) {
    multiplier = 1.0;
  }
  NSTimeInterval maxSeconds = [rawBackoff[@"maxSeconds"] respondsToSelector:@selector(doubleValue)]
                                  ? [rawBackoff[@"maxSeconds"] doubleValue]
                                  : MAX(baseSeconds, 60.0);
  if (maxSeconds < baseSeconds) {
    maxSeconds = baseSeconds;
  }
  return @{
    @"strategy" : strategy,
    @"baseSeconds" : @(baseSeconds),
    @"multiplier" : @(multiplier),
    @"maxSeconds" : @(maxSeconds),
  };
}

static NSDictionary *NMNormalizedChannelPolicies(id rawValue) {
  NSDictionary *rawPolicies = [rawValue isKindOfClass:[NSDictionary class]] ? rawValue : @{};
  NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
  for (id rawChannel in rawPolicies) {
    NSString *channel = NMLowerTrimmedString(rawChannel);
    NSDictionary *policy = [rawPolicies[rawChannel] isKindOfClass:[NSDictionary class]] ? rawPolicies[rawChannel] : nil;
    if ([channel length] == 0 || policy == nil) {
      continue;
    }
    NSString *queue = NMTrimmedString(policy[@"queue"]);
    NSUInteger maxAttempts = [policy[@"maxAttempts"] respondsToSelector:@selector(unsignedIntegerValue)]
                                 ? [policy[@"maxAttempts"] unsignedIntegerValue]
                                 : 0;
    normalized[channel] = @{
      @"queue" : queue ?: @"",
      @"maxAttempts" : @(maxAttempts),
      @"retryBackoff" : NMNormalizedRetryBackoff(policy[@"retryBackoff"]),
    };
  }
  return [NSDictionary dictionaryWithDictionary:normalized];
}

static BOOL NMChannelsAreSubsetOfSupported(NSArray<NSString *> *requested,
                                           NSArray<NSString *> *supported) {
  NSSet *supportedSet = [NSSet setWithArray:supported ?: @[]];
  for (NSString *channel in requested ?: @[]) {
    if (![supportedSet containsObject:channel]) {
      return NO;
    }
  }
  return YES;
}

static NSDictionary *NMNormalizedWebhookRequest(NSDictionary *request,
                                                NSDictionary *fallbackPayload,
                                                NSError **error) {
  NSDictionary *rawRequest = [request isKindOfClass:[NSDictionary class]] ? request : @{};
  NSString *url = NMTrimmedString(rawRequest[@"url"]);
  if ([url length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorDeliveryFailed,
                       @"webhook notifications require a target URL",
                       nil);
    }
    return nil;
  }
  if (![url hasPrefix:@"http://"] && ![url hasPrefix:@"https://"]) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"webhook URL must use http or https",
                       @{ @"url" : url });
    }
    return nil;
  }

  NSMutableDictionary *headers = [NSMutableDictionary dictionary];
  NSDictionary *rawHeaders = [rawRequest[@"headers"] isKindOfClass:[NSDictionary class]] ? rawRequest[@"headers"] : @{};
  for (id rawHeaderKey in rawHeaders) {
    NSString *key = NMTrimmedString(rawHeaderKey);
    NSString *value = NMTrimmedString(rawHeaders[rawHeaderKey]);
    if ([key length] == 0 || [value length] == 0) {
      continue;
    }
    headers[key] = value;
  }

  id bodyValue = rawRequest[@"body"];
  NSData *bodyData = nil;
  if ([bodyValue isKindOfClass:[NSData class]]) {
    bodyData = bodyValue;
  } else if ([bodyValue isKindOfClass:[NSString class]]) {
    bodyData = [bodyValue dataUsingEncoding:NSUTF8StringEncoding];
  } else if ([bodyValue isKindOfClass:[NSDictionary class]] || [bodyValue isKindOfClass:[NSArray class]]) {
    bodyData = [NSJSONSerialization dataWithJSONObject:bodyValue options:0 error:NULL];
    if (headers[@"Content-Type"] == nil) {
      headers[@"Content-Type"] = @"application/json";
    }
  } else {
    bodyData = [NSJSONSerialization dataWithJSONObject:NMNormalizeDictionary(fallbackPayload) options:0 error:NULL];
    if (headers[@"Content-Type"] == nil) {
      headers[@"Content-Type"] = @"application/json";
    }
  }

  NSString *method = [NMTrimmedString(rawRequest[@"method"]) length] > 0
                         ? [[NMTrimmedString(rawRequest[@"method"]) uppercaseString] copy]
                         : @"POST";
  return @{
    @"url" : url,
    @"method" : method,
    @"headers" : headers ?: @{},
    @"body" : bodyData ?: [NSData data],
    @"metadata" : NMNormalizeDictionary(rawRequest[@"metadata"]),
  };
}

static NSDictionary *NMWebhookPreviewRepresentation(NSDictionary *request) {
  NSDictionary *normalized = [request isKindOfClass:[NSDictionary class]] ? request : @{};
  NSData *bodyData = [normalized[@"body"] isKindOfClass:[NSData class]] ? normalized[@"body"] : nil;
  NSString *bodyText = (bodyData != nil) ? ([[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] ?: @"") : @"";
  return @{
    @"url" : NMTrimmedString(normalized[@"url"]),
    @"method" : NMTrimmedString(normalized[@"method"]),
    @"headers" : NMNormalizeDictionary(normalized[@"headers"]),
    @"body" : bodyText ?: @"",
    @"metadata" : NMNormalizeDictionary(normalized[@"metadata"]),
  };
}

static NSArray<NSString *> *NMRecipientsFromInAppEntry(NSDictionary *entry) {
  NSMutableArray<NSString *> *recipients = [NSMutableArray array];
  for (id rawRecipient in NMNormalizeArray(entry[@"recipients"])) {
    NSString *recipient = NMTrimmedString(rawRecipient);
    if ([recipient length] > 0 && ![recipients containsObject:recipient]) {
      [recipients addObject:recipient];
    }
  }
  NSString *singleRecipient = NMTrimmedString(entry[@"recipient"]);
  if ([singleRecipient length] == 0) {
    singleRecipient = NMTrimmedString(entry[@"recipientSubject"]);
  }
  if ([singleRecipient length] > 0 && ![recipients containsObject:singleRecipient]) {
    [recipients addObject:singleRecipient];
  }
  return [NSArray arrayWithArray:recipients];
}

static NSArray<NSString *> *NMPreferenceRecipientsFromPayloadAndEntry(NSDictionary *payload,
                                                                      NSDictionary *entry) {
  NSMutableArray<NSString *> *recipients = [NSMutableArray array];
  NSString *payloadRecipient = NMTrimmedString(payload[@"recipient"]);
  if ([payloadRecipient length] == 0) {
    payloadRecipient = NMTrimmedString(payload[@"recipientSubject"]);
  }
  if ([payloadRecipient length] > 0) {
    [recipients addObject:payloadRecipient];
  }
  for (NSString *recipient in NMRecipientsFromInAppEntry(entry)) {
    if (![recipients containsObject:recipient]) {
      [recipients addObject:recipient];
    }
  }
  return [NSArray arrayWithArray:recipients];
}

@interface ALNNotificationsDispatchJob : NSObject <ALNJobsJobDefinition>
@end

@implementation ALNNotificationsDispatchJob

- (NSString *)jobsModuleJobIdentifier {
  return ALNNotificationsDispatchJobIdentifier;
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Notification dispatch",
    @"description" : @"Delivers queued notifications through first-party channels",
    @"queue" : @"default",
    @"maxAttempts" : @3,
    @"allowManualEnqueue" : @NO,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  NSString *identifier = NMTrimmedString(payload[@"identifier"]);
  if ([identifier length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"notification identifier is required",
                       nil);
    }
    return NO;
  }
  return YES;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload
                         context:(NSDictionary *)context
                           error:(NSError **)error {
  (void)context;
  NSDictionary *summary =
      [[ALNNotificationsModuleRuntime sharedRuntime] processQueuedNotificationPayload:payload error:error];
  return summary != nil;
}

@end

@interface ALNNotificationsModuleRuntime ()

@property(nonatomic, strong, readwrite) ALNApplication *application;
@property(nonatomic, strong, readwrite) id<ALNMailAdapter> mailAdapter;
@property(nonatomic, strong) id<ALNWebhookAdapter> webhookAdapter;
@property(nonatomic, copy, readwrite) NSString *prefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, copy) NSString *senderAddress;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id<ALNNotificationDefinition>> *definitionsByIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *metadataByIdentifier;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *outboxEntries;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *inboxByRecipient;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *preferencesByRecipient;
@property(nonatomic, assign) NSUInteger nextEntrySequence;
@property(nonatomic, strong) id<ALNNotificationPreferenceHook> preferenceHook;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *recentFanoutEvents;
@property(nonatomic, strong) ALNRealtimeHub *realtimeHub;
@property(nonatomic, assign) BOOL persistenceEnabled;
@property(nonatomic, copy) NSString *statePath;

- (BOOL)registerNotificationDefinition:(id<ALNNotificationDefinition>)definition
                                source:(NSString *)source
                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)artifactsForNotificationIdentifier:(NSString *)identifier
                                                      payload:(NSDictionary *)payload
                                                     channels:(NSArray<NSString *> *)channels
                                                        error:(NSError **)error;
- (BOOL)channel:(NSString *)channel
    enabledForRecipient:(NSString *)recipient
 notificationIdentifier:(NSString *)identifier
          defaultEnabled:(BOOL)defaultEnabled;
- (BOOL)loadPersistedStateWithError:(NSError *_Nullable *_Nullable)error;
- (BOOL)persistStateWithError:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)appendOutboxEntryForNotification:(NSString *)identifier
                                           channel:(NSString *)channel
                                         recipient:(NSString *)recipient
                                            status:(NSString *)status
                                             jobID:(NSString *)jobID
                                             queue:(NSString *)queue
                                        deliveryID:(NSString *)deliveryID
                                           message:(NSDictionary *)message
                                      errorMessage:(NSString *)errorMessage;
- (void)recordFanoutForRecipient:(NSString *)recipient
                    notification:(NSString *)identifier
                           entry:(NSDictionary *)entry;
- (nullable NSDictionary *)queueNotificationSummaryForIdentifier:(NSString *)identifier
                                                         payload:(NSDictionary *)payload
                                                        channels:(NSArray<NSString *> *)channels
                                                           error:(NSError **)error;
- (NSDictionary *)inboxSummaryLockedForRecipient:(NSString *)recipient;

@end

@implementation ALNNotificationsModuleRuntime

+ (instancetype)sharedRuntime {
  static ALNNotificationsModuleRuntime *runtime = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    runtime = [[ALNNotificationsModuleRuntime alloc] init];
  });
  return runtime;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _prefix = @"/notifications";
    _apiPrefix = @"/notifications/api";
    _senderAddress = @"notifications@example.test";
    _lock = [[NSLock alloc] init];
    _definitionsByIdentifier = [NSMutableDictionary dictionary];
    _metadataByIdentifier = [NSMutableDictionary dictionary];
    _outboxEntries = [NSMutableArray array];
    _inboxByRecipient = [NSMutableDictionary dictionary];
    _preferencesByRecipient = [NSMutableDictionary dictionary];
    _nextEntrySequence = 0;
    _recentFanoutEvents = [NSMutableArray array];
    _realtimeHub = [ALNRealtimeHub sharedHub];
    _persistenceEnabled = NO;
    _statePath = @"";
  }
  return self;
}

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError **)error {
  if (application == nil || application.mailAdapter == nil) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                       @"notifications module requires a mail adapter",
                       nil);
    }
    return NO;
  }

  ALNJobsModuleRuntime *jobsRuntime = [ALNJobsModuleRuntime sharedRuntime];
  if (jobsRuntime.application == nil || jobsRuntime.jobsAdapter == nil) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                       @"notifications module requires the jobs module to be configured first",
                       nil);
    }
    return NO;
  }

  NSDictionary *moduleConfig =
      [application.config[@"notificationsModule"] isKindOfClass:[NSDictionary class]]
          ? application.config[@"notificationsModule"]
          : @{};
  NSString *preferenceHookClass =
      NMTrimmedString(moduleConfig[@"preferenceHookClass"]).length > 0
          ? NMTrimmedString(moduleConfig[@"preferenceHookClass"])
          : NMTrimmedString([moduleConfig[@"preferences"] isKindOfClass:[NSDictionary class]]
                                ? moduleConfig[@"preferences"][@"hookClass"]
                                : nil);

  [self.lock lock];
  self.application = application;
  self.mailAdapter = application.mailAdapter;
  self.webhookAdapter = application.webhookAdapter;
  self.prefix = NMConfiguredPath(moduleConfig, @"prefix", @"");
  self.apiPrefix = NMConfiguredPath(moduleConfig, @"apiPrefix", @"api");
  self.senderAddress = [NMTrimmedString(moduleConfig[@"sender"]) length] > 0
                           ? NMTrimmedString(moduleConfig[@"sender"])
                           : @"notifications@example.test";
  [self.definitionsByIdentifier removeAllObjects];
  [self.metadataByIdentifier removeAllObjects];
  [self.outboxEntries removeAllObjects];
  [self.inboxByRecipient removeAllObjects];
  [self.preferencesByRecipient removeAllObjects];
  [self.recentFanoutEvents removeAllObjects];
  self.preferenceHook = nil;
  self.nextEntrySequence = 0;
  self.statePath = NMResolvedPersistencePath(application, moduleConfig);
  self.persistenceEnabled = ([self.statePath length] > 0);
  [self.lock unlock];

  if (![self loadPersistedStateWithError:error]) {
    return NO;
  }

  if ([preferenceHookClass length] > 0) {
    Class klass = NSClassFromString(preferenceHookClass);
    id hook = (klass != Nil) ? [[klass alloc] init] : nil;
    if (hook == nil || ![hook conformsToProtocol:@protocol(ALNNotificationPreferenceHook)]) {
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"notification preference hook %@ is invalid", preferenceHookClass],
                         @{ @"class" : preferenceHookClass ?: @"" });
      }
      return NO;
    }
    self.preferenceHook = hook;
  }

  if (![jobsRuntime registerSystemJobDefinition:[[ALNNotificationsDispatchJob alloc] init] error:error]) {
    return NO;
  }

  NSArray *providerClasses =
      [moduleConfig[@"notificationProviderClasses"] isKindOfClass:[NSArray class]]
          ? moduleConfig[@"notificationProviderClasses"]
          : ([moduleConfig[@"providers"] isKindOfClass:[NSDictionary class]] &&
                     [moduleConfig[@"providers"][@"classes"] isKindOfClass:[NSArray class]]
                 ? moduleConfig[@"providers"][@"classes"]
                 : @[]);
  for (id rawClassName in providerClasses) {
    NSString *className = NMTrimmedString(rawClassName);
    if ([className length] == 0) {
      continue;
    }
    Class klass = NSClassFromString(className);
    id provider = klass != Nil ? [[klass alloc] init] : nil;
    if (provider == nil || ![provider conformsToProtocol:@protocol(ALNNotificationProvider)]) {
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"notification provider %@ is invalid", className],
                         @{ @"class" : className });
      }
      return NO;
    }
    NSError *providerError = nil;
    NSArray *definitions =
        [(id<ALNNotificationProvider>)provider notificationsModuleDefinitionsForRuntime:self error:&providerError];
    if (definitions == nil) {
      if (error != NULL) {
        *error = providerError ?: NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                                          @"notification provider failed to load definitions",
                                          @{ @"class" : className });
      }
      return NO;
    }
    for (id definition in definitions) {
      if (![self registerNotificationDefinition:definition source:className error:error]) {
        return NO;
      }
    }
  }

  return YES;
}

- (BOOL)loadPersistedStateWithError:(NSError **)error {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return YES;
  }
  NSError *readError = nil;
  NSDictionary *state = NMReadPropertyListAtPath(self.statePath, &readError);
  if (state == nil) {
    if (readError != nil && error != NULL) {
      *error = readError;
      return NO;
    }
    return YES;
  }
  [self.lock lock];
  NSArray *outbox = [state[@"outboxEntries"] isKindOfClass:[NSArray class]] ? state[@"outboxEntries"] : @[];
  [self.outboxEntries addObjectsFromArray:outbox];
  NSDictionary *inboxByRecipient = [state[@"inboxByRecipient"] isKindOfClass:[NSDictionary class]]
                                       ? state[@"inboxByRecipient"]
                                       : @{};
  for (NSString *recipient in inboxByRecipient) {
    NSArray *entries = [inboxByRecipient[recipient] isKindOfClass:[NSArray class]] ? inboxByRecipient[recipient] : @[];
    NSMutableArray *normalizedEntries = [NSMutableArray array];
    for (id rawEntry in entries) {
      [normalizedEntries addObject:NMNormalizedInboxEntry(rawEntry)];
    }
    self.inboxByRecipient[recipient] = normalizedEntries;
  }
  NSDictionary *preferences = [state[@"preferencesByRecipient"] isKindOfClass:[NSDictionary class]]
                                  ? state[@"preferencesByRecipient"]
                                  : @{};
  [self.preferencesByRecipient addEntriesFromDictionary:preferences];
  NSArray *fanout = [state[@"recentFanoutEvents"] isKindOfClass:[NSArray class]] ? state[@"recentFanoutEvents"] : @[];
  [self.recentFanoutEvents addObjectsFromArray:fanout];
  self.nextEntrySequence = [state[@"nextEntrySequence"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? [state[@"nextEntrySequence"] unsignedIntegerValue]
                               : self.nextEntrySequence;
  [self.lock unlock];
  return YES;
}

- (BOOL)persistStateWithError:(NSError **)error {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return YES;
  }
  NSDictionary *payload = nil;
  [self.lock lock];
  NSMutableDictionary *inbox = [NSMutableDictionary dictionary];
  for (NSString *recipient in self.inboxByRecipient) {
    inbox[recipient] = [[NSArray alloc] initWithArray:self.inboxByRecipient[recipient] ?: @[] copyItems:YES] ?: @[];
  }
  payload = @{
    @"version" : @1,
    @"nextEntrySequence" : @(self.nextEntrySequence),
    @"outboxEntries" : [[NSArray alloc] initWithArray:self.outboxEntries copyItems:YES] ?: @[],
    @"inboxByRecipient" : inbox,
    @"preferencesByRecipient" : [NSDictionary dictionaryWithDictionary:self.preferencesByRecipient ?: @{}],
    @"recentFanoutEvents" : [[NSArray alloc] initWithArray:self.recentFanoutEvents copyItems:YES] ?: @[],
  };
  [self.lock unlock];
  return NMWritePropertyListAtPath(self.statePath, payload, error);
}

- (NSDictionary *)appendOutboxEntryForNotification:(NSString *)identifier
                                           channel:(NSString *)channel
                                         recipient:(NSString *)recipient
                                            status:(NSString *)status
                                             jobID:(NSString *)jobID
                                             queue:(NSString *)queue
                                        deliveryID:(NSString *)deliveryID
                                           message:(NSDictionary *)message
                                      errorMessage:(NSString *)errorMessage {
  [self.lock lock];
  self.nextEntrySequence += 1;
  NSDictionary *entry = @{
    @"entryID" : [NSString stringWithFormat:@"notification-%lu", (unsigned long)self.nextEntrySequence],
    @"notification" : NMTrimmedString(identifier),
    @"channel" : NMLowerTrimmedString(channel),
    @"recipient" : NMTrimmedString(recipient),
    @"jobID" : NMTrimmedString(jobID),
    @"queue" : NMTrimmedString(queue),
    @"deliveryID" : NMTrimmedString(deliveryID),
    @"status" : NMLowerTrimmedString(status),
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
    @"message" : NMNormalizeDictionary(message),
    @"error" : NMTrimmedString(errorMessage),
  };
  [self.outboxEntries addObject:entry];
  [self.lock unlock];
  return entry;
}

- (void)recordFanoutForRecipient:(NSString *)recipient
                    notification:(NSString *)identifier
                           entry:(NSDictionary *)entry {
  NSString *channel = NMFanoutChannelForRecipient(recipient);
  NSDictionary *payload = @{
    @"type" : @"notification.in_app",
    @"notification" : NMTrimmedString(identifier),
    @"recipient" : NMTrimmedString(recipient),
    @"entry" : entry ?: @{},
  };
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
  NSString *message = (jsonData != nil) ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
  NSUInteger subscribers = [self.realtimeHub publishMessage:message ?: @"{}" onChannel:channel];
  [self.lock lock];
  [self.recentFanoutEvents addObject:@{
    @"notification" : NMTrimmedString(identifier),
    @"recipient" : NMTrimmedString(recipient),
    @"channel" : channel,
    @"entryID" : NMTrimmedString(entry[@"entryID"]),
    @"subscriberCount" : @(subscribers),
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
  }];
  while ([self.recentFanoutEvents count] > 20) {
    [self.recentFanoutEvents removeObjectAtIndex:0];
  }
  [self.lock unlock];
}

- (NSDictionary *)resolvedConfigSummary {
  [self.lock lock];
  NSDictionary *summary = @{
    @"prefix" : self.prefix ?: @"/notifications",
    @"apiPrefix" : self.apiPrefix ?: @"/notifications/api",
    @"sender" : self.senderAddress ?: @"notifications@example.test",
    @"definitionCount" : @([self.metadataByIdentifier count]),
    @"outboxCount" : @([self.outboxEntries count]),
    @"inboxRecipientCount" : @([self.inboxByRecipient count]),
    @"preferenceRecipientCount" : @([self.preferencesByRecipient count]),
    @"preferenceHookClass" : self.preferenceHook ? NSStringFromClass([(NSObject *)self.preferenceHook class]) : @"",
    @"webhookAdapter" : (self.webhookAdapter != nil) ? [self.webhookAdapter adapterName] : @"",
    @"fanoutEventCount" : @([self.recentFanoutEvents count]),
    @"persistenceEnabled" : @(self.persistenceEnabled),
    @"statePath" : self.statePath ?: @"",
  };
  [self.lock unlock];
  return summary;
}

- (NSArray<NSDictionary *> *)registeredNotifications {
  [self.lock lock];
  NSArray *keys = [[self.metadataByIdentifier allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray *definitions = [NSMutableArray array];
  for (NSString *identifier in keys) {
    NSDictionary *metadata = self.metadataByIdentifier[identifier];
    if ([metadata isKindOfClass:[NSDictionary class]]) {
      [definitions addObject:[metadata copy]];
    }
  }
  [self.lock unlock];
  return definitions;
}

- (BOOL)registerNotificationDefinition:(id<ALNNotificationDefinition>)definition
                                source:(NSString *)source
                                 error:(NSError **)error {
  if (definition == nil || ![definition conformsToProtocol:@protocol(ALNNotificationDefinition)]) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                       @"notification definition must conform to ALNNotificationDefinition",
                       nil);
    }
    return NO;
  }

  NSString *identifier = NMTrimmedString([definition notificationsModuleIdentifier]);
  if ([identifier length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                       @"notification identifier is required",
                       nil);
    }
    return NO;
  }

  NSDictionary *rawMetadata = NMNormalizeDictionary([definition notificationsModuleMetadata]);
  NSArray<NSString *> *channels =
      [definition respondsToSelector:@selector(notificationsModuleDefaultChannels)]
          ? NMNormalizedChannelArray([definition notificationsModuleDefaultChannels])
          : NMNormalizedChannelArray(rawMetadata[@"channels"]);
  NSDictionary *channelPolicies = NMNormalizedChannelPolicies(rawMetadata[@"channelPolicies"]);
  NSDictionary *metadata = @{
    @"identifier" : identifier,
    @"title" : [NMTrimmedString(rawMetadata[@"title"]) length] > 0 ? NMTrimmedString(rawMetadata[@"title"]) : identifier,
    @"description" : NMTrimmedString(rawMetadata[@"description"]),
    @"channels" : channels ?: @[],
    @"channelPolicies" : channelPolicies ?: @{},
    @"source" : NMTrimmedString(source),
  };

  [self.lock lock];
  if (self.definitionsByIdentifier[identifier] != nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"duplicate notification %@", identifier],
                       @{ @"identifier" : identifier });
    }
    return NO;
  }
  self.definitionsByIdentifier[identifier] = definition;
  self.metadataByIdentifier[identifier] = metadata;
  [self.lock unlock];
  return YES;
}

- (BOOL)registerSystemNotificationDefinition:(id<ALNNotificationDefinition>)definition
                                       error:(NSError **)error {
  return [self registerNotificationDefinition:definition source:@"system" error:error];
}

- (NSDictionary *)artifactsForNotificationIdentifier:(NSString *)identifier
                                              payload:(NSDictionary *)payload
                                             channels:(NSArray<NSString *> *)channels
                                                error:(NSError **)error {
  NSString *notificationID = NMTrimmedString(identifier);
  if ([notificationID length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"notification identifier is required",
                       nil);
    }
    return nil;
  }

  [self.lock lock];
  id<ALNNotificationDefinition> definition = self.definitionsByIdentifier[notificationID];
  NSDictionary *metadata = self.metadataByIdentifier[notificationID];
  [self.lock unlock];
  if (definition == nil || metadata == nil) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown notification %@", notificationID],
                       @{ @"identifier" : notificationID });
    }
    return nil;
  }

  NSDictionary *normalizedPayload = NMNormalizeDictionary(payload);
  NSError *validationError = nil;
  if (![definition notificationsModuleValidatePayload:normalizedPayload error:&validationError]) {
    if (error != NULL) {
      *error = validationError ?: NMError(ALNNotificationsModuleErrorValidationFailed,
                                          @"notification payload was rejected",
                                          @{ @"identifier" : notificationID });
    }
    return nil;
  }

  NSArray<NSString *> *normalizedChannels = NMNormalizedChannelArray(channels);
  if ([normalizedChannels count] == 0) {
    normalizedChannels = NMNormalizeArray(metadata[@"channels"]);
  }
  if ([normalizedChannels count] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"notification requires at least one channel",
                       @{ @"identifier" : notificationID });
    }
    return nil;
  }
  if (!NMChannelsAreSubsetOfSupported(normalizedChannels, NMNormalizeArray(metadata[@"channels"]))) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"requested notification channel is not supported",
                       @{ @"identifier" : notificationID, @"channels" : normalizedChannels });
    }
    return nil;
  }

  ALNMailMessage *message = nil;
  NSDictionary *inAppEntry = nil;
  NSDictionary *webhookRequest = nil;
  if ([normalizedChannels containsObject:@"email"]) {
    NSError *mailError = nil;
    message = [definition notificationsModuleMailMessageForPayload:normalizedPayload runtime:self error:&mailError];
    if (message == nil) {
      if (error != NULL) {
        *error = mailError ?: NMError(ALNNotificationsModuleErrorDeliveryFailed,
                                      @"notification did not produce an email message",
                                      @{ @"identifier" : notificationID });
      }
      return nil;
    }
  }
  if ([normalizedChannels containsObject:@"in_app"]) {
    NSError *entryError = nil;
    inAppEntry = [definition notificationsModuleInAppEntryForPayload:normalizedPayload runtime:self error:&entryError];
    if (inAppEntry == nil) {
      if (error != NULL) {
        *error = entryError ?: NMError(ALNNotificationsModuleErrorDeliveryFailed,
                                       @"notification did not produce an in-app entry",
                                       @{ @"identifier" : notificationID });
      }
      return nil;
    }
    if ([NMRecipientsFromInAppEntry(inAppEntry) count] == 0) {
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorDeliveryFailed,
                         @"in-app notification requires at least one recipient",
                         @{ @"identifier" : notificationID });
      }
      return nil;
    }
  }
  if ([normalizedChannels containsObject:@"webhook"]) {
    NSError *webhookError = nil;
    if (![definition respondsToSelector:@selector(notificationsModuleWebhookRequestForPayload:runtime:error:)]) {
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                         @"notification does not support the webhook channel",
                         @{ @"identifier" : notificationID });
      }
      return nil;
    }
    NSDictionary *rawRequest =
        [definition notificationsModuleWebhookRequestForPayload:normalizedPayload runtime:self error:&webhookError];
    webhookRequest = NMNormalizedWebhookRequest(rawRequest, normalizedPayload, &webhookError);
    if (webhookRequest == nil) {
      if (error != NULL) {
        *error = webhookError ?: NMError(ALNNotificationsModuleErrorDeliveryFailed,
                                         @"notification did not produce a webhook request",
                                         @{ @"identifier" : notificationID });
      }
      return nil;
    }
  }

  return @{
    @"identifier" : notificationID,
    @"metadata" : metadata ?: @{},
    @"payload" : normalizedPayload,
    @"channels" : normalizedChannels,
    @"message" : message ?: [NSNull null],
    @"inAppEntry" : inAppEntry ?: [NSNull null],
    @"webhook" : webhookRequest ?: [NSNull null],
  };
}

- (NSDictionary *)queueNotificationSummaryForIdentifier:(NSString *)identifier
                                                 payload:(NSDictionary *)payload
                                                channels:(NSArray<NSString *> *)channels
                                                   error:(NSError **)error {
  NSDictionary *artifacts = [self artifactsForNotificationIdentifier:identifier payload:payload channels:channels error:error];
  if (artifacts == nil) {
    return nil;
  }
  NSDictionary *metadata = [artifacts[@"metadata"] isKindOfClass:[NSDictionary class]] ? artifacts[@"metadata"] : @{};
  NSDictionary *channelPolicies =
      [metadata[@"channelPolicies"] isKindOfClass:[NSDictionary class]] ? metadata[@"channelPolicies"] : @{};
  NSDictionary *normalizedPayload = [artifacts[@"payload"] isKindOfClass:[NSDictionary class]] ? artifacts[@"payload"] : @{};
  NSArray<NSString *> *requestedChannels = [artifacts[@"channels"] isKindOfClass:[NSArray class]] ? artifacts[@"channels"] : @[];
  ALNMailMessage *message = [artifacts[@"message"] isKindOfClass:[ALNMailMessage class]] ? artifacts[@"message"] : nil;
  NSDictionary *inAppEntry = [artifacts[@"inAppEntry"] isKindOfClass:[NSDictionary class]] ? artifacts[@"inAppEntry"] : nil;
  NSDictionary *webhookRequest = [artifacts[@"webhook"] isKindOfClass:[NSDictionary class]] ? artifacts[@"webhook"] : nil;
  NSArray<NSString *> *preferenceRecipients = NMPreferenceRecipientsFromPayloadAndEntry(normalizedPayload, inAppEntry ?: @{});

  NSMutableArray *jobIDs = [NSMutableArray array];
  NSMutableArray *channelJobs = [NSMutableArray array];
  for (NSString *channel in requestedChannels) {
    NSDictionary *policy = [channelPolicies[channel] isKindOfClass:[NSDictionary class]] ? channelPolicies[channel] : @{};
    NSString *queue = [NMTrimmedString(policy[@"queue"]) length] > 0 ? NMTrimmedString(policy[@"queue"]) : @"default";
    NSUInteger maxAttempts = [policy[@"maxAttempts"] respondsToSelector:@selector(unsignedIntegerValue)]
                                 ? [policy[@"maxAttempts"] unsignedIntegerValue]
                                 : 0;
    NSDictionary *jobPayload = @{
      @"identifier" : artifacts[@"identifier"] ?: @"",
      @"payload" : normalizedPayload,
      @"channels" : @[ channel ],
    };
    NSMutableDictionary *options = [@{
      @"queue" : queue,
      @"source" : @"notification",
    } mutableCopy];
    if (maxAttempts > 0) {
      options[@"maxAttempts"] = @(maxAttempts);
    }
    if ([policy[@"retryBackoff"] isKindOfClass:[NSDictionary class]]) {
      options[@"retryBackoff"] = policy[@"retryBackoff"];
    }
    NSError *enqueueError = nil;
    NSString *jobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:ALNNotificationsDispatchJobIdentifier
                                                                         payload:jobPayload
                                                                         options:options
                                                                           error:&enqueueError];
    if ([jobID length] == 0) {
      if (error != NULL) {
        *error = enqueueError;
      }
      return nil;
    }
    [jobIDs addObject:jobID];
    [channelJobs addObject:@{
      @"channel" : channel,
      @"jobID" : jobID,
      @"queue" : queue,
      @"maxAttempts" : @(maxAttempts),
    }];

    if ([channel isEqualToString:@"email"] && message != nil) {
      [self appendOutboxEntryForNotification:artifacts[@"identifier"]
                                     channel:channel
                                   recipient:([preferenceRecipients count] > 0) ? preferenceRecipients[0] : @""
                                      status:@"queued"
                                       jobID:jobID
                                       queue:queue
                                  deliveryID:@""
                                     message:[message dictionaryRepresentation]
                                errorMessage:nil];
    } else if ([channel isEqualToString:@"in_app"] && inAppEntry != nil) {
      for (NSString *recipient in NMRecipientsFromInAppEntry(inAppEntry)) {
        [self appendOutboxEntryForNotification:artifacts[@"identifier"]
                                       channel:channel
                                     recipient:recipient
                                        status:@"queued"
                                         jobID:jobID
                                         queue:queue
                                    deliveryID:@""
                                       message:inAppEntry
                                  errorMessage:nil];
      }
    } else if ([channel isEqualToString:@"webhook"] && webhookRequest != nil) {
      [self appendOutboxEntryForNotification:artifacts[@"identifier"]
                                     channel:channel
                                   recipient:([preferenceRecipients count] > 0) ? preferenceRecipients[0] : NMTrimmedString(webhookRequest[@"url"])
                                      status:@"queued"
                                       jobID:jobID
                                       queue:queue
                                  deliveryID:@""
                                     message:NMWebhookPreviewRepresentation(webhookRequest)
                                errorMessage:nil];
    }
  }
  if (![self persistStateWithError:error]) {
    return nil;
  }
  return @{
    @"notification" : artifacts[@"identifier"] ?: @"",
    @"jobID" : ([jobIDs count] > 0) ? jobIDs[0] : @"",
    @"jobIDs" : jobIDs ?: @[],
    @"channelJobs" : channelJobs ?: @[],
  };
}

- (NSString *)queueNotificationIdentifier:(NSString *)identifier
                                  payload:(NSDictionary *)payload
                                 channels:(NSArray<NSString *> *)channels
                                    error:(NSError **)error {
  if ([channels count] == 0) {
    NSDictionary *artifacts = [self artifactsForNotificationIdentifier:identifier
                                                               payload:payload
                                                              channels:channels
                                                                 error:error];
    if (artifacts == nil) {
      return nil;
    }
    NSDictionary *jobPayload = @{
      @"identifier" : artifacts[@"identifier"] ?: @"",
      @"payload" : [artifacts[@"payload"] isKindOfClass:[NSDictionary class]] ? artifacts[@"payload"] : @{},
      @"channels" : [artifacts[@"channels"] isKindOfClass:[NSArray class]] ? artifacts[@"channels"] : @[],
    };
    return [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:ALNNotificationsDispatchJobIdentifier
                                                              payload:jobPayload
                                                              options:@{ @"queue" : @"default", @"source" : @"notification" }
                                                                error:error];
  }
  NSDictionary *summary = [self queueNotificationSummaryForIdentifier:identifier
                                                              payload:payload
                                                             channels:channels
                                                                error:error];
  return [summary[@"jobID"] isKindOfClass:[NSString class]] ? summary[@"jobID"] : nil;
}

- (BOOL)channel:(NSString *)channel
enabledForRecipient:(NSString *)recipient
notificationIdentifier:(NSString *)identifier
  defaultEnabled:(BOOL)defaultEnabled {
  NSString *normalizedRecipient = NMTrimmedString(recipient);
  if ([normalizedRecipient length] == 0) {
    return defaultEnabled;
  }
  NSString *notificationID = NMTrimmedString(identifier);
  NSString *channelID = NMLowerTrimmedString(channel);
  [self.lock lock];
  NSDictionary *recipientPreferences = self.preferencesByRecipient[normalizedRecipient];
  NSNumber *explicitValue = [recipientPreferences[notificationID] isKindOfClass:[NSDictionary class]]
                                ? recipientPreferences[notificationID][channelID]
                                : nil;
  [self.lock unlock];
  if ([explicitValue respondsToSelector:@selector(boolValue)]) {
    return [explicitValue boolValue];
  }
  if (self.preferenceHook != nil &&
      [self.preferenceHook respondsToSelector:@selector(notificationsModuleChannelEnabledForRecipient:notificationIdentifier:channel:defaultEnabled:runtime:)]) {
    NSNumber *override =
        [self.preferenceHook notificationsModuleChannelEnabledForRecipient:normalizedRecipient
                                                     notificationIdentifier:notificationID
                                                                    channel:channelID
                                                             defaultEnabled:defaultEnabled
                                                                    runtime:self];
    if ([override respondsToSelector:@selector(boolValue)]) {
      return [override boolValue];
    }
  }
  return defaultEnabled;
}

- (NSDictionary *)previewNotificationIdentifier:(NSString *)identifier
                                         payload:(NSDictionary *)payload
                                        channels:(NSArray<NSString *> *)channels
                                           error:(NSError **)error {
  NSDictionary *artifacts = [self artifactsForNotificationIdentifier:identifier payload:payload channels:channels error:error];
  if (artifacts == nil) {
    return nil;
  }
  ALNMailMessage *message = [artifacts[@"message"] isKindOfClass:[ALNMailMessage class]] ? artifacts[@"message"] : nil;
  NSDictionary *inAppEntry = [artifacts[@"inAppEntry"] isKindOfClass:[NSDictionary class]] ? artifacts[@"inAppEntry"] : nil;
  NSDictionary *webhookRequest = [artifacts[@"webhook"] isKindOfClass:[NSDictionary class]] ? artifacts[@"webhook"] : nil;
  return @{
    @"notification" : artifacts[@"identifier"] ?: @"",
    @"channels" : artifacts[@"channels"] ?: @[],
    @"email" : message ? [message dictionaryRepresentation] : @{},
    @"in_app" : inAppEntry ?: @{},
    @"webhook" : webhookRequest ? NMWebhookPreviewRepresentation(webhookRequest) : @{},
    @"recipients" : NMPreferenceRecipientsFromPayloadAndEntry(artifacts[@"payload"], inAppEntry ?: @{}),
  };
}

- (NSDictionary *)processQueuedNotificationPayload:(NSDictionary *)jobPayload
                                             error:(NSError **)error {
  NSDictionary *artifacts =
      [self artifactsForNotificationIdentifier:jobPayload[@"identifier"]
                                       payload:NMNormalizeDictionary(jobPayload[@"payload"])
                                      channels:NMNormalizedChannelArray(jobPayload[@"channels"])
                                         error:error];
  if (artifacts == nil) {
    return nil;
  }
  NSString *identifier = artifacts[@"identifier"] ?: @"";
  NSDictionary *payload = artifacts[@"payload"] ?: @{};
  NSArray<NSString *> *channels = artifacts[@"channels"] ?: @[];
  ALNMailMessage *message = [artifacts[@"message"] isKindOfClass:[ALNMailMessage class]] ? artifacts[@"message"] : nil;
  NSDictionary *inAppEntry = [artifacts[@"inAppEntry"] isKindOfClass:[NSDictionary class]] ? artifacts[@"inAppEntry"] : nil;
  NSDictionary *webhookRequest = [artifacts[@"webhook"] isKindOfClass:[NSDictionary class]] ? artifacts[@"webhook"] : nil;
  NSArray<NSString *> *preferenceRecipients = NMPreferenceRecipientsFromPayloadAndEntry(payload, inAppEntry ?: @{});

  NSMutableArray *deliveredChannels = [NSMutableArray array];
  NSMutableArray *skippedChannels = [NSMutableArray array];
  NSMutableArray *deliveryIDs = [NSMutableArray array];

  if ([channels containsObject:@"email"] && message != nil) {
    BOOL emailEnabled = YES;
    for (NSString *recipient in preferenceRecipients) {
      if (![self channel:@"email"
       enabledForRecipient:recipient
     notificationIdentifier:identifier
             defaultEnabled:YES]) {
        emailEnabled = NO;
        break;
      }
    }
    if (emailEnabled) {
      NSError *mailError = nil;
      NSString *deliveryID = [self.mailAdapter deliverMessage:message error:&mailError];
      if ([deliveryID length] == 0) {
        [self appendOutboxEntryForNotification:identifier
                                       channel:@"email"
                                     recipient:([preferenceRecipients count] > 0) ? preferenceRecipients[0] : @""
                                        status:@"failed"
                                         jobID:@""
                                         queue:@""
                                    deliveryID:@""
                                       message:[message dictionaryRepresentation]
                                  errorMessage:mailError.localizedDescription ?: @"mail delivery failed"];
        (void)[self persistStateWithError:NULL];
        if (error != NULL) {
          *error = mailError ?: NMError(ALNNotificationsModuleErrorDeliveryFailed,
                                        @"mail delivery failed",
                                        @{ @"identifier" : identifier });
        }
        return nil;
      }
      [self appendOutboxEntryForNotification:identifier
                                     channel:@"email"
                                   recipient:([preferenceRecipients count] > 0) ? preferenceRecipients[0] : @""
                                      status:@"delivered"
                                       jobID:@""
                                       queue:@""
                                  deliveryID:deliveryID
                                     message:[message dictionaryRepresentation]
                                errorMessage:nil];
      [deliveredChannels addObject:@"email"];
      [deliveryIDs addObject:deliveryID];
    } else {
      [self appendOutboxEntryForNotification:identifier
                                     channel:@"email"
                                   recipient:([preferenceRecipients count] > 0) ? preferenceRecipients[0] : @""
                                      status:@"suppressed"
                                       jobID:@""
                                       queue:@""
                                  deliveryID:@""
                                     message:[message dictionaryRepresentation]
                                errorMessage:@"suppressed by preference policy"];
      [skippedChannels addObject:@"email"];
    }
  }

  if ([channels containsObject:@"in_app"] && [inAppEntry isKindOfClass:[NSDictionary class]]) {
    NSArray<NSString *> *entryRecipients = NMRecipientsFromInAppEntry(inAppEntry);
    NSUInteger deliveredRecipientCount = 0;
    for (NSString *recipient in entryRecipients) {
      if (![self channel:@"in_app"
       enabledForRecipient:recipient
     notificationIdentifier:identifier
             defaultEnabled:YES]) {
        continue;
      }
      [self.lock lock];
      NSMutableArray *inbox = [self.inboxByRecipient[recipient] isKindOfClass:[NSMutableArray class]]
                                  ? self.inboxByRecipient[recipient]
                                  : [NSMutableArray array];
      self.nextEntrySequence += 1;
      NSDictionary *record = @{
        @"entryID" : [NSString stringWithFormat:@"notification-%lu", (unsigned long)self.nextEntrySequence],
        @"notification" : identifier,
        @"recipient" : recipient,
        @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
        @"title" : NMTrimmedString(inAppEntry[@"title"]),
        @"body" : NMTrimmedString(inAppEntry[@"body"]),
        @"metadata" : NMNormalizeDictionary(inAppEntry[@"metadata"]),
        @"read" : @NO,
      };
      [inbox addObject:record];
      self.inboxByRecipient[recipient] = inbox;
      [self.lock unlock];
      [self appendOutboxEntryForNotification:identifier
                                     channel:@"in_app"
                                   recipient:recipient
                                      status:@"delivered"
                                       jobID:@""
                                       queue:@""
                                  deliveryID:@""
                                     message:record
                                errorMessage:nil];
      [self recordFanoutForRecipient:recipient notification:identifier entry:record];
      deliveredRecipientCount += 1;
    }
    if (deliveredRecipientCount > 0) {
      [deliveredChannels addObject:@"in_app"];
    } else {
      [self appendOutboxEntryForNotification:identifier
                                     channel:@"in_app"
                                   recipient:([entryRecipients count] > 0) ? entryRecipients[0] : @""
                                      status:@"suppressed"
                                       jobID:@""
                                       queue:@""
                                  deliveryID:@""
                                     message:inAppEntry
                                errorMessage:@"suppressed by preference policy"];
      [skippedChannels addObject:@"in_app"];
    }
  }

  if ([channels containsObject:@"webhook"] && [webhookRequest isKindOfClass:[NSDictionary class]]) {
    BOOL webhookEnabled = YES;
    for (NSString *recipient in preferenceRecipients) {
      if (![self channel:@"webhook"
       enabledForRecipient:recipient
     notificationIdentifier:identifier
             defaultEnabled:YES]) {
        webhookEnabled = NO;
        break;
      }
    }
    if (webhookEnabled) {
      NSError *webhookError = nil;
      NSString *deliveryID = [self.webhookAdapter deliverRequest:webhookRequest error:&webhookError];
      if ([deliveryID length] == 0) {
        [self appendOutboxEntryForNotification:identifier
                                       channel:@"webhook"
                                     recipient:([preferenceRecipients count] > 0) ? preferenceRecipients[0] : NMTrimmedString(webhookRequest[@"url"])
                                        status:@"failed"
                                         jobID:@""
                                         queue:@""
                                    deliveryID:@""
                                       message:NMWebhookPreviewRepresentation(webhookRequest)
                                  errorMessage:webhookError.localizedDescription ?: @"webhook delivery failed"];
        (void)[self persistStateWithError:NULL];
        if (error != NULL) {
          *error = webhookError ?: NMError(ALNNotificationsModuleErrorDeliveryFailed,
                                           @"webhook delivery failed",
                                           @{ @"identifier" : identifier });
        }
        return nil;
      }
      [self appendOutboxEntryForNotification:identifier
                                     channel:@"webhook"
                                   recipient:([preferenceRecipients count] > 0) ? preferenceRecipients[0] : NMTrimmedString(webhookRequest[@"url"])
                                      status:@"delivered"
                                       jobID:@""
                                       queue:@""
                                  deliveryID:deliveryID
                                     message:NMWebhookPreviewRepresentation(webhookRequest)
                                errorMessage:nil];
      [deliveredChannels addObject:@"webhook"];
      [deliveryIDs addObject:deliveryID];
    } else {
      [self appendOutboxEntryForNotification:identifier
                                     channel:@"webhook"
                                   recipient:([preferenceRecipients count] > 0) ? preferenceRecipients[0] : NMTrimmedString(webhookRequest[@"url"])
                                      status:@"suppressed"
                                       jobID:@""
                                       queue:@""
                                  deliveryID:@""
                                     message:NMWebhookPreviewRepresentation(webhookRequest)
                                errorMessage:@"suppressed by preference policy"];
      [skippedChannels addObject:@"webhook"];
    }
  }

  NSDictionary *summary = @{
    @"notification" : identifier,
    @"channels" : deliveredChannels,
    @"skippedChannels" : skippedChannels,
    @"deliveryIDs" : deliveryIDs,
  };
  if (![self persistStateWithError:error]) {
    return nil;
  }
  return summary;
}

- (NSDictionary *)testSendNotificationIdentifier:(NSString *)identifier
                                          payload:(NSDictionary *)payload
                                         channels:(NSArray<NSString *> *)channels
                                            error:(NSError **)error {
  NSDictionary *jobPayload = @{
    @"identifier" : NMTrimmedString(identifier),
    @"payload" : NMNormalizeDictionary(payload),
    @"channels" : NMNormalizedChannelArray(channels),
  };
  return [self processQueuedNotificationPayload:jobPayload error:error];
}

- (NSArray<NSDictionary *> *)outboxSnapshot {
  [self.lock lock];
  NSArray *snapshot = [[NSArray alloc] initWithArray:self.outboxEntries copyItems:YES];
  [self.lock unlock];
  return snapshot ?: @[];
}

- (NSDictionary *)outboxEntryForIdentifier:(NSString *)entryID {
  NSString *targetID = NMTrimmedString(entryID);
  [self.lock lock];
  NSDictionary *match = nil;
  for (NSDictionary *entry in self.outboxEntries) {
    if ([[entry objectForKey:@"entryID"] isEqualToString:targetID]) {
      match = [entry copy];
      break;
    }
  }
  [self.lock unlock];
  return match;
}

- (NSArray<NSDictionary *> *)inboxSnapshotForRecipient:(NSString *)recipient {
  NSString *normalizedRecipient = NMTrimmedString(recipient);
  [self.lock lock];
  NSArray *storedInbox = self.inboxByRecipient[normalizedRecipient];
  NSMutableArray *snapshot = [NSMutableArray array];
  for (id rawEntry in storedInbox ?: @[]) {
    [snapshot addObject:NMNormalizedInboxEntry(rawEntry)];
  }
  [self.lock unlock];
  return snapshot ?: @[];
}

- (NSDictionary *)inboxSummaryLockedForRecipient:(NSString *)recipient {
  NSMutableArray *entries = [NSMutableArray array];
  NSArray *storedInbox = self.inboxByRecipient[NMTrimmedString(recipient)];
  for (id rawEntry in storedInbox ?: @[]) {
    [entries addObject:NMNormalizedInboxEntry(rawEntry)];
  }
  return NMInboxSummary(recipient, entries);
}

- (NSDictionary *)inboxSummaryForRecipient:(NSString *)recipient {
  NSString *normalizedRecipient = NMTrimmedString(recipient);
  [self.lock lock];
  NSDictionary *summary = [self inboxSummaryLockedForRecipient:normalizedRecipient];
  [self.lock unlock];
  return summary ?: NMInboxSummary(normalizedRecipient, @[]);
}

- (NSDictionary *)markInboxEntryID:(NSString *)entryID
                              read:(BOOL)read
                      forRecipient:(NSString *)recipient
                             error:(NSError **)error {
  NSString *normalizedRecipient = NMTrimmedString(recipient);
  NSString *normalizedEntryID = NMTrimmedString(entryID);
  if ([normalizedRecipient length] == 0 || [normalizedEntryID length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"recipient and entry ID are required",
                       @{ @"recipient" : normalizedRecipient ?: @"", @"entryID" : normalizedEntryID ?: @"" });
    }
    return nil;
  }

  NSDictionary *result = nil;
  [self.lock lock];
  NSMutableArray *storedInbox = [self.inboxByRecipient[normalizedRecipient] isKindOfClass:[NSMutableArray class]]
                                    ? self.inboxByRecipient[normalizedRecipient]
                                    : nil;
  NSUInteger matchIndex = NSNotFound;
  for (NSUInteger idx = 0; idx < [storedInbox count]; idx++) {
    NSDictionary *entry = NMNormalizedInboxEntry(storedInbox[idx]);
    if ([entry[@"entryID"] isEqualToString:normalizedEntryID]) {
      matchIndex = idx;
      break;
    }
  }
  if (matchIndex == NSNotFound) {
    [self.lock unlock];
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorNotFound,
                       @"inbox entry not found",
                       @{ @"recipient" : normalizedRecipient, @"entryID" : normalizedEntryID });
    }
    return nil;
  }

  NSMutableDictionary *updatedEntry =
      [NSMutableDictionary dictionaryWithDictionary:NMNormalizedInboxEntry(storedInbox[matchIndex])];
  updatedEntry[@"read"] = @(read);
  if (read) {
    updatedEntry[@"readAt"] = @([[NSDate date] timeIntervalSince1970]);
  } else {
    [updatedEntry removeObjectForKey:@"readAt"];
  }
  storedInbox[matchIndex] = updatedEntry;
  self.inboxByRecipient[normalizedRecipient] = storedInbox;
  NSDictionary *summary = [self inboxSummaryLockedForRecipient:normalizedRecipient];
  result = @{
    @"recipient" : normalizedRecipient,
    @"entry" : [updatedEntry copy],
    @"totalCount" : summary[@"totalCount"] ?: @0,
    @"unreadCount" : summary[@"unreadCount"] ?: @0,
  };
  [self.lock unlock];

  if (![self persistStateWithError:error]) {
    return nil;
  }
  return result;
}

- (NSDictionary *)markAllInboxEntriesReadForRecipient:(NSString *)recipient
                                                error:(NSError **)error {
  NSString *normalizedRecipient = NMTrimmedString(recipient);
  if ([normalizedRecipient length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"recipient is required",
                       @{ @"field" : @"recipient" });
    }
    return nil;
  }

  NSDictionary *result = nil;
  [self.lock lock];
  NSMutableArray *storedInbox = [self.inboxByRecipient[normalizedRecipient] isKindOfClass:[NSMutableArray class]]
                                    ? self.inboxByRecipient[normalizedRecipient]
                                    : [NSMutableArray array];
  NSUInteger updatedCount = 0;
  NSNumber *readAt = @([[NSDate date] timeIntervalSince1970]);
  for (NSUInteger idx = 0; idx < [storedInbox count]; idx++) {
    NSMutableDictionary *entry =
        [NSMutableDictionary dictionaryWithDictionary:NMNormalizedInboxEntry(storedInbox[idx])];
    if (![entry[@"read"] boolValue]) {
      entry[@"read"] = @YES;
      entry[@"readAt"] = readAt;
      updatedCount += 1;
    }
    storedInbox[idx] = entry;
  }
  self.inboxByRecipient[normalizedRecipient] = storedInbox;
  NSDictionary *summary = [self inboxSummaryLockedForRecipient:normalizedRecipient];
  result = @{
    @"recipient" : normalizedRecipient,
    @"updatedCount" : @(updatedCount),
    @"totalCount" : summary[@"totalCount"] ?: @0,
    @"unreadCount" : summary[@"unreadCount"] ?: @0,
  };
  [self.lock unlock];

  if (![self persistStateWithError:error]) {
    return nil;
  }
  return result;
}

- (NSDictionary *)notificationPreferencesForRecipient:(NSString *)recipient {
  NSString *normalizedRecipient = NMTrimmedString(recipient);
  [self.lock lock];
  NSDictionary *preferences = [self.preferencesByRecipient[normalizedRecipient] copy];
  [self.lock unlock];
  return preferences ?: @{};
}

- (NSDictionary *)updateNotificationPreferences:(NSDictionary *)preferences
                                   forRecipient:(NSString *)recipient
                                          error:(NSError **)error {
  NSString *normalizedRecipient = NMTrimmedString(recipient);
  if ([normalizedRecipient length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"recipient is required",
                       @{ @"field" : @"recipient" });
    }
    return nil;
  }
  NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
  NSDictionary *rawPreferences = [preferences isKindOfClass:[NSDictionary class]] ? preferences : @{};
  for (id notificationKey in rawPreferences) {
    NSString *identifier = NMTrimmedString(notificationKey);
    NSDictionary *channelMap = [rawPreferences[notificationKey] isKindOfClass:[NSDictionary class]] ? rawPreferences[notificationKey] : nil;
    if ([identifier length] == 0 || channelMap == nil) {
      continue;
    }
    NSMutableDictionary *normalizedChannels = [NSMutableDictionary dictionary];
    for (id channelKey in channelMap) {
      NSString *channel = NMLowerTrimmedString(channelKey);
      id value = channelMap[channelKey];
      if ([channel length] == 0 || ![value respondsToSelector:@selector(boolValue)]) {
        continue;
      }
      normalizedChannels[channel] = @([value boolValue]);
    }
    if ([normalizedChannels count] > 0) {
      normalized[identifier] = [NSDictionary dictionaryWithDictionary:normalizedChannels];
    }
  }
  [self.lock lock];
  self.preferencesByRecipient[normalizedRecipient] = [NSDictionary dictionaryWithDictionary:normalized];
  NSDictionary *stored = [self.preferencesByRecipient[normalizedRecipient] copy];
  [self.lock unlock];
  NSDictionary *result = @{
    @"recipient" : normalizedRecipient,
    @"preferences" : stored ?: @{},
  };
  if (![self persistStateWithError:error]) {
    return nil;
  }
  return result;
}

- (NSDictionary *)dashboardSummary {
  NSArray *definitions = [self registeredNotifications];
  NSArray *outbox = [self outboxSnapshot];
  NSUInteger unreadInboxCount = 0;
  [self.lock lock];
  for (NSString *recipient in self.inboxByRecipient) {
    NSDictionary *summary = [self inboxSummaryLockedForRecipient:recipient];
    unreadInboxCount += [summary[@"unreadCount"] respondsToSelector:@selector(unsignedIntegerValue)]
                            ? [summary[@"unreadCount"] unsignedIntegerValue]
                            : 0;
  }
  [self.lock unlock];
  return @{
    @"cards" : @[
      @{ @"label" : @"Definitions", @"value" : @([definitions count]) },
      @{ @"label" : @"Outbox", @"value" : @([outbox count]) },
      @{ @"label" : @"Inbox Recipients", @"value" : @([self.inboxByRecipient count]) },
      @{ @"label" : @"Unread Inbox", @"value" : @(unreadInboxCount) },
      @{ @"label" : @"Preference Recipients", @"value" : @([self.preferencesByRecipient count]) },
      @{ @"label" : @"Realtime fanout", @"value" : @([self.recentFanoutEvents count]) },
    ],
    @"recentOutbox" : ([outbox count] > 10) ? [outbox subarrayWithRange:NSMakeRange(MAX((NSInteger)[outbox count] - 10, 0), 10)] : outbox,
    @"recentFanout" : ([[NSArray alloc] initWithArray:self.recentFanoutEvents copyItems:YES] ?: @[]),
  };
}

@end

@interface ALNNotificationsModuleController : ALNController

@property(nonatomic, strong) ALNNotificationsModuleRuntime *runtime;
@property(nonatomic, strong) ALNAuthModuleRuntime *authRuntime;

- (BOOL)requireNotificationsUserHTML:(ALNContext *)ctx;
- (BOOL)requireNotificationsAdminHTML:(ALNContext *)ctx;
- (id)renderInboxPageForContext:(ALNContext *)ctx
                        message:(NSString *)message
                         errors:(NSArray *)errors;

@end

@interface ALNNotificationsAdminOutboxResource : NSObject <ALNAdminUIResource>

@property(nonatomic, strong) ALNNotificationsModuleRuntime *runtime;

- (instancetype)initWithRuntime:(ALNNotificationsModuleRuntime *)runtime;

@end

@interface ALNNotificationsAdminDefinitionsResource : NSObject <ALNAdminUIResource>

@property(nonatomic, strong) ALNNotificationsModuleRuntime *runtime;

- (instancetype)initWithRuntime:(ALNNotificationsModuleRuntime *)runtime;

@end

@interface ALNNotificationsAdminResourceProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation ALNNotificationsModuleController

- (instancetype)init {
  self = [super init];
  if (self) {
    _runtime = [ALNNotificationsModuleRuntime sharedRuntime];
    _authRuntime = [ALNAuthModuleRuntime sharedRuntime];
  }
  return self;
}

- (NSDictionary *)requestParameters {
  NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:self.context.request.queryParams ?: @{}];
  NSString *contentType = [[[self headerValueForName:@"content-type"] lowercaseString] componentsSeparatedByString:@";"][0];
  NSDictionary *bodyParameters = @{};
  if ([contentType containsString:@"application/json"]) {
    bodyParameters = NMJSONParametersFromBody(self.context.request.body);
  } else if ([contentType containsString:@"application/x-www-form-urlencoded"]) {
    bodyParameters = NMFormParametersFromBody(self.context.request.body);
  }
  [parameters addEntriesFromDictionary:bodyParameters ?: @{}];
  return parameters;
}

- (NSDictionary *)pageContextWithTitle:(NSString *)title
                               heading:(NSString *)heading
                               message:(NSString *)message
                                errors:(NSArray *)errors
                                 extra:(NSDictionary *)extra {
  NSMutableDictionary *context = [NSMutableDictionary dictionary];
  context[@"pageTitle"] = title ?: @"Arlen Notifications";
  context[@"pageHeading"] = heading ?: context[@"pageTitle"];
  context[@"message"] = message ?: @"";
  context[@"errors"] = [errors isKindOfClass:[NSArray class]] ? errors : @[];
  context[@"notificationsPrefix"] = self.runtime.prefix ?: @"/notifications";
  context[@"notificationsAPIPrefix"] = self.runtime.apiPrefix ?: @"/notifications/api";
  context[@"authLoginPath"] = [self.authRuntime loginPath] ?: @"/auth/login";
  context[@"authLogoutPath"] = [self.authRuntime logoutPath] ?: @"/auth/logout";
  context[@"csrfToken"] = [self csrfToken] ?: @"";
  context[@"summary"] = [self.runtime dashboardSummary] ?: @{};
  context[@"definitions"] = [self.runtime registeredNotifications] ?: @[];
  if ([extra isKindOfClass:[NSDictionary class]]) {
    [context addEntriesFromDictionary:extra];
  }
  return context;
}

- (NSString *)notificationsReturnPathForContext:(ALNContext *)ctx {
  NSString *path = ctx.request.path ?: @"/";
  NSString *query = NMTrimmedString(ctx.request.queryString);
  if ([query length] > 0) {
    return [NSString stringWithFormat:@"%@?%@", path, query];
  }
  return path;
}

- (BOOL)requireNotificationsUserHTML:(ALNContext *)ctx {
  NSString *returnTo = [self notificationsReturnPathForContext:ctx];
  if ([[ctx authSubject] length] == 0) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime loginPath] ?: @"/auth/login",
                                                    NMPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  return YES;
}

- (BOOL)requireNotificationsAdminHTML:(ALNContext *)ctx {
  if (![self requireNotificationsUserHTML:ctx]) {
    return NO;
  }
  if (![self.authRuntime isAdminContext:ctx error:NULL]) {
    [self setStatus:403];
    [self renderTemplate:@"modules/notifications/result/index"
                 context:[self pageContextWithTitle:@"Notifications Access"
                                            heading:@"Access denied"
                                            message:@"You do not have the operator/admin role required for this surface."
                                             errors:nil
                                              extra:@{
                                                @"resultActionPath" : self.runtime.prefix ?: @"/notifications/inbox",
                                                @"resultActionLabel" : @"Back to notifications",
                                              }]
                  layout:@"modules/notifications/layouts/main"
                   error:NULL];
    return NO;
  }
  if ([ctx authAssuranceLevel] < 2) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime totpPath] ?: @"/auth/mfa/totp",
                                                    NMPercentEncodedQueryComponent([self notificationsReturnPathForContext:ctx])];
    [self redirectTo:location status:302];
    return NO;
  }
  return YES;
}

- (id)inboxHTML:(ALNContext *)ctx {
  return [self renderInboxPageForContext:ctx message:@"" errors:nil];
}

- (id)renderInboxPageForContext:(ALNContext *)ctx
                        message:(NSString *)message
                         errors:(NSArray *)errors {
  NSString *recipient = [ctx authSubject] ?: @"";
  NSDictionary *inboxSummary = [self.runtime inboxSummaryForRecipient:recipient] ?: @{};
  [self renderTemplate:@"modules/notifications/inbox/index"
               context:[self pageContextWithTitle:@"Notifications"
                                          heading:@"Inbox"
                                          message:message
                                           errors:errors
                                            extra:@{
                                              @"recipient" : recipient,
                                              @"inbox" : inboxSummary[@"entries"] ?: @[],
                                              @"inboxSummary" : inboxSummary,
                                            }]
                layout:@"modules/notifications/layouts/main"
                 error:NULL];
  return nil;
}

- (id)markInboxEntryReadHTML:(ALNContext *)ctx {
  NSString *recipient = [ctx authSubject] ?: @"";
  NSError *error = nil;
  NSDictionary *result = [self.runtime markInboxEntryID:[self stringParamForName:@"entryID"] ?: @""
                                                   read:YES
                                           forRecipient:recipient
                                                  error:&error];
  if (result == nil) {
    [self setStatus:(error.code == ALNNotificationsModuleErrorNotFound) ? 404 : 422];
    return [self renderInboxPageForContext:ctx
                                   message:@""
                                    errors:@[ @{ @"message" : error.localizedDescription ?: @"Inbox update failed" } ]];
  }
  [self redirectTo:[NSString stringWithFormat:@"%@/inbox", self.runtime.prefix ?: @"/notifications"] status:302];
  return nil;
}

- (id)markInboxEntryUnreadHTML:(ALNContext *)ctx {
  NSString *recipient = [ctx authSubject] ?: @"";
  NSError *error = nil;
  NSDictionary *result = [self.runtime markInboxEntryID:[self stringParamForName:@"entryID"] ?: @""
                                                   read:NO
                                           forRecipient:recipient
                                                  error:&error];
  if (result == nil) {
    [self setStatus:(error.code == ALNNotificationsModuleErrorNotFound) ? 404 : 422];
    return [self renderInboxPageForContext:ctx
                                   message:@""
                                    errors:@[ @{ @"message" : error.localizedDescription ?: @"Inbox update failed" } ]];
  }
  [self redirectTo:[NSString stringWithFormat:@"%@/inbox", self.runtime.prefix ?: @"/notifications"] status:302];
  return nil;
}

- (id)markAllInboxReadHTML:(ALNContext *)ctx {
  NSString *recipient = [ctx authSubject] ?: @"";
  NSError *error = nil;
  NSDictionary *result = [self.runtime markAllInboxEntriesReadForRecipient:recipient error:&error];
  if (result == nil) {
    [self setStatus:422];
    return [self renderInboxPageForContext:ctx
                                   message:@""
                                    errors:@[ @{ @"message" : error.localizedDescription ?: @"Inbox update failed" } ]];
  }
  [self redirectTo:[NSString stringWithFormat:@"%@/inbox", self.runtime.prefix ?: @"/notifications"] status:302];
  return nil;
}

- (id)preferencesHTML:(ALNContext *)ctx {
  NSString *recipient = [ctx authSubject] ?: @"";
  [self renderTemplate:@"modules/notifications/preferences/index"
               context:[self pageContextWithTitle:@"Notification Preferences"
                                          heading:@"Notification Preferences"
                                          message:@""
                                           errors:nil
                                            extra:@{
                                              @"recipient" : recipient,
                                              @"preferences" : [self.runtime notificationPreferencesForRecipient:recipient] ?: @{},
                                            }]
                layout:@"modules/notifications/layouts/main"
                 error:NULL];
  return nil;
}

- (id)updatePreferencesHTML:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSString *recipient = [ctx authSubject] ?: @"";
  NSMutableDictionary *preferences = [NSMutableDictionary dictionary];
  for (NSString *key in parameters) {
    if (![key hasPrefix:@"pref__"]) {
      continue;
    }
    NSArray<NSString *> *parts = [key componentsSeparatedByString:@"__"];
    if ([parts count] != 3) {
      continue;
    }
    NSString *identifier = NMTrimmedString(parts[1]);
    NSString *channel = NMLowerTrimmedString(parts[2]);
    if ([identifier length] == 0 || [channel length] == 0) {
      continue;
    }
    NSMutableDictionary *channelMap = [preferences[identifier] isKindOfClass:[NSMutableDictionary class]]
                                          ? preferences[identifier]
                                          : [NSMutableDictionary dictionary];
    channelMap[channel] = @([[parameters[key] description] length] > 0);
    preferences[identifier] = channelMap;
  }
  NSError *error = nil;
  NSDictionary *result = [self.runtime updateNotificationPreferences:preferences forRecipient:recipient error:&error];
  if (result == nil) {
    [self setStatus:422];
    return [self preferencesHTML:ctx];
  }
  [self renderTemplate:@"modules/notifications/preferences/index"
               context:[self pageContextWithTitle:@"Notification Preferences"
                                          heading:@"Notification Preferences"
                                          message:@"Preferences updated."
                                           errors:nil
                                            extra:@{
                                              @"recipient" : recipient,
                                              @"preferences" : result[@"preferences"] ?: @{},
                                            }]
                layout:@"modules/notifications/layouts/main"
                 error:NULL];
  return nil;
}

- (id)outboxHTML:(ALNContext *)ctx {
  (void)ctx;
  [self renderTemplate:@"modules/notifications/outbox/index"
               context:[self pageContextWithTitle:@"Notification Outbox"
                                          heading:@"Notification Outbox"
                                          message:@""
                                           errors:nil
                                            extra:@{
                                              @"outbox" : [self.runtime outboxSnapshot] ?: @[],
                                            }]
                layout:@"modules/notifications/layouts/main"
                 error:NULL];
  return nil;
}

- (id)previewHTML:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSString *notificationID = NMTrimmedString(parameters[@"notification"]);
  NSDictionary *payload = @{
    @"recipient" : NMTrimmedString(parameters[@"recipient"]),
    @"email" : NMTrimmedString(parameters[@"email"]),
    @"name" : NMTrimmedString(parameters[@"name"]),
  };
  NSError *error = nil;
  NSDictionary *preview = ([notificationID length] > 0)
                              ? [self.runtime previewNotificationIdentifier:notificationID
                                                                     payload:payload
                                                                    channels:nil
                                                                       error:&error]
                              : nil;
  [self renderTemplate:@"modules/notifications/preview/index"
               context:[self pageContextWithTitle:@"Notification Preview"
                                          heading:@"Notification Preview"
                                          message:@""
                                           errors:(error != nil) ? @[ @{ @"message" : error.localizedDescription ?: @"Preview failed" } ] : nil
                                            extra:@{
                                              @"selectedNotification" : notificationID,
                                              @"preview" : preview ?: @{},
                                              @"previewForm" : payload,
                                            }]
                layout:@"modules/notifications/layouts/main"
                 error:NULL];
  return nil;
}

- (id)testSendHTML:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *result =
      [self.runtime testSendNotificationIdentifier:NMTrimmedString(parameters[@"notification"])
                                           payload:@{
                                             @"recipient" : NMTrimmedString(parameters[@"recipient"]),
                                             @"email" : NMTrimmedString(parameters[@"email"]),
                                             @"name" : NMTrimmedString(parameters[@"name"]),
                                           }
                                          channels:nil
                                             error:&error];
  [self renderTemplate:@"modules/notifications/result/index"
               context:[self pageContextWithTitle:@"Notification Test Send"
                                          heading:(result != nil) ? @"Notification queued" : @"Notification failed"
                                          message:(result != nil) ? @"Preview and delivery contract executed successfully." : (error.localizedDescription ?: @"Notification failed.")
                                           errors:nil
                                            extra:@{
                                              @"resultActionPath" : NMPathJoin(self.runtime.prefix, @"outbox"),
                                              @"resultActionLabel" : @"View outbox",
                                            }]
                layout:@"modules/notifications/layouts/main"
                 error:NULL];
  return nil;
}

- (id)apiDefinitions:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"definitions" : [self.runtime registeredNotifications] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiOutbox:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"outbox" : [self.runtime outboxSnapshot] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiOutboxEntry:(ALNContext *)ctx {
  NSDictionary *entry = [self.runtime outboxEntryForIdentifier:[self stringParamForName:@"entryID"] ?: @""];
  if (entry == nil) {
    [self setStatus:404];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : @"Outbox entry not found" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"entry" : entry } meta:nil error:NULL];
  return nil;
}

- (id)apiInbox:(ALNContext *)ctx {
  NSString *recipient = [[ctx authSubject] length] > 0 ? [ctx authSubject] : ([self stringParamForName:@"recipient"] ?: @"");
  NSDictionary *summary = [self.runtime inboxSummaryForRecipient:recipient] ?: @{};
  [self renderJSONEnvelopeWithData:@{
    @"recipient" : recipient ?: @"",
    @"inbox" : summary[@"entries"] ?: @[],
    @"totalCount" : summary[@"totalCount"] ?: @0,
    @"unreadCount" : summary[@"unreadCount"] ?: @0,
  } meta:nil error:NULL];
  return nil;
}

- (id)apiMarkInboxEntryRead:(ALNContext *)ctx {
  NSString *recipient = [ctx authSubject] ?: @"";
  NSError *error = nil;
  NSDictionary *result = [self.runtime markInboxEntryID:[self stringParamForName:@"entryID"] ?: @""
                                                   read:YES
                                           forRecipient:recipient
                                                  error:&error];
  if (result == nil) {
    [self setStatus:(error.code == ALNNotificationsModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"inbox update failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:result meta:nil error:NULL];
  return nil;
}

- (id)apiMarkInboxEntryUnread:(ALNContext *)ctx {
  NSString *recipient = [ctx authSubject] ?: @"";
  NSError *error = nil;
  NSDictionary *result = [self.runtime markInboxEntryID:[self stringParamForName:@"entryID"] ?: @""
                                                   read:NO
                                           forRecipient:recipient
                                                  error:&error];
  if (result == nil) {
    [self setStatus:(error.code == ALNNotificationsModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"inbox update failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:result meta:nil error:NULL];
  return nil;
}

- (id)apiReadAllInbox:(ALNContext *)ctx {
  NSString *recipient = [ctx authSubject] ?: @"";
  NSError *error = nil;
  NSDictionary *result = [self.runtime markAllInboxEntriesReadForRecipient:recipient error:&error];
  if (result == nil) {
    [self setStatus:422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"inbox update failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:result meta:nil error:NULL];
  return nil;
}

- (id)apiQueue:(ALNContext *)ctx {
  (void)ctx;
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *summary =
      [self.runtime queueNotificationSummaryForIdentifier:NMTrimmedString(parameters[@"notification"])
                                                  payload:NMNormalizeDictionary(parameters[@"payload"])
                                                 channels:NMNormalizeArray(parameters[@"channels"])
                                                    error:&error];
  if (summary == nil) {
    [self setStatus:422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"queue failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:summary meta:nil error:NULL];
  return nil;
}

- (id)apiPreview:(ALNContext *)ctx {
  (void)ctx;
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *preview =
      [self.runtime previewNotificationIdentifier:NMTrimmedString(parameters[@"notification"])
                                          payload:NMNormalizeDictionary(parameters[@"payload"])
                                         channels:NMNormalizeArray(parameters[@"channels"])
                                            error:&error];
  if (preview == nil) {
    [self setStatus:(error.code == ALNNotificationsModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"preview failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:preview meta:nil error:NULL];
  return nil;
}

- (id)apiTestSend:(ALNContext *)ctx {
  (void)ctx;
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *result =
      [self.runtime testSendNotificationIdentifier:NMTrimmedString(parameters[@"notification"])
                                           payload:NMNormalizeDictionary(parameters[@"payload"])
                                          channels:NMNormalizeArray(parameters[@"channels"])
                                             error:&error];
  if (result == nil) {
    [self setStatus:(error.code == ALNNotificationsModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"test send failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:result meta:nil error:NULL];
  return nil;
}

- (id)apiPreferences:(ALNContext *)ctx {
  NSString *recipient = [[ctx authSubject] length] > 0 ? [ctx authSubject] : ([self stringParamForName:@"recipient"] ?: @"");
  [self renderJSONEnvelopeWithData:@{
    @"recipient" : recipient ?: @"",
    @"preferences" : [self.runtime notificationPreferencesForRecipient:recipient] ?: @{},
  } meta:nil error:NULL];
  return nil;
}

- (id)apiUpdatePreferences:(ALNContext *)ctx {
  NSString *recipient = [[ctx authSubject] length] > 0 ? [ctx authSubject] : ([self stringParamForName:@"recipient"] ?: @"");
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *result = [self.runtime updateNotificationPreferences:NMNormalizeDictionary(parameters[@"preferences"])
                                                        forRecipient:recipient
                                                               error:&error];
  if (result == nil) {
    [self setStatus:422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"preferences update failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:result meta:nil error:NULL];
  return nil;
}

@end

@implementation ALNNotificationsAdminOutboxResource

- (instancetype)initWithRuntime:(ALNNotificationsModuleRuntime *)runtime {
  self = [super init];
  if (self != nil) {
    _runtime = runtime;
  }
  return self;
}

- (NSString *)adminUIResourceIdentifier {
  return @"notification_outbox";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Notification Outbox",
    @"singularLabel" : @"Outbox Entry",
    @"summary" : @"Inspect delivered email and in-app notification history from the shared module contract.",
    @"identifierField" : @"entryID",
    @"primaryField" : @"notification",
    @"legacyPath" : @"notifications/outbox",
    @"fields" : @[
      @{ @"name" : @"notification", @"label" : @"Notification", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"channel", @"label" : @"Channel", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"recipient", @"label" : @"Recipient", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"status", @"label" : @"Status", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"deliveryID", @"label" : @"Delivery", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"entryID", @"label" : @"Entry ID", @"list" : @NO, @"detail" : @YES },
    ],
    @"filters" : @[ @{ @"name" : @"q", @"label" : @"Search", @"type" : @"search", @"placeholder" : @"notification, recipient, channel" } ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  (void)error;
  NSString *search = NMLowerTrimmedString(query);
  NSMutableArray *records = [NSMutableArray array];
  for (NSDictionary *entry in [self.runtime outboxSnapshot]) {
    if ([search length] > 0 &&
        ![NMLowerTrimmedString(entry[@"notification"]) containsString:search] &&
        ![NMLowerTrimmedString(entry[@"recipient"]) containsString:search] &&
        ![NMLowerTrimmedString(entry[@"channel"]) containsString:search]) {
      continue;
    }
    [records addObject:entry];
  }
  if (offset >= [records count]) {
    return @[];
  }
  return [records subarrayWithRange:NSMakeRange(offset, MIN(limit, [records count] - offset))];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  NSDictionary *entry = [self.runtime outboxEntryForIdentifier:identifier];
  if (entry == nil && error != NULL) {
    *error = NMError(ALNNotificationsModuleErrorNotFound, @"outbox entry not found", @{ @"entryID" : NMTrimmedString(identifier) });
  }
  return entry;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  (void)identifier;
  (void)parameters;
  if (error != NULL) {
    *error = NMError(ALNNotificationsModuleErrorValidationFailed, @"outbox entries are not directly editable", nil);
  }
  return nil;
}

@end

@implementation ALNNotificationsAdminDefinitionsResource

- (instancetype)initWithRuntime:(ALNNotificationsModuleRuntime *)runtime {
  self = [super init];
  if (self != nil) {
    _runtime = runtime;
  }
  return self;
}

- (NSString *)adminUIResourceIdentifier {
  return @"notification_definitions";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Notification Definitions",
    @"singularLabel" : @"Notification Definition",
    @"summary" : @"Browse notification definitions and jump into preview/test-send flows.",
    @"identifierField" : @"identifier",
    @"primaryField" : @"title",
    @"legacyPath" : @"notifications/definitions",
    @"fields" : @[
      @{ @"name" : @"title", @"label" : @"Title", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"identifier", @"label" : @"Identifier", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"channels", @"label" : @"Channels", @"kind" : @"array", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"previewLink", @"label" : @"Preview", @"kind" : @"link", @"list" : @YES, @"detail" : @YES },
    ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  (void)error;
  NSString *search = NMLowerTrimmedString(query);
  NSMutableArray *records = [NSMutableArray array];
  for (NSDictionary *definition in [self.runtime registeredNotifications]) {
    if ([search length] > 0 &&
        ![NMLowerTrimmedString(definition[@"identifier"]) containsString:search] &&
        ![NMLowerTrimmedString(definition[@"title"]) containsString:search]) {
      continue;
    }
    NSString *identifier = NMTrimmedString(definition[@"identifier"]);
    [records addObject:@{
      @"identifier" : identifier,
      @"title" : definition[@"title"] ?: identifier,
      @"channels" : definition[@"channels"] ?: @[],
      @"previewLink" : @{
        @"href" : [NSString stringWithFormat:@"%@/preview?notification=%@&recipient=demo-user&email=demo@example.test&name=Preview",
                                             self.runtime.prefix ?: @"/notifications",
                                             NMPercentEncodedQueryComponent(identifier)],
        @"label" : @"Open preview",
      },
    }];
  }
  if (offset >= [records count]) {
    return @[];
  }
  return [records subarrayWithRange:NSMakeRange(offset, MIN(limit, [records count] - offset))];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  NSArray *records = [self adminUIListRecordsMatching:nil limit:1000 offset:0 error:error];
  for (NSDictionary *record in records) {
    if ([[record objectForKey:@"identifier"] isEqualToString:NMTrimmedString(identifier)]) {
      return record;
    }
  }
  if (error != NULL) {
    *error = NMError(ALNNotificationsModuleErrorNotFound, @"notification definition not found", @{ @"identifier" : NMTrimmedString(identifier) });
  }
  return nil;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  (void)identifier;
  (void)parameters;
  if (error != NULL) {
    *error = NMError(ALNNotificationsModuleErrorValidationFailed, @"notification definitions are not directly editable", nil);
  }
  return nil;
}

@end

@implementation ALNNotificationsAdminResourceProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  ALNNotificationsModuleRuntime *moduleRuntime = [ALNNotificationsModuleRuntime sharedRuntime];
  return @[
    [[ALNNotificationsAdminOutboxResource alloc] initWithRuntime:moduleRuntime],
    [[ALNNotificationsAdminDefinitionsResource alloc] initWithRuntime:moduleRuntime],
  ];
}

@end

@implementation ALNNotificationsModule

- (NSString *)moduleIdentifier {
  return @"notifications";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  if (![runtime configureWithApplication:application error:error]) {
    return NO;
  }

  [application beginRouteGroupWithPrefix:runtime.prefix guardAction:@"requireNotificationsUserHTML" formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/"
                              name:@"notifications_inbox_root"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"inboxHTML"];
  [application registerRouteMethod:@"GET"
                              path:@"/inbox"
                              name:@"notifications_inbox"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"inboxHTML"];
  [application registerRouteMethod:@"POST"
                              path:@"/inbox/read-all"
                              name:@"notifications_inbox_read_all"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"markAllInboxReadHTML"];
  [application registerRouteMethod:@"POST"
                              path:@"/inbox/:entryID/read"
                              name:@"notifications_inbox_mark_read"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"markInboxEntryReadHTML"];
  [application registerRouteMethod:@"POST"
                              path:@"/inbox/:entryID/unread"
                              name:@"notifications_inbox_mark_unread"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"markInboxEntryUnreadHTML"];
  [application registerRouteMethod:@"GET"
                              path:@"/preferences"
                              name:@"notifications_preferences"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"preferencesHTML"];
  [application registerRouteMethod:@"POST"
                              path:@"/preferences"
                              name:@"notifications_preferences_update"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"updatePreferencesHTML"];
  [application endRouteGroup];

  [application beginRouteGroupWithPrefix:runtime.prefix guardAction:@"requireNotificationsAdminHTML" formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/outbox"
                              name:@"notifications_outbox"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"outboxHTML"];
  [application registerRouteMethod:@"GET"
                              path:@"/preview"
                              name:@"notifications_preview"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"previewHTML"];
  [application registerRouteMethod:@"POST"
                              path:@"/test-send"
                              name:@"notifications_test_send"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"testSendHTML"];
  [application endRouteGroup];

  [application beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:nil formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/definitions"
                              name:@"notifications_api_definitions"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiDefinitions"];
  [application registerRouteMethod:@"GET"
                              path:@"/outbox"
                              name:@"notifications_api_outbox"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiOutbox"];
  [application registerRouteMethod:@"GET"
                              path:@"/outbox/:entryID"
                              name:@"notifications_api_outbox_entry"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiOutboxEntry"];
  [application registerRouteMethod:@"GET"
                              path:@"/inbox"
                              name:@"notifications_api_inbox_self"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiInbox"];
  [application registerRouteMethod:@"GET"
                              path:@"/inbox/:recipient"
                              name:@"notifications_api_inbox"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiInbox"];
  [application registerRouteMethod:@"POST"
                              path:@"/inbox/read-all"
                              name:@"notifications_api_inbox_read_all"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiReadAllInbox"];
  [application registerRouteMethod:@"POST"
                              path:@"/inbox/:entryID/read"
                              name:@"notifications_api_inbox_mark_read"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiMarkInboxEntryRead"];
  [application registerRouteMethod:@"POST"
                              path:@"/inbox/:entryID/unread"
                              name:@"notifications_api_inbox_mark_unread"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiMarkInboxEntryUnread"];
  [application registerRouteMethod:@"POST"
                              path:@"/queue"
                              name:@"notifications_api_queue"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiQueue"];
  [application registerRouteMethod:@"POST"
                              path:@"/preview"
                              name:@"notifications_api_preview"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiPreview"];
  [application registerRouteMethod:@"POST"
                              path:@"/test-send"
                              name:@"notifications_api_test_send"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiTestSend"];
  [application registerRouteMethod:@"GET"
                              path:@"/preferences"
                              name:@"notifications_api_preferences"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiPreferences"];
  [application registerRouteMethod:@"POST"
                              path:@"/preferences"
                              name:@"notifications_api_preferences_update"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiUpdatePreferences"];
  [application endRouteGroup];

  NSArray *adminRoutes = @[
    @"notifications_api_outbox",
    @"notifications_api_outbox_entry",
    @"notifications_api_preview",
    @"notifications_api_test_send",
  ];
  for (NSString *routeName in adminRoutes) {
    [application configureRouteNamed:routeName
                       requestSchema:nil
                      responseSchema:nil
                             summary:@"Notifications module API"
                         operationID:routeName
                                tags:@[ @"notifications" ]
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

  NSArray *userRoutes = @[
    @"notifications_api_definitions",
    @"notifications_api_inbox_self",
    @"notifications_api_inbox",
    @"notifications_api_inbox_read_all",
    @"notifications_api_inbox_mark_read",
    @"notifications_api_inbox_mark_unread",
    @"notifications_api_queue",
    @"notifications_api_preferences",
    @"notifications_api_preferences_update",
  ];
  for (NSString *routeName in userRoutes) {
    [application configureRouteNamed:routeName
                       requestSchema:nil
                      responseSchema:nil
                             summary:@"Notifications module API"
                         operationID:routeName
                                tags:@[ @"notifications" ]
                      requiredScopes:nil
                       requiredRoles:nil
                     includeInOpenAPI:YES
                                error:NULL];
    [application configureAuthAssuranceForRouteNamed:routeName
                           minimumAuthAssuranceLevel:1
                     maximumAuthenticationAgeSeconds:0
                                          stepUpPath:nil
                                               error:NULL];
  }

  return YES;
}

@end
