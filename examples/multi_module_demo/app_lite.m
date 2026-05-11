#import <Foundation/Foundation.h>

#import "ALNAdminUIModule.h"
#import "ALNController.h"
#import "ALNJobsModule.h"
#import "ALNNotificationsModule.h"
#import "ALNOpsModule.h"
#import "ALNStorageModule.h"
#import "ArlenServer.h"

static NSMutableDictionary<NSString *, NSMutableDictionary *> *Phase16DemoOrderStore(void) {
  static NSMutableDictionary<NSString *, NSMutableDictionary *> *store = nil;
  if (store == nil) {
    store = [@{
      @"ord-100" : [@{
        @"id" : @"ord-100",
        @"order_number" : @"100",
        @"status" : @"reviewed",
        @"owner_email" : @"buyer-one@example.test",
        @"total_cents" : @1250,
        @"updated_at" : @"2026-03-01",
      } mutableCopy],
      @"ord-102" : [@{
        @"id" : @"ord-102",
        @"order_number" : @"102",
        @"status" : @"pending",
        @"owner_email" : @"priority@example.test",
        @"total_cents" : @2400,
        @"updated_at" : @"2026-03-08",
      } mutableCopy],
    } mutableCopy];
  }
  return store;
}

static NSMutableArray<NSString *> *Phase16DemoExecutions(void) {
  static NSMutableArray<NSString *> *executions = nil;
  if (executions == nil) {
    executions = [NSMutableArray array];
  }
  return executions;
}

@interface Phase16DemoOrdersResource : NSObject <ALNAdminUIResource>
@end

@implementation Phase16DemoOrdersResource

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
    @"pageSize" : @1,
    @"pageSizes" : @[ @1, @2, @10 ],
    @"fields" : @[
      @{ @"name" : @"order_number", @"label" : @"Order", @"list" : @YES, @"detail" : @YES },
      @{
        @"name" : @"status",
        @"label" : @"Status",
        @"list" : @YES,
        @"detail" : @YES,
        @"editable" : @YES,
        @"choices" : @[ @"pending", @"reviewed" ],
        @"autocomplete" : @{ @"enabled" : @YES, @"minQueryLength" : @1 },
      },
      @{ @"name" : @"owner_email", @"label" : @"Owner", @"kind" : @"email", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"total_cents", @"label" : @"Total", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"updated_at", @"label" : @"Updated", @"kind" : @"date", @"detail" : @YES, @"list" : @NO },
    ],
    @"filters" : @[
      @{ @"name" : @"q", @"label" : @"Search", @"type" : @"search", @"placeholder" : @"order, owner, status" },
      @{ @"name" : @"status", @"label" : @"Status", @"type" : @"select", @"choices" : @[ @"pending", @"reviewed" ] },
      @{ @"name" : @"total_min", @"label" : @"Min total", @"type" : @"number", @"min" : @"0", @"step" : @"1" },
      @{ @"name" : @"updated_after", @"label" : @"Updated after", @"type" : @"date" },
    ],
    @"sorts" : @[
      @{ @"name" : @"updated_at", @"label" : @"Updated", @"default" : @YES, @"direction" : @"desc" },
      @{ @"name" : @"total_cents", @"label" : @"Total", @"direction" : @"desc" },
      @{ @"name" : @"order_number", @"label" : @"Order" },
    ],
    @"bulkActions" : @[
      @{ @"name" : @"mark_reviewed", @"label" : @"Mark reviewed", @"method" : @"POST" },
    ],
    @"exports" : @[ @"json", @"csv" ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  return [self adminUIListRecordsWithParameters:@{ @"q" : query ?: @"" } limit:limit offset:offset error:error];
}

