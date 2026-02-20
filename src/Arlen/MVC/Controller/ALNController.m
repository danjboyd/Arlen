#import "ALNController.h"

#import "ALNContext.h"
#import "ALNPageState.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNView.h"
#import "ALNPerf.h"

@implementation ALNController

static NSDictionary *ALNTemplateContextFromStash(NSDictionary *stash) {
  NSMutableDictionary *context = [NSMutableDictionary dictionary];
  for (id key in stash ?: @{}) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *name = (NSString *)key;
    if ([name hasPrefix:@"aln."] || [name isEqualToString:@"request_id"]) {
      continue;
    }
    id value = stash[key];
    if (value != nil) {
      context[name] = value;
    }
  }
  return [NSDictionary dictionaryWithDictionary:context];
}

static NSString *ALNJSONStringFromObject(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"";
  }
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([NSJSONSerialization isValidJSONObject:value]) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (data != nil) {
      NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      if ([json length] > 0) {
        return json;
      }
    }
  }
  return [value description] ?: @"";
}

+ (NSJSONWritingOptions)jsonWritingOptions {
  return 0;
}

- (BOOL)renderTemplate:(NSString *)templateName
               context:(NSDictionary *)context
                 error:(NSError **)error {
  return [self renderTemplate:templateName context:context layout:nil error:error];
}

- (BOOL)renderTemplate:(NSString *)templateName error:(NSError **)error {
  return [self renderTemplate:templateName
                      context:ALNTemplateContextFromStash(self.context.stash)
                        error:error];
}

- (BOOL)renderTemplate:(NSString *)templateName
               context:(NSDictionary *)context
                layout:(NSString *)layoutName
                 error:(NSError **)error {
  BOOL strictLocals =
      [self.context.stash[ALNContextEOCStrictLocalsStashKey] boolValue];
  BOOL strictStringify =
      [self.context.stash[ALNContextEOCStrictStringifyStashKey] boolValue];
  [self.context.perfTrace startStage:@"render"];
  NSString *rendered = [ALNView renderTemplate:templateName
                                       context:context
                                        layout:layoutName
                                  strictLocals:strictLocals
                               strictStringify:strictStringify
                                         error:error];
  [self.context.perfTrace endStage:@"render"];
  if (rendered == nil) {
    return NO;
  }
  [self.context.response setHeader:@"Content-Type" value:@"text/html; charset=utf-8"];
  [self.context.response setTextBody:rendered];
  self.context.response.committed = YES;
  return YES;
}

- (BOOL)renderTemplate:(NSString *)templateName
                layout:(NSString *)layoutName
                 error:(NSError **)error {
  return [self renderTemplate:templateName
                      context:ALNTemplateContextFromStash(self.context.stash)
                       layout:layoutName
                        error:error];
}

- (void)stashValue:(id)value forKey:(NSString *)key {
  if ([key length] == 0) {
    return;
  }
  if (value == nil) {
    [self.context.stash removeObjectForKey:key];
    return;
  }
  self.context.stash[key] = value;
}

- (void)stashValues:(NSDictionary *)values {
  for (id key in values ?: @{}) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    [self stashValue:values[key] forKey:key];
  }
}

- (id)stashValueForKey:(NSString *)key {
  if ([key length] == 0) {
    return nil;
  }
  return self.context.stash[key];
}

