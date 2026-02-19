#ifndef ALN_RATE_LIMIT_MIDDLEWARE_H
#define ALN_RATE_LIMIT_MIDDLEWARE_H

#import <Foundation/Foundation.h>

#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNRateLimitMiddleware : NSObject <ALNMiddleware>

- (instancetype)initWithMaxRequests:(NSUInteger)maxRequests
                      windowSeconds:(NSUInteger)windowSeconds;

@end

NS_ASSUME_NONNULL_END

#endif
