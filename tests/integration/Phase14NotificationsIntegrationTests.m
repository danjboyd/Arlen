#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

@interface Phase14NotificationsInjectedAuthMiddleware : NSObject <ALNMiddleware>

@property(nonatomic, copy) NSString *subject;
@property(nonatomic, copy) NSArray *roles;
@property(nonatomic, assign) NSUInteger assuranceLevel;

@end

@implementation Phase14NotificationsInjectedAuthMiddleware

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _roles = @[];
    _assuranceLevel = 0;
  }
  return self;
}

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSString *subject = [self.subject isKindOfClass:[NSString class]] ? self.subject : @"";
  NSArray *roles = [self.roles isKindOfClass:[NSArray class]] ? self.roles : @[];
  if ([subject length] == 0 && [roles count] == 0) {
    return YES;
  }

  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  context.stash[ALNContextAuthSubjectStashKey] = subject;
  context.stash[ALNContextAuthRolesStashKey] = roles;
  context.stash[ALNContextAuthClaimsStashKey] = @{
    @"sub" : subject,
    @"roles" : roles,
    @"aal" : @(MAX(self.assuranceLevel, (NSUInteger)1)),
    @"amr" : @[ (self.assuranceLevel >= 2) ? @"otp" : @"pwd" ],
    @"iat" : @((NSInteger)now),
    @"auth_time" : @((NSInteger)now),
  };
  return YES;
}

@end

@interface Phase14NotificationsDefinition : NSObject <ALNNotificationDefinition>
@end

@implementation Phase14NotificationsDefinition

- (NSString *)notificationsModuleIdentifier {
  return @"phase14.notifications.preview";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Phase14 Preview",
    @"channels" : @[ @"email", @"in_app" ],
  };
}

- (NSArray<NSString *> *)notificationsModuleDefaultChannels {
  return @[ @"email", @"in_app" ];
}

- (BOOL)notificationsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"recipient"] isKindOfClass:[NSString class]] &&
      [payload[@"email"] isKindOfClass:[NSString class]] &&
      [payload[@"name"] isKindOfClass:[NSString class]]) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14NotificationsIntegration"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"recipient, email, and name are required" }];
  }
  return NO;
}

- (ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                     runtime:(ALNNotificationsModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)error;
  NSString *name = [payload[@"name"] isKindOfClass:[NSString class]] ? payload[@"name"] : @"friend";
  return [[ALNMailMessage alloc] initWithFrom:[runtime resolvedConfigSummary][@"sender"] ?: @"phase14@example.test"
                                           to:@[ payload[@"email"] ?: @"" ]
                                           cc:nil
                                          bcc:nil
                                      subject:[NSString stringWithFormat:@"Phase14 Preview %@", name]
                                     textBody:[NSString stringWithFormat:@"Hello %@.", name]
                                     htmlBody:[NSString stringWithFormat:@"<p>Hello %@.</p>", name]
                                      headers:nil
                                     metadata:@{ @"template" : @"phase14_preview" }];
}

- (NSDictionary *)notificationsModuleInAppEntryForPayload:(NSDictionary *)payload
                                                  runtime:(ALNNotificationsModuleRuntime *)runtime
                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  NSString *name = [payload[@"name"] isKindOfClass:[NSString class]] ? payload[@"name"] : @"friend";
  return @{
    @"recipient" : payload[@"recipient"] ?: @"",
    @"title" : @"Phase14 Inbox",
    @"body" : [NSString stringWithFormat:@"Hello %@.", name],
    @"metadata" : @{ @"kind" : @"phase14" },
  };
}

@end

@interface Phase14NotificationsProvider : NSObject <ALNNotificationProvider>
@end

@implementation Phase14NotificationsProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14NotificationsDefinition alloc] init] ];
}

@end

@interface Phase14NotificationsIntegrationTests : XCTestCase
@end

@implementation Phase14NotificationsIntegrationTests

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"notificationsModule" : @{
      @"sender" : @"phase14@example.test",
      @"providers" : @{ @"classes" : @[ @"Phase14NotificationsProvider" ] },
    },
  }];
}

