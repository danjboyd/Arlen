#ifndef ALN_RESPONSE_ENVELOPE_MIDDLEWARE_H
#define ALN_RESPONSE_ENVELOPE_MIDDLEWARE_H

#import <Foundation/Foundation.h>

#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

/// Set to @YES in a context stash for protocols that require their own envelope.
FOUNDATION_EXPORT NSString *const ALNResponseEnvelopeDisabledStashKey;

@interface ALNResponseEnvelopeMiddleware : NSObject <ALNMiddleware>

- (instancetype)init;
- (instancetype)initWithIncludeRequestID:(BOOL)includeRequestID;

@end

NS_ASSUME_NONNULL_END

#endif
