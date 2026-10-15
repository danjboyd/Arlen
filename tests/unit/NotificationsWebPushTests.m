#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNSecurityPrimitives.h"
#import "ALNWebPush.h"

// Records each push request and answers with the next scripted status for its endpoint.
@interface NWPRecordingTransport : NSObject <ALNWebPushTransport>
@property(nonatomic, strong) NSMutableArray<NSURLRequest *> *requests;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *scripted;
- (void)respondTo:(NSString *)endpoint status:(NSInteger)status headers:(NSDictionary *)headers;
@end

@implementation NWPRecordingTransport

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _requests = [NSMutableArray array];
    _scripted = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)respondTo:(NSString *)endpoint status:(NSInteger)status headers:(NSDictionary *)headers {
  NSMutableArray *queue = self.scripted[endpoint] ?: [NSMutableArray array];
  [queue addObject:@{ @"status" : @(status), @"headers" : headers ?: @{} }];
  self.scripted[endpoint] = queue;
}

- (NSDictionary *)webPushSendRequest:(NSURLRequest *)request error:(NSError **)error {
  (void)error;
  [self.requests addObject:request];
  NSMutableArray *queue = self.scripted[[[request URL] absoluteString]];
  if ([queue count] > 0) {
    NSDictionary *response = queue[0];
    [queue removeObjectAtIndex:0];
    return response;
  }
  return @{ @"status" : @201, @"headers" : @{ @"location" : @"https://web.push.apple.com/m/1" } };
}

@end

@interface NWPInjectedAuthMiddleware : NSObject <ALNMiddleware>
@property(nonatomic, copy) NSString *subject;
@end

@implementation NWPInjectedAuthMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  if ([self.subject length] == 0) {
    return YES;
  }
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  context.stash[ALNContextAuthSubjectStashKey] = self.subject;
  context.stash[ALNContextAuthRolesStashKey] = @[];
  context.stash[ALNContextAuthClaimsStashKey] = @{
    @"sub" : self.subject,
    @"roles" : @[],
    @"aal" : @1,
    @"amr" : @[ @"pwd" ],
    @"iat" : @((NSInteger)now),
    @"auth_time" : @((NSInteger)now),
  };
  return YES;
}

@end

@interface NWPTurnNotification : NSObject <ALNNotificationDefinition>
@end

@implementation NWPTurnNotification

- (NSString *)notificationsModuleIdentifier {
  return @"helpdesk.your_turn";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Your turn",
    @"channels" : @[ @"in_app", @"webpush" ],
    @"channelPolicies" : @{ @"webpush" : @{ @"queue" : @"push", @"maxAttempts" : @4 } },
  };
}

- (BOOL)notificationsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  (void)error;
  return [payload[@"recipient"] isKindOfClass:[NSString class]];
}

- (ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                     runtime:(ALNNotificationsModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)payload;
  (void)runtime;
  (void)error;
  return nil;
}

- (NSDictionary *)notificationsModuleInAppEntryForPayload:(NSDictionary *)payload
                                                  runtime:(ALNNotificationsModuleRuntime *)runtime
                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @{ @"recipient" : payload[@"recipient"] ?: @"", @"title" : @"Your turn", @"body" : @"Ticket 42" };
}

- (NSDictionary *)notificationsModuleWebPushMessageForPayload:(NSDictionary *)payload
                                                      runtime:(ALNNotificationsModuleRuntime *)runtime
                                                        error:(NSError **)error {
  (void)runtime;
  (void)error;
  if ([payload[@"rawMessage"] isKindOfClass:[NSDictionary class]]) {
    return payload[@"rawMessage"];
  }
  if ([payload[@"nudge"] boolValue]) {
    return @{ @"nudge" : @YES, @"title" : @"Ticket 42 needs you" };
  }
  return @{
    @"title" : @"Your turn",
    @"body" : @"Ticket 42 is waiting for your confirmation.",
    @"url" : @"/tickets/42",
    @"tag" : @"ticket-42",
    @"topic" : @"ticket-42",
    @"urgency" : @"high",
    @"ttl" : @600,
  };
}

@end

@interface NWPNotificationProvider : NSObject <ALNNotificationProvider>
@end

@implementation NWPNotificationProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:(ALNNotificationsModuleRuntime *)runtime
                                                                                error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[NWPTurnNotification alloc] init] ];
}

@end

@interface NWPRetryAfterJob : NSObject <ALNJobsJobDefinition>
@end

@implementation NWPRetryAfterJob

