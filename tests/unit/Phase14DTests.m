#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"

@interface Phase14DWelcomeNotification : NSObject <ALNNotificationDefinition>
@end

@implementation Phase14DWelcomeNotification

- (NSString *)notificationsModuleIdentifier {
  return @"phase14d.welcome";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Phase14D Welcome",
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
    *error = [NSError errorWithDomain:@"Phase14D"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"recipient, email, and name are required" }];
  }
  return NO;
}

- (ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                     runtime:(ALNNotificationsModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)error;
  NSString *name = payload[@"name"] ?: @"friend";
  return [[ALNMailMessage alloc] initWithFrom:[runtime resolvedConfigSummary][@"sender"] ?: @"notifications@example.test"
                                           to:@[ payload[@"email"] ?: @"" ]
                                           cc:nil
                                          bcc:nil
                                      subject:[NSString stringWithFormat:@"Phase14D Welcome %@", name]
                                     textBody:[NSString stringWithFormat:@"Hello %@.", name]
                                     htmlBody:[NSString stringWithFormat:@"<p>Hello %@.</p>", name]
                                      headers:nil
                                     metadata:@{ @"template" : @"phase14d_welcome" }];
}

- (NSDictionary *)notificationsModuleInAppEntryForPayload:(NSDictionary *)payload
                                                  runtime:(ALNNotificationsModuleRuntime *)runtime
                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @{
    @"recipient" : payload[@"recipient"] ?: @"",
    @"title" : @"Workspace Ready",
    @"body" : [NSString stringWithFormat:@"Hello %@.", payload[@"name"] ?: @"friend"],
    @"metadata" : @{ @"kind" : @"welcome" },
  };
}

@end

@interface Phase14DNotificationProvider : NSObject <ALNNotificationProvider>
@end

@implementation Phase14DNotificationProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14DWelcomeNotification alloc] init] ];
}

@end

@interface Phase14DPreferenceHook : NSObject <ALNNotificationPreferenceHook>
@end

@implementation Phase14DPreferenceHook

- (NSNumber *)notificationsModuleChannelEnabledForRecipient:(NSString *)recipient
                                     notificationIdentifier:(NSString *)identifier
                                                    channel:(NSString *)channel
                                             defaultEnabled:(BOOL)defaultEnabled
                                                    runtime:(ALNNotificationsModuleRuntime *)runtime {
  (void)identifier;
  (void)runtime;
  if ([recipient isEqualToString:@"hook-blocked"] && [channel isEqualToString:@"in_app"]) {
    return @NO;
  }
  return @(defaultEnabled);
}

@end

@interface Phase14DTests : XCTestCase
@end

@implementation Phase14DTests

- (ALNApplication *)applicationWithHook:(BOOL)withHook {
  NSMutableDictionary *notificationsConfig = [@{
    @"sender" : @"phase14d@example.test",
    @"providers" : @{
      @"classes" : @[ @"Phase14DNotificationProvider" ],
    },
  } mutableCopy];
  if (withHook) {
    notificationsConfig[@"preferences"] = @{ @"hookClass" : @"Phase14DPreferenceHook" };
  }
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[] },
    },
    @"notificationsModule" : notificationsConfig,
  }];
}

- (void)registerModulesForApplication:(ALNApplication *)app {
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
  XCTAssertTrue([[[ALNNotificationsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);
}

- (void)testPreviewAndDeliveryShareOneNotificationContract {
  ALNApplication *app = [self applicationWithHook:NO];
  [self registerModulesForApplication:app];

  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  NSDictionary *payload = @{
    @"recipient" : @"user-14d",
    @"email" : @"user14d@example.test",
    @"name" : @"Taylor",
  };
  NSError *error = nil;
  NSDictionary *preview = [runtime previewNotificationIdentifier:@"phase14d.welcome"
                                                         payload:payload
                                                        channels:nil
                                                           error:&error];
  XCTAssertNotNil(preview);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"Phase14D Welcome Taylor", preview[@"email"][@"subject"]);
  XCTAssertEqualObjects(@"Workspace Ready", preview[@"in_app"][@"title"]);
  XCTAssertEqualObjects((@[ @"user-14d" ]), preview[@"recipients"]);

  NSDictionary *result = [runtime testSendNotificationIdentifier:@"phase14d.welcome"
                                                         payload:payload
                                                        channels:nil
                                                           error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);
  XCTAssertEqualObjects((@[ @"email", @"in_app" ]), result[@"channels"]);
  XCTAssertEqual((NSUInteger)2, [[runtime outboxSnapshot] count]);
  XCTAssertEqual((NSUInteger)1, [[runtime inboxSnapshotForRecipient:@"user-14d"] count]);
  XCTAssertEqual((NSUInteger)1, [[app.mailAdapter deliveriesSnapshot] count]);
  XCTAssertEqualObjects(@"Workspace Ready", [runtime inboxSnapshotForRecipient:@"user-14d"][0][@"title"]);
}

- (void)testPreferenceRulesAreEvaluatedDeterministically {
  ALNApplication *app = [self applicationWithHook:YES];
  [self registerModulesForApplication:app];

  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *prefs =
      [runtime updateNotificationPreferences:@{
        @"phase14d.welcome" : @{
          @"email" : @NO,
          @"in_app" : @YES,
        },
      }
                             forRecipient:@"user-pref"
                                    error:&error];
  XCTAssertNotNil(prefs);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@NO, prefs[@"preferences"][@"phase14d.welcome"][@"email"]);

  NSDictionary *result = [runtime testSendNotificationIdentifier:@"phase14d.welcome"
                                                         payload:@{
                                                           @"recipient" : @"user-pref",
                                                           @"email" : @"pref@example.test",
                                                           @"name" : @"Prefs",
                                                         }
                                                        channels:nil
                                                           error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);
  XCTAssertTrue([result[@"skippedChannels"] containsObject:@"email"]);
  XCTAssertTrue([result[@"channels"] containsObject:@"in_app"]);
  XCTAssertEqual((NSUInteger)0, [[app.mailAdapter deliveriesSnapshot] count]);
  XCTAssertEqual((NSUInteger)1, [[runtime inboxSnapshotForRecipient:@"user-pref"] count]);

  result = [runtime testSendNotificationIdentifier:@"phase14d.welcome"
                                           payload:@{
                                             @"recipient" : @"hook-blocked",
                                             @"email" : @"hook@example.test",
                                             @"name" : @"Hook",
                                           }
                                          channels:nil
                                             error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);
  XCTAssertTrue([result[@"channels"] containsObject:@"email"]);
  XCTAssertTrue([result[@"skippedChannels"] containsObject:@"in_app"]);
  XCTAssertEqual((NSUInteger)1, [[app.mailAdapter deliveriesSnapshot] count]);
  XCTAssertEqual((NSUInteger)0, [[runtime inboxSnapshotForRecipient:@"hook-blocked"] count]);
}

@end
