#ifndef ALN_ROUTE_POLICY_MIDDLEWARE_H
#define ALN_ROUTE_POLICY_MIDDLEWARE_H

#import <Foundation/Foundation.h>
#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const ALNContextRoutePolicyNamesStashKey;
FOUNDATION_EXPORT NSString *const ALNContextRoutePolicyDecisionStashKey;

@interface ALNRoutePolicyMiddleware : NSObject <ALNMiddleware>

+ (nullable NSError *)validateSecurityConfiguration:(NSDictionary *)config;

@end

NS_ASSUME_NONNULL_END

#endif
