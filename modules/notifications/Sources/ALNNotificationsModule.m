#import "ALNNotificationsModule.h"

#import "../../admin-ui/Sources/ALNAdminUIModule.h"
#import "../../auth/Sources/ALNAuthModule.h"

#import "ALNDataCompat.h"
#import "ALNApplication.h"
#import "ALNController.h"
#import "ALNContext.h"
#import "ALNPlatform.h"
#import "ALNRequest.h"
#import "ALNRealtime.h"
#import "ALNResponse.h"
#import "ALNSecurityPrimitives.h"
#import "ALNWebPush.h"

NSString *const ALNNotificationsModuleErrorDomain = @"Arlen.Modules.Notifications.Error";

static NSString *const ALNNotificationsDispatchJobIdentifier = @"notifications.dispatch";
static NSUInteger const ALNNotificationsDefaultMaxOutboxEntries = 1000;
static NSUInteger const ALNNotificationsDefaultMaxInboxEntriesPerRecipient = 200;
static NSUInteger const ALNNotificationsMaxInboxPageLimit = 200;
static NSError *NMError(ALNNotificationsModuleErrorCode code, NSString *message, NSDictionary *details);

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
    // Relative paths belong to the app, not the process working directory, so the
    // server and `arlen jobs worker` (which runs from the framework root) agree.
    return [application pathRelativeToAppRoot:configured];
  }
  NSString *environment = NMLowerTrimmedString(application.environment);
  if ([environment isEqualToString:@"test"]) {
    return @"";
  }
  return [application pathRelativeToAppRoot:
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
                                                        options:NSPropertyListImmutable
                                                         format:&format
                                                          error:error];
  if (object != nil && ![object isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorDeliveryFailed, @"notification state is not a dictionary", nil);
    }
    return nil;
  }
  return object;
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

// Positive integer config value, or the default when missing or invalid.
static NSUInteger NMConfiguredLimit(id rawValue, NSUInteger defaultValue) {
  if ([rawValue isKindOfClass:[NSString class]]) {
    NSInteger parsed = [(NSString *)rawValue integerValue];
    return (parsed > 0) ? (NSUInteger)parsed : defaultValue;
  }
  if ([rawValue respondsToSelector:@selector(longLongValue)] && [rawValue longLongValue] > 0) {
    return (NSUInteger)[rawValue longLongValue];
  }
  return defaultValue;
}

// Inbox deep links render only for http(s) URLs and same-origin relative
// references; anything else (other schemes, protocol-relative `//host`,
// backslashes or control characters) renders without a link.
static NSString *NMSafeInboxHref(id rawValue) {
  NSString *href = NMTrimmedString(rawValue);
  if ([href length] == 0) {
    return @"";
  }
  for (NSUInteger index = 0; index < [href length]; index++) {
    unichar character = [href characterAtIndex:index];
    if (character < 0x20 || character == 0x7f || character == '\\') {
      return @"";
    }
  }
  if ([href hasPrefix:@"//"]) {
    return @"";
  }
  if ([href hasPrefix:@"/"]) {
    return href;
  }
  NSRange delimiter = [href rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@":/?#"]];
  if (delimiter.location == NSNotFound || [href characterAtIndex:delimiter.location] != ':') {
    return href;
  }
  NSString *scheme = [[href substringToIndex:delimiter.location] lowercaseString];
  if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
    return @"";
  }
  NSURL *url = [NSURL URLWithString:href];
  if ([[url host] length] == 0) {
    return @"";
  }
  return href;
}

// Drops the oldest entries so at most `limit` remain.
static void NMTrimOldestEntries(NSMutableArray *entries, NSUInteger limit) {
  if (limit > 0 && [entries count] > limit) {
    [entries removeObjectsInRange:NSMakeRange(0, [entries count] - limit)];
  }
}

// Overlay only entries changed since this runtime last read the file. A second
// worker may have committed other recipients while this worker delivered mail.
static NSMutableArray *NMMergeChangedEntries(NSArray *authoritative, NSArray *baseline,
                                             NSArray *local, NSUInteger limit) {
  NSMutableDictionary *baselineByID = [NSMutableDictionary dictionary];
  for (NSDictionary *entry in baseline) {
    if (![entry isKindOfClass:[NSDictionary class]]) continue;
    NSString *entryID = NMTrimmedString(entry[@"entryID"]);
    if ([entryID length] > 0) baselineByID[entryID] = entry;
  }
  NSMutableArray *merged = [NSMutableArray arrayWithArray:authoritative ?: @[]];
  NSMutableDictionary *positions = [NSMutableDictionary dictionary];
  for (NSUInteger index = 0; index < [merged count]; index++) {
    NSString *entryID = NMTrimmedString([merged[index] isKindOfClass:[NSDictionary class]] ? merged[index][@"entryID"] : nil);
    if ([entryID length] > 0) positions[entryID] = @(index);
  }
  for (NSDictionary *entry in local) {
    if (![entry isKindOfClass:[NSDictionary class]]) continue;
    NSString *entryID = NMTrimmedString(entry[@"entryID"]);
    if ([entryID length] > 0 && [baselineByID[entryID] isEqual:entry]) continue;
    NSNumber *position = positions[entryID];
    if (position != nil) {
      merged[[position unsignedIntegerValue]] = entry;
    } else {
      if ([entryID length] > 0) positions[entryID] = @([merged count]);
      [merged addObject:entry];
    }
  }
  NMTrimOldestEntries(merged, limit);
  return merged;
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

// Where to send a user who needs higher assurance: the auth module's configurable
// step-up target (authModule.paths.stepUp). An older auth module has only
// totpPath, so fall back to it.
@protocol NMStepUpPathSource <NSObject>
@optional
- (nullable NSString *)stepUpPath;
- (nullable NSString *)totpPath;
@end

static NSString *NMStepUpPath(id runtime) {
  id<NMStepUpPathSource> source = runtime;
  NSString *path = [source respondsToSelector:@selector(stepUpPath)] ? [source stepUpPath] : nil;
  if ([path length] == 0 && [source respondsToSelector:@selector(totpPath)]) {
    path = [source totpPath];
  }
  return ([path length] > 0) ? path : @"/auth/mfa/totp";
}

static NSString *NMStepUpLocation(id runtime, NSString *encodedReturnTo) {
  NSString *path = NMStepUpPath(runtime);
  NSString *separator = [path containsString:@"?"] ? @"&" : @"?";
  return [NSString stringWithFormat:@"%@%@return_to=%@", path, separator, encodedReturnTo ?: @""];
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
    NSUInteger maxAttempts = ALNUnsignedIntegerValueOrDefault(policy[@"maxAttempts"], 0);
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

static NSArray<NSString *> *NMRecipientsFromInAppEntry(NSDictionary *entry);

// Hosts of the browser push services. Subscription endpoints come from browsers,
// so the server only POSTs to these unless an app widens the list ("*" allows any
// https host).
static NSArray<NSString *> *NMWebPushDefaultAllowedHosts(void) {
  return @[ @"push.apple.com", @"fcm.googleapis.com", @"push.services.mozilla.com", @"notify.windows.com" ];
}

static BOOL NMWebPushEndpointIsAllowed(NSURL *endpoint, NSArray<NSString *> *allowedHosts) {
  if (endpoint == nil || ![[[endpoint scheme] lowercaseString] isEqualToString:@"https"]) {
    return NO;
  }
  NSString *host = [[endpoint host] lowercaseString];
  if ([host length] == 0 || [endpoint user] != nil || [endpoint password] != nil) {
    return NO;
  }
  for (NSString *rawAllowed in allowedHosts ?: @[]) {
    NSString *allowed = NMLowerTrimmedString(rawAllowed);
    if ([allowed isEqualToString:@"*"]) {
      return YES;
    }
    if ([allowed hasPrefix:@"."]) {
      allowed = [allowed substringFromIndex:1];
    }
    if ([allowed length] > 0 &&
        ([host isEqualToString:allowed] || [host hasSuffix:[@"." stringByAppendingString:allowed]])) {
      return YES;
    }
  }
  return NO;
}

static NSArray<NSString *> *NMWebPushUrgencies(void) {
  return @[ @"very-low", @"low", @"normal", @"high" ];
}

static NSDictionary *NMNormalizedWebPushMessage(NSDictionary *rawMessage, NSDictionary *payload, NSError **error) {
  NSDictionary *raw = NMNormalizeDictionary(rawMessage);
  BOOL nudge = [raw[@"nudge"] respondsToSelector:@selector(boolValue)] && [raw[@"nudge"] boolValue];
  NSString *title = NMTrimmedString(raw[@"title"]);
  if (!nudge && [title length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"web push messages require a title, or nudge: YES for a content-free push",
                       nil);
    }
    return nil;
  }
  NSString *topic = NMTrimmedString(raw[@"topic"]);
  if ([topic length] > 0 && !ALNWebPushTopicIsValid(topic)) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"web push topic must be 1-32 base64url characters",
                       @{ @"topic" : topic });
    }
    return nil;
  }
  NSString *urgency = NMLowerTrimmedString(raw[@"urgency"]);
  if ([urgency length] > 0 && ![NMWebPushUrgencies() containsObject:urgency]) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"web push urgency must be very-low, low, normal or high",
                       @{ @"urgency" : urgency });
    }
    return nil;
  }
  id ttl = [raw[@"ttl"] respondsToSelector:@selector(doubleValue)] && [raw[@"ttl"] doubleValue] >= 0.0
               ? @((long long)[raw[@"ttl"] doubleValue])
               : [NSNull null];

  NSMutableArray<NSString *> *recipients = [NSMutableArray arrayWithArray:NMRecipientsFromInAppEntry(raw)];
  NSString *payloadRecipient = NMTrimmedString(payload[@"recipient"]);
  if ([payloadRecipient length] == 0) {
    payloadRecipient = NMTrimmedString(payload[@"recipientSubject"]);
  }
  if ([recipients count] == 0 && [payloadRecipient length] > 0) {
    [recipients addObject:payloadRecipient];
  }
  if ([recipients count] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"web push notification requires at least one recipient",
                       nil);
    }
    return nil;
  }

  NSMutableDictionary *content = [NSMutableDictionary dictionary];
  if (nudge) {
    content[@"nudge"] = @YES;
  } else {
    content[@"title"] = title;
    for (NSString *key in @[ @"body", @"url", @"tag" ]) {
      if ([NMTrimmedString(raw[key]) length] > 0) {
        content[key] = NMTrimmedString(raw[key]);
      }
    }
  }
  NSData *payloadData = [NSJSONSerialization dataWithJSONObject:content options:0 error:NULL] ?: [NSData data];
  if ([payloadData length] > ALNWebPushMaxPlaintextLength) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       [NSString stringWithFormat:@"web push payload is %lu bytes; the limit is %lu",
                                                  (unsigned long)[payloadData length],
                                                  (unsigned long)ALNWebPushMaxPlaintextLength],
                       @{ @"bytes" : @([payloadData length]) });
    }
    return nil;
  }
  return @{
    @"title" : nudge ? @"" : title,
    @"body" : nudge ? @"" : NMTrimmedString(raw[@"body"]),
    @"url" : nudge ? @"" : NMTrimmedString(raw[@"url"]),
    @"tag" : nudge ? @"" : NMTrimmedString(raw[@"tag"]),
    @"topic" : topic,
    @"ttl" : ttl,
    @"urgency" : urgency,
    @"nudge" : @(nudge),
    @"recipients" : recipients,
    @"payloadData" : payloadData,
  };
}

