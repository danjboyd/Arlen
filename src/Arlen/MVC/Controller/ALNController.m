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

@end
