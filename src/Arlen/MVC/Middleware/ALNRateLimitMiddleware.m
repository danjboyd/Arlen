#import "ALNRateLimitMiddleware.h"

#import <math.h>

#import "ALNContext.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

// Distinct clients tracked at once by default; see -evictEntriesForNewKeyAtTime:.
static const NSUInteger ALNRateLimitDefaultMaxEntries = 65536;

@interface ALNRateLimitMiddleware ()

@property(nonatomic, assign) NSUInteger maxRequests;
@property(nonatomic, assign) NSUInteger windowSeconds;
@property(nonatomic, assign) NSUInteger maxEntries;
@property(nonatomic, strong) NSMutableDictionary *entries;
@property(nonatomic, assign) NSUInteger seenRequests;
@property(nonatomic, strong) NSLock *entriesLock;

@end

@implementation ALNRateLimitMiddleware

- (instancetype)initWithMaxRequests:(NSUInteger)maxRequests
                      windowSeconds:(NSUInteger)windowSeconds {
  self = [super init];
  if (self) {
    _maxRequests = (maxRequests > 0) ? maxRequests : 120;
    _windowSeconds = (windowSeconds > 0) ? windowSeconds : 60;
    _maxEntries = ALNRateLimitDefaultMaxEntries;
    _entries = [[NSMutableDictionary alloc] init];
    _seenRequests = 0;
    // Created before the middleware is shared; libobjc2's first
    // @synchronized on an instance can race (gnustep/libobjc2#424).
    _entriesLock = [[NSLock alloc] init];
  }
  return self;
}

- (void)pruneStaleEntriesAtTime:(NSTimeInterval)now {
  if ([self.entries count] < 1024) {
    return;
  }
  NSMutableArray *stale = [NSMutableArray array];
  for (NSString *key in self.entries) {
    NSDictionary *entry = self.entries[key];
    NSTimeInterval start = [entry[@"start"] doubleValue];
    if ((now - start) > (NSTimeInterval)(self.windowSeconds * 2)) {
      [stale addObject:key];
    }
  }
  if ([stale count] > 0) {
    [self.entries removeObjectsForKeys:stale];
  }
}

// Holds the table at maxEntries however many distinct clients
// arrive within one window: drop expired windows first, then the oldest
// eighth of what is left.
- (void)evictEntriesForNewKeyAtTime:(NSTimeInterval)now {
  if ([self.entries count] < self.maxEntries) {
    return;
  }
  NSMutableArray *expired = [NSMutableArray array];
  for (NSString *key in self.entries) {
    if ((now - [self.entries[key][@"start"] doubleValue]) >= (NSTimeInterval)self.windowSeconds) {
      [expired addObject:key];
    }
  }
  [self.entries removeObjectsForKeys:expired];
  if ([self.entries count] < self.maxEntries) {
    return;
  }
  NSArray *byStart = [self.entries keysSortedByValueUsingComparator:^NSComparisonResult(id left, id right) {
    return [left[@"start"] compare:right[@"start"]];
  }];
  NSUInteger evict = MAX((NSUInteger)1, [byStart count] / 8);
  [self.entries removeObjectsForKeys:[byStart subarrayWithRange:NSMakeRange(0, evict)]];
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

  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSUInteger count = 0;
  NSTimeInterval start = now;
  BOOL limited = NO;
  NSUInteger remaining = 0;
  NSUInteger retryAfterSeconds = self.windowSeconds;

  [self.entriesLock lock];
  @try {
    NSMutableDictionary *entry = [self.entries[key] mutableCopy];
    if (entry == nil) {
      [self evictEntriesForNewKeyAtTime:now];
      entry = [NSMutableDictionary dictionaryWithDictionary:@{
        @"start" : @(now),
        @"count" : @(0),
      }];
    }

    start = [entry[@"start"] doubleValue];
    count = [entry[@"count"] unsignedIntegerValue];

    if ((now - start) >= (NSTimeInterval)self.windowSeconds) {
      start = now;
      count = 0;
    }

    count += 1;
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

    entry[@"start"] = @(start);
    entry[@"count"] = @(count);
    self.entries[key] = entry;

    self.seenRequests += 1;
    if ((self.seenRequests % 128) == 0) {
      [self pruneStaleEntriesAtTime:now];
    }
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
