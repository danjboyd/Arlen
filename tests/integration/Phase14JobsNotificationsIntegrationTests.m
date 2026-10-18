#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

static NSMutableArray<NSString *> *gPhase14IntegrationExecutions = nil;

static NSMutableArray<NSString *> *Phase14IntegrationExecutions(void) {
  if (gPhase14IntegrationExecutions == nil) {
    gPhase14IntegrationExecutions = [NSMutableArray array];
  }
  return gPhase14IntegrationExecutions;
}

// The signed-in identity the auth middleware below presents; reset in -setUp.
static NSString *gPhase14IntegrationSubject = @"user-77";
static NSArray<NSString *> *gPhase14IntegrationRoles = nil;
static NSInteger gPhase14IntegrationAAL = 2;

@interface Phase14IntegrationAuthMiddleware : NSObject <ALNMiddleware>
@end

@implementation Phase14IntegrationAuthMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSArray *roles = gPhase14IntegrationRoles ?: @[];
  context.stash[ALNContextAuthSubjectStashKey] = gPhase14IntegrationSubject;
  context.stash[ALNContextAuthRolesStashKey] = roles;
  context.stash[ALNContextAuthClaimsStashKey] = @{
    @"sub" : gPhase14IntegrationSubject,
    @"roles" : roles,
    @"aal" : @(gPhase14IntegrationAAL),
    @"amr" : (gPhase14IntegrationAAL >= 2) ? @[ @"otp" ] : @[ @"pwd" ],
    @"iat" : @((NSInteger)now),
    @"auth_time" : @((NSInteger)now),
    @"email" : [gPhase14IntegrationSubject stringByAppendingString:@"@self.example.test"],
    @"email_verified" : @YES,
  };
  return YES;
}

@end

@interface Phase14IntegrationJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase14IntegrationJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase14integration.echo";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Integration Echo",
    @"queue" : @"default",
    @"maxAttempts" : @2,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"value"] isKindOfClass:[NSString class]]) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14Integration"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"value is required" }];
  }
  return NO;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)context;
  (void)error;
  [Phase14IntegrationExecutions() addObject:payload[@"value"]];
  return YES;
}

@end

@interface Phase14IntegrationJobProvider : NSObject <ALNJobsJobProvider>
@end

@implementation Phase14IntegrationJobProvider

- (NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14IntegrationJob alloc] init] ];
}

@end

@interface Phase14IntegrationNotification : NSObject <ALNNotificationDefinition>
@end

@implementation Phase14IntegrationNotification

- (NSString *)notificationsModuleIdentifier {
  return @"phase14integration.welcome";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Integration Welcome",
    @"channels" : @[ @"email", @"in_app" ],
  };
}

- (NSArray<NSString *> *)notificationsModuleDefaultChannels {
  return @[ @"email", @"in_app" ];
}

- (BOOL)notificationsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"recipient"] isKindOfClass:[NSString class]] &&
      [payload[@"email"] isKindOfClass:[NSString class]]) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14Integration"
                                 code:2
                             userInfo:@{ NSLocalizedDescriptionKey : @"recipient and email are required" }];
  }
  return NO;
}

- (ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                     runtime:(ALNNotificationsModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)error;
  return [[ALNMailMessage alloc] initWithFrom:[runtime resolvedConfigSummary][@"sender"] ?: @"hello@example.test"
                                           to:@[ payload[@"email"] ?: @"" ]
                                           cc:nil
                                          bcc:nil
                                      subject:@"Integration Welcome"
                                     textBody:@"Welcome from integration."
                                     htmlBody:@"<p>Welcome from integration.</p>"
                                      headers:nil
                                     metadata:nil];
}

- (NSDictionary *)notificationsModuleInAppEntryForPayload:(NSDictionary *)payload
                                                  runtime:(ALNNotificationsModuleRuntime *)runtime
                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @{
    @"recipient" : payload[@"recipient"] ?: @"",
    @"title" : @"Integration Welcome",
    @"body" : @"Your workspace is ready.",
  };
}

@end

// In-app only, so a self-addressed queue needs no email address.
@interface Phase14IntegrationInboxNotification : NSObject <ALNNotificationDefinition>
@end

@implementation Phase14IntegrationInboxNotification

- (NSString *)notificationsModuleIdentifier {
  return @"phase14integration.inbox";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Integration Inbox",
    @"channels" : @[ @"in_app" ],
  };
}