static NSDictionary *NMWebPushPreviewRepresentation(NSDictionary *message) {
  NSDictionary *normalized = NMNormalizeDictionary(message);
  return @{
    @"title" : NMTrimmedString(normalized[@"title"]),
    @"body" : NMTrimmedString(normalized[@"body"]),
    @"url" : NMTrimmedString(normalized[@"url"]),
    @"tag" : NMTrimmedString(normalized[@"tag"]),
    @"topic" : NMTrimmedString(normalized[@"topic"]),
    @"urgency" : NMTrimmedString(normalized[@"urgency"]),
    @"nudge" : @([normalized[@"nudge"] boolValue]),
    @"recipients" : NMNormalizeArray(normalized[@"recipients"]),
  };
}

static NSDictionary *NMWebPushPublicSubscription(NSDictionary *subscription) {
  NSDictionary *entry = NMNormalizeDictionary(subscription);
  NSURL *endpoint = [NSURL URLWithString:NMTrimmedString(entry[@"endpoint"])];
  return @{
    @"subscriptionID" : NMTrimmedString(entry[@"subscriptionID"]),
    @"endpointHost" : [[endpoint host] lowercaseString] ?: @"",
    @"userAgent" : NMTrimmedString(entry[@"userAgent"]),
    @"createdAt" : entry[@"createdAt"] ?: @0,
    @"lastSuccessAt" : entry[@"lastSuccessAt"] ?: @0,
    @"active" : @([entry[@"active"] boolValue]),
    @"inactiveReason" : NMTrimmedString(entry[@"inactiveReason"]),
    @"inactiveAt" : entry[@"inactiveAt"] ?: @0,
  };
}

static NSString *NMEnvironmentValue(NSString *name) {
  return NMTrimmedString([[NSProcessInfo processInfo] environment][name]);
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
@property(nonatomic, assign) NSUInteger maxOutboxEntries;
@property(nonatomic, assign) NSUInteger maxInboxEntriesPerRecipient;
@property(nonatomic, strong) id<ALNNotificationPreferenceHook> preferenceHook;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *recentFanoutEvents;
@property(nonatomic, strong) ALNRealtimeHub *realtimeHub;
@property(nonatomic, assign) BOOL persistenceEnabled;
@property(nonatomic, copy) NSString *statePath;
@property(nonatomic, copy) NSDictionary *lastPersistedState;
@property(nonatomic, assign) BOOL webPushEnabled;
@property(nonatomic, strong) ALNWebPushVAPIDKey *webPushVAPIDKey;
@property(nonatomic, copy) NSString *webPushSubject;
@property(nonatomic, assign) NSTimeInterval webPushDefaultTTL;
@property(nonatomic, copy) NSString *webPushDefaultUrgency;
@property(nonatomic, copy) NSArray<NSString *> *webPushAllowedHosts;
@property(nonatomic, assign) NSUInteger webPushMaxSubscriptionsPerRecipient;
@property(nonatomic, assign) BOOL webPushTestRouteEnabled;
@property(nonatomic, copy) NSDictionary *webPushNudgeDefaults;
@property(nonatomic, strong) ALNNotificationsWebPushSubscriptionStore *webPushStore;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *webPushTokenCache;

- (BOOL)registerNotificationDefinition:(id<ALNNotificationDefinition>)definition
                                source:(NSString *)source
                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)artifactsForNotificationIdentifier:(NSString *)identifier
                                                      payload:(NSDictionary *)payload
                                                     channels:(NSArray<NSString *> *)channels
                                                        error:(NSError **)error;
// `deliveryScope` (@{ recipient, email }) marks a notification a user queued
// for themselves over HTTP: every channel's target is replaced with those
// values after the definition runs, whatever the payload or definition chose.
- (nullable NSDictionary *)artifactsForNotificationIdentifier:(NSString *)identifier
                                                      payload:(NSDictionary *)payload
                                                     channels:(NSArray<NSString *> *)channels
                                                deliveryScope:(nullable NSDictionary *)deliveryScope
                                                        error:(NSError **)error;
- (BOOL)channel:(NSString *)channel
    enabledForRecipient:(NSString *)recipient
 notificationIdentifier:(NSString *)identifier
          defaultEnabled:(BOOL)defaultEnabled;
- (BOOL)loadPersistedStateWithError:(NSError *_Nullable *_Nullable)error;
- (BOOL)persistStateWithError:(NSError *_Nullable *_Nullable)error;
- (void)replaceStateLockedFromDocument:(NSDictionary *)state;
- (NSDictionary *)stateDocumentLocked;
- (nullable NSDictionary *)mutateStateWithError:(NSError **)error
                                           block:(NSDictionary *(^)(void))block;
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
- (nullable NSDictionary *)queueNotificationSummaryForIdentifier:(NSString *)identifier
                                                         payload:(NSDictionary *)payload
                                                        channels:(NSArray<NSString *> *)channels
                                                   deliveryScope:(nullable NSDictionary *)deliveryScope
                                                           error:(NSError **)error;
- (NSDictionary *)inboxSummaryLockedForRecipient:(NSString *)recipient;
- (nullable NSDictionary *)deliverWebPushMessage:(NSDictionary *)message
                                      identifier:(NSString *)identifier
                                         payload:(NSDictionary *)payload
                                      jobPayload:(NSDictionary *)jobPayload
                                          policy:(NSDictionary *)policy
                                           error:(NSError **)error;

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
    _maxOutboxEntries = ALNNotificationsDefaultMaxOutboxEntries;
    _maxInboxEntriesPerRecipient = ALNNotificationsDefaultMaxInboxEntriesPerRecipient;
    _recentFanoutEvents = [NSMutableArray array];
    _realtimeHub = [ALNRealtimeHub sharedHub];
    _persistenceEnabled = NO;
    _statePath = @"";
    _lastPersistedState = @{};
    _webPushEnabled = NO;
    _webPushSubject = @"";
    _webPushDefaultTTL = 86400.0;
    _webPushDefaultUrgency = @"normal";
    _webPushAllowedHosts = NMWebPushDefaultAllowedHosts();
    _webPushMaxSubscriptionsPerRecipient = 10;
    _webPushNudgeDefaults = @{};
    _webPushStore = [[ALNNotificationsWebPushSubscriptionStore alloc] initWithPath:nil];
    _webPushTokenCache = [NSMutableDictionary dictionary];
  }
  return self;
}

