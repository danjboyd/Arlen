#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNEOCRuntime.h"
#import <dispatch/dispatch.h>

typedef struct {
  dispatch_semaphore_t held;
  dispatch_semaphore_t release;
  long waitResult;
} RuntimeClassMonitorState;

static void *HoldRuntimeClassMonitor(void *context) {
  RuntimeClassMonitorState *state = context;
  @autoreleasepool {
    @synchronized([NSThread class]) {
      dispatch_semaphore_signal(state->held);
      state->waitResult = dispatch_semaphore_wait(
          state->release, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    }
  }
  return NULL;
}

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

static NSString *RenderOverlayPartial(id ctx, NSError **error) {
  NSError *localError = nil;
  NSString *name = ALNEOCLocal(ctx, @"name", @"partials/_overlay.html.eoc", 1, 1, &localError);
  if (localError != nil) {
    if (error != NULL) {
      *error = localError;
    }
    return nil;
  }
  NSString *shared = ALNEOCLocal(ctx, @"shared", @"partials/_overlay.html.eoc", 1, 10, &localError);
  if (localError != nil) {
    if (error != NULL) {
      *error = localError;
    }
    return nil;
  }
  return [NSString stringWithFormat:@"%@/%@", name ?: @"", shared ?: @""];
}

static NSString *RenderCollectionRow(id ctx, NSError **error) {
  NSError *localError = nil;
  NSString *title = ALNEOCLocal(ctx, @"title", @"partials/_row.html.eoc", 1, 1, &localError);
  if (localError != nil) {
    if (error != NULL) {
      *error = localError;
    }
    return nil;
  }
  NSString *row = ALNEOCLocal(ctx, @"row", @"partials/_row.html.eoc", 1, 10, &localError);
  if (localError != nil) {
    if (error != NULL) {
      *error = localError;
    }
    return nil;
  }
  return [NSString stringWithFormat:@"<li>%@:%@</li>", title ?: @"", row ?: @""];
}

static NSString *RenderCollectionEmpty(id ctx, NSError **error) {
  (void)ctx;
  (void)error;
  return @"<li>empty</li>";
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

- (void)testEscapeHTMLStringReturnsEquivalentStringWhenNothingNeedsEscaping {
  NSString *raw = @"plain text with no markup, 100% safe";
  XCTAssertEqualObjects(ALNEOCEscapeHTMLString(raw), raw);
  XCTAssertEqualObjects(ALNEOCEscapeHTMLString(@""), @"");

  NSMutableString *mutableRaw = [NSMutableString stringWithString:@"mutable"];
  NSString *escaped = ALNEOCEscapeHTMLString(mutableRaw);
  [mutableRaw appendString:@"-changed"];
  XCTAssertEqualObjects(escaped, @"mutable");

  NSMutableString *out = [NSMutableString stringWithString:@"<p>"];
  ALNEOCAppendEscaped(out, raw);
  XCTAssertEqualObjects(out, [@"<p>" stringByAppendingString:raw]);
}

- (void)testEscapeHTMLStringPreservesNonASCIIAndSurrogatePairs {
  // U+1F600 (surrogate pair), U+00E9, U+4E2D, U+2028 and an embedded NUL.
  unichar units[] = {0xD83D, 0xDE00, '<', 0x00E9, '&', 0x4E2D, 0x2028, 0, '\'', 0xD83D, 0xDE00};
  NSString *raw = [NSString stringWithCharacters:units length:sizeof(units) / sizeof(units[0])];
  unichar expectedUnits[] = {0xD83D, 0xDE00, '&', 'l', 't', ';', 0x00E9, '&', 'a', 'm', 'p', ';',
                             0x4E2D, 0x2028, 0, '&', '#', '3', '9', ';', 0xD83D, 0xDE00};
  NSString *expected =
      [NSString stringWithCharacters:expectedUnits
                              length:sizeof(expectedUnits) / sizeof(expectedUnits[0])];
  XCTAssertEqualObjects(ALNEOCEscapeHTMLString(raw), expected);

  NSString *plainNonASCII = @"caf\u00e9 \u4e2d\u6587 \U0001F600";
  XCTAssertEqualObjects(ALNEOCEscapeHTMLString(plainNonASCII), plainNonASCII);
}

- (void)testEscapeHTMLStringHandlesLongInputsAcrossBufferBoundaries {
  NSMutableString *raw = [NSMutableString string];
  NSMutableString *expected = [NSMutableString string];
  for (NSUInteger idx = 0; idx < 700; idx++) {
    [raw appendString:@"a&b<c>d\"e'f\U0001F600"];
    [expected appendString:@"a&amp;b&lt;c&gt;d&quot;e&#39;f\U0001F600"];
  }
  [raw appendString:@" tail"];
  [expected appendString:@" tail"];
  XCTAssertEqualObjects(ALNEOCEscapeHTMLString(raw), expected);

  NSMutableString *out = [NSMutableString stringWithString:@"head "];
  ALNEOCAppendEscaped(out, raw);
  XCTAssertEqualObjects(out, [@"head " stringByAppendingString:expected]);

  NSMutableString *checkedOut = [NSMutableString string];
  NSError *error = nil;
  XCTAssertTrue(ALNEOCAppendEscapedChecked(checkedOut, raw, @"pages/long.html.eoc", 1, 1, &error));
  XCTAssertNil(error);
  XCTAssertEqualObjects(checkedOut, expected);
}

- (void)testJSONForScriptEscapesScriptBreakoutCharacters {
  NSDictionary *payload = @{
    @"name" : @"</script><script>alert(1)</script>",
    @"note" : @"a & b \u2028 c \u2029 d"
  };
  NSString *json = ALNEOCJSONForScript(payload);
  XCTAssertEqualObjects(
      json,
      @"{\"name\":\"\\u003c/script\\u003e\\u003cscript\\u003ealert(1)\\u003c/script\\u003e\","
      @"\"note\":\"a \\u0026 b \\u2028 c \\u2029 d\"}");
  XCTAssertFalse([json containsString:@"<"]);
  XCTAssertFalse([json containsString:@">"]);
  XCTAssertFalse([json containsString:@"&"]);
  XCTAssertFalse([json containsString:@"\u2028"]);
  XCTAssertFalse([json containsString:@"\u2029"]);

  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
  XCTAssertEqualObjects(decoded, payload);
}

- (void)testJSONForScriptSerializesScalarsNilAndUnsupportedValues {
  XCTAssertEqualObjects(ALNEOCJSONForScript(@"x<y"), @"\"x\\u003cy\"");
  XCTAssertEqualObjects(ALNEOCJSONForScript(@42), @"42");
  XCTAssertEqualObjects(ALNEOCJSONForScript(@[ @1, @"caf\u00e9" ]), @"[1,\"caf\u00e9\"]");
  XCTAssertEqualObjects(ALNEOCJSONForScript(@{ @"b" : @2, @"a" : @1 }), @"{\"a\":1,\"b\":2}");
  XCTAssertEqualObjects(ALNEOCJSONForScript(nil), @"null");
  XCTAssertEqualObjects(ALNEOCJSONForScript([NSNull null]), @"null");
  XCTAssertEqualObjects(ALNEOCJSONForScript([NSDate date]), @"null");
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

- (void)testRenderAndIncludeNormalizeUnsuffixedTemplateReferences {
  ALNEOCRegisterTemplate(@"partials/_greeting.html.eoc", &RenderGreeting);

  NSError *renderError = nil;
  NSString *rendered = ALNEOCRenderTemplate(@"partials/_greeting", @"World", &renderError);
  XCTAssertNil(renderError);
  XCTAssertEqualObjects(rendered, @"Hello World");

  NSMutableString *out = [NSMutableString stringWithString:@"Before "];
  NSError *includeError = nil;
  BOOL included = ALNEOCInclude(out, @"World", @"partials/_greeting", &includeError);
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

- (void)testEnsureRequiredLocalsRejectsMissingLocal {
  NSError *error = nil;
  BOOL ok = ALNEOCEnsureRequiredLocals(@{ @"title" : @"Inbox" },
                                       @[ @"title", @"rows" ],
                                       @"pages/show.html.eoc",
                                       2,
                                       4,
                                       &error);
  XCTAssertFalse(ok);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNEOCErrorDomain, error.domain);
  XCTAssertEqual((NSInteger)ALNEOCErrorTemplateExecutionFailed, [error code]);
  XCTAssertEqualObjects(@"Missing required EOC local: $rows", error.localizedDescription);
  XCTAssertEqualObjects(@"rows", error.userInfo[ALNEOCErrorLocalNameKey]);
  XCTAssertEqualObjects(@"pages/show.html.eoc", error.userInfo[ALNEOCErrorPathKey]);
}

- (void)testIncludeWithLocalsOverlaysContext {
  ALNEOCRegisterTemplate(@"partials/_overlay.html.eoc", &RenderOverlayPartial);

  NSMutableString *out = [NSMutableString string];
  NSError *error = nil;
  BOOL included = ALNEOCIncludeWithLocals(out,
                                          @{ @"shared" : @"base" },
                                          @"partials/_overlay",
                                          @{ @"name" : @"local" },
                                          @"pages/show.html.eoc",
                                          4,
                                          2,
                                          &error);
  XCTAssertTrue(included);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"local/base", out);
}

- (void)testIncludeWithLocalsRejectsNonDictionaryLikeLocals {
  NSMutableString *out = [NSMutableString string];
  NSError *error = nil;
  BOOL included = ALNEOCIncludeWithLocals(out,
                                          @{ @"shared" : @"base" },
                                          @"partials/_overlay",
                                          @"bad-locals",
                                          @"pages/show.html.eoc",
                                          4,
                                          2,
                                          &error);
  XCTAssertFalse(included);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorInvalidArgument, [error code]);
  XCTAssertEqualObjects(@"pages/show.html.eoc", error.userInfo[ALNEOCErrorPathKey]);
}

- (void)testRenderCollectionUsesOverlayAndBaseContext {
  ALNEOCRegisterTemplate(@"partials/_row.html.eoc", &RenderCollectionRow);

  NSMutableString *out = [NSMutableString string];
  NSError *error = nil;
  BOOL rendered = ALNEOCRenderCollection(out,
                                         @{ @"title" : @"Inbox" },
                                         @"partials/_row",
                                         @[ @"first", @"second" ],
                                         @"row",
                                         nil,
                                         nil,
                                         @"pages/show.html.eoc",
                                         9,
                                         4,
                                         &error);
  XCTAssertTrue(rendered);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"<li>Inbox:first</li><li>Inbox:second</li>", out);
}

