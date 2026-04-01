#import "ALNLiveTestSupport.h"

#import "ALNTestSupport.h"
#import "ALNLive.h"

#import <dispatch/dispatch.h>

static NSString *const ALNLiveTestSupportErrorDomain = @"Arlen.LiveTestSupport.Error";

static NSError *ALNLiveTestSupportError(NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] =
      [message isKindOfClass:[NSString class]] && [message length] > 0
          ? message
          : @"live test support error";
  if ([details isKindOfClass:[NSDictionary class]] && [details count] > 0) {
    [userInfo addEntriesFromDictionary:details];
  }
  return [NSError errorWithDomain:ALNLiveTestSupportErrorDomain code:1 userInfo:userInfo];
}

static NSString *ALNLiveTrimmedLine(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *ALNLiveRuntimeHarnessNodePath(void) {
  static NSString *resolvedPath = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    int exitCode = 0;
    NSString *output = ALNTestRunShellCapture(@"command -v node || command -v nodejs || true", &exitCode);
    (void)exitCode;
    NSArray<NSString *> *lines =
        [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
      NSString *trimmed = ALNLiveTrimmedLine(line);
      if ([trimmed length] > 0) {
        resolvedPath = [trimmed copy];
        break;
      }
    }
  });
  return resolvedPath;
}

BOOL ALNLiveRuntimeHarnessIsAvailable(void) {
  return [ALNLiveRuntimeHarnessNodePath() length] > 0;
}

static NSData *ALNLiveRuntimeScenarioData(NSDictionary *scenario, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSMutableDictionary *resolved =
      [[scenario isKindOfClass:[NSDictionary class]] ? scenario : @{} mutableCopy];
  if (![resolved[@"runtime"] isKindOfClass:[NSString class]]) {
    resolved[@"runtime"] = [ALNLive runtimeJavaScript];
  }
  NSError *jsonError = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:resolved options:0 error:&jsonError];
  if (data == nil && error != NULL) {
    *error = jsonError ?: ALNLiveTestSupportError(@"unable to encode runtime scenario as JSON", nil);
  }
  return data;
}

NSDictionary *ALNLiveRunRuntimeScenario(NSDictionary *scenario, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSString *nodePath = ALNLiveRuntimeHarnessNodePath();
  if ([nodePath length] == 0) {
    if (error != NULL) {
      *error = ALNLiveTestSupportError(@"node is required for the live runtime harness", nil);
    }
    return nil;
  }

  NSError *scenarioError = nil;
  NSData *inputData = ALNLiveRuntimeScenarioData(scenario, &scenarioError);
  if (inputData == nil) {
    if (error != NULL) {
      *error = scenarioError;
    }
    return nil;
  }

  NSString *scriptPath = ALNTestPathFromRepoRoot(@"tests/shared/live_runtime_harness.js");
  NSTask *task = [[NSTask alloc] init];
  task.launchPath = nodePath;
  task.arguments = @[ scriptPath ];

  NSPipe *stdinPipe = [NSPipe pipe];
  NSPipe *stdoutPipe = [NSPipe pipe];
  NSPipe *stderrPipe = [NSPipe pipe];
  task.standardInput = stdinPipe;
  task.standardOutput = stdoutPipe;
  task.standardError = stderrPipe;

  @try {
    [task launch];
  } @catch (NSException *exception) {
    if (error != NULL) {
      *error = ALNLiveTestSupportError(
          @"failed launching live runtime harness",
          @{
            @"exception" : exception.reason ?: @"unknown",
            @"node_path" : nodePath ?: @"",
            @"script_path" : scriptPath ?: @"",
          });
    }
    return nil;
  }

  [[stdinPipe fileHandleForWriting] writeData:inputData];
  [[stdinPipe fileHandleForWriting] closeFile];
  [task waitUntilExit];

  NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
  NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
  NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding] ?: @"";
  if (task.terminationStatus != 0) {
    if (error != NULL) {
      *error = ALNLiveTestSupportError(
          @"live runtime harness exited unsuccessfully",
          @{
            @"stderr" : stderrText ?: @"",
            @"status" : @(task.terminationStatus),
          });
    }
    return nil;
  }

  NSError *jsonError = nil;
  id object = [NSJSONSerialization JSONObjectWithData:stdoutData options:0 error:&jsonError];
  if (![object isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = jsonError ?: ALNLiveTestSupportError(
                                  @"live runtime harness did not return a JSON dictionary",
                                  @{
                                    @"stderr" : stderrText ?: @"",
                                  });
    }
    return nil;
  }
  return object;
}

NSDictionary *ALNLiveRuntimeResponse(NSInteger status,
                                     NSDictionary *headers,
                                     NSString *body,
                                     NSString *url,
                                     BOOL redirected,
                                     NSDictionary *extras) {
  NSMutableDictionary *response = [NSMutableDictionary dictionary];
  response[@"status"] = @(status);
  response[@"headers"] = [headers isKindOfClass:[NSDictionary class]] ? headers : @{};
  if ([body isKindOfClass:[NSString class]]) {
    response[@"body"] = body;
  }
  if ([url isKindOfClass:[NSString class]] && [url length] > 0) {
    response[@"url"] = url;
  }
  response[@"redirected"] = @(redirected);
  if ([extras isKindOfClass:[NSDictionary class]]) {
    [response addEntriesFromDictionary:extras];
  }
  return [NSDictionary dictionaryWithDictionary:response];
}

NSDictionary *ALNLiveRuntimeElementSnapshot(NSDictionary *result, NSString *selector) {
  if (![result isKindOfClass:[NSDictionary class]] || ![selector isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSDictionary *elements = [result[@"elements"] isKindOfClass:[NSDictionary class]] ? result[@"elements"] : nil;
  return [elements[selector] isKindOfClass:[NSDictionary class]] ? elements[selector] : nil;
}

NSArray<NSDictionary *> *ALNLiveRuntimeEventsNamed(NSDictionary *result, NSString *name) {
  NSArray *events = [result[@"events"] isKindOfClass:[NSArray class]] ? result[@"events"] : @[];
  NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
  for (id entry in events) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *eventName = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    if ([eventName isEqualToString:(name ?: @"")]) {
      [matches addObject:entry];
    }
  }
  return [NSArray arrayWithArray:matches];
}

NSArray<NSDictionary *> *ALNLiveRuntimeRequestsForTransport(NSDictionary *result,
                                                            NSString *transport) {
  NSArray *requests = [result[@"requests"] isKindOfClass:[NSArray class]] ? result[@"requests"] : @[];
  NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
  for (id entry in requests) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *requestTransport =
        [entry[@"transport"] isKindOfClass:[NSString class]] ? entry[@"transport"] : @"";
    if ([requestTransport isEqualToString:(transport ?: @"")]) {
      [matches addObject:entry];
    }
  }
  return [NSArray arrayWithArray:matches];
}
