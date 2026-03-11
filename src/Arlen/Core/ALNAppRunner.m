#import "ALNAppRunner.h"

#import <float.h>
#import <stdio.h>
#import <stdlib.h>

#import "ALNApplication.h"
#import "ALNHTTPServer.h"

@protocol ALNAppRunnerJobsWorkerRuntime <NSObject>

+ (instancetype)sharedRuntime;

@property(nonatomic, strong, readonly, nullable) ALNApplication *application;

- (nullable NSDictionary *)runSchedulerAt:(nullable NSDate *)timestamp
                                    error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)runWorkerAt:(nullable NSDate *)timestamp
                                 limit:(NSUInteger)limit
                                 error:(NSError *_Nullable *_Nullable)error;

@end

static NSString *ALNResolvedAppRoot(void) {
  const char *envValue = getenv("ARLEN_APP_ROOT");
  if (envValue != NULL && envValue[0] != '\0') {
    return [[NSString stringWithUTF8String:envValue] stringByStandardizingPath];
  }
  return [[NSFileManager defaultManager] currentDirectoryPath];
}

static void ALNPrintUsage(void) {
  fprintf(stdout,
          "Usage: boomhauer [--port <port>] [--host <addr>] [--env <env>] "
          "[--once] [--print-routes]\n");
}

static int ALNRunJobsWorker(ALNApplication *application,
                            NSUInteger limit,
                            BOOL once,
                            BOOL runScheduler,
                            NSTimeInterval pollIntervalSeconds,
                            NSTimeInterval schedulerIntervalSeconds) {
  (void)application;
  Class runtimeClass = NSClassFromString(@"ALNJobsModuleRuntime");
  if (runtimeClass == Nil || ![runtimeClass respondsToSelector:@selector(sharedRuntime)]) {
    fprintf(stderr, "jobs worker: ALNJobsModuleRuntime is unavailable in this app binary\n");
    return 1;
  }

  id<ALNAppRunnerJobsWorkerRuntime> runtime = [runtimeClass sharedRuntime];
  if (runtime == nil || runtime.application == nil) {
    fprintf(stderr, "jobs worker: jobs module is not configured for this app\n");
    return 1;
  }

  if (pollIntervalSeconds < 0.0) {
    pollIntervalSeconds = 0.0;
  }
  if (schedulerIntervalSeconds < 0.0) {
    schedulerIntervalSeconds = 0.0;
  }

  NSTimeInterval nextSchedulerAt = runScheduler ? 0.0 : DBL_MAX;
  while (YES) {
    NSDate *now = [NSDate date];
    NSTimeInterval nowSeconds = [now timeIntervalSince1970];

    if (runScheduler && nowSeconds >= nextSchedulerAt) {
      NSError *schedulerError = nil;
      if ([runtime runSchedulerAt:now error:&schedulerError] == nil) {
        fprintf(stderr, "jobs worker: scheduler run failed: %s\n",
                [[schedulerError localizedDescription] UTF8String]);
        return 1;
      }
      nextSchedulerAt = nowSeconds + schedulerIntervalSeconds;
    }

    NSError *workerError = nil;
    NSDictionary *summary = [runtime runWorkerAt:now limit:limit error:&workerError];
    if (summary == nil) {
      fprintf(stderr, "jobs worker: worker run failed: %s\n",
              [[workerError localizedDescription] UTF8String]);
      return 1;
    }

    if (once) {
      return 0;
    }

    BOOL reachedRunLimit = [summary[@"reachedRunLimit"] boolValue];
    NSUInteger leasedCount = [summary[@"leasedCount"] respondsToSelector:@selector(unsignedIntegerValue)]
                                 ? [summary[@"leasedCount"] unsignedIntegerValue]
                                 : 0;
    NSUInteger acknowledgedCount =
        [summary[@"acknowledgedCount"] respondsToSelector:@selector(unsignedIntegerValue)]
            ? [summary[@"acknowledgedCount"] unsignedIntegerValue]
            : 0;
    NSUInteger retriedCount = [summary[@"retriedCount"] respondsToSelector:@selector(unsignedIntegerValue)]
                                  ? [summary[@"retriedCount"] unsignedIntegerValue]
                                  : 0;
    NSUInteger handlerErrorCount =
        [summary[@"handlerErrorCount"] respondsToSelector:@selector(unsignedIntegerValue)]
            ? [summary[@"handlerErrorCount"] unsignedIntegerValue]
            : 0;

    BOOL didWork = (leasedCount > 0 || acknowledgedCount > 0 || retriedCount > 0 || handlerErrorCount > 0);
    if (reachedRunLimit || didWork) {
      continue;
    }
    if (pollIntervalSeconds > 0.0) {
      [NSThread sleepForTimeInterval:pollIntervalSeconds];
    }
  }
}

int ALNRunAppMain(int argc, const char * _Nonnull const * _Nonnull argv,
                  ALNRouteRegistrationCallback registerRoutes) {
  int portOverride = 0;
  NSString *host = nil;
  NSString *environment = @"development";
  BOOL once = NO;
  BOOL printRoutes = NO;
  BOOL jobsWorkerMode = NO;
  BOOL jobsWorkerOnce = NO;
  BOOL jobsWorkerRunScheduler = NO;
  NSUInteger jobsWorkerLimit = 0;
  NSTimeInterval jobsWorkerPollIntervalSeconds = 5.0;
  NSTimeInterval jobsWorkerSchedulerIntervalSeconds = 60.0;

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
    } else if ([arg isEqualToString:@"--jobs-worker"]) {
      jobsWorkerMode = YES;
    } else if ([arg isEqualToString:@"--jobs-worker-once"]) {
      jobsWorkerMode = YES;
      jobsWorkerOnce = YES;
    } else if ([arg isEqualToString:@"--jobs-worker-run-scheduler"]) {
      jobsWorkerMode = YES;
      jobsWorkerRunScheduler = YES;
    } else if ([arg isEqualToString:@"--jobs-worker-limit"]) {
      if (idx + 1 >= argc) {
        ALNPrintUsage();
        return 2;
      }
      jobsWorkerMode = YES;
      int parsedLimit = atoi(argv[++idx]);
      jobsWorkerLimit = (NSUInteger)MAX(0, parsedLimit);
    } else if ([arg isEqualToString:@"--jobs-worker-poll-interval-seconds"]) {
      if (idx + 1 >= argc) {
        ALNPrintUsage();
        return 2;
      }
      jobsWorkerMode = YES;
      jobsWorkerPollIntervalSeconds = atof(argv[++idx]);
    } else if ([arg isEqualToString:@"--jobs-worker-scheduler-interval-seconds"]) {
      if (idx + 1 >= argc) {
        ALNPrintUsage();
        return 2;
      }
      jobsWorkerMode = YES;
      jobsWorkerSchedulerIntervalSeconds = atof(argv[++idx]);
    } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
      ALNPrintUsage();
      return 0;
    } else {
      fprintf(stderr, "Unknown argument: %s\n", argv[idx]);
      return 2;
    }
  }

  NSString *appRoot = ALNResolvedAppRoot();
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

  if (jobsWorkerMode) {
    return ALNRunJobsWorker(app,
                            jobsWorkerLimit,
                            jobsWorkerOnce,
                            jobsWorkerRunScheduler,
                            jobsWorkerPollIntervalSeconds,
                            jobsWorkerSchedulerIntervalSeconds);
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
