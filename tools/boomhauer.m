#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>

#import "ArlenServer.h"

@interface HomeController : ALNController
@end

@implementation HomeController

- (id)index:(ALNContext *)ctx {
  NSDictionary *viewContext = @{
    @"title" : @"Arlen EOC Dev Server",
    @"items" : @[
      @"render pipeline ok",
      [NSString stringWithFormat:@"request path: %@", ctx.request.path ?: @"/"],
      @"unsafe sample: <unsafe>"
    ]
  };

  NSError *error = nil;
  BOOL rendered = [self renderTemplate:@"index" context:viewContext error:&error];
  if (!rendered) {
    [self setStatus:500];
    [self renderText:[NSString stringWithFormat:@"render failed: %@",
                                                error.localizedDescription ?: @"unknown"]];
  }
  return nil;
}

- (id)about:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"Arlen Phase 1 server\n"];
  return nil;
}

@end

@interface ApiController : ALNController
@end

@implementation ApiController

- (id)status:(ALNContext *)ctx {
  (void)ctx;
  return @{
    @"ok" : @(YES),
    @"server" : @"boomhauer",
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
  };
}

- (id)echo:(ALNContext *)ctx {
  NSString *name = ctx.params[@"name"] ?: @"unknown";
  return @{
    @"name" : name,
    @"path" : ctx.request.path ?: @"",
  };
}

- (id)requestMeta:(ALNContext *)ctx {
  return @{
    @"remoteAddress" : ctx.request.remoteAddress ?: @"",
    @"effectiveRemoteAddress" : ctx.request.effectiveRemoteAddress ?: @"",
    @"scheme" : ctx.request.scheme ?: @"http",
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

static ALNApplication *BuildApplication(NSString *environment) {
  NSError *error = nil;
  ALNApplication *app = [[ALNApplication alloc] initWithEnvironment:environment
                                                         configRoot:[[NSFileManager defaultManager]
                                                                       currentDirectoryPath]
                                                              error:&error];
  if (app == nil) {
    fprintf(stderr, "boomhauer: failed loading config: %s\n", [[error localizedDescription] UTF8String]);
    return nil;
  }

  [app registerRouteMethod:@"GET"
                      path:@"/"
                      name:@"home"
           controllerClass:[HomeController class]
                    action:@"index"];
  [app registerRouteMethod:@"GET"
                      path:@"/about"
                      name:@"about"
           controllerClass:[HomeController class]
                    action:@"about"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/status"
                      name:@"api_status"
           controllerClass:[ApiController class]
                    action:@"status"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/echo/:name"
                      name:@"api_echo"
           controllerClass:[ApiController class]
                    action:@"echo"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/request-meta"
                      name:@"api_request_meta"
           controllerClass:[ApiController class]
                    action:@"requestMeta"];
  [app registerRouteMethod:@"GET"
                      path:@"/healthz"
                      name:@"healthz"
           controllerClass:[HealthController class]
                    action:@"check"];
  return app;
}

static void PrintUsage(void) {
  fprintf(stdout,
          "Usage: boomhauer [--port <port>] [--host <addr>] [--env <env>] [--once] [--print-routes]\n");
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

    ALNApplication *app = BuildApplication(environment);
    if (app == nil) {
      return 1;
    }

    NSString *publicRoot = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent:@"public"];
    ALNHTTPServer *server = [[ALNHTTPServer alloc] initWithApplication:app publicRoot:publicRoot];
    server.serverName = @"boomhauer";

    if (printRoutes) {
      [server printRoutesToFile:stdout];
      return 0;
    }

    return [server runWithHost:host portOverride:portOverride once:once];
  }
}
