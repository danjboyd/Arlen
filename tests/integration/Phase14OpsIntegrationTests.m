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

@interface Phase14OpsAuthMiddleware : NSObject <ALNMiddleware>
@property(nonatomic, copy) NSArray *roles;
@end

@implementation Phase14OpsAuthMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  context.stash[ALNContextAuthSubjectStashKey] = @"operator-14g";
  NSArray *roles = self.roles ?: @[ @"operator" ];
  context.stash[ALNContextAuthRolesStashKey] = roles;
  context.stash[ALNContextAuthClaimsStashKey] = @{
    @"sub" : @"operator-14g",
    @"roles" : roles,
    @"aal" : @2,
    @"amr" : @[ @"otp" ],
    @"iat" : @((NSInteger)now),
    @"auth_time" : @((NSInteger)now),
  };
  return YES;
}

@end

@interface Phase14OpsJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase14OpsJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase14ops.echo";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Phase14 Ops Echo",
    @"queue" : @"default",
    @"maxAttempts" : @2,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"value"] isKindOfClass:[NSString class]]) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14Ops"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"value is required" }];
  }
  return NO;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)payload;
  (void)context;
  (void)error;
  return YES;
}

@end

@interface Phase14OpsJobProvider : NSObject <ALNJobsJobProvider>
@end

@implementation Phase14OpsJobProvider

- (NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14OpsJob alloc] init] ];
}

@end

@interface Phase14OpsNotification : NSObject <ALNNotificationDefinition>
@end

@implementation Phase14OpsNotification

- (NSString *)notificationsModuleIdentifier {
  return @"phase14ops.notification";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Phase14 Ops Notification",
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
    *error = [NSError errorWithDomain:@"Phase14Ops"
                                 code:2
                             userInfo:@{ NSLocalizedDescriptionKey : @"recipient and email are required" }];
  }
  return NO;
}

- (ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                     runtime:(ALNNotificationsModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)error;
  return [[ALNMailMessage alloc] initWithFrom:[runtime resolvedConfigSummary][@"sender"] ?: @"phase14ops@example.test"
                                           to:@[ payload[@"email"] ?: @"" ]
                                           cc:nil
                                          bcc:nil
                                      subject:@"Phase14 Ops Notification"
                                     textBody:@"Phase14 Ops Notification"
                                     htmlBody:@"<p>Phase14 Ops Notification</p>"
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
    @"title" : @"Phase14 Ops Inbox",
    @"body" : @"Operations notification",
  };
}

@end

@interface Phase14OpsNotificationProvider : NSObject <ALNNotificationProvider>
@end

@implementation Phase14OpsNotificationProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14OpsNotification alloc] init] ];
}

@end

@interface Phase14OpsCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation Phase14OpsCollection

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

@interface Phase14OpsCollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation Phase14OpsCollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14OpsCollection alloc] init] ];
}

@end

@interface Phase14OpsIntegrationTests : XCTestCase
@end

@implementation Phase14OpsIntegrationTests

