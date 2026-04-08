#import "ALNCSRFMiddleware.h"

#import "ALNContext.h"
#import "ALNPlatform.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

static NSString *ALNCSRFTokenFromRandomBytes(void) {
  uint32_t parts[2] = {0, 0};
  if (!ALNPlatformFillRandomBytes(parts, sizeof(parts))) {
    parts[0] = (uint32_t)[[NSProcessInfo processInfo] processIdentifier];
    parts[1] = (uint32_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
  }
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  uuid = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  return [NSString stringWithFormat:@"%08x%08x%@", parts[0], parts[1], uuid];
}

static BOOL ALNIsSafeMethod(NSString *method) {
  NSString *upper = [method uppercaseString];
  return [upper isEqualToString:@"GET"] || [upper isEqualToString:@"HEAD"] ||
         [upper isEqualToString:@"OPTIONS"] || [upper isEqualToString:@"TRACE"];
}

static NSString *ALNCSRFTokenFromFormBody(ALNRequest *request, NSString *queryParamName) {
  if (request == nil || ![queryParamName isKindOfClass:[NSString class]] ||
      [queryParamName length] == 0) {
    return nil;
  }
  NSString *value = request.formParams[queryParamName];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

@interface ALNCSRFMiddleware ()

@property(nonatomic, copy) NSString *headerName;
@property(nonatomic, copy) NSString *queryParamName;
@property(nonatomic, assign) BOOL allowQueryParamFallback;

@end

@implementation ALNCSRFMiddleware

- (instancetype)initWithHeaderName:(NSString *)headerName
                    queryParamName:(NSString *)queryParamName {
  return [self initWithHeaderName:headerName
                   queryParamName:queryParamName
        allowQueryParamFallback:NO];
}

- (instancetype)initWithHeaderName:(NSString *)headerName
                    queryParamName:(NSString *)queryParamName
         allowQueryParamFallback:(BOOL)allowQueryParamFallback {
  self = [super init];
  if (self) {
    NSString *resolvedHeader = [[headerName lowercaseString] copy];
    if ([resolvedHeader length] == 0) {
      resolvedHeader = @"x-csrf-token";
    }
    _headerName = resolvedHeader;

    _queryParamName = [queryParamName copy];
    if ([_queryParamName length] == 0) {
      _queryParamName = @"csrf_token";
    }
    _allowQueryParamFallback = allowQueryParamFallback;
  }
  return self;
}

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSMutableDictionary *session = [context session];

  NSString *token = session[@"_csrf_token"];
  if (![token isKindOfClass:[NSString class]] || [token length] == 0) {
    token = ALNCSRFTokenFromRandomBytes();
    session[@"_csrf_token"] = token;
    [context markSessionDirty];
  }
  context.stash[ALNContextCSRFTokenStashKey] = token;

  if (ALNIsSafeMethod(context.request.method ?: @"GET")) {
    return YES;
  }

  NSString *provided = [context.request headerValueForName:self.headerName];
  if ([provided length] == 0) {
    provided = ALNCSRFTokenFromFormBody(context.request, self.queryParamName);
  }
  if ([provided length] == 0) {
    if (self.allowQueryParamFallback) {
      provided = context.request.queryParams[self.queryParamName];
    }
  }

  if ([provided isKindOfClass:[NSString class]] && [provided isEqualToString:token]) {
    return YES;
  }

  context.response.statusCode = 403;
  [context.response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  [context.response setTextBody:@"csrf verification failed\n"];
  context.response.committed = YES;
  return NO;
}

@end
