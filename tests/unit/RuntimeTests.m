#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNEOCRuntime.h"

static NSString *RenderGreeting(id ctx, NSError **error) {
  (void)error;
  NSString *name = (ctx != nil) ? [ctx description] : @"unknown";
  return [NSString stringWithFormat:@"Hello %@", name];
}

static NSString *RenderFailure(id ctx, NSError **error) {
  (void)ctx;
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"UnitTest"
                                 code:99
                             userInfo:@{NSLocalizedDescriptionKey : @"render failed"}];
  }
  return nil;
}

@interface RuntimeTests : XCTestCase
@end

@implementation RuntimeTests

- (void)setUp {
  [super setUp];
  ALNEOCClearTemplateRegistry();
}

- (void)tearDown {
  ALNEOCClearTemplateRegistry();
  [super tearDown];
}

- (void)testEscapeHTMLStringEscapesSpecialCharacters {
  NSString *raw = @"a&b<c>d\"e'f";
  NSString *escaped = ALNEOCEscapeHTMLString(raw);
  XCTAssertEqualObjects(escaped, @"a&amp;b&lt;c&gt;d&quot;e&#39;f");
}

- (void)testAppendEscapedUsesDescriptionForNonStrings {
  NSMutableString *out = [NSMutableString string];
  NSDictionary *value = @{@"k" : @"v"};
  ALNEOCAppendEscaped(out, value);
  XCTAssertTrue([out containsString:@"k"]);
  XCTAssertTrue([out containsString:@"v"]);
}

- (void)testRegisterRenderAndIncludeTemplate {
  ALNEOCRegisterTemplate(@"partials/_greeting.html.eoc", &RenderGreeting);

  NSError *renderError = nil;
  NSString *rendered = ALNEOCRenderTemplate(@"partials/_greeting.html.eoc", @"World",
                                             &renderError);
  XCTAssertNil(renderError);
  XCTAssertEqualObjects(rendered, @"Hello World");

  NSMutableString *out = [NSMutableString stringWithString:@"Before "];
  NSError *includeError = nil;
  BOOL included =
      ALNEOCInclude(out, @"World", @"partials/_greeting.html.eoc", &includeError);
  XCTAssertTrue(included);
  XCTAssertNil(includeError);
  XCTAssertEqualObjects(out, @"Before Hello World");
}

- (void)testMissingTemplateReturnsTemplateNotFoundError {
  NSError *error = nil;
  NSString *rendered = ALNEOCRenderTemplate(@"missing.html.eoc", nil, &error);
  XCTAssertNil(rendered);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTemplateNotFound, [error code]);
  XCTAssertEqualObjects(ALNEOCErrorDomain, [error domain]);
}

- (void)testRenderFailureBubblesUnderlyingError {
  ALNEOCRegisterTemplate(@"partials/_failure.html.eoc", &RenderFailure);

  NSError *error = nil;
  NSString *rendered = ALNEOCRenderTemplate(@"partials/_failure.html.eoc", nil, &error);
  XCTAssertNil(rendered);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(@"UnitTest", [error domain]);
  XCTAssertEqual((NSInteger)99, [error code]);
}

@end
