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
  BOOL rendered = [self renderTemplate:@"home/index"
                               context:viewContext
                                layout:@"layouts/main"
                                 error:&error];
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
  BOOL rendered = [self renderTemplate:@"dashboard/index"
                               context:viewContext
                                layout:@"layouts/main"
                                 error:&error];
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
  BOOL rendered = [self renderTemplate:@"users/show"
                               context:viewContext
                                layout:@"layouts/main"
                                 error:&error];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:[NSString stringWithFormat:@"user render failed: %@",
                                                error.localizedDescription ?: @"unknown"]];
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
