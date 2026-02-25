#import "ALNRealtime.h"

static NSString *ALNNormalizeChannelName(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  NSString *trimmed =
      [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return [trimmed lowercaseString];
}

@interface ALNRealtimeSubscription ()

@property(nonatomic, copy, readwrite) NSString *channel;
@property(nonatomic, strong, readwrite) id<ALNRealtimeSubscriber> subscriber;

@end

@implementation ALNRealtimeSubscription

- (instancetype)initWithChannel:(NSString *)channel
                     subscriber:(id<ALNRealtimeSubscriber>)subscriber {
  self = [super init];
  if (self) {
    _channel = [channel copy] ?: @"";
    _subscriber = subscriber;
  }
  return self;
}

@end

@interface ALNRealtimeHub ()

@property(nonatomic, strong) NSMutableDictionary *subscriptionsByChannel;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, assign) NSUInteger maxTotalSubscribers;
@property(nonatomic, assign) NSUInteger maxSubscribersPerChannel;
@property(nonatomic, assign) NSUInteger activeSubscriberCount;
@property(nonatomic, assign) NSUInteger peakSubscriberCount;
@property(nonatomic, assign) NSUInteger totalSubscriptions;
@property(nonatomic, assign) NSUInteger totalUnsubscriptions;
@property(nonatomic, assign) NSUInteger rejectedSubscriptions;

@end

@implementation ALNRealtimeHub

+ (instancetype)sharedHub {
  static ALNRealtimeHub *shared = nil;
  @synchronized(self) {
    if (shared == nil) {
      shared = [[ALNRealtimeHub alloc] init];
    }
  }
  return shared;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _subscriptionsByChannel = [NSMutableDictionary dictionary];
    _lock = [[NSLock alloc] init];
    _maxTotalSubscribers = 0;
    _maxSubscribersPerChannel = 0;
    _activeSubscriberCount = 0;
    _peakSubscriberCount = 0;
    _totalSubscriptions = 0;
    _totalUnsubscriptions = 0;
    _rejectedSubscriptions = 0;
  }
  return self;
}

- (void)configureLimitsWithMaxTotalSubscribers:(NSUInteger)maxTotalSubscribers
                    maxSubscribersPerChannel:(NSUInteger)maxSubscribersPerChannel {
  [self.lock lock];
  self.maxTotalSubscribers = maxTotalSubscribers;
  self.maxSubscribersPerChannel = maxSubscribersPerChannel;
  [self.lock unlock];
}

- (ALNRealtimeSubscription *)subscribeChannel:(NSString *)channel
                                   subscriber:(id<ALNRealtimeSubscriber>)subscriber {
  return [self subscribeChannel:channel subscriber:subscriber rejectionReason:NULL];
}

- (ALNRealtimeSubscription *)subscribeChannel:(NSString *)channel
                                   subscriber:(id<ALNRealtimeSubscriber>)subscriber
                             rejectionReason:(NSString **)rejectionReason {
  if (rejectionReason != NULL) {
    *rejectionReason = nil;
  }
  NSString *normalized = ALNNormalizeChannelName(channel);
  if ([normalized length] == 0 || subscriber == nil) {
    return nil;
  }

  ALNRealtimeSubscription *subscription =
      [[ALNRealtimeSubscription alloc] initWithChannel:normalized subscriber:subscriber];

  [self.lock lock];
  NSMutableArray *subscriptions = self.subscriptionsByChannel[normalized];
  NSUInteger channelCount = [subscriptions count];
  if (self.maxTotalSubscribers > 0 &&
      self.activeSubscriberCount >= self.maxTotalSubscribers) {
    self.rejectedSubscriptions += 1;
    if (rejectionReason != NULL) {
      *rejectionReason = @"max_total_subscribers";
    }
    [self.lock unlock];
    return nil;
  }
  if (self.maxSubscribersPerChannel > 0 &&
      channelCount >= self.maxSubscribersPerChannel) {
    self.rejectedSubscriptions += 1;
    if (rejectionReason != NULL) {
      *rejectionReason = @"max_channel_subscribers";
    }
    [self.lock unlock];
    return nil;
  }
  if (subscriptions == nil) {
    subscriptions = [NSMutableArray array];
    self.subscriptionsByChannel[normalized] = subscriptions;
  }
  [subscriptions addObject:subscription];
  self.activeSubscriberCount += 1;
  self.totalSubscriptions += 1;
  if (self.activeSubscriberCount > self.peakSubscriberCount) {
    self.peakSubscriberCount = self.activeSubscriberCount;
  }
  [self.lock unlock];

  return subscription;
}