// notificationsModule.webPush. The ARLEN_WEBPUSH_* environment variables override
// the plist so the VAPID private key never has to live in the repository.
- (BOOL)configureWebPushWithModuleConfig:(NSDictionary *)moduleConfig error:(NSError **)error {
  NSDictionary *config = NMNormalizeDictionary(moduleConfig[@"webPush"]);
  NSDictionary *vapid = NMNormalizeDictionary(config[@"vapid"]);
  BOOL enabled = [config[@"enabled"] respondsToSelector:@selector(boolValue)] && [config[@"enabled"] boolValue];
  NSString *enabledOverride = [NMEnvironmentValue(@"ARLEN_WEBPUSH_ENABLED") lowercaseString];
  if ([enabledOverride length] > 0) {
    enabled = [@[ @"1", @"true", @"yes", @"on" ] containsObject:enabledOverride];
  }
  NSString *publicKey = [NMEnvironmentValue(@"ARLEN_WEBPUSH_VAPID_PUBLIC_KEY") length] > 0
                            ? NMEnvironmentValue(@"ARLEN_WEBPUSH_VAPID_PUBLIC_KEY")
                            : NMTrimmedString(vapid[@"publicKey"]);
  NSString *privateKey = [NMEnvironmentValue(@"ARLEN_WEBPUSH_VAPID_PRIVATE_KEY") length] > 0
                             ? NMEnvironmentValue(@"ARLEN_WEBPUSH_VAPID_PRIVATE_KEY")
                             : NMTrimmedString(vapid[@"privateKey"]);
  NSString *subject = [NMEnvironmentValue(@"ARLEN_WEBPUSH_VAPID_SUBJECT") length] > 0
                          ? NMEnvironmentValue(@"ARLEN_WEBPUSH_VAPID_SUBJECT")
                          : NMTrimmedString(vapid[@"subject"]);

  ALNWebPushVAPIDKey *key = nil;
  if (enabled) {
    NSError *keyError = nil;
    key = [ALNWebPushVAPIDKey keyWithPublicKey:publicKey privateKey:privateKey error:&keyError];
    if (key == nil) {
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"notificationsModule.webPush is enabled but its VAPID keys are unusable: %@",
                                                    keyError.localizedDescription ?: @"invalid key"],
                         nil);
      }
      return NO;
    }
    // Apple's push service rejects tokens without a contact subject.
    if (![subject hasPrefix:@"mailto:"] && ![subject hasPrefix:@"https://"]) {
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                         @"notificationsModule.webPush.vapid.subject must be a mailto: or https: URL",
                         nil);
      }
      return NO;
    }
  }

  NSTimeInterval ttl = [config[@"ttlSeconds"] respondsToSelector:@selector(doubleValue)] ? [config[@"ttlSeconds"] doubleValue] : 86400.0;
  NSString *urgency = NMLowerTrimmedString(config[@"urgency"]);
  if (![NMWebPushUrgencies() containsObject:urgency]) {
    urgency = @"normal";
  }
  NSArray *hosts = [config[@"allowedEndpointHosts"] isKindOfClass:[NSArray class]] ? config[@"allowedEndpointHosts"]
                                                                                   : NMWebPushDefaultAllowedHosts();
  NSUInteger maxSubscriptions = ALNUnsignedIntegerValueOrDefault(config[@"maxSubscriptionsPerRecipient"], 10);
  NSDictionary *testRoute = NMNormalizeDictionary(config[@"testRoute"]);
  NSDictionary *nudge = NMNormalizeDictionary(config[@"nudge"]);
  NSMutableDictionary *nudgeDefaults = [NSMutableDictionary dictionary];
  nudgeDefaults[@"title"] = [NMTrimmedString(nudge[@"title"]) length] > 0 ? NMTrimmedString(nudge[@"title"]) : @"New notification";
  nudgeDefaults[@"body"] = [NMTrimmedString(nudge[@"body"]) length] > 0 ? NMTrimmedString(nudge[@"body"]) : @"Open the app to see it.";
  nudgeDefaults[@"url"] = [NMTrimmedString(nudge[@"url"]) length] > 0 ? NMTrimmedString(nudge[@"url"]) : @"/";
  for (NSString *imageKey in @[ @"icon", @"badge" ]) {
    if ([NMTrimmedString(nudge[imageKey]) length] > 0) {
      nudgeDefaults[imageKey] = NMTrimmedString(nudge[imageKey]);
    }
  }

  id<ALNWebPushTransport> transport = nil;
  NSString *transportClass = NMTrimmedString(config[@"transportClass"]);
  if ([transportClass length] > 0) {
    Class klass = NSClassFromString(transportClass);
    transport = (klass != Nil) ? [[klass alloc] init] : nil;
    if (transport == nil || ![transport conformsToProtocol:@protocol(ALNWebPushTransport)]) {
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"web push transport %@ is invalid", transportClass],
                         @{ @"class" : transportClass });
      }
      return NO;
    }
  }

  // Subscriptions live beside the module state file; the test environment and
  // disabled persistence keep them in memory.
  NSDictionary *subscriptions = NMNormalizeDictionary(config[@"subscriptions"]);
  NSString *storePath = NMTrimmedString(subscriptions[@"path"]);
  if ([storePath length] > 0) {
    storePath = [storePath hasPrefix:@"/"] ? storePath : [self.application pathRelativeToAppRoot:storePath];
  } else if ([self.statePath length] > 0) {
    storePath = [[self.statePath stringByDeletingPathExtension] stringByAppendingString:@"-webpush.plist"];
  }

  [self.lock lock];
  self.webPushEnabled = enabled;
  self.webPushVAPIDKey = key;
  self.webPushSubject = subject ?: @"";
  self.webPushDefaultTTL = MIN(MAX(ttl, 0.0), 2419200.0);
  self.webPushDefaultUrgency = urgency;
  self.webPushAllowedHosts = hosts;
  self.webPushMaxSubscriptionsPerRecipient = MIN(MAX(maxSubscriptions, (NSUInteger)1), (NSUInteger)100);
  self.webPushTestRouteEnabled =
      [testRoute[@"enabled"] respondsToSelector:@selector(boolValue)] && [testRoute[@"enabled"] boolValue];
  self.webPushNudgeDefaults = nudgeDefaults;
  self.webPushStore = [[ALNNotificationsWebPushSubscriptionStore alloc] initWithPath:storePath];
  self.webPushTransport = transport ?: [[ALNWebPushHTTPTransport alloc] init];
  [self.webPushTokenCache removeAllObjects];
  [self.lock unlock];
  return YES;
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
  self.lastPersistedState = @{};
  self.maxOutboxEntries = NMConfiguredLimit(NMNormalizeDictionary(moduleConfig[@"outbox"])[@"maxEntries"],
                                            ALNNotificationsDefaultMaxOutboxEntries);
  self.maxInboxEntriesPerRecipient =
      NMConfiguredLimit(NMNormalizeDictionary(moduleConfig[@"inbox"])[@"maxEntriesPerRecipient"],
                        ALNNotificationsDefaultMaxInboxEntriesPerRecipient);
  self.statePath = NMResolvedPersistencePath(application, moduleConfig);
  self.persistenceEnabled = ([self.statePath length] > 0);
  [self.lock unlock];

  if (![self loadPersistedStateWithError:error]) {
    return NO;
  }
  if (![self configureWebPushWithModuleConfig:moduleConfig error:error]) {
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
  NMTrimOldestEntries(self.outboxEntries, self.maxOutboxEntries);
  NSDictionary *inboxByRecipient = [state[@"inboxByRecipient"] isKindOfClass:[NSDictionary class]]
                                       ? state[@"inboxByRecipient"]
                                       : @{};
  for (NSString *recipient in inboxByRecipient) {
    NSArray *entries = [inboxByRecipient[recipient] isKindOfClass:[NSArray class]] ? inboxByRecipient[recipient] : @[];
    NSMutableArray *normalizedEntries = [NSMutableArray array];
    for (id rawEntry in entries) {
      [normalizedEntries addObject:NMNormalizedInboxEntry(rawEntry)];
    }
    NMTrimOldestEntries(normalizedEntries, self.maxInboxEntriesPerRecipient);
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
  self.lastPersistedState = [state copy];
  [self.lock unlock];
  return YES;
}

- (void)replaceStateLockedFromDocument:(NSDictionary *)state {
  [self.outboxEntries removeAllObjects];
  [self.outboxEntries addObjectsFromArray:NMNormalizeArray(state[@"outboxEntries"])];
  NMTrimOldestEntries(self.outboxEntries, self.maxOutboxEntries);
  [self.inboxByRecipient removeAllObjects];
  for (NSString *recipient in NMNormalizeDictionary(state[@"inboxByRecipient"])) {
    NSMutableArray *entries = [NSMutableArray array];
    for (id rawEntry in NMNormalizeArray(state[@"inboxByRecipient"][recipient])) {
      [entries addObject:NMNormalizedInboxEntry(rawEntry)];
    }
    NMTrimOldestEntries(entries, self.maxInboxEntriesPerRecipient);
    self.inboxByRecipient[recipient] = entries;
  }
  [self.preferencesByRecipient removeAllObjects];
  [self.preferencesByRecipient addEntriesFromDictionary:NMNormalizeDictionary(state[@"preferencesByRecipient"])];
  [self.recentFanoutEvents removeAllObjects];
  [self.recentFanoutEvents addObjectsFromArray:NMNormalizeArray(state[@"recentFanoutEvents"])];
  self.nextEntrySequence = [state[@"nextEntrySequence"] unsignedIntegerValue];
  self.lastPersistedState = state ?: @{};
}

- (NSDictionary *)stateDocumentLocked {
  NSMutableDictionary *inbox = [NSMutableDictionary dictionary];
  for (NSString *recipient in self.inboxByRecipient) {
    inbox[recipient] = [[NSArray alloc] initWithArray:self.inboxByRecipient[recipient] ?: @[] copyItems:YES] ?: @[];
  }
  return @{ @"version" : @1, @"nextEntrySequence" : @(self.nextEntrySequence),
            @"outboxEntries" : [[NSArray alloc] initWithArray:self.outboxEntries copyItems:YES] ?: @[],
            @"inboxByRecipient" : inbox,
            @"preferencesByRecipient" : [NSDictionary dictionaryWithDictionary:self.preferencesByRecipient ?: @{}],
            @"recentFanoutEvents" : [[NSArray alloc] initWithArray:self.recentFanoutEvents copyItems:YES] ?: @[] };
}

- (NSDictionary *)mutateStateWithError:(NSError **)error block:(NSDictionary *(^)(void))block {
  if (self.persistenceEnabled && ![self persistStateWithError:error]) return nil;
  [self.lock lock];
  int stateLock = -1;
  NSDictionary *authoritative = @{};
  if (self.persistenceEnabled) {
    stateLock = ALNPlatformOpenExclusiveLock([self.statePath stringByAppendingString:@".lock"]);
    if (stateLock < 0) {
      if (error != NULL) *error = NMError(ALNNotificationsModuleErrorDeliveryFailed, @"could not lock notification state", nil);
      [self.lock unlock];
      return nil;
    }
    NSError *readError = nil;
    authoritative = NMReadPropertyListAtPath(self.statePath, &readError) ?: @{};
    if (readError != nil) {
      if (error != NULL) *error = readError;
      ALNPlatformReleaseExclusiveLock(stateLock);
      [self.lock unlock];
      return nil;
    }
    [self replaceStateLockedFromDocument:authoritative ?: @{}];
  }
  NSDictionary *result = block();
  if (result != nil && self.persistenceEnabled) {
    NSDictionary *payload = [self stateDocumentLocked];
    if (!NMWritePropertyListAtPath(self.statePath, payload, error)) {
      result = nil;
      [self replaceStateLockedFromDocument:authoritative];
    } else {
      self.lastPersistedState = NMReadPropertyListAtPath(self.statePath, NULL) ?: @{};
    }
  }
  if (stateLock >= 0) ALNPlatformReleaseExclusiveLock(stateLock);
  [self.lock unlock];
  return result;
}

- (BOOL)persistStateWithError:(NSError **)error {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return YES;
  }
  [self.lock lock];
  NSString *directory = [self.statePath stringByDeletingLastPathComponent];
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                 withIntermediateDirectories:YES attributes:nil error:error]) {
    [self.lock unlock];
    return NO;
  }
  int stateLock = ALNPlatformOpenExclusiveLock([self.statePath stringByAppendingString:@".lock"]);
  if (stateLock < 0) {
    if (error != NULL) *error = NMError(ALNNotificationsModuleErrorDeliveryFailed, @"could not lock notification state", nil);
    [self.lock unlock];
    return NO;
  }
  NSError *readError = nil;
  NSDictionary *authoritative = NMReadPropertyListAtPath(self.statePath, &readError) ?: @{};
  if (readError != nil) {
    if (error != NULL) *error = readError;
    ALNPlatformReleaseExclusiveLock(stateLock);
    [self.lock unlock];
    return NO;
  }
  NSDictionary *baseline = self.lastPersistedState ?: @{};
  if ([[self stateDocumentLocked] isEqualToDictionary:baseline]) {
    [self replaceStateLockedFromDocument:authoritative];
    ALNPlatformReleaseExclusiveLock(stateLock);
    [self.lock unlock];
    return YES;
  }
  NSMutableArray *outbox = NMMergeChangedEntries(NMNormalizeArray(authoritative[@"outboxEntries"]),
                                                NMNormalizeArray(baseline[@"outboxEntries"]),
                                                self.outboxEntries, self.maxOutboxEntries);
  NSDictionary *authoritativeInbox = NMNormalizeDictionary(authoritative[@"inboxByRecipient"]);
  NSDictionary *baselineInbox = NMNormalizeDictionary(baseline[@"inboxByRecipient"]);
  NSMutableDictionary *inbox = [NSMutableDictionary dictionaryWithDictionary:authoritativeInbox];
  for (NSString *recipient in self.inboxByRecipient) {
    inbox[recipient] = NMMergeChangedEntries(NMNormalizeArray(authoritativeInbox[recipient]),
                                             NMNormalizeArray(baselineInbox[recipient]),
                                             self.inboxByRecipient[recipient], self.maxInboxEntriesPerRecipient);
  }
  NSDictionary *authoritativePreferences = NMNormalizeDictionary(authoritative[@"preferencesByRecipient"]);
  NSDictionary *baselinePreferences = NMNormalizeDictionary(baseline[@"preferencesByRecipient"]);
  NSMutableDictionary *preferences = [NSMutableDictionary dictionaryWithDictionary:authoritativePreferences];
  for (NSString *recipient in self.preferencesByRecipient) {
    NSDictionary *local = self.preferencesByRecipient[recipient];
    if (![local isEqual:baselinePreferences[recipient]]) preferences[recipient] = local;
  }
  NSMutableArray *fanout = NMMergeChangedEntries(NMNormalizeArray(authoritative[@"recentFanoutEvents"]),
                                                NMNormalizeArray(baseline[@"recentFanoutEvents"]),
                                                self.recentFanoutEvents, 20);
  NSUInteger sequence = MAX(self.nextEntrySequence, [authoritative[@"nextEntrySequence"] unsignedIntegerValue]);
  NSDictionary *payload = @{ @"version" : @1, @"nextEntrySequence" : @(sequence),
                             @"outboxEntries" : outbox, @"inboxByRecipient" : inbox,
                             @"preferencesByRecipient" : preferences, @"recentFanoutEvents" : fanout };
  BOOL saved = NMWritePropertyListAtPath(self.statePath, payload, error);
  if (saved) {
    self.outboxEntries = outbox;
    self.inboxByRecipient = inbox;
    self.preferencesByRecipient = preferences;
    self.recentFanoutEvents = fanout;
    self.nextEntrySequence = sequence;
    // The runtime mutates these containers later; retain an immutable on-disk
    // baseline so the next write can distinguish local edits from peer edits.
    self.lastPersistedState = NMReadPropertyListAtPath(self.statePath, NULL) ?: @{};
  } else {
    [self replaceStateLockedFromDocument:authoritative];
  }
  ALNPlatformReleaseExclusiveLock(stateLock);
  [self.lock unlock];
  return saved;
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
    @"entryID" : [NSString stringWithFormat:@"notification-%@", [[NSUUID UUID] UUIDString].lowercaseString],
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
  NMTrimOldestEntries(self.outboxEntries, self.maxOutboxEntries);
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
  (void)[self persistStateWithError:NULL];
  NSDictionary *webPushSubscriptions = [self.webPushStore summary] ?: @{};
  [self.lock lock];
  NSDictionary *summary = @{
    @"prefix" : self.prefix ?: @"/notifications",
    @"apiPrefix" : self.apiPrefix ?: @"/notifications/api",
    @"sender" : self.senderAddress ?: @"notifications@example.test",
    @"definitionCount" : @([self.metadataByIdentifier count]),
    @"outboxCount" : @([self.outboxEntries count]),
    @"maxOutboxEntries" : @(self.maxOutboxEntries),
    @"maxInboxEntriesPerRecipient" : @(self.maxInboxEntriesPerRecipient),
    @"inboxRecipientCount" : @([self.inboxByRecipient count]),
    @"preferenceRecipientCount" : @([self.preferencesByRecipient count]),
    @"preferenceHookClass" : self.preferenceHook ? NSStringFromClass([(NSObject *)self.preferenceHook class]) : @"",
    @"webhookAdapter" : (self.webhookAdapter != nil) ? [self.webhookAdapter adapterName] : @"",
    @"fanoutEventCount" : @([self.recentFanoutEvents count]),
    @"persistenceEnabled" : @(self.persistenceEnabled),
    @"statePath" : self.statePath ?: @"",
    @"webPush" : @{
      @"enabled" : @(self.webPushEnabled),
      @"vapidPublicKey" : self.webPushVAPIDKey.publicKey ?: @"",
      @"subject" : self.webPushSubject ?: @"",
      @"allowedEndpointHosts" : self.webPushAllowedHosts ?: @[],
      @"subscriptionStorePath" : self.webPushStore.path ?: @"",
      @"testRouteEnabled" : @(self.webPushTestRouteEnabled),
      @"subscriptions" : webPushSubscriptions,
    },
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
  return [self artifactsForNotificationIdentifier:identifier
                                          payload:payload
                                         channels:channels
                                    deliveryScope:nil
                                            error:error];
}

