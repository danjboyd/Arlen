#import "ALNHTTPCompat.h"
#include <math.h>
#include <time.h>
#if defined(_WIN32)
#include <windows.h>
#endif

#import <dispatch/dispatch.h>
#if defined(GNUSTEP) || defined(__APPLE__)
#include <curl/curl.h>
#include <limits.h>
#include <string.h>
#include <strings.h>
#endif

#if defined(GNUSTEP) || defined(__APPLE__)
static BOOL ALNCurlGlobalReady(void) {
  static CURLcode initialized;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ initialized = curl_global_init(CURL_GLOBAL_DEFAULT); });
  return initialized == CURLE_OK;
}
#endif

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
static NSData *MetadataCurlRequest(NSURLRequest *request, NSUInteger maxBytes, NSTimeInterval timeout,
                                NSTimeInterval deadline, NSError **error) {
  // Synchronous DNS cannot guarantee a total deadline with NOSIGNAL on workers.
  if (!ALNCurlGlobalReady() || (curl_version_info(CURLVERSION_NOW)->features & (CURL_VERSION_ASYNCHDNS | CURL_VERSION_SSL)) != (CURL_VERSION_ASYNCHDNS | CURL_VERSION_SSL)) {
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
  METADATA_OPTION(CURLOPT_URL, request.URL.absoluteString.UTF8String);
  if ([request.HTTPMethod isEqual:@"POST"]) {
    struct curl_slist *next = curl_slist_append(headers, "Content-Type: application/x-www-form-urlencoded");
    if (!next) goto cleanup;
    headers = next;
    METADATA_OPTION(CURLOPT_POST, 1L);
    METADATA_OPTION(CURLOPT_POSTFIELDS, request.HTTPBody.bytes ?: "");
    METADATA_OPTION(CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)request.HTTPBody.length);
  }
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
  if (!url || !maxBytes || !isfinite(timeout) || timeout <= 0) {
    if (error) *error = MetadataError(1, @"Invalid metadata request bounds");
    return nil;
  }
  NSURLRequest *request = [NSURLRequest requestWithURL:url
      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:timeout];
  return ALNBoundedJSONRequest(request, maxBytes, error);
}

