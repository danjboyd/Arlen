#import <Foundation/Foundation.h>

#import <stdlib.h>
#import <time.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNJSONSerialization.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

@interface ALNDispatchBenchController : ALNController
@end

@implementation ALNDispatchBenchController

- (BOOL)allow:(ALNContext *)context {
  (void)context;
  return YES;
}

- (void)ping:(ALNContext *)context {
  (void)context;
  [self renderText:@"ok"];  // Keep response work deterministic and minimal.
}

@end

static void PrintUsage(void) {
  fprintf(stderr,
          "Usage: dispatch_perf_bench [--mode <cached_imp|selector>] [--iterations <count>] "
          "[--warmup <count>]\n");
}

static double ALNMonotonicMicros(void) {
  struct timespec ts;
#ifdef CLOCK_MONOTONIC_RAW
  const clockid_t clockID = CLOCK_MONOTONIC_RAW;
#else
  const clockid_t clockID = CLOCK_MONOTONIC;
#endif
  if (clock_gettime(clockID, &ts) != 0) {
    return 0.0;
  }
  return ((double)ts.tv_sec * 1000000.0) + ((double)ts.tv_nsec / 1000.0);
}

static NSDictionary *TimingSummaryFromSamples(NSArray<NSNumber *> *samplesMicros) {
  if ([samplesMicros count] == 0) {
    return @{
      @"iterations" : @0,
      @"avg_us" : @0,
      @"p95_us" : @0,
      @"ops_per_sec" : @0,
      @"total_seconds" : @0,
    };
  }

  double totalMicros = 0.0;
  for (NSNumber *sample in samplesMicros) {
    totalMicros += [sample doubleValue];
  }

  NSArray<NSNumber *> *sorted = [samplesMicros sortedArrayUsingSelector:@selector(compare:)];
  NSUInteger p95Index = (NSUInteger)ceil((double)[sorted count] * 0.95);
  if (p95Index == 0) {
    p95Index = 1;
  }
  p95Index -= 1;
  if (p95Index >= [sorted count]) {
    p95Index = [sorted count] - 1;
  }

  double avgMicros = totalMicros / (double)[samplesMicros count];
  double totalSeconds = totalMicros / 1000000.0;
  double opsPerSecond = (totalSeconds > 0.0) ? ((double)[samplesMicros count] / totalSeconds) : 0.0;

  return @{
    @"iterations" : @([samplesMicros count]),
    @"avg_us" : @(avgMicros),
    @"p95_us" : @([sorted[p95Index] doubleValue]),
    @"ops_per_sec" : @(opsPerSecond),
    @"total_seconds" : @(totalSeconds),
  };
}