- (NSDictionary *)artifactsForNotificationIdentifier:(NSString *)identifier
                                              payload:(NSDictionary *)payload
                                             channels:(NSArray<NSString *> *)channels
                                        deliveryScope:(NSDictionary *)deliveryScope
                                                error:(NSError **)error {
  NSDictionary *scope = NMNormalizeDictionary(deliveryScope);
  BOOL scoped = ([NMTrimmedString(scope[@"recipient"]) length] > 0);
  NSString *scopeRecipient = NMTrimmedString(scope[@"recipient"]);
  NSString *scopeEmail = NMTrimmedString(scope[@"email"]);
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
  if (scoped) {
    NSMutableDictionary *forced = [NSMutableDictionary dictionaryWithDictionary:normalizedPayload];
    forced[@"recipient"] = scopeRecipient;
    if ([forced[@"recipientSubject"] isKindOfClass:[NSString class]]) {
      forced[@"recipientSubject"] = scopeRecipient;
    }
    [forced removeObjectForKey:@"recipients"];
    if ([scopeEmail length] > 0) {
      forced[@"email"] = scopeEmail;
    } else {
      [forced removeObjectForKey:@"email"];
    }
    normalizedPayload = forced;
  }
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
  if (scoped && [normalizedChannels containsObject:@"webhook"]) {
    // A webhook target is chosen by the definition, so the module cannot
    // point it at the caller. It is left out unless the definition says its
    // webhook target does not depend on the payload.
    BOOL allowed = [definition respondsToSelector:@selector(notificationsModuleAllowsWebhookForSelfQueuedNotifications)] &&
                   [definition notificationsModuleAllowsWebhookForSelfQueuedNotifications];
    if (!allowed) {
      NSMutableArray *withoutWebhook = [NSMutableArray arrayWithArray:normalizedChannels];
      [withoutWebhook removeObject:@"webhook"];
      if ([withoutWebhook count] == 0) {
        if (error != NULL) {
          *error = NMError(ALNNotificationsModuleErrorPolicyRejected,
                           @"the webhook channel is not available for notifications users queue for themselves",
                           @{ @"identifier" : notificationID });
        }
        return nil;
      }
      normalizedChannels = withoutWebhook;
    }
  }
  if (scoped && [normalizedChannels containsObject:@"email"] && [scopeEmail length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"the email channel needs an email address on the signed-in account",
                       @{ @"identifier" : notificationID });
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

  NSDictionary *webPushMessage = nil;
  if ([normalizedChannels containsObject:@"webpush"]) {
    if (![definition respondsToSelector:@selector(notificationsModuleWebPushMessageForPayload:runtime:error:)]) {
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                         @"notification does not support the webpush channel",
                         @{ @"identifier" : notificationID });
      }
      return nil;
    }
    NSError *pushError = nil;
    NSDictionary *rawMessage =
        [definition notificationsModuleWebPushMessageForPayload:normalizedPayload runtime:self error:&pushError];
    webPushMessage = (rawMessage != nil) ? NMNormalizedWebPushMessage(rawMessage, normalizedPayload, &pushError) : nil;
    if (webPushMessage == nil) {
      if (error != NULL) {
        *error = pushError ?: NMError(ALNNotificationsModuleErrorDeliveryFailed,
                                      @"notification did not produce a web push message",
                                      @{ @"identifier" : notificationID });
      }
      return nil;
    }
  }

  if (scoped) {
    // Replace every target the definition produced with the caller's own.
    if (message != nil) {
      NSMutableDictionary *headers = [NSMutableDictionary dictionary];
      for (id key in message.headers ?: @{}) {
        NSString *lower = [[key description] lowercaseString];
        if (![@[ @"to", @"cc", @"bcc" ] containsObject:lower]) {
          headers[key] = message.headers[key];
        }
      }
      message = [[ALNMailMessage alloc] initWithFrom:message.from
                                                  to:@[ scopeEmail ]
                                                  cc:nil
                                                 bcc:nil
                                             subject:message.subject
                                            textBody:message.textBody
                                            htmlBody:message.htmlBody
                                             headers:headers
                                            metadata:message.metadata];
    }
    if (inAppEntry != nil) {
      NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:inAppEntry];
      [entry removeObjectForKey:@"recipients"];
      [entry removeObjectForKey:@"recipientSubject"];
      entry[@"recipient"] = scopeRecipient;
      inAppEntry = entry;
    }
    if (webPushMessage != nil) {
      NSMutableDictionary *push = [NSMutableDictionary dictionaryWithDictionary:webPushMessage];
      push[@"recipients"] = @[ scopeRecipient ];
      webPushMessage = push;
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
    @"webpush" : webPushMessage ?: [NSNull null],
  };
}

- (NSDictionary *)queueNotificationSummaryForIdentifier:(NSString *)identifier
                                                 payload:(NSDictionary *)payload
                                                channels:(NSArray<NSString *> *)channels
                                                   error:(NSError **)error {
  return [self queueNotificationSummaryForIdentifier:identifier
                                             payload:payload
                                            channels:channels
                                       deliveryScope:nil
                                               error:error];
}

- (NSDictionary *)queueNotificationSummaryForIdentifier:(NSString *)identifier
                                                 payload:(NSDictionary *)payload
                                                channels:(NSArray<NSString *> *)channels
                                           deliveryScope:(NSDictionary *)deliveryScope
                                                   error:(NSError **)error {
  NSDictionary *artifacts = [self artifactsForNotificationIdentifier:identifier
                                                             payload:payload
                                                            channels:channels
                                                       deliveryScope:deliveryScope
                                                               error:error];
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
  NSDictionary *webPushMessage = [artifacts[@"webpush"] isKindOfClass:[NSDictionary class]] ? artifacts[@"webpush"] : nil;
  NSArray<NSString *> *preferenceRecipients = NMPreferenceRecipientsFromPayloadAndEntry(normalizedPayload, inAppEntry ?: @{});

  NSMutableArray *jobIDs = [NSMutableArray array];
  NSMutableArray *channelJobs = [NSMutableArray array];
  for (NSString *channel in requestedChannels) {
    NSDictionary *policy = [channelPolicies[channel] isKindOfClass:[NSDictionary class]] ? channelPolicies[channel] : @{};
    NSString *queue = [NMTrimmedString(policy[@"queue"]) length] > 0 ? NMTrimmedString(policy[@"queue"]) : @"default";
    NSUInteger maxAttempts = [policy[@"maxAttempts"] respondsToSelector:@selector(unsignedIntegerValue)]
                                 ? [policy[@"maxAttempts"] unsignedIntegerValue]
                                 : 0;
    NSMutableDictionary *jobPayload = [@{
      @"identifier" : artifacts[@"identifier"] ?: @"",
      @"payload" : normalizedPayload,
      @"channels" : @[ channel ],
    } mutableCopy];
    if ([NMTrimmedString(NMNormalizeDictionary(deliveryScope)[@"recipient"]) length] > 0) {
      jobPayload[@"deliveryScope"] = NMNormalizeDictionary(deliveryScope);
    }
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
    } else if ([channel isEqualToString:@"webpush"] && webPushMessage != nil) {
      for (NSString *recipient in NMNormalizeArray(webPushMessage[@"recipients"])) {
        [self appendOutboxEntryForNotification:artifacts[@"identifier"]
                                       channel:channel
                                     recipient:recipient
                                        status:@"queued"
                                         jobID:jobID
                                         queue:queue
                                    deliveryID:@""
                                       message:NMWebPushPreviewRepresentation(webPushMessage)
                                  errorMessage:nil];
      }
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
  if (![self persistStateWithError:NULL]) return NO;
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
    @"webpush" : [artifacts[@"webpush"] isKindOfClass:[NSDictionary class]]
                     ? NMWebPushPreviewRepresentation(artifacts[@"webpush"])
                     : @{},
    @"recipients" : NMPreferenceRecipientsFromPayloadAndEntry(artifacts[@"payload"], inAppEntry ?: @{}),
  };
}