- (void)testRenderCollectionUsesEmptyTemplateForEmptyCollections {
  ALNEOCRegisterTemplate(@"partials/_row.html.eoc", &RenderCollectionRow);
  ALNEOCRegisterTemplate(@"partials/_empty.html.eoc", &RenderCollectionEmpty);

  NSMutableString *out = [NSMutableString string];
  NSError *error = nil;
  BOOL rendered = ALNEOCRenderCollection(out,
                                         @{ @"title" : @"Inbox" },
                                         @"partials/_row",
                                         @[],
                                         @"row",
                                         @"partials/_empty",
                                         nil,
                                         @"pages/show.html.eoc",
                                         12,
                                         4,
                                         &error);
  XCTAssertTrue(rendered);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"<li>empty</li>", out);
}

- (void)testRenderCollectionMatchesPerItemIncludeOutput {
  ALNEOCRegisterTemplate(@"partials/_row.html.eoc", &RenderCollectionRow);

  NSArray *items = @[ @"first", @"<second>", [NSNull null], @"fourth" ];
  NSDictionary *locals = @{ @"title" : @"Shared" };
  NSMutableString *expected = [NSMutableString stringWithString:@"<ul>"];
  for (id item in items) {
    NSMutableDictionary *itemLocals = [locals mutableCopy];
    itemLocals[@"row"] = item;
    NSError *includeError = nil;
    XCTAssertTrue(ALNEOCIncludeWithLocals(expected,
                                          @{ @"title" : @"Base" },
                                          @"partials/_row",
                                          itemLocals,
                                          @"pages/show.html.eoc",
                                          1,
                                          1,
                                          &includeError));
    XCTAssertNil(includeError);
  }

  NSMutableString *out = [NSMutableString stringWithString:@"<ul>"];
  NSError *error = nil;
  BOOL rendered = ALNEOCRenderCollection(out,
                                         @{ @"title" : @"Base" },
                                         @"./partials/_row",
                                         items,
                                         @"row",
                                         nil,
                                         locals,
                                         @"pages/show.html.eoc",
                                         9,
                                         4,
                                         &error);
  XCTAssertTrue(rendered);
  XCTAssertNil(error);
  XCTAssertEqualObjects(out, expected);
  XCTAssertEqualObjects(out,
                        @"<ul><li>Shared:first</li><li>Shared:<second></li>"
                        @"<li>Shared:<null></li><li>Shared:fourth</li>");
}

