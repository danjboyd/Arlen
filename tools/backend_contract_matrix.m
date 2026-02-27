#import <Foundation/Foundation.h>

#import "ALNJSONSerialization.h"
#import "ALNRequest.h"

static void PrintUsage(void) {
  fprintf(stderr,
          "Usage: backend_contract_matrix [--http-fixtures-dir <path>] [--json-fixtures-dir <path>]\n");
}

static NSString *ISO8601NowUTC(void) {
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
  return [formatter stringFromDate:[NSDate date]];
}

static NSArray<NSNumber *> *AvailableParserBackends(void) {
  NSMutableArray<NSNumber *> *backends = [NSMutableArray array];
  if ([ALNRequest isLLHTTPAvailable]) {
    [backends addObject:@(ALNHTTPParserBackendLLHTTP)];
  }
  [backends addObject:@(ALNHTTPParserBackendLegacy)];
  return backends;
}

static NSArray<NSNumber *> *AvailableJSONBackends(void) {
  NSMutableArray<NSNumber *> *backends = [NSMutableArray arrayWithObject:@(ALNJSONBackendFoundation)];
  if ([ALNJSONSerialization isYYJSONAvailable]) {
    [backends addObject:@(ALNJSONBackendYYJSON)];
  }
  return backends;
}

static NSDictionary *NormalizeRequest(ALNRequest *request) {
  if (request == nil) {
    return @{};
  }
  NSString *body = [request.body base64EncodedStringWithOptions:0] ?: @"";
  return @{
    @"method" : request.method ?: @"",
    @"path" : request.path ?: @"",
    @"query" : request.queryString ?: @"",
    @"http_version" : request.httpVersion ?: @"",
    @"headers" : request.headers ?: @{},
    @"body_b64" : body,
    @"query_params" : request.queryParams ?: @{},
    @"cookies" : request.cookies ?: @{},
  };
}

static NSDictionary *RunHTTPFixture(NSString *fixturePath,
                                    NSArray<NSNumber *> *backends,
                                    NSMutableArray<NSString *> *violations) {
  NSData *data = [NSData dataWithContentsOfFile:fixturePath];
  NSString *fixtureName = [fixturePath lastPathComponent] ?: fixturePath;
  if (data == nil) {
    NSString *message = [NSString stringWithFormat:@"http fixture unreadable: %@", fixtureName];
    [violations addObject:message];
    return @{
      @"fixture" : fixtureName,
      @"status" : @"fail",
      @"error" : @"unreadable fixture",
    };
  }

  NSMutableArray<NSDictionary *> *results = [NSMutableArray arrayWithCapacity:[backends count]];
  NSMutableDictionary<NSString *, NSDictionary *> *resultByBackend =
      [NSMutableDictionary dictionaryWithCapacity:[backends count]];

  for (NSNumber *backendValue in backends) {
    ALNHTTPParserBackend backend = (ALNHTTPParserBackend)[backendValue unsignedIntegerValue];
    NSString *backendName = [ALNRequest parserBackendNameForBackend:backend] ?: @"unknown";

    NSError *error = nil;
    ALNRequest *request = [ALNRequest requestFromRawData:data backend:backend error:&error];
    BOOL success = (request != nil && error == nil);

    NSDictionary *entry = @{
      @"backend" : backendName,
      @"success" : @(success),
      @"error_domain" : error.domain ?: @"",
      @"error_code" : @(error != nil ? error.code : 0),
      @"error_message" : error.localizedDescription ?: @"",
      @"normalized_request" : success ? NormalizeRequest(request) : @{},
    };
    [results addObject:entry];
    resultByBackend[backendName] = entry;
  }

  NSString *status = @"pass";
  if ([backends count] >= 2) {
    NSDictionary *baseline = results[0];
    BOOL baselineSuccess = [baseline[@"success"] boolValue];
    NSDictionary *baselineNormalized = baseline[@"normalized_request"];
    NSInteger baselineErrorCode = [baseline[@"error_code"] integerValue];

    for (NSUInteger idx = 1; idx < [results count]; idx++) {
      NSDictionary *candidate = results[idx];
      BOOL candidateSuccess = [candidate[@"success"] boolValue];
      if (candidateSuccess != baselineSuccess) {
        status = @"fail";
        [violations addObject:[NSString stringWithFormat:
                                           @"http fixture '%@' backend success mismatch (%@=%@ vs %@=%@)",
                                           fixtureName,
                                           baseline[@"backend"],
                                           baseline[@"success"],
                                           candidate[@"backend"],
                                           candidate[@"success"]]];
        continue;
      }
      if (candidateSuccess) {
        NSDictionary *candidateNormalized = candidate[@"normalized_request"];
        if (![candidateNormalized isEqual:baselineNormalized]) {
          status = @"fail";
          [violations addObject:[NSString stringWithFormat:
                                             @"http fixture '%@' normalized request mismatch (%@ vs %@)",
                                             fixtureName,
                                             baseline[@"backend"],
                                             candidate[@"backend"]]];
        }
      } else {
        NSInteger candidateCode = [candidate[@"error_code"] integerValue];
        if (candidateCode != baselineErrorCode) {
          status = @"fail";
          [violations addObject:[NSString stringWithFormat:
                                             @"http fixture '%@' error code mismatch (%@=%ld vs %@=%ld)",
                                             fixtureName,
                                             baseline[@"backend"],
                                             (long)baselineErrorCode,
                                             candidate[@"backend"],
                                             (long)candidateCode]];
        }
      }
    }
  }

  return @{
    @"fixture" : fixtureName,
    @"status" : status,
    @"bytes" : @([data length]),
    @"results" : results,
  };
}