NSData *ALNBoundedJSONRequest(NSURLRequest *input, NSUInteger maxBytes, NSError **error) {
  if (error) *error = nil;
  NSTimeInterval timeout = input.timeoutInterval;
  if (!input.URL || !maxBytes || !isfinite(timeout) || timeout <= 0 ||
      (![(input.HTTPMethod ?: @"GET") isEqual:@"GET"] && ![input.HTTPMethod isEqual:@"POST"])) {
    if (error) *error = MetadataError(1, @"Invalid bounded JSON request");
    return nil;
  }
  NSTimeInterval deadline = MetadataNow() + timeout;
  if (!isfinite(deadline)) {
    if (error) *error = MetadataError(6, @"Metadata monotonic clock unavailable");
    return nil;
  }
#if defined(GNUSTEP)
  return MetadataCurlRequest(input, maxBytes, timeout, deadline, error);
#else
  NSMutableURLRequest *request = [input mutableCopy];
  [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
  [request setAllHTTPHeaderFields:@{ @"Accept": @"application/json" }];
  if ([input.HTTPMethod isEqual:@"POST"])
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
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

#pragma mark - Synchronous requests

const NSUInteger ALNSynchronousURLRequestDefaultMaxRedirects = 10;

static NSError *ALNSynchronousURLError(NSInteger code, NSString *description) {
  return [NSError errorWithDomain:NSURLErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : description ?: @"request failed"}];
}

// Internal parser seam used by wire-version regression tests. No canonical fallback.
NSString *ALNHTTPReceivedReasonPhraseFromStatusLine(NSString *line) {
  if (![line hasPrefix:@"HTTP/1."]) return nil;
  NSUInteger length = line.length;
  while (length && ([line characterAtIndex:length - 1] == '\r' || [line characterAtIndex:length - 1] == '\n')) length--;
  NSString *statusLine = [line substringToIndex:length];
  NSRange firstSpace = [statusLine rangeOfString:@" "];
  if (firstSpace.location == NSNotFound) return @"";
  NSUInteger start = firstSpace.location + 1;
  NSRange secondSpace = [statusLine rangeOfString:@" " options:0
      range:NSMakeRange(start, statusLine.length - start)];
  return secondSpace.location == NSNotFound ? @"" : [statusLine substringFromIndex:secondSpace.location + 1];
}

#if defined(GNUSTEP) || defined(__APPLE__)
// GNUstep's -[NSURLConnection sendSynchronousRequest:...] never issues the
// redirected request (issue #22, same libs-base transport as #783), so the
// synchronous helper drives libcurl directly on GNUstep. libcurl follows a
// bounded redirect chain, keeps only the final response's headers, and maps
// transport failures onto NSURLErrorDomain codes; HTTP error statuses are
// returned as responses, not errors, matching Foundation.
typedef struct {
  void *body;         // NSMutableData
  void *headers;      // NSMutableDictionary<NSString *, NSString *>
  void *httpVersion;  // NSMutableString
  void *reasonPhrase; // NSMutableString
  BOOL hasReasonPhrase;
} ALNSynchronousTransfer;

static size_t ALNSynchronousWrite(char *bytes, size_t size, size_t count, void *context) {
  ALNSynchronousTransfer *transfer = context;
  if (size && count > NSUIntegerMax / size) return 0;
  NSMutableData *body = (__bridge NSMutableData *)transfer->body;
  [body appendBytes:bytes length:size * count];
  return size * count;
}

static size_t ALNSynchronousHeader(char *bytes, size_t size, size_t count, void *context) {
  ALNSynchronousTransfer *transfer = context;
  if (size && count > NSUIntegerMax / size) return 0;
  size_t length = size * count;
  NSMutableDictionary *headers = (__bridge NSMutableDictionary *)transfer->headers;
  NSMutableString *version = (__bridge NSMutableString *)transfer->httpVersion;
  NSString *line = [[NSString alloc] initWithBytes:bytes length:length encoding:NSISOLatin1StringEncoding] ?: @"";
  NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed hasPrefix:@"HTTP/"]) {
    // Every status line (1xx interim, a redirect hop, or the final response)
    // starts a new header block; only the last block is reported.
    [headers removeAllObjects];
    [(__bridge NSMutableData *)transfer->body setLength:0];
    NSMutableString *phrase = (__bridge NSMutableString *)transfer->reasonPhrase;
    [phrase setString:@""];
    NSString *received = ALNHTTPReceivedReasonPhraseFromStatusLine(line);
    transfer->hasReasonPhrase = received != nil;
    [phrase setString:received ?: @""];
    NSRange space = [trimmed rangeOfString:@" "];
    [version setString:(space.location == NSNotFound ? trimmed : [trimmed substringToIndex:space.location])];
    return length;
  }
  NSRange separator = [trimmed rangeOfString:@":"];
  if (separator.location == NSNotFound || separator.location == 0) return length;
  NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
  NSString *name = [[trimmed substringToIndex:separator.location] stringByTrimmingCharactersInSet:whitespace];
  NSString *value = [[trimmed substringFromIndex:separator.location + 1] stringByTrimmingCharactersInSet:whitespace];
  NSString *existingKey = nil;
  for (NSString *key in headers) {
    if ([key caseInsensitiveCompare:name] == NSOrderedSame) { existingKey = key; break; }
  }
  if (existingKey != nil) {
    headers[existingKey] = [headers[existingKey] stringByAppendingFormat:@", %@", value];
  } else {
    headers[name] = value;
  }
  return length;
}

static NSInteger ALNSynchronousURLErrorCode(CURLcode result) {
  switch (result) {
    case CURLE_OPERATION_TIMEDOUT: return NSURLErrorTimedOut;
    case CURLE_COULDNT_RESOLVE_HOST:
    case CURLE_COULDNT_RESOLVE_PROXY: return NSURLErrorCannotFindHost;
    case CURLE_COULDNT_CONNECT: return NSURLErrorCannotConnectToHost;
    case CURLE_TOO_MANY_REDIRECTS: return NSURLErrorHTTPTooManyRedirects;
    case CURLE_URL_MALFORMAT: return NSURLErrorBadURL;
    case CURLE_UNSUPPORTED_PROTOCOL: return NSURLErrorUnsupportedURL;
    case CURLE_SEND_ERROR:
    case CURLE_RECV_ERROR:
    case CURLE_GOT_NOTHING:
    case CURLE_PARTIAL_FILE: return NSURLErrorNetworkConnectionLost;
    case CURLE_SSL_CONNECT_ERROR:
    case CURLE_PEER_FAILED_VERIFICATION: return NSURLErrorSecureConnectionFailed;
    default: return NSURLErrorUnknown;
  }
}