- (void)unsubscribe:(ALNRealtimeSubscription *)subscription {
  if (subscription == nil) {
    return;
  }

  NSString *channel = ALNNormalizeChannelName(subscription.channel);
  if ([channel length] == 0) {
    return;
  }

  [self.lock lock];
  NSMutableArray *subscriptions = self.subscriptionsByChannel[channel];
  if (subscriptions != nil) {
    NSUInteger beforeCount = [subscriptions count];
    [subscriptions removeObjectIdenticalTo:subscription];
    if ([subscriptions count] < beforeCount) {
      if (self.activeSubscriberCount > 0) {
        self.activeSubscriberCount -= 1;
      }
      self.totalUnsubscriptions += 1;
    }
    if ([subscriptions count] == 0) {
      [self.subscriptionsByChannel removeObjectForKey:channel];
    }
  }
  [self.lock unlock];
}

- (NSUInteger)publishMessage:(NSString *)message onChannel:(NSString *)channel {
  NSString *normalizedChannel = ALNNormalizeChannelName(channel);
  NSString *payload = [message isKindOfClass:[NSString class]] ? message : @"";
  if ([normalizedChannel length] == 0) {
    return 0;
  }

  NSArray *subscriptions = nil;
  [self.lock lock];
  subscriptions = [NSArray arrayWithArray:self.subscriptionsByChannel[normalizedChannel] ?: @[]];
  [self.lock unlock];

  NSUInteger delivered = 0;
  for (id candidate in subscriptions) {
    if (![candidate isKindOfClass:[ALNRealtimeSubscription class]]) {
      continue;
    }
    ALNRealtimeSubscription *subscription = (ALNRealtimeSubscription *)candidate;
    id<ALNRealtimeSubscriber> subscriber = subscription.subscriber;
    if (subscriber == nil) {
      continue;
    }
    @try {
      [subscriber receiveRealtimeMessage:payload onChannel:normalizedChannel];
      delivered += 1;
    } @catch (NSException *exception) {
      (void)exception;
      // Subscriber exceptions are isolated so one bad consumer does not break fanout.
    }
  }
  return delivered;
}

- (NSUInteger)subscriberCountForChannel:(NSString *)channel {
  NSString *normalized = ALNNormalizeChannelName(channel);
  if ([normalized length] == 0) {
    return 0;
  }

  [self.lock lock];
  NSUInteger count = [self.subscriptionsByChannel[normalized] count];
  [self.lock unlock];
  return count;
}

- (NSDictionary *)metricsSnapshot {
  [self.lock lock];
  NSDictionary *snapshot = @{
    @"activeSubscribers" : @(self.activeSubscriberCount),
    @"activeChannels" : @([self.subscriptionsByChannel count]),
    @"peakSubscribers" : @(self.peakSubscriberCount),
    @"totalSubscriptions" : @(self.totalSubscriptions),
    @"totalUnsubscriptions" : @(self.totalUnsubscriptions),
    @"rejectedSubscriptions" : @(self.rejectedSubscriptions),
    @"maxTotalSubscribers" : @(self.maxTotalSubscribers),
    @"maxSubscribersPerChannel" : @(self.maxSubscribersPerChannel),
  };
  [self.lock unlock];
  return snapshot;
}

- (void)reset {
  [self.lock lock];
  [self.subscriptionsByChannel removeAllObjects];
  self.maxTotalSubscribers = 0;
  self.maxSubscribersPerChannel = 0;
  self.activeSubscriberCount = 0;
  self.peakSubscriberCount = 0;
  self.totalSubscriptions = 0;
  self.totalUnsubscriptions = 0;
  self.rejectedSubscriptions = 0;
  [self.lock unlock];
}

@end
