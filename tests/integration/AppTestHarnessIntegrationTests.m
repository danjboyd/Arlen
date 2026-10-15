#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "../shared/ALNTestSupport.h"

// GitHub issue 65: freshly generated apps ship request tests that `arlen test
// --app` builds and runs, and a failing app test fails the command.
@interface AppTestHarnessIntegrationTests : XCTestCase
@end

@implementation AppTestHarnessIntegrationTests

- (void)testGeneratedAppsPassTheirRequestTestsAndFailuresPropagate {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *parent = ALNTestTemporaryDirectory(@"arlen-app-tests");
  XCTAssertNotNil(parent);
  if (parent == nil) {
    return;
  }
  @try {
    int code = 0;
    NSString *output = ALNTestRunShellCapture([NSString stringWithFormat:@"cd %@ && %@",
                                                                         ALNTestShellQuote(repoRoot),
                                                                         ALNTestFrameworkBuildCommand(@"arlen boomhauer")],
                                              &code);
    XCTAssertEqual(0, code, @"%@", output);
    NSString *arlen = [NSString stringWithFormat:@"ARLEN_FRAMEWORK_ROOT=%@ %@",
                                                 ALNTestShellQuote(repoRoot),
                                                 ALNTestShellQuote([repoRoot stringByAppendingPathComponent:@"build/arlen"])];
    for (NSArray *app in @[ @[ @"FullApp", @"--full", @"HomeControllerTests" ], @[ @"LiteApp", @"--lite", @"HomeTests" ] ]) {
      output = ALNTestRunShellCapture([NSString stringWithFormat:@"cd %@ && %@ new %@ %@",
                                                                 ALNTestShellQuote(parent), arlen, app[0], app[1]],
                                      &code);
      XCTAssertEqual(0, code, @"%@", output);
      NSString *appRoot = [parent stringByAppendingPathComponent:app[0]];
      output = ALNTestRunShellCapture([NSString stringWithFormat:@"cd %@ && %@ test --app 2>&1",
                                                                 ALNTestShellQuote(appRoot), arlen],
                                      &code);
      XCTAssertEqual(0, code, @"%@: %@", app[0], output);
      NSString *expected = [NSString stringWithFormat:@"%@: 1 tests PASSED", app[2]];
      XCTAssertTrue([output containsString:expected], @"%@", output);
    }

    NSString *fullRoot = [parent stringByAppendingPathComponent:@"FullApp"];
    output = ALNTestRunShellCapture([NSString stringWithFormat:
                                                  @"cd %@ && %@ generate test Missing --request --route /no-such-page && "
                                                   "%@ test --app 2>&1",
                                                  ALNTestShellQuote(fullRoot), arlen, arlen],
                                    &code);
    XCTAssertNotEqual(0, code, @"%@", output);
    XCTAssertTrue([output containsString:@"MissingTests: 1/1 tests FAILED"], @"%@", output);
    output = ALNTestRunShellCapture([NSString stringWithFormat:@"cd %@ && %@ test --app --only HomeControllerTests 2>&1",
                                                               ALNTestShellQuote(fullRoot), arlen],
                                    &code);
    XCTAssertEqual(0, code, @"%@", output);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:parent error:NULL];
  }
}

@end