static NSData *ALNSynchronousRequestBody(NSURLRequest *request) {
  if (request.HTTPBody != nil) return request.HTTPBody;
  NSInputStream *stream = request.HTTPBodyStream;
  if (stream == nil) return nil;
  NSMutableData *body = [NSMutableData data];
  uint8_t buffer[16384];
  [stream open];
  for (;;) {
    NSInteger count = [stream read:buffer maxLength:sizeof(buffer)];
    if (count <= 0) break;
    [body appendBytes:buffer length:(NSUInteger)count];
  }
  [stream close];
  return body;
}

// Applies every libcurl option; returns the first failing CURLcode.
static CURLcode ALNSynchronousConfigure(CURL *curl, NSString *urlString, NSString *method,
                                        NSData *requestBody, struct curl_slist *headerList,
                                        NSUInteger maxRedirects, NSTimeInterval timeout,
                                        char *message, ALNSynchronousTransfer *transfer) {
  CURLcode result = CURLE_OK;
#define SYNC_OPTION(option, value) do { result = curl_easy_setopt(curl, option, value); if (result != CURLE_OK) return result; } while (0)
  SYNC_OPTION(CURLOPT_URL, urlString.UTF8String);
  SYNC_OPTION(CURLOPT_ERRORBUFFER, message);
  SYNC_OPTION(CURLOPT_NOSIGNAL, 1L);
  SYNC_OPTION(CURLOPT_SSL_VERIFYPEER, 1L);
  SYNC_OPTION(CURLOPT_SSL_VERIFYHOST, 2L);
  SYNC_OPTION(CURLOPT_FOLLOWLOCATION, maxRedirects > 0 ? 1L : 0L);
  SYNC_OPTION(CURLOPT_MAXREDIRS, (long)MIN(maxRedirects, (NSUInteger)LONG_MAX));
#if LIBCURL_VERSION_NUM >= 0x075500
  SYNC_OPTION(CURLOPT_PROTOCOLS_STR, "http,https");
  SYNC_OPTION(CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
#else
  SYNC_OPTION(CURLOPT_PROTOCOLS, (long)(CURLPROTO_HTTP | CURLPROTO_HTTPS));
  SYNC_OPTION(CURLOPT_REDIR_PROTOCOLS, (long)(CURLPROTO_HTTP | CURLPROTO_HTTPS));
#endif
  SYNC_OPTION(CURLOPT_TIMEOUT_MS,
      timeout >= (double)LONG_MAX / 1000 ? LONG_MAX : MAX(1L, (long)ceil(timeout * 1000)));
  SYNC_OPTION(CURLOPT_HTTPHEADER, headerList);
  if ([method isEqualToString:@"HEAD"]) {
    SYNC_OPTION(CURLOPT_NOBODY, 1L);
  } else if ([method isEqualToString:@"GET"] && requestBody.length == 0) {
    SYNC_OPTION(CURLOPT_HTTPGET, 1L);
  } else {
    if (requestBody.length > 0) {
      SYNC_OPTION(CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)requestBody.length);
      SYNC_OPTION(CURLOPT_POSTFIELDS, requestBody.bytes);
    } else {
      SYNC_OPTION(CURLOPT_POST, 1L);
      SYNC_OPTION(CURLOPT_POSTFIELDSIZE, 0L);
    }
    if (![method isEqualToString:@"POST"]) {
      SYNC_OPTION(CURLOPT_CUSTOMREQUEST, method.UTF8String);
    }
  }
  SYNC_OPTION(CURLOPT_WRITEFUNCTION, ALNSynchronousWrite);
  SYNC_OPTION(CURLOPT_WRITEDATA, transfer);
  SYNC_OPTION(CURLOPT_HEADERFUNCTION, ALNSynchronousHeader);
  SYNC_OPTION(CURLOPT_HEADERDATA, transfer);
#undef SYNC_OPTION
  return result;
}