- (NSArray<NSString *> *)notificationsModuleDefaultChannels {
  return @[ @"in_app" ];
}

- (BOOL)notificationsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"recipient"] isKindOfClass:[NSString class]]) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14Integration"
                                 code:3
                             userInfo:@{ NSLocalizedDescriptionKey : @"recipient is required" }];
  }
  return NO;
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
  return @{
    @"recipient" : payload[@"recipient"] ?: @"",
    @"title" : @"Integration Inbox",
    @"body" : @"Queued over HTTP.",
  };
}

@end

// Reads delivery targets from many payload keys, as a careless definition might.
static NSArray *Phase14SneakyValues(NSDictionary *payload, NSArray *keys) {
  NSMutableArray *values = [NSMutableArray array];
  NSDictionary *nested = [payload[@"nested"] isKindOfClass:[NSDictionary class]] ? payload[@"nested"] : @{};
  for (NSDictionary *source in @[ payload, nested ]) {
    for (NSString *key in keys) {
      if ([source[key] isKindOfClass:[NSString class]]) {
        [values addObject:source[key]];
      }
    }
  }
  return values;
}

@interface Phase14IntegrationSneakyNotification : NSObject <ALNNotificationDefinition>
@end

@implementation Phase14IntegrationSneakyNotification

- (NSString *)notificationsModuleIdentifier {
  return @"phase14integration.sneaky";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{ @"title" : @"Integration Sneaky", @"channels" : @[ @"email", @"in_app", @"webhook" ] };
}

- (BOOL)notificationsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  (void)payload;
  (void)error;
  return YES;
}

- (ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                     runtime:(ALNNotificationsModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)runtime;
  (void)error;
  NSMutableArray *to = [NSMutableArray arrayWithArray:Phase14SneakyValues(payload, @[ @"emailAddress", @"email_address", @"mail", @"destination" ])];
  if ([payload[@"email"] isKindOfClass:[NSString class]]) {
    [to addObject:payload[@"email"]];
  }
  return [[ALNMailMessage alloc] initWithFrom:@"hello@example.test"
                                           to:to
                                           cc:Phase14SneakyValues(payload, @[ @"phoneNumber" ])
                                          bcc:Phase14SneakyValues(payload, @[ @"mail" ])
                                      subject:@"Integration Sneaky"
                                     textBody:@"Hello."
                                     htmlBody:nil
                                      headers:@{ @"Bcc" : @"hidden@outside.example.test", @"X-Kind" : @"sneaky" }
                                     metadata:nil];
}

- (NSDictionary *)notificationsModuleInAppEntryForPayload:(NSDictionary *)payload
                                                  runtime:(ALNNotificationsModuleRuntime *)runtime
                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  NSMutableArray *recipients = [NSMutableArray arrayWithArray:Phase14SneakyValues(payload, @[ @"user", @"destination" ])];
  if ([payload[@"recipient"] isKindOfClass:[NSString class]]) {
    [recipients addObject:payload[@"recipient"]];
  }
  return @{ @"recipients" : recipients, @"recipientSubject" : [recipients firstObject] ?: @"", @"title" : @"Sneaky", @"body" : @"Hi." };
}

- (NSDictionary *)notificationsModuleWebhookRequestForPayload:(NSDictionary *)payload
                                                      runtime:(ALNNotificationsModuleRuntime *)runtime
                                                        error:(NSError **)error {
  (void)runtime;
  (void)error;
  NSString *url = [Phase14SneakyValues(payload, @[ @"webhook_url", @"callbackUrl", @"endpoint" ]) firstObject];
  return @{ @"url" : url ?: @"https://fixed.example.test/hook", @"method" : @"POST", @"body" : @{} };
}

@end

@interface Phase14IntegrationNotificationProvider : NSObject <ALNNotificationProvider>
@end

@implementation Phase14IntegrationNotificationProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    [[Phase14IntegrationNotification alloc] init],
    [[Phase14IntegrationInboxNotification alloc] init],
    [[Phase14IntegrationSneakyNotification alloc] init],
  ];
}

@end

@interface Phase14JobsNotificationsIntegrationTests : XCTestCase
@end

@implementation Phase14JobsNotificationsIntegrationTests

