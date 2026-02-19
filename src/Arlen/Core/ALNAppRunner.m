#import "ALNAppRunner.h"

#import <stdio.h>
#import <stdlib.h>

#import "ALNApplication.h"
#import "ALNHTTPServer.h"

static void ALNPrintUsage(void) {
  fprintf(stdout,
          "Usage: boomhauer [--port <port>] [--host <addr>] [--env <env>] "
          "[--once] [--print-routes]\n");
}

int ALNRunAppMain(int argc, const char * _Nonnull const * _Nonnull argv,
                  ALNRouteRegistrationCallback registerRoutes) {
  int portOverride = 0;
  NSString *host = nil;
  NSString *environment = @"development";
  BOOL once = NO;
  BOOL printRoutes = NO;

  for (int idx = 1; idx < argc; idx++) {
    NSString *arg = [NSString stringWithUTF8String:argv[idx]];
    if ([arg isEqualToString:@"--port"]) {
      if (idx + 1 >= argc) {
        ALNPrintUsage();
        return 2;
      }
      portOverride = atoi(argv[++idx]);
    } else if ([arg isEqualToString:@"--host"]) {
      if (idx + 1 >= argc) {
        ALNPrintUsage();
        return 2;
      }
      host = [NSString stringWithUTF8String:argv[++idx]];
    } else if ([arg isEqualToString:@"--env"]) {
      if (idx + 1 >= argc) {
        ALNPrintUsage();
        return 2;
      }
      environment = [NSString stringWithUTF8String:argv[++idx]];
    } else if ([arg isEqualToString:@"--once"]) {
      once = YES;
    } else if ([arg isEqualToString:@"--print-routes"]) {
      printRoutes = YES;
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      ALNPrintUsage();
      return 0;
    } else {
      fprintf(stderr, "Unknown argument: %s\n", argv[idx]);
      return 2;
    }
  }

  NSString *appRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSError *error = nil;
  ALNApplication *app = [[ALNApplication alloc] initWithEnvironment:environment
                                                         configRoot:appRoot
                                                              error:&error];
  if (app == nil) {
    fprintf(stderr, "failed loading config: %s\n", [[error localizedDescription] UTF8String]);
    return 1;
  }

  if (registerRoutes != NULL) {
    registerRoutes(app);
  }

  ALNHTTPServer *server =
      [[ALNHTTPServer alloc] initWithApplication:app
                                      publicRoot:[appRoot stringByAppendingPathComponent:@"public"]];
  server.serverName = @"boomhauer";

  if (printRoutes) {
    [server printRoutesToFile:stdout];
    return 0;
  }

  return [server runWithHost:host portOverride:portOverride once:once];
}
