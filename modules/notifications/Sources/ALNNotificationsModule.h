#ifndef ALN_NOTIFICATIONS_MODULE_H
#define ALN_NOTIFICATIONS_MODULE_H

#import <Foundation/Foundation.h>

#import "ALNJobsModule.h"
#import "ALNModuleSystem.h"
#import "ALNNotificationsWebPush.h"
#import "ALNServices.h"

@class ALNApplication;
@class ALNNotificationsModuleRuntime;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNNotificationsModuleErrorDomain;

typedef NS_ENUM(NSInteger, ALNNotificationsModuleErrorCode) {
  ALNNotificationsModuleErrorInvalidConfiguration = 1,
  ALNNotificationsModuleErrorValidationFailed = 2,
  ALNNotificationsModuleErrorNotFound = 3,
  ALNNotificationsModuleErrorDeliveryFailed = 4,
  ALNNotificationsModuleErrorPolicyRejected = 5,
};

@protocol ALNNotificationDefinition <NSObject>

- (NSString *)notificationsModuleIdentifier;
- (NSDictionary *)notificationsModuleMetadata;
- (BOOL)notificationsModuleValidatePayload:(NSDictionary *)payload
                                     error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                              runtime:
                                                                  (ALNNotificationsModuleRuntime *)runtime
                                                                error:
                                                                    (NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)notificationsModuleInAppEntryForPayload:(NSDictionary *)payload
                                                           runtime:
                                                               (ALNNotificationsModuleRuntime *)runtime
                                                             error:
                                                                 (NSError *_Nullable *_Nullable)error;

@optional
- (nullable NSDictionary *)notificationsModuleWebhookRequestForPayload:(NSDictionary *)payload
                                                               runtime:
                                                                   (ALNNotificationsModuleRuntime *)runtime
                                                                 error:
                                                                     (NSError *_Nullable *_Nullable)error;
- (NSArray<NSString *> *)notificationsModuleDefaultChannels;
// When a signed-in user queues this notification for themselves over HTTP
// (below the admin role at AAL2), the module replaces every channel's target
// with the caller's own: email goes only to their account address, in-app and
// web push only to their subject. A webhook target cannot be replaced, so the
// webhook channel is left out of those notifications unless this returns YES,
// meaning the webhook URL never depends on the payload.
- (BOOL)notificationsModuleAllowsWebhookForSelfQueuedNotifications;
// The `webpush` channel. Keys: title (required unless nudge), body, url, tag,
// topic (<= 32 base64url chars; collapses repeats), ttl (seconds), urgency
// (very-low|low|normal|high), nudge (BOOL: send no content, the service worker
// shows the configured fallback text), and recipient or recipients.
- (nullable NSDictionary *)notificationsModuleWebPushMessageForPayload:(NSDictionary *)payload
                                                               runtime:
                                                                   (ALNNotificationsModuleRuntime *)runtime
                                                                 error:
                                                                     (NSError *_Nullable *_Nullable)error;

@end

@protocol ALNNotificationProvider <NSObject>

- (nullable NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError *_Nullable *_Nullable)error;

@end

@protocol ALNNotificationPreferenceHook <NSObject>

@optional
- (nullable NSNumber *)notificationsModuleChannelEnabledForRecipient:(NSString *)recipient
                                              notificationIdentifier:(NSString *)identifier
                                                             channel:(NSString *)channel
                                                      defaultEnabled:(BOOL)defaultEnabled
                                                             runtime:(ALNNotificationsModuleRuntime *)runtime;

@end

@interface ALNNotificationsModuleRuntime : NSObject

@property(nonatomic, copy, readonly) NSString *prefix;
@property(nonatomic, copy, readonly) NSString *apiPrefix;
@property(nonatomic, strong, readonly, nullable) ALNApplication *application;
@property(nonatomic, strong, readonly, nullable) id<ALNMailAdapter> mailAdapter;

+ (instancetype)sharedRuntime;

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)resolvedConfigSummary;
- (NSArray<NSDictionary *> *)registeredNotifications;
- (BOOL)registerSystemNotificationDefinition:(id<ALNNotificationDefinition>)definition
                                       error:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)queueNotificationIdentifier:(NSString *)identifier
                                           payload:(nullable NSDictionary *)payload
                                          channels:(nullable NSArray<NSString *> *)channels
                                             error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)processQueuedNotificationPayload:(NSDictionary *)jobPayload
                                                      error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)previewNotificationIdentifier:(NSString *)identifier
                                                 payload:(nullable NSDictionary *)payload
                                                channels:(nullable NSArray<NSString *> *)channels
                                                   error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)testSendNotificationIdentifier:(NSString *)identifier
                                                  payload:(nullable NSDictionary *)payload
                                                 channels:(nullable NSArray<NSString *> *)channels
                                                    error:(NSError *_Nullable *_Nullable)error;
- (NSArray<NSDictionary *> *)outboxSnapshot;
- (nullable NSDictionary *)outboxEntryForIdentifier:(NSString *)entryID;
- (NSArray<NSDictionary *> *)inboxSnapshotForRecipient:(NSString *)recipient;
- (NSDictionary *)inboxSummaryForRecipient:(NSString *)recipient;
// Paginated inbox listing. `limit` 0 returns every stored entry (at most
// `inbox.maxEntriesPerRecipient`); larger limits are clamped to 200. The
// result adds `pagination` = { limit, offset, returned, total, hasMore };
// `totalCount` and `unreadCount` still describe the whole inbox.
- (NSDictionary *)inboxSummaryForRecipient:(NSString *)recipient
                                     limit:(NSUInteger)limit
                                    offset:(NSUInteger)offset;
- (nullable NSDictionary *)markInboxEntryID:(NSString *)entryID
                                       read:(BOOL)read
                               forRecipient:(NSString *)recipient
                                      error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)markAllInboxEntriesReadForRecipient:(NSString *)recipient
                                                         error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)notificationPreferencesForRecipient:(NSString *)recipient;
- (nullable NSDictionary *)updateNotificationPreferences:(NSDictionary *)preferences
                                            forRecipient:(NSString *)recipient
                                                   error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)dashboardSummary;

// Web Push (notificationsModule.webPush). Subscriptions belong to a recipient (the
// auth subject); endpoints must be https on an allowed push-service host.
@property(nonatomic, strong, nullable) id<ALNWebPushTransport> webPushTransport;
- (NSDictionary *)webPushClientConfiguration;
- (nullable NSDictionary *)saveWebPushSubscription:(NSDictionary *)subscription
                                         userAgent:(nullable NSString *)userAgent
                                      forRecipient:(NSString *)recipient
                                             error:(NSError *_Nullable *_Nullable)error;
- (BOOL)removeWebPushSubscriptionWithEndpoint:(NSString *)endpoint
                                 forRecipient:(NSString *)recipient
                                        error:(NSError *_Nullable *_Nullable)error;
- (NSArray<NSDictionary *> *)webPushSubscriptionsForRecipient:(NSString *)recipient;
/// Sends a fixed test message to the recipient's active subscriptions, bypassing
/// notification definitions, preferences and the job queue.
- (nullable NSDictionary *)sendWebPushTestToRecipient:(NSString *)recipient
                                                error:(NSError *_Nullable *_Nullable)error;

@end

@interface ALNNotificationsModule : NSObject <ALNModule>
@end

NS_ASSUME_NONNULL_END

#endif
