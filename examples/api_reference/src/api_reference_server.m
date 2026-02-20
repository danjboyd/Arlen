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

@interface APIReferenceController : ALNController
@end

@implementation APIReferenceController

- (id)status:(ALNContext *)ctx {
  (void)ctx;
  return @{
    @"ok" : @(YES),
    @"application" : @"api_reference_server",
    @"server" : @"boomhauer",
  };
}

- (id)showUser:(ALNContext *)ctx {
  (void)ctx;
  NSNumber *userID = [self validatedValueForName:@"id"] ?: @0;
  NSNumber *verbose = [self validatedValueForName:@"verbose"] ?: @(NO);
  return @{
    @"id" : userID,
    @"verbose" : verbose,
    @"subject" : [self authSubject] ?: @"",
    @"source" : @"api_reference",
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
    fprintf(stderr, "api-reference-server: failed loading config from %s: %s\n",
            [appRoot UTF8String], [[error localizedDescription] UTF8String]);
    return nil;
  }

  [app registerRouteMethod:@"GET"
                      path:@"/api/reference/status"
                      name:@"api_reference_status"
           controllerClass:[APIReferenceController class]
                    action:@"status"];
  [app registerRouteMethod:@"GET"
                      path:@"/api/reference/users/:id"
                      name:@"api_reference_user_show"
           controllerClass:[APIReferenceController class]
                    action:@"showUser"];
  [app registerRouteMethod:@"GET"
                      path:@"/healthz"
                      name:@"healthz"
           controllerClass:[HealthController class]
                    action:@"check"];

  NSError *routeError = nil;
  BOOL configured = [app configureRouteNamed:@"api_reference_user_show"
                               requestSchema:@{
                                 @"type" : @"object",
                                 @"properties" : @{
                                   @"id" : @{
                                     @"type" : @"integer",
                                     @"source" : @"path",
                                     @"required" : @(YES),
                                   },
                                   @"verbose" : @{
                                     @"type" : @"boolean",
                                     @"source" : @"query",
                                     @"default" : @(NO),
                                   },
                                 },
                               }
                              responseSchema:@{
                                @"type" : @"object",
                                @"properties" : @{
                                  @"id" : @{ @"type" : @"integer" },
                                  @"verbose" : @{ @"type" : @"boolean" },
                                  @"subject" : @{ @"type" : @"string" },
                                  @"source" : @{ @"type" : @"string" },
                                },
                                @"required" : @[ @"id", @"verbose", @"subject", @"source" ]
                              }
                                     summary:@"Fetch API reference user"
                                 operationID:@"apiReferenceUserShow"
                                        tags:@[ @"reference", @"users" ]
                               requiredScopes:@[ @"users:read" ]
                                requiredRoles:nil
                              includeInOpenAPI:YES
                                        error:&routeError];
  if (!configured) {
    fprintf(stderr, "api-reference-server: failed configuring route: %s\n",
            [[routeError localizedDescription] UTF8String]);
    return nil;
  }

  configured = [app configureRouteNamed:@"api_reference_status"
                          requestSchema:nil
                         responseSchema:@{
                           @"type" : @"object",
                           @"properties" : @{
                             @"ok" : @{ @"type" : @"boolean" },
                             @"application" : @{ @"type" : @"string" },
                             @"server" : @{ @"type" : @"string" },
                           },
                           @"required" : @[ @"ok", @"application", @"server" ]
                         }
                                summary:@"API reference status"
                            operationID:@"apiReferenceStatus"
                                   tags:@[ @"reference" ]
                          requiredScopes:nil
                           requiredRoles:nil
                         includeInOpenAPI:YES
                                   error:&routeError];
  if (!configured) {
    fprintf(stderr, "api-reference-server: failed configuring status route: %s\n",
            [[routeError localizedDescription] UTF8String]);
    return nil;
  }

  return app;
}

static void PrintUsage(void) {
  fprintf(stdout,
          "Usage: api-reference-server [--port <port>] [--host <addr>] [--env <env>] [--once] [--print-routes]\n");
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
    server.serverName = @"api-reference-server";

    if (printRoutes) {
      [server printRoutesToFile:stdout];
      return 0;
    }

    return [server runWithHost:host portOverride:portOverride once:once];
  }
}
