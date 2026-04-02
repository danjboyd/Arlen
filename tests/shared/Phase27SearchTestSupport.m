#import "Phase27SearchTestSupport.h"

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNRequest.h"

NSString *const Phase27SearchPredicateAllowedStashKey = @"phase27_search_predicate_allowed";

static BOOL gPhase27SearchProductsBuildShouldFail = NO;
static BOOL gPhase27SearchTenantOrdersIndexingShouldFail = NO;
static BOOL gPhase27SearchTenantOrdersPaused = NO;

NSMutableDictionary<NSString *, NSMutableDictionary *> *Phase27SearchProductStore(void) {
  static NSMutableDictionary<NSString *, NSMutableDictionary *> *store = nil;
  if (store == nil) {
    store = [NSMutableDictionary dictionary];
  }
  return store;
}

static NSString *Phase27SearchHeaderValue(NSDictionary *headers, NSString *name) {
  NSString *target = [[name ?: @"" lowercaseString] copy];
  for (id rawKey in [headers allKeys]) {
    NSString *key = [[rawKey description] lowercaseString];
    if ([key isEqualToString:target]) {
      return [headers[rawKey] isKindOfClass:[NSString class]] ? headers[rawKey] : [[headers[rawKey] description] copy];
    }
  }
  return @"";
}

void Phase27SearchResetStores(void) {
  NSMutableDictionary *products = Phase27SearchProductStore();
  [products removeAllObjects];
  products[@"sku-100"] = [@{
    @"sku" : @"sku-100",
    @"name" : @"Starter Kit",
    @"category" : @"starter",
    @"description" : @"Entry starter kit for new operators.",
    @"inventory_count" : @12,
    @"internal_cost" : @"17.10",
  } mutableCopy];
  products[@"sku-102"] = [@{
    @"sku" : @"sku-102",
    @"name" : @"Priority Kit",
    @"category" : @"priority",
    @"description" : @"Priority workflow kit for fast-moving queues.",
    @"inventory_count" : @4,
    @"internal_cost" : @"21.50",
  } mutableCopy];
  products[@"sku-103"] = [@{
    @"sku" : @"sku-103",
    @"name" : @"Priority Rack",
    @"category" : @"priority",
    @"description" : @"Rack accessory for priority stations.",
    @"inventory_count" : @7,
    @"internal_cost" : @"31.00",
  } mutableCopy];
  gPhase27SearchProductsBuildShouldFail = NO;
  gPhase27SearchTenantOrdersIndexingShouldFail = NO;
  gPhase27SearchTenantOrdersPaused = NO;
}

void Phase27SearchSetProductsBuildShouldFail(BOOL shouldFail) {
  gPhase27SearchProductsBuildShouldFail = shouldFail;
}

void Phase27SearchSetTenantOrdersIndexingShouldFail(BOOL shouldFail) {
  gPhase27SearchTenantOrdersIndexingShouldFail = shouldFail;
}

void Phase27SearchSetTenantOrdersPaused(BOOL shouldPause) {
  gPhase27SearchTenantOrdersPaused = shouldPause;
}

NSString *Phase27SearchUniquePostgresTableName(void) {
  NSString *raw = [[NSProcessInfo processInfo] globallyUniqueString] ?: @"phase27";
  NSMutableString *sanitized = [NSMutableString stringWithString:@"phase27_search_"];
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  for (NSUInteger index = 0; index < [raw length]; index++) {
    unichar ch = [raw characterAtIndex:index];
    [sanitized appendString:[allowed characterIsMember:ch] ? [NSString stringWithFormat:@"%C", ch] : @"_"];
  }
  return [sanitized copy];
}

NSString *Phase27SearchFixturesPath(NSString *filename) {
  NSString *resolved = [filename isKindOfClass:[NSString class]] ? filename : @"";
  return [[[NSFileManager defaultManager] currentDirectoryPath]
      stringByAppendingPathComponent:[NSString stringWithFormat:@"tests/fixtures/phase27/%@", resolved]];
}

@interface Phase27SearchProductsResource : NSObject <ALNSearchResourceDefinition>
@end

@implementation Phase27SearchProductsResource

- (NSString *)searchModuleResourceIdentifier {
  return @"products";
}

