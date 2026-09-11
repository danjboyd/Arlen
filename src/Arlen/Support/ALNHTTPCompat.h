#ifndef ALN_HTTP_COMPAT_H
#define ALN_HTTP_COMPAT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSData *_Nullable ALNSynchronousURLRequest(NSURLRequest *request,
                                                             NSURLResponse *_Nullable *_Nullable response,
                                                             NSError *_Nullable *_Nullable error);

/// Bounded GET for trusted metadata: rejects redirects, cookies and non-200 responses.
FOUNDATION_EXPORT NSData *_Nullable ALNBoundedMetadataGET(NSURL *url, NSUInteger maxBytes,
                                                          NSTimeInterval timeout);

/// Same bounded transport with sanitized Arlen.Metadata errors (no URLs or bodies).
/// Codes: 1 invalid bounds, 2 redirect, 3 response/declared size, 4 streamed size,
/// 5 transport, 6 total deadline. GNUstep requires libcurl with TLS and async DNS.
FOUNDATION_EXPORT NSData *_Nullable ALNBoundedMetadataGETWithError(NSURL *url, NSUInteger maxBytes,
    NSTimeInterval timeout, NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END

#endif
