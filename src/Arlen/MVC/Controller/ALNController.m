#import "ALNController.h"

#import "ALNContext.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNView.h"
#import "ALNPerf.h"

@implementation ALNController

+ (NSJSONWritingOptions)jsonWritingOptions {
  return 0;
}

- (BOOL)renderTemplate:(NSString *)templateName
               context:(NSDictionary *)context
                 error:(NSError **)error {
  return [self renderTemplate:templateName context:context layout:nil error:error];
}

- (BOOL)renderTemplate:(NSString *)templateName
               context:(NSDictionary *)context
                layout:(NSString *)layoutName
                 error:(NSError **)error {
  [self.context.perfTrace startStage:@"render"];
  NSString *rendered =
      [ALNView renderTemplate:templateName context:context layout:layoutName error:error];
  [self.context.perfTrace endStage:@"render"];
  if (rendered == nil) {
    return NO;
  }
  [self.context.response setHeader:@"Content-Type" value:@"text/html; charset=utf-8"];
  [self.context.response setTextBody:rendered];
  self.context.response.committed = YES;
  return YES;
}

- (BOOL)renderJSON:(id)object error:(NSError **)error {
  NSJSONWritingOptions options = [[self class] jsonWritingOptions];
  BOOL ok = [self.context.response setJSONBody:object options:options error:error];
  if (ok) {
    self.context.response.committed = YES;
  }
  return ok;
}

- (void)renderText:(NSString *)text {
  [self.context.response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  [self.context.response setTextBody:text ?: @""];
  self.context.response.committed = YES;
}

- (void)redirectTo:(NSString *)location status:(NSInteger)statusCode {
  NSInteger code = (statusCode == 0) ? 302 : statusCode;
  self.context.response.statusCode = code;
  [self.context.response setHeader:@"Location" value:location ?: @"/"];
  self.context.response.committed = YES;
}

- (void)setStatus:(NSInteger)statusCode {
  self.context.response.statusCode = statusCode;
}

- (BOOL)hasRendered {
  return self.context.response.committed;
}

- (NSMutableDictionary *)session {
  [self.context markSessionDirty];
  return [self.context session];
}

- (NSString *)csrfToken {
  return [self.context csrfToken];
}

- (void)markSessionDirty {
  [self.context markSessionDirty];
}

- (NSDictionary *)params {
  return [self.context allParams];
}

- (id)paramValueForName:(NSString *)name {
  return [self.context paramValueForName:name];
}

- (NSString *)stringParamForName:(NSString *)name {
  return [self.context stringParamForName:name];
}

- (BOOL)requireStringParam:(NSString *)name value:(NSString **)value {
  return [self.context requireStringParam:name value:value];
}

- (BOOL)requireIntegerParam:(NSString *)name value:(NSInteger *)value {
  return [self.context requireIntegerParam:name value:value];
}

- (void)addValidationErrorForField:(NSString *)field
                              code:(NSString *)code
                           message:(NSString *)message {
  [self.context addValidationErrorForField:field code:code message:message];
}

- (NSArray *)validationErrors {
  return [self.context validationErrors];
}

- (BOOL)renderValidationErrors {
  NSArray *issues = [self validationErrors];
  if ([issues count] == 0) {
    return NO;
  }

  NSString *requestID = [self.context.stash[@"request_id"] isKindOfClass:[NSString class]]
                            ? self.context.stash[@"request_id"]
                            : @"";
  NSDictionary *payload = @{
    @"error" : @{
      @"code" : @"validation_failed",
      @"message" : @"Validation failed",
      @"request_id" : requestID ?: @"",
    },
    @"details" : issues
  };

  NSError *error = nil;
  BOOL ok = [self.context.response setJSONBody:payload options:0 error:&error];
  if (!ok) {
    [self.context.response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    [self.context.response setTextBody:@"validation failed\n"];
  }
  self.context.response.statusCode = 422;
  self.context.response.committed = YES;
  return ok;
}

@end
