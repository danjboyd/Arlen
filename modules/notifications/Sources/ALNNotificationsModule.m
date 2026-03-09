#import "ALNNotificationsModule.h"

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

static NSDictionary *NMJSONParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  id object = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

static NSArray<NSString *> *NMNormalizedChannelArray(id rawValue) {
  NSMutableArray<NSString *> *channels = [NSMutableArray array];
  for (id rawChannel in NMNormalizeArray(rawValue)) {
    NSString *channel = [[NMTrimmedString(rawChannel) lowercaseString] copy];
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
@property(nonatomic, assign) NSUInteger nextEntrySequence;

- (BOOL)registerNotificationDefinition:(id<ALNNotificationDefinition>)definition
                                source:(NSString *)source
                                 error:(NSError *_Nullable *_Nullable)error;

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
  self.nextEntrySequence = 0;
  [self.lock unlock];

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

- (NSString *)queueNotificationIdentifier:(NSString *)identifier
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
                       @{
                         @"identifier" : notificationID,
                         @"channels" : normalizedChannels,
                       });
    }
    return nil;
  }

  NSDictionary *jobPayload = @{
    @"identifier" : notificationID,
    @"payload" : normalizedPayload,
    @"channels" : normalizedChannels,
  };
  return [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:ALNNotificationsDispatchJobIdentifier
                                                            payload:jobPayload
                                                            options:@{
                                                              @"queue" : @"default",
                                                              @"source" : @"notification",
                                                            }
                                                              error:error];
}

- (NSDictionary *)processQueuedNotificationPayload:(NSDictionary *)jobPayload
                                             error:(NSError **)error {
  NSString *identifier = NMTrimmedString(jobPayload[@"identifier"]);
  NSDictionary *payload = NMNormalizeDictionary(jobPayload[@"payload"]);
  NSArray<NSString *> *channels = NMNormalizedChannelArray(jobPayload[@"channels"]);

  [self.lock lock];
  id<ALNNotificationDefinition> definition = self.definitionsByIdentifier[identifier];
  NSDictionary *metadata = self.metadataByIdentifier[identifier];
  [self.lock unlock];
  if (definition == nil || metadata == nil) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorNotFound,
                       [NSString stringWithFormat:@"unknown notification %@", identifier],
                       @{ @"identifier" : identifier });
    }
    return nil;
  }

  NSError *validationError = nil;
  if (![definition notificationsModuleValidatePayload:payload error:&validationError]) {
    if (error != NULL) {
      *error = validationError;
    }
    return nil;
  }

  if ([channels count] == 0) {
    channels = NMNormalizeArray(metadata[@"channels"]);
  }
  if ([channels count] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"notification requires at least one channel",
                       @{ @"identifier" : identifier });
    }
    return nil;
  }
  if (!NMChannelsAreSubsetOfSupported(channels, NMNormalizeArray(metadata[@"channels"]))) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"requested notification channel is not supported",
                       @{
                         @"identifier" : identifier,
                         @"channels" : channels,
                       });
    }
    return nil;
  }

  NSMutableArray *deliveredChannels = [NSMutableArray array];
  NSMutableArray *deliveryIDs = [NSMutableArray array];

  if ([channels containsObject:@"email"]) {
    NSError *mailError = nil;
    ALNMailMessage *message =
        [definition notificationsModuleMailMessageForPayload:payload runtime:self error:&mailError];
    if (message == nil) {
      if (error != NULL) {
        *error = mailError ?: NMError(ALNNotificationsModuleErrorDeliveryFailed,
                                      @"notification did not produce an email message",
                                      @{ @"identifier" : identifier });
      }
      return nil;
    }
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
      @"deliveryID" : deliveryID,
      @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
      @"message" : [message dictionaryRepresentation],
    }];
    [self.lock unlock];
    [deliveredChannels addObject:@"email"];
    [deliveryIDs addObject:deliveryID];
  }

  if ([channels containsObject:@"in_app"]) {
    NSError *entryError = nil;
    NSDictionary *entry = [definition notificationsModuleInAppEntryForPayload:payload runtime:self error:&entryError];
    if (entry == nil) {
      if (error != NULL) {
        *error = entryError ?: NMError(ALNNotificationsModuleErrorDeliveryFailed,
                                       @"notification did not produce an in-app entry",
                                       @{ @"identifier" : identifier });
      }
      return nil;
    }
    NSArray *recipients = NMNormalizedChannelArray(nil);
    recipients = NMNormalizeArray(entry[@"recipients"]);
    NSMutableArray<NSString *> *targetRecipients = [NSMutableArray array];
    for (id rawRecipient in recipients) {
      NSString *recipient = NMTrimmedString(rawRecipient);
      if ([recipient length] > 0 && ![targetRecipients containsObject:recipient]) {
        [targetRecipients addObject:recipient];
      }
    }
    NSString *singleRecipient = NMTrimmedString(entry[@"recipient"]);
    if ([singleRecipient length] == 0) {
      singleRecipient = NMTrimmedString(entry[@"recipientSubject"]);
    }
    if ([singleRecipient length] > 0 && ![targetRecipients containsObject:singleRecipient]) {
      [targetRecipients addObject:singleRecipient];
    }
    if ([targetRecipients count] == 0) {
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorDeliveryFailed,
                         @"in-app notification requires a recipient",
                         @{ @"identifier" : identifier });
      }
      return nil;
    }
    for (NSString *recipient in targetRecipients) {
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
        @"title" : NMTrimmedString(entry[@"title"]),
        @"body" : NMTrimmedString(entry[@"body"]),
        @"metadata" : NMNormalizeDictionary(entry[@"metadata"]),
      };
      [inbox addObject:record];
      self.inboxByRecipient[recipient] = inbox;
      [self.lock unlock];
    }
    [deliveredChannels addObject:@"in_app"];
  }

  return @{
    @"notification" : identifier,
    @"channels" : deliveredChannels,
    @"deliveryIDs" : deliveryIDs,
  };
}

