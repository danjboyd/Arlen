#ifndef ALN_ROUTE_POLICY_MIDDLEWARE_H
#define ALN_ROUTE_POLICY_MIDDLEWARE_H

#import <Foundation/Foundation.h>
#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const ALNContextRoutePolicyNamesStashKey;
FOUNDATION_EXPORT NSString *const ALNContextRoutePolicyMatchedPathStashKey;
FOUNDATION_EXPORT NSString *const ALNContextRoutePolicyDecisionStashKey;
FOUNDATION_EXPORT NSString *const ALNContextRoutePolicyAdditionalPathStashKey;

@interface ALNRoutePolicyMiddleware : NSObject <ALNMiddleware>

+ (nullable NSError *)validateSecurityConfiguration:(NSDictionary *)config;
// Read-only catalog check. Invocation still runs the full route policy.
+ (BOOL)context:(ALNContext *)context canListRoute:(ALNRoute *)route;

@end

NS_ASSUME_NONNULL_END

#endif