- (NSArray<NSDictionary *> *)adminUIListRecordsWithParameters:(NSDictionary *)parameters
                                                        limit:(NSUInteger)limit
                                                       offset:(NSUInteger)offset
                                                        error:(NSError **)error {
  (void)error;
  NSString *search = [parameters[@"q"] isKindOfClass:[NSString class]] ? [parameters[@"q"] lowercaseString] : @"";
  NSString *status = [parameters[@"status"] isKindOfClass:[NSString class]] ? [parameters[@"status"] lowercaseString] : @"";
  NSInteger totalMin = [parameters[@"total_min"] respondsToSelector:@selector(integerValue)] ? [parameters[@"total_min"] integerValue] : 0;
  NSString *updatedAfter = [parameters[@"updated_after"] isKindOfClass:[NSString class]] ? parameters[@"updated_after"] : @"";
  NSString *sort = [parameters[@"sort"] isKindOfClass:[NSString class]] ? [parameters[@"sort"] lowercaseString] : @"";

  NSMutableArray *records = [NSMutableArray array];
  for (NSString *key in [[Phase16DemoOrderStore() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    NSDictionary *record = [Phase16DemoOrderStore()[key] copy];
    NSString *haystack = [[NSString stringWithFormat:@"%@ %@ %@",
                                                     record[@"order_number"] ?: @"",
                                                     record[@"status"] ?: @"",
                                                     record[@"owner_email"] ?: @""]
        lowercaseString];
    if ([search length] > 0 && [haystack rangeOfString:search].location == NSNotFound) {
      continue;
    }
    if ([status length] > 0 && ![[record[@"status"] lowercaseString] isEqualToString:status]) {
      continue;
    }
    if ([record[@"total_cents"] integerValue] < totalMin) {
      continue;
    }
    if ([updatedAfter length] > 0 &&
        [[record[@"updated_at"] description] compare:updatedAfter options:NSNumericSearch] == NSOrderedAscending) {
      continue;
    }
    [records addObject:record];
  }

  BOOL descending = [sort hasPrefix:@"-"] || [sort length] == 0;
  NSString *sortField = ([sort hasPrefix:@"-"] ? [sort substringFromIndex:1] : sort);
  if ([sortField length] == 0) {
    sortField = @"updated_at";
  }
  [records sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
    NSString *left = [[lhs[sortField] description] lowercaseString];
    NSString *right = [[rhs[sortField] description] lowercaseString];
    NSComparisonResult result = [left compare:right options:NSNumericSearch];
    if (result == NSOrderedSame) {
      result = [[[lhs[@"order_number"] description] lowercaseString]
          compare:[[rhs[@"order_number"] description] lowercaseString]];
    }
    return descending ? -result : result;
  }];

  NSUInteger start = MIN(offset, [records count]);
  NSUInteger length = MIN(limit, ([records count] - start));
  return [records subarrayWithRange:NSMakeRange(start, length)];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  NSDictionary *record = [Phase16DemoOrderStore()[identifier ?: @""] copy];
  if (record == nil && error != NULL) {
    *error = [NSError errorWithDomain:@"Phase16Demo"
                                 code:404
                             userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
  }
  return record;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  NSMutableDictionary *record = Phase16DemoOrderStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase16Demo"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  NSString *status = [parameters[@"status"] isKindOfClass:[NSString class]] ? parameters[@"status"] : @"";
  if ([status length] > 0) {
    record[@"status"] = status;
  }
  return [record copy];
}

- (NSDictionary *)adminUIPerformBulkActionNamed:(NSString *)actionName
                                      identifiers:(NSArray<NSString *> *)identifiers
                                       parameters:(NSDictionary *)parameters
                                            error:(NSError **)error {
  (void)parameters;
  if (![[actionName lowercaseString] isEqualToString:@"mark_reviewed"]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase16Demo"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Unknown action" }];
    }
    return nil;
  }
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *identifier in identifiers) {
    NSMutableDictionary *record = Phase16DemoOrderStore()[identifier];
    if (record == nil) {
      continue;
    }
    record[@"status"] = @"reviewed";
    [records addObject:[record copy]];
  }
  return @{
    @"count" : @([records count]),
    @"records" : records,
    @"message" : @"Orders marked reviewed.",
  };
}

- (NSArray<NSDictionary *> *)adminUIAutocompleteSuggestionsForFieldNamed:(NSString *)fieldName
                                                                    query:(NSString *)query
                                                                    limit:(NSUInteger)limit
                                                                    error:(NSError **)error {
  (void)error;
  if (![[fieldName lowercaseString] isEqualToString:@"status"]) {
    return @[];
  }
  NSString *needle = [query isKindOfClass:[NSString class]] ? [query lowercaseString] : @"";
  NSMutableArray *matches = [NSMutableArray array];
  for (NSString *value in @[ @"pending", @"reviewed" ]) {
    if ([needle length] > 0 && [[value lowercaseString] rangeOfString:needle].location == NSNotFound) {
      continue;
    }
    [matches addObject:@{ @"value" : value, @"label" : [value capitalizedString] }];
    if ([matches count] >= MAX((NSUInteger)1U, limit)) {
      break;
    }
  }
  return matches;
}

@end

@interface Phase16DemoOrdersProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation Phase16DemoOrdersProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16DemoOrdersResource alloc] init] ];
}

@end

@interface Phase16DemoRecordedJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase16DemoRecordedJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase16demo.recorded";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Phase16 Demo Recorded Job",
    @"queue" : @"default",
    @"maxAttempts" : @2,
    @"tags" : @[ @"phase16", @"demo" ],
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"value"] isKindOfClass:[NSString class]] && [payload[@"value"] length] > 0) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase16Demo"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"value is required" }];
  }
  return NO;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)context;
  (void)error;
  [Phase16DemoExecutions() addObject:payload[@"value"]];
  return YES;
}