- (void)setUp {
  [super setUp];
  gPhase14IntegrationExecutions = [NSMutableArray array];
  gPhase14IntegrationSubject = @"user-77";
  gPhase14IntegrationRoles = @[ @"admin" ];
  gPhase14IntegrationAAL = 2;
}

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{
      @"enabled" : @NO,
    },
    @"jobsModule" : @{
      @"providers" : @{
        @"classes" : @[ @"Phase14IntegrationJobProvider" ],
      },
    },
    @"notificationsModule" : @{
      @"sender" : @"hello@example.test",
      @"providers" : @{
        @"classes" : @[ @"Phase14IntegrationNotificationProvider" ],
      },
    },
  }];
}

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                          headers:(NSDictionary *)headers
                             body:(NSData *)body {
  return [[ALNRequest alloc] initWithMethod:method ?: @"GET"
                                      path:path ?: @"/"
                               queryString:@""
                                   headers:headers ?: @{}
                                      body:body ?: [NSData data]];
}

- (NSDictionary *)JSONObjectFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([json isKindOfClass:[NSDictionary class]]);
  return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (void)testJobsAndNotificationsModulesWorkTogether {
  ALNApplication *app = [self application];
  [app addMiddleware:[[Phase14IntegrationAuthMiddleware alloc] init]];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  NSString *jobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:@"phase14integration.echo"
                                                                       payload:@{ @"value" : @"job-ok" }
                                                                       options:nil
                                                                         error:&error];
  XCTAssertNotNil(jobID);
  XCTAssertNil(error);
  NSDictionary *workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@1, workerSummary[@"acknowledgedCount"]);
  XCTAssertEqualObjects((@[ @"job-ok" ]), Phase14IntegrationExecutions());

  NSDictionary *payload = @{
    @"notification" : @"phase14integration.welcome",
    @"payload" : @{
      @"recipient" : @"user-77",
      @"email" : @"user77@example.test",
    },
  };
  NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
  ALNResponse *queueResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/notifications/api/queue"
                                           headers:@{ @"Content-Type" : @"application/json" }
                                              body:body]];
  XCTAssertEqual((NSInteger)200, queueResponse.statusCode);
  NSDictionary *queueJSON = [self JSONObjectFromResponse:queueResponse];
  XCTAssertTrue([queueJSON[@"data"][@"jobID"] isKindOfClass:[NSString class]]);

  workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);

  ALNResponse *outboxResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET" path:@"/notifications/api/outbox" headers:@{} body:nil]];
  NSDictionary *outboxJSON = [self JSONObjectFromResponse:outboxResponse];
  NSArray *outbox = [outboxJSON[@"data"][@"outbox"] isKindOfClass:[NSArray class]] ? outboxJSON[@"data"][@"outbox"] : @[];
  XCTAssertEqual((NSUInteger)4, [outbox count]);
  NSPredicate *queuedPredicate = [NSPredicate predicateWithFormat:@"status == %@", @"queued"];
  NSPredicate *deliveredPredicate = [NSPredicate predicateWithFormat:@"status == %@", @"delivered"];
  XCTAssertEqual((NSUInteger)2, [[outbox filteredArrayUsingPredicate:queuedPredicate] count]);
  XCTAssertEqual((NSUInteger)2, [[outbox filteredArrayUsingPredicate:deliveredPredicate] count]);

  ALNResponse *inboxResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/notifications/api/inbox/user-77"
                                           headers:@{}
                                              body:nil]];
  NSDictionary *inboxJSON = [self JSONObjectFromResponse:inboxResponse];
  NSArray *inbox = [inboxJSON[@"data"][@"inbox"] isKindOfClass:[NSArray class]] ? inboxJSON[@"data"][@"inbox"] : @[];
  XCTAssertEqual((NSUInteger)1, [inbox count]);
  XCTAssertEqual((NSUInteger)1, [[app.mailAdapter deliveriesSnapshot] count]);
}

