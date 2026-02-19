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
  XCTAssertTrue([source containsString:@"ALNEOCAppendEscaped(out, ([ctx objectForKey:@\"title\"]));"]);
  XCTAssertTrue([source containsString:@"ALNEOCAppendRaw(out, (item));"]);
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

@end
