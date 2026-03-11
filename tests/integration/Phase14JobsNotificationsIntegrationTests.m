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

@interface Phase14IntegrationAuthMiddleware : NSObject <ALNMiddleware>
@end

@implementation Phase14IntegrationAuthMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  context.stash[ALNContextAuthSubjectStashKey] = @"user-77";
  context.stash[ALNContextAuthRolesStashKey] = @[ @"admin" ];
  context.stash[ALNContextAuthClaimsStashKey] = @{
    @"sub" : @"user-77",
    @"roles" : @[ @"admin" ],
    @"aal" : @2,
    @"amr" : @[ @"otp" ],
    @"iat" : @((NSInteger)now),
    @"auth_time" : @((NSInteger)now),
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

@interface Phase14IntegrationNotificationProvider : NSObject <ALNNotificationProvider>
@end

@implementation Phase14IntegrationNotificationProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14IntegrationNotification alloc] init] ];
}

@end

@interface Phase14JobsNotificationsIntegrationTests : XCTestCase
@end

@implementation Phase14JobsNotificationsIntegrationTests

- (void)setUp {
  [super setUp];
  gPhase14IntegrationExecutions = [NSMutableArray array];
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

@end
