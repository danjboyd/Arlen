#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNEOCRuntime.h"
#import "ALNEOCTranspiler.h"

#import "../shared/ALNTemplateTestSupport.h"

@interface TemplateSecurityTests : XCTestCase
@end

@implementation TemplateSecurityTests

- (void)testLintDiagnosticsReportUnguardedIncludeFromSecurityFixtureNamespace {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText =
      ALNTemplateFixtureText(@"security/unguarded_include_warning.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSArray<NSDictionary *> *diagnostics =
      [transpiler lintDiagnosticsForTemplateString:templateText
                                       logicalPath:@"security/unguarded_include_warning.html.eoc"
                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(diagnostics);
  XCTAssertEqual((NSUInteger)1, [diagnostics count]);

  NSDictionary *diagnostic = [diagnostics firstObject];
  XCTAssertEqualObjects(@"warning", diagnostic[ALNEOCLintDiagnosticLevelKey]);
  XCTAssertEqualObjects(@"unguarded_include", diagnostic[ALNEOCLintDiagnosticCodeKey]);
  XCTAssertEqualObjects(@"security/unguarded_include_warning.html.eoc",
                        diagnostic[ALNEOCLintDiagnosticPathKey]);
  XCTAssertEqualObjects(@2, diagnostic[ALNEOCLintDiagnosticLineKey]);
  XCTAssertEqualObjects(@4, diagnostic[ALNEOCLintDiagnosticColumnKey]);
}

- (void)testLintDiagnosticsDoNotReportGuardedIncludeFromSecurityFixtureNamespace {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"security/guarded_include_ok.html.eoc",
                                                  &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSArray<NSDictionary *> *diagnostics =
      [transpiler lintDiagnosticsForTemplateString:templateText
                                       logicalPath:@"security/guarded_include_ok.html.eoc"
                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(diagnostics);
  XCTAssertEqual((NSUInteger)0, [diagnostics count]);
}

@end
