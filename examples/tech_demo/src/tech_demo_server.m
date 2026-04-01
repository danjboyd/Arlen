#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>

#import "ArlenServer.h"

static NSString *ALNEnvValue(const char *name) {
  const char *value = getenv(name);
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

static NSString *ALNResolveAppRoot(void) {
  NSString *override = ALNEnvValue("ARLEN_APP_ROOT");
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  if ([override length] == 0) {
    return cwd;
  }
  if ([override hasPrefix:@"/"]) {
    return [override stringByStandardizingPath];
  }
  return [[cwd stringByAppendingPathComponent:override] stringByStandardizingPath];
}

static NSString *ALNLiveDemoNormalizedValue(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL ALNLiveDemoMatchesFilter(NSString *candidate, NSString *filter) {
  NSString *normalizedFilter = [ALNLiveDemoNormalizedValue(filter) lowercaseString];
  if ([normalizedFilter length] == 0) {
    return YES;
  }
  return [[[ALNLiveDemoNormalizedValue(candidate) lowercaseString] copy]
      isEqualToString:normalizedFilter];
}

static NSArray *TechDemoOrderRecords(void) {
  return @[
    @{
      @"id" : @"ORD-100",
      @"owner" : @"Pat",
      @"status" : @"Queued",
      @"priority" : @"High",
      @"region" : @"Central"
    },
    @{
      @"id" : @"ORD-204",
      @"owner" : @"Peggy",
      @"status" : @"Review",
      @"priority" : @"Medium",
      @"region" : @"West"
    },
    @{
      @"id" : @"ORD-305",
      @"owner" : @"Hank",
      @"status" : @"Live",
      @"priority" : @"High",
      @"region" : @"Central"
    },
    @{
      @"id" : @"ORD-410",
      @"owner" : @"Pat",
      @"status" : @"Live",
      @"priority" : @"Low",
      @"region" : @"South"
    },
  ];
}

static NSArray *TechDemoFilteredOrders(NSString *ownerFilter, NSString *statusFilter) {
  NSMutableArray *filtered = [NSMutableArray array];
  for (NSDictionary *record in TechDemoOrderRecords()) {
    if (!ALNLiveDemoMatchesFilter(record[@"owner"], ownerFilter)) {
      continue;
    }
    if (!ALNLiveDemoMatchesFilter(record[@"status"], statusFilter)) {
      continue;
    }
    [filtered addObject:record];
  }
  return [NSArray arrayWithArray:filtered];
}

static NSDictionary *TechDemoLiveOrdersContext(NSDictionary *queryParams) {
  NSString *ownerFilter = ALNLiveDemoNormalizedValue(queryParams[@"owner"]);
  NSString *statusFilter = ALNLiveDemoNormalizedValue(queryParams[@"status"]);
  NSArray *orders = TechDemoFilteredOrders(ownerFilter, statusFilter);
  return @{
    @"ownerFilter" : ownerFilter ?: @"",
    @"ownerFilterLabel" : ([ownerFilter length] > 0 ? ownerFilter : @"All owners"),
    @"statusFilter" : statusFilter ?: @"",
    @"statusFilterLabel" : ([statusFilter length] > 0 ? statusFilter : @"All statuses"),
    @"orders" : orders,
    @"ordersCount" : @([orders count]),
  };
}

static NSArray *TechDemoInitialFeedItems(void) {
  return @[
    @{
      @"key" : @"row-alpha",
      @"label" : @"Alpha worker warmed and ready",
      @"tone" : @"neutral",
      @"meta" : @"just now"
    },
    @{
      @"key" : @"row-beta",
      @"label" : @"Beta deployment waiting on review",
      @"tone" : @"priority",
      @"meta" : @"queued"
    },
  ];
}

static NSString *TechDemoTimestampString(void) {
  static NSDateFormatter *formatter = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss 'UTC'";
  });
  return [formatter stringFromDate:[NSDate date]] ?: @"unknown";
}