- (NSDictionary *)processQueuedNotificationPayload:(NSDictionary *)jobPayload
                                             error:(NSError **)error {
  NSDictionary *artifacts =
      [self artifactsForNotificationIdentifier:jobPayload[@"identifier"]
                                       payload:NMNormalizeDictionary(jobPayload[@"payload"])
                                      channels:NMNormalizedChannelArray(jobPayload[@"channels"])
                                 deliveryScope:NMNormalizeDictionary(jobPayload[@"deliveryScope"])
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
        @"entryID" : [NSString stringWithFormat:@"notification-%@", [[NSUUID UUID] UUIDString].lowercaseString],
        @"notification" : identifier,
        @"recipient" : recipient,
        @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
        @"title" : NMTrimmedString(inAppEntry[@"title"]),
        @"body" : NMTrimmedString(inAppEntry[@"body"]),
        @"metadata" : NMNormalizeDictionary(inAppEntry[@"metadata"]),
        @"read" : @NO,
      };
      [inbox addObject:record];
      NMTrimOldestEntries(inbox, self.maxInboxEntriesPerRecipient);
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

  // Web Push runs last: a targeted retry job carries only this channel, so failing
  // the job here never re-sends another channel.
  NSDictionary *webPushMessage = [artifacts[@"webpush"] isKindOfClass:[NSDictionary class]] ? artifacts[@"webpush"] : nil;
  if ([channels containsObject:@"webpush"] && webPushMessage != nil) {
    NSDictionary *metadata = NMNormalizeDictionary(artifacts[@"metadata"]);
    NSDictionary *policy = NMNormalizeDictionary(NMNormalizeDictionary(metadata[@"channelPolicies"])[@"webpush"]);
    NSDictionary *pushSummary = [self deliverWebPushMessage:webPushMessage
                                                 identifier:identifier
                                                    payload:payload
                                                 jobPayload:jobPayload
                                                     policy:policy
                                                      error:error];
    if (pushSummary == nil) {
      (void)[self persistStateWithError:NULL];
      return nil;
    }
    if ([pushSummary[@"delivered"] boolValue]) {
      [deliveredChannels addObject:@"webpush"];
    } else {
      [skippedChannels addObject:@"webpush"];
    }
    [deliveryIDs addObjectsFromArray:NMNormalizeArray(pushSummary[@"deliveryIDs"])];
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

#pragma mark - Web Push

- (NSDictionary *)webPushClientConfiguration {
  [self.lock lock];
  NSDictionary *configuration = @{
    @"enabled" : @(self.webPushEnabled),
    @"vapidPublicKey" : (self.webPushEnabled ? self.webPushVAPIDKey.publicKey : nil) ?: @"",
    @"serviceWorkerPath" : NMPathJoin(self.prefix, @"push/service-worker.js"),
    @"clientScriptPath" : NMPathJoin(self.prefix, @"push/client.js"),
    @"apiPrefix" : self.apiPrefix ?: @"/notifications/api",
    @"testRouteEnabled" : @(self.webPushTestRouteEnabled),
  };
  [self.lock unlock];
  return configuration;
}

- (NSDictionary *)saveWebPushSubscription:(NSDictionary *)subscription
                                userAgent:(NSString *)userAgent
                             forRecipient:(NSString *)recipient
                                    error:(NSError **)error {
  NSString *owner = NMTrimmedString(recipient);
  if ([owner length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed, @"recipient is required", @{ @"field" : @"recipient" });
    }
    return nil;
  }
  if (!self.webPushEnabled) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorPolicyRejected, @"web push is disabled", nil);
    }
    return nil;
  }
  NSDictionary *raw = NMNormalizeDictionary(subscription);
  NSDictionary *keys = NMNormalizeDictionary(raw[@"keys"]);
  NSString *endpoint = NMTrimmedString(raw[@"endpoint"]);
  NSString *p256dh = [NMTrimmedString(keys[@"p256dh"]) length] > 0 ? NMTrimmedString(keys[@"p256dh"]) : NMTrimmedString(raw[@"p256dh"]);
  NSString *auth = [NMTrimmedString(keys[@"auth"]) length] > 0 ? NMTrimmedString(keys[@"auth"]) : NMTrimmedString(raw[@"auth"]);
  NSURL *endpointURL = ([endpoint length] > 0 && [endpoint length] <= 2048) ? [NSURL URLWithString:endpoint] : nil;
  [self.lock lock];
  NSArray *allowedHosts = self.webPushAllowedHosts;
  NSUInteger maxPerRecipient = self.webPushMaxSubscriptionsPerRecipient;
  ALNNotificationsWebPushSubscriptionStore *store = self.webPushStore;
  [self.lock unlock];
  if (!NMWebPushEndpointIsAllowed(endpointURL, allowedHosts)) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                       @"push endpoint must be an https URL on an allowed push service host",
                       @{ @"endpointHost" : [[endpointURL host] lowercaseString] ?: @"" });
    }
    return nil;
  }
  NSData *p256dhData = ([p256dh length] > 0) ? ALNDataFromBase64URLString(p256dh) : nil;
  NSData *authData = ([auth length] > 0) ? ALNDataFromBase64URLString(auth) : nil;
  // Encrypting an empty message checks the point is on P-256 and the secret is 16 bytes.
  if (p256dhData == nil || authData == nil ||
      ALNWebPushEncryptPayload([NSData data], p256dhData, authData, nil, nil, NULL) == nil) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed, @"push subscription keys are invalid", nil);
    }
    return nil;
  }
  NSDictionary *record = [store saveSubscriptionWithEndpoint:endpoint
                                                      p256dh:p256dh
                                                        auth:auth
                                                   userAgent:userAgent
                                                forRecipient:owner
                                             maxPerRecipient:maxPerRecipient
                                                       error:error];
  return (record != nil) ? NMWebPushPublicSubscription(record) : nil;
}

- (BOOL)removeWebPushSubscriptionWithEndpoint:(NSString *)endpoint
                                 forRecipient:(NSString *)recipient
                                        error:(NSError **)error {
  return [self.webPushStore removeSubscriptionWithEndpoint:endpoint forRecipient:recipient error:error];
}

- (NSArray<NSDictionary *> *)webPushSubscriptionsForRecipient:(NSString *)recipient {
  NSMutableArray *subscriptions = [NSMutableArray array];
  for (NSDictionary *entry in [self.webPushStore subscriptionsForRecipient:recipient includeInactive:YES]) {
    [subscriptions addObject:NMWebPushPublicSubscription(entry)];
  }
  return subscriptions;
}

// VAPID tokens last 12 hours (RFC 8292 allows 24) and are reused per push-service
// origin until an hour before they expire.
- (NSString *)webPushAuthorizationForEndpoint:(NSURL *)endpoint error:(NSError **)error {
  NSString *audience = ALNWebPushAudienceForEndpoint(endpoint);
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  [self.lock lock];
  NSDictionary *cached = (audience != nil) ? self.webPushTokenCache[audience] : nil;
  ALNWebPushVAPIDKey *key = self.webPushVAPIDKey;
  NSString *subject = self.webPushSubject;
  [self.lock unlock];
  if ([cached[@"refreshAt"] doubleValue] > now && [cached[@"header"] length] > 0) {
    return cached[@"header"];
  }
  if (audience == nil || key == nil) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorInvalidConfiguration, @"web push is not configured with VAPID keys", nil);
    }
    return nil;
  }
  NSString *header = [key authorizationHeaderForAudience:audience
                                                 subject:subject
                                              expiration:[NSDate dateWithTimeIntervalSince1970:now + 12.0 * 3600.0]
                                                   error:error];
  if (header != nil) {
    [self.lock lock];
    self.webPushTokenCache[audience] = @{ @"header" : header, @"refreshAt" : @(now + 11.0 * 3600.0) };
    [self.lock unlock];
  }
  return header;
}

// One encrypted POST. Outcomes: delivered, expired (the subscription is gone),
// retry (429, 5xx or no response) and failed (any other rejection).
- (NSDictionary *)sendWebPushMessage:(NSDictionary *)message toSubscription:(NSDictionary *)subscription {
  NSURL *endpoint = [NSURL URLWithString:NMTrimmedString(subscription[@"endpoint"])];
  [self.lock lock];
  NSArray *allowedHosts = self.webPushAllowedHosts;
  id<ALNWebPushTransport> transport = self.webPushTransport;
  NSTimeInterval defaultTTL = self.webPushDefaultTTL;
  NSString *defaultUrgency = self.webPushDefaultUrgency;
  [self.lock unlock];

  if (!NMWebPushEndpointIsAllowed(endpoint, allowedHosts)) {
    return @{ @"outcome" : @"failed", @"status" : @0, @"error" : @"push endpoint host is not allowed" };
  }
  NSData *body = ALNWebPushEncryptPayload([message[@"payloadData"] isKindOfClass:[NSData class]] ? message[@"payloadData"] : [NSData data],
                                          ALNDataFromBase64URLString(NMTrimmedString(subscription[@"p256dh"])) ?: [NSData data],
                                          ALNDataFromBase64URLString(NMTrimmedString(subscription[@"auth"])) ?: [NSData data],
                                          nil,
                                          nil,
                                          NULL);
  if (body == nil) {
    return @{ @"outcome" : @"expired", @"status" : @0, @"error" : @"subscription keys are invalid" };
  }
  NSError *authorizationError = nil;
  NSString *authorization = [self webPushAuthorizationForEndpoint:endpoint error:&authorizationError];
  if (authorization == nil) {
    return @{ @"outcome" : @"failed", @"status" : @0, @"error" : authorizationError.localizedDescription ?: @"VAPID signing failed" };
  }

  NSTimeInterval ttl = [message[@"ttl"] respondsToSelector:@selector(doubleValue)] ? [message[@"ttl"] doubleValue] : defaultTTL;
  NSString *urgency = [NMTrimmedString(message[@"urgency"]) length] > 0 ? NMTrimmedString(message[@"urgency"]) : defaultUrgency;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint];
  [request setHTTPMethod:@"POST"];
  [request setHTTPBody:body];
  [request setTimeoutInterval:15.0];
  [request setValue:authorization forHTTPHeaderField:@"Authorization"];
  [request setValue:[NSString stringWithFormat:@"%lld", (long long)ttl] forHTTPHeaderField:@"TTL"];
  [request setValue:urgency forHTTPHeaderField:@"Urgency"];
  [request setValue:@"aes128gcm" forHTTPHeaderField:@"Content-Encoding"];
  [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
  if ([NMTrimmedString(message[@"topic"]) length] > 0) {
    [request setValue:NMTrimmedString(message[@"topic"]) forHTTPHeaderField:@"Topic"];
  }

  NSError *transportError = nil;
  NSDictionary *response = [transport webPushSendRequest:request error:&transportError];
  if (response == nil) {
    return @{
      @"outcome" : @"retry",
      @"status" : @0,
      @"retryAfter" : @(-1),
      @"error" : transportError.localizedDescription ?: @"push service did not respond",
    };
  }
  NSInteger status = [response[@"status"] integerValue];
  NSDictionary *headers = NMNormalizeDictionary(response[@"headers"]);
  NSTimeInterval retryAfter = ALNWebPushRetryAfterSeconds(NMTrimmedString(headers[@"retry-after"]), [NSDate date]);
  NSString *outcome = @"failed";
  if (status >= 200 && status < 300) {
    outcome = @"delivered";
  } else if (status == 404 || status == 410) {
    outcome = @"expired";
  } else if (status == 429 || status >= 500) {
    outcome = @"retry";
  }
  return @{
    @"outcome" : outcome,
    @"status" : @(status),
    @"retryAfter" : @(retryAfter),
    @"deliveryID" : NMTrimmedString(headers[@"location"]),
    @"error" : [outcome isEqualToString:@"delivered"]
                   ? @""
                   : [NSString stringWithFormat:@"push service returned HTTP %ld", (long)status],
  };
}

