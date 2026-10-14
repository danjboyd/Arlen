#ifndef ALN_NOTIFICATIONS_WEB_PUSH_H
#define ALN_NOTIFICATIONS_WEB_PUSH_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Sends one encrypted push request. Returns @{ @"status" : NSNumber, @"headers" :
// NSDictionary (lowercased names) }, or nil with an error when the request never
// produced an HTTP response. Apps and tests may supply their own transport through
// notificationsModule.webPush.transportClass.
@protocol ALNWebPushTransport <NSObject>
- (nullable NSDictionary *)webPushSendRequest:(NSURLRequest *)request error:(NSError *_Nullable *_Nullable)error;
@end

// libcurl-backed transport: no redirects, 15 second timeout.
@interface ALNWebPushHTTPTransport : NSObject <ALNWebPushTransport>
@end

// Push subscriptions per recipient. With a path, every operation re-reads and
// rewrites the file under an advisory lock, so an app server and a separate
// `arlen jobs worker` process on the same host share one view. Without a path the
// store lives in memory (the test environment default).
@interface ALNNotificationsWebPushSubscriptionStore : NSObject

@property(nonatomic, copy, readonly) NSString *path;

- (instancetype)initWithPath:(nullable NSString *)path;

/// Adds or refreshes a subscription, keyed by endpoint. An endpoint already held by
/// another recipient moves to this one. Oldest subscriptions beyond the limit are dropped.
- (nullable NSDictionary *)saveSubscriptionWithEndpoint:(NSString *)endpoint
                                                 p256dh:(NSString *)p256dh
                                                   auth:(NSString *)auth
                                              userAgent:(nullable NSString *)userAgent
                                           forRecipient:(NSString *)recipient
                                        maxPerRecipient:(NSUInteger)maxPerRecipient
                                                  error:(NSError *_Nullable *_Nullable)error;
- (BOOL)removeSubscriptionWithEndpoint:(NSString *)endpoint
                          forRecipient:(NSString *)recipient
                                 error:(NSError *_Nullable *_Nullable)error;
- (BOOL)removeSubscriptionID:(NSString *)subscriptionID
                forRecipient:(NSString *)recipient
                       error:(NSError *_Nullable *_Nullable)error;
- (NSArray<NSDictionary *> *)subscriptionsForRecipient:(NSString *)recipient includeInactive:(BOOL)includeInactive;
- (nullable NSDictionary *)subscriptionWithID:(NSString *)subscriptionID;
- (void)recordSuccessForSubscriptionID:(NSString *)subscriptionID;
- (void)deactivateSubscriptionID:(NSString *)subscriptionID reason:(NSString *)reason;
- (NSDictionary *)summary;

@end

/// Seconds from a Retry-After value (delta-seconds or an HTTP-date), or -1.
FOUNDATION_EXPORT NSTimeInterval ALNWebPushRetryAfterSeconds(NSString *_Nullable value, NSDate *now);

/// The service worker and page helper the module serves. The service worker is
/// prefixed with the app's fallback title, body and URL for content-free nudges.
FOUNDATION_EXPORT NSString *ALNWebPushServiceWorkerScript(NSDictionary *defaults);
FOUNDATION_EXPORT NSString *ALNWebPushClientScript(void);

NS_ASSUME_NONNULL_END

#endif
