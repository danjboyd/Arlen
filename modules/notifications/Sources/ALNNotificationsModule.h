#ifndef ALN_NOTIFICATIONS_MODULE_H
#define ALN_NOTIFICATIONS_MODULE_H

#import <Foundation/Foundation.h>

#import "ALNJobsModule.h"
#import "ALNModuleSystem.h"
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
- (NSArray<NSString *> *)notificationsModuleDefaultChannels;

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
- (NSDictionary *)notificationPreferencesForRecipient:(NSString *)recipient;
- (nullable NSDictionary *)updateNotificationPreferences:(NSDictionary *)preferences
                                            forRecipient:(NSString *)recipient
                                                   error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)dashboardSummary;

@end

@interface ALNNotificationsModule : NSObject <ALNModule>
@end

NS_ASSUME_NONNULL_END

#endif
