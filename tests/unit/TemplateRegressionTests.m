#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNEOCRuntime.h"
#import "ALNEOCTranspiler.h"

#import "../shared/ALNTemplateTestSupport.h"
#import "../shared/ALNTestSupport.h"

@interface TemplateRegressionTests : XCTestCase
@end

@implementation TemplateRegressionTests

- (void)testRegressionCatalogRecordsNamedTemplateBugIntakeCases {
  NSError *error = nil;
  NSDictionary *catalog = ALNTemplateRegressionCatalog(&error);
  XCTAssertNil(error);
  XCTAssertNotNil(catalog);
  XCTAssertEqualObjects(@"phase21-template-regressions-v1", catalog[@"version"]);

  NSArray *cases = [catalog[@"cases"] isKindOfClass:[NSArray class]] ? catalog[@"cases"] : @[];
  XCTAssertTrue([cases count] >= 2);

  NSMutableSet *caseIDs = [NSMutableSet set];
  for (NSDictionary *entry in cases) {
    NSString *caseID = [entry[@"id"] isKindOfClass:[NSString class]] ? entry[@"id"] : @"";
    if ([caseID length] > 0) {
      [caseIDs addObject:caseID];
    }
  }
  XCTAssertTrue([caseIDs containsObject:@"auth_fragment_requires_contract"]);
  XCTAssertTrue([caseIDs containsObject:@"render_missing_as_diagnostic"]);
}

- (void)testRegressionFixtureRequiresContractTranspilesWithRequiredLocalGuards {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText =
      ALNTemplateFixtureText(@"regressions/requires_fragment_contract.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"regressions/requires_fragment_contract.html.eoc"
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(source);
  XCTAssertTrue([source containsString:@"ALNEOCEnsureRequiredLocals(ctx"]);
  XCTAssertTrue([source containsString:@"ALNEOCRenderCollection(out, ctx, @\"partials/_row.html.eoc\""]);
  XCTAssertTrue([source containsString:@"ALNEOCLocal(ctx, @\"title\""]);
}

- (void)testRegressionFixtureRetainsDeterministicRenderMissingAsDiagnostic {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText =
      ALNTemplateFixtureText(@"regressions/render_missing_as.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSDictionary *metadata = [transpiler templateMetadataForTemplateString:templateText
                                                             logicalPath:@"regressions/render_missing_as.html.eoc"
                                                                   error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Render directive requires as:\"item\"", error.localizedDescription);
}

- (void)testAuthModuleFragmentTemplatesWithRequiresTranspileCleanly {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateRoot = ALNTemplateModuleTemplateRoot();
  NSString *tempRoot = ALNTestTemporaryDirectory(@"template_regression_auth_fragments");
  XCTAssertNotNil(tempRoot);
  if (tempRoot == nil) {
    return;
  }

  NSArray<NSString *> *relativePaths = @[
    @"fragments/provider_login_buttons.html.eoc",
    @"fragments/mfa_enrollment_panel.html.eoc",
    @"fragments/mfa_challenge_form.html.eoc",
    @"fragments/mfa_recovery_codes_panel.html.eoc",
    @"fragments/mfa_factor_inventory_panel.html.eoc",
    @"fragments/mfa_sms_enrollment_panel.html.eoc",
    @"fragments/mfa_sms_challenge_form.html.eoc",
  ];

  @try {
    for (NSString *relativePath in relativePaths) {
      NSString *sourcePath = [templateRoot stringByAppendingPathComponent:relativePath];
      NSString *outputPath =
          [tempRoot stringByAppendingPathComponent:[relativePath stringByAppendingString:@".m"]];
      NSError *error = nil;
      BOOL ok = [transpiler transpileTemplateAtPath:sourcePath
                                       templateRoot:templateRoot
                                         outputPath:outputPath
                                              error:&error];
      XCTAssertTrue(ok, @"failed to transpile %@", relativePath);
      XCTAssertNil(error, @"unexpected transpile error for %@", relativePath);

      NSString *generated = [NSString stringWithContentsOfFile:outputPath
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
      XCTAssertNil(error, @"unable to read generated output for %@", relativePath);
      XCTAssertNotNil(generated);
      XCTAssertTrue([generated containsString:@"ALNEOCEnsureRequiredLocals("],
                    @"expected required-local guard in %@", relativePath);
      XCTAssertFalse([generated containsString:@"@ requires"],
                     @"raw requires directive leaked into %@", relativePath);
    }
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:tempRoot error:nil];
  }
}

- (void)testRegressionFixtureRejectsRenderDirectiveWithEmptyWithExpression {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText =
      ALNTemplateFixtureText(@"composition_render_empty_with.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSDictionary *metadata = [transpiler templateMetadataForTemplateString:templateText
                                                             logicalPath:@"regressions/render_empty_with.html.eoc"
                                                                   error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Render directive 'with' expression cannot be empty",
                        error.localizedDescription);
}

@end
