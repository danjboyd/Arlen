#import "ALNCSRFMiddleware.h"

#import "ALNContext.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

static NSString *ALNCSRFTokenFromRandomBytes(void) {
  uint32_t partA = arc4random();
  uint32_t partB = arc4random();
  NSString *uuid = [[[NSUUID UUID] UUIDString] lowercaseString];
  uuid = [uuid stringByReplacingOccurrencesOfString:@"-" withString:@""];
  return [NSString stringWithFormat:@"%08x%08x%@", partA, partB, uuid];
}

static BOOL ALNIsSafeMethod(NSString *method) {
  NSString *upper = [method uppercaseString];
  return [upper isEqualToString:@"GET"] || [upper isEqualToString:@"HEAD"] ||
         [upper isEqualToString:@"OPTIONS"] || [upper isEqualToString:@"TRACE"];
}

@interface ALNCSRFMiddleware ()

@property(nonatomic, copy) NSString *headerName;
@property(nonatomic, copy) NSString *queryParamName;

@end

@implementation ALNCSRFMiddleware

- (instancetype)initWithHeaderName:(NSString *)headerName
                    queryParamName:(NSString *)queryParamName {
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

  NSString *provided = context.request.headers[self.headerName];
  if ([provided length] == 0) {
    provided = context.request.queryParams[self.queryParamName];
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