// Sends to each subscription and records the outcome. Delivered subscriptions note
// the time; expired ones are kept but marked inactive so the app can tell the user.
- (NSDictionary *)sendWebPushMessage:(NSDictionary *)message
                     toSubscriptions:(NSArray<NSDictionary *> *)subscriptions
                        notification:(NSString *)identifier {
  NSDictionary *preview = NMWebPushPreviewRepresentation(message);
  NSMutableArray *results = [NSMutableArray array];
  NSMutableArray *deliveryIDs = [NSMutableArray array];
  NSMutableArray *retryIDs = [NSMutableArray array];
  NSTimeInterval retryAfter = 0.0;
  NSUInteger deliveredCount = 0;
  for (NSDictionary *subscription in subscriptions) {
    NSString *subscriptionID = NMTrimmedString(subscription[@"subscriptionID"]);
    NSDictionary *result = [self sendWebPushMessage:message toSubscription:subscription];
    NSString *outcome = result[@"outcome"];
    NSString *status = @"failed";
    if ([outcome isEqualToString:@"delivered"]) {
      status = @"delivered";
      deliveredCount += 1;
      [self.webPushStore recordSuccessForSubscriptionID:subscriptionID];
      [deliveryIDs addObject:[result[@"deliveryID"] length] > 0 ? result[@"deliveryID"]
                                                                  : [@"webpush:" stringByAppendingString:subscriptionID]];
    } else if ([outcome isEqualToString:@"expired"]) {
      status = @"expired";
      [self.webPushStore deactivateSubscriptionID:subscriptionID reason:result[@"error"] ?: @"expired"];
    } else if ([outcome isEqualToString:@"retry"]) {
      status = @"retrying";
      [retryIDs addObject:subscriptionID];
      retryAfter = MAX(retryAfter, [result[@"retryAfter"] doubleValue]);
    }
    NSMutableDictionary *entryMessage = [preview mutableCopy];
    entryMessage[@"subscriptionID"] = subscriptionID;
    entryMessage[@"endpointHost"] = [[[NSURL URLWithString:NMTrimmedString(subscription[@"endpoint"])] host] lowercaseString] ?: @"";
    entryMessage[@"httpStatus"] = result[@"status"] ?: @0;
    [self appendOutboxEntryForNotification:identifier
                                   channel:@"webpush"
                                 recipient:NMTrimmedString(subscription[@"recipient"])
                                    status:status
                                     jobID:@""
                                     queue:@""
                                deliveryID:[status isEqualToString:@"delivered"] ? [deliveryIDs lastObject] : @""
                                   message:entryMessage
                              errorMessage:result[@"error"]];
    [results addObject:@{
      @"subscriptionID" : subscriptionID,
      @"endpointHost" : entryMessage[@"endpointHost"],
      @"outcome" : outcome ?: @"failed",
      @"status" : result[@"status"] ?: @0,
      @"error" : result[@"error"] ?: @"",
    }];
  }
  return @{
    @"results" : results,
    @"deliveredCount" : @(deliveredCount),
    @"deliveryIDs" : deliveryIDs,
    @"retryIDs" : retryIDs,
    @"retryAfter" : @(retryAfter),
  };
}

- (NSDictionary *)deliverWebPushMessage:(NSDictionary *)message
                             identifier:(NSString *)identifier
                                payload:(NSDictionary *)payload
                             jobPayload:(NSDictionary *)jobPayload
                                 policy:(NSDictionary *)policy
                                  error:(NSError **)error {
  NSArray<NSString *> *recipients = NMNormalizeArray(message[@"recipients"]);
  NSDictionary *preview = NMWebPushPreviewRepresentation(message);
  if (!self.webPushEnabled) {
    [self appendOutboxEntryForNotification:identifier
                                   channel:@"webpush"
                                 recipient:([recipients count] > 0) ? recipients[0] : @""
                                    status:@"suppressed"
                                     jobID:@""
                                     queue:@""
                                deliveryID:@""
                                   message:preview
                              errorMessage:@"web push is disabled"];
    return @{ @"delivered" : @NO, @"deliveryIDs" : @[] };
  }

  NSMutableArray<NSString *> *enabledRecipients = [NSMutableArray array];
  for (NSString *recipient in recipients) {
    if ([self channel:@"webpush" enabledForRecipient:recipient notificationIdentifier:identifier defaultEnabled:YES]) {
      [enabledRecipients addObject:recipient];
      continue;
    }
    [self appendOutboxEntryForNotification:identifier
                                   channel:@"webpush"
                                 recipient:recipient
                                    status:@"suppressed"
                                     jobID:@""
                                     queue:@""
                                deliveryID:@""
                                   message:preview
                              errorMessage:@"suppressed by preference policy"];
  }

  // A retry job names the subscriptions that still need this message, so devices
  // that already received it are not notified twice.
  NSMutableArray<NSString *> *targetIDs = [NSMutableArray array];
  for (id rawID in NMNormalizeArray(jobPayload[@"webPushSubscriptionIDs"])) {
    if ([NMTrimmedString(rawID) length] > 0) {
      [targetIDs addObject:NMTrimmedString(rawID)];
    }
  }
  BOOL targeted = ([targetIDs count] > 0);
  NSMutableArray<NSDictionary *> *subscriptions = [NSMutableArray array];
  if (targeted) {
    for (NSString *subscriptionID in targetIDs) {
      NSDictionary *subscription = [self.webPushStore subscriptionWithID:subscriptionID];
      if ([subscription[@"active"] boolValue] && [enabledRecipients containsObject:NMTrimmedString(subscription[@"recipient"])]) {
        [subscriptions addObject:subscription];
      }
    }
  } else {
    for (NSString *recipient in enabledRecipients) {
      NSArray *active = [self.webPushStore subscriptionsForRecipient:recipient includeInactive:NO];
      if ([active count] == 0) {
        [self appendOutboxEntryForNotification:identifier
                                       channel:@"webpush"
                                     recipient:recipient
                                        status:@"skipped"
                                         jobID:@""
                                         queue:@""
                                    deliveryID:@""
                                       message:preview
                                  errorMessage:@"no active push subscriptions"];
      }
      [subscriptions addObjectsFromArray:active];
    }
  }

  NSDictionary *sent = [self sendWebPushMessage:message toSubscriptions:subscriptions notification:identifier];
  NSArray *retryIDs = NMNormalizeArray(sent[@"retryIDs"]);
  NSTimeInterval retryAfter = [sent[@"retryAfter"] doubleValue];
  if ([retryIDs count] > 0) {
    if (targeted) {
      NSMutableDictionary *details = [@{ @"subscriptionIDs" : retryIDs } mutableCopy];
      if (retryAfter > 0.0) {
        details[ALNJobsModuleRetryAfterSecondsErrorKey] = @(retryAfter);
      }
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorDeliveryFailed, @"push service asked for a retry", details);
      }
      return nil;
    }
    NSDictionary *backoff = NMNormalizedRetryBackoff(policy[@"retryBackoff"]);
    NSTimeInterval delay = MAX(retryAfter, [backoff[@"baseSeconds"] doubleValue]);
    NSMutableDictionary *options = [@{
      @"queue" : [NMTrimmedString(policy[@"queue"]) length] > 0 ? NMTrimmedString(policy[@"queue"]) : @"default",
      @"source" : @"notification",
      @"notBefore" : [NSDate dateWithTimeIntervalSinceNow:delay],
    } mutableCopy];
    if ([policy[@"maxAttempts"] respondsToSelector:@selector(unsignedIntegerValue)] &&
        [policy[@"maxAttempts"] unsignedIntegerValue] > 0) {
      options[@"maxAttempts"] = policy[@"maxAttempts"];
    }
    if ([policy[@"retryBackoff"] isKindOfClass:[NSDictionary class]]) {
      options[@"retryBackoff"] = policy[@"retryBackoff"];
    }
    NSError *enqueueError = nil;
    NSString *jobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:ALNNotificationsDispatchJobIdentifier
                                                                         payload:@{
                                                                           @"identifier" : identifier ?: @"",
                                                                           @"payload" : payload ?: @{},
                                                                           @"channels" : @[ @"webpush" ],
                                                                           @"webPushSubscriptionIDs" : retryIDs,
                                                                         }
                                                                         options:options
                                                                           error:&enqueueError];
    if ([jobID length] == 0) {
      if (error != NULL) {
        *error = enqueueError ?: NMError(ALNNotificationsModuleErrorDeliveryFailed, @"could not schedule a web push retry", nil);
      }
      return nil;
    }
  }
  return @{
    @"delivered" : @([sent[@"deliveredCount"] unsignedIntegerValue] > 0),
    @"deliveryIDs" : NMNormalizeArray(sent[@"deliveryIDs"]),
  };
}

- (NSDictionary *)sendWebPushTestToRecipient:(NSString *)recipient error:(NSError **)error {
  NSString *owner = NMTrimmedString(recipient);
  if ([owner length] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorValidationFailed, @"recipient is required", @{ @"field" : @"recipient" });
    }
    return nil;
  }
  if (!self.webPushEnabled) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorPolicyRejected, @"web push is disabled", nil);
    }
    return nil;
  }
  NSArray *subscriptions = [self.webPushStore subscriptionsForRecipient:owner includeInactive:NO];
  if ([subscriptions count] == 0) {
    if (error != NULL) {
      *error = NMError(ALNNotificationsModuleErrorNotFound, @"no active push subscriptions for this recipient", nil);
    }
    return nil;
  }
  [self.lock lock];
  NSString *url = NMTrimmedString(self.webPushNudgeDefaults[@"url"]);
  [self.lock unlock];
  NSDictionary *message = NMNormalizedWebPushMessage(@{
    @"title" : @"Test notification",
    @"body" : @"Web Push is working on this device.",
    @"url" : ([url length] > 0) ? url : @"/",
    @"tag" : @"arlen-webpush-test",
    @"recipient" : owner,
  },
                                                     @{}, error);
  if (message == nil) {
    return nil;
  }
  NSDictionary *sent = [self sendWebPushMessage:message toSubscriptions:subscriptions notification:@"webpush.test"];
  if (![self persistStateWithError:error]) {
    return nil;
  }
  return @{
    @"recipient" : owner,
    @"sentCount" : @([subscriptions count]),
    @"deliveredCount" : sent[@"deliveredCount"] ?: @0,
    @"results" : sent[@"results"] ?: @[],
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
  if (![self persistStateWithError:NULL]) return @[];
  [self.lock lock];
  NSArray *snapshot = [[NSArray alloc] initWithArray:self.outboxEntries copyItems:YES];
  [self.lock unlock];
  return snapshot ?: @[];
}