- (NSArray<NSDictionary *> *)outboxSnapshot {
  [self.lock lock];
  NSArray *snapshot = [[NSArray alloc] initWithArray:self.outboxEntries copyItems:YES];
  [self.lock unlock];
  return snapshot ?: @[];
}

- (NSArray<NSDictionary *> *)inboxSnapshotForRecipient:(NSString *)recipient {
  NSString *normalizedRecipient = NMTrimmedString(recipient);
  [self.lock lock];
  NSArray *inbox = self.inboxByRecipient[normalizedRecipient];
  NSArray *snapshot = [[NSArray alloc] initWithArray:inbox ?: @[] copyItems:YES];
  [self.lock unlock];
  return snapshot ?: @[];
}

@end

@interface ALNNotificationsModuleController : ALNController

@property(nonatomic, strong) ALNNotificationsModuleRuntime *runtime;

@end

@implementation ALNNotificationsModuleController

- (instancetype)init {
  self = [super init];
  if (self) {
    _runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  }
  return self;
}

- (NSDictionary *)requestParameters {
  NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:[self params] ?: @{}];
  [parameters addEntriesFromDictionary:NMJSONParametersFromBody(self.context.request.body) ?: @{}];
  return parameters;
}

- (id)apiDefinitions:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"definitions" : [self.runtime registeredNotifications] ?: @[] }
                              meta:nil
                             error:NULL];
  return nil;
}

- (id)apiOutbox:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"outbox" : [self.runtime outboxSnapshot] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiInbox:(ALNContext *)ctx {
  (void)ctx;
  NSString *recipient = [self stringParamForName:@"recipient"] ?: @"";
  [self renderJSONEnvelopeWithData:@{ @"inbox" : [self.runtime inboxSnapshotForRecipient:recipient] ?: @[] }
                              meta:nil
                             error:NULL];
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
                              path:@"/inbox/:recipient"
                              name:@"notifications_api_inbox"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiInbox"];
  [application registerRouteMethod:@"POST"
                              path:@"/queue"
                              name:@"notifications_api_queue"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiQueue"];
  [application endRouteGroup];

  NSArray *routes = @[
    @"notifications_api_definitions",
    @"notifications_api_outbox",
    @"notifications_api_inbox",
    @"notifications_api_queue",
  ];
  for (NSString *routeName in routes) {
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
  }

  return YES;
}

@end
