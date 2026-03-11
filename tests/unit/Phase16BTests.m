#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"
#import "ALNRealtime.h"

@interface Phase16BNotification : NSObject <ALNNotificationDefinition>
@end

@implementation Phase16BNotification

- (NSString *)notificationsModuleIdentifier {
  return @"phase16b.digest";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Digest Ready",
    @"channels" : @[ @"email", @"in_app", @"webhook" ],
    @"channelPolicies" : @{
      @"webhook" : @{
        @"queue" : @"webhooks",
        @"maxAttempts" : @4,
        @"retryBackoff" : @{
          @"strategy" : @"linear",
          @"baseSeconds" : @2,
          @"maxSeconds" : @8,
        },
      },
    },
  };
}

- (NSArray<NSString *> *)notificationsModuleDefaultChannels {
  return @[ @"email", @"in_app", @"webhook" ];
}

- (BOOL)notificationsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"recipient"] isKindOfClass:[NSString class]] &&
      [payload[@"email"] isKindOfClass:[NSString class]] &&
      [payload[@"name"] isKindOfClass:[NSString class]]) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase16B"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"recipient, email, and name are required" }];
  }
  return NO;
}

- (ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                     runtime:(ALNNotificationsModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)error;
  return [[ALNMailMessage alloc] initWithFrom:[runtime resolvedConfigSummary][@"sender"] ?: @"notify@example.test"
                                           to:@[ payload[@"email"] ?: @"" ]
                                           cc:nil
                                          bcc:nil
                                      subject:@"Digest Ready"
                                     textBody:@"Your digest is ready."
                                     htmlBody:@"<p>Your digest is ready.</p>"
                                      headers:nil
                                     metadata:@{ @"kind" : @"digest" }];
}

- (NSDictionary *)notificationsModuleInAppEntryForPayload:(NSDictionary *)payload
                                                  runtime:(ALNNotificationsModuleRuntime *)runtime
                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @{
    @"recipient" : payload[@"recipient"] ?: @"",
    @"title" : @"Digest Ready",
    @"body" : [NSString stringWithFormat:@"Hello %@.", payload[@"name"] ?: @"friend"],
    @"metadata" : @{ @"kind" : @"digest" },
  };
}

- (NSDictionary *)notificationsModuleWebhookRequestForPayload:(NSDictionary *)payload
                                                      runtime:(ALNNotificationsModuleRuntime *)runtime
                                                        error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @{
    @"url" : @"https://hooks.example.test/digest",
    @"body" : @{
      @"recipient" : payload[@"recipient"] ?: @"",
      @"name" : payload[@"name"] ?: @"",
    },
  };
}

@end

@interface Phase16BNotificationProvider : NSObject <ALNNotificationProvider>
@end

@implementation Phase16BNotificationProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16BNotification alloc] init] ];
}

@end

@interface Phase16BFanoutSubscriber : NSObject <ALNRealtimeSubscriber>

@property(nonatomic, strong) NSMutableArray<NSDictionary *> *received;

@end

@implementation Phase16BFanoutSubscriber

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _received = [NSMutableArray array];
  }
  return self;
}

- (void)receiveRealtimeMessage:(NSString *)message onChannel:(NSString *)channel {
  [self.received addObject:@{
    @"channel" : channel ?: @"",
    @"message" : message ?: @"",
  }];
}

@end

@interface Phase16BTests : XCTestCase
@end

@implementation Phase16BTests

- (void)setUp {
  [super setUp];
  [[ALNRealtimeHub sharedHub] reset];
}

- (NSString *)temporaryDirectory {
  NSString *template =
      [NSTemporaryDirectory() stringByAppendingPathComponent:@"arlen-phase16b-XXXXXX"];
  const char *templateCString = [template fileSystemRepresentation];
  char *buffer = strdup(templateCString);
  XCTAssertNotEqual(buffer, NULL);
  char *created = mkdtemp(buffer);
  XCTAssertNotEqual(created, NULL);
  NSString *result = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:buffer
                                                                                  length:strlen(buffer)];
  free(buffer);
  return result;
}