- (NSDictionary *)outboxEntryForIdentifier:(NSString *)entryID {
  NSString *targetID = NMTrimmedString(entryID);
  if (![self persistStateWithError:NULL]) return nil;
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
  if (![self persistStateWithError:NULL]) return @[];
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
  if (![self persistStateWithError:NULL]) return NMInboxSummary(normalizedRecipient, @[]);
  [self.lock lock];
  NSDictionary *summary = [self inboxSummaryLockedForRecipient:normalizedRecipient];
  [self.lock unlock];
  return summary ?: NMInboxSummary(normalizedRecipient, @[]);
}

- (NSDictionary *)inboxSummaryForRecipient:(NSString *)recipient
                                     limit:(NSUInteger)limit
                                    offset:(NSUInteger)offset {
  NSDictionary *summary = [self inboxSummaryForRecipient:recipient];
  NSArray *entries = NMNormalizeArray(summary[@"entries"]);
  NSUInteger total = [entries count];
  NSUInteger resolvedLimit = (limit == 0U) ? total : MIN(limit, ALNNotificationsMaxInboxPageLimit);
  NSUInteger start = MIN(offset, total);
  NSUInteger length = MIN(resolvedLimit, total - start);
  NSArray *page = [entries subarrayWithRange:NSMakeRange(start, length)];
  NSMutableDictionary *paged = [NSMutableDictionary dictionaryWithDictionary:summary];
  paged[@"entries"] = page ?: @[];
  paged[@"pagination"] = @{
    @"limit" : @(resolvedLimit),
    @"offset" : @(start),
    @"returned" : @([page count]),
    @"total" : @(total),
    @"hasMore" : @((start + length) < total),
  };
  return paged;
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

  __block NSError *missingEntryError = nil;
  NSDictionary *result = [self mutateStateWithError:error block:^NSDictionary *{
    NSMutableArray *storedInbox = self.inboxByRecipient[normalizedRecipient];
    NSUInteger matchIndex = NSNotFound;
    for (NSUInteger idx = 0; idx < [storedInbox count]; idx++) {
      NSDictionary *entry = NMNormalizedInboxEntry(storedInbox[idx]);
      if ([entry[@"entryID"] isEqualToString:normalizedEntryID]) {
        matchIndex = idx;
        break;
      }
    }
    if (matchIndex == NSNotFound) {
      missingEntryError = NMError(ALNNotificationsModuleErrorNotFound, @"inbox entry not found",
                                  @{ @"recipient" : normalizedRecipient, @"entryID" : normalizedEntryID });
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
    return @{ @"recipient" : normalizedRecipient, @"entry" : [updatedEntry copy],
              @"totalCount" : summary[@"totalCount"] ?: @0,
              @"unreadCount" : summary[@"unreadCount"] ?: @0 };
  }];
  if (result == nil && missingEntryError != nil && error != NULL) *error = missingEntryError;
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

  return [self mutateStateWithError:error block:^NSDictionary *{
    NSMutableArray *storedInbox = self.inboxByRecipient[normalizedRecipient] ?: [NSMutableArray array];
    NSUInteger updatedCount = 0;
    NSNumber *readAt = @([[NSDate date] timeIntervalSince1970]);
    for (NSUInteger idx = 0; idx < [storedInbox count]; idx++) {
      NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:NMNormalizedInboxEntry(storedInbox[idx])];
      if (![entry[@"read"] boolValue]) {
        entry[@"read"] = @YES;
        entry[@"readAt"] = readAt;
        updatedCount += 1;
      }
      storedInbox[idx] = entry;
    }
    self.inboxByRecipient[normalizedRecipient] = storedInbox;
    NSDictionary *summary = [self inboxSummaryLockedForRecipient:normalizedRecipient];
    return @{ @"recipient" : normalizedRecipient, @"updatedCount" : @(updatedCount),
              @"totalCount" : summary[@"totalCount"] ?: @0,
              @"unreadCount" : summary[@"unreadCount"] ?: @0 };
  }];
}

- (NSDictionary *)notificationPreferencesForRecipient:(NSString *)recipient {
  NSString *normalizedRecipient = NMTrimmedString(recipient);
  if (![self persistStateWithError:NULL]) return @{};
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
  NSMutableSet<NSString *> *knownIdentifiers = [NSMutableSet set];
  NSMutableSet<NSString *> *knownChannels = [NSMutableSet setWithArray:@[ @"email", @"in_app", @"webhook", @"webpush" ]];
  for (NSDictionary *definition in [self registeredNotifications]) {
    [knownIdentifiers addObject:NMTrimmedString(definition[@"identifier"])];
    [knownChannels addObjectsFromArray:NMNormalizeArray(definition[@"channels"])];
  }
  for (id notificationKey in rawPreferences) {
    NSString *identifier = NMTrimmedString(notificationKey);
    NSDictionary *channelMap = [rawPreferences[notificationKey] isKindOfClass:[NSDictionary class]] ? rawPreferences[notificationKey] : nil;
    if ([identifier length] == 0 || channelMap == nil) {
      continue;
    }
    if (![knownIdentifiers containsObject:identifier]) {
      if (error != NULL) {
        *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                         @"unknown notification in preferences",
                         @{ @"field" : @"preferences", @"notification" : identifier });
      }
      return nil;
    }
    NSMutableDictionary *normalizedChannels = [NSMutableDictionary dictionary];
    for (id channelKey in channelMap) {
      NSString *channel = NMLowerTrimmedString(channelKey);
      id value = channelMap[channelKey];
      if ([channel length] == 0 || ![value respondsToSelector:@selector(boolValue)]) {
        continue;
      }
      if (![knownChannels containsObject:channel]) {
        if (error != NULL) {
          *error = NMError(ALNNotificationsModuleErrorValidationFailed,
                           @"unknown notification channel in preferences",
                           @{ @"field" : @"preferences", @"notification" : identifier, @"channel" : channel });
        }
        return nil;
      }
      normalizedChannels[channel] = @([value boolValue]);
    }
    if ([normalizedChannels count] > 0) {
      normalized[identifier] = [NSDictionary dictionaryWithDictionary:normalizedChannels];
    }
  }
  return [self mutateStateWithError:error block:^NSDictionary *{
    self.preferencesByRecipient[normalizedRecipient] = [NSDictionary dictionaryWithDictionary:normalized];
    return @{ @"recipient" : normalizedRecipient,
              @"preferences" : [self.preferencesByRecipient[normalizedRecipient] copy] ?: @{} };
  }];
}

- (NSDictionary *)dashboardSummary {
  NSArray *definitions = [self registeredNotifications];
  NSArray *outbox = [self outboxSnapshot];
  NSDictionary *webPushSubscriptions = [self.webPushStore summary] ?: @{};
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
      @{ @"label" : @"Push subscriptions", @"value" : webPushSubscriptions[@"activeSubscriptionCount"] ?: @0 },
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
    NSString *location = NMStepUpLocation(self.authRuntime, NMPercentEncodedQueryComponent([self notificationsReturnPathForContext:ctx]));
    [self redirectTo:location status:302];
    return NO;
  }
  return YES;
}

- (id)inboxHTML:(ALNContext *)ctx {
  return [self renderInboxPageForContext:ctx message:@"" errors:nil];
}

- (NSUInteger)inboxPaginationValueForName:(NSString *)name {
  id rawValue = self.context.request.queryParams[name];
  if ([rawValue isKindOfClass:[NSString class]] || [rawValue isKindOfClass:[NSNumber class]]) {
    long long value = [rawValue longLongValue];
    return (value > 0) ? (NSUInteger)value : 0U;
  }
  return 0U;
}

- (NSDictionary *)inboxPageForRecipient:(NSString *)recipient {
  return [self.runtime inboxSummaryForRecipient:recipient
                                          limit:[self inboxPaginationValueForName:@"limit"]
                                         offset:[self inboxPaginationValueForName:@"offset"]] ?: @{};
}

