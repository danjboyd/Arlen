#import "ALNHTTPClient.h"
#import "ALNPlatform.h"

#import "ALNJSONSerialization.h"
#import "ALNLogger.h"
#include <math.h>

NSString *const ALNHTTPClientErrorDomain = @"Arlen.HTTPClient";

// Internal seams in ALNHTTPCompat.m.
extern NSTimeInterval ALNHTTPMonotonicNow(void);
extern NSData *ALNHTTPClientPerformHop(NSURLRequest *request, NSUInteger maxBytes, NSHTTPURLResponse **response,
                                       NSString **receivedPhrase, NSError **error);

@interface ALNHTTPClientResult (ALNHTTPClientInternal)
- (instancetype)initWithResponse:(NSHTTPURLResponse *)response body:(NSData *)body
                         phrase:(NSString *)phrase stopped:(BOOL)stopped;
@end

static NSError *HCError(ALNHTTPClientErrorCode code, NSString *reason) {
  return [NSError errorWithDomain:ALNHTTPClientErrorDomain code:code
                         userInfo:@{NSLocalizedDescriptionKey : reason}];
}

static id HCFail(NSError **error, ALNHTTPClientErrorCode code, NSString *reason) {
  if (error) *error = HCError(code, reason);
  return nil;
}

// A non-negative integer from an NSNumber (not a boolean) or a decimal string,
// as plist configuration gives it; -1 when absent, -2 when invalid.
static long long HCInteger(id value) {
  if (value == nil) return -1;
  if ([value isKindOfClass:[NSString class]]) {
    NSScanner *scanner = [NSScanner scannerWithString:value];
    long long parsed = 0;
    return ([scanner scanLongLong:&parsed] && scanner.isAtEnd && parsed >= 0) ? parsed : -2;
  }
  if (![value isKindOfClass:[NSNumber class]] || ALNNumberIsBoolean(value)) return -2;
  double number = [value doubleValue];
  return (isfinite(number) && number >= 0 && number == floor(number) && number < 9.0e15) ? (long long)number : -2;
}

static NSInteger HCDefaultPort(NSString *scheme) {
  return [scheme isEqualToString:@"https"] ? 443 : 80;
}