static NSDictionary *TechDemoLivePageContext(ALNContext *ctx) {
  NSMutableDictionary *context = [NSMutableDictionary dictionaryWithDictionary:
                                                          TechDemoLiveOrdersContext(ctx.request.queryParams ?: @{})];
  context[@"pageTitle"] = @"Arlen Technology Demo";
  context[@"tagline"] = @"Phase 25 live fragments, keyed streams, deferred regions, and realtime fanout";
  context[@"feedItems"] = TechDemoInitialFeedItems();
  return [NSDictionary dictionaryWithDictionary:context];
}

static NSDictionary *TechDemoPulseContext(void) {
  return @{
    @"timestamp" : TechDemoTimestampString(),
    @"requestCount" : @"4 live fragments",
    @"status" : @"runtime steady"
  };
}

static NSDictionary *TechDemoInsightsContext(void) {
  return @{
    @"headline" : @"Lazy region hydrated",
    @"bullets" : @[
      @"HTML-first links and forms stay intact",
      @"Regions can hydrate on viewport entry",
      @"The same protocol handles local and websocket updates"
    ]
  };
}

static NSDictionary *TechDemoDeferredContext(void) {
  return @{
    @"headline" : @"Deferred fragment settled",
    @"notes" : @[
      @"This region waited before hydrating.",
      @"The target container stayed in place while content filled in.",
      @"Polling, lazy, and deferred paths all ride the same live runtime."
    ]
  };
}

static NSDictionary *TechDemoUploadSummaryContext(ALNContext *ctx) {
  NSString *contentType = [ctx.request headerValueForName:@"content-type"] ?: @"unknown";
  return @{
    @"bodyBytes" : @([ctx.request.body length]),
    @"contentType" : contentType,
    @"timestamp" : TechDemoTimestampString(),
  };
}

static NSDictionary *TechDemoFeedItemContext(NSString *key, NSString *label, BOOL prepend) {
  return @{
    @"key" : ALNLiveDemoNormalizedValue(key),
    @"label" : ([ALNLiveDemoNormalizedValue(label) length] > 0
                    ? ALNLiveDemoNormalizedValue(label)
                    : @"Live item"),
    @"tone" : (prepend ? @"priority" : @"neutral"),
    @"meta" : TechDemoTimestampString(),
  };
}

@interface RootController : ALNController
@end

@implementation RootController

- (id)index:(ALNContext *)ctx {
  (void)ctx;
  [self redirectTo:@"/tech-demo" status:302];
  return nil;
}

@end

@interface TechDemoController : ALNController
@end

@implementation TechDemoController

- (id)landing:(ALNContext *)ctx {
  NSDictionary *viewContext = @{
    @"pageTitle" : @"Arlen Technology Demo",
    @"tagline" : @"GNUstep-native MVC, EOC templates, and implicit JSON responses",
    @"effectiveRemoteAddress" : ctx.request.effectiveRemoteAddress ?: @"unknown",
    @"items" : @[
      @"controller dispatch with route params",
      @"layout + partial rendering in .html.eoc",
      @"implicit JSON conversion from NSDictionary/NSArray",
      @"Foundation-based config and logging",
      @"development static assets from /static/*"
    ]
  };

  NSError *error = nil;
  BOOL rendered = [self renderTemplate:@"home/index" context:viewContext error:&error];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:[NSString stringWithFormat:@"tech demo render failed: %@",
                                                error.localizedDescription ?: @"unknown"]];
  }
  return nil;
}

- (id)dashboard:(ALNContext *)ctx {
  NSString *tab = ctx.request.queryParams[@"tab"] ?: @"overview";
  NSDictionary *viewContext = @{
    @"pageTitle" : @"Arlen Technology Demo",
    @"tagline" : @"Request metrics and context visibility",
    @"activeTab" : tab,
    @"metrics" : @[
      @{
        @"name" : @"router",
        @"value" : @"method + path matching",
        @"notes" : @"static/parameterized/wildcard precedence"
      },
      @{
        @"name" : @"render",
        @"value" : @"EOC transpiled templates",
        @"notes" : @"auto-escape + raw output support"
      },
      @{
        @"name" : @"api",
        @"value" : @"implicit JSON",
        @"notes" : @"NSDictionary/NSArray return values"
      },
    ],
  };

  NSError *error = nil;
  BOOL rendered = [self renderTemplate:@"dashboard/index" context:viewContext error:&error];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:[NSString stringWithFormat:@"dashboard render failed: %@",
                                                error.localizedDescription ?: @"unknown"]];
  }
  return nil;
}

