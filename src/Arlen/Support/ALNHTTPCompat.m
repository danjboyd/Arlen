#import "ALNHTTPCompat.h"
#include <math.h>
#include <time.h>
#if defined(_WIN32)
#include <windows.h>
#endif

#import <dispatch/dispatch.h>
#if defined(GNUSTEP)
#include <curl/curl.h>
#include <limits.h>
#include <string.h>
#include <strings.h>
#endif

NSData *ALNSynchronousURLRequest(NSURLRequest *request,
                                 NSURLResponse *__autoreleasing _Nullable *_Nullable response,
                                 NSError *__autoreleasing _Nullable *_Nullable error) {
  if (error != NULL) {
    *error = nil;
  }
  if (response != NULL) {
    *response = nil;
  }
  if (request == nil) {
    return nil;
  }

#if defined(__APPLE__)
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  __block NSData *resultData = nil;
  __block NSURLResponse *resultResponse = nil;
  __block NSError *resultError = nil;

  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
  NSURLSessionDataTask *task =
      [session dataTaskWithRequest:request
                 completionHandler:^(NSData *data, NSURLResponse *taskResponse, NSError *taskError) {
                   resultData = data;
                   resultResponse = taskResponse;
                   resultError = taskError;
                   dispatch_semaphore_signal(semaphore);
                 }];
  [task resume];
  dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
  [session finishTasksAndInvalidate];

  if (response != NULL) {
    *response = resultResponse;
  }
  if (error != NULL) {
    *error = resultError;
  }
  return resultData;
#else
  return [NSURLConnection sendSynchronousRequest:request returningResponse:response error:error];
#endif
}

// GNUstep's systemUptime returns whole seconds. Use a fractional monotonic
// clock so short deadlines and slow trickling responses cannot evade the cap.
static NSTimeInterval MetadataNow(void) {
#if defined(_WIN32)
  LARGE_INTEGER counter, frequency;
  if (!QueryPerformanceFrequency(&frequency) || !QueryPerformanceCounter(&counter)) return NAN;
  return (NSTimeInterval)counter.QuadPart / frequency.QuadPart;
#else
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return NAN;
  return (NSTimeInterval)value.tv_sec + value.tv_nsec / 1e9;
#endif
}

static NSError *MetadataError(NSInteger code, NSString *reason) {
  return [NSError errorWithDomain:@"Arlen.Metadata" code:code
                        userInfo:@{NSLocalizedDescriptionKey:reason}];
}

#if !defined(GNUSTEP)
// Apple Foundation transport; GNUstep workaround follows below.
@interface ALNMetadataConnection : NSObject <NSURLConnectionDelegate>
@property(nonatomic, strong) NSMutableData *data;
@property(nonatomic, assign) NSUInteger limit;
@property(nonatomic, assign) BOOL done;
@property(nonatomic, assign) BOOL accepted;
@property(nonatomic, strong) NSError *error;
@end
@implementation ALNMetadataConnection
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response {
  if (response) { self.error = MetadataError(2, @"Metadata redirect rejected"); self.accepted = NO; self.done = YES; [connection cancel]; return nil; }
  return request;
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
  self.accepted = [response isKindOfClass:[NSHTTPURLResponse class]] &&
      [(NSHTTPURLResponse *)response statusCode] == 200 &&
      (response.expectedContentLength < 0 || (unsigned long long)response.expectedContentLength <= self.limit);
  if (!self.accepted) {
    self.error = MetadataError(3, @"Metadata HTTP response rejected (requires 200 within size limit)");
    self.done = YES; [connection cancel]; }
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
  if (data.length > self.limit - self.data.length) {
    self.error = MetadataError(4, @"Metadata response exceeds size limit");
    self.accepted = NO; self.done = YES; [connection cancel]; return;
  }
  [self.data appendData:data];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection { self.done = YES; }
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
  // Never retain Foundation userInfo: it can contain URLs and response data.
  self.error = MetadataError(5, @"Metadata transport failed");
  if ([error.domain isEqual:NSURLErrorDomain]) {
    self.error = MetadataError(5, [NSString stringWithFormat:@"Metadata transport failed (NSURLErrorDomain %ld)", (long)error.code]);
  }
  self.accepted = NO; self.done = YES;
}
@end
#endif

