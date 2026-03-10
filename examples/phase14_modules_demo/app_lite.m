#import <Foundation/Foundation.h>

#import "ALNAdminUIModule.h"
#import "ALNController.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"
#import "ALNStorageModule.h"
#import "ArlenServer.h"

static NSMutableDictionary<NSString *, NSMutableDictionary *> *Phase14DemoOrderStore(void) {
  static NSMutableDictionary<NSString *, NSMutableDictionary *> *store = nil;
  if (store == nil) {
    store = [@{
      @"ord-100" : [@{
        @"id" : @"ord-100",
        @"order_number" : @"100",
        @"status" : @"reviewed",
        @"owner_email" : @"buyer-one@example.test",
        @"total_cents" : @1250,
      } mutableCopy],
      @"ord-101" : [@{
        @"id" : @"ord-101",
        @"order_number" : @"101",
        @"status" : @"pending",
        @"owner_email" : @"buyer-two@example.test",
        @"total_cents" : @2400,
      } mutableCopy],
    } mutableCopy];
  }
  return store;
}

static NSMutableArray<NSString *> *Phase14DemoExecutions(void) {
  static NSMutableArray<NSString *> *executions = nil;
  if (executions == nil) {
    executions = [NSMutableArray array];
  }
  return executions;
}

@interface Phase14DemoOrdersResource : NSObject <ALNAdminUIResource>
@end

@implementation Phase14DemoOrdersResource

- (NSString *)adminUIResourceIdentifier {
  return @"orders";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Orders",
    @"singularLabel" : @"Order",
    @"summary" : @"Example app-owned resource registered into admin-ui and indexed by the search module.",
    @"identifierField" : @"id",
    @"primaryField" : @"order_number",
    @"fields" : @[
      @{ @"name" : @"order_number", @"label" : @"Order", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"status", @"label" : @"Status", @"list" : @YES, @"detail" : @YES, @"editable" : @YES },
      @{ @"name" : @"owner_email", @"label" : @"Owner", @"kind" : @"email", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"total_cents", @"label" : @"Total", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
    ],
    @"filters" : @[ @{ @"name" : @"q", @"label" : @"Search", @"type" : @"search" } ],
    @"actions" : @[ @{ @"name" : @"mark_reviewed", @"label" : @"Mark reviewed", @"scope" : @"row" } ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  (void)error;
  NSString *search = [(query ?: @"") lowercaseString];
  NSArray *keys = [[Phase14DemoOrderStore() allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *key in keys) {
    NSDictionary *record = Phase14DemoOrderStore()[key];
    NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@",
                                                     record[@"order_number"] ?: @"",
                                                     record[@"status"] ?: @"",
                                                     record[@"owner_email"] ?: @""]
        lowercaseString];
    if ([search length] > 0 && [haystack rangeOfString:search].location == NSNotFound) {
      continue;
    }
    [records addObject:[record copy]];
  }
  NSUInteger start = MIN(offset, [records count]);
  NSUInteger length = MIN(limit, ([records count] - start));
  return [records subarrayWithRange:NSMakeRange(start, length)];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  NSDictionary *record = [Phase14DemoOrderStore()[identifier ?: @""] copy];
  if (record == nil && error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14Demo"
                                 code:404
                             userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
  }
  return record;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  NSMutableDictionary *record = Phase14DemoOrderStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase14Demo"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  NSString *status = [parameters[@"status"] isKindOfClass:[NSString class]] ? parameters[@"status"] : @"";
  if ([status length] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase14Demo"
                                   code:422
                               userInfo:@{ NSLocalizedDescriptionKey : @"status is required" }];
    }
    return nil;
  }
  record[@"status"] = status;
  return [record copy];
}

- (NSDictionary *)adminUIPerformActionNamed:(NSString *)actionName
                                 identifier:(NSString *)identifier
                                 parameters:(NSDictionary *)parameters
                                      error:(NSError **)error {
  (void)parameters;
  NSMutableDictionary *record = Phase14DemoOrderStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase14Demo"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  if (![[actionName lowercaseString] isEqualToString:@"mark_reviewed"]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase14Demo"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Action not found" }];
    }
    return nil;
  }
  record[@"status"] = @"reviewed";
  return @{
    @"record" : [record copy],
    @"message" : @"Order marked reviewed.",
  };
}

@end

@interface Phase14DemoOrdersProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation Phase14DemoOrdersProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14DemoOrdersResource alloc] init] ];
}

@end

@interface Phase14DemoRecordedJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase14DemoRecordedJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase14demo.recorded";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Phase14 Demo Recorded Job",
    @"queue" : @"default",
    @"maxAttempts" : @2,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"value"] isKindOfClass:[NSString class]] && [payload[@"value"] length] > 0) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14Demo"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"value is required" }];
  }
  return NO;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)context;
  (void)error;
  [Phase14DemoExecutions() addObject:payload[@"value"]];
  return YES;
}

