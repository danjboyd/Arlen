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

@class ALNRealtimeHub;

// Cross-process fanout for the hub (GitHub issue 48). Without one, publishes
// reach only subscribers in the same process, which under propane's prefork
// workers means only the worker that handled the publishing request.
@protocol ALNRealtimeFanout <NSObject>
// Called after local delivery for every publishMessage:onChannel:. Implementations
// forward the message to other processes, which call deliverRemoteMessage:onChannel:.
- (void)hub:(ALNRealtimeHub *)hub didPublishMessage:(NSString *)message onChannel:(NSString *)channel;
- (void)stop;
@end

@interface ALNRealtimeHub : NSObject

// Set once per process at startup; replacing it stops the previous fanout.
@property(nonatomic, strong, nullable) id<ALNRealtimeFanout> fanout;

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
// Delivers to this process's subscribers only; fanouts call this for messages
// published elsewhere, so it never re-broadcasts.
- (NSUInteger)deliverRemoteMessage:(NSString *)message onChannel:(NSString *)channel;
- (NSUInteger)subscriberCountForChannel:(NSString *)channel;
- (NSDictionary *)metricsSnapshot;
- (void)reset;

@end

NS_ASSUME_NONNULL_END

#endif
