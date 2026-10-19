#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <unistd.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"
#import "ALNRealtime.h"
#import "../shared/ALNTestSupport.h"
#import "../shared/ALNTestWait.h"

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
  NSString *directory = ALNTestTemporaryDirectory(@"arlen-phase16b");
  XCTAssertNotNil(directory);
  return directory;
}

- (BOOL)waitForFileAtPath:(NSString *)path {
  return ALNTestWaitUntil(5.0, 0.05, ^BOOL {
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
  });
}

- (ALNApplication *)applicationWithStatePath:(NSString *)statePath {
  return [self applicationWithStatePath:statePath extraModuleConfig:nil];
}

- (ALNApplication *)applicationWithStatePath:(NSString *)statePath extraModuleConfig:(NSDictionary *)extra {
  NSMutableDictionary *moduleConfig = [NSMutableDictionary dictionaryWithDictionary:@{
    @"sender" : @"phase16b@example.test",
    @"providers" : @{ @"classes" : @[ @"Phase16BNotificationProvider" ] },
    @"persistence" : @{
      @"enabled" : @YES,
      @"path" : statePath ?: @"",
    },
  }];
  [moduleConfig addEntriesFromDictionary:extra ?: @{}];
  return [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"jobsModule" : @{ @"providers" : @{ @"classes" : @[] } },
    @"notificationsModule" : moduleConfig,
  }];
}

- (void)sendInAppDigestsToRecipient:(NSString *)recipient count:(NSUInteger)count {
  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  for (NSUInteger index = 0; index < count; index++) {
    NSError *error = nil;
    NSDictionary *result = [runtime testSendNotificationIdentifier:@"phase16b.digest"
                                                           payload:@{
                                                             @"recipient" : recipient,
                                                             @"email" : @"reader@example.test",
                                                             @"name" : [NSString stringWithFormat:@"Reader %lu", (unsigned long)index],
                                                           }
                                                          channels:@[ @"in_app" ]
                                                             error:&error];
    XCTAssertNotNil(result);
    XCTAssertNil(error);
  }
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

- (void)testOutboxAndInboxCapsDropOldestEntries {
  NSString *statePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"notifications-state.plist"];
  ALNApplication *app = [self applicationWithStatePath:statePath
                                     extraModuleConfig:@{
                                       @"outbox" : @{ @"maxEntries" : @4 },
                                       @"inbox" : @{ @"maxEntriesPerRecipient" : @"3" },
                                     }];
  [self registerModulesForApplication:app];
  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  XCTAssertEqualObjects(@4, [runtime resolvedConfigSummary][@"maxOutboxEntries"]);
  XCTAssertEqualObjects(@3, [runtime resolvedConfigSummary][@"maxInboxEntriesPerRecipient"]);

  [self sendInAppDigestsToRecipient:@"capped-user" count:6];
  [self sendInAppDigestsToRecipient:@"other-user" count:1];

  NSArray *inbox = [runtime inboxSnapshotForRecipient:@"capped-user"];
  XCTAssertEqual((NSUInteger)3, [inbox count]);
  NSArray *bodies = [inbox valueForKey:@"body"];
  XCTAssertEqualObjects((@[ @"Hello Reader 3.", @"Hello Reader 4.", @"Hello Reader 5." ]), bodies);
  XCTAssertEqual((NSUInteger)1, [[runtime inboxSnapshotForRecipient:@"other-user"] count]);
  NSArray *outbox = [runtime outboxSnapshot];
  XCTAssertEqual((NSUInteger)4, [outbox count]);
  XCTAssertEqualObjects(@"other-user", [outbox lastObject][@"recipient"]);

  // Reloading a state file written under larger limits applies the current caps.
  ALNApplication *tighter = [self applicationWithStatePath:statePath
                                         extraModuleConfig:@{
                                           @"outbox" : @{ @"maxEntries" : @2 },
                                           @"inbox" : @{ @"maxEntriesPerRecipient" : @1 },
                                         }];
  [self registerModulesForApplication:tighter];
  XCTAssertEqual((NSUInteger)2, [[runtime outboxSnapshot] count]);
  NSArray *reloaded = [runtime inboxSnapshotForRecipient:@"capped-user"];
  XCTAssertEqual((NSUInteger)1, [reloaded count]);
  XCTAssertEqualObjects(@"Hello Reader 5.", [reloaded firstObject][@"body"]);

  ALNApplication *defaults = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"defaults.plist"]
                                          extraModuleConfig:@{ @"outbox" : @{ @"maxEntries" : @0 } }];
  [self registerModulesForApplication:defaults];
  XCTAssertEqualObjects(@1000, [runtime resolvedConfigSummary][@"maxOutboxEntries"]);
  XCTAssertEqualObjects(@200, [runtime resolvedConfigSummary][@"maxInboxEntriesPerRecipient"]);
}

