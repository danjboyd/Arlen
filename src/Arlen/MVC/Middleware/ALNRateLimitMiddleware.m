#import "ALNRateLimitMiddleware.h"

#import <math.h>

#import "ALNClientAddressInternal.h"
#import "ALNContext.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

// Distinct clients tracked at once by default.
static const NSUInteger ALNRateLimitDefaultMaxEntries = 65536;

// One client's current window.
@interface ALNRateLimitEntry : NSObject
@property(nonatomic, assign) NSTimeInterval start;
@property(nonatomic, assign) NSUInteger count;
@end

@implementation ALNRateLimitEntry
@end

// A window as it was queued. The queue is in window-start order because a
// window always starts "now"; a record is stale once its client has started a
// newer window (record.start != entry.start).
@interface ALNRateLimitQueueRecord : NSObject
@property(nonatomic, copy) NSString *key;
@property(nonatomic, assign) NSTimeInterval start;
@end

@implementation ALNRateLimitQueueRecord
@end

@interface ALNRateLimitMiddleware ()

@property(nonatomic, assign) NSUInteger maxRequests;
@property(nonatomic, assign) NSUInteger windowSeconds;
@property(nonatomic, assign) NSUInteger ipv6PrefixLength;
@property(nonatomic, assign) NSUInteger maxEntries;
@property(nonatomic, strong) NSMutableDictionary *entries;
@property(nonatomic, strong) NSMutableArray *queue;
@property(nonatomic, assign) NSUInteger queueHead;
@property(nonatomic, strong) NSLock *entriesLock;

@end

@implementation ALNRateLimitMiddleware

- (instancetype)initWithMaxRequests:(NSUInteger)maxRequests
                      windowSeconds:(NSUInteger)windowSeconds {
  return [self initWithMaxRequests:maxRequests windowSeconds:windowSeconds ipv6PrefixLength:64];
}

- (instancetype)initWithMaxRequests:(NSUInteger)maxRequests
                      windowSeconds:(NSUInteger)windowSeconds
                   ipv6PrefixLength:(NSUInteger)ipv6PrefixLength {
  self = [super init];
  if (self) {
    _maxRequests = (maxRequests > 0) ? maxRequests : 120;
    _windowSeconds = (windowSeconds > 0) ? windowSeconds : 60;
    _ipv6PrefixLength = (ipv6PrefixLength > 0 && ipv6PrefixLength <= 128) ? ipv6PrefixLength : 64;
    _maxEntries = ALNRateLimitDefaultMaxEntries;
    _entries = [[NSMutableDictionary alloc] init];
    _queue = [[NSMutableArray alloc] init];
    _queueHead = 0;
    // Created before the middleware is shared; libobjc2's first
    // @synchronized on an instance can race (gnustep/libobjc2#424).
    _entriesLock = [[NSLock alloc] init];
  }
  return self;
}

- (void)enqueueKey:(NSString *)key start:(NSTimeInterval)start {
  ALNRateLimitQueueRecord *record = [[ALNRateLimitQueueRecord alloc] init];
  record.key = key;
  record.start = start;
  [self.queue addObject:record];
}

// Removes the oldest queued window, and its client if that window is still
// the client's current one.
- (void)dequeueOldest {
  ALNRateLimitQueueRecord *record = self.queue[self.queueHead];
  self.queue[self.queueHead] = [NSNull null];
  self.queueHead += 1;
  ALNRateLimitEntry *entry = self.entries[record.key];
  if (entry != nil && entry.start == record.start) {
    [self.entries removeObjectForKey:record.key];
  }
  // Drop the consumed prefix once it is at least half the array, so each
  // dequeue costs O(1) amortized.
  if (self.queueHead >= 1024 && self.queueHead * 2 >= [self.queue count]) {
    [self.queue removeObjectsInRange:NSMakeRange(0, self.queueHead)];
    self.queueHead = 0;
  }
}

// Expired windows are at the head of the queue, and the oldest live windows
// follow them. Every request drops the expired head, and a new client evicts
// the oldest until the table is under maxEntries. Both cost O(1) amortized:
// each queued window is dequeued once.
- (void)dropExpiredAtTime:(NSTimeInterval)now {
  while (self.queueHead < [self.queue count]) {
    ALNRateLimitQueueRecord *record = self.queue[self.queueHead];
    if ((now - record.start) < (NSTimeInterval)self.windowSeconds) {
      break;
    }
    [self dequeueOldest];
  }
}

- (void)makeRoomForNewKey {
  while ([self.entries count] >= self.maxEntries && self.queueHead < [self.queue count]) {
    [self dequeueOldest];
  }
}

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSString *key = context.request.effectiveRemoteAddress;
  if ([key length] == 0) {
    key = context.request.remoteAddress;
  }
  if ([key length] == 0) {
    key = @"unknown";
  }
  // Canonical spelling; IPv6 clients count per network prefix.
  key = ALNClientAddressRateLimitKey(key, self.ipv6PrefixLength) ?: key;

  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSUInteger count = 0;
  NSTimeInterval start = now;
  BOOL limited = NO;
  NSUInteger remaining = 0;
  NSUInteger retryAfterSeconds = self.windowSeconds;

  [self.entriesLock lock];
  @try {
    [self dropExpiredAtTime:now];
    ALNRateLimitEntry *entry = self.entries[key];
    if (entry == nil) {
      [self makeRoomForNewKey];
      entry = [[ALNRateLimitEntry alloc] init];
      entry.start = now;
      entry.count = 0;
      self.entries[key] = entry;
      [self enqueueKey:key start:now];
    } else if ((now - entry.start) >= (NSTimeInterval)self.windowSeconds) {
      // An expired window still in the table: after the clock stepped back,
      // the queue can be out of order and hold it behind a newer one. Its
      // old record goes stale.
      entry.start = now;
      entry.count = 0;
      [self enqueueKey:key start:now];
    }

    start = entry.start;
    entry.count += 1;
    count = entry.count;
    limited = (count > self.maxRequests);
    if (count >= self.maxRequests) {
      remaining = 0;
    } else {
      remaining = self.maxRequests - count;
    }

    NSTimeInterval elapsed = now - start;
    NSTimeInterval retryAfter = (NSTimeInterval)self.windowSeconds - elapsed;
    if (retryAfter < 1.0) {
      retryAfter = 1.0;
    }
    retryAfterSeconds = (NSUInteger)ceil(retryAfter);
  } @finally {
    [self.entriesLock unlock];
  }

  [context.response setHeader:@"X-RateLimit-Limit"
                        value:[NSString stringWithFormat:@"%lu", (unsigned long)self.maxRequests]];
  [context.response setHeader:@"X-RateLimit-Remaining"
                        value:[NSString stringWithFormat:@"%lu", (unsigned long)remaining]];

  if (!limited) {
    return YES;
  }

  context.response.statusCode = 429;
  [context.response setHeader:@"Retry-After"
                        value:[NSString stringWithFormat:@"%lu", (unsigned long)retryAfterSeconds]];
  [context.response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  [context.response setTextBody:@"rate limit exceeded\n"];
  context.response.committed = YES;
  return NO;
}

@end