@end

@interface Phase14DemoJobProvider : NSObject <ALNJobsJobProvider>
@end

@implementation Phase14DemoJobProvider

- (NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14DemoRecordedJob alloc] init] ];
}

@end

@interface Phase14DemoScheduleProvider : NSObject <ALNJobsScheduleProvider>
@end

@implementation Phase14DemoScheduleProvider

- (NSArray<NSDictionary *> *)jobsModuleScheduleDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                               error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ @{
    @"identifier" : @"phase14demo.interval",
    @"job" : @"phase14demo.recorded",
    @"intervalSeconds" : @60,
    @"payload" : @{ @"value" : @"scheduled-job" },
  } ];
}

@end

@interface Phase14DemoNotificationDefinition : NSObject <ALNNotificationDefinition>
@end

@implementation Phase14DemoNotificationDefinition

- (NSString *)notificationsModuleIdentifier {
  return @"phase14demo.notification";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Phase14 Demo Notification",
    @"channels" : @[ @"email", @"in_app" ],
  };
}

- (NSArray<NSString *> *)notificationsModuleDefaultChannels {
  return @[ @"email", @"in_app" ];
}

- (BOOL)notificationsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"recipient"] isKindOfClass:[NSString class]] &&
      [payload[@"email"] isKindOfClass:[NSString class]] &&
      [payload[@"name"] isKindOfClass:[NSString class]]) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14Demo"
                                 code:2
                             userInfo:@{ NSLocalizedDescriptionKey : @"recipient, email, and name are required" }];
  }
  return NO;
}

- (ALNMailMessage *)notificationsModuleMailMessageForPayload:(NSDictionary *)payload
                                                     runtime:(ALNNotificationsModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)error;
  NSString *name = [payload[@"name"] isKindOfClass:[NSString class]] ? payload[@"name"] : @"friend";
  return [[ALNMailMessage alloc] initWithFrom:[runtime resolvedConfigSummary][@"sender"] ?: @"phase14-demo@example.test"
                                           to:@[ payload[@"email"] ?: @"" ]
                                           cc:nil
                                          bcc:nil
                                      subject:[NSString stringWithFormat:@"Phase14 Demo %@", name]
                                     textBody:[NSString stringWithFormat:@"Hello %@.", name]
                                     htmlBody:[NSString stringWithFormat:@"<p>Hello %@.</p>", name]
                                      headers:nil
                                     metadata:nil];
}

- (NSDictionary *)notificationsModuleInAppEntryForPayload:(NSDictionary *)payload
                                                  runtime:(ALNNotificationsModuleRuntime *)runtime
                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  NSString *name = [payload[@"name"] isKindOfClass:[NSString class]] ? payload[@"name"] : @"friend";
  return @{
    @"recipient" : payload[@"recipient"] ?: @"",
    @"title" : @"Phase14 Demo Inbox",
    @"body" : [NSString stringWithFormat:@"Hello %@.", name],
  };
}

@end

@interface Phase14DemoNotificationsProvider : NSObject <ALNNotificationProvider>
@end

@implementation Phase14DemoNotificationsProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14DemoNotificationDefinition alloc] init] ];
}

@end

@interface Phase14DemoMediaCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation Phase14DemoMediaCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"media";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Media Library",
    @"description" : @"Phase 14 demo uploads",
    @"acceptedContentTypes" : @[ @"image/png" ],
    @"maxBytes" : @128,
    @"visibility" : @"public",
    @"variants" : @[
      @{ @"identifier" : @"hero", @"label" : @"Hero", @"contentType" : @"image/png" },
      @{ @"identifier" : @"thumb", @"label" : @"Thumb", @"contentType" : @"image/png" },
    ],
  };
}

@end

@interface Phase14DemoStorageCollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation Phase14DemoStorageCollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14DemoMediaCollection alloc] init] ];
}

@end

@interface Phase14DemoController : ALNController
@end

@implementation Phase14DemoController

- (id)home:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"phase14-modules-demo\n"];
  return nil;
}

- (id)executions:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"executions" : Phase14DemoExecutions() ?: @[] } meta:nil error:NULL];
  return nil;
}

@end

static void RegisterRoutes(ALNApplication *app) {
  [app registerRouteMethod:@"GET"
                      path:@"/"
                      name:@"home"
           controllerClass:[Phase14DemoController class]
                    action:@"home"];
  [app registerRouteMethod:@"GET"
                      path:@"/demo/api/executions"
                      name:@"demo_api_executions"
           controllerClass:[Phase14DemoController class]
                    action:@"executions"];
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    return ALNRunAppMain(argc, argv, &RegisterRoutes);
  }
}