- (ALNApplication *)application {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[ @"Phase14OpsJobProvider" ] },
    },
    @"notificationsModule" : @{
      @"sender" : @"phase14ops@example.test",
      @"providers" : @{ @"classes" : @[ @"Phase14OpsNotificationProvider" ] },
    },
    @"storageModule" : @{
      @"collections" : @{ @"classes" : @[ @"Phase14OpsCollectionProvider" ] },
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

- (NSString *)stringFromResponse:(ALNResponse *)response {
  return [[NSString alloc] initWithData:response.bodyData encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)testOperatorCanAccessOpsHTMLAndJSONWithLiveModuleState {
  ALNApplication *app = [self application];
  Phase14OpsAuthMiddleware *auth = [[Phase14OpsAuthMiddleware alloc] init];
  [app addMiddleware:auth];
  [self registerModulesForApplication:app];

  NSError *error = nil;
  NSString *jobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:@"phase14ops.echo"
                                                                       payload:@{ @"value" : @"private-job-payload-marker" }
                                                                       options:nil
                                                                         error:&error];
  XCTAssertNotNil(jobID);
  XCTAssertNil(error);

  NSDictionary *notification =
      [[ALNNotificationsModuleRuntime sharedRuntime] testSendNotificationIdentifier:@"phase14ops.notification"
                                                                            payload:@{
                                                                              @"recipient" : @"operator-14g",
                                                                              @"email" : @"private-outbox-marker@example.test",
                                                                            }
                                                                           channels:nil
                                                                              error:&error];
  XCTAssertNotNil(notification);
  XCTAssertNil(error);

  NSDictionary *object = [[ALNStorageModuleRuntime sharedRuntime] storeObjectInCollection:@"documents"
                                                                                      name:@"phase14ops.txt"
                                                                               contentType:@"text/plain"
                                                                                      data:[@"ops" dataUsingEncoding:NSUTF8StringEncoding]
                                                                                  metadata:nil
                                                                                     error:&error];
  XCTAssertNotNil(object);
  XCTAssertNil(error);

  ALNResponse *htmlResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET" path:@"/ops" headers:@{} body:nil]];
  XCTAssertEqual((NSInteger)200, htmlResponse.statusCode);
  NSString *html = [self stringFromResponse:htmlResponse];
  XCTAssertFalse([html containsString:@"private-job-payload-marker"]);
  XCTAssertFalse([html containsString:@"private-outbox-marker"]);
  XCTAssertTrue([html containsString:@"phase14ops.txt"]);

  ALNResponse *jsonResponse =
      [app dispatchRequest:[self requestWithMethod:@"GET"
                                              path:@"/ops/api/summary"
                                           headers:@{ @"Accept" : @"application/json" }
                                              body:nil]];
  XCTAssertEqual((NSInteger)200, jsonResponse.statusCode);
  NSDictionary *json = [self JSONObjectFromResponse:jsonResponse];
  NSDictionary *summary = [json[@"data"] isKindOfClass:[NSDictionary class]] ? json[@"data"] : @{};
  XCTAssertEqualObjects(@1, summary[@"jobs"][@"totals"][@"pending"]);
  XCTAssertNil(summary[@"jobs"][@"pendingJobs"]);
  XCTAssertNil(summary[@"jobs"][@"leasedJobs"]);
  XCTAssertNil(summary[@"jobs"][@"deadLetterJobs"]);
  XCTAssertNil(summary[@"jobs"][@"recentRuns"]);
  XCTAssertNil(summary[@"notifications"][@"recentOutbox"]);
  XCTAssertNil(summary[@"notifications"][@"recentFanout"]);
  XCTAssertEqual((NSUInteger)1, [summary[@"storage"][@"recentObjects"] count]);
  XCTAssertEqualObjects(@"phase14ops.txt", summary[@"storage"][@"recentObjects"][0][@"name"]);
  for (NSString *module in @[ @"jobs", @"notifications" ]) {
    NSString *path = [@"/ops/api/modules/" stringByAppendingString:module];
    ALNResponse *drilldownResponse = [app dispatchRequest:[self requestWithMethod:@"GET" path:path
                                                      headers:@{ @"Accept" : @"application/json" } body:nil]];
    XCTAssertEqual((NSInteger)200, drilldownResponse.statusCode);
    NSString *body = [self stringFromResponse:drilldownResponse];
    XCTAssertFalse([body containsString:@"private-job-payload-marker"]);
    XCTAssertFalse([body containsString:@"private-outbox-marker"]);
    NSString *htmlPath = [@"/ops/modules/" stringByAppendingString:module];
    ALNResponse *htmlDrilldown = [app dispatchRequest:[self requestWithMethod:@"GET" path:htmlPath
                                                                 headers:@{} body:nil]];
    XCTAssertEqual((NSInteger)200, htmlDrilldown.statusCode);
    XCTAssertFalse([[self stringFromResponse:htmlDrilldown] containsString:@"private-job-payload-marker"]);
    XCTAssertFalse([[self stringFromResponse:htmlDrilldown] containsString:@"private-outbox-marker"]);
  }

  auth.roles = @[ @"admin" ];
  ALNResponse *adminResponse = [app dispatchRequest:[self requestWithMethod:@"GET"
                                               path:@"/ops/api/summary"
                                            headers:@{ @"Accept" : @"application/json" } body:nil]];
  XCTAssertEqual((NSInteger)200, adminResponse.statusCode);
  NSDictionary *adminSummary = [self JSONObjectFromResponse:adminResponse][@"data"];
  XCTAssertEqual((NSUInteger)2, [adminSummary[@"notifications"][@"recentOutbox"] count]);
  XCTAssertTrue([adminSummary[@"jobs"][@"pendingJobs"] count] > 0);
  XCTAssertTrue([[self stringFromResponse:adminResponse] containsString:@"private-job-payload-marker"]);
  XCTAssertTrue([[self stringFromResponse:adminResponse] containsString:@"private-outbox-marker"]);
}

@end
