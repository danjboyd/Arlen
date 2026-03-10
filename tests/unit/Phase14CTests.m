#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"

@interface Phase14CWelcomeNotification : NSObject <ALNNotificationDefinition>
@end

@implementation Phase14CWelcomeNotification

- (NSString *)notificationsModuleIdentifier {
  return @"phase14c.welcome";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Welcome Notification",
    @"channels" : @[ @"email", @"in_app" ],
  };
}

- (NSArray<NSString *> *)notificationsModuleDefaultChannels {
  return @[ @"email", @"in_app" ];
}

- (BOOL)notificationsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  NSString *recipient = [payload[@"recipient"] isKindOfClass:[NSString class]] ? payload[@"recipient"] : @"";
  NSString *email = [payload[@"email"] isKindOfClass:[NSString class]] ? payload[@"email"] : @"";
  if ([recipient length] > 0 && [email length] > 0) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14C"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"recipient and email are required" }];
  }
  return NO;
}

- (ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                     runtime:(ALNNotificationsModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)error;
  NSString *name = [payload[@"name"] isKindOfClass:[NSString class]] ? payload[@"name"] : @"there";
  return [[ALNMailMessage alloc] initWithFrom:[runtime resolvedConfigSummary][@"sender"] ?: @"notifications@example.test"
                                           to:@[ payload[@"email"] ?: @"" ]
                                           cc:nil
                                          bcc:nil
                                      subject:[NSString stringWithFormat:@"Welcome, %@", name]
                                     textBody:@"Welcome to Arlen."
                                     htmlBody:@"<p>Welcome to Arlen.</p>"
                                      headers:nil
                                     metadata:@{ @"template" : @"welcome" }];
}

- (NSDictionary *)notificationsModuleInAppEntryForPayload:(NSDictionary *)payload
                                                  runtime:(ALNNotificationsModuleRuntime *)runtime
                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @{
    @"recipient" : payload[@"recipient"] ?: @"",
    @"title" : @"Welcome",
    @"body" : @"Your account is ready.",
    @"metadata" : @{ @"kind" : @"welcome" },
  };
}

@end

@interface Phase14CAlertNotification : NSObject <ALNNotificationDefinition>
@end

@implementation Phase14CAlertNotification

- (NSString *)notificationsModuleIdentifier {
  return @"phase14c.alert";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Alert Notification",
    @"channels" : @[ @"email" ],
  };
}

- (NSArray<NSString *> *)notificationsModuleDefaultChannels {
  return @[ @"email" ];
}

- (BOOL)notificationsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  (void)payload;
  (void)error;
  return YES;
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
  (void)payload;
  (void)runtime;
  (void)error;
  return nil;
}

@end

@interface Phase14CNotificationProvider : NSObject <ALNNotificationProvider>
@end

@implementation Phase14CNotificationProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14CWelcomeNotification alloc] init], [[Phase14CAlertNotification alloc] init] ];
}

@end

@interface Phase14CTests : XCTestCase
@end

@implementation Phase14CTests

- (ALNApplication *)applicationWithConfig {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{
      @"enabled" : @NO,
    },
    @"jobsModule" : @{
      @"providers" : @{
        @"classes" : @[],
      },
    },
    @"notificationsModule" : @{
      @"sender" : @"hello@example.test",
      @"providers" : @{
        @"classes" : @[ @"Phase14CNotificationProvider" ],
      },
    },
  }];
}

- (void)testNotificationRegistrationOrderIsDeterministic {
  ALNApplication *app = [self applicationWithConfig];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  NSArray<NSDictionary *> *definitions = [runtime registeredNotifications];
  XCTAssertEqualObjects(@"phase14c.alert", definitions[0][@"identifier"]);
  XCTAssertEqualObjects(@"phase14c.welcome", definitions[1][@"identifier"]);
  XCTAssertEqualObjects(@"hello@example.test", [runtime resolvedConfigSummary][@"sender"]);
}

- (void)testNotificationQueueRejectsUnsupportedChannelAndDeliversViaJobsModule {
  ALNApplication *app = [self applicationWithConfig];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  NSString *invalid =
      [runtime queueNotificationIdentifier:@"phase14c.welcome"
                                  payload:@{
                                    @"recipient" : @"user-1",
                                    @"email" : @"user@example.test",
                                    @"name" : @"Taylor",
                                  }
                                 channels:@[ @"sms" ]
                                    error:&error];
  XCTAssertNil(invalid);
  XCTAssertNotNil(error);

  error = nil;
  NSString *jobID = [runtime queueNotificationIdentifier:@"phase14c.welcome"
                                                 payload:@{
                                                   @"recipient" : @"user-1",
                                                   @"email" : @"user@example.test",
                                                   @"name" : @"Taylor",
                                                 }
                                                channels:nil
                                                   error:&error];
  XCTAssertNotNil(jobID);
  XCTAssertNil(error);

  NSDictionary *workerSummary = [[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:10 error:&error];
  XCTAssertNotNil(workerSummary);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@1, workerSummary[@"acknowledgedCount"]);

  NSArray<NSDictionary *> *outbox = [runtime outboxSnapshot];
  XCTAssertEqual((NSUInteger)2, [outbox count]);
  XCTAssertEqualObjects(@"email", outbox[0][@"channel"]);
  XCTAssertEqualObjects(@"in_app", outbox[1][@"channel"]);
  XCTAssertEqual((NSUInteger)1, [[runtime inboxSnapshotForRecipient:@"user-1"] count]);
  XCTAssertEqual((NSUInteger)1, [[app.mailAdapter deliveriesSnapshot] count]);
}

@end