- (NSString *)jobsModuleJobIdentifier {
  return @"nwp.retry_after";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{ @"title" : @"Retry-After probe", @"queue" : @"default", @"maxAttempts" : @3 };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  (void)payload;
  (void)error;
  return YES;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)payload;
  (void)context;
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"NWP"
                                 code:1
                             userInfo:@{ ALNJobsModuleRetryAfterSecondsErrorKey : @300 }];
  }
  return NO;
}

@end

static NSString *const NWPAppleEndpoint = @"https://web.push.apple.com/QGuQyavXutnMH";
static NSString *const NWPFirefoxEndpoint = @"https://updates.push.services.mozilla.com/wpush/v2/gAAAA";

@interface NotificationsWebPushTests : XCTestCase
@property(nonatomic, copy) NSDictionary *vapid;
@property(nonatomic, strong) NWPRecordingTransport *transport;
@property(nonatomic, strong) NWPInjectedAuthMiddleware *auth;
@end

@implementation NotificationsWebPushTests

- (void)setUp {
  [super setUp];
  self.vapid = ALNWebPushGenerateVAPIDKeyPair(NULL);
  self.transport = [[NWPRecordingTransport alloc] init];
}

- (ALNApplication *)applicationWithWebPush:(NSDictionary *)webPush {
  NSMutableDictionary *notifications = [@{
    @"providers" : @{ @"classes" : @[ @"NWPNotificationProvider" ] },
  } mutableCopy];
  if (webPush != nil) {
    notifications[@"webPush"] = webPush;
  }
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"notificationsModule" : notifications,
  }];
}

- (NSDictionary *)enabledConfig {
  return @{
    @"enabled" : @YES,
    @"vapid" : @{
      @"publicKey" : self.vapid[@"publicKey"],
      @"privateKey" : self.vapid[@"privateKey"],
      @"subject" : @"mailto:ops@example.test",
    },
    @"testRoute" : @{ @"enabled" : @YES },
    @"nudge" : @{ @"title" : @"Helpdesk", @"body" : @"Something needs you.", @"url" : @"/inbox" },
  };
}

