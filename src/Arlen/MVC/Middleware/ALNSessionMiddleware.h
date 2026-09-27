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

@property(nonatomic, copy, readonly) NSString *cookieName;

// Seals a session dictionary into a cookie value this middleware accepts, and
// opens one again (nil when tampered, expired or from another secret). Intended
// for tests and tooling that must present an established session.
- (nullable NSString *)encodeSessionDictionary:(NSDictionary *)session;
- (nullable NSDictionary *)sessionDictionaryFromCookieValue:(NSString *)value;

@end

NS_ASSUME_NONNULL_END

#endif