- (void)testRenderCollectionReportsMissingPartialOnlyWhenItemsExist {
  NSMutableString *out = [NSMutableString string];
  NSError *error = nil;
  XCTAssertTrue(ALNEOCRenderCollection(out,
                                       nil,
                                       @"partials/_missing",
                                       @[],
                                       @"row",
                                       nil,
                                       nil,
                                       @"pages/show.html.eoc",
                                       3,
                                       2,
                                       &error));
  XCTAssertNil(error);
  XCTAssertEqualObjects(out, @"");

  BOOL rendered = ALNEOCRenderCollection(out,
                                         nil,
                                         @"partials/_missing",
                                         @[ @"first", @"second" ],
                                         @"row",
                                         nil,
                                         nil,
                                         @"pages/show.html.eoc",
                                         3,
                                         2,
                                         &error);
  XCTAssertFalse(rendered);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorTemplateNotFound, [error code]);
  XCTAssertEqualObjects(@"partials/_missing.html.eoc", error.userInfo[ALNEOCErrorPathKey]);
  XCTAssertEqualObjects(out, @"");
}

- (void)testRenderCollectionRejectsEmptyItemLocalName {
  NSMutableString *out = [NSMutableString string];
  NSError *error = nil;
  BOOL rendered = ALNEOCRenderCollection(out,
                                         @{ @"title" : @"Inbox" },
                                         @"partials/_row",
                                         @[ @"first" ],
                                         @"",
                                         nil,
                                         nil,
                                         @"pages/show.html.eoc",
                                         14,
                                         3,
                                         &error);
  XCTAssertFalse(rendered);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorInvalidArgument, [error code]);
  XCTAssertEqualObjects(@"EOC collection render requires a non-empty item local name",
                        error.localizedDescription);
}

