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
  }
  return self;
}

- (ALNRealtimeSubscription *)subscribeChannel:(NSString *)channel
                                   subscriber:(id<ALNRealtimeSubscriber>)subscriber {
  NSString *normalized = ALNNormalizeChannelName(channel);
  if ([normalized length] == 0 || subscriber == nil) {
    return nil;
  }

  ALNRealtimeSubscription *subscription =
      [[ALNRealtimeSubscription alloc] initWithChannel:normalized subscriber:subscriber];

  [self.lock lock];
  NSMutableArray *subscriptions = self.subscriptionsByChannel[normalized];
  if (subscriptions == nil) {
    subscriptions = [NSMutableArray array];
    self.subscriptionsByChannel[normalized] = subscriptions;
  }
  [subscriptions addObject:subscription];
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
    [subscriptions removeObjectIdenticalTo:subscription];
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

- (void)reset {
  [self.lock lock];
  [self.subscriptionsByChannel removeAllObjects];
  [self.lock unlock];
}

@end
