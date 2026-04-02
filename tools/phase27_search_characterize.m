#import <Foundation/Foundation.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"
#import "ALNSearchModule.h"
#import "../tests/shared/Phase27SearchTestSupport.h"

static NSString *Phase27EnvString(NSString *name) {
  const char *value = getenv([name UTF8String]);
  if (value == NULL || value[0] == '\0') {
    return @"";
  }
  return [NSString stringWithUTF8String:value];
}

static NSDictionary *Phase27ApplicationConfig(NSDictionary *extraSearchConfig, NSDictionary *databaseConfig) {
  NSMutableDictionary *searchModule = [NSMutableDictionary dictionaryWithDictionary:@{
    @"providers" : @{ @"classes" : @[ @"Phase27SearchProvider" ] },
    @"persistence" : @{ @"enabled" : @NO },
  }];
  if ([extraSearchConfig isKindOfClass:[NSDictionary class]]) {
    [searchModule addEntriesFromDictionary:extraSearchConfig];
  }

  return @{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{ @"enabled" : @NO },
    @"database" : [databaseConfig isKindOfClass:[NSDictionary class]] ? databaseConfig : @{},
    @"jobsModule" : @{
      @"providers" : @{ @"classes" : @[] },
      @"worker" : @{ @"retryDelaySeconds" : @0 },
    },
    @"searchModule" : searchModule,
  };
}

static BOOL Phase27RegisterModules(ALNApplication *app, NSError **error) {
  if (![[[ALNJobsModule alloc] init] registerWithApplication:app error:error]) {
    return NO;
  }
  return [[[ALNSearchModule alloc] init] registerWithApplication:app error:error];
}

static BOOL Phase27SeedIndexes(ALNSearchModuleRuntime *runtime, NSError **error) {
  if ([runtime queueReindexForResourceIdentifier:nil error:error] == nil) {
    return NO;
  }
  return ([[ALNJobsModuleRuntime sharedRuntime] runWorkerAt:[NSDate date] limit:20 error:error] != nil);
}

static NSString *Phase27FirstResultID(NSDictionary *result) {
  NSArray *results = [result[@"results"] isKindOfClass:[NSArray class]] ? result[@"results"] : @[];
  NSDictionary *first = ([results count] > 0 && [results[0] isKindOfClass:[NSDictionary class]]) ? results[0] : @{};
  return [first[@"recordID"] isKindOfClass:[NSString class]] ? first[@"recordID"] : @"";
}

static NSArray<NSString *> *Phase27TopResultIDs(NSDictionary *result, NSUInteger count) {
  NSMutableArray<NSString *> *recordIDs = [NSMutableArray array];
  for (NSDictionary *entry in [result[@"results"] isKindOfClass:[NSArray class]] ? result[@"results"] : @[]) {
    NSString *recordID = [entry[@"recordID"] isKindOfClass:[NSString class]] ? entry[@"recordID"] : @"";
    if ([recordID length] > 0) {
      [recordIDs addObject:recordID];
    }
    if ([recordIDs count] >= count) {
      break;
    }
  }
  return recordIDs;
}

