#ifndef ALN_REALTIME_H
#define ALN_REALTIME_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ALNRealtimeSubscriber <NSObject>

- (void)receiveRealtimeMessage:(NSString *)message onChannel:(NSString *)channel;

@end

@interface ALNRealtimeSubscription : NSObject

@property(nonatomic, copy, readonly) NSString *channel;
@property(nonatomic, strong, readonly) id<ALNRealtimeSubscriber> subscriber;

- (instancetype)initWithChannel:(NSString *)channel
                     subscriber:(id<ALNRealtimeSubscriber>)subscriber;

@end

/**
 * In-process publish/subscribe fanout for realtime channels.
 *
 * WARNING: fanout is process-local and has no adapter seam. Under the prefork
 * worker model (see docs/DEPLOYMENT.md), a message published on one worker is
 * never delivered to a subscriber whose connection is held by another worker.
 * The failure is silent: no error is returned, nothing is logged, and a
 * single-worker development environment behaves correctly.
 *
 * Delivery is at-most-once even within a single process: a message published
 * to a channel with no current subscriber is dropped, and nothing is retained
 * or replayed for a subscriber that reconnects.
 *
 * Apps that must be correct under more than one worker should run a single
 * worker, use a polling live region (docs/LIVE_UI.md section 7.1), or build on
 * the durable event-stream seam (docs/EVENT_STREAMS.md), which supports a
 * broker adapter.
 *
 * Note that configureLimitsWithMaxTotalSubscribers:maxSubscribersPerChannel:
 * and metricsSnapshot are per-process, so a configured limit bounds one
 * worker's subscribers rather than the deployment's.
 */
@interface ALNRealtimeHub : NSObject

+ (instancetype)sharedHub;

- (void)configureLimitsWithMaxTotalSubscribers:(NSUInteger)maxTotalSubscribers
                    maxSubscribersPerChannel:(NSUInteger)maxSubscribersPerChannel;
- (nullable ALNRealtimeSubscription *)subscribeChannel:(NSString *)channel
                                            subscriber:(id<ALNRealtimeSubscriber>)subscriber;
- (nullable ALNRealtimeSubscription *)
    subscribeChannel:(NSString *)channel
          subscriber:(id<ALNRealtimeSubscriber>)subscriber
    rejectionReason:(NSString * _Nullable * _Nullable)rejectionReason;
- (void)unsubscribe:(nullable ALNRealtimeSubscription *)subscription;
- (NSUInteger)publishMessage:(NSString *)message onChannel:(NSString *)channel;
- (NSUInteger)subscriberCountForChannel:(NSString *)channel;
- (NSDictionary *)metricsSnapshot;
- (void)reset;

@end

NS_ASSUME_NONNULL_END

#endif