NSData *ALNBoundedMetadataGET(NSURL *url, NSUInteger maxBytes, NSTimeInterval timeout) {
  return ALNBoundedMetadataGETWithError(url, maxBytes, timeout, NULL);
}
#if defined(GNUSTEP)
// Work around GNUstep libs-base #783. The older NSURLConnection socket path
// requires default-mode pumping; its TLS defaults also depend on process-wide
// settings. libcurl provides per-request chain/hostname verification and a
// streaming, deadline-bounded transport without servicing the caller's run loop.
typedef struct {
  void *buffer;
  NSError *__strong *failure;
  NSUInteger limit;
  NSTimeInterval deadline;
} MetadataTransfer;

static void MetadataSetFailure(MetadataTransfer *transfer, NSInteger code, NSString *reason) {
  NSError *__strong *error = transfer->failure;
  if (!*error) *error = MetadataError(code, reason);
}
static size_t MetadataWrite(char *bytes, size_t size, size_t count, void *context) {
  MetadataTransfer *transfer = context;
  NSMutableData *data = (__bridge NSMutableData *)transfer->buffer;
  if (size && count > NSUIntegerMax / size) return 0;
  size_t length = size * count;
  if (length > transfer->limit - data.length) {
    MetadataSetFailure(transfer, 4, @"Metadata response exceeds size limit");
    return 0;
  }
  [data appendBytes:bytes length:length];
  return length;
}
static size_t MetadataHeader(char *bytes, size_t size, size_t count, void *context) {
  MetadataTransfer *transfer = context;
  if (size && count > NSUIntegerMax / size) return 0;
  size_t length = size * count;
  if (length >= 15 && strncasecmp(bytes, "Content-Length:", 15) == 0) {
    NSString *value = [[NSString alloc] initWithBytes:bytes + 15 length:length - 15 encoding:NSASCIIStringEncoding];
    NSScanner *scanner = [NSScanner scannerWithString:value ?: @""];
    long long declared = 0;
    if ([scanner scanLongLong:&declared] && declared > 0 && (unsigned long long)declared > transfer->limit) {
      MetadataSetFailure(transfer, 3, @"Metadata declared response exceeds size limit");
      return 0;
    }
  }
  // libcurl parses the wire syntax; inspect the HTTP status line here.
  if (length >= 5 && memcmp(bytes, "HTTP/", 5) == 0) {
    NSString *line = [[NSString alloc] initWithBytes:bytes length:length encoding:NSASCIIStringEncoding];
    NSScanner *scanner = [NSScanner scannerWithString:line ?: @""];
    [scanner scanUpToString:@" " intoString:NULL];
    NSInteger status = 0;
    [scanner scanInteger:&status];
    if (status >= 300 && status < 400) {
      MetadataSetFailure(transfer, 2, @"Metadata redirect rejected");
      return 0;
    }
    if (status >= 200 && status != 200) {
      MetadataSetFailure(transfer, 3, @"Metadata HTTP response rejected (requires 200)");
      return 0;
    }
  }
  return length;
}
static int MetadataProgress(void *context, curl_off_t total, curl_off_t received,
                            curl_off_t uploadTotal, curl_off_t uploaded) {
  MetadataTransfer *transfer = context;
  NSTimeInterval now = MetadataNow();
  return !isfinite(now) || now >= transfer->deadline;
}
static NSData *MetadataCurlGET(NSURL *url, NSUInteger maxBytes, NSTimeInterval timeout,
                                NSTimeInterval deadline, NSError **error) {
  static CURLcode initialized;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ initialized = curl_global_init(CURL_GLOBAL_DEFAULT); });
  // Synchronous DNS cannot guarantee a total deadline with NOSIGNAL on workers.
  if (initialized != CURLE_OK || (curl_version_info(CURLVERSION_NOW)->features & (CURL_VERSION_ASYNCHDNS | CURL_VERSION_SSL)) != (CURL_VERSION_ASYNCHDNS | CURL_VERSION_SSL)) {
    if (error) *error = MetadataError(5, @"Metadata transport requires libcurl with TLS and asynchronous DNS");
    return nil;
  }
  CURL *curl = curl_easy_init();
  if (!curl) { if (error) *error = MetadataError(5, @"Metadata transport could not initialize"); return nil; }
  NSMutableData *data = [NSMutableData data];
  NSError *failure = nil;
  MetadataTransfer transfer = {(__bridge void *)data, &failure, maxBytes, deadline};
  struct curl_slist *headers = curl_slist_append(NULL, "Accept: application/json");
  CURLcode result = CURLE_OUT_OF_MEMORY;
  long status = 0;
  if (!headers) goto cleanup;
