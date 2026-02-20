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

@interface MigrationController : ALNController
@end

@implementation MigrationController

- (id)legacyUser:(ALNContext *)ctx {
  NSString *identifier = ctx.params[@"id"] ?: @"unknown";
  [self renderText:[NSString stringWithFormat:@"user:%@\n", identifier]];
  return nil;
}

- (id)arlenUser:(ALNContext *)ctx {
  NSString *identifier = ctx.params[@"id"] ?: @"unknown";
  [self renderText:[NSString stringWithFormat:@"user:%@\n", identifier]];
  return nil;
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
    fprintf(stderr, "migration-sample-server: failed loading config from %s: %s\n",
            [appRoot UTF8String], [[error localizedDescription] UTF8String]);
    return nil;
  }

  [app registerRouteMethod:@"GET"
                      path:@"/legacy/users/:id"
                      name:@"legacy_user"
           controllerClass:[MigrationController class]
                    action:@"legacyUser"];
  [app registerRouteMethod:@"GET"
                      path:@"/arlen/users/:id"
                      name:@"arlen_user"
           controllerClass:[MigrationController class]
                    action:@"arlenUser"];
  [app registerRouteMethod:@"GET"
                      path:@"/healthz"
                      name:@"healthz"
           controllerClass:[HealthController class]
                    action:@"check"];
  return app;
}

static void PrintUsage(void) {
  fprintf(stdout,
          "Usage: migration-sample-server [--port <port>] [--host <addr>] [--env <env>] [--once] [--print-routes]\n");
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
    ALNHTTPServer *server = [[ALNHTTPServer alloc] initWithApplication:app
                                                             publicRoot:publicRoot];
    server.serverName = @"migration-sample-server";

    if (printRoutes) {
      [server printRoutesToFile:stdout];
      return 0;
    }

    return [server runWithHost:host portOverride:portOverride once:once];
  }
}
