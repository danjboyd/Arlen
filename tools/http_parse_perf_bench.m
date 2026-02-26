#import <Foundation/Foundation.h>

#import "ALNJSONSerialization.h"
#import "ALNRequest.h"

static void PrintUsage(void) {
  fprintf(stderr,
          "Usage: http_parse_perf_bench [--fixtures-dir <path>] [--backend <llhttp|legacy>] "
          "[--iterations <count>] [--warmup <count>]\n");
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

static ALNHTTPParserBackend BackendFromName(NSString *value) {
  NSString *normalized = [[value lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"legacy"] ||
      [normalized isEqualToString:@"manual"] ||
      [normalized isEqualToString:@"string"]) {
    return ALNHTTPParserBackendLegacy;
  }
  return ALNHTTPParserBackendLLHTTP;
}

static NSDictionary *RunBenchmarkForFixture(NSString *fixturePath,
                                            ALNHTTPParserBackend backend,
                                            NSUInteger warmupIterations,
                                            NSUInteger measureIterations,
                                            NSError **errorOut) {
  NSData *fixtureData = [NSData dataWithContentsOfFile:fixturePath];
  if (fixtureData == nil) {
    if (errorOut != NULL) {
      *errorOut = [NSError errorWithDomain:@"Arlen.HTTP.Parse.Perf"
                                      code:1
                                  userInfo:@{ NSLocalizedDescriptionKey :
                                                  [NSString stringWithFormat:@"failed reading fixture %@",
                                                                             fixturePath] }];
    }
    return nil;
  }

  for (NSUInteger idx = 0; idx < warmupIterations; idx++) {
    @autoreleasepool {
      NSError *error = nil;
      ALNRequest *request = [ALNRequest requestFromRawData:fixtureData backend:backend error:&error];
      if (request == nil || error != nil) {
        if (errorOut != NULL) {
          *errorOut = error ?: [NSError errorWithDomain:@"Arlen.HTTP.Parse.Perf"
                                                   code:2
                                               userInfo:@{ NSLocalizedDescriptionKey :
                                                               [NSString stringWithFormat:@"warmup parse failed for %@",
                                                                                          fixturePath] }];
        }
        return nil;
      }
    }
  }

  NSMutableArray<NSNumber *> *samples = [NSMutableArray arrayWithCapacity:measureIterations];
  for (NSUInteger idx = 0; idx < measureIterations; idx++) {
    @autoreleasepool {
      NSError *error = nil;
      NSDate *start = [NSDate date];
      ALNRequest *request = [ALNRequest requestFromRawData:fixtureData backend:backend error:&error];
      NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];
      if (request == nil || error != nil) {
        if (errorOut != NULL) {
          *errorOut = error ?: [NSError errorWithDomain:@"Arlen.HTTP.Parse.Perf"
                                                   code:3
                                               userInfo:@{ NSLocalizedDescriptionKey :
                                                               [NSString stringWithFormat:@"parse failed for %@",
                                                                                          fixturePath] }];
        }
        return nil;
      }
      [samples addObject:@(elapsed * 1000000.0)];
    }
  }

  NSString *fixtureName = [fixturePath lastPathComponent] ?: @"fixture";
  return @{
    @"fixture" : fixtureName,
    @"bytes" : @([fixtureData length]),
    @"parse" : TimingSummaryFromSamples(samples),
  };
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *fixturesDir = @"tests/fixtures/performance/http_parse";
    NSString *backendName = @"llhttp";
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
      } else if ([arg isEqualToString:@"--backend"]) {
        if (idx + 1 >= [args count]) {
          PrintUsage();
          return 2;
        }
        backendName = [[args[++idx] lowercaseString] copy];
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
        fprintf(stderr, "http_parse_perf_bench: unknown option %s\n", [arg UTF8String]);
        PrintUsage();
        return 2;
      }
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:fixturesDir isDirectory:&isDirectory] || !isDirectory) {
      fprintf(stderr, "http_parse_perf_bench: fixtures dir not found: %s\n", [fixturesDir UTF8String]);
      return 1;
    }

    NSError *lsError = nil;
    NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:fixturesDir error:&lsError];
    if (entries == nil) {
      fprintf(stderr, "http_parse_perf_bench: failed listing fixtures: %s\n",
              [[lsError localizedDescription] UTF8String]);
      return 1;
    }

    NSMutableArray<NSString *> *fixturePaths = [NSMutableArray array];
    for (NSString *entry in entries) {
      if (![entry hasSuffix:@".http"]) {
        continue;
      }
      [fixturePaths addObject:[fixturesDir stringByAppendingPathComponent:entry]];
    }
    [fixturePaths sortUsingSelector:@selector(compare:)];
    if ([fixturePaths count] == 0) {
      fprintf(stderr, "http_parse_perf_bench: no fixture .http files in %s\n", [fixturesDir UTF8String]);
      return 1;
    }

    ALNHTTPParserBackend backend = BackendFromName(backendName);
    backendName = [ALNRequest parserBackendNameForBackend:backend];

    NSMutableArray<NSDictionary *> *results = [NSMutableArray arrayWithCapacity:[fixturePaths count]];
    for (NSString *fixturePath in fixturePaths) {
      NSError *error = nil;
      NSDictionary *result = RunBenchmarkForFixture(fixturePath, backend, warmup, iterations, &error);
      if (result == nil) {
        fprintf(stderr,
                "http_parse_perf_bench: fixture failed (%s): %s\n",
                [fixturePath UTF8String],
                [[error localizedDescription] UTF8String]);
        return 1;
      }
      [results addObject:result];
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";

    NSDictionary *payload = @{
      @"version" : @"phase10h-http-parse-benchmark-v1",
      @"backend" : backendName ?: @"llhttp",
      @"llhttp_version" : [ALNRequest llhttpVersion] ?: @"unknown",
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
      fprintf(stderr, "http_parse_perf_bench: failed encoding output: %s\n",
              [[jsonError localizedDescription] UTF8String]);
      return 1;
    }

    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}";
    fprintf(stdout, "%s\n", [text UTF8String]);
  }

  return 0;
}