- (NSDictionary *)searchModuleResourceMetadata {
  return @{
    @"label" : @"Products",
    @"summary" : @"Public storefront catalog results.",
    @"identifierField" : @"sku",
    @"primaryField" : @"name",
    @"summaryField" : @"description",
    @"indexedFields" : @[ @"sku", @"name", @"category", @"description", @"inventory_count", @"internal_cost" ],
    @"searchFields" : @[ @"sku", @"name", @"category", @"description" ],
    @"autocompleteFields" : @[ @"name", @"sku" ],
    @"suggestionFields" : @[ @"name", @"description", @"category" ],
    @"highlightFields" : @[ @"description", @"name" ],
    @"resultFields" : @[ @"sku", @"name", @"category" ],
    @"fieldTypes" : @{
      @"sku" : @"string",
      @"name" : @"string",
      @"category" : @"string",
      @"description" : @"string",
      @"inventory_count" : @"integer",
    },
    @"weightedFields" : @{
      @"name" : @4,
      @"category" : @2,
      @"description" : @1,
      @"sku" : @3,
    },
    @"filters" : @[
      @{
        @"name" : @"category",
        @"type" : @"string",
        @"operators" : @[ @"eq", @"in" ],
        @"choices" : @[ @"starter", @"priority" ],
      },
      @{
        @"name" : @"inventory_count",
        @"type" : @"integer",
        @"operators" : @[ @"gte", @"lte" ],
      },
    ],
    @"facetFields" : @[
      @{
        @"name" : @"category",
        @"label" : @"Category",
        @"type" : @"string",
        @"choices" : @[ @"starter", @"priority" ],
        @"limit" : @5,
      },
    ],
    @"sorts" : @[
      @{ @"name" : @"name", @"default" : @YES },
      @{ @"name" : @"inventory_count", @"type" : @"integer", @"direction" : @"desc" },
    ],
    @"defaultSort" : @"name",
    @"pagination" : @{
      @"defaultLimit" : @10,
      @"maxLimit" : @50,
      @"pageSizes" : @[ @10, @25, @50 ],
    },
    @"queryPolicy" : @"public",
    @"queryModes" : @[ @"search", @"phrase", @"fuzzy", @"autocomplete" ],
    @"promotions" : @[
      @{
        @"query" : @"priority",
        @"recordIDs" : @[ @"sku-102" ],
        @"label" : @"Featured",
      },
    ],
    @"pathTemplate" : @"/products/:identifier",
  };
}

- (NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)runtime;
  if (gPhase27SearchProductsBuildShouldFail) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase27Search"
                                   code:41
                               userInfo:@{ NSLocalizedDescriptionKey : @"expected products rebuild failure" }];
    }
    return nil;
  }
  NSMutableArray *records = [NSMutableArray array];
  for (NSString *key in [[Phase27SearchProductStore() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    [records addObject:[Phase27SearchProductStore()[key] copy]];
  }
  return records;
}

- (NSDictionary *)searchModulePublicResultForDocument:(NSDictionary *)document
                                              metadata:(NSDictionary *)metadata
                                               runtime:(ALNSearchModuleRuntime *)runtime
                                                 error:(NSError **)error {
  (void)metadata;
  (void)runtime;
  (void)error;
  NSDictionary *record = [document[@"record"] isKindOfClass:[NSDictionary class]] ? document[@"record"] : @{};
  NSString *category = [record[@"category"] isKindOfClass:[NSString class]] ? record[@"category"] : @"";
  return @{
    @"fields" : @{
      @"sku" : record[@"sku"] ?: @"",
      @"category" : category ?: @"",
      @"inventory" : record[@"inventory_count"] ?: @0,
    },
    @"badge" : [category isEqualToString:@"priority"] ? @"featured" : @"catalog",
  };
}

@end

@interface Phase27SearchMembersResource : NSObject <ALNSearchResourceDefinition>
@end

@implementation Phase27SearchMembersResource

- (NSString *)searchModuleResourceIdentifier {
  return @"members";
}

- (NSDictionary *)searchModuleResourceMetadata {
  return @{
    @"label" : @"Members",
    @"summary" : @"Authenticated member directory.",
    @"identifierField" : @"id",
    @"primaryField" : @"name",
    @"indexedFields" : @[ @"id", @"name", @"team", @"email" ],
    @"resultFields" : @[ @"id", @"name", @"team" ],
    @"queryPolicy" : @"authenticated",
    @"queryModes" : @[ @"search", @"phrase" ],
  };
}

- (NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    @{
      @"id" : @"mem-100",
      @"name" : @"Alice Example",
      @"team" : @"success",
      @"email" : @"alice@example.test",
    },
  ];
}

@end

@interface Phase27SearchFinanceResource : NSObject <ALNSearchResourceDefinition>
@end

@implementation Phase27SearchFinanceResource

- (NSString *)searchModuleResourceIdentifier {
  return @"finance";
}

