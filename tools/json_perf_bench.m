#import <Foundation/Foundation.h>

#import "ALNJSONSerialization.h"

static void PrintUsage(void) {
  fprintf(stderr,
          "Usage: json_perf_bench [--fixtures-dir <path>] [--iterations <count>] [--warmup <count>]\n");
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

static NSDictionary *RunBenchmarkForFixture(NSString *fixturePath,
                                            NSUInteger warmupIterations,
                                            NSUInteger measureIterations,
                                            NSError **errorOut) {
  NSData *fixtureData = [NSData dataWithContentsOfFile:fixturePath];
  if (fixtureData == nil) {
    if (errorOut != NULL) {
      *errorOut = [NSError errorWithDomain:@"Arlen.JSON.Perf"
                                      code:1
                                  userInfo:@{
                                    NSLocalizedDescriptionKey :
                                        [NSString stringWithFormat:@"failed reading fixture %@", fixturePath]
                                  }];
    }
    return nil;
  }

  NSError *parseError = nil;
  id parsedFixture = [ALNJSONSerialization JSONObjectWithData:fixtureData options:0 error:&parseError];
  if (![parsedFixture isKindOfClass:[NSDictionary class]] &&
      ![parsedFixture isKindOfClass:[NSArray class]]) {
    if (parseError == nil) {
      parseError = [NSError errorWithDomain:@"Arlen.JSON.Perf"
                                       code:2
                                   userInfo:@{
                                     NSLocalizedDescriptionKey :
                                         [NSString stringWithFormat:@"fixture %@ must decode to object or array",
                                                                    fixturePath]
                                   }];
    }
    if (errorOut != NULL) {
      *errorOut = parseError;
    }
    return nil;
  }

  for (NSUInteger idx = 0; idx < warmupIterations; idx++) {
    @autoreleasepool {
      NSError *error = nil;
      (void)[ALNJSONSerialization JSONObjectWithData:fixtureData options:0 error:&error];
      if (error != nil) {
        if (errorOut != NULL) {
          *errorOut = error;
        }
        return nil;
      }
    }
  }

  NSMutableArray<NSNumber *> *decodeSamples =
      [NSMutableArray arrayWithCapacity:measureIterations];
  for (NSUInteger idx = 0; idx < measureIterations; idx++) {
    @autoreleasepool {
      NSError *error = nil;
      NSDate *start = [NSDate date];
      id parsed = [ALNJSONSerialization JSONObjectWithData:fixtureData options:0 error:&error];
      NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];
      if (parsed == nil || error != nil) {
        if (errorOut != NULL) {
          *errorOut = error ?: [NSError errorWithDomain:@"Arlen.JSON.Perf"
                                                   code:3
                                               userInfo:@{
                                                 NSLocalizedDescriptionKey :
                                                     [NSString stringWithFormat:@"decode failed for fixture %@",
                                                                                fixturePath]
                                               }];
        }
        return nil;
      }
      [decodeSamples addObject:@(elapsed * 1000000.0)];
    }
  }

  for (NSUInteger idx = 0; idx < warmupIterations; idx++) {
    @autoreleasepool {
      NSError *error = nil;
      (void)[ALNJSONSerialization dataWithJSONObject:parsedFixture options:0 error:&error];
      if (error != nil) {
        if (errorOut != NULL) {
          *errorOut = error;
        }
        return nil;
      }
    }
  }

  NSMutableArray<NSNumber *> *encodeSamples =
      [NSMutableArray arrayWithCapacity:measureIterations];
  for (NSUInteger idx = 0; idx < measureIterations; idx++) {
    @autoreleasepool {
      NSError *error = nil;
      NSDate *start = [NSDate date];
      NSData *encoded = [ALNJSONSerialization dataWithJSONObject:parsedFixture options:0 error:&error];
      NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];
      if (encoded == nil || error != nil) {
        if (errorOut != NULL) {
          *errorOut = error ?: [NSError errorWithDomain:@"Arlen.JSON.Perf"
                                                   code:4
                                               userInfo:@{
                                                 NSLocalizedDescriptionKey :
                                                     [NSString stringWithFormat:@"encode failed for fixture %@",
                                                                                fixturePath]
                                               }];
        }
        return nil;
      }
      [encodeSamples addObject:@(elapsed * 1000000.0)];
    }
  }

  NSString *fixtureName = [[fixturePath lastPathComponent] stringByDeletingPathExtension];
  return @{
    @"fixture" : fixtureName ?: [fixturePath lastPathComponent],
    @"bytes" : @([fixtureData length]),
    @"decode" : TimingSummaryFromSamples(decodeSamples),
    @"encode" : TimingSummaryFromSamples(encodeSamples),
  };
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *fixturesDir = @"tests/fixtures/performance/json";
    NSUInteger iterations = 1500;
    NSUInteger warmup = 200;

    NSMutableArray<NSString *> *args = [NSMutableArray arrayWithCapacity:(NSUInteger)MAX(argc - 1, 0)];
    for (int idx = 1; idx < argc; idx++) {
      [args addObject:[NSString stringWithUTF8String:argv[idx]]];
    }

    for (NSUInteger idx = 0; idx < [args count]; idx++) {
      NSString *arg = args[idx];
      if ([arg isEqualToString:@"--fixtures-dir"]) {
        if (idx + 1 >= [args count]) {
          PrintUsage();
          return 2;
        }
        fixturesDir = args[++idx];
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
        fprintf(stderr, "json_perf_bench: unknown option %s\n", [arg UTF8String]);
        PrintUsage();
        return 2;
      }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:fixturesDir isDirectory:&isDirectory] || !isDirectory) {
      fprintf(stderr, "json_perf_bench: fixtures dir not found: %s\n", [fixturesDir UTF8String]);
      return 1;
    }

    NSError *lsError = nil;
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:fixturesDir error:&lsError];
    if (entries == nil) {
      fprintf(stderr, "json_perf_bench: failed listing fixtures: %s\n",
              [[lsError localizedDescription] UTF8String]);
      return 1;
    }

    NSMutableArray<NSString *> *fixturePaths = [NSMutableArray array];
    for (NSString *entry in entries) {
      if (![entry hasSuffix:@".json"]) {
        continue;
      }
      [fixturePaths addObject:[fixturesDir stringByAppendingPathComponent:entry]];
    }
    [fixturePaths sortUsingSelector:@selector(compare:)];
    if ([fixturePaths count] == 0) {
      fprintf(stderr, "json_perf_bench: no fixture .json files in %s\n", [fixturesDir UTF8String]);
      return 1;
    }

    NSMutableArray<NSDictionary *> *results = [NSMutableArray arrayWithCapacity:[fixturePaths count]];
    for (NSString *fixturePath in fixturePaths) {
      NSError *error = nil;
      NSDictionary *fixtureResult =
          RunBenchmarkForFixture(fixturePath, warmup, iterations, &error);
      if (fixtureResult == nil) {
        fprintf(stderr, "json_perf_bench: fixture failed (%s): %s\n",
                [fixturePath UTF8String],
                [[error localizedDescription] UTF8String]);
        return 1;
      }
      [results addObject:fixtureResult];
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";

    NSDictionary *payload = @{
      @"version" : @"phase10e-json-benchmark-v1",
      @"backend" : [ALNJSONSerialization backendName] ?: @"unknown",
      @"yyjson_version" : [ALNJSONSerialization yyjsonVersion] ?: @"unknown",
      @"iterations" : @(iterations),
      @"warmup" : @(warmup),
      @"fixture_count" : @([results count]),
      @"fixtures" : results,
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
      fprintf(stderr, "json_perf_bench: failed encoding benchmark output: %s\n",
              [[jsonError localizedDescription] UTF8String]);
      return 1;
    }
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}";
    fprintf(stdout, "%s\n", [text UTF8String]);
  }
  return 0;
}
