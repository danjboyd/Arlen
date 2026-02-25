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

@interface RuntimeStringValueObject : NSObject
@end

@implementation RuntimeStringValueObject

- (NSString *)stringValue {
  return @"runtime-string-value";
}

@end

@interface RuntimeBadStringValueObject : NSObject
@end

@implementation RuntimeBadStringValueObject

- (id)stringValue {
  return @(123);
}

@end

@interface RuntimeTests : XCTestCase
@end

@implementation RuntimeTests

- (void)setUp {
  [super setUp];
  ALNEOCClearTemplateRegistry();
  ALNEOCSetStrictLocalsEnabled(NO);
  ALNEOCSetStrictStringifyEnabled(NO);
}

- (void)tearDown {
  ALNEOCClearTemplateRegistry();
  ALNEOCSetStrictLocalsEnabled(NO);
  ALNEOCSetStrictStringifyEnabled(NO);
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

- (void)testLocalLookupFromDictionary {
  NSDictionary *ctx = @{@"title" : @"hello"};
  NSError *error = nil;
  id value = ALNEOCLocal(ctx, @"title", @"index.html.eoc", 3, 4, &error);
  XCTAssertEqualObjects(@"hello", value);
  XCTAssertNil(error);
}

- (void)testStrictLocalsMissingValueProducesDiagnostic {
  ALNEOCSetStrictLocalsEnabled(YES);

  NSError *error = nil;
  id value = ALNEOCLocal(@{}, @"missingKey", @"index.html.eoc", 8, 16, &error);
  XCTAssertNil(value);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNEOCErrorDomain, error.domain);
  XCTAssertEqual((NSInteger)ALNEOCErrorTemplateExecutionFailed, [error code]);
  XCTAssertEqualObjects(@"index.html.eoc", error.userInfo[ALNEOCErrorPathKey]);
  XCTAssertEqualObjects(@8, error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertEqualObjects(@16, error.userInfo[ALNEOCErrorColumnKey]);
  XCTAssertEqualObjects(@"missingKey", error.userInfo[ALNEOCErrorLocalNameKey]);
}

- (void)testLocalPathLookupFromNestedDictionary {
  NSDictionary *ctx = @{
    @"user" : @{
      @"profile" : @{
        @"email" : @"dev@example.test",
      },
    },
  };
  NSError *error = nil;
  id value = ALNEOCLocalPath(ctx, @"user.profile.email", @"index.html.eoc", 5, 3, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"dev@example.test", value);
}

- (void)testStrictLocalsMissingKeyPathSegmentProducesDiagnostic {
  ALNEOCSetStrictLocalsEnabled(YES);

  NSDictionary *ctx = @{ @"user" : @{} };
  NSError *error = nil;
  id value = ALNEOCLocalPath(ctx, @"user.profile.email", @"index.html.eoc", 12, 8, &error);
  XCTAssertNil(value);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNEOCErrorDomain, error.domain);
  XCTAssertEqual((NSInteger)ALNEOCErrorTemplateExecutionFailed, [error code]);
  XCTAssertEqualObjects(@"index.html.eoc", error.userInfo[ALNEOCErrorPathKey]);
  XCTAssertEqualObjects(@12, error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertEqualObjects(@8, error.userInfo[ALNEOCErrorColumnKey]);
  XCTAssertEqualObjects(@"user", error.userInfo[ALNEOCErrorLocalNameKey]);
  XCTAssertEqualObjects(@"user.profile.email", error.userInfo[ALNEOCErrorKeyPathKey]);
  XCTAssertEqualObjects(@"profile", error.userInfo[ALNEOCErrorSegmentKey]);
}

- (void)testStrictStringifyAllowsStringValueObjects {
  ALNEOCSetStrictStringifyEnabled(YES);

  NSMutableString *out = [NSMutableString string];
  NSError *error = nil;
  BOOL ok = ALNEOCAppendEscapedChecked(out,
                                       [[RuntimeStringValueObject alloc] init],
                                       @"index.html.eoc",
                                       2,
                                       5,
                                       &error);
  XCTAssertTrue(ok);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"runtime-string-value", out);
}

- (void)testStrictStringifyRejectsNonStringConvertibleOutput {
  ALNEOCSetStrictStringifyEnabled(YES);

  NSMutableString *out = [NSMutableString string];
  NSError *error = nil;
  BOOL ok = ALNEOCAppendRawChecked(out,
                                   [[RuntimeBadStringValueObject alloc] init],
                                   @"index.html.eoc",
                                   11,
                                   9,
                                   &error);
  XCTAssertFalse(ok);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNEOCErrorDomain, error.domain);
  XCTAssertEqual((NSInteger)ALNEOCErrorTemplateExecutionFailed, [error code]);
  XCTAssertEqualObjects(@"index.html.eoc", error.userInfo[ALNEOCErrorPathKey]);
  XCTAssertEqualObjects(@11, error.userInfo[ALNEOCErrorLineKey]);
  XCTAssertEqualObjects(@9, error.userInfo[ALNEOCErrorColumnKey]);
}

- (void)testPushPopRenderOptionsRestoresPriorStrictFlags {
  ALNEOCSetStrictLocalsEnabled(NO);
  ALNEOCSetStrictStringifyEnabled(NO);

  NSDictionary *token = ALNEOCPushRenderOptions(YES, YES);
  XCTAssertTrue(ALNEOCStrictLocalsEnabled());
  XCTAssertTrue(ALNEOCStrictStringifyEnabled());

  ALNEOCPopRenderOptions(token);
  XCTAssertFalse(ALNEOCStrictLocalsEnabled());
  XCTAssertFalse(ALNEOCStrictStringifyEnabled());
}

- (void)testPushPopRenderOptionsSupportsNestedScopes {
  ALNEOCSetStrictLocalsEnabled(NO);
  ALNEOCSetStrictStringifyEnabled(NO);

  NSDictionary *outer = ALNEOCPushRenderOptions(YES, NO);
  XCTAssertTrue(ALNEOCStrictLocalsEnabled());
  XCTAssertFalse(ALNEOCStrictStringifyEnabled());

  NSDictionary *inner = ALNEOCPushRenderOptions(NO, YES);
  XCTAssertFalse(ALNEOCStrictLocalsEnabled());
  XCTAssertTrue(ALNEOCStrictStringifyEnabled());

  ALNEOCPopRenderOptions(inner);
  XCTAssertTrue(ALNEOCStrictLocalsEnabled());
  XCTAssertFalse(ALNEOCStrictStringifyEnabled());

  ALNEOCPopRenderOptions(outer);
  XCTAssertFalse(ALNEOCStrictLocalsEnabled());
  XCTAssertFalse(ALNEOCStrictStringifyEnabled());
}

@end
