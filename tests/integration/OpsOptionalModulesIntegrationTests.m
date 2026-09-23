#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "../shared/ALNTestSupport.h"

@interface OpsOptionalModulesIntegrationTests : XCTestCase
@end
@implementation OpsOptionalModulesIntegrationTests
- (void)testScaffoldLinksAndRunsWithoutOptionalModules {
  NSString *repo = [[NSFileManager defaultManager] currentDirectoryPath];
  NSString *root = ALNTestTemporaryDirectory(@"ops-optional-modules");
  XCTAssertNotNil(root);
  if (!root) return;
  @try {
    NSString *app = [root stringByAppendingPathComponent:@"Probe"];
    NSString *prefix = [NSString stringWithFormat:@"%@ && export ARLEN_FRAMEWORK_ROOT=%@ && ",
                       ALNTestGNUstepSourceCommandForRepoRoot(repo), ALNTestShellQuote(repo)];
    NSString *cli = ALNTestShellQuote([repo stringByAppendingPathComponent:@"build/arlen"]);
    int code = 0;
    NSString *output = ALNTestRunShellCapture([prefix stringByAppendingFormat:
      @"cd %@ && %@ new Probe --full && cd Probe && %@ module add ops",
      ALNTestShellQuote(root), cli, cli], &code);
    XCTAssertEqual(0, code, @"%@", output);
    if (code) return;
    NSError *error = nil;
    NSString *probe = [NSString stringWithContentsOfFile:[repo stringByAppendingPathComponent:
                       @"tests/fixtures/modules/ops_optional_probe.m"] encoding:NSUTF8StringEncoding error:&error];
    XCTAssertTrue(ALNTestWriteUTF8File([app stringByAppendingPathComponent:@"src/main.m"], probe, &error));
    // First prove ops alone, then the exact reported subset. No live database is needed.
    for (NSString *extraModules in @[ @"", @"auth jobs search" ]) {
      NSString *command = [prefix stringByAppendingFormat:
        @"cd %@ && for module in %@; do %@ module add \"$module\" || exit; done && %@ boomhauer --prepare-only && .boomhauer/build/boomhauer-app",
        ALNTestShellQuote(app), extraModules, cli, cli];
      output = ALNTestRunShellCapture(command, &code);
      XCTAssertEqual(0, code, @"%@", output);
      XCTAssertTrue([output containsString:@"ops optional modules: ok"], @"%@", output);
    }
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
  }
}
@end