- (ALNApplication *)registeredNotificationsApplication {
  ALNApplication *app = [self application];
  [app addMiddleware:[[Phase14IntegrationAuthMiddleware alloc] init]];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertTrue([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  return app;
}

- (ALNResponse *)queueNotification:(NSString *)identifier payload:(NSDictionary *)payload app:(ALNApplication *)app {
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{ @"notification" : identifier, @"payload" : payload ?: @{} }
                                                 options:0
                                                   error:NULL];
  return [app dispatchRequest:[self requestWithMethod:@"POST"
                                                 path:@"/notifications/api/queue"
                                              headers:@{ @"Content-Type" : @"application/json" }
                                                 body:body]];
}

- (NSUInteger)inboxCountForRecipient:(NSString *)recipient {
  NSDictionary *summary = [[ALNNotificationsModuleRuntime sharedRuntime] inboxSummaryForRecipient:recipient];
  return [summary[@"entries"] isKindOfClass:[NSArray class]] ? [summary[@"entries"] count] : 0U;
}

- (void)testQueueRouteLimitsOrdinaryUsersToThemselves {
  ALNApplication *app = [self registeredNotificationsApplication];
  NSString *subject = [NSString stringWithFormat:@"user-%@", [[NSUUID UUID] UUIDString]];
  NSString *victim = [NSString stringWithFormat:@"victim-%@", [[NSUUID UUID] UUIDString]];
  gPhase14IntegrationSubject = subject;
  gPhase14IntegrationRoles = @[];
  gPhase14IntegrationAAL = 1;

  NSArray *forbiddenPayloads = @[
    @{ @"recipient" : victim },
    @{ @"recipientSubject" : victim },
    @{ @"recipients" : @[ subject, victim ] },
    @{ @"recipient" : subject, @"email" : @"anyone@external.test" },
  ];
  for (NSDictionary *payload in forbiddenPayloads) {
    ALNResponse *response = [self queueNotification:@"phase14integration.inbox" payload:payload app:app];
    XCTAssertEqual((NSInteger)403, response.statusCode, @"%@", payload);
    NSDictionary *json = [self JSONObjectFromResponse:response];
    XCTAssertTrue([json[@"meta"][@"error"] containsString:@"admin role and AAL2"], @"%@", json);
  }

  // A self-addressed queue works, with or without naming the caller.
  XCTAssertEqual((NSInteger)200, [self queueNotification:@"phase14integration.inbox" payload:@{} app:app].statusCode);
  XCTAssertEqual((NSInteger)200,
                 [self queueNotification:@"phase14integration.inbox" payload:@{ @"recipient" : subject } app:app]
                     .statusCode);
  NSError *error = nil;
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:20 error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)2, [self inboxCountForRecipient:subject]);
  XCTAssertEqual((NSUInteger)0, [self inboxCountForRecipient:victim]);

  // An admin who has not stepped up is held to the same rule.
  gPhase14IntegrationRoles = @[ @"admin" ];
  XCTAssertEqual((NSInteger)403,
                 [self queueNotification:@"phase14integration.inbox" payload:@{ @"recipient" : victim } app:app]
                     .statusCode);
}

- (void)testQueueRouteLetsAdminsAtAAL2QueueForOthers {
  ALNApplication *app = [self registeredNotificationsApplication];
  NSString *recipient = [NSString stringWithFormat:@"member-%@", [[NSUUID UUID] UUIDString]];
  gPhase14IntegrationSubject = @"operator-1";
  gPhase14IntegrationRoles = @[ @"admin" ];
  gPhase14IntegrationAAL = 2;
  NSUInteger mailBefore = [[app.mailAdapter deliveriesSnapshot] count];

  NSDictionary *payload = @{ @"recipient" : recipient, @"email" : @"member@external.test" };
  ALNResponse *response = [self queueNotification:@"phase14integration.welcome" payload:payload app:app];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSError *error = nil;
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:20 error:&error]);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [self inboxCountForRecipient:recipient]);
  NSArray *deliveries = [app.mailAdapter deliveriesSnapshot];
  XCTAssertEqual(mailBefore + 1, [deliveries count]);
  NSDictionary *message = [[deliveries lastObject] isKindOfClass:[NSDictionary class]] ? [deliveries lastObject][@"message"] : @{};
  XCTAssertEqualObjects((@[ @"member@external.test" ]), message[@"to"]);
}

- (ALNResponse *)queueNotification:(NSString *)identifier
                           payload:(NSDictionary *)payload
                          channels:(NSArray *)channels
                               app:(ALNApplication *)app {
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{
    @"notification" : identifier,
    @"payload" : payload ?: @{},
    @"channels" : channels ?: @[],
  }
                                                 options:0
                                                   error:NULL];
  return [app dispatchRequest:[self requestWithMethod:@"POST"
                                                 path:@"/notifications/api/queue"
                                              headers:@{ @"Content-Type" : @"application/json" }
                                                 body:body]];
}

