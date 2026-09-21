#ifndef ALN_HTTP_COMPAT_H
#define ALN_HTTP_COMPAT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Synchronous request that follows up to ALNSynchronousURLRequestDefaultMaxRedirects
/// redirects. HTTP error statuses are returned as responses, not errors; transport
/// failures use NSURLErrorDomain (for example NSURLErrorTimedOut,
/// NSURLErrorHTTPTooManyRedirects). On GNUstep this is a libcurl transport (no
/// shared cookie storage); on Apple platforms it is NSURLSession.
FOUNDATION_EXPORT NSData *_Nullable ALNSynchronousURLRequest(NSURLRequest *request,
                                                             NSURLResponse *_Nullable *_Nullable response,
                                                             NSError *_Nullable *_Nullable error);

/// Same transport with an explicit redirect budget. maxRedirects of 0 returns the
/// 3xx response unfollowed; exceeding a positive budget fails with
/// NSURLErrorHTTPTooManyRedirects.
FOUNDATION_EXPORT NSData *_Nullable ALNSynchronousURLRequestFollowingRedirects(
    NSURLRequest *request, NSUInteger maxRedirects,
    NSURLResponse *_Nullable *_Nullable response, NSError *_Nullable *_Nullable error);

FOUNDATION_EXPORT const NSUInteger ALNSynchronousURLRequestDefaultMaxRedirects;

typedef NS_ENUM(NSUInteger, ALNHTTPRedirectLimitPolicy) {
  ALNHTTPRedirectLimitError = 0,
  ALNHTTPRedirectLimitReturnResponse = 1,
};

/// Received data, without synthesized status descriptions. Uses libcurl on
/// GNUstep and Apple; no shared cookie store. Existing helpers are unchanged.
@interface ALNHTTPClientResult : NSObject
@property(nonatomic, strong, readonly) NSHTTPURLResponse *response;
@property(nonatomic, copy, readonly) NSData *body;
/// nil for HTTP/2 or HTTP/3; an empty string means an empty HTTP/1.x phrase.
@property(nonatomic, copy, readonly, nullable) NSString *receivedReasonPhrase;
@property(nonatomic, assign, readonly) BOOL stoppedAtRedirectLimit;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Follows at most maxRedirects under one total request timeout. With the return
/// policy, a boundary redirect includes its complete body and is not an error.
/// Zero follows no redirects and returns the initial response under either policy.
/// Real transport failures return nil and NSURLErrorDomain, never a partial result.
FOUNDATION_EXPORT ALNHTTPClientResult *_Nullable ALNSynchronousHTTPResult(
    NSURLRequest *request, NSUInteger maxRedirects, ALNHTTPRedirectLimitPolicy policy,
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
