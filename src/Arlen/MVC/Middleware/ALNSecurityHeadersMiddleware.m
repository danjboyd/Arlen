#import "ALNSecurityHeadersMiddleware.h"

#import "ALNContext.h"
#import "ALNResponse.h"
#import <dispatch/dispatch.h>

@interface ALNSecurityHeadersMiddleware ()

@property(nonatomic, copy) NSString *contentSecurityPolicy;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *resolvedResponseHeaders;

@end

static NSDictionary<NSString *, NSString *> *ALNSecurityHeadersDefaults(void) {
  static NSDictionary<NSString *, NSString *> *defaults = nil;
  static dispatch_once_t defaultsOnce;
  dispatch_once(&defaultsOnce, ^{
    defaults = @{
      @"X-Content-Type-Options" : @"nosniff",
      @"X-Frame-Options" : @"SAMEORIGIN",
      @"Referrer-Policy" : @"strict-origin-when-cross-origin",
      @"Cross-Origin-Opener-Policy" : @"same-origin",
      @"Cross-Origin-Resource-Policy" : @"same-site",
      @"X-Permitted-Cross-Domain-Policies" : @"none",
    };
  });
  return defaults;
}

@implementation ALNSecurityHeadersMiddleware

- (instancetype)initWithContentSecurityPolicy:(NSString *)contentSecurityPolicy {
  self = [super init];
  if (self) {
    _contentSecurityPolicy =
        [contentSecurityPolicy copy] ?: @"default-src 'self'";
    NSMutableDictionary *headers = [ALNSecurityHeadersDefaults() mutableCopy];
    if ([_contentSecurityPolicy length] > 0) {
      headers[@"Content-Security-Policy"] = _contentSecurityPolicy;
    }
    _resolvedResponseHeaders = [headers copy];
  }
  return self;
}

- (NSDictionary<NSString *, NSString *> *)responseHeaders {
  return self.resolvedResponseHeaders;
}

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  [context.response setHeadersIfMissing:[self responseHeaders]];
  return YES;
}

@end
