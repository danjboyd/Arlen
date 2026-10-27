#ifndef ALN_HTTP_CLIENT_H
#define ALN_HTTP_CLIENT_H

#import <Foundation/Foundation.h>

#import "ALNHTTPCompat.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNLogger;

FOUNDATION_EXPORT NSString *const ALNHTTPClientErrorDomain;

typedef NS_ENUM(NSInteger, ALNHTTPClientErrorCode) {
  ALNHTTPClientErrorInvalidConfiguration = 1,
  ALNHTTPClientErrorInvalidRequest = 2,
  ALNHTTPClientErrorHostNotAllowed = 3,
  ALNHTTPClientErrorRedirectNotAllowed = 4,
  ALNHTTPClientErrorTooManyRedirects = 5,
  ALNHTTPClientErrorResponseTooLarge = 6,
  ALNHTTPClientErrorTimedOut = 7,
  ALNHTTPClientErrorTransport = 8,
  ALNHTTPClientErrorCancelled = 9,
  ALNHTTPClientErrorIdleTimedOut = 10,
};

/// A thread-safe, single-use cancellation token for an outbound stream.
/// Create before starting the request; `cancel` may be called on any thread.
/// Cancellation is permanent. A pre-cancelled token prevents a connection.
@interface ALNHTTPClientCancellation : NSObject
@property(nonatomic, readonly, getter=isCancelled) BOOL cancelled;
- (void)cancel;
@end

/// Called once with the final response headers, before any body data.
/// Return NO to cancel. Interim responses and followed redirects are hidden.
typedef BOOL (^ALNHTTPClientResponseHandler)(NSHTTPURLResponse *response);
/// Receives arbitrary byte chunks (not text, SSE events, or HTTP chunk frames).
/// Return NO to cancel. Retain data explicitly if it is needed after the callback.
typedef BOOL (^ALNHTTPClientDataHandler)(NSData *data);

/// Outbound HTTP client for calling third-party APIs from app code.
///
/// Every request, and every redirect hop, must go to a host on the allowlist
/// fixed at construction; anything else fails before a connection is made.
/// Each request has one total deadline and a response size limit. Redirects
/// are not followed unless `maxRedirects` is set, and never for a request that
/// carries `Authorization` or `Cookie`. Errors and log lines never contain
/// request headers, bodies or query strings.
///
/// Configuration keys:
/// - `allowedHosts` (required): hostnames, optionally `host:port`. A bare host
///   allows only the scheme's default port. Matching is exact and
///   case-insensitive; there are no wildcards.
/// - `timeoutSeconds`: total deadline per request, redirects included
///   (default 10, at most 300).
/// - `maxResponseBytes`: response body limit (default 1048576, at most 67108864).
/// - `maxRedirects`: redirects to follow (default 0, at most 10). With 0 a 3xx
///   is returned as the result.
/// - `allowHTTP`: allow plain `http` URLs (default NO).
/// - `idleTimeoutSeconds`: streaming only, maximum silence between incoming
///   response bytes, including waiting for headers (default 30, range 1–300).
/// - `streamingTimeoutSeconds`: streaming only, total deadline including
///   redirects (default 900, range 1–86400). Buffered calls use timeoutSeconds.
///
/// Requests are synchronous. Use libcurl with TLS and asynchronous DNS on
/// GNUstep and Apple.
@interface ALNHTTPClient : NSObject

@property(nonatomic, copy, readonly) NSArray<NSString *> *allowedHosts;
@property(nonatomic, assign, readonly) NSTimeInterval timeout;
@property(nonatomic, assign, readonly) NSUInteger maxResponseBytes;
@property(nonatomic, assign, readonly) NSUInteger maxRedirects;
@property(nonatomic, assign, readonly) BOOL allowHTTP;
@property(nonatomic, assign, readonly) NSTimeInterval idleTimeout;
@property(nonatomic, assign, readonly) NSTimeInterval streamingTimeout;
/// When set, each request is logged (info on success, warn on failure) with
/// method, host, path, status, duration and size only.
@property(nonatomic, strong, nullable) ALNLogger *logger;

- (nullable instancetype)initWithConfiguration:(NSDictionary *)configuration
                                         error:(NSError *_Nullable *_Nullable)error;
- (instancetype)init NS_UNAVAILABLE;

/// Sends `request` (GET, HEAD, POST, PUT, PATCH or DELETE). HTTP error statuses
/// are results, not errors.
- (nullable ALNHTTPClientResult *)performRequest:(NSURLRequest *)request
                                           error:(NSError *_Nullable *_Nullable)error;
/// Streams synchronously on the calling thread, without buffering the body.
/// All callbacks are serial and finish before this method returns. Run on an
/// application worker; callbacks must return promptly. Use a cancellation token
/// for Stop/disconnect handling even when no data is arriving. Transport polls
/// cancellation and deadlines at intervals of at most 100 ms while waiting.
///
/// YES means a complete HTTP response (including HTTP error statuses). NO means
/// failure or cancellation; already delivered bytes cannot be recalled and must
/// not be treated as a complete response. Callback exceptions become sanitized
/// transport errors. maxResponseBytes bounds all body bytes across redirects,
/// including discarded redirect bodies. Request bodies must use HTTPBody;
/// HTTPBodyStream is unsupported by this API. Existing buffered APIs are unchanged.
- (BOOL)streamRequest:(NSURLRequest *)request
        cancellation:(nullable ALNHTTPClientCancellation *)cancellation
          onResponse:(ALNHTTPClientResponseHandler)onResponse
              onData:(ALNHTTPClientDataHandler)onData
               error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNHTTPClientResult *)GETURL:(NSURL *)url
                                 headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                                   error:(NSError *_Nullable *_Nullable)error;
/// POSTs `object` as JSON (`Content-Type: application/json`).
- (nullable ALNHTTPClientResult *)POSTJSONObject:(id)object
                                           toURL:(NSURL *)url
                                         headers:(nullable NSDictionary<NSString *, NSString *> *)headers
                                           error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
