#ifndef ALN_SECURITY_HEADERS_MIDDLEWARE_H
#define ALN_SECURITY_HEADERS_MIDDLEWARE_H

#import <Foundation/Foundation.h>

#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNSecurityHeadersMiddleware : NSObject <ALNMiddleware>

- (instancetype)initWithContentSecurityPolicy:(nullable NSString *)contentSecurityPolicy;
// The headers this middleware adds when missing: the fixed defaults plus the
// configured Content-Security-Policy. Also applied to responses produced outside
// the middleware chain (static mounts, route-miss 404s, built-in endpoints).
- (NSDictionary<NSString *, NSString *> *)responseHeaders;

@end

NS_ASSUME_NONNULL_END

#endif