- (NSDictionary *)searchModuleResourceMetadata {
  return @{
    @"label" : @"Finance",
    @"summary" : @"Role-gated finance search.",
    @"identifierField" : @"id",
    @"primaryField" : @"title",
    @"indexedFields" : @[ @"id", @"title", @"classification" ],
    @"resultFields" : @[ @"id", @"title", @"classification" ],
    @"queryPolicy" : @"role_gated",
    @"queryRoles" : @[ @"auditor" ],
  };
}

- (NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    @{
      @"id" : @"fin-100",
      @"title" : @"Quarterly Forecast",
      @"classification" : @"internal",
    },
  ];
}

@end

@interface Phase27SearchPredicateResource : NSObject <ALNSearchResourceDefinition>
@end

@implementation Phase27SearchPredicateResource

- (NSString *)searchModuleResourceIdentifier {
  return @"regional_docs";
}

- (NSDictionary *)searchModuleResourceMetadata {
  return @{
    @"label" : @"Regional Docs",
    @"summary" : @"Predicate-gated tenant documents.",
    @"identifierField" : @"id",
    @"primaryField" : @"title",
    @"indexedFields" : @[ @"id", @"title", @"region" ],
    @"resultFields" : @[ @"id", @"title", @"region" ],
    @"queryPolicy" : @"predicate",
  };
}

- (NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime
                                                       error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    @{
      @"id" : @"doc-100",
      @"title" : @"Central Handbook",
      @"region" : @"central",
    },
  ];
}

- (BOOL)searchModuleAllowsQueryForContext:(ALNContext *)context
                                  runtime:(ALNSearchModuleRuntime *)runtime
                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return [context.stash[Phase27SearchPredicateAllowedStashKey] boolValue];
}

@end

@interface Phase27SearchTenantOrdersResource : NSObject <ALNSearchResourceDefinition>
@end

@implementation Phase27SearchTenantOrdersResource

- (NSString *)searchModuleResourceIdentifier {
  return @"tenant_orders";
}

- (NSDictionary *)searchModuleResourceMetadata {
  return @{
    @"label" : @"Tenant Orders",
    @"summary" : @"Tenant-scoped documents with soft delete and replay semantics.",
    @"identifierField" : @"id",
    @"primaryField" : @"title",
    @"summaryField" : @"description",
    @"indexedFields" : @[ @"id", @"title", @"description", @"tenant_id", @"deleted", @"archived", @"published", @"status" ],
    @"searchFields" : @[ @"title", @"description", @"status" ],
    @"resultFields" : @[ @"id", @"title", @"tenant_id", @"status" ],
    @"fieldTypes" : @{
      @"deleted" : @"boolean",
      @"archived" : @"boolean",
      @"published" : @"boolean",
    },
    @"queryPolicy" : @"authenticated",
    @"tenantField" : @"tenant_id",
    @"tenantClaim" : @"tenant",
    @"softDeleteField" : @"deleted",
    @"archivedField" : @"archived",
    @"syncPolicy" : @{
      @"bulkBatchSize" : @2,
      @"replayLimit" : @3,
      @"softDeleteMode" : @"delete",
      @"paused" : @(gPhase27SearchTenantOrdersPaused),
      @"pauseReason" : gPhase27SearchTenantOrdersPaused ? @"fixture pause" : @"",
      @"conditionalField" : @"published",
      @"conditionalValues" : @[ @"yes" ],
    },
    @"queryModes" : @[ @"search", @"phrase" ],
  };
}

- (BOOL)searchModuleEnumerateDocumentBatchesForRuntime:(ALNSearchModuleRuntime *)runtime
                                             batchSize:(NSUInteger)batchSize
                                            usingBlock:(ALNSearchResourceBatchConsumer)consumer
                                                 error:(NSError **)error {
  (void)runtime;
  NSArray *records = @[
    @{
      @"id" : @"ord-100",
      @"title" : @"Tenant A Priority Runbook",
      @"description" : @"Published queue guide for tenant A.",
      @"tenant_id" : @"tenant-a",
      @"deleted" : @"false",
      @"archived" : @"false",
      @"published" : @"yes",
      @"status" : @"active",
    },
    @{
      @"id" : @"ord-101",
      @"title" : @"Tenant B Priority Runbook",
      @"description" : @"Published queue guide for tenant B.",
      @"tenant_id" : @"tenant-b",
      @"deleted" : @"false",
      @"archived" : @"false",
      @"published" : @"yes",
      @"status" : @"active",
    },
    @{
      @"id" : @"ord-102",
      @"title" : @"Tenant A Deleted Runbook",
      @"description" : @"Soft-deleted tenant A document.",
      @"tenant_id" : @"tenant-a",
      @"deleted" : @"true",
      @"archived" : @"false",
      @"published" : @"yes",
      @"status" : @"deleted",
    },
    @{
      @"id" : @"ord-103",
      @"title" : @"Tenant A Archived Note",
      @"description" : @"Archived tenant A note.",
      @"tenant_id" : @"tenant-a",
      @"deleted" : @"false",
      @"archived" : @"true",
      @"published" : @"yes",
      @"status" : @"archived",
    },
    @{
      @"id" : @"ord-104",
      @"title" : @"Tenant A Draft Note",
      @"description" : @"Unpublished tenant A draft.",
      @"tenant_id" : @"tenant-a",
      @"deleted" : @"false",
      @"archived" : @"false",
      @"published" : @"no",
      @"status" : @"draft",
    },
  ];
  NSUInteger size = MAX((NSUInteger)1U, batchSize);
  for (NSUInteger index = 0; index < [records count]; index += size) {
    NSUInteger length = MIN(size, [records count] - index);
    NSArray *batch = [records subarrayWithRange:NSMakeRange(index, length)];
    if (!consumer(batch, error)) {
      return NO;
    }
  }
  return YES;
}

