#import "ALNDataverseTestSupport.h"

#import "ALNJSONSerialization.h"
#import "ALNTestSupport.h"

@implementation ALNFakeDataverseTransport

- (instancetype)init {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _queuedResults = [NSMutableArray array];
  _capturedRequests = [NSMutableArray array];
  return self;
}

- (void)enqueueResponse:(ALNDataverseResponse *)response {
  [self.queuedResults addObject:response ?: [NSNull null]];
}

- (void)enqueueError:(NSError *)error {
  [self.queuedResults addObject:error ?: [NSNull null]];
}

- (ALNDataverseResponse *)executeRequest:(ALNDataverseRequest *)request error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  [self.capturedRequests addObject:request];
  id next = ([self.queuedResults count] > 0) ? self.queuedResults[0] : nil;
  if ([self.queuedResults count] > 0) {
    [self.queuedResults removeObjectAtIndex:0];
  }
  if ([next isKindOfClass:[NSError class]]) {
    if (error != NULL) {
      *error = next;
    }
    return nil;
  }
  return [next isKindOfClass:[ALNDataverseResponse class]] ? next : nil;
}

@end

@implementation ALNFakeDataverseTokenProvider

- (instancetype)init {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  _token = @"test-token";
  return self;
}

- (NSString *)accessTokenForTarget:(ALNDataverseTarget *)target
                         transport:(id<ALNDataverseTransport>)transport
                             error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  self.requestCount += 1;
  if (self.queuedError != nil) {
    if (error != NULL) {
      *error = self.queuedError;
    }
    return nil;
  }
  return self.token;
}

@end

@implementation ALNDataverseTestCase

- (ALNDataverseTarget *)targetWithError:(NSError **)error {
  return [self targetNamed:@"crm" maxRetries:0 pageSize:250 error:error];
}

- (ALNDataverseTarget *)targetNamed:(NSString *)targetName
                         maxRetries:(NSUInteger)maxRetries
                           pageSize:(NSUInteger)pageSize
                              error:(NSError **)error {
  return [[ALNDataverseTarget alloc] initWithServiceRootURLString:@"https://example.crm.dynamics.com/api/data/v9.2"
                                                         tenantID:@"tenant-id"
                                                         clientID:@"client-id"
                                                     clientSecret:@"client-secret"
                                                        targetName:targetName
                                                   timeoutInterval:5.0
                                                        maxRetries:maxRetries
                                                          pageSize:pageSize
                                                             error:error];
}

- (ALNDataverseClient *)clientWithTransport:(id<ALNDataverseTransport>)transport
                              tokenProvider:(id<ALNDataverseTokenProvider>)tokenProvider
                                 targetName:(NSString *)targetName
                                 maxRetries:(NSUInteger)maxRetries
                                   pageSize:(NSUInteger)pageSize
                                      error:(NSError **)error {
  ALNDataverseTarget *target = [self targetNamed:targetName
                                      maxRetries:maxRetries
                                        pageSize:pageSize
                                           error:error];
  if (target == nil) {
    return nil;
  }
  return [[ALNDataverseClient alloc] initWithTarget:target
                                          transport:transport
                                      tokenProvider:tokenProvider
                                              error:error];
}

- (NSDictionary *)applicationConfig {
  return @{
    @"dataverse" : @{
      @"serviceRootURL" : @"https://example.crm.dynamics.com/api/data/v9.2",
      @"tenantID" : @"tenant-id",
      @"clientID" : @"client-id",
      @"clientSecret" : @"client-secret",
      @"pageSize" : @250,
      @"maxRetries" : @2,
      @"timeout" : @5,
      @"targets" : @{
        @"sales" : @{
          @"serviceRootURL" : @"https://sales.crm.dynamics.com/api/data/v9.2",
          @"pageSize" : @100,
        },
      },
    },
  };
}

- (NSString *)environmentValueForName:(NSString *)name {
  const char *value = getenv([name UTF8String]);
  if (value == NULL) {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (void)setEnvironmentValue:(NSString *)value forName:(NSString *)name {
  if ([value length] > 0) {
    setenv([name UTF8String], [value UTF8String], 1);
  } else {
    unsetenv([name UTF8String]);
  }
}

- (NSDictionary<NSString *, NSString *> *)snapshotEnvironmentForNames:(NSArray<NSString *> *)names {
  NSMutableDictionary<NSString *, NSString *> *snapshot = [NSMutableDictionary dictionary];
  for (NSString *name in names) {
    NSString *value = [self environmentValueForName:name];
    if (value != nil) {
      snapshot[name] = value;
    }
  }
  return [snapshot copy];
}

- (void)restoreEnvironmentSnapshot:(NSDictionary<NSString *, NSString *> *)snapshot
                             names:(NSArray<NSString *> *)names {
  for (NSString *name in names) {
    [self setEnvironmentValue:snapshot[name] forName:name];
  }
}

- (ALNDataverseResponse *)responseWithStatus:(NSInteger)status
                                     headers:(NSDictionary<NSString *, NSString *> *)headers
                                  JSONObject:(id)object {
  NSData *data = nil;
  if (object != nil) {
    data = [ALNJSONSerialization dataWithJSONObject:object options:0 error:NULL];
  }
  return [[ALNDataverseResponse alloc] initWithStatusCode:status headers:headers bodyData:data];
}

- (NSDictionary *)JSONObjectFromRequestBody:(ALNDataverseRequest *)request {
  if ([request.bodyData length] == 0) {
    return nil;
  }
  id object = [ALNJSONSerialization JSONObjectWithData:request.bodyData options:0 error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

@end