- (ALNApplication *)applicationWithStatePath:(NSString *)statePath {
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"notificationsModule" : @{
      @"sender" : @"phase16b@example.test",
      @"providers" : @{ @"classes" : @[ @"Phase16BNotificationProvider" ] },
      @"persistence" : @{
        @"enabled" : @YES,
        @"path" : statePath ?: @"",
      },
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

- (void)testNotificationStatePersistsAcrossReconfigure {
  NSString *tempDir = [self temporaryDirectory];
  NSString *statePath = [tempDir stringByAppendingPathComponent:@"notifications-state.plist"];

  ALNApplication *app = [self applicationWithStatePath:statePath];
  [self registerModulesForApplication:app];

  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *prefs = [runtime updateNotificationPreferences:@{
    @"phase16b.digest" : @{
      @"email" : @NO,
      @"in_app" : @YES,
    },
  }
                                             forRecipient:@"persist-user"
                                                    error:&error];
  XCTAssertNotNil(prefs);
  XCTAssertNil(error);

  NSDictionary *result = [runtime testSendNotificationIdentifier:@"phase16b.digest"
                                                         payload:@{
                                                           @"recipient" : @"persist-user",
                                                           @"email" : @"persist@example.test",
                                                           @"name" : @"Persist",
                                                         }
                                                        channels:nil
                                                           error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);
  XCTAssertTrue([result[@"channels"] containsObject:@"in_app"]);
  XCTAssertTrue([result[@"channels"] containsObject:@"webhook"]);
  XCTAssertTrue([result[@"skippedChannels"] containsObject:@"email"]);
  XCTAssertEqual((NSUInteger)1, [[app.webhookAdapter deliveriesSnapshot] count]);

  ALNApplication *restarted = [self applicationWithStatePath:statePath];
  [self registerModulesForApplication:restarted];

  runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  XCTAssertEqual((NSUInteger)3, [[runtime outboxSnapshot] count]);
  NSArray<NSDictionary *> *inbox = [runtime inboxSnapshotForRecipient:@"persist-user"];
  XCTAssertEqual((NSUInteger)1, [inbox count]);
  NSDictionary *markReadResult = [runtime markInboxEntryID:inbox[0][@"entryID"]
                                                      read:YES
                                              forRecipient:@"persist-user"
                                                     error:&error];
  XCTAssertNotNil(markReadResult);
  XCTAssertNil(error);

  ALNApplication *reread = [self applicationWithStatePath:statePath];
  [self registerModulesForApplication:reread];

  runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  NSDictionary *inboxSummary = [runtime inboxSummaryForRecipient:@"persist-user"];
  XCTAssertEqualObjects(@0, inboxSummary[@"unreadCount"]);
  XCTAssertEqualObjects(@YES, inboxSummary[@"entries"][0][@"read"]);
  XCTAssertEqualObjects(@NO,
                        [runtime notificationPreferencesForRecipient:@"persist-user"][@"phase16b.digest"][@"email"]);
}

- (void)testInAppDeliveryPublishesRealtimeFanout {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"notifications-state.plist"]];
  [self registerModulesForApplication:app];

  Phase16BFanoutSubscriber *subscriber = [[Phase16BFanoutSubscriber alloc] init];
  ALNRealtimeSubscription *subscription =
      [[ALNRealtimeHub sharedHub] subscribeChannel:@"notifications.inbox.realtime-user"
                                        subscriber:subscriber];
  XCTAssertNotNil(subscription);

  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *result = [runtime testSendNotificationIdentifier:@"phase16b.digest"
                                                         payload:@{
                                                           @"recipient" : @"realtime-user",
                                                           @"email" : @"rt@example.test",
                                                           @"name" : @"Realtime",
                                                         }
                                                        channels:@[ @"in_app" ]
                                                           error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [subscriber.received count]);
  XCTAssertTrue([subscriber.received[0][@"channel"] containsString:@"realtime-user"]);

  NSDictionary *summary = [runtime dashboardSummary];
  NSArray *recentFanout = [summary[@"recentFanout"] isKindOfClass:[NSArray class]] ? summary[@"recentFanout"] : @[];
  XCTAssertEqual((NSUInteger)1, [recentFanout count]);
  XCTAssertEqualObjects(@"realtime-user", recentFanout[0][@"recipient"]);
}

