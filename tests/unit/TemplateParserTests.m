#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNEOCRuntime.h"
#import "ALNEOCTranspiler.h"

#import "../shared/ALNTemplateTestSupport.h"

@interface TemplateParserTests : XCTestCase
@end

@implementation TemplateParserTests

- (void)testSymbolNameSanitization {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *symbol =
      [transpiler symbolNameForLogicalPath:@"partials/_nav-menu.html.eoc"];
  XCTAssertEqualObjects(symbol, @"ALNEOCRender_partials__nav_menu_html_eoc");
}

- (void)testRejectsUnclosedTagWithLocationFromParserFixtureNamespace {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *broken = ALNTemplateFixtureText(@"parser/invalid/unclosed_tag.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(broken);

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:broken
                                                       logicalPath:@"parser/invalid/unclosed_tag.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(ALNEOCErrorDomain, [error domain]);
  XCTAssertNotNil(error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertNotNil(error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testRejectsEmptyExpressionTag {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:@"<h1><%=   %></h1>"
                                                       logicalPath:@"parser/invalid/empty_expr.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
}

- (void)testRejectsInvalidSigilLocal {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:@"<%= $ %>"
                                                       logicalPath:@"parser/invalid/invalid_sigil.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertNotNil(error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertNotNil(error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testRejectsInvalidKeypathSigilLocal {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"malformed_invalid_sigil_keypath.html.eoc",
                                                  &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"parser/invalid/malformed_invalid_sigil_keypath.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(ALNEOCErrorDomain, [error domain]);
  XCTAssertEqualObjects(@1, error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertEqualObjects(@4, error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testRejectsMultilineEmptyExpressionWithDeterministicLocation {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText =
      ALNTemplateFixtureText(@"parser/invalid/malformed_empty_expression_multiline.html.eoc",
                             &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"parser/invalid/malformed_empty_expression_multiline.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(ALNEOCErrorDomain, [error domain]);
  XCTAssertEqualObjects(@2, error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertEqualObjects(@4, error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testRejectsMultilineInvalidSigilWithDeterministicLocation {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText =
      ALNTemplateFixtureText(@"parser/invalid/malformed_invalid_sigil_multiline.html.eoc",
                             &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"parser/invalid/malformed_invalid_sigil_multiline.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(ALNEOCErrorDomain, [error domain]);
  XCTAssertEqualObjects(@2, error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertEqualObjects(@4, error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testTemplateMetadataRejectsMultipleLayoutDirectives {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_multiple_layouts.html.eoc",
                                                  &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSDictionary *metadata = [transpiler templateMetadataForTemplateString:templateText
                                                             logicalPath:@"pages/show.html.eoc"
                                                                   error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Multiple layout directives are not allowed",
                        error.localizedDescription);
}

- (void)testRejectsUnclosedSlotDirective {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_unclosed_slot.html.eoc",
                                                  &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"pages/show.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Unclosed slot directive", error.localizedDescription);
}

- (void)testRejectsMalformedRequiresDirective {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_bad_requires.html.eoc",
                                                  &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSDictionary *metadata = [transpiler templateMetadataForTemplateString:templateText
                                                             logicalPath:@"pages/show.html.eoc"
                                                                   error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Expected ',' between required locals", error.localizedDescription);
}

- (void)testRejectsUnexpectedEndslotDirective {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_unexpected_endslot.html.eoc",
                                                  &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"pages/show.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Unexpected endslot directive", error.localizedDescription);
}

- (void)testRejectsYieldDirectiveWithTrailingContent {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_yield_trailing_content.html.eoc",
                                                  &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSDictionary *metadata = [transpiler templateMetadataForTemplateString:templateText
                                                             logicalPath:@"layouts/application.html.eoc"
                                                                   error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Unexpected content after yield directive",
                        error.localizedDescription);
}

- (void)testRejectsSlotDirectiveWithTrailingContent {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_slot_trailing_content.html.eoc",
                                                  &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSDictionary *metadata = [transpiler templateMetadataForTemplateString:templateText
                                                             logicalPath:@"pages/show.html.eoc"
                                                                   error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Unexpected content after slot directive",
                        error.localizedDescription);
}

- (void)testRejectsIncludeDirectiveWithEmptyWithExpression {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_include_empty_with.html.eoc",
                                                  &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSDictionary *metadata = [transpiler templateMetadataForTemplateString:templateText
                                                             logicalPath:@"pages/show.html.eoc"
                                                                   error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Include directive 'with' expression cannot be empty",
                        error.localizedDescription);
}

- (void)testRejectsRenderDirectiveMissingCollectionExpression {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_render_missing_collection.html.eoc",
                                                  &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSDictionary *metadata = [transpiler templateMetadataForTemplateString:templateText
                                                             logicalPath:@"pages/show.html.eoc"
                                                                   error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Render directive requires collection:<expr>",
                        error.localizedDescription);
}

@end