- (id)user:(ALNContext *)ctx {
  NSString *name = ctx.params[@"name"] ?: @"unknown";
  NSString *flag = ctx.request.queryParams[@"flag"] ?: @"none";

  NSDictionary *viewContext = @{
    @"pageTitle" : @"Arlen Technology Demo",
    @"tagline" : @"Route params and query params in templates",
    @"name" : name,
    @"flag" : flag,
    @"path" : ctx.request.path ?: @"/",
    @"query" : ctx.request.queryString ?: @"",
  };

  NSError *error = nil;
  BOOL rendered = [self renderTemplate:@"users/show" context:viewContext error:&error];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:[NSString stringWithFormat:@"user render failed: %@",
                                                error.localizedDescription ?: @"unknown"]];
  }
  return nil;
}

@end

@interface TechDemoLiveController : ALNController
@end

@implementation TechDemoLiveController

- (void)renderFailurePrefix:(NSString *)prefix error:(NSError *)error {
  [self setStatus:500];
  [self renderText:[NSString stringWithFormat:@"%@: %@",
                                              prefix ?: @"live demo error",
                                              error.localizedDescription ?: @"unknown"]];
}

- (BOOL)renderFragmentTemplate:(NSString *)templateName
                       context:(NSDictionary *)context
                         error:(NSError **)error {
  if ([self isLiveRequest]) {
    return [self renderLiveTemplate:templateName
                             target:nil
                             action:nil
                            context:context
                              error:error];
  }
  return [self renderTemplateWithoutLayout:templateName context:context error:error];
}

- (id)index:(ALNContext *)ctx {
  NSDictionary *viewContext = TechDemoLivePageContext(ctx);
  NSError *error = nil;
  if (![self renderTemplate:@"live/index" context:viewContext error:&error]) {
    [self renderFailurePrefix:@"live page render failed" error:error];
  }
  return nil;
}

- (id)orders:(ALNContext *)ctx {
  NSError *error = nil;
  if (![self renderFragmentTemplate:@"live/_orders"
                            context:TechDemoLiveOrdersContext(ctx.request.queryParams ?: @{})
                              error:&error]) {
    [self renderFailurePrefix:@"live orders render failed" error:error];
  }
  return nil;
}

- (id)pulse:(ALNContext *)ctx {
  NSError *error = nil;
  if (![self renderFragmentTemplate:@"live/_pulse" context:TechDemoPulseContext() error:&error]) {
    [self renderFailurePrefix:@"live pulse render failed" error:error];
  }
  return nil;
}

- (id)insights:(ALNContext *)ctx {
  NSError *error = nil;
  if (![self renderFragmentTemplate:@"live/_insights"
                            context:TechDemoInsightsContext()
                              error:&error]) {
    [self renderFailurePrefix:@"live insights render failed" error:error];
  }
  return nil;
}

- (id)deferred:(ALNContext *)ctx {
  NSError *error = nil;
  if (![self renderFragmentTemplate:@"live/_deferred"
                            context:TechDemoDeferredContext()
                              error:&error]) {
    [self renderFailurePrefix:@"live deferred render failed" error:error];
  }
  return nil;
}

- (id)upload:(ALNContext *)ctx {
  NSError *error = nil;
  if (![self renderFragmentTemplate:@"live/_upload_summary"
                            context:TechDemoUploadSummaryContext(ctx)
                              error:&error]) {
    [self renderFailurePrefix:@"live upload render failed" error:error];
  }
  return nil;
}

- (id)feedSocket:(ALNContext *)ctx {
  (void)ctx;
  [self acceptWebSocketChannel:@"tech_demo.live"];
  return nil;
}