- (void)testRenderCollectionRejectsNonEnumerableCollection {
  NSMutableString *out = [NSMutableString string];
  NSError *error = nil;
  BOOL rendered = ALNEOCRenderCollection(out,
                                         @{ @"title" : @"Inbox" },
                                         @"partials/_row",
                                         @(42),
                                         @"row",
                                         nil,
                                         nil,
                                         @"pages/show.html.eoc",
                                         15,
                                         3,
                                         &error);
  XCTAssertFalse(rendered);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorInvalidArgument, [error code]);
  XCTAssertEqualObjects(@"EOC collection render requires an enumerable collection",
                        error.localizedDescription);
}

- (void)testRenderCollectionRejectsInvalidOverlayLocals {
  NSMutableString *out = [NSMutableString string];
  NSError *error = nil;
  BOOL rendered = ALNEOCRenderCollection(out,
                                         @{ @"title" : @"Inbox" },
                                         @"partials/_row",
                                         @[ @"first" ],
                                         @"row",
                                         nil,
                                         @"bad-locals",
                                         @"pages/show.html.eoc",
                                         16,
                                         3,
                                         &error);
  XCTAssertFalse(rendered);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorInvalidArgument, [error code]);
  XCTAssertEqualObjects(@"pages/show.html.eoc", error.userInfo[ALNEOCErrorPathKey]);
}

