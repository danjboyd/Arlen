#import <Foundation/Foundation.h>

#import <time.h>

#import "ALNJSONSerialization.h"
#import "ALNRouter.h"

@interface ALNRouteMatchBenchController : NSObject
@end

@implementation ALNRouteMatchBenchController

- (id)index:(id)context {
  (void)context;
  return nil;
}

@end

static void PrintUsage(void) {
  fprintf(stderr,
          "Usage: route_match_perf_bench [--route-count <count>] [--iterations <count>] "
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

static ALNRouter *BuildLargeRouteTable(NSUInteger routeCount, NSUInteger *actualRouteCountOut) {
  NSUInteger perKind = routeCount / 3;
  if (perKind == 0) {
    perKind = 1;
  }

  ALNRouter *router = [[ALNRouter alloc] init];
  for (NSUInteger idx = 0; idx < perKind; idx++) {
    NSString *staticPath = [NSString stringWithFormat:@"/bench/static/%lu", (unsigned long)idx];
    NSString *staticName = [NSString stringWithFormat:@"bench_static_%lu", (unsigned long)idx];
    [router addRouteMethod:@"GET"
                      path:staticPath
                      name:staticName
           controllerClass:[ALNRouteMatchBenchController class]
                    action:@"index"];

    NSString *paramPath = [NSString stringWithFormat:@"/bench/tenant/%lu/:id", (unsigned long)idx];
    NSString *paramName = [NSString stringWithFormat:@"bench_param_%lu", (unsigned long)idx];
    [router addRouteMethod:@"GET"
                      path:paramPath
                      name:paramName
           controllerClass:[ALNRouteMatchBenchController class]
                    action:@"index"];

    NSString *wildPath = [NSString stringWithFormat:@"/bench/wild/%lu/*tail", (unsigned long)idx];
    NSString *wildName = [NSString stringWithFormat:@"bench_wild_%lu", (unsigned long)idx];
    [router addRouteMethod:@"GET"
                      path:wildPath
                      name:wildName
           controllerClass:[ALNRouteMatchBenchController class]
                    action:@"index"];
  }

  if (actualRouteCountOut != NULL) {
    *actualRouteCountOut = perKind * 3;
  }
  return router;
}

static NSDictionary *RunScenario(ALNRouter *router,
                                 NSString *name,
                                 NSString *method,
                                 NSString *path,
                                 BOOL expectMatch,
                                 NSUInteger warmupIterations,
                                 NSUInteger measureIterations,
                                 NSError **errorOut) {
  if (router == nil) {
    if (errorOut != NULL) {
      *errorOut = [NSError errorWithDomain:@"Arlen.Route.Match.Perf"
                                      code:1
                                  userInfo:@{ NSLocalizedDescriptionKey : @"router is nil" }];
    }
    return nil;
  }

  for (NSUInteger idx = 0; idx < warmupIterations; idx++) {
    ALNRouteMatch *match = [router matchMethod:method path:path];
    BOOL matched = (match != nil);
    if (matched != expectMatch) {
      if (errorOut != NULL) {
        NSString *message = [NSString stringWithFormat:@"warmup scenario %@ expectation failed", name];
        *errorOut = [NSError errorWithDomain:@"Arlen.Route.Match.Perf"
                                        code:2
                                    userInfo:@{ NSLocalizedDescriptionKey : message }];
      }
      return nil;
    }
  }

  NSMutableArray<NSNumber *> *samples = [NSMutableArray arrayWithCapacity:measureIterations];
  for (NSUInteger idx = 0; idx < measureIterations; idx++) {
    double startMicros = ALNMonotonicMicros();
    ALNRouteMatch *match = [router matchMethod:method path:path];
    double elapsedMicros = ALNMonotonicMicros() - startMicros;
    if (elapsedMicros < 0.0) {
      elapsedMicros = 0.0;
    }
    BOOL matched = (match != nil);
    if (matched != expectMatch) {
      if (errorOut != NULL) {
        NSString *message = [NSString stringWithFormat:@"measure scenario %@ expectation failed", name];
        *errorOut = [NSError errorWithDomain:@"Arlen.Route.Match.Perf"
                                        code:3
                                    userInfo:@{ NSLocalizedDescriptionKey : message }];
      }
      return nil;
    }
    [samples addObject:@(elapsedMicros)];
  }

  return @{
    @"scenario" : name ?: @"unknown",
    @"method" : method ?: @"GET",
    @"path" : path ?: @"/",
    @"expect_match" : @(expectMatch),
    @"timing" : TimingSummaryFromSamples(samples),
  };
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSUInteger routeCount = 12000;
    NSUInteger iterations = 15000;
    NSUInteger warmup = 1500;

    NSMutableArray<NSString *> *args = [NSMutableArray arrayWithCapacity:(NSUInteger)MAX(argc - 1, 0)];
    for (int idx = 1; idx < argc; idx++) {
      [args addObject:[NSString stringWithUTF8String:argv[idx]]];
    }

    for (NSUInteger idx = 0; idx < [args count]; idx++) {
      NSString *arg = args[idx];
      if ([arg isEqualToString:@"--route-count"]) {
        if (idx + 1 >= [args count]) {
          PrintUsage();
          return 2;
        }
        NSInteger parsed = [args[idx + 1] integerValue];
        idx += 1;
        routeCount = (parsed > 0) ? (NSUInteger)parsed : 1;
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
        fprintf(stderr, "route_match_perf_bench: unknown option %s\n", [arg UTF8String]);
        PrintUsage();
        return 2;
      }
    }

    NSUInteger actualRouteCount = 0;
    ALNRouter *router = BuildLargeRouteTable(routeCount, &actualRouteCount);
    NSUInteger perKind = (actualRouteCount > 0) ? (actualRouteCount / 3) : 1;
    NSUInteger lastIndex = (perKind > 0) ? (perKind - 1) : 0;

    NSArray<NSDictionary *> *scenarioDefinitions = @[
      @{
        @"name" : @"static_hit",
        @"method" : @"GET",
        @"path" : [NSString stringWithFormat:@"/bench/static/%lu", (unsigned long)lastIndex],
        @"expect_match" : @(YES),
      },
      @{
        @"name" : @"param_hit",
        @"method" : @"GET",
        @"path" : [NSString stringWithFormat:@"/bench/tenant/%lu/abc123", (unsigned long)lastIndex],
        @"expect_match" : @(YES),
      },
      @{
        @"name" : @"wildcard_hit",
        @"method" : @"GET",
        @"path" : [NSString stringWithFormat:@"/bench/wild/%lu/a/b/c", (unsigned long)lastIndex],
        @"expect_match" : @(YES),
      },
      @{
        @"name" : @"miss",
        @"method" : @"GET",
        @"path" : @"/bench/not-found/path",
        @"expect_match" : @(NO),
      },
    ];

    NSMutableArray<NSDictionary *> *results = [NSMutableArray arrayWithCapacity:[scenarioDefinitions count]];
    for (NSDictionary *definition in scenarioDefinitions) {
      NSError *scenarioError = nil;
      NSDictionary *result = RunScenario(router,
                                         definition[@"name"],
                                         definition[@"method"],
                                         definition[@"path"],
                                         [definition[@"expect_match"] boolValue],
                                         warmup,
                                         iterations,
                                         &scenarioError);
      if (result == nil) {
        fprintf(stderr,
                "route_match_perf_bench: scenario failed (%s): %s\n",
                [definition[@"name"] UTF8String],
                [[scenarioError localizedDescription] UTF8String]);
        return 1;
      }
      [results addObject:result];
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";

    NSDictionary *payload = @{
      @"version" : @"phase10l-route-match-benchmark-v1",
      @"route_count_requested" : @(routeCount),
      @"route_count_actual" : @(actualRouteCount),
      @"iterations" : @(iterations),
      @"warmup" : @(warmup),
      @"scenario_count" : @([results count]),
      @"scenarios" : results,
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
              "route_match_perf_bench: failed encoding output: %s\n",
              [[jsonError localizedDescription] UTF8String]);
      return 1;
    }

    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}";
    fprintf(stdout, "%s\n", [text UTF8String]);
  }

  return 0;
}
