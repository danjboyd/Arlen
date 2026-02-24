#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNEOCRuntime.h"
#import "ALNEOCTranspiler.h"

@interface TranspilerTests : XCTestCase
@end

@implementation TranspilerTests

- (NSString *)fixturePath:(NSString *)name {
  NSString *root = [[NSFileManager defaultManager] currentDirectoryPath];
  return [root stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"tests/fixtures/templates/%@", name]];
}

- (NSString *)loadFixture:(NSString *)name {
  NSString *path = [self fixturePath:name];
  NSError *error = nil;
  NSString *content = [NSString stringWithContentsOfFile:path
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(content);
  return content;
}

- (void)testSymbolNameSanitization {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *symbol =
      [transpiler symbolNameForLogicalPath:@"partials/_nav-menu.html.eoc"];
  XCTAssertEqualObjects(symbol, @"ALNEOCRender_partials__nav_menu_html_eoc");
}

- (void)testTranspileTemplateStringEmitsExpectedOperations {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"basic.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"basic.html.eoc"
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(source);
  XCTAssertTrue([source containsString:@"ALNEOCAppendEscapedChecked(out, (ALNEOCLocal(ctx, @\"title\""]);
  XCTAssertTrue([source containsString:@"for (NSString *item in ALNEOCLocal(ctx, @\"items\""]);
  XCTAssertTrue([source containsString:@"ALNEOCAppendRawChecked(out, (item)"]);
  XCTAssertFalse([source containsString:@"this is a template comment"]);
  XCTAssertTrue([source containsString:@"#line"]);
}

- (void)testTranspileRejectsUnclosedTagWithLocation {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *broken = [self loadFixture:@"unclosed_tag.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:broken
                                                       logicalPath:@"unclosed_tag.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(ALNEOCErrorDomain, [error domain]);
  XCTAssertNotNil(error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertNotNil(error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testTranspileRejectsEmptyExpressionTag {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = @"<h1><%=   %></h1>";

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"empty_expr.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
}

- (void)testTranspileRewritesSigilMethodCallExpression {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = @"<p><%= [$myObject generateAString] %></p>";

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"method_call.html.eoc"
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(source);
  XCTAssertTrue([source containsString:@"[ALNEOCLocal(ctx, @\"myObject\""]);
  XCTAssertTrue([source containsString:@"generateAString]"]);
}

- (void)testTranspileFixtureRewritesKeypathSigilLocals {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"keypath_locals.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"keypath_locals.html.eoc"
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(source);
  XCTAssertTrue([source containsString:@"NSDictionary *profile = ALNEOCLocalPath(ctx, @\"user.profile\""]);
  XCTAssertTrue([source containsString:@"ALNEOCAppendEscapedChecked(out, (ALNEOCLocalPath(ctx, @\"user.profile.email\""]);
  XCTAssertTrue([source containsString:@"ALNEOCLocal(ctx, @\"title\""]);
}

- (void)testTranspileRejectsInvalidSigilLocal {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = @"<%= $ %>";

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"invalid_sigil.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertNotNil(error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertNotNil(error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testTranspileRejectsInvalidKeypathSigilLocal {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"malformed_invalid_sigil_keypath.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"malformed_invalid_sigil_keypath.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(ALNEOCErrorDomain, [error domain]);
  XCTAssertEqualObjects(@1, error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertEqualObjects(@4, error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testTranspileTemplatePathWritesOutputFile {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *fixture = [self fixturePath:@"basic.html.eoc"];

  NSString *tempRoot = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  NSString *outputPath = [tempRoot stringByAppendingPathComponent:@"basic.html.eoc.m"];

  NSError *error = nil;
  BOOL ok = [transpiler transpileTemplateAtPath:fixture
                                   templateRoot:[self fixturePath:@".."]
                                     outputPath:outputPath
                                          error:&error];
  XCTAssertTrue(ok);
  XCTAssertNil(error);

  BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:outputPath];
  XCTAssertTrue(exists);

  NSString *generated = [NSString stringWithContentsOfFile:outputPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([generated containsString:@"ALNEOCRender_"]);
}

- (void)testTranspileFixtureWithMultilineTagsAndExpressions {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"multiline_tags.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"multiline_tags.html.eoc"
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(source);
  XCTAssertTrue([source containsString:@"NSString *header ="]);
  XCTAssertTrue([source containsString:@"ALNEOCLocal(ctx, @\"title\""]);
  XCTAssertTrue([source containsString:@"NSArray *rows = ALNEOCLocal(ctx, @\"items\""]);
  XCTAssertTrue([source containsString:@"for (NSString *row in rows) {"]);
  XCTAssertTrue([source containsString:@"ALNEOCAppendRawChecked(out, (row)"]);
  XCTAssertTrue([source containsString:@"row-count"]);
}

- (void)testTranspileFixtureRejectsMultilineEmptyExpressionWithDeterministicLocation {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"malformed_empty_expression_multiline.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"malformed_empty_expression_multiline.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(ALNEOCErrorDomain, [error domain]);
  XCTAssertEqualObjects(@2, error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertEqualObjects(@4, error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testTranspileFixtureRejectsMultilineInvalidSigilWithDeterministicLocation {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"malformed_invalid_sigil_multiline.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"malformed_invalid_sigil_multiline.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(ALNEOCErrorDomain, [error domain]);
  XCTAssertEqualObjects(@2, error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertEqualObjects(@4, error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testTranspileFixtureWithNestedControlFlowAndSigils {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"nested_control_flow.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"nested_control_flow.html.eoc"
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(source);
  XCTAssertTrue([source containsString:@"NSArray *sections = ALNEOCLocal(ctx, @\"sections\""]);
  XCTAssertTrue([source containsString:@"for (NSDictionary *section in sections) {"]);
  XCTAssertTrue([source containsString:@"for (NSDictionary *row in rows) {"]);
  XCTAssertTrue([source containsString:@"visibleCount += 1;"]);
  XCTAssertTrue([source containsString:@"ALNEOCAppendRawChecked(out, (row[@\"label\"])"]);
}

- (void)testLintDiagnosticsReportUnguardedIncludeWithDeterministicLocation {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"lint_unguarded_include.html.eoc"];

  NSError *error = nil;
  NSArray<NSDictionary *> *diagnostics =
      [transpiler lintDiagnosticsForTemplateString:templateText
                                       logicalPath:@"lint_unguarded_include.html.eoc"
                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(diagnostics);
  XCTAssertEqual((NSUInteger)1, [diagnostics count]);

  NSDictionary *diagnostic = [diagnostics firstObject];
  XCTAssertEqualObjects(@"warning", diagnostic[ALNEOCLintDiagnosticLevelKey]);
  XCTAssertEqualObjects(@"unguarded_include", diagnostic[ALNEOCLintDiagnosticCodeKey]);
  XCTAssertEqualObjects(@"lint_unguarded_include.html.eoc",
                        diagnostic[ALNEOCLintDiagnosticPathKey]);
  XCTAssertEqualObjects(@2, diagnostic[ALNEOCLintDiagnosticLineKey]);
  XCTAssertEqualObjects(@4, diagnostic[ALNEOCLintDiagnosticColumnKey]);
}

- (void)testLintDiagnosticsDoNotReportGuardedInclude {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"lint_guarded_include.html.eoc"];

  NSError *error = nil;
  NSArray<NSDictionary *> *diagnostics =
      [transpiler lintDiagnosticsForTemplateString:templateText
                                       logicalPath:@"lint_guarded_include.html.eoc"
                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(diagnostics);
  XCTAssertEqual((NSUInteger)0, [diagnostics count]);
}

@end
