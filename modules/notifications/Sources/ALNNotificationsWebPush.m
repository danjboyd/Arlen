#import "ALNNotificationsWebPush.h"

#include <errno.h>

#import "ALNDataCompat.h"
#import "ALNHTTPCompat.h"
#import "ALNJSONSerialization.h"
#import "ALNPlatform.h"
#import "ALNSecurityPrimitives.h"

static NSString *WPTrimmed(id value) {
  return [value isKindOfClass:[NSString class]]
             ? [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
             : @"";
}

@implementation ALNWebPushHTTPTransport

- (NSDictionary *)webPushSendRequest:(NSURLRequest *)request error:(NSError **)error {
  NSMutableURLRequest *bounded = [request mutableCopy];
  if ([bounded timeoutInterval] <= 0.0 || [bounded timeoutInterval] > 15.0) {
    [bounded setTimeoutInterval:15.0];
  }
  ALNHTTPClientResult *result = ALNSynchronousHTTPResult(bounded, 0, ALNHTTPRedirectLimitReturnResponse, error);
  if (result == nil) {
    return nil;
  }
  NSMutableDictionary *headers = [NSMutableDictionary dictionary];
  NSDictionary *rawHeaders = [result.response allHeaderFields] ?: @{};
  for (id name in rawHeaders) {
    headers[[[name description] lowercaseString]] = [rawHeaders[name] description] ?: @"";
  }
  return @{
    @"status" : @([result.response statusCode]),
    @"headers" : headers,
  };
}

@end

NSTimeInterval ALNWebPushRetryAfterSeconds(NSString *value, NSDate *now) {
  NSString *trimmed = WPTrimmed(value);
  if ([trimmed length] == 0) {
    return -1.0;
  }
  NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
  if ([trimmed rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
    return (NSTimeInterval)[trimmed longLongValue];
  }
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
  [formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
  [formatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss 'GMT'"];
  NSDate *date = [formatter dateFromString:trimmed];
  if (date == nil) {
    return -1.0;
  }
  return MAX(0.0, [date timeIntervalSinceDate:now ?: [NSDate date]]);
}

@interface ALNNotificationsWebPushSubscriptionStore ()
@property(nonatomic, copy, readwrite) NSString *path;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *memory;
@end

@implementation ALNNotificationsWebPushSubscriptionStore

- (instancetype)initWithPath:(NSString *)path {
  self = [super init];
  if (self != nil) {
    _path = [WPTrimmed(path) copy];
    _lock = [[NSLock alloc] init];
    _memory = [NSMutableDictionary dictionary];
  }
  return self;
}

- (NSMutableDictionary *)readFileState {
  NSMutableDictionary *byRecipient = [NSMutableDictionary dictionary];
  if (![[NSFileManager defaultManager] fileExistsAtPath:self.path]) {
    return byRecipient;
  }
  NSData *data = ALNDataReadFromFile(self.path, 0, NULL);
  id object = (data != nil) ? [NSPropertyListSerialization propertyListWithData:data
                                                                        options:NSPropertyListMutableContainersAndLeaves
                                                                         format:NULL
                                                                          error:NULL]
                            : nil;
  NSDictionary *stored = [object isKindOfClass:[NSDictionary class]] ? object[@"subscriptionsByRecipient"] : nil;
  for (id recipient in [stored isKindOfClass:[NSDictionary class]] ? stored : @{}) {
    NSArray *entries = [stored[recipient] isKindOfClass:[NSArray class]] ? stored[recipient] : @[];
    byRecipient[recipient] = [entries mutableCopy];
  }
  return byRecipient;
}

- (BOOL)writeFileState:(NSDictionary *)byRecipient error:(NSError **)error {
  NSString *parent = [self.path stringByDeletingLastPathComponent];
  if ([parent length] > 0 &&
      ![[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:error]) {
    return NO;
  }
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{ @"version" : @1, @"subscriptionsByRecipient" : byRecipient }
                                                            format:NSPropertyListBinaryFormat_v1_0
                                                           options:0
                                                             error:error];
  return (data != nil) && [data writeToFile:self.path options:NSDataWritingAtomic error:error];
}

// Runs a read-modify-write under the in-process lock and, for file stores, an
// advisory lock that serializes the app server and job workers.
- (id)mutate:(id (^)(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *state, BOOL *changed))block
       error:(NSError **)error {
  [self.lock lock];
  if ([self.path length] == 0) {
    BOOL changed = NO;
    id result = block(self.memory, &changed);
    [self.lock unlock];
    return result;
  }
  NSString *lockPath = [self.path stringByAppendingString:@".lock"];
  [[NSFileManager defaultManager] createDirectoryAtPath:[lockPath stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  int descriptor = ALNPlatformOpenExclusiveLock(lockPath);
  if (descriptor < 0) {
    [self.lock unlock];
    if (error != NULL) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                   code:errno
                               userInfo:@{ NSLocalizedDescriptionKey : @"could not lock the push subscription store" }];
    }
    return nil;
  }
  NSMutableDictionary *state = [self readFileState];
  BOOL changed = NO;
  id result = block(state, &changed);
  if (changed && ![self writeFileState:state error:error]) {
    result = nil;
  }
  ALNPlatformReleaseExclusiveLock(descriptor);
  [self.lock unlock];
  return result;
}

- (NSDictionary *)saveSubscriptionWithEndpoint:(NSString *)endpoint
                                        p256dh:(NSString *)p256dh
                                          auth:(NSString *)auth
                                     userAgent:(NSString *)userAgent
                                  forRecipient:(NSString *)recipient
                               maxPerRecipient:(NSUInteger)maxPerRecipient
                                         error:(NSError **)error {
  NSString *owner = WPTrimmed(recipient);
  NSString *normalizedEndpoint = WPTrimmed(endpoint);
  NSNumber *now = @([[NSDate date] timeIntervalSince1970]);
  return [self mutate:^id(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *state, BOOL *changed) {
    NSDictionary *previous = nil;
    for (NSString *holder in [state allKeys]) {
      NSMutableArray *entries = state[holder];
      for (NSUInteger index = 0; index < [entries count]; index++) {
        if ([entries[index][@"endpoint"] isEqualToString:normalizedEndpoint]) {
          previous = entries[index];
          [entries removeObjectAtIndex:index];
          break;
        }
      }
      if ([entries count] == 0) {
        [state removeObjectForKey:holder];
      }
    }
    BOOL sameOwner = [previous[@"recipient"] isEqualToString:owner];
    NSString *subscriptionID = (sameOwner && [WPTrimmed(previous[@"subscriptionID"]) length] > 0)
                                   ? previous[@"subscriptionID"]
                                   : ALNBase64URLStringFromData(ALNSecureRandomData(12));
    NSDictionary *record = @{
      @"subscriptionID" : subscriptionID ?: @"",
      @"recipient" : owner,
      @"endpoint" : normalizedEndpoint,
      @"p256dh" : WPTrimmed(p256dh),
      @"auth" : WPTrimmed(auth),
      @"userAgent" : [WPTrimmed(userAgent) length] > 512 ? [WPTrimmed(userAgent) substringToIndex:512] : WPTrimmed(userAgent),
      @"createdAt" : sameOwner && previous[@"createdAt"] ? previous[@"createdAt"] : now,
      @"updatedAt" : now,
      @"lastSuccessAt" : sameOwner && previous[@"lastSuccessAt"] ? previous[@"lastSuccessAt"] : @0,
      @"active" : @YES,
      @"inactiveReason" : @"",
      @"inactiveAt" : @0,
    };
    NSMutableArray *entries = state[owner] ?: [NSMutableArray array];
    [entries addObject:record];
    NSUInteger limit = MAX((NSUInteger)1, maxPerRecipient);
    while ([entries count] > limit) {
      [entries removeObjectAtIndex:0];
    }
    state[owner] = entries;
    *changed = YES;
    return record;
  }
                error:error];
}

- (BOOL)removeMatching:(BOOL (^)(NSDictionary *entry))match forRecipient:(NSString *)recipient error:(NSError **)error {
  NSString *owner = WPTrimmed(recipient);
  NSNumber *removed = [self mutate:^id(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *state, BOOL *changed) {
    NSMutableArray *entries = state[owner];
    NSUInteger before = [entries count];
    NSIndexSet *indexes = [entries indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
      (void)idx;
      (void)stop;
      return match(entry);
    }];
    [entries removeObjectsAtIndexes:indexes];
    if (entries != nil && [entries count] == 0) {
      [state removeObjectForKey:owner];
    }
    *changed = ([entries count] != before);
    return @(*changed);
  }
                            error:error];
  return [removed boolValue];
}

- (BOOL)removeSubscriptionWithEndpoint:(NSString *)endpoint forRecipient:(NSString *)recipient error:(NSError **)error {
  NSString *target = WPTrimmed(endpoint);
  return [self removeMatching:^BOOL(NSDictionary *entry) {
    return [entry[@"endpoint"] isEqualToString:target];
  }
                 forRecipient:recipient
                        error:error];
}

- (BOOL)removeSubscriptionID:(NSString *)subscriptionID forRecipient:(NSString *)recipient error:(NSError **)error {
  NSString *target = WPTrimmed(subscriptionID);
  return [self removeMatching:^BOOL(NSDictionary *entry) {
    return [entry[@"subscriptionID"] isEqualToString:target];
  }
                 forRecipient:recipient
                        error:error];
}

- (NSArray<NSDictionary *> *)subscriptionsForRecipient:(NSString *)recipient includeInactive:(BOOL)includeInactive {
  NSString *owner = WPTrimmed(recipient);
  return [self mutate:^id(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *state, BOOL *changed) {
    (void)changed;
    NSMutableArray *matches = [NSMutableArray array];
    for (NSDictionary *entry in state[owner] ?: @[]) {
      if (includeInactive || [entry[@"active"] boolValue]) {
        [matches addObject:[entry copy]];
      }
    }
    return matches;
  }
                error:NULL] ?: @[];
}

- (NSDictionary *)subscriptionWithID:(NSString *)subscriptionID {
  NSString *target = WPTrimmed(subscriptionID);
  return [self mutate:^id(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *state, BOOL *changed) {
    (void)changed;
    for (NSString *owner in state) {
      for (NSDictionary *entry in state[owner]) {
        if ([entry[@"subscriptionID"] isEqualToString:target]) {
          return [entry copy];
        }
      }
    }
    return nil;
  }
                error:NULL];
}

- (void)updateSubscriptionID:(NSString *)subscriptionID with:(void (^)(NSMutableDictionary *entry))update {
  NSString *target = WPTrimmed(subscriptionID);
  (void)[self mutate:^id(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *state, BOOL *changed) {
    for (NSString *owner in state) {
      NSMutableArray *entries = state[owner];
      for (NSUInteger index = 0; index < [entries count]; index++) {
        if ([entries[index][@"subscriptionID"] isEqualToString:target]) {
          NSMutableDictionary *entry = [entries[index] mutableCopy];
          update(entry);
          entries[index] = entry;
          *changed = YES;
          return @YES;
        }
      }
    }
    return @NO;
  }
               error:NULL];
}

- (void)recordSuccessForSubscriptionID:(NSString *)subscriptionID {
  [self updateSubscriptionID:subscriptionID with:^(NSMutableDictionary *entry) {
    entry[@"lastSuccessAt"] = @([[NSDate date] timeIntervalSince1970]);
  }];
}

- (void)deactivateSubscriptionID:(NSString *)subscriptionID reason:(NSString *)reason {
  [self updateSubscriptionID:subscriptionID with:^(NSMutableDictionary *entry) {
    entry[@"active"] = @NO;
    entry[@"inactiveReason"] = WPTrimmed(reason);
    entry[@"inactiveAt"] = @([[NSDate date] timeIntervalSince1970]);
  }];
}

- (NSDictionary *)summary {
  return [self mutate:^id(NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *state, BOOL *changed) {
    (void)changed;
    NSUInteger active = 0;
    NSUInteger inactive = 0;
    for (NSString *owner in state) {
      for (NSDictionary *entry in state[owner]) {
        if ([entry[@"active"] boolValue]) {
          active += 1;
        } else {
          inactive += 1;
        }
      }
    }
    return @{
      @"recipientCount" : @([state count]),
      @"activeSubscriptionCount" : @(active),
      @"inactiveSubscriptionCount" : @(inactive),
    };
  }
                error:NULL] ?: @{};
}

@end

static NSString *WPJSONLiteral(id object) {
  // ALNJSONSerialization (yyjson) leaves "/" unescaped on every platform; Apple's
  // NSJSONSerialization writes "<\/script>" and would diverge from GNUstep.
  NSData *data = [ALNJSONSerialization dataWithJSONObject:object ?: @{} options:0 error:NULL];
  NSString *json = (data != nil) ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
  // Keep the literal inert inside a script even if a value contains "</script>",
  // and escape the separators that end a line in pre-ES2019 string literals.
  json = [json stringByReplacingOccurrencesOfString:@"<" withString:@"\\u003c"];
  json = [json stringByReplacingOccurrencesOfString:@"\u2028" withString:@"\\u2028"];
  return [json stringByReplacingOccurrencesOfString:@"\u2029" withString:@"\\u2029"];
}

NSString *ALNWebPushServiceWorkerScript(NSDictionary *defaults) {
  NSString *prefix = [NSString stringWithFormat:@"var ARLEN_WEBPUSH_DEFAULTS = %@;\n", WPJSONLiteral(defaults)];
  NSString *body =
      @"// Arlen notifications Web Push service worker.\n"
       "'use strict';\n"
       "self.addEventListener('install', function () { self.skipWaiting(); });\n"
       "self.addEventListener('activate', function (event) { event.waitUntil(self.clients.claim()); });\n"
       "\n"
       "self.addEventListener('push', function (event) {\n"
       "  var message = {};\n"
       "  try { message = event.data ? event.data.json() : {}; } catch (e) { message = {}; }\n"
       "  var fallback = ARLEN_WEBPUSH_DEFAULTS || {};\n"
       "  // iOS has no silent push: every push must show a notification, so a\n"
       "  // content-free nudge (or an unreadable payload) uses the app's fallback text.\n"
       "  var nudge = message.nudge === true || !message.title;\n"
       "  var title = nudge ? (fallback.title || 'New notification') : String(message.title);\n"
       "  var options = {\n"
       "    body: nudge ? (fallback.body || '') : String(message.body || ''),\n"
       "    data: { url: message.url || fallback.url || '/' }\n"
       "  };\n"
       "  if (message.tag) { options.tag = String(message.tag); }\n"
       "  if (fallback.icon) { options.icon = fallback.icon; }\n"
       "  if (fallback.badge) { options.badge = fallback.badge; }\n"
       "  event.waitUntil(self.registration.showNotification(title, options));\n"
       "});\n"
       "\n"
       "self.addEventListener('notificationclick', function (event) {\n"
       "  event.notification.close();\n"
       "  var target = new URL('/', self.location.origin);\n"
       "  try {\n"
       "    var requested = new URL((event.notification.data && event.notification.data.url) || '/', self.location.origin);\n"
       "    // Only open pages of this app; a payload cannot redirect to another site.\n"
       "    if (requested.origin === self.location.origin) { target = requested; }\n"
       "  } catch (e) {}\n"
       "  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (windows) {\n"
       "    for (var i = 0; i < windows.length; i++) {\n"
       "      if (windows[i].url === target.href && 'focus' in windows[i]) { return windows[i].focus(); }\n"
       "    }\n"
       "    return self.clients.openWindow(target.href);\n"
       "  }));\n"
       "});\n";
  return [prefix stringByAppendingString:body];
}

NSString *ALNWebPushClientScript(void) {
  return
      @"// Arlen notifications Web Push helper: window.ArlenWebPush.\n"
       "// <script src=\".../push/client.js\" data-api-prefix=\"/notifications/api\"\n"
       "//         data-service-worker=\"/notifications/push/service-worker.js\" data-scope=\"/\"></script>\n"
       "(function () {\n"
       "  'use strict';\n"
       "  var script = document.currentScript;\n"
       "  var data = (script && script.dataset) || {};\n"
       "  var config = {\n"
       "    apiPrefix: data.apiPrefix || '/notifications/api',\n"
       "    serviceWorker: data.serviceWorker || '/notifications/push/service-worker.js',\n"
       "    scope: data.scope || '/',\n"
       "    csrfHeader: data.csrfHeader || 'X-CSRF-Token',\n"
       "    csrfToken: data.csrfToken || ''\n"
       "  };\n"
       "\n"
       "  function csrfToken() {\n"
       "    if (config.csrfToken) { return config.csrfToken; }\n"
       "    var meta = document.querySelector('meta[name=\"csrf-token\"]');\n"
       "    return meta ? meta.getAttribute('content') || '' : '';\n"
       "  }\n"
       "\n"
       "  function request(method, path, body) {\n"
       "    var headers = { 'Accept': 'application/json' };\n"
       "    if (method !== 'GET') { headers['Content-Type'] = 'application/json'; headers[config.csrfHeader] = csrfToken(); }\n"
       "    return fetch(config.apiPrefix + path, {\n"
       "      method: method, credentials: 'same-origin', headers: headers,\n"
       "      body: body === undefined ? undefined : JSON.stringify(body)\n"
       "    }).then(function (response) {\n"
       "      return response.json().catch(function () { return {}; }).then(function (json) {\n"
       "        if (!response.ok) {\n"
       "          var reason = (json && json.meta && json.meta.error) || ('request failed: ' + response.status);\n"
       "          throw new Error(reason);\n"
       "        }\n"
       "        return (json && json.data !== undefined) ? json.data : json;\n"
       "      });\n"
       "    });\n"
       "  }\n"
       "\n"
       "  function keyBytes(base64url) {\n"
       "    var padded = (base64url + '===='.slice((base64url.length + 3) % 4)).replace(/-/g, '+').replace(/_/g, '/');\n"
       "    var raw = atob(padded);\n"
       "    var bytes = new Uint8Array(raw.length);\n"
       "    for (var i = 0; i < raw.length; i++) { bytes[i] = raw.charCodeAt(i); }\n"
       "    return bytes;\n"
       "  }\n"
       "\n"
       "  function sameKey(subscription, bytes) {\n"
       "    var current = subscription.options && subscription.options.applicationServerKey;\n"
       "    if (!current) { return true; }\n"
       "    var existing = new Uint8Array(current);\n"
       "    if (existing.length !== bytes.length) { return false; }\n"
       "    for (var i = 0; i < bytes.length; i++) { if (existing[i] !== bytes[i]) { return false; } }\n"
       "    return true;\n"
       "  }\n"
       "\n"
       "  function supported() {\n"
       "    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;\n"
       "  }\n"
       "\n"
       "  function registration() {\n"
       "    return navigator.serviceWorker.register(config.serviceWorker, { scope: config.scope })\n"
       "      .then(function () { return navigator.serviceWorker.ready; });\n"
       "  }\n"
       "\n"
       "  // Call from a click or tap handler: iOS grants notification permission only\n"
       "  // in response to a user gesture, so requestPermission runs first.\n"
       "  function subscribe() {\n"
       "    if (!supported()) { return Promise.reject(new Error('Web Push is not supported in this browser')); }\n"
       "    return Notification.requestPermission().then(function (permission) {\n"
       "      if (permission !== 'granted') { throw new Error('notification permission was not granted'); }\n"
       "      return Promise.all([request('GET', '/push/config'), registration()]);\n"
       "    }).then(function (results) {\n"
       "      var settings = results[0] || {};\n"
       "      var worker = results[1];\n"
       "      if (!settings.enabled || !settings.vapidPublicKey) { throw new Error('Web Push is not enabled on this server'); }\n"
       "      var key = keyBytes(settings.vapidPublicKey);\n"
       "      return worker.pushManager.getSubscription().then(function (existing) {\n"
       "        if (existing && sameKey(existing, key)) { return existing; }\n"
       "        var cleared = existing ? existing.unsubscribe() : Promise.resolve(true);\n"
       "        return cleared.then(function () {\n"
       "          return worker.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });\n"
       "        });\n"
       "      });\n"
       "    }).then(function (subscription) {\n"
       "      return request('POST', '/push/subscriptions', { subscription: subscription.toJSON() });\n"
       "    });\n"
       "  }\n"
       "\n"
       "  function unsubscribe() {\n"
       "    if (!supported()) { return Promise.resolve({ removed: false }); }\n"
       "    return navigator.serviceWorker.getRegistration(config.scope).then(function (worker) {\n"
       "      return worker ? worker.pushManager.getSubscription() : null;\n"
       "    }).then(function (subscription) {\n"
       "      if (!subscription) { return { removed: false }; }\n"
       "      return request('POST', '/push/unsubscribe', { endpoint: subscription.endpoint }).then(function (result) {\n"
       "        return subscription.unsubscribe().then(function () { return result; });\n"
       "      });\n"
       "    });\n"
       "  }\n"
       "\n"
       "  function status() {\n"
       "    if (!supported()) { return Promise.resolve({ supported: false, permission: 'unsupported', subscribed: false }); }\n"
       "    return navigator.serviceWorker.getRegistration(config.scope).then(function (worker) {\n"
       "      return worker ? worker.pushManager.getSubscription() : null;\n"
       "    }).then(function (subscription) {\n"
       "      return { supported: true, permission: Notification.permission, subscribed: !!subscription };\n"
       "    });\n"
       "  }\n"
       "\n"
       "  window.ArlenWebPush = {\n"
       "    supported: supported,\n"
       "    status: status,\n"
       "    subscribe: subscribe,\n"
       "    unsubscribe: unsubscribe,\n"
       "    listSubscriptions: function () { return request('GET', '/push/subscriptions'); },\n"
       "    sendTest: function () { return request('POST', '/push/test', {}); }\n"
       "  };\n"
       "})();\n";
}