#define METADATA_OPTION(option, value) do { result = curl_easy_setopt(curl, option, value); if (result != CURLE_OK) goto cleanup; } while (0)
  METADATA_OPTION(CURLOPT_URL, url.absoluteString.UTF8String);
  METADATA_OPTION(CURLOPT_HTTPHEADER, headers);
  METADATA_OPTION(CURLOPT_NOSIGNAL, 1L);
  METADATA_OPTION(CURLOPT_SSL_VERIFYPEER, 1L);
  METADATA_OPTION(CURLOPT_SSL_VERIFYHOST, 2L);
  METADATA_OPTION(CURLOPT_FOLLOWLOCATION, 0L);
#if LIBCURL_VERSION_NUM >= 0x075500
  METADATA_OPTION(CURLOPT_PROTOCOLS_STR, "http,https");
#else
  METADATA_OPTION(CURLOPT_PROTOCOLS, (long)(CURLPROTO_HTTP | CURLPROTO_HTTPS));
#endif
  METADATA_OPTION(CURLOPT_TIMEOUT_MS,
      timeout >= (double)LONG_MAX / 1000 ? LONG_MAX : MAX(1L, (long)ceil(timeout * 1000)));
  METADATA_OPTION(CURLOPT_MAXFILESIZE_LARGE, (curl_off_t)MIN(maxBytes, (NSUInteger)LLONG_MAX));
  METADATA_OPTION(CURLOPT_WRITEFUNCTION, MetadataWrite);
  METADATA_OPTION(CURLOPT_WRITEDATA, &transfer);
  METADATA_OPTION(CURLOPT_HEADERFUNCTION, MetadataHeader);
  METADATA_OPTION(CURLOPT_HEADERDATA, &transfer);
  METADATA_OPTION(CURLOPT_NOPROGRESS, 0L);
  METADATA_OPTION(CURLOPT_XFERINFOFUNCTION, MetadataProgress);
  METADATA_OPTION(CURLOPT_XFERINFODATA, &transfer);
  result = curl_easy_perform(curl);
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
#undef METADATA_OPTION
cleanup:
  curl_slist_free_all(headers);
  curl_easy_cleanup(curl);
  if (result == CURLE_OPERATION_TIMEDOUT || !isfinite(MetadataNow()) || MetadataNow() >= deadline)
    failure = MetadataError(6, @"Metadata total deadline exceeded");
  else if (!failure && result == CURLE_FILESIZE_EXCEEDED)
    failure = MetadataError(4, @"Metadata response exceeds size limit");
  else if (!failure && result != CURLE_OK)
    failure = MetadataError(5, [NSString stringWithFormat:@"Metadata transport failed (libcurl %ld)", (long)result]);
  else if (!failure && status != 200)
    failure = MetadataError(3, @"Metadata HTTP response rejected (requires 200)");
  if (error) *error = failure;
  return failure ? nil : [data copy];
}
#endif

NSData *ALNBoundedMetadataGETWithError(NSURL *url, NSUInteger maxBytes, NSTimeInterval timeout,
                                      NSError **error) {
  if (error) *error = nil;
  if (!url || !maxBytes || !isfinite(timeout) || timeout <= 0) {
    if (error) *error = MetadataError(1, @"Invalid metadata request bounds");
    return nil;
  }
  NSTimeInterval deadline = MetadataNow() + timeout;
  if (!isfinite(deadline)) {
    if (error) *error = MetadataError(6, @"Metadata monotonic clock unavailable");
    return nil;
  }
#if defined(GNUSTEP)
  return MetadataCurlGET(url, maxBytes, timeout, deadline, error);
#else
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:timeout];
  [request setHTTPShouldHandleCookies:NO];
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  ALNMetadataConnection *delegate = [ALNMetadataConnection new];
  delegate.limit = maxBytes; delegate.data = [NSMutableData data];
  NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:delegate startImmediately:NO];
  if (!connection) {
    if (error) *error = MetadataError(5, @"Metadata transport could not initialize");
    return nil;
  }
  NSString *mode = @"Arlen.MetadataFetch";
  [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:mode];
  [connection start];
  while (!delegate.done && MetadataNow() < deadline) {
    [[NSRunLoop currentRunLoop] runMode:mode beforeDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.05, MAX(0, deadline - MetadataNow()))]];
  }
  [connection cancel];
  [connection unscheduleFromRunLoop:[NSRunLoop currentRunLoop] forMode:mode];
  if (!delegate.done || !isfinite(MetadataNow()) || MetadataNow() >= deadline) {
    if (error) *error = MetadataError(6, @"Metadata total deadline exceeded");
    return nil;
  }
  if (error) *error = delegate.error;
  return delegate.accepted ? [delegate.data copy] : nil;
#endif
}