- (id)feedPublish:(ALNContext *)ctx {
  NSString *key = ALNLiveDemoNormalizedValue(ctx.request.queryParams[@"key"]);
  if ([key length] == 0) {
    key = @"row-gamma";
  }
  NSString *label = ALNLiveDemoNormalizedValue(ctx.request.queryParams[@"label"]);
  NSNumber *prependValue = [self queryBooleanForName:@"prepend"];
  BOOL prepend = [prependValue boolValue];
  NSDictionary *itemContext = TechDemoFeedItemContext(key, label, prepend);

  NSError *error = nil;
  if ([self publishLiveKeyedTemplate:@"live/_feed_item"
                           container:@"#live-feed"
                                 key:key
                             prepend:prepend
                             context:@{ @"item" : itemContext }
                           onChannel:@"tech_demo.live"
                               error:&error] == 0 &&
      error != nil) {
    [self renderFailurePrefix:@"live feed publish failed" error:error];
    return nil;
  }

  if ([self isLiveRequest]) {
    if (![self renderLiveKeyedTemplate:@"live/_feed_item"
                             container:@"#live-feed"
                                   key:key
                               prepend:prepend
                               context:@{ @"item" : itemContext }
                                 error:&error]) {
      [self renderFailurePrefix:@"live feed response failed" error:error];
    }
  } else {
    [self redirectTo:@"/tech-demo/live" status:302];
  }
  return nil;
}

- (id)feedRemove:(ALNContext *)ctx {
  NSString *key = ALNLiveDemoNormalizedValue(ctx.request.queryParams[@"key"]);
  if ([key length] == 0) {
    key = @"row-beta";
  }
  NSDictionary *operation = [ALNLive removeKeyedOperationForContainer:@"#live-feed" key:key];
  NSError *error = nil;
  if ([self publishLiveOperations:@[ operation ] onChannel:@"tech_demo.live" error:&error] == 0 &&
      error != nil) {
    [self renderFailurePrefix:@"live feed remove publish failed" error:error];
    return nil;
  }

  if ([self isLiveRequest]) {
    if (![self renderLiveOperations:@[ operation ] error:&error]) {
      [self renderFailurePrefix:@"live feed remove response failed" error:error];
    }
  } else {
    [self redirectTo:@"/tech-demo/live" status:302];
  }
  return nil;
}

@end

@interface TechDemoAPIController : ALNController
@end

@implementation TechDemoAPIController

+ (NSJSONWritingOptions)jsonWritingOptions {
  return NSJSONWritingPrettyPrinted;
}

- (id)catalog:(ALNContext *)ctx {
  (void)ctx;
  return @[
    @{
      @"id" : @"widget-100",
      @"name" : @"Foundation Widget",
      @"price" : @(19.95),
    },
    @{
      @"id" : @"router-200",
      @"name" : @"Route Matcher Pro",
      @"price" : @(39.50),
    },
    @{
      @"id" : @"template-300",
      @"name" : @"EOC View Kit",
      @"price" : @(24.00),
    },
  ];
}

- (id)summary:(ALNContext *)ctx {
  return @{
    @"ok" : @(YES),
    @"framework" : @"Arlen",
    @"server" : @"tech-demo-server",
    @"path" : ctx.request.path ?: @"",
    @"query" : ctx.request.queryParams ?: @{},
    @"remoteAddress" : ctx.request.effectiveRemoteAddress ?: @"",
  };
}

@end

@interface HealthController : ALNController
@end

@implementation HealthController

- (id)check:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"ok\n"];
  return nil;
}

@end

