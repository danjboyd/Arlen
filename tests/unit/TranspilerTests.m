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

- (NSString *)moduleTemplateRoot {
  NSString *root = [[NSFileManager defaultManager] currentDirectoryPath];
  return [root stringByAppendingPathComponent:@"modules/auth/Resources/Templates"];
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

- (void)testTemplateMetadataCapturesCompositionContracts {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_page.html.eoc"];

  NSError *error = nil;
  NSDictionary *metadata =
      [transpiler templateMetadataForTemplateString:templateText
                                        logicalPath:@"pages/show.html.eoc"
                                              error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(metadata);
  XCTAssertEqualObjects(@"layouts/application.html.eoc",
                        metadata[ALNEOCTemplateMetadataLayoutPathKey]);
  XCTAssertEqualObjects((@[ @"rows", @"title" ]),
                        metadata[ALNEOCTemplateMetadataRequiredLocalsKey]);
  XCTAssertEqualObjects((@[ @"sidebar" ]),
                        metadata[ALNEOCTemplateMetadataFilledSlotsKey]);
  XCTAssertEqualObjects((@[ @"layouts/application.html.eoc",
                            @"partials/_empty.html.eoc",
                            @"partials/_row.html.eoc",
                            @"partials/_summary.html.eoc" ]),
                        metadata[ALNEOCTemplateMetadataStaticDependenciesKey]);
}

- (void)testTemplateMetadataCapturesYieldSlotsForLayoutFixture {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_layout.html.eoc"];

  NSError *error = nil;
  NSDictionary *metadata =
      [transpiler templateMetadataForTemplateString:templateText
                                        logicalPath:@"layouts/application.html.eoc"
                                              error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(metadata);
  XCTAssertEqualObjects((@[ @"content", @"sidebar" ]),
                        metadata[ALNEOCTemplateMetadataYieldSlotsKey]);
  XCTAssertEqualObjects((@[]), metadata[ALNEOCTemplateMetadataFilledSlotsKey]);
}

- (void)testTranspileFixtureWithCompositionDirectivesEmitsRuntimeHelpers {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_page.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"pages/show.html.eoc"
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(source);
  XCTAssertTrue([source containsString:@"ALNEOCEnsureRequiredLocals(ctx"]);
  XCTAssertTrue([source containsString:@"ALNEOCSetSlot(ctx, @\"sidebar\""]);
  XCTAssertTrue([source containsString:@"ALNEOCIncludeWithLocals(out, ctx, @\"partials/_summary.html.eoc\""]);
  XCTAssertTrue([source containsString:@"ALNEOCRenderCollection(out, ctx, @\"partials/_row.html.eoc\""]);
  XCTAssertTrue([source containsString:@"@\"partials/_empty.html.eoc\""]);
  XCTAssertTrue([source containsString:@"ALNEOCLocal(ctx, @\"rows\""]);
  XCTAssertTrue([source containsString:@"ALNEOCLocal(ctx, @\"title\""]);
}

- (void)testTranspileLayoutFixtureEmitsYieldHelpers {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_layout.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"layouts/application.html.eoc"
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(source);
  XCTAssertTrue([source containsString:@"ALNEOCAppendYield(out, ctx, @\"content\""]);
  XCTAssertTrue([source containsString:@"ALNEOCAppendYield(out, ctx, @\"sidebar\""]);
}

- (void)testGeneratedTemplatesSelfRegisterRenderFunctionAndLayout {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_page.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"pages/show.html.eoc"
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(source);
  XCTAssertTrue([source containsString:@"__attribute__((constructor))"]);
  XCTAssertTrue([source containsString:@"ALNEOCRegisterTemplate(@\"pages/show.html.eoc\""]);
  XCTAssertTrue([source containsString:@"ALNEOCRegisterTemplateLayout(@\"pages/show.html.eoc\", @\"layouts/application.html.eoc\")"]);
}

- (void)testTemplateMetadataRejectsMultipleLayoutDirectives {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_multiple_layouts.html.eoc"];

  NSError *error = nil;
  NSDictionary *metadata =
      [transpiler templateMetadataForTemplateString:templateText
                                        logicalPath:@"pages/show.html.eoc"
                                              error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Multiple layout directives are not allowed",
                        error.localizedDescription);
}

- (void)testTranspileRejectsUnclosedSlotDirective {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_unclosed_slot.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"composition_unclosed_slot.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Unclosed slot directive", error.localizedDescription);
}

- (void)testTranspileRejectsMalformedRequiresDirective {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_bad_requires.html.eoc"];

  NSError *error = nil;
  NSDictionary *metadata =
      [transpiler templateMetadataForTemplateString:templateText
                                        logicalPath:@"pages/show.html.eoc"
                                              error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Expected ',' between required locals", error.localizedDescription);
}

- (void)testAuthModuleFragmentTemplatesWithRequiresTranspileCleanly {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateRoot = [self moduleTemplateRoot];
  NSString *tempRoot = [NSTemporaryDirectory()
      stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  NSArray<NSString *> *relativePaths = @[
    @"fragments/provider_login_buttons.html.eoc",
    @"fragments/mfa_enrollment_panel.html.eoc",
    @"fragments/mfa_challenge_form.html.eoc",
    @"fragments/mfa_recovery_codes_panel.html.eoc",
    @"fragments/mfa_factor_inventory_panel.html.eoc",
    @"fragments/mfa_sms_enrollment_panel.html.eoc",
    @"fragments/mfa_sms_challenge_form.html.eoc",
  ];

  for (NSString *relativePath in relativePaths) {
    NSString *sourcePath = [templateRoot stringByAppendingPathComponent:relativePath];
    NSString *outputPath = [tempRoot stringByAppendingPathComponent:[relativePath stringByAppendingString:@".m"]];
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
}

- (void)testTranspileRejectsUnexpectedEndslotDirective {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_unexpected_endslot.html.eoc"];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:templateText
                                                       logicalPath:@"pages/show.html.eoc"
                                                             error:&error];
  XCTAssertNil(source);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Unexpected endslot directive", error.localizedDescription);
}

- (void)testTranspileRejectsYieldDirectiveWithTrailingContent {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_yield_trailing_content.html.eoc"];

  NSError *error = nil;
  NSDictionary *metadata =
      [transpiler templateMetadataForTemplateString:templateText
                                        logicalPath:@"layouts/application.html.eoc"
                                              error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Unexpected content after yield directive", error.localizedDescription);
}

- (void)testTranspileRejectsSlotDirectiveWithTrailingContent {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_slot_trailing_content.html.eoc"];

  NSError *error = nil;
  NSDictionary *metadata =
      [transpiler templateMetadataForTemplateString:templateText
                                        logicalPath:@"pages/show.html.eoc"
                                              error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Unexpected content after slot directive", error.localizedDescription);
}

- (void)testTranspileRejectsIncludeDirectiveWithEmptyWithExpression {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_include_empty_with.html.eoc"];

  NSError *error = nil;
  NSDictionary *metadata =
      [transpiler templateMetadataForTemplateString:templateText
                                        logicalPath:@"pages/show.html.eoc"
                                              error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Include directive 'with' expression cannot be empty",
                        error.localizedDescription);
}

- (void)testTranspileRejectsRenderDirectiveMissingCollectionExpression {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_render_missing_collection.html.eoc"];

  NSError *error = nil;
  NSDictionary *metadata =
      [transpiler templateMetadataForTemplateString:templateText
                                        logicalPath:@"pages/show.html.eoc"
                                              error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Render directive requires collection:<expr>", error.localizedDescription);
}

- (void)testTranspileRejectsRenderDirectiveMissingItemLocalName {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_render_missing_as.html.eoc"];

  NSError *error = nil;
  NSDictionary *metadata =
      [transpiler templateMetadataForTemplateString:templateText
                                        logicalPath:@"pages/show.html.eoc"
                                              error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Render directive requires as:\"item\"", error.localizedDescription);
}

- (void)testTranspileRejectsRenderDirectiveWithEmptyWithExpression {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *templateText = [self loadFixture:@"composition_render_empty_with.html.eoc"];

  NSError *error = nil;
  NSDictionary *metadata =
      [transpiler templateMetadataForTemplateString:templateText
                                        logicalPath:@"pages/show.html.eoc"
                                              error:&error];
  XCTAssertNil(metadata);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTranspilerSyntax, [error code]);
  XCTAssertEqualObjects(@"Render directive 'with' expression cannot be empty",
                        error.localizedDescription);
}

@end