- (void)registerModulesForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (ALNRequest *)requestWithMethod:(NSString *)method
                             path:(NSString *)path
                      queryString:(NSString *)queryString
                          headers:(NSDictionary *)headers
                             body:(NSData *)body {
  return [[ALNRequest alloc] initWithMethod:method ?: @"GET"
                                      path:path ?: @"/"
                               queryString:queryString ?: @""
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

- (NSString *)stringFromResponse:(ALNResponse *)response {
  return [[NSString alloc] initWithData:response.bodyData encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)testAuthenticatedUserCanInspectInboxOverHTMLAndJSON {
  ALNApplication *app = [self application];
  Phase14NotificationsInjectedAuthMiddleware *middleware =
      [[Phase14NotificationsInjectedAuthMiddleware alloc] init];
  [app addMiddleware:middleware];
  [self registerModulesForApplication:app];

  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *result = [runtime testSendNotificationIdentifier:@"phase14.notifications.preview"
                                                         payload:@{
                                                           @"recipient" : @"user-phase14",
                                                           @"email" : @"user-phase14@example.test",
                                                           @"name" : @"Taylor",
                                                         }
                                                        channels:nil
                                                           error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);

  ALNResponse *unauthorizedResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/notifications/api/inbox"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)401, unauthorizedResponse.statusCode);
  NSDictionary *unauthorizedJSON = [self JSONObjectFromResponse:unauthorizedResponse];
  XCTAssertEqualObjects(@"unauthorized", unauthorizedJSON[@"error"][@"code"]);

  ALNResponse *redirectResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/notifications/inbox"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)302, redirectResponse.statusCode);
  NSString *redirectLocation = [redirectResponse headerForName:@"Location"] ?: @"";
  XCTAssertTrue([redirectLocation containsString:@"/auth/login?return_to="]);

  middleware.subject = @"user-phase14";
  middleware.roles = @[];
  middleware.assuranceLevel = 1;

  ALNResponse *htmlResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/notifications/inbox"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, htmlResponse.statusCode);
  NSString *html = [self stringFromResponse:htmlResponse];
  XCTAssertTrue([html containsString:@"Recipient:"]);
  XCTAssertTrue([html containsString:@"user-phase14"]);
  XCTAssertTrue([html containsString:@"Phase14 Inbox"]);

  ALNResponse *jsonResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/notifications/api/inbox"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, jsonResponse.statusCode);
  NSDictionary *json = [self JSONObjectFromResponse:jsonResponse];
  NSArray *inbox = [json[@"data"][@"inbox"] isKindOfClass:[NSArray class]] ? json[@"data"][@"inbox"] : @[];
  XCTAssertEqual((NSUInteger)1, [inbox count]);
  XCTAssertEqualObjects(@"Phase14 Inbox", inbox[0][@"title"]);
  XCTAssertEqualObjects(@"user-phase14", inbox[0][@"recipient"]);
  XCTAssertEqualObjects(@1, json[@"data"][@"unreadCount"]);
  NSString *entryID = [inbox[0][@"entryID"] isKindOfClass:[NSString class]] ? inbox[0][@"entryID"] : @"";
  XCTAssertTrue([entryID length] > 0);

  ALNResponse *markReadResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:[NSString stringWithFormat:@"/notifications/api/inbox/%@/read", entryID]
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, markReadResponse.statusCode);
  NSDictionary *markReadJSON = [self JSONObjectFromResponse:markReadResponse];
  XCTAssertEqualObjects(@0, markReadJSON[@"data"][@"unreadCount"]);
  XCTAssertEqualObjects(@YES, markReadJSON[@"data"][@"entry"][@"read"]);

  ALNResponse *markUnreadResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:[NSString stringWithFormat:@"/notifications/api/inbox/%@/unread", entryID]
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, markUnreadResponse.statusCode);
  NSDictionary *markUnreadJSON = [self JSONObjectFromResponse:markUnreadResponse];
  XCTAssertEqualObjects(@1, markUnreadJSON[@"data"][@"unreadCount"]);
  XCTAssertEqualObjects(@NO, markUnreadJSON[@"data"][@"entry"][@"read"]);

  ALNResponse *readAllResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/notifications/inbox/read-all"
                                       queryString:@""
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)302, readAllResponse.statusCode);
  XCTAssertTrue([([readAllResponse headerForName:@"Location"] ?: @"") containsString:@"/notifications/inbox"]);

  ALNResponse *jsonAfterReadAll =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/notifications/api/inbox"
                                       queryString:@""
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, jsonAfterReadAll.statusCode);
  NSDictionary *jsonAfterReadAllPayload = [self JSONObjectFromResponse:jsonAfterReadAll];
  XCTAssertEqualObjects(@0, jsonAfterReadAllPayload[@"data"][@"unreadCount"]);
  NSArray *inboxAfterReadAll =
      [jsonAfterReadAllPayload[@"data"][@"inbox"] isKindOfClass:[NSArray class]] ? jsonAfterReadAllPayload[@"data"][@"inbox"] : @[];
  XCTAssertEqualObjects(@YES, inboxAfterReadAll[0][@"read"]);
}