static NSDictionary *Phase27CharacterizeEngine(NSDictionary *extraSearchConfig,
                                               NSDictionary *databaseConfig,
                                               NSString *priorityQuery,
                                               NSString *adapterQuery,
                                               BOOL includeTenantMetadata) {
  Phase27SearchResetStores();

  ALNApplication *app = [[ALNApplication alloc] initWithConfig:Phase27ApplicationConfig(extraSearchConfig, databaseConfig)];
  if (includeTenantMetadata) {
    [app addMiddleware:[[Phase27SearchContextMiddleware alloc] init]];
  }

  NSError *error = nil;
  if (!Phase27RegisterModules(app, &error)) {
    return @{
      @"status" : @"fail",
      @"error" : error.localizedDescription ?: @"module registration failed",
    };
  }

  ALNSearchModuleRuntime *runtime = [ALNSearchModuleRuntime sharedRuntime];
  if (!Phase27SeedIndexes(runtime, &error)) {
    return @{
      @"status" : @"fail",
      @"error" : error.localizedDescription ?: @"index seed failed",
    };
  }

  NSDictionary *primary = [runtime searchQuery:priorityQuery
                            resourceIdentifier:@"products"
                                       filters:nil
                                          sort:nil
                                         limit:10
                                        offset:0
                                  queryOptions:@{ @"mode" : @"search", @"explain" : @YES }
                                         error:&error];
  if (primary == nil) {
    return @{
      @"status" : @"fail",
      @"error" : error.localizedDescription ?: @"primary query failed",
    };
  }

  NSDictionary *autocomplete = [runtime searchQuery:@"pri"
                                 resourceIdentifier:@"products"
                                            filters:nil
                                               sort:nil
                                              limit:10
                                             offset:0
                                       queryOptions:@{ @"mode" : @"autocomplete" }
                                              error:&error];
  if (autocomplete == nil) {
    return @{
      @"status" : @"fail",
      @"error" : error.localizedDescription ?: @"autocomplete query failed",
    };
  }

  NSDictionary *fuzzy = [runtime searchQuery:@"pririty"
                          resourceIdentifier:@"products"
                                     filters:nil
                                        sort:nil
                                       limit:10
                                      offset:0
                                queryOptions:@{ @"mode" : @"fuzzy" }
                                       error:&error];
  if (fuzzy == nil) {
    return @{
      @"status" : @"fail",
      @"error" : error.localizedDescription ?: @"fuzzy query failed",
    };
  }

  NSDictionary *adapterPageOne = [runtime searchQuery:adapterQuery
                                   resourceIdentifier:@"products"
                                              filters:nil
                                                 sort:nil
                                                limit:1
                                               offset:0
                                         queryOptions:@{ @"mode" : @"search", @"explain" : @YES }
                                                error:&error];
  if (adapterPageOne == nil) {
    return @{
      @"status" : @"fail",
      @"error" : error.localizedDescription ?: @"adapter query failed",
    };
  }

  NSMutableDictionary *engineSummary = [NSMutableDictionary dictionary];
  engineSummary[@"status"] = @"pass";
  engineSummary[@"engine"] = primary[@"engine"] ?: @"";
  engineSummary[@"queryModes"] = primary[@"availableModes"] ?: @[];
  engineSummary[@"topResults"] = Phase27TopResultIDs(primary, 3);
  engineSummary[@"topResult"] = Phase27FirstResultID(primary);
  engineSummary[@"promotedResults"] = Phase27TopResultIDs(@{ @"results" : primary[@"promotedResults"] ?: @[] }, 3);
  engineSummary[@"autocomplete"] = autocomplete[@"autocomplete"] ?: @[];
  engineSummary[@"suggestions"] = fuzzy[@"suggestions"] ?: @[];
  engineSummary[@"facets"] = primary[@"facets"] ?: @[];
  engineSummary[@"debug"] = primary[@"debug"] ?: @{};
  engineSummary[@"engineCapabilities"] = primary[@"engineCapabilities"] ?: @{};
  engineSummary[@"adapterSample"] = @{
    @"query" : adapterQuery ?: @"",
    @"topResults" : Phase27TopResultIDs(adapterPageOne, 2),
    @"cursor" : adapterPageOne[@"cursor"] ?: @{},
    @"debug" : adapterPageOne[@"debug"] ?: @{},
  };

  NSDictionary *productsDrilldown = [runtime resourceDrilldownForIdentifier:@"products"] ?: @{};
  NSDictionary *productsResource = [productsDrilldown[@"resource"] isKindOfClass:[NSDictionary class]]
                                       ? productsDrilldown[@"resource"]
                                       : @{};
  engineSummary[@"products"] = @{
    @"bulkImport" : productsResource[@"bulkImport"] ?: @{},
    @"engineDescriptor" : productsResource[@"engineDescriptor"] ?: @{},
    @"replayQueueDepth" : productsResource[@"replayQueueDepth"] ?: @0,
  };

  if (includeTenantMetadata) {
    NSDictionary *tenantMetadata = [runtime resourceMetadataForIdentifier:@"tenant_orders"] ?: @{};
    NSDictionary *tenantDrilldown = [runtime resourceDrilldownForIdentifier:@"tenant_orders"] ?: @{};
    NSDictionary *tenantResource = [tenantDrilldown[@"resource"] isKindOfClass:[NSDictionary class]]
                                       ? tenantDrilldown[@"resource"]
                                       : @{};
    engineSummary[@"tenantOrders"] = @{
      @"visibility" : tenantMetadata[@"visibility"] ?: @{},
      @"syncPolicy" : tenantMetadata[@"syncPolicy"] ?: @{},
      @"bulkImport" : tenantResource[@"bulkImport"] ?: @{},
    };
  }

  NSDictionary *dashboard = [runtime dashboardSummary] ?: @{};
  engineSummary[@"dashboard"] = @{
    @"engine" : dashboard[@"engine"] ?: @{},
    @"totals" : dashboard[@"totals"] ?: @{},
    @"recentQueries" : dashboard[@"recentQueries"] ?: @[],
  };
  return engineSummary;
}

