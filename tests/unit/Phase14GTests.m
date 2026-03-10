#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"
#import "ALNOpsModule.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNStorageModule.h"

@interface Phase14GInjectedAuthMiddleware : NSObject <ALNMiddleware>

@property(nonatomic, copy) NSString *subject;
@property(nonatomic, copy) NSArray *roles;
@property(nonatomic, assign) NSUInteger assuranceLevel;

@end

@implementation Phase14GInjectedAuthMiddleware

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
  if ([self.subject length] == 0) {
    return YES;
  }
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  context.stash[ALNContextAuthSubjectStashKey] = self.subject;
  context.stash[ALNContextAuthRolesStashKey] = self.roles ?: @[];
  context.stash[ALNContextAuthClaimsStashKey] = @{
    @"sub" : self.subject ?: @"",
    @"roles" : self.roles ?: @[],
    @"aal" : @(MAX(self.assuranceLevel, (NSUInteger)1)),
    @"amr" : @[ (self.assuranceLevel >= 2) ? @"otp" : @"pwd" ],
    @"iat" : @((NSInteger)now),
    @"auth_time" : @((NSInteger)now),
  };
  return YES;
}

@end

@interface Phase14GOpsNotification : NSObject <ALNNotificationDefinition>
@end

@implementation Phase14GOpsNotification

- (NSString *)notificationsModuleIdentifier {
  return @"phase14g.ops";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Phase14G Ops",
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
    *error = [NSError errorWithDomain:@"Phase14G"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"recipient and email are required" }];
  }
  return NO;
}

- (ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                     runtime:(ALNNotificationsModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)error;
  return [[ALNMailMessage alloc] initWithFrom:[runtime resolvedConfigSummary][@"sender"] ?: @"phase14g@example.test"
                                           to:@[ payload[@"email"] ?: @"" ]
                                           cc:nil
                                          bcc:nil
                                      subject:@"Phase14G Ops"
                                     textBody:@"Phase14G Ops"
                                     htmlBody:@"<p>Phase14G Ops</p>"
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
    @"title" : @"Phase14G Ops",
    @"body" : @"Phase14G inbox",
  };
}

@end

@interface Phase14GOpsNotificationProvider : NSObject <ALNNotificationProvider>
@end

@implementation Phase14GOpsNotificationProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14GOpsNotification alloc] init] ];
}

@end

@interface Phase14GDocumentsCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation Phase14GDocumentsCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"documents";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Documents",
    @"acceptedContentTypes" : @[ @"text/plain" ],
    @"maxBytes" : @64,
    @"visibility" : @"private",
  };
}

@end

@interface Phase14GCollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation Phase14GCollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14GDocumentsCollection alloc] init] ];
}

@end

@interface Phase14GTests : XCTestCase
@end

@implementation Phase14GTests

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"notificationsModule" : @{
      @"sender" : @"phase14g@example.test",
      @"providers" : @{ @"classes" : @[ @"Phase14GOpsNotificationProvider" ] },
    },
    @"storageModule" : @{
      @"signingSecret" : @"phase14g-storage-secret",
      @"collections" : @{ @"classes" : @[ @"Phase14GCollectionProvider" ] },
    },
    @"opsModule" : @{
      @"access" : @{ @"roles" : @[ @"operator", @"admin" ], @"minimumAuthAssuranceLevel" : @2 },
    },
  }];
}

- (void)registerModulesForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNStorageModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNOpsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
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

- (BOOL)dictionary:(NSDictionary *)dictionary containsKeyNamed:(NSString *)targetKey {
  for (id key in [dictionary allKeys]) {
    if ([key isKindOfClass:[NSString class]] && [(NSString *)key isEqualToString:targetKey]) {
      return YES;
    }
    id value = dictionary[key];
    if ([value isKindOfClass:[NSDictionary class]] && [self dictionary:value containsKeyNamed:targetKey]) {
      return YES;
    }
    if ([value isKindOfClass:[NSArray class]]) {
      for (id entry in (NSArray *)value) {
        if ([entry isKindOfClass:[NSDictionary class]] && [self dictionary:entry containsKeyNamed:targetKey]) {
          return YES;
        }
      }
    }
  }
  return NO;
}