static ALNApplication *BuildApplication(NSString *environment, NSString *appRoot) {
  NSError *error = nil;
  ALNApplication *app = [[ALNApplication alloc] initWithEnvironment:environment
                                                         configRoot:appRoot
                                                              error:&error];
  if (app == nil) {
    fprintf(stderr, "tech-demo-server: failed loading config from %s: %s\n", [appRoot UTF8String],
            [[error localizedDescription] UTF8String]);
    return nil;
  }

  [app registerRouteMethod:@"GET"
                      path:@"/"
                      name:@"root"
           controllerClass:[RootController class]
                    action:@"index"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo"
                      name:@"tech_demo_home"
           controllerClass:[TechDemoController class]
                    action:@"landing"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/dashboard"
                      name:@"tech_demo_dashboard"
           controllerClass:[TechDemoController class]
                    action:@"dashboard"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/live"
                      name:@"tech_demo_live"
           controllerClass:[TechDemoLiveController class]
                    action:@"index"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/live/orders"
                      name:@"tech_demo_live_orders"
           controllerClass:[TechDemoLiveController class]
                    action:@"orders"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/live/pulse"
                      name:@"tech_demo_live_pulse"
           controllerClass:[TechDemoLiveController class]
                    action:@"pulse"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/live/insights"
                      name:@"tech_demo_live_insights"
           controllerClass:[TechDemoLiveController class]
                    action:@"insights"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/live/deferred"
                      name:@"tech_demo_live_deferred"
           controllerClass:[TechDemoLiveController class]
                    action:@"deferred"];
  [app registerRouteMethod:@"POST"
                      path:@"/tech-demo/live/upload"
                      name:@"tech_demo_live_upload"
           controllerClass:[TechDemoLiveController class]
                    action:@"upload"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/live/feed/publish"
                      name:@"tech_demo_live_feed_publish"
           controllerClass:[TechDemoLiveController class]
                    action:@"feedPublish"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/live/feed/remove"
                      name:@"tech_demo_live_feed_remove"
           controllerClass:[TechDemoLiveController class]
                    action:@"feedRemove"];
  [app registerRouteMethod:@"GET"
                      path:@"/ws/channel/tech_demo.live"
                      name:@"tech_demo_live_feed_socket"
           controllerClass:[TechDemoLiveController class]
                    action:@"feedSocket"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/users/:name"
                      name:@"tech_demo_user"
           controllerClass:[TechDemoController class]
                    action:@"user"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/api/catalog"
                      name:@"tech_demo_api_catalog"
           controllerClass:[TechDemoAPIController class]
                    action:@"catalog"];
  [app registerRouteMethod:@"GET"
                      path:@"/tech-demo/api/summary"
                      name:@"tech_demo_api_summary"
           controllerClass:[TechDemoAPIController class]
                    action:@"summary"];
  [app registerRouteMethod:@"GET"
                      path:@"/healthz"
                      name:@"healthz"
           controllerClass:[HealthController class]
                    action:@"check"];
  return app;
}

static void PrintUsage(void) {
  fprintf(stdout,
          "Usage: tech-demo-server [--port <port>] [--host <addr>] [--env <env>] [--once] [--print-routes]\n");
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    int portOverride = 0;
    NSString *host = nil;
    NSString *environment = @"development";
    BOOL once = NO;
    BOOL printRoutes = NO;

    for (int idx = 1; idx < argc; idx++) {
      NSString *arg = [NSString stringWithUTF8String:argv[idx]];
      if ([arg isEqualToString:@"--port"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        portOverride = atoi(argv[++idx]);
      } else if ([arg isEqualToString:@"--host"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        host = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--env"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        environment = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--once"]) {
        once = YES;
      } else if ([arg isEqualToString:@"--print-routes"]) {
        printRoutes = YES;
      } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
        PrintUsage();
        return 0;
      } else {
        fprintf(stderr, "Unknown argument: %s\n", argv[idx]);
        return 2;
      }
    }

    NSString *appRoot = ALNResolveAppRoot();
    ALNApplication *app = BuildApplication(environment, appRoot);
    if (app == nil) {
      return 1;
    }

    NSString *publicRoot = [appRoot stringByAppendingPathComponent:@"public"];
    ALNHTTPServer *server = [[ALNHTTPServer alloc] initWithApplication:app publicRoot:publicRoot];
    server.serverName = @"tech-demo-server";

    if (printRoutes) {
      [server printRoutesToFile:stdout];
      return 0;
    }

    return [server runWithHost:host portOverride:portOverride once:once];
  }
}