- (void)testAdminCanPreviewAndTestSendNotification {
  ALNApplication *app = [self application];
  Phase14NotificationsInjectedAuthMiddleware *middleware =
      [[Phase14NotificationsInjectedAuthMiddleware alloc] init];
  [app addMiddleware:middleware];
  [self registerModulesForApplication:app];

  middleware.subject = @"admin-phase14";
  middleware.roles = @[ @"admin" ];
  middleware.assuranceLevel = 1;

  ALNResponse *stepUpResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/notifications/preview"
                                       queryString:@"notification=phase14.notifications.preview&recipient=admin-user&email=admin-user%40example.test&name=Admin"
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)302, stepUpResponse.statusCode);
  NSString *stepUpLocation = [stepUpResponse headerForName:@"Location"] ?: @"";
  XCTAssertTrue([stepUpLocation containsString:@"/auth/mfa/totp?return_to="]);

  middleware.assuranceLevel = 2;

  ALNResponse *previewResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/notifications/preview"
                                       queryString:@"notification=phase14.notifications.preview&recipient=admin-user&email=admin-user%40example.test&name=Admin"
                                           headers:@{}
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, previewResponse.statusCode);
  NSString *previewHTML = [self stringFromResponse:previewResponse];
  XCTAssertTrue([previewHTML containsString:@"Phase14 Preview Admin"]);
  XCTAssertTrue([previewHTML containsString:@"Phase14 Inbox"]);

  NSData *body =
      [NSJSONSerialization dataWithJSONObject:@{
        @"notification" : @"phase14.notifications.preview",
        @"payload" : @{
          @"recipient" : @"admin-user",
          @"email" : @"admin-user@example.test",
          @"name" : @"Admin",
        },
      }
                                  options:0
                                    error:NULL];
  ALNResponse *testSendResponse =
      [app dispatchRequest:[self requestWithMethod:@"POST"
                                              path:@"/notifications/api/test-send"
                                       queryString:@""
                                           headers:@{
                                             @"Accept" : @"application/json",
                                             @"Content-Type" : @"application/json",
                                           }
                                              body:body]];
  XCTAssertEqual((NSInteger)200, testSendResponse.statusCode);
  NSDictionary *json = [self JSONObjectFromResponse:testSendResponse];
  NSArray *channels = [json[@"data"][@"channels"] isKindOfClass:[NSArray class]] ? json[@"data"][@"channels"] : @[];
  XCTAssertTrue([channels containsObject:@"email"]);
  XCTAssertTrue([channels containsObject:@"in_app"]);

  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  XCTAssertEqual((NSUInteger)2, [[runtime outboxSnapshot] count]);
  XCTAssertEqual((NSUInteger)1, [[runtime inboxSnapshotForRecipient:@"admin-user"] count]);
  XCTAssertEqual((NSUInteger)1, [[app.mailAdapter deliveriesSnapshot] count]);
}

@end