- (void)testInboxPaginationReturnsRequestedSlice {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"notifications-state.plist"]];
  [self registerModulesForApplication:app];
  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
  [self sendInAppDigestsToRecipient:@"paged-user" count:5];

  NSDictionary *page = [runtime inboxSummaryForRecipient:@"paged-user" limit:2 offset:1];
  XCTAssertEqualObjects((@[ @"Hello Reader 1.", @"Hello Reader 2." ]), [page[@"entries"] valueForKey:@"body"]);
  XCTAssertEqualObjects(@5, page[@"totalCount"]);
  XCTAssertEqualObjects(@5, page[@"unreadCount"]);
  XCTAssertEqualObjects((@{ @"limit" : @2, @"offset" : @1, @"returned" : @2, @"total" : @5, @"hasMore" : @YES }),
                        page[@"pagination"]);

  NSDictionary *last = [runtime inboxSummaryForRecipient:@"paged-user" limit:2 offset:4];
  XCTAssertEqual((NSUInteger)1, [last[@"entries"] count]);
  XCTAssertEqualObjects(@NO, last[@"pagination"][@"hasMore"]);

  NSDictionary *past = [runtime inboxSummaryForRecipient:@"paged-user" limit:2 offset:50];
  XCTAssertEqual((NSUInteger)0, [past[@"entries"] count]);
  XCTAssertEqualObjects(@5, past[@"pagination"][@"offset"]);

  NSDictionary *all = [runtime inboxSummaryForRecipient:@"paged-user" limit:0 offset:0];
  XCTAssertEqual((NSUInteger)5, [all[@"entries"] count]);
  XCTAssertEqualObjects(@5, all[@"pagination"][@"limit"]);

  NSDictionary *clamped = [runtime inboxSummaryForRecipient:@"paged-user" limit:100000 offset:0];
  XCTAssertEqualObjects(@200, clamped[@"pagination"][@"limit"]);
}

- (void)testUnknownPreferenceIdentifiersAreRejected {
  ALNApplication *app = [self applicationWithStatePath:[[self temporaryDirectory] stringByAppendingPathComponent:@"notifications-state.plist"]];
  [self registerModulesForApplication:app];
  ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];

  NSError *error = nil;
  XCTAssertNotNil([runtime updateNotificationPreferences:@{ @"phase16b.digest" : @{ @"email" : @NO } }
                                            forRecipient:@"prefs-user"
                                                   error:&error]);
  XCTAssertNil(error);

  XCTAssertNil([runtime updateNotificationPreferences:@{ @"phase16b.unknown" : @{ @"email" : @NO } }
                                         forRecipient:@"prefs-user"
                                                error:&error]);
  XCTAssertEqual(ALNNotificationsModuleErrorValidationFailed, error.code);
  XCTAssertEqualObjects(@"phase16b.unknown", error.userInfo[@"notification"]);

  error = nil;
  XCTAssertNil([runtime updateNotificationPreferences:@{ @"phase16b.digest" : @{ @"carrier_pigeon" : @YES } }
                                         forRecipient:@"prefs-user"
                                                error:&error]);
  XCTAssertEqual(ALNNotificationsModuleErrorValidationFailed, error.code);
  XCTAssertEqualObjects(@"carrier_pigeon", error.userInfo[@"channel"]);

  XCTAssertEqualObjects((@{ @"phase16b.digest" : @{ @"email" : @NO } }),
                        [runtime notificationPreferencesForRecipient:@"prefs-user"]);
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

