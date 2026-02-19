#ifndef ALN_SECURITY_HEADERS_MIDDLEWARE_H
#define ALN_SECURITY_HEADERS_MIDDLEWARE_H

#import <Foundation/Foundation.h>

#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNSecurityHeadersMiddleware : NSObject <ALNMiddleware>

- (instancetype)initWithContentSecurityPolicy:(nullable NSString *)contentSecurityPolicy;

@end

NS_ASSUME_NONNULL_END

#endif