- (void)testSetSlotRejectsEmptySlotName {
  NSError *error = nil;
  BOOL ok = ALNEOCSetSlot(nil, @"", @"nav", @"pages/show.html.eoc", 6, 2, &error);
  XCTAssertFalse(ok);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorInvalidArgument, [error code]);
  XCTAssertEqualObjects(@"EOC slot name cannot be empty", error.localizedDescription);
}

- (void)testSetSlotRejectsInactiveCompositionState {
  NSError *error = nil;
  BOOL ok = ALNEOCSetSlot(nil, @"sidebar", @"nav", @"pages/show.html.eoc", 7, 2, &error);
  XCTAssertFalse(ok);
  XCTAssertNotNil(error);
  XCTAssertEqual((NSInteger)ALNEOCErrorInvalidArgument, [error code]);
  XCTAssertEqualObjects(@"EOC composition state is not active", error.localizedDescription);
}

- (void)testCompositionStateStoresAndYieldsNamedSlots {
  NSDictionary *token = ALNEOCPushCompositionState();
  @try {
    NSError *error = nil;
    XCTAssertTrue(ALNEOCSetSlot(nil,
                                @"sidebar",
                                @"nav",
                                @"pages/show.html.eoc",
                                3,
                                1,
                                &error));
    XCTAssertNil(error);

    NSMutableString *out = [NSMutableString string];
    XCTAssertTrue(ALNEOCAppendYield(out,
                                    @{},
                                    @"sidebar",
                                    @"layouts/application.html.eoc",
                                    2,
                                    1,
                                    &error));
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"nav", out);
  } @finally {
    ALNEOCPopCompositionState(token);
  }
}

- (void)testAppendYieldDefaultsToContentSlot {
  NSDictionary *token = ALNEOCPushCompositionState();
  @try {
    ALNEOCSetSlotContent(@"content", @"body");
    NSMutableString *out = [NSMutableString string];
    NSError *error = nil;
    XCTAssertTrue(ALNEOCAppendYield(out,
                                    @{},
                                    @"",
                                    @"layouts/application.html.eoc",
                                    2,
                                    1,
                                    &error));
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"body", out);
  } @finally {
    ALNEOCPopCompositionState(token);
  }
}

- (void)testAppendYieldEscapesUnfilledNamedSlotContextFallback {
  NSDictionary *token = ALNEOCPushCompositionState();
  @try {
    NSMutableString *out = [NSMutableString string];
    NSError *error = nil;
    NSDictionary *ctx = @{ @"title" : @"</title><script>alert(1)</script>" };
    XCTAssertTrue(ALNEOCAppendYield(out,
                                    ctx,
                                    @"title",
                                    @"layouts/application.html.eoc",
                                    2,
                                    1,
                                    &error));
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"&lt;/title&gt;&lt;script&gt;alert(1)&lt;/script&gt;", out);
  } @finally {
    ALNEOCPopCompositionState(token);
  }
}