- (NSDictionary *)sneakyPayloadForVictim:(NSString *)victim {
  NSDictionary *targets = @{
    @"emailAddress" : @"a@outside.example.test",
    @"email_address" : @"b@outside.example.test",
    @"mail" : @"c@outside.example.test",
    @"destination" : @"d@outside.example.test",
    @"user" : victim,
    @"phoneNumber" : @"+15550100",
    @"webhook_url" : @"https://outside.example.test/hook",
    @"callbackUrl" : @"https://outside.example.test/callback",
    @"endpoint" : @"https://outside.example.test/endpoint",
  };
  NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:targets];
  payload[@"nested"] = targets;
  return payload;
}

- (void)testUserQueuedNotificationsDeliverOnlyToTheCaller {
  ALNApplication *app = [self registeredNotificationsApplication];
  NSString *subject = [NSString stringWithFormat:@"user-%@", [[NSUUID UUID] UUIDString]];
  NSString *victim = [NSString stringWithFormat:@"victim-%@", [[NSUUID UUID] UUIDString]];
  NSString *ownEmail = [subject stringByAppendingString:@"@self.example.test"];
  gPhase14IntegrationSubject = subject;
  gPhase14IntegrationRoles = @[];
  gPhase14IntegrationAAL = 1;
  NSUInteger mailBefore = [[app.mailAdapter deliveriesSnapshot] count];

  ALNResponse *response = [self queueNotification:@"phase14integration.sneaky"
                                          payload:[self sneakyPayloadForVictim:victim]
                                         channels:@[ @"email", @"in_app", @"webhook" ]
                                              app:app];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSArray *channelJobs = [self JSONObjectFromResponse:response][@"data"][@"channelJobs"];
  XCTAssertEqualObjects((@[ @"email", @"in_app" ]), [channelJobs valueForKey:@"channel"]);
  NSError *error = nil;
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:20 error:&error]);

  NSArray *deliveries = [app.mailAdapter deliveriesSnapshot];
  XCTAssertEqual(mailBefore + 1, [deliveries count]);
  NSDictionary *message = [deliveries lastObject][@"message"];
  XCTAssertEqualObjects((@[ ownEmail ]), message[@"to"]);
  XCTAssertEqual((NSUInteger)0, [message[@"cc"] count]);
  XCTAssertEqual((NSUInteger)0, [message[@"bcc"] count]);
  NSDictionary *headers = [message[@"headers"] isKindOfClass:[NSDictionary class]] ? message[@"headers"] : @{};
  XCTAssertNil(headers[@"Bcc"]);
  XCTAssertEqualObjects(@"sneaky", headers[@"X-Kind"]);
  XCTAssertEqual((NSUInteger)1, [self inboxCountForRecipient:subject]);
  XCTAssertEqual((NSUInteger)0, [self inboxCountForRecipient:victim]);

  // Only a webhook channel left: refused rather than sent to a payload URL.
  ALNResponse *webhookOnly = [self queueNotification:@"phase14integration.sneaky"
                                             payload:[self sneakyPayloadForVictim:victim]
                                            channels:@[ @"webhook" ]
                                                 app:app];
  XCTAssertEqual((NSInteger)403, webhookOnly.statusCode);
}

- (void)testAdminAtAAL2QueuedNotificationsKeepTheDefinitionTargets {
  ALNApplication *app = [self registeredNotificationsApplication];
  NSString *victim = [NSString stringWithFormat:@"member-%@", [[NSUUID UUID] UUIDString]];
  gPhase14IntegrationSubject = @"operator-2";
  gPhase14IntegrationRoles = @[ @"admin" ];
  gPhase14IntegrationAAL = 2;
  ALNResponse *response = [self queueNotification:@"phase14integration.sneaky"
                                          payload:[self sneakyPayloadForVictim:victim]
                                         channels:@[ @"email", @"in_app" ]
                                              app:app];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSError *error = nil;
  XCTAssertNotNil([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:20 error:&error]);
  NSDictionary *message = [[app.mailAdapter deliveriesSnapshot] lastObject][@"message"];
  XCTAssertTrue([message[@"to"] containsObject:@"a@outside.example.test"]);
  XCTAssertEqual((NSUInteger)1, [self inboxCountForRecipient:victim]);
}

@end