- (void)testInboxReadUnreadStateAndMarkAllRoundTrip {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"notifications-state.plist"]];
  [self registerModulesForApplication:app];

  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *result = [runtime testSendNotificationIdentifier:@"phase16b.digest"
                                                         payload:@{
                                                           @"recipient" : @"reader-user",
                                                           @"email" : @"reader@example.test",
                                                           @"name" : @"Reader",
                                                         }
                                                        channels:@[ @"in_app" ]
                                                           error:&error];
  XCTAssertNotNil(result);
  XCTAssertNil(error);

  NSDictionary *summary = [runtime inboxSummaryForRecipient:@"reader-user"];
  NSArray<NSDictionary *> *entries = [summary[@"entries"] isKindOfClass:[NSArray class]] ? summary[@"entries"] : @[];
  XCTAssertEqual((NSUInteger)1, [entries count]);
  XCTAssertEqualObjects(@1, summary[@"unreadCount"]);
  XCTAssertEqualObjects(@NO, entries[0][@"read"]);

  NSDictionary *markReadResult = [runtime markInboxEntryID:entries[0][@"entryID"]
                                                      read:YES
                                              forRecipient:@"reader-user"
                                                     error:&error];
  XCTAssertNotNil(markReadResult);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@0, markReadResult[@"unreadCount"]);
  XCTAssertEqualObjects(@YES, markReadResult[@"entry"][@"read"]);
  XCTAssertNotNil(markReadResult[@"entry"][@"readAt"]);

  NSDictionary *markUnreadResult = [runtime markInboxEntryID:entries[0][@"entryID"]
                                                        read:NO
                                                forRecipient:@"reader-user"
                                                       error:&error];
  XCTAssertNotNil(markUnreadResult);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@1, markUnreadResult[@"unreadCount"]);
  XCTAssertEqualObjects(@NO, markUnreadResult[@"entry"][@"read"]);
  XCTAssertNil(markUnreadResult[@"entry"][@"readAt"]);

  NSDictionary *markAllResult = [runtime markAllInboxEntriesReadForRecipient:@"reader-user" error:&error];
  XCTAssertNotNil(markAllResult);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@1, markAllResult[@"updatedCount"]);
  XCTAssertEqualObjects(@0, markAllResult[@"unreadCount"]);

  NSDictionary *dashboardSummary = [runtime dashboardSummary];
  NSArray *cards = [dashboardSummary[@"cards"] isKindOfClass:[NSArray class]] ? dashboardSummary[@"cards"] : @[];
  NSPredicate *unreadPredicate = [NSPredicate predicateWithFormat:@"label == %@", @"Unread Inbox"];
  NSDictionary *unreadCard = [[cards filteredArrayUsingPredicate:unreadPredicate] firstObject];
  XCTAssertEqualObjects(@0, unreadCard[@"value"]);
}

- (void)testQueueingSplitsChannelJobsAndRecordsQueuedAuditEntries {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"notifications-state.plist"]];
  [self registerModulesForApplication:app];

  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSString *jobID =
      [runtime queueNotificationIdentifier:@"phase16b.digest"
                                   payload:@{
                                     @"recipient" : @"queue-user",
                                     @"email" : @"queue@example.test",
                                     @"name" : @"Queue",
                                   }
                                  channels:@[ @"email", @"webhook" ]
                                     error:&error];
  XCTAssertNotNil(jobID);
  XCTAssertNil(error);

  NSArray *pending = [[ALNJobsModuleRuntime sharedRuntime] pendingJobs];
  XCTAssertEqual((NSUInteger)2, [pending count]);
  NSPredicate *webhookPredicate = [NSPredicate predicateWithFormat:@"queue == %@", @"webhooks"];
  XCTAssertEqual((NSUInteger)1, [[pending filteredArrayUsingPredicate:webhookPredicate] count]);

  NSArray *outbox = [runtime outboxSnapshot];
  NSPredicate *queuedPredicate = [NSPredicate predicateWithFormat:@"status == %@", @"queued"];
  XCTAssertEqual((NSUInteger)2, [[outbox filteredArrayUsingPredicate:queuedPredicate] count]);
}

@end