static NSDictionary *RunJSONFixture(NSString *fixturePath,
                                    NSArray<NSNumber *> *backends,
                                    NSMutableArray<NSString *> *violations) {
  NSData *data = [NSData dataWithContentsOfFile:fixturePath];
  NSString *fixtureName = [fixturePath lastPathComponent] ?: fixturePath;
  if (data == nil) {
    NSString *message = [NSString stringWithFormat:@"json fixture unreadable: %@", fixtureName];
    [violations addObject:message];
    return @{
      @"fixture" : fixtureName,
      @"status" : @"fail",
      @"error" : @"unreadable fixture",
    };
  }

  NSMutableArray<NSDictionary *> *results = [NSMutableArray arrayWithCapacity:[backends count]];
  [ALNJSONSerialization resetBackendForTesting];

  for (NSNumber *backendValue in backends) {
    ALNJSONBackend backend = (ALNJSONBackend)[backendValue unsignedIntegerValue];
    [ALNJSONSerialization setBackendForTesting:backend];
    NSString *backendName = [ALNJSONSerialization backendName] ?: @"unknown";

    NSError *decodeError = nil;
    id decoded = [ALNJSONSerialization JSONObjectWithData:data options:0 error:&decodeError];
    BOOL decodeSuccess = (decoded != nil && decodeError == nil);

    NSError *encodeError = nil;
    NSData *encoded = nil;
    id reparsed = nil;
    if (decodeSuccess) {
      encoded = [ALNJSONSerialization dataWithJSONObject:decoded options:0 error:&encodeError];
      if (encoded != nil && encodeError == nil) {
        NSError *reparseError = nil;
        reparsed = [ALNJSONSerialization JSONObjectWithData:encoded options:0 error:&reparseError];
        if (reparseError != nil) {
          encodeError = reparseError;
        }
      }
    }

    BOOL encodeSuccess = (decodeSuccess && encoded != nil && encodeError == nil && reparsed != nil);

    NSDictionary *entry = @{
      @"backend" : backendName,
      @"decode_success" : @(decodeSuccess),
      @"encode_roundtrip_success" : @(encodeSuccess),
      @"decode_error_domain" : decodeError.domain ?: @"",
      @"decode_error_code" : @(decodeError != nil ? decodeError.code : 0),
      @"decode_error_message" : decodeError.localizedDescription ?: @"",
      @"encode_error_domain" : encodeError.domain ?: @"",
      @"encode_error_code" : @(encodeError != nil ? encodeError.code : 0),
      @"encode_error_message" : encodeError.localizedDescription ?: @"",
      @"decoded_value" : decodeSuccess ? decoded : [NSNull null],
      @"roundtrip_value" : encodeSuccess ? reparsed : [NSNull null],
    };
    [results addObject:entry];
  }

  [ALNJSONSerialization resetBackendForTesting];

  NSString *status = @"pass";
  if ([backends count] >= 2) {
    NSDictionary *baseline = results[0];
    BOOL baselineDecode = [baseline[@"decode_success"] boolValue];
    BOOL baselineEncode = [baseline[@"encode_roundtrip_success"] boolValue];
    id baselineDecoded = baseline[@"decoded_value"];

    for (NSUInteger idx = 1; idx < [results count]; idx++) {
      NSDictionary *candidate = results[idx];
      BOOL candidateDecode = [candidate[@"decode_success"] boolValue];
      BOOL candidateEncode = [candidate[@"encode_roundtrip_success"] boolValue];
      if (candidateDecode != baselineDecode || candidateEncode != baselineEncode) {
        status = @"fail";
        [violations addObject:[NSString stringWithFormat:
                                           @"json fixture '%@' backend success mismatch (%@ decode=%@ encode=%@ vs %@ decode=%@ encode=%@)",
                                           fixtureName,
                                           baseline[@"backend"],
                                           baseline[@"decode_success"],
                                           baseline[@"encode_roundtrip_success"],
                                           candidate[@"backend"],
                                           candidate[@"decode_success"],
                                           candidate[@"encode_roundtrip_success"]]];
        continue;
      }
      if (baselineDecode) {
        id candidateDecoded = candidate[@"decoded_value"];
        if ((baselineDecoded == [NSNull null]) || (candidateDecoded == [NSNull null]) ||
            ![candidateDecoded isEqual:baselineDecoded]) {
          status = @"fail";
          [violations addObject:[NSString stringWithFormat:
                                             @"json fixture '%@' decoded value mismatch (%@ vs %@)",
                                             fixtureName,
                                             baseline[@"backend"],
                                             candidate[@"backend"]]];
        }
      } else {
        NSInteger baselineErrorCode = [baseline[@"decode_error_code"] integerValue];
        NSInteger candidateErrorCode = [candidate[@"decode_error_code"] integerValue];
        if (baselineErrorCode != candidateErrorCode) {
          status = @"fail";
          [violations addObject:[NSString stringWithFormat:
                                             @"json fixture '%@' decode error code mismatch (%@=%ld vs %@=%ld)",
                                             fixtureName,
                                             baseline[@"backend"],
                                             (long)baselineErrorCode,
                                             candidate[@"backend"],
                                             (long)candidateErrorCode]];
        }
      }
    }
  }

  return @{
    @"fixture" : fixtureName,
    @"status" : status,
    @"bytes" : @([data length]),
    @"results" : results,
  };
}

