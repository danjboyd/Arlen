#ifndef ALN_RESPONSE_ENVELOPE_MIDDLEWARE_H
#define ALN_RESPONSE_ENVELOPE_MIDDLEWARE_H

#import <Foundation/Foundation.h>

#import "ALNApplication.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNResponseEnvelopeMiddleware : NSObject <ALNMiddleware>

- (instancetype)init;
- (instancetype)initWithIncludeRequestID:(BOOL)includeRequestID;

@end

NS_ASSUME_NONNULL_END

#endif
