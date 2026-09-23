#import "ALNSecurityHeadersMiddleware.h"

#import "ALNContext.h"
#import "ALNResponse.h"
#import <dispatch/dispatch.h>

@interface ALNSecurityHeadersMiddleware ()

@property(nonatomic, copy) NSString *contentSecurityPolicy;

@end

@implementation ALNSecurityHeadersMiddleware

- (instancetype)initWithContentSecurityPolicy:(NSString *)contentSecurityPolicy {
  self = [super init];
  if (self) {
    _contentSecurityPolicy =
        [contentSecurityPolicy copy] ?: @"default-src 'self'";
  }
  return self;
}

- (void)ensureHeader:(NSString *)name value:(NSString *)value response:(ALNResponse *)response {
  if ([response headerForName:name] == nil) {
    [response setHeader:name value:value];
  }
}

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  ALNResponse *response = context.response;
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
  [response setHeadersIfMissing:defaults];
  if ([self.contentSecurityPolicy length] > 0) {
    [self ensureHeader:@"Content-Security-Policy" value:self.contentSecurityPolicy response:response];
  }
  return YES;
}

@end
