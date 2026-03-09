#import <Foundation/Foundation.h>

#import "ALNAdminUIModule.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ArlenServer.h"

static NSMutableDictionary *AuthAdminDemoOrderStore(void) {
  static NSMutableDictionary *store = nil;
  if (store == nil) {
    store = [@{
      @"ord-100" : [@{
        @"id" : @"ord-100",
        @"order_number" : @"100",
        @"status" : @"pending",
        @"owner_email" : @"buyer-one@example.test",
        @"total_cents" : @1250,
      } mutableCopy],
      @"ord-101" : [@{
        @"id" : @"ord-101",
        @"order_number" : @"101",
        @"status" : @"fulfilled",
        @"owner_email" : @"buyer-two@example.test",
        @"total_cents" : @2400,
      } mutableCopy],
    } mutableCopy];
  }
  return store;
}

@interface AuthAdminDemoOrdersResource : NSObject <ALNAdminUIResource>
@end

@implementation AuthAdminDemoOrdersResource

- (NSString *)adminUIResourceIdentifier {
  return @"orders";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Orders",
    @"singularLabel" : @"Order",
    @"summary" : @"Example app-owned resource registered into the first-party admin module.",
    @"identifierField" : @"id",
    @"primaryField" : @"order_number",
    @"fields" : @[
      @{ @"name" : @"order_number", @"label" : @"Order", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"status", @"label" : @"Status", @"list" : @YES, @"detail" : @YES, @"editable" : @YES },
      @{ @"name" : @"total_cents", @"label" : @"Total", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"owner_email", @"label" : @"Owner", @"kind" : @"email", @"list" : @YES, @"detail" : @YES },
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
  NSArray *keys = [[AuthAdminDemoOrderStore() allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *key in keys) {
    NSDictionary *record = AuthAdminDemoOrderStore()[key];
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
  NSDictionary *record = [AuthAdminDemoOrderStore()[identifier ?: @""] copy];
  if (record == nil && error != NULL) {
    *error = [NSError errorWithDomain:@"AuthAdminDemo"
                                 code:404
                             userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
  }
  return record;
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  NSMutableDictionary *record = AuthAdminDemoOrderStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"AuthAdminDemo"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  NSString *status = [parameters[@"status"] isKindOfClass:[NSString class]] ? parameters[@"status"] : @"";
  if ([status length] == 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"AuthAdminDemo"
                                   code:422
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"status is required",
                                 @"field" : @"status",
                               }];
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
  NSMutableDictionary *record = AuthAdminDemoOrderStore()[identifier ?: @""];
  if (record == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"AuthAdminDemo"
                                   code:404
                               userInfo:@{ NSLocalizedDescriptionKey : @"Order not found" }];
    }
    return nil;
  }
  if (![[actionName lowercaseString] isEqualToString:@"mark_reviewed"]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"AuthAdminDemo"
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

@interface AuthAdminDemoOrdersProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation AuthAdminDemoOrdersProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[AuthAdminDemoOrdersResource alloc] init] ];
}

@end

@interface AuthAdminDemoController : ALNController
@end

@implementation AuthAdminDemoController

- (id)home:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"auth-admin-demo\n"];
  return nil;
}

@end

static void RegisterRoutes(ALNApplication *app) {
  [app registerRouteMethod:@"GET"
                      path:@"/"
                      name:@"home"
           controllerClass:[AuthAdminDemoController class]
                    action:@"home"];
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    return ALNRunAppMain(argc, argv, &RegisterRoutes);
  }
}
