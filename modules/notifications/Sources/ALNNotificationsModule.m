#import "ALNNotificationsModule.h"

#import "../../admin-ui/Sources/ALNAdminUIModule.h"
#import "../../auth/Sources/ALNAuthModule.h"

#import "ALNApplication.h"
#import "ALNController.h"
#import "ALNContext.h"
#import "ALNRequest.h"

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
  self.preferenceHook = nil;
  self.nextEntrySequence = 0;
  [self.lock unlock];

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
  NSDictionary *metadata = @{
    @"identifier" : identifier,
    @"title" : [NMTrimmedString(rawMetadata[@"title"]) length] > 0 ? NMTrimmedString(rawMetadata[@"title"]) : identifier,
    @"description" : NMTrimmedString(rawMetadata[@"description"]),
    @"channels" : channels ?: @[],
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

  return @{
    @"identifier" : notificationID,
    @"metadata" : metadata ?: @{},
    @"payload" : normalizedPayload,
    @"channels" : normalizedChannels,
    @"message" : message ?: [NSNull null],
    @"inAppEntry" : inAppEntry ?: [NSNull null],
  };
}

- (NSString *)queueNotificationIdentifier:(NSString *)identifier
                                  payload:(NSDictionary *)payload
                                 channels:(NSArray<NSString *> *)channels
                                    error:(NSError **)error {
  NSDictionary *artifacts = [self artifactsForNotificationIdentifier:identifier payload:payload channels:channels error:error];
  if (artifacts == nil) {
    return nil;
  }
  NSDictionary *jobPayload = @{
    @"identifier" : artifacts[@"identifier"] ?: @"",
    @"payload" : artifacts[@"payload"] ?: @{},
    @"channels" : artifacts[@"channels"] ?: @[],
  };
  return [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:ALNNotificationsDispatchJobIdentifier
                                                            payload:jobPayload
                                                            options:@{
                                                              @"queue" : @"default",
                                                              @"source" : @"notification",
                                                            }
                                                              error:error];
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
  return @{
    @"notification" : artifacts[@"identifier"] ?: @"",
    @"channels" : artifacts[@"channels"] ?: @[],
    @"email" : message ? [message dictionaryRepresentation] : @{},
    @"in_app" : inAppEntry ?: @{},
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
        if (error != NULL) {
          *error = mailError ?: NMError(ALNNotificationsModuleErrorDeliveryFailed,
                                        @"mail delivery failed",
                                        @{ @"identifier" : identifier });
        }
        return nil;
      }
      [self.lock lock];
      self.nextEntrySequence += 1;
      [self.outboxEntries addObject:@{
        @"entryID" : [NSString stringWithFormat:@"notification-%lu", (unsigned long)self.nextEntrySequence],
        @"notification" : identifier,
        @"channel" : @"email",
        @"recipient" : ([preferenceRecipients count] > 0) ? preferenceRecipients[0] : @"",
        @"deliveryID" : deliveryID,
        @"status" : @"delivered",
        @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
        @"message" : [message dictionaryRepresentation],
      }];
      [self.lock unlock];
      [deliveredChannels addObject:@"email"];
      [deliveryIDs addObject:deliveryID];
    } else {
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
      };
      [inbox addObject:record];
      self.inboxByRecipient[recipient] = inbox;
      self.nextEntrySequence += 1;
      [self.outboxEntries addObject:@{
        @"entryID" : [NSString stringWithFormat:@"notification-%lu", (unsigned long)self.nextEntrySequence],
        @"notification" : identifier,
        @"channel" : @"in_app",
        @"recipient" : recipient,
        @"deliveryID" : @"",
        @"status" : @"delivered",
        @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
        @"message" : record,
      }];
      [self.lock unlock];
      deliveredRecipientCount += 1;
    }
    if (deliveredRecipientCount > 0) {
      [deliveredChannels addObject:@"in_app"];
    } else {
      [skippedChannels addObject:@"in_app"];
    }
  }

  return @{
    @"notification" : identifier,
    @"channels" : deliveredChannels,
    @"skippedChannels" : skippedChannels,
    @"deliveryIDs" : deliveryIDs,
  };
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
  NSArray *inbox = self.inboxByRecipient[normalizedRecipient];
  NSArray *snapshot = [[NSArray alloc] initWithArray:inbox ?: @[] copyItems:YES];
  [self.lock unlock];
  return snapshot ?: @[];
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
  return @{
    @"recipient" : normalizedRecipient,
    @"preferences" : stored ?: @{},
  };
}

- (NSDictionary *)dashboardSummary {
  NSArray *definitions = [self registeredNotifications];
  NSArray *outbox = [self outboxSnapshot];
  return @{
    @"cards" : @[
      @{ @"label" : @"Definitions", @"value" : @([definitions count]) },
      @{ @"label" : @"Outbox", @"value" : @([outbox count]) },
      @{ @"label" : @"Inbox Recipients", @"value" : @([self.inboxByRecipient count]) },
      @{ @"label" : @"Preference Recipients", @"value" : @([self.preferencesByRecipient count]) },
    ],
    @"recentOutbox" : ([outbox count] > 10) ? [outbox subarrayWithRange:NSMakeRange(MAX((NSInteger)[outbox count] - 10, 0), 10)] : outbox,
  };
}

@end

@interface ALNNotificationsModuleController : ALNController

@property(nonatomic, strong) ALNNotificationsModuleRuntime *runtime;
@property(nonatomic, strong) ALNAuthModuleRuntime *authRuntime;

- (BOOL)requireNotificationsUserHTML:(ALNContext *)ctx;
- (BOOL)requireNotificationsAdminHTML:(ALNContext *)ctx;

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
  NSString *recipient = [ctx authSubject] ?: @"";
  [self renderTemplate:@"modules/notifications/inbox/index"
               context:[self pageContextWithTitle:@"Notifications"
                                          heading:@"Inbox"
                                          message:@""
                                           errors:nil
                                            extra:@{
                                              @"recipient" : recipient,
                                              @"inbox" : [self.runtime inboxSnapshotForRecipient:recipient] ?: @[],
                                            }]
                layout:@"modules/notifications/layouts/main"
                 error:NULL];
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
  [self renderJSONEnvelopeWithData:@{ @"inbox" : [self.runtime inboxSnapshotForRecipient:recipient] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiQueue:(ALNContext *)ctx {
  (void)ctx;
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSString *jobID = [self.runtime queueNotificationIdentifier:NMTrimmedString(parameters[@"notification"])
                                                      payload:NMNormalizeDictionary(parameters[@"payload"])
                                                     channels:NMNormalizeArray(parameters[@"channels"])
                                                        error:&error];
  if ([jobID length] == 0) {
    [self setStatus:422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"queue failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"jobID" : jobID } meta:nil error:NULL];
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