- (NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime
                                                       error:(NSError **)error {
  NSMutableArray *records = [NSMutableArray array];
  if (![self searchModuleEnumerateDocumentBatchesForRuntime:runtime
                                                  batchSize:100U
                                                 usingBlock:^BOOL(NSArray<NSDictionary *> *batch, NSError **batchError) {
                                                   (void)batchError;
                                                   [records addObjectsFromArray:batch ?: @[]];
                                                   return YES;
                                                 }
                                                      error:error]) {
    return nil;
  }
  return [records copy];
}

- (BOOL)searchModuleAllowsIndexingRecord:(NSDictionary *)record
                                 metadata:(NSDictionary *)metadata
                                  runtime:(ALNSearchModuleRuntime *)runtime
                                    error:(NSError **)error {
  (void)metadata;
  (void)runtime;
  if (gPhase27SearchTenantOrdersIndexingShouldFail) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase27Search"
                                   code:42
                               userInfo:@{ NSLocalizedDescriptionKey : @"expected tenant orders indexing failure" }];
    }
    return NO;
  }
  return YES;
}

@end

@implementation Phase27SearchProvider

- (NSArray<id<ALNSearchResourceDefinition>> *)searchModuleResourcesForRuntime:(ALNSearchModuleRuntime *)runtime
                                                                        error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[
    [[Phase27SearchProductsResource alloc] init],
    [[Phase27SearchMembersResource alloc] init],
    [[Phase27SearchFinanceResource alloc] init],
    [[Phase27SearchPredicateResource alloc] init],
    [[Phase27SearchTenantOrdersResource alloc] init],
  ];
}

@end

@interface Phase27SearchContextMiddleware () <ALNMiddleware>
@end

@implementation Phase27SearchContextMiddleware

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSDictionary *headers = [context.request.headers isKindOfClass:[NSDictionary class]] ? context.request.headers : @{};
  NSString *subject = Phase27SearchHeaderValue(headers, @"x-search-user");
  NSString *rolesHeader = Phase27SearchHeaderValue(headers, @"x-search-roles");
  NSString *predicate = Phase27SearchHeaderValue(headers, @"x-search-predicate");
  NSString *tenant = Phase27SearchHeaderValue(headers, @"x-search-tenant");
  NSArray *roles = ([rolesHeader length] > 0) ? [[rolesHeader lowercaseString] componentsSeparatedByString:@","] : @[];
  NSMutableArray *normalizedRoles = [NSMutableArray array];
  for (NSString *entry in roles) {
    NSString *role = [[entry stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([role length] == 0) {
      continue;
    }
    [normalizedRoles addObject:role];
  }
  if ([subject length] == 0 && [normalizedRoles count] > 0) {
    subject = @"phase27-user";
  }
  if ([subject length] > 0) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    context.stash[ALNContextAuthSubjectStashKey] = subject;
    context.stash[ALNContextAuthRolesStashKey] = normalizedRoles ?: @[];
    context.stash[ALNContextAuthClaimsStashKey] = @{
      @"sub" : subject,
      @"roles" : normalizedRoles ?: @[],
      @"tenant" : tenant ?: @"",
      @"aal" : @2,
      @"amr" : @[ @"pwd" ],
      @"iat" : @((NSInteger)now),
      @"auth_time" : @((NSInteger)now),
    };
  }
  context.stash[Phase27SearchPredicateAllowedStashKey] = @([[predicate lowercaseString] isEqualToString:@"allow"]);
  return YES;
}

@end
