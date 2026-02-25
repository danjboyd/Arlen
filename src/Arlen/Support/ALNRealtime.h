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

@interface ALNRealtimeHub : NSObject

+ (instancetype)sharedHub;

- (void)configureLimitsWithMaxTotalSubscribers:(NSUInteger)maxTotalSubscribers
                    maxSubscribersPerChannel:(NSUInteger)maxSubscribersPerChannel;
- (nullable ALNRealtimeSubscription *)subscribeChannel:(NSString *)channel
                                            subscriber:(id<ALNRealtimeSubscriber>)subscriber;
- (void)unsubscribe:(nullable ALNRealtimeSubscription *)subscription;
- (NSUInteger)publishMessage:(NSString *)message onChannel:(NSString *)channel;
- (NSUInteger)subscriberCountForChannel:(NSString *)channel;
- (NSDictionary *)metricsSnapshot;
- (void)reset;

@end

NS_ASSUME_NONNULL_END

#endif
