#import "ALNSecurityHeadersMiddleware.h"

#import "ALNContext.h"
#import "ALNResponse.h"

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
  [self ensureHeader:@"X-Content-Type-Options" value:@"nosniff" response:response];
  [self ensureHeader:@"X-Frame-Options" value:@"SAMEORIGIN" response:response];
  [self ensureHeader:@"Referrer-Policy" value:@"strict-origin-when-cross-origin" response:response];
  [self ensureHeader:@"Cross-Origin-Opener-Policy" value:@"same-origin" response:response];
  [self ensureHeader:@"Cross-Origin-Resource-Policy" value:@"same-site" response:response];
  [self ensureHeader:@"X-Permitted-Cross-Domain-Policies" value:@"none" response:response];
  if ([self.contentSecurityPolicy length] > 0) {
    [self ensureHeader:@"Content-Security-Policy" value:self.contentSecurityPolicy response:response];
  }
  return YES;
}

@end
