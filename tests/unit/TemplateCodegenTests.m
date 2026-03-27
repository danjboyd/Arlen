#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNEOCRuntime.h"
#import "ALNEOCTranspiler.h"

#import "../shared/ALNTemplateTestSupport.h"
#import "../shared/ALNTestSupport.h"

@interface TemplateCodegenTests : XCTestCase
@end

@implementation TemplateCodegenTests

- (void)testTranspileTemplateStringEmitsExpectedOperations {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"basic.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

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

- (void)testTranspileRewritesSigilMethodCallExpression {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];

  NSError *error = nil;
  NSString *source = [transpiler transpiledSourceForTemplateString:@"<p><%= [$myObject generateAString] %></p>"
                                                       logicalPath:@"method_call.html.eoc"
                                                             error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(source);
  XCTAssertTrue([source containsString:@"[ALNEOCLocal(ctx, @\"myObject\""]);
  XCTAssertTrue([source containsString:@"generateAString]"]);
}

- (void)testTranspileFixtureRewritesKeypathSigilLocals {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"keypath_locals.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

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

- (void)testTranspileTemplatePathWritesOutputFile {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSString *fixture = ALNTemplateFixturePath(@"basic.html.eoc");
  NSString *tempRoot = ALNTestTemporaryDirectory(@"template_codegen_output");
  XCTAssertNotNil(tempRoot);
  if (tempRoot == nil) {
    return;
  }
  NSString *outputPath = [tempRoot stringByAppendingPathComponent:@"basic.html.eoc.m"];

  @try {
    NSError *error = nil;
    BOOL ok = [transpiler transpileTemplateAtPath:fixture
                                     templateRoot:ALNTemplateFixturePath(@"..")
                                       outputPath:outputPath
                                            error:&error];
    XCTAssertTrue(ok);
    XCTAssertNil(error);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:outputPath]);

    NSString *generated = [NSString stringWithContentsOfFile:outputPath
                                                    encoding:NSUTF8StringEncoding
                                                       error:&error];
    XCTAssertNil(error);
    XCTAssertTrue([generated containsString:@"ALNEOCRender_"]);
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:tempRoot error:nil];
  }
}

- (void)testTranspileFixtureWithMultilineTagsAndExpressions {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"multiline_tags.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

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

- (void)testTranspileFixtureWithNestedControlFlowAndSigils {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"nested_control_flow.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

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

- (void)testTemplateMetadataCapturesCompositionContracts {
  ALNEOCTranspiler *transpiler = [[ALNEOCTranspiler alloc] init];
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_page.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSDictionary *metadata = [transpiler templateMetadataForTemplateString:templateText
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
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_layout.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

  NSError *error = nil;
  NSDictionary *metadata = [transpiler templateMetadataForTemplateString:templateText
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
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_page.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

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
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_layout.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

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
  NSError *fixtureError = nil;
  NSString *templateText = ALNTemplateFixtureText(@"composition_page.html.eoc", &fixtureError);
  XCTAssertNil(fixtureError);
  XCTAssertNotNil(templateText);

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

@end
