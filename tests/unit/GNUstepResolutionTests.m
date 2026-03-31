#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNTestSupport.h"

@interface GNUstepResolutionTests : XCTestCase
@end

@implementation GNUstepResolutionTests

- (NSString *)resolverPath {
  return ALNTestPathFromRepoRoot(@"tools/resolve_gnustep.sh");
}

- (NSString *)shellQuoted:(NSString *)value {
  NSString *safe = value ?: @"";
  return [NSString stringWithFormat:@"'%@'",
                                    [safe stringByReplacingOccurrencesOfString:@"'"
                                                                    withString:@"'\"'\"'"]];
}

- (BOOL)makeExecutableAtPath:(NSString *)path {
  NSError *error = nil;
  BOOL updated = [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions : @0755 }
                                                  ofItemAtPath:path
                                                         error:&error];
  XCTAssertTrue(updated, @"failed marking %@ executable: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  return updated;
}

- (NSString *)runResolverWithEnvironment:(NSDictionary<NSString *, NSString *> *)environment
                                exitCode:(int *)exitCode {
  NSMutableString *command = [NSMutableString stringWithString:@"env -i"];
  [command appendFormat:@" HOME=%@", [self shellQuoted:NSHomeDirectory() ?: @"/tmp"]];

  NSArray<NSString *> *keys = [[environment allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    NSString *value = environment[key];
    [command appendFormat:@" %@=%@", key, [self shellQuoted:value ?: @""]];
  }

  if (environment[@"PATH"] == nil) {
    [command appendFormat:@" PATH=%@", [self shellQuoted:@"/usr/bin:/bin"]];
  }

  [command appendFormat:@" /bin/bash %@", [self shellQuoted:[self resolverPath]]];
  return ALNTestRunShellCapture(command, exitCode);
}

- (NSString *)writeExecutableScriptNamed:(NSString *)name
                                 content:(NSString *)content
                                  inRoot:(NSString *)root {
  NSString *path = [root stringByAppendingPathComponent:name ?: @"script"];
  NSError *error = nil;
  BOOL wrote = ALNTestWriteUTF8File(path, content ?: @"", &error);
  XCTAssertTrue(wrote, @"failed writing %@: %@", path, error.localizedDescription);
  XCTAssertNil(error);
  XCTAssertTrue([self makeExecutableAtPath:path]);
  return path;
}

- (void)testResolverPrefersGNUSTEP_SHOverOtherSources {
  NSString *tempRoot = ALNTestTemporaryDirectory(@"gnustep_resolver_env");
  XCTAssertNotNil(tempRoot);

  NSString *preferredMakefiles = [tempRoot stringByAppendingPathComponent:@"preferred/Makefiles"];
  NSString *fallbackMakefiles = [tempRoot stringByAppendingPathComponent:@"fallback/Makefiles"];
  NSString *configMakefiles = [tempRoot stringByAppendingPathComponent:@"config/Makefiles"];
  NSError *error = nil;
  XCTAssertTrue(ALNTestWriteUTF8File([preferredMakefiles stringByAppendingPathComponent:@"GNUstep.sh"], @"#!/bin/sh\n", &error));
  XCTAssertNil(error);
  XCTAssertTrue(ALNTestWriteUTF8File([fallbackMakefiles stringByAppendingPathComponent:@"GNUstep.sh"], @"#!/bin/sh\n", &error));
  XCTAssertNil(error);
  XCTAssertTrue(ALNTestWriteUTF8File([configMakefiles stringByAppendingPathComponent:@"GNUstep.sh"], @"#!/bin/sh\n", &error));
  XCTAssertNil(error);

  NSString *binDir = [tempRoot stringByAppendingPathComponent:@"bin"];
  NSString *fakeConfigPath = [self writeExecutableScriptNamed:@"gnustep-config"
                                                      content:[NSString stringWithFormat:
                                                                   @"#!/bin/bash\nif [[ \"$1\" == \"--variable=GNUSTEP_MAKEFILES\" ]]; then\n  printf '%%s\\n' %@\nfi\n",
                                                                   [self shellQuoted:configMakefiles]]
                                                       inRoot:binDir];
  XCTAssertNotNil(fakeConfigPath);

  int exitCode = 0;
  NSString *output = [self runResolverWithEnvironment:@{
    @"GNUSTEP_SH" : [preferredMakefiles stringByAppendingPathComponent:@"GNUstep.sh"],
    @"GNUSTEP_MAKEFILES" : fallbackMakefiles,
    @"PATH" : binDir,
  }
                                           exitCode:&exitCode];
  XCTAssertEqual(0, exitCode);
  XCTAssertEqualObjects([preferredMakefiles stringByAppendingPathComponent:@"GNUstep.sh"], [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
}

- (void)testResolverFallsBackToGNUSTEP_MAKEFILES {
  NSString *tempRoot = ALNTestTemporaryDirectory(@"gnustep_resolver_makefiles");
  XCTAssertNotNil(tempRoot);

  NSString *makefiles = [tempRoot stringByAppendingPathComponent:@"managed/Makefiles"];
  NSError *error = nil;
  XCTAssertTrue(ALNTestWriteUTF8File([makefiles stringByAppendingPathComponent:@"GNUstep.sh"], @"#!/bin/sh\n", &error));
  XCTAssertNil(error);

  int exitCode = 0;
  NSString *output = [self runResolverWithEnvironment:@{
    @"GNUSTEP_MAKEFILES" : makefiles,
    @"PATH" : @"/usr/bin:/bin",
  }
                                           exitCode:&exitCode];
  XCTAssertEqual(0, exitCode);
  XCTAssertEqualObjects([makefiles stringByAppendingPathComponent:@"GNUstep.sh"], [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
}

- (void)testResolverFallsBackToGnustepConfig {
  NSString *tempRoot = ALNTestTemporaryDirectory(@"gnustep_resolver_config");
  XCTAssertNotNil(tempRoot);

  NSString *makefiles = [tempRoot stringByAppendingPathComponent:@"configured/Makefiles"];
  NSError *error = nil;
  XCTAssertTrue(ALNTestWriteUTF8File([makefiles stringByAppendingPathComponent:@"GNUstep.sh"], @"#!/bin/sh\n", &error));
  XCTAssertNil(error);

  NSString *binDir = [tempRoot stringByAppendingPathComponent:@"bin"];
  NSString *fakeConfigPath = [self writeExecutableScriptNamed:@"gnustep-config"
                                                      content:[NSString stringWithFormat:
                                                                   @"#!/bin/bash\nif [[ \"$1\" == \"--variable=GNUSTEP_MAKEFILES\" ]]; then\n  printf '%%s\\n' %@\n  exit 0\nfi\nexit 1\n",
                                                                   [self shellQuoted:makefiles]]
                                                       inRoot:binDir];
  XCTAssertNotNil(fakeConfigPath);

  int exitCode = 0;
  NSString *output = [self runResolverWithEnvironment:@{
    @"PATH" : binDir,
  }
                                           exitCode:&exitCode];
  XCTAssertEqual(0, exitCode);
  XCTAssertEqualObjects([makefiles stringByAppendingPathComponent:@"GNUstep.sh"], [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
}

@end