- (void)testAppendYieldKeepsFilledNamedSlotRawOverContextValue {
  NSDictionary *token = ALNEOCPushCompositionState();
  @try {
    NSError *error = nil;
    XCTAssertTrue(ALNEOCSetSlot(nil,
                                @"title",
                                @"<b>Rendered</b>",
                                @"pages/show.html.eoc",
                                3,
                                1,
                                &error));
    NSMutableString *out = [NSMutableString string];
    XCTAssertTrue(ALNEOCAppendYield(out,
                                    @{ @"title" : @"<i>context</i>" },
                                    @"title",
                                    @"layouts/application.html.eoc",
                                    2,
                                    1,
                                    &error));
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"<b>Rendered</b>", out);
  } @finally {
    ALNEOCPopCompositionState(token);
  }
}

- (void)testAppendYieldMissingNamedSlotAndContextValueRendersEmpty {
  NSDictionary *token = ALNEOCPushCompositionState();
  @try {
    NSMutableString *out = [NSMutableString string];
    NSError *error = nil;
    XCTAssertTrue(ALNEOCAppendYield(out,
                                    @{},
                                    @"sidebar",
                                    @"layouts/application.html.eoc",
                                    2,
                                    1,
                                    &error));
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"", out);
  } @finally {
    ALNEOCPopCompositionState(token);
  }
}

- (void)testAppendYieldUnnamedContentContextFallbackStaysRaw {
  NSDictionary *token = ALNEOCPushCompositionState();
  @try {
    NSMutableString *out = [NSMutableString string];
    NSError *error = nil;
    XCTAssertTrue(ALNEOCAppendYield(out,
                                    @{ @"content" : @"<p>body</p>" },
                                    @"",
                                    @"layouts/application.html.eoc",
                                    2,
                                    1,
                                    &error));
    XCTAssertNil(error);
    XCTAssertEqualObjects(@"<p>body</p>", out);
  } @finally {
    ALNEOCPopCompositionState(token);
  }
}

- (void)testTemplateRegistryDoesNotAcquireNSThreadClassMonitor {
  RuntimeClassMonitorState state = {
    dispatch_semaphore_create(0), dispatch_semaphore_create(0), -1
  };
  // NSThread, not pthread: on Windows <pthread.h> clashes with the pthread
  // types libdispatch's headers (pulled in by Foundation) declare.
  RuntimeClassMonitorState *statePointer = &state;
  dispatch_semaphore_t finished = dispatch_semaphore_create(0);
  NSThread *thread = [[NSThread alloc] initWithBlock:^{
    (void)HoldRuntimeClassMonitor(statePointer);
    dispatch_semaphore_signal(finished);
  }];
  [thread start];
  long ready = dispatch_semaphore_wait(state.held, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
  if (ready == 0) {
    ALNEOCRegisterTemplate(@"monitor-independent", RenderGreeting);
    ALNEOCRegisterTemplateLayout(@"monitor-independent", @"layouts/application");
    XCTAssertTrue(ALNEOCResolveTemplate(@"monitor-independent") == RenderGreeting);
    XCTAssertEqualObjects(ALNEOCResolveTemplateLayout(@"monitor-independent"), @"layouts/application.html.eoc");
    ALNEOCClearTemplateRegistry();
  }
  dispatch_semaphore_signal(state.release);
  XCTAssertEqual(0L, dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)),
                 @"monitor thread did not finish");
  XCTAssertEqual(ready, 0);
  XCTAssertEqual(state.waitResult, 0, @"Registry operations waited for the shared NSThread class monitor");
#if !OS_OBJECT_USE_OBJC
  dispatch_release(state.held);
  dispatch_release(state.release);
  dispatch_release(finished);
#endif
}

- (void)testTemplateLayoutRegistryResolvesRegisteredLayout {
  ALNEOCRegisterTemplateLayout(@"pages/show.html.eoc", @"layouts/application");
  XCTAssertEqualObjects(@"layouts/application.html.eoc",
                        ALNEOCResolveTemplateLayout(@"pages/show.html.eoc"));
}

@end