static NSData *ALNSynchronousCurlRequest(NSURLRequest *request, NSUInteger maxRedirects,
                                         NSURLResponse *__autoreleasing *response,
                                         NSString *__autoreleasing *receivedPhrase,
                                         NSError *__autoreleasing *error) {
  if (!ALNCurlGlobalReady()) {
    if (error) *error = ALNSynchronousURLError(NSURLErrorUnknown, @"libcurl could not initialize");
    return nil;
  }
  CURL *curl = curl_easy_init();
  if (!curl) {
    if (error) *error = ALNSynchronousURLError(NSURLErrorUnknown, @"libcurl could not initialize");
    return nil;
  }
  NSMutableData *body = [NSMutableData data];
  NSMutableDictionary *headers = [NSMutableDictionary dictionary];
  NSMutableString *httpVersion = [NSMutableString string];
  NSMutableString *reasonPhrase = [NSMutableString string];
  ALNSynchronousTransfer transfer = {(__bridge void *)body, (__bridge void *)headers,
      (__bridge void *)httpVersion, (__bridge void *)reasonPhrase, NO};
  NSData *requestBody = ALNSynchronousRequestBody(request);
  NSString *method = [request.HTTPMethod length] > 0 ? [request.HTTPMethod uppercaseString] : @"GET";
  NSString *urlString = request.URL.absoluteString ?: @"";
  NSDictionary *requestHeaders = request.allHTTPHeaderFields ?: @{};
  NSTimeInterval timeout = request.timeoutInterval > 0 ? request.timeoutInterval : 60;
  char message[CURL_ERROR_SIZE] = {0};
  struct curl_slist *headerList = NULL;
  CURLcode result = CURLE_OUT_OF_MEMORY;
  long status = 0;
  char *effectiveURL = NULL;
  BOOL hasContentType = NO;
  BOOL listOK = YES;

  for (NSString *name in requestHeaders) {
    NSString *line = [NSString stringWithFormat:@"%@: %@", name, requestHeaders[name]];
    struct curl_slist *next = curl_slist_append(headerList, line.UTF8String);
    if (!next) { listOK = NO; break; }
    headerList = next;
    if ([name caseInsensitiveCompare:@"Content-Type"] == NSOrderedSame) hasContentType = YES;
  }
  // Deterministic wire shape: no implicit Expect handshake and no implied form
  // Content-Type for bodies the caller left untyped.
  if (listOK) {
    struct curl_slist *next = curl_slist_append(headerList, "Expect:");
    listOK = next != NULL;
    if (next) headerList = next;
  }
  if (listOK && requestBody.length > 0 && !hasContentType) {
    struct curl_slist *next = curl_slist_append(headerList, "Content-Type:");
    listOK = next != NULL;
    if (next) headerList = next;
  }
  if (listOK) {
    result = ALNSynchronousConfigure(curl, urlString, method, requestBody, headerList, maxRedirects,
                                     timeout, message, &transfer);
  }
  if (result == CURLE_OK) {
    result = curl_easy_perform(curl);
  }
  if (result == CURLE_OK) {
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &effectiveURL);
  }

  NSData *resultData = nil;
  if (result == CURLE_OK) {
    NSURL *finalURL = effectiveURL ? [NSURL URLWithString:@(effectiveURL)] : nil;
    NSHTTPURLResponse *http = [[NSHTTPURLResponse alloc] initWithURL:finalURL ?: request.URL
                                                         statusCode:status
                                                        HTTPVersion:([httpVersion length] > 0 ? httpVersion : @"HTTP/1.1")
                                                       headerFields:headers];
    if (response) *response = http;
    if (receivedPhrase) *receivedPhrase = transfer.hasReasonPhrase ? [reasonPhrase copy] : nil;
    resultData = [body copy];
  } else if (error) {
    NSString *description = message[0] ? @(message) : @(curl_easy_strerror(result));
    *error = ALNSynchronousURLError(ALNSynchronousURLErrorCode(result), description);
  }
  curl_slist_free_all(headerList);
  curl_easy_cleanup(curl);
  return resultData;
}
#endif

