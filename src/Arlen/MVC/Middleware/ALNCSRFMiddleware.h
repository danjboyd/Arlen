#ifndef ALN_CSRF_MIDDLEWARE_H
#define ALN_CSRF_MIDDLEWARE_H

#import <Foundation/Foundation.h>

#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNCSRFMiddleware : NSObject <ALNMiddleware>

- (instancetype)initWithHeaderName:(nullable NSString *)headerName
                    queryParamName:(nullable NSString *)queryParamName;

@end

NS_ASSUME_NONNULL_END

#endif