- (id)renderInboxPageForContext:(ALNContext *)ctx
                        message:(NSString *)message
                         errors:(NSArray *)errors {
  NSString *recipient = [ctx authSubject] ?: @"";
  NSMutableDictionary *inboxSummary = [NSMutableDictionary dictionaryWithDictionary:[self inboxPageForRecipient:recipient]];
  NSMutableArray *displayEntries = [NSMutableArray array];
  for (NSDictionary *entry in NMNormalizeArray(inboxSummary[@"entries"])) {
    NSMutableDictionary *displayEntry = [NSMutableDictionary dictionaryWithDictionary:entry];
    NSDictionary *metadata = NMNormalizeDictionary(entry[@"metadata"]);
    displayEntry[@"linkHref"] = NMSafeInboxHref(metadata[@"href"] ?: metadata[@"path"]);
    [displayEntries addObject:displayEntry];
  }
  inboxSummary[@"entries"] = displayEntries;
  NSDictionary *pagination = NMNormalizeDictionary(inboxSummary[@"pagination"]);
  NSUInteger pageLimit = [pagination[@"limit"] unsignedIntegerValue];
  NSUInteger pageOffset = [pagination[@"offset"] unsignedIntegerValue];
  NSString *inboxPath = NMPathJoin(self.runtime.prefix, @"inbox");
  if ([pagination[@"hasMore"] boolValue] && pageLimit > 0U) {
    inboxSummary[@"nextPagePath"] = [NSString stringWithFormat:@"%@?limit=%lu&offset=%lu",
                                                               inboxPath,
                                                               (unsigned long)pageLimit,
                                                               (unsigned long)(pageOffset + pageLimit)];
  }
  if (pageOffset > 0U && pageLimit > 0U) {
    inboxSummary[@"previousPagePath"] = [NSString stringWithFormat:@"%@?limit=%lu&offset=%lu",
                                                                   inboxPath,
                                                                   (unsigned long)pageLimit,
                                                                   (unsigned long)((pageOffset > pageLimit) ? (pageOffset - pageLimit) : 0U)];
  }
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
  NSDictionary *summary = [self inboxPageForRecipient:recipient];
  [self renderJSONEnvelopeWithData:@{
    @"recipient" : recipient ?: @"",
    @"inbox" : summary[@"entries"] ?: @[],
    @"totalCount" : summary[@"totalCount"] ?: @0,
    @"unreadCount" : summary[@"unreadCount"] ?: @0,
    @"pagination" : summary[@"pagination"] ?: @{},
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

// Payload keys that choose who a notification goes to.
static BOOL NMPayloadTargetsOnlySubject(NSDictionary *payload, NSString *subject) {
  for (NSString *key in @[ @"recipient", @"recipientSubject" ]) {
    NSString *value = NMTrimmedString(payload[key]);
    if ([value length] > 0 && ![value isEqualToString:subject]) {
      return NO;
    }
  }
  id recipients = payload[@"recipients"];
  if (recipients != nil && ![recipients isKindOfClass:[NSArray class]] && ![recipients isKindOfClass:[NSNull class]]) {
    return NO;
  }
  for (id value in [recipients isKindOfClass:[NSArray class]] ? recipients : @[]) {
    if (![NMTrimmedString(value) isEqualToString:subject]) {
      return NO;
    }
  }
  return YES;
}

// The HTTP queue route lets a signed-in user queue notifications only for
// themselves. Below the admin role at AAL2 the payload may not name anyone else
// (`recipient`, `recipientSubject`, `recipients` or `email`; 403), and the
// notification is queued with a delivery scope of the caller's subject and own
// email address: after the definition runs, every channel's target is replaced
// with those values, so no other payload key can choose who or where it goes.
// Returns nil after rendering an error response. *deliveryScope is nil for
// admins at AAL2.
- (NSDictionary *)queuePayloadForContext:(ALNContext *)ctx
                                 payload:(NSDictionary *)rawPayload
                           deliveryScope:(NSDictionary **)deliveryScope {
  if (deliveryScope != NULL) {
    *deliveryScope = nil;
  }
  NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:rawPayload ?: @{}];
  if ([[ctx authRoles] containsObject:@"admin"] && [ctx authAssuranceLevel] >= 2) {
    return payload;
  }
  NSString *subject = NMTrimmedString([ctx authSubject]);
  if ([subject length] == 0) {
    [self setStatus:401];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : @"authentication required" } error:NULL];
    return nil;
  }
  NSDictionary *user = [self.authRuntime currentUserForContext:ctx error:NULL];
  NSString *ownEmail = NMTrimmedString(user[@"email"]);
  if ([ownEmail length] == 0) {
    // Apps that sign users in with bearer tokens: a verified email claim.
    NSDictionary *claims = NMNormalizeDictionary(ctx.stash[ALNContextAuthClaimsStashKey]);
    if ([claims[@"email_verified"] respondsToSelector:@selector(boolValue)] && [claims[@"email_verified"] boolValue]) {
      ownEmail = NMTrimmedString(claims[@"email"]);
    }
  }
  NSString *requestedEmail = NMTrimmedString(payload[@"email"]);
  BOOL emailIsOwn = ([requestedEmail length] == 0) ||
                    ([ownEmail length] > 0 && [requestedEmail caseInsensitiveCompare:ownEmail] == NSOrderedSame);
  if (!NMPayloadTargetsOnlySubject(payload, subject) || !emailIsOwn) {
    [self setStatus:403];
    [self renderJSONEnvelopeWithData:nil
                                meta:@{
                                  @"error" : @"queueing a notification for another recipient or email address "
                                             "requires the admin role and AAL2",
                                }
                               error:NULL];
    return nil;
  }
  if (deliveryScope != NULL) {
    *deliveryScope = @{ @"recipient" : subject, @"email" : ownEmail ?: @"" };
  }
  return payload;
}

- (id)apiQueue:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSDictionary *deliveryScope = nil;
  NSDictionary *payload = [self queuePayloadForContext:ctx
                                               payload:NMNormalizeDictionary(parameters[@"payload"])
                                         deliveryScope:&deliveryScope];
  if (payload == nil) {
    return nil;
  }
  NSError *error = nil;
  NSDictionary *summary =
      [self.runtime queueNotificationSummaryForIdentifier:NMTrimmedString(parameters[@"notification"])
                                                  payload:payload
                                                 channels:NMNormalizeArray(parameters[@"channels"])
                                            deliveryScope:deliveryScope
                                                    error:&error];
  if (summary == nil) {
    [self setStatus:(error.code == ALNNotificationsModuleErrorPolicyRejected) ? 403 : 422];
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

- (NSInteger)statusForWebPushError:(NSError *)error {
  switch (error.code) {
  case ALNNotificationsModuleErrorNotFound:
    return 404;
  case ALNNotificationsModuleErrorPolicyRejected:
    return 409;
  case ALNNotificationsModuleErrorValidationFailed:
    return 422;
  default:
    return 500;
  }
}

- (BOOL)renderWebPushError:(NSError *)error fallback:(NSString *)fallback {
  [self setStatus:[self statusForWebPushError:error]];
  [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: fallback } error:NULL];
  return YES;
}

- (NSString *)webPushRecipientForContext:(ALNContext *)ctx {
  NSString *recipient = NMTrimmedString([ctx authSubject]);
  if ([recipient length] == 0) {
    [self setStatus:401];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : @"authentication required" } error:NULL];
    return nil;
  }
  return recipient;
}

- (id)apiWebPushConfig:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:[self.runtime webPushClientConfiguration] meta:nil error:NULL];
  return nil;
}

- (id)apiWebPushSubscriptions:(ALNContext *)ctx {
  NSString *recipient = [self webPushRecipientForContext:ctx];
  if (recipient == nil) {
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{
    @"recipient" : recipient,
    @"subscriptions" : [self.runtime webPushSubscriptionsForRecipient:recipient] ?: @[],
  }
                              meta:nil
                             error:NULL];
  return nil;
}

- (id)apiWebPushSubscribe:(ALNContext *)ctx {
  NSString *recipient = [self webPushRecipientForContext:ctx];
  if (recipient == nil) {
    return nil;
  }
  NSDictionary *parameters = [self requestParameters];
  NSDictionary *subscription = [parameters[@"subscription"] isKindOfClass:[NSDictionary class]] ? parameters[@"subscription"] : parameters;
  NSError *error = nil;
  NSDictionary *saved = [self.runtime saveWebPushSubscription:subscription
                                                    userAgent:[self headerValueForName:@"user-agent"]
                                                 forRecipient:recipient
                                                        error:&error];
  if (saved == nil) {
    [self renderWebPushError:error fallback:@"subscription failed"];
    return nil;
  }
  [self setStatus:201];
  [self renderJSONEnvelopeWithData:@{ @"subscription" : saved } meta:nil error:NULL];
  return nil;
}

- (id)apiWebPushUnsubscribe:(ALNContext *)ctx {
  NSString *recipient = [self webPushRecipientForContext:ctx];
  if (recipient == nil) {
    return nil;
  }
  NSDictionary *parameters = [self requestParameters];
  NSString *endpoint = NMTrimmedString(parameters[@"endpoint"]);
  NSString *subscriptionID = NMTrimmedString(parameters[@"subscriptionID"]);
  NSError *error = nil;
  BOOL removed = NO;
  if ([endpoint length] > 0) {
    removed = [self.runtime removeWebPushSubscriptionWithEndpoint:endpoint forRecipient:recipient error:&error];
  } else if ([subscriptionID length] > 0) {
    removed = [self.runtime.webPushStore removeSubscriptionID:subscriptionID forRecipient:recipient error:&error];
  } else {
    error = NMError(ALNNotificationsModuleErrorValidationFailed, @"endpoint or subscriptionID is required", nil);
  }
  if (error != nil) {
    [self renderWebPushError:error fallback:@"unsubscribe failed"];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"removed" : @(removed) } meta:nil error:NULL];
  return nil;
}

- (id)apiWebPushTest:(ALNContext *)ctx {
  NSString *recipient = [self webPushRecipientForContext:ctx];
  if (recipient == nil) {
    return nil;
  }
  NSError *error = nil;
  NSDictionary *result = [self.runtime sendWebPushTestToRecipient:recipient error:&error];
  if (result == nil) {
    [self renderWebPushError:error fallback:@"test push failed"];
    return nil;
  }
  [self renderJSONEnvelopeWithData:result meta:nil error:NULL];
  return nil;
}

// Served from a route rather than a static file so it can carry
// Service-Worker-Allowed: / and control pages outside the module's path.
- (id)webPushServiceWorker:(ALNContext *)ctx {
  [ctx.response setHeader:@"Service-Worker-Allowed" value:@"/"];
  [ctx.response setHeader:@"Cache-Control" value:@"no-cache"];
  NSString *script = ALNWebPushServiceWorkerScript(self.runtime.webPushNudgeDefaults ?: @{});
  [self renderData:[script dataUsingEncoding:NSUTF8StringEncoding] contentType:@"text/javascript; charset=utf-8"];
  return nil;
}

- (id)webPushClientScript:(ALNContext *)ctx {
  [ctx.response setHeader:@"Cache-Control" value:@"no-cache"];
  [self renderData:[ALNWebPushClientScript() dataUsingEncoding:NSUTF8StringEncoding]
       contentType:@"text/javascript; charset=utf-8"];
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
  [application registerRouteMethod:@"GET"
                              path:@"/push/config"
                              name:@"notifications_api_push_config"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiWebPushConfig"];
  [application registerRouteMethod:@"GET"
                              path:@"/push/subscriptions"
                              name:@"notifications_api_push_subscriptions"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiWebPushSubscriptions"];
  [application registerRouteMethod:@"POST"
                              path:@"/push/subscriptions"
                              name:@"notifications_api_push_subscribe"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiWebPushSubscribe"];
  [application registerRouteMethod:@"POST"
                              path:@"/push/unsubscribe"
                              name:@"notifications_api_push_unsubscribe"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"apiWebPushUnsubscribe"];
  BOOL webPushTestRoute = [[runtime webPushClientConfiguration][@"testRouteEnabled"] boolValue];
  if (webPushTestRoute) {
    [application registerRouteMethod:@"POST"
                                path:@"/push/test"
                                name:@"notifications_api_push_test"
                     controllerClass:[ALNNotificationsModuleController class]
                              action:@"apiWebPushTest"];
  }
  [application endRouteGroup];

  // The service worker and helper are static scripts without user data, so they
  // need no session; registration also fetches them outside a page request.
  [application beginRouteGroupWithPrefix:runtime.prefix guardAction:nil formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/push/service-worker.js"
                              name:@"notifications_push_service_worker"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"webPushServiceWorker"];
  [application registerRouteMethod:@"GET"
                              path:@"/push/client.js"
                              name:@"notifications_push_client_script"
                   controllerClass:[ALNNotificationsModuleController class]
                            action:@"webPushClientScript"];
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
                                          stepUpPath:NMStepUpPath([ALNAuthModuleRuntime sharedRuntime])
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
    @"notifications_api_push_config",
    @"notifications_api_push_subscriptions",
    @"notifications_api_push_subscribe",
    @"notifications_api_push_unsubscribe",
  ];
  if (webPushTestRoute) {
    userRoutes = [userRoutes arrayByAddingObject:@"notifications_api_push_test"];
  }
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