static NSDictionary *RunDispatchBenchmark(NSString *mode,
                                          NSUInteger warmup,
                                          NSUInteger iterations,
                                          NSError **errorOut) {
  if (![mode isEqualToString:@"cached_imp"] && ![mode isEqualToString:@"selector"]) {
    if (errorOut != NULL) {
      *errorOut = [NSError errorWithDomain:@"Arlen.Dispatch.Bench"
                                      code:1
                                  userInfo:@{ NSLocalizedDescriptionKey : @"mode must be cached_imp or selector" }];
    }
    return nil;
  }

  setenv("ARLEN_RUNTIME_INVOCATION_MODE", [mode UTF8String], 1);

  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"performanceLogging" : @(NO),
    @"apiOnly" : @(YES),
    @"securityHeaders" : @{ @"enabled" : @(NO) },
    @"rateLimit" : @{ @"enabled" : @(NO) },
    @"session" : @{ @"enabled" : @(NO), @"secret" : @"" },
    @"csrf" : @{ @"enabled" : @(NO) },
    @"auth" : @{ @"enabled" : @(NO), @"bearerSecret" : @"" },
  }];
  [app registerRouteMethod:@"GET"
                      path:@"/ping"
                      name:@"bench_ping"
                   formats:nil
           controllerClass:[ALNDispatchBenchController class]
               guardAction:@"allow"
                    action:@"ping"];

  NSError *startError = nil;
  if (![app startWithError:&startError]) {
    if (errorOut != NULL) {
      *errorOut = startError ?: [NSError errorWithDomain:@"Arlen.Dispatch.Bench"
                                                    code:2
                                                userInfo:@{ NSLocalizedDescriptionKey : @"application failed to start" }];
    }
    return nil;
  }

  NSMutableArray<NSNumber *> *samples = [NSMutableArray arrayWithCapacity:iterations];
  @try {
    for (NSUInteger idx = 0; idx < warmup; idx++) {
      @autoreleasepool {
        ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET"
                                                            path:@"/ping"
                                                     queryString:@""
                                                         headers:@{}
                                                            body:[NSData data]];
        ALNResponse *response = [app dispatchRequest:request];
        if (response.statusCode != 200) {
          if (errorOut != NULL) {
            *errorOut = [NSError errorWithDomain:@"Arlen.Dispatch.Bench"
                                            code:3
                                        userInfo:@{ NSLocalizedDescriptionKey : @"warmup dispatch failed" }];
          }
          return nil;
        }
      }
    }

    for (NSUInteger idx = 0; idx < iterations; idx++) {
      @autoreleasepool {
        ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET"
                                                            path:@"/ping"
                                                     queryString:@""
                                                         headers:@{}
                                                            body:[NSData data]];
        double startMicros = ALNMonotonicMicros();
        ALNResponse *response = [app dispatchRequest:request];
        double elapsedMicros = ALNMonotonicMicros() - startMicros;
        if (elapsedMicros < 0.0) {
          elapsedMicros = 0.0;
        }
        if (response.statusCode != 200) {
          if (errorOut != NULL) {
            *errorOut = [NSError errorWithDomain:@"Arlen.Dispatch.Bench"
                                            code:4
                                        userInfo:@{ NSLocalizedDescriptionKey : @"dispatch failed" }];
          }
          return nil;
        }
        [samples addObject:@(elapsedMicros)];
      }
    }
  } @finally {
    [app shutdown];
  }

  return @{ @"mode" : app.runtimeInvocationMode ?: mode,
            @"timing" : TimingSummaryFromSamples(samples) };
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *mode = @"cached_imp";
    NSUInteger iterations = 50000;
    NSUInteger warmup = 5000;

    NSMutableArray<NSString *> *args = [NSMutableArray arrayWithCapacity:(NSUInteger)MAX(argc - 1, 0)];
    for (int idx = 1; idx < argc; idx++) {
      [args addObject:[NSString stringWithUTF8String:argv[idx]]];
    }

    for (NSUInteger idx = 0; idx < [args count]; idx++) {
      NSString *arg = args[idx];
      if ([arg isEqualToString:@"--mode"]) {
        if (idx + 1 >= [args count]) {
          PrintUsage();
          return 2;
        }
        mode = [[args[idx + 1] lowercaseString] copy];
        idx += 1;
      } else if ([arg isEqualToString:@"--iterations"]) {
        if (idx + 1 >= [args count]) {
          PrintUsage();
          return 2;
        }
        NSInteger parsed = [args[idx + 1] integerValue];
        idx += 1;
        iterations = (parsed > 0) ? (NSUInteger)parsed : 1;
      } else if ([arg isEqualToString:@"--warmup"]) {
        if (idx + 1 >= [args count]) {
          PrintUsage();
          return 2;
        }
        NSInteger parsed = [args[idx + 1] integerValue];
        idx += 1;
        warmup = (parsed > 0) ? (NSUInteger)parsed : 0;
      } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
        PrintUsage();
        return 0;
      } else {
        fprintf(stderr, "dispatch_perf_bench: unknown option %s\n", [arg UTF8String]);
        PrintUsage();
        return 2;
      }
    }

    NSError *error = nil;
    NSDictionary *result = RunDispatchBenchmark(mode, warmup, iterations, &error);
    if (result == nil) {
      fprintf(stderr,
              "dispatch_perf_bench: benchmark failed (%s): %s\n",
              [mode UTF8String],
              [[error localizedDescription] UTF8String]);
      return 1;
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";

    NSDictionary *payload = @{
      @"version" : @"phase10g-dispatch-benchmark-v1",
      @"mode" : result[@"mode"] ?: mode,
      @"iterations" : @(iterations),
      @"warmup" : @(warmup),
      @"timing" : result[@"timing"] ?: @{},
      @"generated_at" : [formatter stringFromDate:[NSDate date]],
    };

    NSJSONWritingOptions writeOptions = NSJSONWritingPrettyPrinted;
#ifdef NSJSONWritingSortedKeys
    writeOptions |= NSJSONWritingSortedKeys;
#endif
    NSError *jsonError = nil;
    NSData *json = [ALNJSONSerialization dataWithJSONObject:payload
                                                    options:writeOptions
                                                      error:&jsonError];
    if (json == nil) {
      fprintf(stderr,
              "dispatch_perf_bench: failed encoding output: %s\n",
              [[jsonError localizedDescription] UTF8String]);
      return 1;
    }

    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}";
    fprintf(stdout, "%s\n", [text UTF8String]);
  }

  return 0;
}