- (void)testOpsSummaryPayloadsAreRedactedAndDeterministic {
  ALNApplication *app = [self application];
  [self registerModulesForApplication:app];

  NSError *error = nil;
  NSDictionary *notification =
      [[ALNNotificationsModuleRuntime sharedRuntime] testSendNotificationIdentifier:@"phase14g.ops"
                                                                            payload:@{
                                                                              @"recipient" : @"ops-user",
                                                                              @"email" : @"ops-user@example.test",
                                                                            }
                                                                           channels:nil
                                                                              error:&error];
  XCTAssertNotNil(notification);
  XCTAssertNil(error);

  NSDictionary *object = [[ALNStorageModuleRuntime sharedRuntime] storeObjectInCollection:@"documents"
                                                                                      name:@"ops.txt"
                                                                               contentType:@"text/plain"
                                                                                      data:[@"ops" dataUsingEncoding:NSUTF8StringEncoding]
                                                                                  metadata:nil
                                                                                     error:&error];
  XCTAssertNotNil(object);
  XCTAssertNil(error);

  NSDictionary *summary = [[ALNOpsModuleRuntime sharedRuntime] dashboardSummary];
  XCTAssertEqualObjects((@[ @"operator", @"admin" ]), summary[@"config"][@"accessRoles"]);
  XCTAssertEqualObjects(@2, summary[@"config"][@"minimumAuthAssuranceLevel"]);
  XCTAssertTrue([summary[@"signals"][@"health"][@"statusCode"] integerValue] >= 200);
  XCTAssertEqualObjects(@"/metrics", summary[@"automation"][@"metricsPath"]);
  XCTAssertTrue([summary[@"automation"][@"openAPI"][@"pathCount"] integerValue] > 0);
  XCTAssertFalse([self dictionary:summary containsKeyNamed:@"signingSecret"]);
  XCTAssertNil(summary[@"automation"][@"openAPI"][@"paths"]);
  XCTAssertEqual((NSUInteger)2, [summary[@"notifications"][@"recentOutbox"] count]);
  XCTAssertEqual((NSUInteger)1, [summary[@"storage"][@"recentObjects"] count]);
}

- (void)testProtectedRoutesFailClosedForMissingRoleOrMissingStepUp {
  ALNApplication *app = [self application];
  Phase14GInjectedAuthMiddleware *middleware = [[Phase14GInjectedAuthMiddleware alloc] init];
  [app addMiddleware:middleware];
  [self registerModulesForApplication:app];

  middleware.subject = @"ops-user";
  middleware.roles = @[ @"member" ];
  middleware.assuranceLevel = 2;

  ALNResponse *forbidden =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/ops/api/summary"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)403, forbidden.statusCode);
  NSDictionary *forbiddenJSON = [self JSONObjectFromResponse:forbidden];
  XCTAssertEqualObjects(@"forbidden", forbiddenJSON[@"meta"][@"code"]);

  middleware.roles = @[ @"operator" ];
  middleware.assuranceLevel = 1;

  ALNResponse *htmlRedirect =
      [app dispatchRequest:[self requestWithMethod:@"GET" path:@"/ops" headers:@{} body:nil]];
  XCTAssertEqual((NSInteger)302, htmlRedirect.statusCode);
  XCTAssertTrue([[htmlRedirect headerForName:@"Location"] containsString:@"/auth/mfa/totp?return_to="]);

  ALNResponse *stepUp =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/ops/api/summary"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)403, stepUp.statusCode);
  NSDictionary *stepUpJSON = [self JSONObjectFromResponse:stepUp];
  XCTAssertEqualObjects(@"step_up_required", stepUpJSON[@"meta"][@"code"]);
}

@end
