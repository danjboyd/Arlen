#ifndef ALN_SESSION_MIDDLEWARE_H
#define ALN_SESSION_MIDDLEWARE_H

#import <Foundation/Foundation.h>

#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNSessionMiddleware : NSObject <ALNMiddleware>

- (instancetype)initWithSecret:(NSString *)secret
                    cookieName:(nullable NSString *)cookieName
                 maxAgeSeconds:(NSUInteger)maxAgeSeconds
                        secure:(BOOL)secure
                      sameSite:(nullable NSString *)sameSite;

@end

NS_ASSUME_NONNULL_END

#endif
