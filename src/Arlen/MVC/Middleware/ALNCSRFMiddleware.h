#ifndef ALN_CSRF_MIDDLEWARE_H
#define ALN_CSRF_MIDDLEWARE_H

#import <Foundation/Foundation.h>

#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNCSRFMiddleware : NSObject <ALNMiddleware>

- (instancetype)initWithHeaderName:(nullable NSString *)headerName
                    queryParamName:(nullable NSString *)queryParamName;

- (instancetype)initWithHeaderName:(nullable NSString *)headerName
                    queryParamName:(nullable NSString *)queryParamName
         allowQueryParamFallback:(BOOL)allowQueryParamFallback;

// `exemptPathPrefixes` skip the check only for requests that carry no session
// cookie: with no ambient credential there is nothing to forge. Requests with a
// session cookie still need a valid token on these paths. Prefixes match the
// exact path or a path below it (`/mcp` matches `/mcp` and `/mcp/x`).
- (instancetype)initWithHeaderName:(nullable NSString *)headerName
                    queryParamName:(nullable NSString *)queryParamName
         allowQueryParamFallback:(BOOL)allowQueryParamFallback
                exemptPathPrefixes:(nullable NSArray<NSString *> *)exemptPathPrefixes;

// Normalizes `csrf.exemptPathPrefixes` config. Returns nil and sets `problem`
// when the value is not an array of literal, non-root absolute paths.
+ (nullable NSArray<NSString *> *)normalizedExemptPathPrefixes:(nullable id)value
                                                        problem:(NSString *_Nullable *_Nullable)problem;

@end

NS_ASSUME_NONNULL_END

#endif
