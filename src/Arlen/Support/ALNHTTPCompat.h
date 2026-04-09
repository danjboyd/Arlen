#ifndef ALN_HTTP_COMPAT_H
#define ALN_HTTP_COMPAT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSData *_Nullable ALNSynchronousURLRequest(NSURLRequest *request,
                                                             NSURLResponse *_Nullable *_Nullable response,
                                                             NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

#endif