@end

@interface Phase16DemoJobProvider : NSObject <ALNJobsJobProvider>
@end

@implementation Phase16DemoJobProvider

- (NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16DemoRecordedJob alloc] init] ];
}

@end

@interface Phase16DemoScheduleProvider : NSObject <ALNJobsScheduleProvider>
@end

@implementation Phase16DemoScheduleProvider

- (NSArray<NSDictionary *> *)jobsModuleScheduleDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                               error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ @{
    @"identifier" : @"phase16demo.interval",
    @"job" : @"phase16demo.recorded",
    @"intervalSeconds" : @60,
    @"queue" : @"maintenance",
    @"payload" : @{ @"value" : @"scheduled-job" },
  } ];
}

@end

@interface Phase16DemoNotificationDefinition : NSObject <ALNNotificationDefinition>
@end

@implementation Phase16DemoNotificationDefinition

- (NSString *)notificationsModuleIdentifier {
  return @"phase16demo.notification";
}

- (NSDictionary *)notificationsModuleMetadata {
  return @{
    @"title" : @"Phase16 Demo Notification",
    @"channels" : @[ @"email", @"in_app", @"webhook" ],
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
    *error = [NSError errorWithDomain:@"Phase16Demo"
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
  return [[ALNMailMessage alloc] initWithFrom:[runtime resolvedConfigSummary][@"sender"] ?: @"phase16-demo@example.test"
                                           to:@[ payload[@"email"] ?: @"" ]
                                           cc:nil
                                          bcc:nil
                                      subject:[NSString stringWithFormat:@"Phase16 Demo %@", name]
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
    @"title" : @"Phase16 Demo Inbox",
    @"body" : [NSString stringWithFormat:@"Hello %@.", name],
  };
}

@end

@interface Phase16DemoNotificationsProvider : NSObject <ALNNotificationProvider>
@end

@implementation Phase16DemoNotificationsProvider

- (NSArray<id<ALNNotificationDefinition>> *)notificationsModuleDefinitionsForRuntime:
    (ALNNotificationsModuleRuntime *)runtime
                                                                          error:
                                                                              (NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16DemoNotificationDefinition alloc] init] ];
}

@end

@interface Phase16DemoMediaCollection : NSObject <ALNStorageCollectionDefinition>
@end

@implementation Phase16DemoMediaCollection

- (NSString *)storageModuleCollectionIdentifier {
  return @"media";
}

- (NSDictionary *)storageModuleCollectionMetadata {
  return @{
    @"title" : @"Media Library",
    @"description" : @"Phase 16 demo uploads",
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

@interface Phase16DemoStorageCollectionProvider : NSObject <ALNStorageCollectionProvider>
@end

@implementation Phase16DemoStorageCollectionProvider

- (NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:(ALNStorageModuleRuntime *)runtime
                                                                              error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase16DemoMediaCollection alloc] init] ];
}

@end

@interface Phase16DemoOpsCardProvider : NSObject <ALNOpsCardProvider>
@end

@implementation Phase16DemoOpsCardProvider

- (NSArray<NSDictionary *> *)opsModuleCardsForRuntime:(ALNOpsModuleRuntime *)runtime
                                                 error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ @{
    @"label" : @"Review Queue",
    @"value" : @"1",
    @"status" : @"healthy",
    @"summary" : @"orders pending review",
  } ];
}

- (NSArray<NSDictionary *> *)opsModuleWidgetsForRuntime:(ALNOpsModuleRuntime *)runtime
                                                   error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ @{
    @"title" : @"Operator Note",
    @"body" : @"Phase 16 widget seam active",
    @"status" : @"informational",
  } ];
}

@end

@interface Phase16DemoController : ALNController
@end

@implementation Phase16DemoController

- (id)home:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"phase16-modules-demo\n"];
  return nil;
}

- (id)executions:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"executions" : Phase16DemoExecutions() ?: @[] } meta:nil error:NULL];
  return nil;
}

@end

static void RegisterRoutes(ALNApplication *app) {
  [app registerRouteMethod:@"GET"
                      path:@"/"
                      name:@"home"
           controllerClass:[Phase16DemoController class]
                    action:@"home"];
  [app registerRouteMethod:@"GET"
                      path:@"/demo/api/executions"
                      name:@"demo_api_executions"
           controllerClass:[Phase16DemoController class]
                    action:@"executions"];
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    return ALNRunAppMain(argc, argv, &RegisterRoutes);
  }
}