- (ALNNotificationsModuleRuntime *)registerApplication:(ALNApplication *)app {
  self.auth = [[NWPInjectedAuthMiddleware alloc] init];
  [app addMiddleware:self.auth];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertTrue([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  runtime.webPushTransport = self.transport;
  return runtime;
}

- (ALNNotificationsModuleRuntime *)enabledRuntime {
  return [self registerApplication:[self applicationWithWebPush:[self enabledConfig]]];
}

// A device: its keys go to the server, its private key decrypts what arrives.
- (NSDictionary *)deviceWithEndpoint:(NSString *)endpoint {
  NSDictionary *keys = ALNWebPushGenerateVAPIDKeyPair(NULL);
  NSData *auth = ALNSecureRandomData(16);
  return @{
    @"subscription" : @{
      @"endpoint" : endpoint,
      @"keys" : @{ @"p256dh" : keys[@"publicKey"], @"auth" : ALNBase64URLStringFromData(auth) },
    },
    @"privateKey" : ALNDataFromBase64URLString(keys[@"privateKey"]),
    @"auth" : auth,
  };
}

- (NSDictionary *)subscribeDevice:(NSDictionary *)device recipient:(NSString *)recipient runtime:(ALNNotificationsModuleRuntime *)runtime {
  NSError *error = nil;
  NSDictionary *saved = [runtime saveWebPushSubscription:device[@"subscription"]
                                               userAgent:@"Mozilla/5.0 (iPhone)"
                                            forRecipient:recipient
                                                   error:&error];
  XCTAssertNotNil(saved, @"%@", error);
  return saved;
}

- (NSDictionary *)decryptRequest:(NSURLRequest *)request forDevice:(NSDictionary *)device {
  NSError *error = nil;
  NSData *plaintext = ALNWebPushDecryptPayload([request HTTPBody], device[@"privateKey"], device[@"auth"], &error);
  XCTAssertNotNil(plaintext, @"%@", error);
  id json = (plaintext != nil) ? [NSJSONSerialization JSONObjectWithData:plaintext options:0 error:NULL] : nil;
  return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (NSURLRequest *)requestToEndpoint:(NSString *)endpoint {
  for (NSURLRequest *request in self.transport.requests) {
    if ([[[request URL] absoluteString] isEqualToString:endpoint]) {
      return request;
    }
  }
  return nil;
}

- (ALNResponse *)dispatch:(ALNApplication *)app method:(NSString *)method path:(NSString *)path json:(id)json {
  NSData *body = (json != nil) ? [NSJSONSerialization dataWithJSONObject:json options:0 error:NULL] : [NSData data];
  NSDictionary *headers = (json != nil) ? @{ @"content-type" : @"application/json", @"user-agent" : @"Mozilla/5.0 (iPhone)" } : @{};
  return [app dispatchRequest:[[ALNRequest alloc] initWithMethod:method
                                                            path:path
                                                     queryString:@""
                                                         headers:headers
                                                            body:body]];
}

- (NSDictionary *)JSONFromResponse:(ALNResponse *)response {
  id json = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:NULL];
  return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (void)testDisabledByDefaultRejectsSubscriptionsAndSuppressesDelivery {
  ALNNotificationsModuleRuntime *runtime = [self registerApplication:[self applicationWithWebPush:nil]];
  XCTAssertEqualObjects(@NO, [runtime webPushClientConfiguration][@"enabled"]);
  XCTAssertEqualObjects(@"", [runtime webPushClientConfiguration][@"vapidPublicKey"]);

  NSError *error = nil;
  XCTAssertNil([runtime saveWebPushSubscription:[self deviceWithEndpoint:NWPAppleEndpoint][@"subscription"]
                                      userAgent:nil
                                   forRecipient:@"dan"
                                          error:&error]);
  XCTAssertEqual(ALNNotificationsModuleErrorPolicyRejected, error.code);

  error = nil;
  NSDictionary *result = [runtime testSendNotificationIdentifier:@"helpdesk.your_turn"
                                                         payload:@{ @"recipient" : @"dan" }
                                                        channels:@[ @"webpush" ]
                                                           error:&error];
  XCTAssertNotNil(result, @"%@", error);
  XCTAssertEqualObjects((@[ @"webpush" ]), result[@"skippedChannels"]);
  XCTAssertEqual((NSUInteger)0, [self.transport.requests count]);
  XCTAssertEqualObjects(@"suppressed", [[runtime outboxSnapshot] lastObject][@"status"]);
}

- (void)testEnabledConfigurationRequiresMatchingKeysAndContactSubject {
  NSMutableDictionary *config = [[self enabledConfig] mutableCopy];
  NSDictionary *other = ALNWebPushGenerateVAPIDKeyPair(NULL);
  config[@"vapid"] = @{ @"publicKey" : other[@"publicKey"], @"privateKey" : self.vapid[@"privateKey"], @"subject" : @"mailto:a@b.test" };
  ALNApplication *app = [self applicationWithWebPush:config];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertFalse([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertEqual(ALNNotificationsModuleErrorInvalidConfiguration, error.code);

  config[@"vapid"] = @{ @"publicKey" : self.vapid[@"publicKey"], @"privateKey" : self.vapid[@"privateKey"], @"subject" : @"ops@example.test" };
  app = [self applicationWithWebPush:config];
  error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertFalse([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertTrue([error.localizedDescription containsString:@"subject"]);
}

- (void)testSubscriptionsAreValidatedKeyedByEndpointAndBounded {
  ALNNotificationsModuleRuntime *runtime = [self enabledRuntime];
  NSDictionary *device = [self deviceWithEndpoint:NWPAppleEndpoint];
  NSMutableDictionary *subscription = [device[@"subscription"] mutableCopy];
  NSError *error = nil;

  for (NSString *endpoint in @[ @"http://web.push.apple.com/x", @"https://push.attacker.test/x", @"https://user:pw@web.push.apple.com/x",
                                @"https://169.254.169.254/latest" ]) {
    subscription[@"endpoint"] = endpoint;
    error = nil;
    XCTAssertNil([runtime saveWebPushSubscription:subscription userAgent:nil forRecipient:@"dan" error:&error], @"%@", endpoint);
    XCTAssertEqual(ALNNotificationsModuleErrorValidationFailed, error.code);
  }
  subscription[@"endpoint"] = NWPAppleEndpoint;
  subscription[@"keys"] = @{ @"p256dh" : @"AAAA", @"auth" : device[@"subscription"][@"keys"][@"auth"] };
  error = nil;
  XCTAssertNil([runtime saveWebPushSubscription:subscription userAgent:nil forRecipient:@"dan" error:&error]);
  XCTAssertEqualObjects(@"push subscription keys are invalid", error.localizedDescription);

  NSDictionary *first = [self subscribeDevice:device recipient:@"dan" runtime:runtime];
  XCTAssertEqualObjects(@"web.push.apple.com", first[@"endpointHost"]);
  XCTAssertNil(first[@"endpoint"]);
  XCTAssertNil(first[@"p256dh"]);
  NSDictionary *again = [self subscribeDevice:device recipient:@"dan" runtime:runtime];
  XCTAssertEqualObjects(first[@"subscriptionID"], again[@"subscriptionID"]);
  XCTAssertEqual((NSUInteger)1, [[runtime webPushSubscriptionsForRecipient:@"dan"] count]);

  // A device handed to another user follows the new session.
  [self subscribeDevice:device recipient:@"sam" runtime:runtime];
  XCTAssertEqual((NSUInteger)0, [[runtime webPushSubscriptionsForRecipient:@"dan"] count]);
  XCTAssertEqual((NSUInteger)1, [[runtime webPushSubscriptionsForRecipient:@"sam"] count]);

  for (NSUInteger index = 0; index < 12; index++) {
    [self subscribeDevice:[self deviceWithEndpoint:[NSString stringWithFormat:@"%@-%lu", NWPAppleEndpoint, (unsigned long)index]]
                recipient:@"dan"
                  runtime:runtime];
  }
  XCTAssertEqual((NSUInteger)10, [[runtime webPushSubscriptionsForRecipient:@"dan"] count]);

  XCTAssertTrue([runtime removeWebPushSubscriptionWithEndpoint:NWPAppleEndpoint forRecipient:@"sam" error:&error]);
  XCTAssertEqual((NSUInteger)0, [[runtime webPushSubscriptionsForRecipient:@"sam"] count]);
}

- (void)testDeliveryEncryptsForEachDeviceWithVAPIDAndProtocolHeaders {
  ALNNotificationsModuleRuntime *runtime = [self enabledRuntime];
  NSDictionary *phone = [self deviceWithEndpoint:NWPAppleEndpoint];
  NSDictionary *laptop = [self deviceWithEndpoint:NWPFirefoxEndpoint];
  [self subscribeDevice:phone recipient:@"dan" runtime:runtime];
  [self subscribeDevice:laptop recipient:@"dan" runtime:runtime];

  NSError *error = nil;
  NSDictionary *result = [runtime testSendNotificationIdentifier:@"helpdesk.your_turn"
                                                         payload:@{ @"recipient" : @"dan" }
                                                        channels:@[ @"webpush" ]
                                                           error:&error];
  XCTAssertNotNil(result, @"%@", error);
  XCTAssertEqualObjects((@[ @"webpush" ]), result[@"channels"]);
  XCTAssertEqual((NSUInteger)2, [self.transport.requests count]);

  for (NSDictionary *device in @[ phone, laptop ]) {
    NSString *endpoint = device[@"subscription"][@"endpoint"];
    NSURLRequest *request = [self requestToEndpoint:endpoint];
    XCTAssertEqualObjects(@"POST", [request HTTPMethod]);
    XCTAssertEqualObjects(@"600", [request valueForHTTPHeaderField:@"TTL"]);
    XCTAssertEqualObjects(@"high", [request valueForHTTPHeaderField:@"Urgency"]);
    XCTAssertEqualObjects(@"ticket-42", [request valueForHTTPHeaderField:@"Topic"]);
    XCTAssertEqualObjects(@"aes128gcm", [request valueForHTTPHeaderField:@"Content-Encoding"]);

    NSString *authorization = [request valueForHTTPHeaderField:@"Authorization"];
    XCTAssertTrue([authorization hasPrefix:@"vapid t="]);
    XCTAssertTrue([authorization hasSuffix:[@", k=" stringByAppendingString:self.vapid[@"publicKey"]]]);
    NSString *token = [[authorization substringFromIndex:8] componentsSeparatedByString:@","][0];
    NSDictionary *claims = [NSJSONSerialization JSONObjectWithData:ALNDataFromBase64URLString([token componentsSeparatedByString:@"."][1])
                                                           options:0
                                                             error:NULL];
    XCTAssertEqualObjects(ALNWebPushAudienceForEndpoint([NSURL URLWithString:endpoint]), claims[@"aud"]);
    XCTAssertEqualObjects(@"mailto:ops@example.test", claims[@"sub"]);
    NSTimeInterval lifetime = [claims[@"exp"] doubleValue] - [[NSDate date] timeIntervalSince1970];
    XCTAssertTrue(lifetime > 11.0 * 3600.0 && lifetime <= 12.0 * 3600.0);

    NSDictionary *message = [self decryptRequest:request forDevice:device];
    XCTAssertEqualObjects(@"Your turn", message[@"title"]);
    XCTAssertEqualObjects(@"Ticket 42 is waiting for your confirmation.", message[@"body"]);
    XCTAssertEqualObjects(@"/tickets/42", message[@"url"]);
    XCTAssertEqualObjects(@"ticket-42", message[@"tag"]);
  }
  for (NSDictionary *subscription in [runtime webPushSubscriptionsForRecipient:@"dan"]) {
    XCTAssertTrue([subscription[@"lastSuccessAt"] doubleValue] > 0.0);
  }
}

- (void)testVAPIDTokenIsReusedPerPushServiceOrigin {
  ALNNotificationsModuleRuntime *runtime = [self enabledRuntime];
  [self subscribeDevice:[self deviceWithEndpoint:NWPAppleEndpoint] recipient:@"dan" runtime:runtime];
  [self subscribeDevice:[self deviceWithEndpoint:[NWPAppleEndpoint stringByAppendingString:@"-2"]] recipient:@"dan" runtime:runtime];
  [self subscribeDevice:[self deviceWithEndpoint:NWPFirefoxEndpoint] recipient:@"dan" runtime:runtime];
  NSError *error = nil;
  XCTAssertNotNil([runtime sendWebPushTestToRecipient:@"dan" error:&error], @"%@", error);
  XCTAssertNotNil([runtime sendWebPushTestToRecipient:@"dan" error:&error], @"%@", error);
  NSMutableDictionary<NSString *, NSMutableSet *> *headersByHost = [NSMutableDictionary dictionary];
  for (NSURLRequest *request in self.transport.requests) {
    NSString *host = [[request URL] host];
    headersByHost[host] = headersByHost[host] ?: [NSMutableSet set];
    [headersByHost[host] addObject:[request valueForHTTPHeaderField:@"Authorization"]];
  }
  XCTAssertEqual((NSUInteger)6, [self.transport.requests count]);
  XCTAssertEqual((NSUInteger)1, [headersByHost[@"web.push.apple.com"] count]);
  XCTAssertEqual((NSUInteger)1, [headersByHost[@"updates.push.services.mozilla.com"] count]);
  XCTAssertNotEqualObjects([headersByHost[@"web.push.apple.com"] anyObject],
                           [headersByHost[@"updates.push.services.mozilla.com"] anyObject]);
}

- (void)testGoneSubscriptionIsMarkedInactiveAndSkipped {
  ALNNotificationsModuleRuntime *runtime = [self enabledRuntime];
  [self subscribeDevice:[self deviceWithEndpoint:NWPAppleEndpoint] recipient:@"dan" runtime:runtime];
  [self.transport respondTo:NWPAppleEndpoint status:410 headers:nil];

  NSError *error = nil;
  NSDictionary *result = [runtime testSendNotificationIdentifier:@"helpdesk.your_turn"
                                                         payload:@{ @"recipient" : @"dan" }
                                                        channels:@[ @"webpush" ]
                                                           error:&error];
  XCTAssertNotNil(result, @"%@", error);
  XCTAssertEqualObjects((@[ @"webpush" ]), result[@"skippedChannels"]);
  NSDictionary *subscription = [runtime webPushSubscriptionsForRecipient:@"dan"][0];
  XCTAssertEqualObjects(@NO, subscription[@"active"]);
  XCTAssertEqualObjects(@"push service returned HTTP 410", subscription[@"inactiveReason"]);
  XCTAssertEqualObjects(@"expired", [[runtime outboxSnapshot] lastObject][@"status"]);

  result = [runtime testSendNotificationIdentifier:@"helpdesk.your_turn"
                                           payload:@{ @"recipient" : @"dan" }
                                          channels:@[ @"webpush" ]
                                             error:&error];
  XCTAssertNotNil(result);
  XCTAssertEqual((NSUInteger)1, [self.transport.requests count]);
  XCTAssertEqualObjects(@"skipped", [[runtime outboxSnapshot] lastObject][@"status"]);

  // Subscribing the device again reactivates it.
  [self subscribeDevice:[self deviceWithEndpoint:NWPAppleEndpoint] recipient:@"dan" runtime:runtime];
  XCTAssertEqualObjects(@YES, [runtime webPushSubscriptionsForRecipient:@"dan"][0][@"active"]);
}

- (void)testTransientFailureRetriesOnlyThatDeviceAfterRetryAfter {
  ALNNotificationsModuleRuntime *runtime = [self enabledRuntime];
  NSDictionary *phone = [self subscribeDevice:[self deviceWithEndpoint:NWPAppleEndpoint] recipient:@"dan" runtime:runtime];
  [self subscribeDevice:[self deviceWithEndpoint:NWPFirefoxEndpoint] recipient:@"dan" runtime:runtime];
  [self.transport respondTo:NWPAppleEndpoint status:429 headers:@{ @"retry-after" : @"120" }];

  NSError *error = nil;
  NSDictionary *result = [runtime testSendNotificationIdentifier:@"helpdesk.your_turn"
                                                         payload:@{ @"recipient" : @"dan" }
                                                        channels:@[ @"webpush" ]
                                                           error:&error];
  XCTAssertNotNil(result, @"%@", error);
  XCTAssertEqualObjects((@[ @"webpush" ]), result[@"channels"]);

  NSArray *pending = [[ALNJobsModuleRuntime sharedRuntime] pendingJobs];
  XCTAssertEqual((NSUInteger)1, [pending count]);
  NSDictionary *retryJob = pending[0];
  XCTAssertEqualObjects(@"push", retryJob[@"queue"]);
  XCTAssertEqualObjects((@[ phone[@"subscriptionID"] ]), retryJob[@"payload"][@"webPushSubscriptionIDs"]);
  NSTimeInterval delay = [retryJob[@"notBefore"] doubleValue] - [[NSDate date] timeIntervalSince1970];
  XCTAssertTrue(delay > 110.0 && delay <= 120.0, @"delay %f", delay);

  // The retry job sends to the one device; another failure fails the job with the
  // push service's delay so the jobs module waits at least that long.
  [self.transport respondTo:NWPAppleEndpoint status:503 headers:@{ @"retry-after" : @"30" }];
  error = nil;
  XCTAssertNil([runtime processQueuedNotificationPayload:retryJob[@"payload"] error:&error]);
  XCTAssertEqual(ALNNotificationsModuleErrorDeliveryFailed, error.code);
  XCTAssertEqualObjects(@30, error.userInfo[ALNJobsModuleRetryAfterSecondsErrorKey]);
  XCTAssertEqual((NSUInteger)3, [self.transport.requests count]);

  error = nil;
  NSDictionary *retried = [runtime processQueuedNotificationPayload:retryJob[@"payload"] error:&error];
  XCTAssertNotNil(retried, @"%@", error);
  XCTAssertEqualObjects((@[ @"webpush" ]), retried[@"channels"]);
  XCTAssertEqual((NSUInteger)4, [self.transport.requests count]);
  XCTAssertEqualObjects(NWPAppleEndpoint, [[[self.transport.requests lastObject] URL] absoluteString]);
}

- (void)testJobsRetryWaitsForServerRequestedDelay {
  ALNApplication *app = [self applicationWithWebPush:nil];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  ALNJobsModuleRuntime *jobs = [ALNJobsModuleRuntime sharedRuntime];
  XCTAssertTrue([jobs registerSystemJobDefinition:[[NWPRetryAfterJob alloc] init] error:&error], @"%@", error);
  XCTAssertNotNil([jobs enqueueJobIdentifier:@"nwp.retry_after" payload:@{} options:nil error:&error], @"%@", error);
  XCTAssertNotNil([jobs runWorkerAt:[NSDate date] limit:1 error:&error], @"%@", error);
  NSArray *pending = [jobs pendingJobs];
  XCTAssertEqual((NSUInteger)1, [pending count]);
  NSTimeInterval delay = [pending[0][@"notBefore"] doubleValue] - [[NSDate date] timeIntervalSince1970];
  XCTAssertTrue(delay > 290.0 && delay <= 300.0, @"delay %f", delay);
}

- (void)testMessagesAreValidatedBeforeQueueing {
  ALNNotificationsModuleRuntime *runtime = [self enabledRuntime];
  NSArray *cases = @[
    @{ @"body" : @"no title" },
    @{ @"title" : @"t", @"topic" : @"not a topic!" },
    @{ @"title" : @"t", @"urgency" : @"urgent" },
    @{ @"title" : @"t", @"body" : [@"" stringByPaddingToLength:4000 withString:@"x" startingAtIndex:0] },
  ];
  for (NSDictionary *rawMessage in cases) {
    NSError *error = nil;
    NSDictionary *payload = @{ @"recipient" : @"dan", @"rawMessage" : rawMessage };
    NSString *jobID = [runtime queueNotificationIdentifier:@"helpdesk.your_turn"
                                                   payload:payload
                                                  channels:@[ @"webpush" ]
                                                     error:&error];
    XCTAssertNil(jobID, @"%@", rawMessage);
    XCTAssertEqual(ALNNotificationsModuleErrorValidationFailed, error.code, @"%@", rawMessage);
  }
  XCTAssertEqual((NSUInteger)0, [[[ALNJobsModuleRuntime sharedRuntime] pendingJobs] count]);
}

- (void)testNudgeCarriesNoContentAndServiceWorkerHasFallbackText {
  ALNNotificationsModuleRuntime *runtime = [self enabledRuntime];
  NSDictionary *phone = [self deviceWithEndpoint:NWPAppleEndpoint];
  [self subscribeDevice:phone recipient:@"dan" runtime:runtime];
  NSError *error = nil;
  NSDictionary *payload = @{ @"recipient" : @"dan", @"nudge" : @YES };
  NSDictionary *sent = [runtime testSendNotificationIdentifier:@"helpdesk.your_turn"
                                                       payload:payload
                                                      channels:@[ @"webpush" ]
                                                         error:&error];
  XCTAssertNotNil(sent, @"%@", error);
  XCTAssertEqualObjects((@{ @"nudge" : @YES }), [self decryptRequest:self.transport.requests[0] forDevice:phone]);

  ALNApplication *app = [self applicationWithWebPush:[self enabledConfig]];
  [self registerApplication:app];
  ALNResponse *worker = [self dispatch:app method:@"GET" path:@"/notifications/push/service-worker.js" json:nil];
  XCTAssertEqual((NSInteger)200, worker.statusCode);
  XCTAssertEqualObjects(@"/", [worker headerForName:@"Service-Worker-Allowed"]);
  XCTAssertTrue([[worker headerForName:@"Content-Type"] hasPrefix:@"text/javascript"]);
  NSString *script = [[NSString alloc] initWithData:worker.bodyData encoding:NSUTF8StringEncoding];
  XCTAssertTrue([script containsString:@"\"title\":\"Helpdesk\""]);
  XCTAssertTrue([script containsString:@"showNotification"]);
  ALNResponse *client = [self dispatch:app method:@"GET" path:@"/notifications/push/client.js" json:nil];
  XCTAssertEqual((NSInteger)200, client.statusCode);
  XCTAssertTrue([[[NSString alloc] initWithData:client.bodyData encoding:NSUTF8StringEncoding] containsString:@"ArlenWebPush"]);
}

- (void)testServiceWorkerDefaultsCannotBreakOutOfTheScript {
  NSString *script = ALNWebPushServiceWorkerScript(@{ @"title" : @"</script><script>alert(1)</script>\u2028x" });
  NSString *firstLine = [script componentsSeparatedByString:@"\n"][0];
  XCTAssertFalse([firstLine containsString:@"</script>"]);
  XCTAssertTrue([firstLine containsString:@"\\u003c/script>"]);
  XCTAssertTrue([firstLine containsString:@"\\u2028x"]);
  XCTAssertFalse([firstLine containsString:@"\u2028"]);
}

- (void)testPreferenceOptOutSuppressesWebPushOnly {
  ALNNotificationsModuleRuntime *runtime = [self enabledRuntime];
  [self subscribeDevice:[self deviceWithEndpoint:NWPAppleEndpoint] recipient:@"dan" runtime:runtime];
  NSError *error = nil;
  XCTAssertNotNil([runtime updateNotificationPreferences:@{ @"helpdesk.your_turn" : @{ @"webpush" : @NO } }
                                            forRecipient:@"dan"
                                                   error:&error]);
  NSDictionary *result = [runtime testSendNotificationIdentifier:@"helpdesk.your_turn"
                                                         payload:@{ @"recipient" : @"dan" }
                                                        channels:nil
                                                           error:&error];
  XCTAssertNotNil(result, @"%@", error);
  XCTAssertEqualObjects((@[ @"in_app" ]), result[@"channels"]);
  XCTAssertEqualObjects((@[ @"webpush" ]), result[@"skippedChannels"]);
  XCTAssertEqual((NSUInteger)0, [self.transport.requests count]);
}

- (void)testSubscriptionRoutesUseTheSessionSubject {
  ALNApplication *app = [self applicationWithWebPush:[self enabledConfig]];
  ALNNotificationsModuleRuntime *runtime = [self registerApplication:app];
  NSDictionary *phone = [self deviceWithEndpoint:NWPAppleEndpoint];

  ALNResponse *anonymous = [self dispatch:app method:@"POST" path:@"/notifications/api/push/subscriptions"
                                     json:@{ @"subscription" : phone[@"subscription"] }];
  XCTAssertTrue(anonymous.statusCode == 401 || anonymous.statusCode == 403, @"%ld", (long)anonymous.statusCode);
  XCTAssertEqual((NSUInteger)0, [[runtime webPushSubscriptionsForRecipient:@"dan"] count]);

  self.auth.subject = @"dan";
  ALNResponse *config = [self dispatch:app method:@"GET" path:@"/notifications/api/push/config" json:nil];
  XCTAssertEqual((NSInteger)200, config.statusCode);
  XCTAssertEqualObjects(self.vapid[@"publicKey"], [self JSONFromResponse:config][@"data"][@"vapidPublicKey"]);

  ALNResponse *created = [self dispatch:app method:@"POST" path:@"/notifications/api/push/subscriptions"
                                   json:@{ @"subscription" : phone[@"subscription"], @"recipient" : @"someone-else" }];
  XCTAssertEqual((NSInteger)201, created.statusCode);
  XCTAssertEqual((NSUInteger)1, [[runtime webPushSubscriptionsForRecipient:@"dan"] count]);
  XCTAssertEqual((NSUInteger)0, [[runtime webPushSubscriptionsForRecipient:@"someone-else"] count]);
  XCTAssertEqualObjects(@"Mozilla/5.0 (iPhone)", [runtime webPushSubscriptionsForRecipient:@"dan"][0][@"userAgent"]);

  ALNResponse *rejected = [self dispatch:app method:@"POST" path:@"/notifications/api/push/subscriptions"
                                    json:@{ @"subscription" : @{ @"endpoint" : @"https://evil.test/x", @"keys" : phone[@"subscription"][@"keys"] } }];
  XCTAssertEqual((NSInteger)422, rejected.statusCode);

  ALNResponse *listed = [self dispatch:app method:@"GET" path:@"/notifications/api/push/subscriptions" json:nil];
  XCTAssertEqual((NSUInteger)1, [[self JSONFromResponse:listed][@"data"][@"subscriptions"] count]);

  ALNResponse *test = [self dispatch:app method:@"POST" path:@"/notifications/api/push/test" json:@{}];
  XCTAssertEqual((NSInteger)200, test.statusCode);
  XCTAssertEqualObjects(@"Test notification", [self decryptRequest:self.transport.requests[0] forDevice:phone][@"title"]);

  ALNResponse *removed = [self dispatch:app method:@"POST" path:@"/notifications/api/push/unsubscribe"
                                   json:@{ @"endpoint" : NWPAppleEndpoint }];
  XCTAssertEqual((NSInteger)200, removed.statusCode);
  XCTAssertEqualObjects(@YES, [self JSONFromResponse:removed][@"data"][@"removed"]);
  XCTAssertEqual((NSUInteger)0, [[runtime webPushSubscriptionsForRecipient:@"dan"] count]);
}

- (void)testTestRouteIsOffUnlessEnabled {
  NSMutableDictionary *config = [[self enabledConfig] mutableCopy];
  [config removeObjectForKey:@"testRoute"];
  ALNApplication *app = [self applicationWithWebPush:config];
  [self registerApplication:app];
  self.auth.subject = @"dan";
  ALNResponse *response = [self dispatch:app method:@"POST" path:@"/notifications/api/push/test" json:@{}];
  XCTAssertEqual((NSInteger)404, response.statusCode);
}

- (void)testFileStoreIsSharedAcrossStoreInstances {
  NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  NSString *path = [directory stringByAppendingPathComponent:@"push.plist"];
  ALNNotificationsWebPushSubscriptionStore *server = [[ALNNotificationsWebPushSubscriptionStore alloc] initWithPath:path];
  ALNNotificationsWebPushSubscriptionStore *worker = [[ALNNotificationsWebPushSubscriptionStore alloc] initWithPath:path];
  NSError *error = nil;
  NSDictionary *saved = [server saveSubscriptionWithEndpoint:NWPAppleEndpoint
                                                      p256dh:@"p"
                                                        auth:@"a"
                                                   userAgent:nil
                                                forRecipient:@"dan"
                                             maxPerRecipient:5
                                                       error:&error];
  XCTAssertNotNil(saved, @"%@", error);
  XCTAssertEqual((NSUInteger)1, [[worker subscriptionsForRecipient:@"dan" includeInactive:NO] count]);
  [worker deactivateSubscriptionID:saved[@"subscriptionID"] reason:@"gone"];
  XCTAssertEqual((NSUInteger)0, [[server subscriptionsForRecipient:@"dan" includeInactive:NO] count]);
  XCTAssertEqualObjects(@"gone", [server subscriptionWithID:saved[@"subscriptionID"]][@"inactiveReason"]);
  [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

- (void)testRetryAfterParsesSecondsAndHTTPDates {
  NSDate *now = [NSDate dateWithTimeIntervalSince1970:1760000000];
  XCTAssertEqual(120.0, ALNWebPushRetryAfterSeconds(@"120", now));
  XCTAssertEqual(-1.0, ALNWebPushRetryAfterSeconds(@"soon", now));
  XCTAssertEqual(-1.0, ALNWebPushRetryAfterSeconds(nil, now));
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
  [formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
  [formatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss 'GMT'"];
  NSString *later = [formatter stringFromDate:[now dateByAddingTimeInterval:90]];
  XCTAssertEqualWithAccuracy(90.0, ALNWebPushRetryAfterSeconds(later, now), 1.0);
}

@end