- (BOOL)renderNegotiatedTemplate:(NSString *)templateName
                         context:(NSDictionary *)context
                      jsonObject:(id)jsonObject
                           error:(NSError **)error {
  if ([self.context wantsJSON]) {
    id payload = jsonObject ?: context ?: @{};
    return [self renderJSON:payload error:error];
  }
  NSDictionary *effectiveContext = context ?: ALNTemplateContextFromStash(self.context.stash);
  return [self renderTemplate:templateName context:effectiveContext error:error];
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

- (void)renderSSEEvents:(NSArray *)events {
  NSMutableString *body = [NSMutableString string];
  for (id value in events ?: @[]) {
    NSDictionary *event = [value isKindOfClass:[NSDictionary class]] ? value : @{};
    NSString *eventName = [event[@"event"] isKindOfClass:[NSString class]] ? event[@"event"] : @"";
    NSString *eventID = [event[@"id"] isKindOfClass:[NSString class]] ? event[@"id"] : @"";
    NSString *data = ALNJSONStringFromObject(event[@"data"]);
    NSString *retry =
        [event[@"retry"] respondsToSelector:@selector(integerValue)]
            ? [NSString stringWithFormat:@"%ld", (long)[event[@"retry"] integerValue]]
            : @"";

    if ([eventID length] > 0) {
      [body appendFormat:@"id: %@\n", eventID];
    }
    if ([eventName length] > 0) {
      [body appendFormat:@"event: %@\n", eventName];
    }
    if ([retry length] > 0) {
      [body appendFormat:@"retry: %@\n", retry];
    }

    NSString *normalizedData = data ?: @"";
    NSArray *dataLines =
        [normalizedData componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if ([dataLines count] == 0) {
      [body appendString:@"data:\n"];
    } else {
      for (NSString *line in dataLines) {
        [body appendFormat:@"data: %@\n", line ?: @""];
      }
    }
    [body appendString:@"\n"];
  }

  [self.context.response setStatusCode:200];
  [self.context.response setHeader:@"Content-Type" value:@"text/event-stream; charset=utf-8"];
  [self.context.response setHeader:@"Cache-Control" value:@"no-cache"];
  [self.context.response setHeader:@"Connection" value:@"keep-alive"];
  [self.context.response setHeader:@"X-Accel-Buffering" value:@"no"];
  [self.context.response setTextBody:body];
  self.context.response.committed = YES;
}

- (void)acceptWebSocketEcho {
  [self.context.response setStatusCode:101];
  [self.context.response setHeader:@"Connection" value:@"Upgrade"];
  [self.context.response setHeader:@"Upgrade" value:@"websocket"];
  [self.context.response setHeader:@"X-Arlen-WebSocket-Mode" value:@"echo"];
  [self.context.response setHeader:@"Content-Type" value:@""];
  [self.context.response.bodyData setLength:0];
  self.context.response.committed = YES;
}

- (void)acceptWebSocketChannel:(NSString *)channel {
  NSString *normalized = [channel isKindOfClass:[NSString class]] ? channel : @"";
  normalized =
      [normalized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized length] == 0) {
    normalized = @"default";
  }

  [self.context.response setStatusCode:101];
  [self.context.response setHeader:@"Connection" value:@"Upgrade"];
  [self.context.response setHeader:@"Upgrade" value:@"websocket"];
  [self.context.response setHeader:@"X-Arlen-WebSocket-Mode" value:@"channel"];
  [self.context.response setHeader:@"X-Arlen-WebSocket-Channel" value:[normalized lowercaseString]];
  [self.context.response setHeader:@"Content-Type" value:@""];
  [self.context.response.bodyData setLength:0];
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

- (NSDictionary *)validatedParams {
  return [self.context validatedParams];
}

- (id)validatedValueForName:(NSString *)name {
  return [self.context validatedValueForName:name];
}

- (NSDictionary *)authClaims {
  return [self.context authClaims];
}

- (NSArray *)authScopes {
  return [self.context authScopes];
}

- (NSArray *)authRoles {
  return [self.context authRoles];
}

- (NSString *)authSubject {
  return [self.context authSubject];
}

- (id<ALNJobAdapter>)jobsAdapter {
  return [self.context jobsAdapter];
}

- (id<ALNCacheAdapter>)cacheAdapter {
  return [self.context cacheAdapter];
}

- (id<ALNLocalizationAdapter>)localizationAdapter {
  return [self.context localizationAdapter];
}

- (id<ALNMailAdapter>)mailAdapter {
  return [self.context mailAdapter];
}

- (id<ALNAttachmentAdapter>)attachmentAdapter {
  return [self.context attachmentAdapter];
}

- (NSString *)localizedStringForKey:(NSString *)key
                             locale:(NSString *)locale
                     fallbackLocale:(NSString *)fallbackLocale
                       defaultValue:(NSString *)defaultValue
                          arguments:(NSDictionary *)arguments {
  return [self.context localizedStringForKey:key
                                      locale:locale
                              fallbackLocale:fallbackLocale
                                defaultValue:defaultValue
                                   arguments:arguments];
}

- (ALNPageState *)pageStateForKey:(NSString *)pageKey {
  return [self.context pageStateForKey:pageKey];
}

@end