- (void)testNotificationStateTransactionsAcrossProcesses {
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
  NSString *sharedPath = environment[@"ARLEN_NOTIFICATIONS_SHARED_STATE_PATH"];
  if ([sharedPath length] > 0) {
    ALNApplication *app = [self applicationWithStatePath:sharedPath];
    [self registerModulesForApplication:app];
    NSString *readyPath = [sharedPath stringByAppendingFormat:@".ready.%d", getpid()];
    XCTAssertTrue([@"ready" writeToFile:readyPath atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    __block NSUInteger readyCount = 0;
    XCTAssertTrue(ALNTestWaitUntil(5.0, 0.05, ^BOOL {
      NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[sharedPath stringByDeletingLastPathComponent]
                                                                           error:NULL];
      readyCount = 0;
      for (NSString *name in names) {
        if ([name hasPrefix:[[sharedPath lastPathComponent] stringByAppendingString:@".ready."]]) readyCount++;
      }
      return readyCount >= 2U;
    }));
    XCTAssertEqual((NSUInteger)2, readyCount);
    NSString *recipient = [NSString stringWithFormat:@"worker-%d", getpid()];
    ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
    NSError *error = nil;
    NSDictionary *payload = @{ @"recipient" : recipient, @"email" : @"reader@example.test", @"name" : @"Reader" };
    NSDictionary *sent = [runtime testSendNotificationIdentifier:@"phase16b.digest"
                                                         payload:payload channels:@[ @"in_app" ] error:&error];
    XCTAssertNotNil(sent);
    XCTAssertNil(error);
    NSDictionary *preference = @{ @"phase16b.digest" : @{ @"email" : @NO } };
    NSDictionary *updated = [runtime updateNotificationPreferences:preference forRecipient:recipient error:&error];
    XCTAssertNotNil(updated);
    XCTAssertNil(error);
    return;
  }

  NSString *statePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"notifications-process-state.plist"];
  NSString *runner = [[[NSProcessInfo processInfo] arguments] firstObject];
  NSString *bundlePath = [[NSBundle bundleForClass:[self class]] bundlePath];
  NSMutableArray *children = [NSMutableArray array];
  for (NSUInteger index = 0; index < 2U; index++) {
    NSTask *child = [[NSTask alloc] init];
    child.launchPath = runner;
    child.arguments = @[ @"-XCTest", @"Phase16BTests/testNotificationStateTransactionsAcrossProcesses", bundlePath ];
    NSMutableDictionary *childEnvironment = [environment mutableCopy];
    childEnvironment[@"ARLEN_NOTIFICATIONS_SHARED_STATE_PATH"] = statePath;
    child.environment = childEnvironment;
    [child launch];
    [children addObject:child];
  }
  for (NSTask *child in children) {
    [child waitUntilExit];
    XCTAssertEqual(0, child.terminationStatus);
  }
  NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:statePath];
  XCTAssertEqual((NSUInteger)2, [(NSArray *)state[@"outboxEntries"] count]);
  XCTAssertEqual((NSUInteger)2, [(NSDictionary *)state[@"inboxByRecipient"] count]);
  XCTAssertEqual((NSUInteger)2, [(NSDictionary *)state[@"preferencesByRecipient"] count]);
  XCTAssertEqual((NSUInteger)2, [(NSArray *)state[@"recentFanoutEvents"] count]);
}