// "host" or "host:port", lower-cased; nil when the entry is not a plain host.
static NSString *HCNormalizedHostEntry(id value) {
  if (![value isKindOfClass:[NSString class]]) return nil;
  NSString *entry = [value lowercaseString];
  NSArray *parts = [entry componentsSeparatedByString:@":"];
  if (parts.count > 2) return nil;
  NSString *host = parts[0];
  NSCharacterSet *invalid =
      [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789.-"] invertedSet];
  if (host.length == 0 || host.length > 253 || [host rangeOfCharacterFromSet:invalid].location != NSNotFound ||
      [host hasPrefix:@"."] || [host hasSuffix:@"."] || [host hasPrefix:@"-"] || [host containsString:@".."]) {
    return nil;
  }
  if (parts.count == 2) {
    long long port = HCInteger(parts[1]);
    if (port < 1 || port > 65535 || ![parts[1] isEqualToString:[NSString stringWithFormat:@"%lld", port]]) return nil;
  }
  return entry;
}

// "host:port" with the scheme's default port filled in, for allowlist checks and errors.
static NSString *HCHostPort(NSURL *url) {
  NSInteger port = url.port ? url.port.integerValue : HCDefaultPort(url.scheme.lowercaseString);
  return [NSString stringWithFormat:@"%@:%ld", url.host.lowercaseString ?: @"", (long)port];
}

static BOOL HCHasHeader(NSURLRequest *request, NSString *name) {
  for (NSString *key in request.allHTTPHeaderFields) {
    if ([key caseInsensitiveCompare:name] == NSOrderedSame) return YES;
  }
  return NO;
}

@implementation ALNHTTPClient

- (instancetype)initWithConfiguration:(NSDictionary *)configuration error:(NSError **)error {
  if (![configuration isKindOfClass:[NSDictionary class]]) {
    return HCFail(error, ALNHTTPClientErrorInvalidConfiguration, @"HTTP client configuration must be a dictionary");
  }
  NSSet *known = [NSSet setWithArray:@[ @"allowedHosts", @"timeoutSeconds", @"maxResponseBytes", @"maxRedirects",
                                        @"allowHTTP" ]];
  for (id key in configuration) {
    if (![known containsObject:key]) {
      return HCFail(error, ALNHTTPClientErrorInvalidConfiguration,
                    [NSString stringWithFormat:@"HTTP client configuration has unknown key %@", key]);
    }
  }
  id hosts = configuration[@"allowedHosts"];
  NSMutableArray *allowed = [NSMutableArray array];
  if ([hosts isKindOfClass:[NSArray class]]) {
    for (id entry in hosts) {
      NSString *normalized = HCNormalizedHostEntry(entry);
      if (!normalized) {
        return HCFail(error, ALNHTTPClientErrorInvalidConfiguration,
                      @"HTTP client allowedHosts entries must be hostnames, optionally host:port");
      }
      if (![allowed containsObject:normalized]) [allowed addObject:normalized];
    }
  }
  if (allowed.count == 0) {
    return HCFail(error, ALNHTTPClientErrorInvalidConfiguration, @"HTTP client requires a nonempty allowedHosts list");
  }
  long long timeout = HCInteger(configuration[@"timeoutSeconds"]);
  long long maxBytes = HCInteger(configuration[@"maxResponseBytes"]);
  long long redirects = HCInteger(configuration[@"maxRedirects"]);
  if (timeout == -2 || timeout == 0 || timeout > 300) {
    return HCFail(error, ALNHTTPClientErrorInvalidConfiguration, @"HTTP client timeoutSeconds must be 1 to 300");
  }
  if (maxBytes == -2 || maxBytes == 0 || maxBytes > 67108864) {
    return HCFail(error, ALNHTTPClientErrorInvalidConfiguration,
                  @"HTTP client maxResponseBytes must be 1 to 67108864");
  }
  if (redirects == -2 || redirects > 10) {
    return HCFail(error, ALNHTTPClientErrorInvalidConfiguration, @"HTTP client maxRedirects must be 0 to 10");
  }
  id allowHTTP = configuration[@"allowHTTP"];
  if (allowHTTP && ![allowHTTP isKindOfClass:[NSNumber class]]) {
    return HCFail(error, ALNHTTPClientErrorInvalidConfiguration, @"HTTP client allowHTTP must be a boolean");
  }
  self = [super init];
  if (self) {
    _allowedHosts = [allowed copy];
    _timeout = timeout > 0 ? (NSTimeInterval)timeout : 10;
    _maxResponseBytes = maxBytes > 0 ? (NSUInteger)maxBytes : 1048576;
    _maxRedirects = redirects > 0 ? (NSUInteger)redirects : 0;
    _allowHTTP = [allowHTTP boolValue];
  }
  return self;
}

- (instancetype)init {
  [NSException raise:NSInvalidArgumentException format:@"Use initWithConfiguration:error:"];
  return nil;
}

// Nil when the URL may be requested; otherwise the reason.
- (NSError *)rejectionForURL:(NSURL *)url {
  NSString *scheme = url.scheme.lowercaseString;
  if (![scheme isEqualToString:@"https"] && !([scheme isEqualToString:@"http"] && self.allowHTTP)) {
    return HCError(ALNHTTPClientErrorInvalidRequest,
                   self.allowHTTP ? @"URL must use http or https" : @"URL must use https");
  }
  if (url.user.length || url.password.length) {
    return HCError(ALNHTTPClientErrorInvalidRequest, @"URL must not carry credentials");
  }
  NSString *host = url.host.lowercaseString;
  if (!HCNormalizedHostEntry(host)) return HCError(ALNHTTPClientErrorInvalidRequest, @"URL host is not a plain hostname");
  NSInteger port = url.port ? url.port.integerValue : HCDefaultPort(scheme);
  NSString *withPort = HCHostPort(url);
  BOOL allowed = [self.allowedHosts containsObject:withPort] ||
                 ([self.allowedHosts containsObject:host] && port == HCDefaultPort(scheme));
  if (!allowed) {
    return HCError(ALNHTTPClientErrorHostNotAllowed, [NSString stringWithFormat:@"Host not allowed: %@", withPort]);
  }
  return nil;
}

- (NSError *)errorForTransportFailure:(NSError *)failure {
  switch (failure.code) {
    case NSURLErrorTimedOut: return HCError(ALNHTTPClientErrorTimedOut, @"Request timed out");
    case NSURLErrorDataLengthExceedsMaximum: return HCError(ALNHTTPClientErrorResponseTooLarge, @"Response exceeds maxResponseBytes");
    case NSURLErrorCannotFindHost: return HCError(ALNHTTPClientErrorTransport, @"Host could not be resolved");
    case NSURLErrorCannotConnectToHost: return HCError(ALNHTTPClientErrorTransport, @"Connection refused");
    case NSURLErrorNetworkConnectionLost: return HCError(ALNHTTPClientErrorTransport, @"Connection lost");
    case NSURLErrorSecureConnectionFailed: return HCError(ALNHTTPClientErrorTransport, @"TLS connection failed");
    default: return HCError(ALNHTTPClientErrorTransport, @"Request failed");
  }
}

- (void)logRequest:(NSURLRequest *)request result:(ALNHTTPClientResult *)result error:(NSError *)error
         redirects:(NSUInteger)redirects started:(NSTimeInterval)started {
  if (!self.logger) return;
  NSMutableDictionary *fields = [NSMutableDictionary dictionaryWithDictionary:@{
    @"event" : @"http_client.request",
    @"method" : request.HTTPMethod.uppercaseString ?: @"GET",
    @"host" : request.URL.host.lowercaseString ?: @"",
    @"path" : request.URL.path ?: @"",
    @"redirects" : @(redirects),
    @"duration_ms" : @((NSInteger)llround(MAX(0, ALNHTTPMonotonicNow() - started) * 1000)),
  }];
  if (result) {
    fields[@"status"] = @(result.response.statusCode);
    fields[@"bytes"] = @(result.body.length);
    [self.logger info:@"outbound http request" fields:fields];
  } else {
    fields[@"error_code"] = @(error.code);
    fields[@"reason"] = error.localizedDescription ?: @"";
    [self.logger warn:@"outbound http request failed" fields:fields];
  }
}

- (ALNHTTPClientResult *)performRequest:(NSURLRequest *)request error:(NSError **)error {
  NSTimeInterval started = ALNHTTPMonotonicNow();
  NSUInteger followed = 0;
  NSError *failure = nil;
  ALNHTTPClientResult *result = [self resultForRequest:request started:started followed:&followed error:&failure];
  if (request.URL) [self logRequest:request result:result error:failure redirects:followed started:started];
  if (error) *error = failure;
  return result;
}

- (ALNHTTPClientResult *)resultForRequest:(NSURLRequest *)request started:(NSTimeInterval)started
                                 followed:(NSUInteger *)followed error:(NSError **)error {
  if (![request isKindOfClass:[NSURLRequest class]] || !request.URL) {
    return HCFail(error, ALNHTTPClientErrorInvalidRequest, @"Request needs a URL");
  }
  NSString *method = request.HTTPMethod.length ? request.HTTPMethod.uppercaseString : @"GET";
  if (![@[ @"GET", @"HEAD", @"POST", @"PUT", @"PATCH", @"DELETE" ] containsObject:method]) {
    return HCFail(error, ALNHTTPClientErrorInvalidRequest, @"Unsupported HTTP method");
  }
  NSError *rejection = [self rejectionForURL:request.URL];
  if (rejection) { if (error) *error = rejection; return nil; }
  if (!isfinite(started)) return HCFail(error, ALNHTTPClientErrorTransport, @"Monotonic clock unavailable");
  // A credential must not be replayed to wherever a server points it.
  BOOL credentials = HCHasHeader(request, @"Authorization") || HCHasHeader(request, @"Cookie");
  NSMutableURLRequest *hop = [request mutableCopy];
  hop.HTTPMethod = method;
  [hop setValue:nil forHTTPHeaderField:@"Host"];
  for (;;) {
    NSTimeInterval remaining = started + self.timeout - ALNHTTPMonotonicNow();
    if (!isfinite(remaining) || remaining <= 0) return HCFail(error, ALNHTTPClientErrorTimedOut, @"Request timed out");
    hop.timeoutInterval = remaining;
    NSHTTPURLResponse *response = nil;
    NSString *phrase = nil;
    NSError *transportError = nil;
    NSData *body = ALNHTTPClientPerformHop(hop, self.maxResponseBytes, &response, &phrase, &transportError);
    if (!body) {
      if (error) *error = [self errorForTransportFailure:transportError];
      return nil;
    }
    NSInteger status = response.statusCode;
    NSString *location = nil;
    for (NSString *key in response.allHeaderFields) {
      if ([key caseInsensitiveCompare:@"Location"] == NSOrderedSame) location = response.allHeaderFields[key];
    }
    BOOL redirect = location.length > 0 && (status == 301 || status == 302 || status == 303 || status == 307 || status == 308);
    if (!redirect || self.maxRedirects == 0 || credentials) {
      return [[ALNHTTPClientResult alloc] initWithResponse:response body:body phrase:phrase stopped:redirect];
    }
    if (*followed == self.maxRedirects) {
      return HCFail(error, ALNHTTPClientErrorTooManyRedirects, @"Too many redirects");
    }
    NSURL *next = [[NSURL URLWithString:location relativeToURL:hop.URL] absoluteURL];
    NSError *redirectRejection = next ? [self rejectionForURL:next] : nil;
    if (!next || redirectRejection) {
      NSString *reason = redirectRejection.code == ALNHTTPClientErrorHostNotAllowed
                             ? [@"Redirect to a host that is not allowed: " stringByAppendingString:HCHostPort(next)]
                             : @"Redirect target is not an allowed URL";
      return HCFail(error, ALNHTTPClientErrorRedirectNotAllowed, reason);
    }
    (*followed)++;
    if ((status == 303 && ![method isEqualToString:@"HEAD"]) ||
        ((status == 301 || status == 302) && [method isEqualToString:@"POST"])) {
      method = @"GET";
      hop.HTTPMethod = @"GET";
      hop.HTTPBody = nil;
      hop.HTTPBodyStream = nil;
      [hop setValue:nil forHTTPHeaderField:@"Content-Length"];
      [hop setValue:nil forHTTPHeaderField:@"Content-Type"];
      [hop setValue:nil forHTTPHeaderField:@"Transfer-Encoding"];
    }
    hop.URL = next;
  }
}

- (ALNHTTPClientResult *)GETURL:(NSURL *)url headers:(NSDictionary *)headers error:(NSError **)error {
  if (![url isKindOfClass:[NSURL class]]) return HCFail(error, ALNHTTPClientErrorInvalidRequest, @"Request needs a URL");
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = @"GET";
  for (NSString *name in headers) [request setValue:headers[name] forHTTPHeaderField:name];
  return [self performRequest:request error:error];
}

- (ALNHTTPClientResult *)POSTJSONObject:(id)object toURL:(NSURL *)url headers:(NSDictionary *)headers
                                  error:(NSError **)error {
  if (![url isKindOfClass:[NSURL class]]) return HCFail(error, ALNHTTPClientErrorInvalidRequest, @"Request needs a URL");
  NSData *body = object ? [ALNJSONSerialization dataWithJSONObject:object options:0 error:NULL] : nil;
  if (!body) return HCFail(error, ALNHTTPClientErrorInvalidRequest, @"Request body is not JSON serializable");
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = @"POST";
  request.HTTPBody = body;
  for (NSString *name in headers) [request setValue:headers[name] forHTTPHeaderField:name];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  return [self performRequest:request error:error];
}

@end