@interface ALNHTTPClientResult ()
@property(nonatomic, strong, readwrite) NSHTTPURLResponse *response;
@property(nonatomic, copy, readwrite) NSData *body;
@property(nonatomic, copy, readwrite) NSString *receivedReasonPhrase;
@property(nonatomic, assign, readwrite) BOOL stoppedAtRedirectLimit;
- (instancetype)initWithResponse:(NSHTTPURLResponse *)response body:(NSData *)body
                         phrase:(NSString *)phrase stopped:(BOOL)stopped;
@end
@implementation ALNHTTPClientResult
- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use ALNSynchronousHTTPResult to obtain a result"];
  return nil;
}
- (instancetype)initWithResponse:(NSHTTPURLResponse *)response body:(NSData *)body
                         phrase:(NSString *)phrase stopped:(BOOL)stopped {
  self = [super init];
  if (self) {
    _response = response;
    _body = [body copy];
    _receivedReasonPhrase = [phrase copy];
    _stoppedAtRedirectLimit = stopped;
  }
  return self;
}
@end

static NSInteger ALNHTTPPort(NSURL *url) {
  return url.port ? url.port.integerValue : ([url.scheme.lowercaseString isEqualToString:@"https"] ? 443 : 80);
}

ALNHTTPClientResult *ALNSynchronousHTTPResult(NSURLRequest *request, NSUInteger maxRedirects,
                                             ALNHTTPRedirectLimitPolicy policy, NSError **error) {
  if (error) *error = nil;
  if (request.URL == nil || (policy != ALNHTTPRedirectLimitError && policy != ALNHTTPRedirectLimitReturnResponse)) {
    if (error) *error = ALNSynchronousURLError(NSURLErrorBadURL, @"invalid request URL or redirect policy");
    return nil;
  }
#if defined(GNUSTEP) || defined(__APPLE__)
  if (!ALNCurlGlobalReady() || (curl_version_info(CURLVERSION_NOW)->features &
      (CURL_VERSION_ASYNCHDNS | CURL_VERSION_SSL)) != (CURL_VERSION_ASYNCHDNS | CURL_VERSION_SSL)) {
    if (error) *error = ALNSynchronousURLError(NSURLErrorUnknown, @"HTTP result transport requires TLS and asynchronous DNS");
    return nil;
  }
  NSTimeInterval timeout = request.timeoutInterval > 0 ? request.timeoutInterval : 60;
  NSTimeInterval deadline = MetadataNow() + timeout;
  NSMutableURLRequest *hop = [request mutableCopy];
  // Consume a stream once so 307/308 can replay it.
  if (request.HTTPBodyStream && !request.HTTPBody) hop.HTTPBody = ALNSynchronousRequestBody(request);
  for (NSUInteger followed = 0;; followed++) {
    NSTimeInterval remaining = deadline - MetadataNow();
    if (!isfinite(remaining) || remaining <= 0) {
      if (error) *error = ALNSynchronousURLError(NSURLErrorTimedOut, @"HTTP total deadline exceeded");
      return nil;
    }
    hop.timeoutInterval = remaining;
    NSURLResponse *response = nil;
    NSString *phrase = nil;
    NSData *body = ALNSynchronousCurlRequest(hop, 0, &response, &phrase, error);
    if (!body) return nil;
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    NSInteger status = http.statusCode;
    NSString *location = nil;
    for (NSString *key in http.allHeaderFields) {
      if ([key caseInsensitiveCompare:@"Location"] == NSOrderedSame) location = http.allHeaderFields[key];
    }
    BOOL redirect = location.length > 0 && (status == 301 || status == 302 || status == 303 || status == 307 || status == 308);
    BOOL stopped = redirect && followed == maxRedirects;
    if (stopped && maxRedirects > 0 && policy == ALNHTTPRedirectLimitError) {
      if (error) *error = ALNSynchronousURLError(NSURLErrorHTTPTooManyRedirects, @"too many HTTP redirects");
      return nil;
    }
    if (!redirect || stopped) {
      return [[ALNHTTPClientResult alloc] initWithResponse:http body:body phrase:phrase stopped:stopped];
    }
    NSURL *next = [[NSURL URLWithString:location relativeToURL:hop.URL] absoluteURL];
    NSString *scheme = next.scheme.lowercaseString;
    if (!next.host.length || (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"])) {
      if (error) *error = ALNSynchronousURLError(NSURLErrorUnsupportedURL, @"redirect requires an HTTP or HTTPS URL");
      return nil;
    }
    BOOL sameOrigin = [hop.URL.scheme.lowercaseString isEqualToString:scheme] &&
        [hop.URL.host.lowercaseString isEqualToString:next.host.lowercaseString] && ALNHTTPPort(hop.URL) == ALNHTTPPort(next);
    if (!sameOrigin) {
      [hop setValue:nil forHTTPHeaderField:@"Authorization"];
      [hop setValue:nil forHTTPHeaderField:@"Cookie"];
    }
    [hop setValue:nil forHTTPHeaderField:@"Host"];
    NSString *method = hop.HTTPMethod.uppercaseString ?: @"GET";
    if ((status == 303 && ![method isEqualToString:@"HEAD"]) ||
        ((status == 301 || status == 302) && [method isEqualToString:@"POST"])) {
      hop.HTTPMethod = @"GET";
      hop.HTTPBody = nil;
      hop.HTTPBodyStream = nil;
      [hop setValue:nil forHTTPHeaderField:@"Content-Length"];
      [hop setValue:nil forHTTPHeaderField:@"Content-Type"];
      [hop setValue:nil forHTTPHeaderField:@"Transfer-Encoding"];
    }
    hop.URL = next;
  }
#else
  if (error) *error = ALNSynchronousURLError(NSURLErrorUnsupportedURL, @"HTTP result transport unavailable");
  return nil;
#endif
}

#if defined(__APPLE__)
@interface ALNSynchronousSessionDelegate : NSObject <NSURLSessionTaskDelegate>
@property(nonatomic, assign) NSUInteger maxRedirects;
@property(nonatomic, assign) NSUInteger redirectCount;
@property(nonatomic, assign) BOOL exceeded;
@end
@implementation ALNSynchronousSessionDelegate
- (void)URLSession:(NSURLSession *)session
                          task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response
                    newRequest:(NSURLRequest *)request
             completionHandler:(void (^)(NSURLRequest *_Nullable))completionHandler {
  if (self.redirectCount >= self.maxRedirects) {
    self.exceeded = self.maxRedirects > 0;
    completionHandler(nil);
    return;
  }
  self.redirectCount += 1;
  completionHandler(request);
}
@end
#endif

NSData *ALNSynchronousURLRequestFollowingRedirects(NSURLRequest *request, NSUInteger maxRedirects,
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
  if (request.URL == nil) {
    if (error != NULL) *error = ALNSynchronousURLError(NSURLErrorBadURL, @"request has no URL");
    return nil;
  }

#if defined(__APPLE__)
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  __block NSData *resultData = nil;
  __block NSURLResponse *resultResponse = nil;
  __block NSError *resultError = nil;

  ALNSynchronousSessionDelegate *delegate = [ALNSynchronousSessionDelegate new];
  delegate.maxRedirects = maxRedirects;
  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration
                                                        delegate:delegate
                                                   delegateQueue:nil];
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

  if (resultError == nil && delegate.exceeded) {
    resultError = ALNSynchronousURLError(NSURLErrorHTTPTooManyRedirects, @"too many HTTP redirects");
    resultData = nil;
    resultResponse = nil;
  }
  if (response != NULL) {
    *response = resultResponse;
  }
  if (error != NULL) {
    *error = resultError;
  }
  return resultData;
#elif defined(GNUSTEP)
  return ALNSynchronousCurlRequest(request, maxRedirects, response, NULL, error);
#else
  (void)maxRedirects;
  return [NSURLConnection sendSynchronousRequest:request returningResponse:response error:error];
#endif
}

NSData *ALNSynchronousURLRequest(NSURLRequest *request,
                                 NSURLResponse *__autoreleasing _Nullable *_Nullable response,
                                 NSError *__autoreleasing _Nullable *_Nullable error) {
  return ALNSynchronousURLRequestFollowingRedirects(request, ALNSynchronousURLRequestDefaultMaxRedirects,
                                                    response, error);
}