- (void)testNotificationFreshReadsAndSameRecipientMutationsAcrossProcesses {
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];
  NSString *sharedPath = environment[@"ARLEN_NOTIFICATIONS_SAME_RECIPIENT_PATH"];
  NSString *role = environment[@"ARLEN_NOTIFICATIONS_SAME_RECIPIENT_ROLE"];
  if ([sharedPath length] > 0) {
    [self registerModulesForApplication:[self applicationWithStatePath:sharedPath]];
    NSString *readyPath = [sharedPath stringByAppendingFormat:@".ready.%@", role];
    XCTAssertTrue([@"ready" writeToFile:readyPath atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    XCTAssertTrue(ALNTestWaitUntil(5.0, 0.05, ^BOOL {
      return [[NSFileManager defaultManager] fileExistsAtPath:[sharedPath stringByAppendingString:@".ready.first"]] &&
             [[NSFileManager defaultManager] fileExistsAtPath:[sharedPath stringByAppendingString:@".ready.second"]];
    }));
    ALNNotificationsModuleRuntime *runtime = [ALNNotificationsModuleRuntime sharedRuntime];
    NSError *error = nil;
    if ([role isEqualToString:@"first"]) {
      NSDictionary *payload = @{ @"recipient" : @"shared-recipient", @"email" : @"reader@example.test", @"name" : @"Reader" };
      XCTAssertNotNil([runtime testSendNotificationIdentifier:@"phase16b.digest"
                                                     payload:payload channels:@[ @"in_app" ] error:&error]);
      XCTAssertNil(error);
      NSDictionary *preference = @{ @"phase16b.digest" : @{ @"email" : @NO } };
      XCTAssertNotNil([runtime updateNotificationPreferences:preference forRecipient:@"shared-recipient" error:&error]);
      XCTAssertNil(error);
      XCTAssertTrue([@"done" writeToFile:[sharedPath stringByAppendingString:@".first"]
                               atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
      XCTAssertTrue([self waitForFileAtPath:[sharedPath stringByAppendingString:@".second"]]);
      XCTAssertEqualObjects(@YES, [runtime notificationPreferencesForRecipient:@"shared-recipient"][@"phase16b.digest"][@"email"]);
      XCTAssertEqualObjects(@0, [runtime inboxSummaryForRecipient:@"shared-recipient"][@"unreadCount"]);
      XCTAssertTrue([@"done" writeToFile:[sharedPath stringByAppendingString:@".third"]
                               atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
      XCTAssertTrue([self waitForFileAtPath:[sharedPath stringByAppendingString:@".fourth"]]);
      // A worker that held the old preference must not resurrect a cleared
      // preference when it next writes unrelated delivery state.
      NSDictionary *otherPayload = @{ @"recipient" : @"other-recipient", @"email" : @"reader@example.test", @"name" : @"Other" };
      XCTAssertNotNil([runtime testSendNotificationIdentifier:@"phase16b.digest"
                                                     payload:otherPayload channels:@[ @"in_app" ] error:&error]);
      XCTAssertEqual((NSUInteger)0, [[runtime notificationPreferencesForRecipient:@"shared-recipient"] count]);
    } else {
      XCTAssertTrue([self waitForFileAtPath:[sharedPath stringByAppendingString:@".first"]]);
      XCTAssertEqualObjects(@1, [runtime inboxSummaryForRecipient:@"shared-recipient"][@"unreadCount"]);
      XCTAssertEqualObjects(@NO, [runtime notificationPreferencesForRecipient:@"shared-recipient"][@"phase16b.digest"][@"email"]);
      NSDictionary *marked = [runtime markAllInboxEntriesReadForRecipient:@"shared-recipient" error:&error];
      XCTAssertNotNil(marked);
      XCTAssertEqualObjects(@1, marked[@"updatedCount"]);
      XCTAssertNil(error);
      NSDictionary *preference = @{ @"phase16b.digest" : @{ @"email" : @YES } };
      XCTAssertNotNil([runtime updateNotificationPreferences:preference forRecipient:@"shared-recipient" error:&error]);
      XCTAssertNil(error);
      XCTAssertTrue([@"done" writeToFile:[sharedPath stringByAppendingString:@".second"]
                               atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
      XCTAssertTrue([self waitForFileAtPath:[sharedPath stringByAppendingString:@".third"]]);
      XCTAssertNotNil([runtime updateNotificationPreferences:@{} forRecipient:@"shared-recipient" error:&error]);
      XCTAssertNil(error);
      XCTAssertTrue([@"done" writeToFile:[sharedPath stringByAppendingString:@".fourth"]
                               atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
    }
    return;
  }
  NSString *statePath = [[self temporaryDirectory] stringByAppendingPathComponent:@"notifications-same-recipient.plist"];
  NSString *runner = [[[NSProcessInfo processInfo] arguments] firstObject];
  NSString *bundlePath = [[NSBundle bundleForClass:[self class]] bundlePath];
  NSMutableArray *children = [NSMutableArray array];
  for (NSString *childRole in @[ @"first", @"second" ]) {
    NSTask *child = [[NSTask alloc] init];
    child.launchPath = runner;
    child.arguments = @[ @"-XCTest", @"Phase16BTests/testNotificationFreshReadsAndSameRecipientMutationsAcrossProcesses", bundlePath ];
    NSMutableDictionary *childEnvironment = [environment mutableCopy];
    childEnvironment[@"ARLEN_NOTIFICATIONS_SAME_RECIPIENT_PATH"] = statePath;
    childEnvironment[@"ARLEN_NOTIFICATIONS_SAME_RECIPIENT_ROLE"] = childRole;
    child.environment = childEnvironment;
    [child launch];
    [children addObject:child];
  }
  for (NSTask *child in children) {
    [child waitUntilExit];
    XCTAssertEqual(0, child.terminationStatus);
  }
  NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:statePath];
  NSArray *inbox = state[@"inboxByRecipient"][@"shared-recipient"];
  XCTAssertEqual((NSUInteger)1, [inbox count]);
  XCTAssertEqualObjects(@YES, inbox[0][@"read"]);
  XCTAssertEqual((NSUInteger)0, [(NSDictionary *)state[@"preferencesByRecipient"][@"shared-recipient"] count]);
}

@end
