#import "ALNResponseEnvelopeMiddleware.h"

#import "ALNContext.h"
#import "ALNJSONSerialization.h"
#import "ALNResponse.h"

@interface ALNResponseEnvelopeMiddleware ()

@property(nonatomic, assign) BOOL includeRequestID;

@end

@implementation ALNResponseEnvelopeMiddleware

- (instancetype)init {
  return [self initWithIncludeRequestID:YES];
}

- (instancetype)initWithIncludeRequestID:(BOOL)includeRequestID {
  self = [super init];
  if (self) {
    _includeRequestID = includeRequestID;
  }
  return self;
}

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)context;
  (void)error;
  return YES;
}

- (BOOL)responseLooksLikeJSON:(ALNResponse *)response {
  NSString *contentType = [[response headerForName:@"Content-Type"] lowercaseString] ?: @"";
  return [contentType containsString:@"application/json"] || [contentType containsString:@"text/json"];
}

- (NSDictionary *)normalizedMetaFromEnvelope:(NSDictionary *)envelope context:(ALNContext *)context {
  NSMutableDictionary *meta = [NSMutableDictionary dictionary];
  NSDictionary *existingMeta = [envelope[@"meta"] isKindOfClass:[NSDictionary class]] ? envelope[@"meta"] : nil;
  if (existingMeta != nil) {
    [meta addEntriesFromDictionary:existingMeta];
  }
  if (self.includeRequestID) {
    NSString *requestID = [context.stash[@"request_id"] isKindOfClass:[NSString class]] ? context.stash[@"request_id"] : @"";
    if ([requestID length] > 0 && meta[@"request_id"] == nil) {
      meta[@"request_id"] = requestID;
    }
  }
  return [NSDictionary dictionaryWithDictionary:meta];
}

- (NSDictionary *)envelopedPayloadFromJSON:(id)parsed
                                   context:(ALNContext *)context
                                    status:(NSInteger)statusCode {
  BOOL alreadyEnveloped = [parsed isKindOfClass:[NSDictionary class]] &&
                          (((NSDictionary *)parsed)[@"data"] != nil || ((NSDictionary *)parsed)[@"error"] != nil);

  NSMutableDictionary *envelope = [NSMutableDictionary dictionary];
  if (alreadyEnveloped) {
    [envelope addEntriesFromDictionary:(NSDictionary *)parsed];
  } else if (statusCode >= 400) {
    envelope[@"error"] = parsed ?: [NSNull null];
  } else {
    envelope[@"data"] = parsed ?: [NSNull null];
  }

  NSDictionary *meta = [self normalizedMetaFromEnvelope:envelope context:context];
  if ([meta count] > 0) {
    envelope[@"meta"] = meta;
  }
  return [NSDictionary dictionaryWithDictionary:envelope];
}

- (void)didProcessContext:(ALNContext *)context {
  ALNResponse *response = context.response;
  if (!response.committed || response.statusCode == 304) {
    return;
  }
  if (![self responseLooksLikeJSON:response]) {
    return;
  }
  if ([response.bodyData length] == 0) {
    return;
  }

  NSError *parseError = nil;
  id parsed = [ALNJSONSerialization JSONObjectWithData:response.bodyData options:0 error:&parseError];
  if (parseError != nil || parsed == nil) {
    return;
  }

  NSDictionary *envelope = [self envelopedPayloadFromJSON:parsed
                                                  context:context
                                                   status:response.statusCode];
  NSError *serializeError = nil;
  if (![response setJSONBody:envelope options:0 error:&serializeError]) {
    return;
  }
  response.committed = YES;
}

@end