static NSDictionary *Phase27SkippedPayload(NSString *reason) {
  return @{
    @"status" : @"skipped",
    @"reason" : reason ?: @"not_configured",
  };
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    (void)argc;
    (void)argv;

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[@"version"] = @"phase27-search-characterization-v1";
    payload[@"generatedAt"] = @([[NSDate date] timeIntervalSince1970]);

    payload[@"default"] = Phase27CharacterizeEngine(nil, nil, @"priority", @"priority", YES);

    payload[@"meilisearch"] = Phase27CharacterizeEngine(@{
      @"engineClass" : @"ALNMeilisearchSearchEngine",
      @"engine" : @{
        @"meilisearch" : @{
          @"fixturesPath" : Phase27SearchFixturesPath(@"meilisearch_fixtures.json"),
          @"indexPrefix" : @"phase27meili",
          @"rankingRules" : @[ @"words", @"typo", @"sort" ],
        },
      },
    },
                                                         nil,
                                                         @"priority",
                                                         @"kit",
                                                         NO);

    payload[@"opensearch"] = Phase27CharacterizeEngine(@{
      @"engineClass" : @"ALNOpenSearchSearchEngine",
      @"engine" : @{
        @"opensearch" : @{
          @"fixturesPath" : Phase27SearchFixturesPath(@"opensearch_fixtures.json"),
          @"indexPrefix" : @"phase27os",
          @"analysis" : @{ @"analyzer" : @"standard" },
          @"aliases" : @[ @"phase27_products_active" ],
        },
      },
    },
                                                        nil,
                                                        @"priority",
                                                        @"kit",
                                                        NO);

    NSString *postgresDSN = Phase27EnvString(@"ARLEN_PG_TEST_DSN");
    if ([postgresDSN length] > 0) {
      payload[@"postgres"] = Phase27CharacterizeEngine(@{
        @"engineClass" : @"ALNPostgresSearchEngine",
        @"engine" : @{
          @"postgres" : @{
            @"tableName" : Phase27SearchUniquePostgresTableName(),
            @"textSearchConfiguration" : @"simple",
          },
        },
      },
                                                           @{
                                                             @"connectionString" : postgresDSN,
                                                           },
                                                           @"Priority Kit",
                                                           @"Priority Kit",
                                                           NO);
    } else {
      payload[@"postgres"] = Phase27SkippedPayload(@"missing_ARLEN_PG_TEST_DSN");
    }

    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (json == nil) {
      fprintf(stderr, "phase27-search-characterize: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}\n";
    fprintf(stdout, "%s\n", [text UTF8String]);
    return 0;
  }
}
