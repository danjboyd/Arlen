#ifndef ALN_RATE_LIMIT_MIDDLEWARE_H
#define ALN_RATE_LIMIT_MIDDLEWARE_H

#import <Foundation/Foundation.h>

#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNRateLimitMiddleware : NSObject <ALNMiddleware>

// Counts IPv6 clients per /64.
- (instancetype)initWithMaxRequests:(NSUInteger)maxRequests
                      windowSeconds:(NSUInteger)windowSeconds;

// `ipv6PrefixLength` (1-128; other values mean 64) is the IPv6 network a
// client is counted as, since one IPv6 client usually holds a whole /64 and
// could otherwise use a new address for every request. IPv4 clients are
// counted per address.
- (instancetype)initWithMaxRequests:(NSUInteger)maxRequests
                      windowSeconds:(NSUInteger)windowSeconds
                   ipv6PrefixLength:(NSUInteger)ipv6PrefixLength;

@end

NS_ASSUME_NONNULL_END

#endif