static NSArray<NSString *> *FixturePaths(NSString *directory, NSString *suffix) {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;
  NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:directory error:&error];
  if (entries == nil) {
    return @[];
  }
  NSMutableArray<NSString *> *paths = [NSMutableArray array];
  for (NSString *entry in entries) {
    if (![entry hasSuffix:suffix]) {
      continue;
    }
    [paths addObject:[directory stringByAppendingPathComponent:entry]];
  }
  [paths sortUsingSelector:@selector(compare:)];
  return paths;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *httpFixturesDir = @"tests/fixtures/performance/http_parse";
    NSString *jsonFixturesDir = @"tests/fixtures/performance/json";

    NSMutableArray<NSString *> *args = [NSMutableArray arrayWithCapacity:(NSUInteger)MAX(argc - 1, 0)];
    for (int idx = 1; idx < argc; idx++) {
      [args addObject:[NSString stringWithUTF8String:argv[idx]]];
    }

    for (NSUInteger idx = 0; idx < [args count]; idx++) {
      NSString *arg = args[idx];
      if ([arg isEqualToString:@"--http-fixtures-dir"]) {
        if (idx + 1 >= [args count]) {
          PrintUsage();
          return 2;
        }
        httpFixturesDir = args[++idx];
      } else if ([arg isEqualToString:@"--json-fixtures-dir"]) {
        if (idx + 1 >= [args count]) {
          PrintUsage();
          return 2;
        }
        jsonFixturesDir = args[++idx];
      } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
        PrintUsage();
        return 0;
      } else {
        fprintf(stderr, "backend_contract_matrix: unknown option %s\n", [arg UTF8String]);
        PrintUsage();
        return 2;
      }
    }

    NSArray<NSString *> *httpFixtures = FixturePaths(httpFixturesDir, @".http");
    NSArray<NSString *> *jsonFixtures = FixturePaths(jsonFixturesDir, @".json");

    NSMutableArray<NSString *> *violations = [NSMutableArray array];
    NSArray<NSNumber *> *parserBackends = AvailableParserBackends();
    NSArray<NSNumber *> *jsonBackends = AvailableJSONBackends();

    NSMutableArray<NSDictionary *> *httpResults = [NSMutableArray arrayWithCapacity:[httpFixtures count]];
    for (NSString *fixturePath in httpFixtures) {
      [httpResults addObject:RunHTTPFixture(fixturePath, parserBackends, violations)];
    }

    NSMutableArray<NSDictionary *> *jsonResults = [NSMutableArray arrayWithCapacity:[jsonFixtures count]];
    for (NSString *fixturePath in jsonFixtures) {
      [jsonResults addObject:RunJSONFixture(fixturePath, jsonBackends, violations)];
    }

    NSMutableArray<NSString *> *parserBackendNames = [NSMutableArray arrayWithCapacity:[parserBackends count]];
    for (NSNumber *backendValue in parserBackends) {
      [parserBackendNames addObject:[ALNRequest parserBackendNameForBackend:(ALNHTTPParserBackend)[backendValue unsignedIntegerValue]] ?: @"unknown"];
    }

    NSMutableArray<NSString *> *jsonBackendNames = [NSMutableArray arrayWithCapacity:[jsonBackends count]];
    for (NSNumber *backendValue in jsonBackends) {
      ALNJSONBackend backend = (ALNJSONBackend)[backendValue unsignedIntegerValue];
      if (backend == ALNJSONBackendYYJSON) {
        [jsonBackendNames addObject:@"yyjson"];
      } else {
        [jsonBackendNames addObject:@"foundation"];
      }
    }

    NSDictionary *payload = @{
      @"version" : @"phase10m-backend-contract-matrix-v1",
      @"generated_at" : ISO8601NowUTC(),
      @"http_fixture_count" : @([httpResults count]),
      @"json_fixture_count" : @([jsonResults count]),
      @"available_parser_backends" : parserBackendNames,
      @"available_json_backends" : jsonBackendNames,
      @"llhttp_version" : [ALNRequest llhttpVersion] ?: @"unknown",
      @"yyjson_version" : [ALNJSONSerialization yyjsonVersion] ?: @"unknown",
      @"http_results" : httpResults,
      @"json_results" : jsonResults,
      @"violations" : violations,
      @"status" : ([violations count] == 0 ? @"pass" : @"fail"),
    };

    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted;
#ifdef NSJSONWritingSortedKeys
    options |= NSJSONWritingSortedKeys;
#endif
    NSError *error = nil;
    NSData *json = [ALNJSONSerialization dataWithJSONObject:payload options:options error:&error];
    if (json == nil) {
      fprintf(stderr,
              "backend_contract_matrix: failed encoding payload: %s\n",
              [[error localizedDescription] UTF8String]);
      return 1;
    }
    NSString *output = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}";
    fprintf(stdout, "%s\n", [output UTF8String]);

    return ([violations count] == 0) ? 0 : 1;
  }
}
