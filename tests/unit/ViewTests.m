#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNEOCRuntime.h"
#import "ALNView.h"

static NSString *RenderAutoLayoutPage(id ctx, NSError **error) {
  if (!ALNEOCSetSlot(ctx, @"sidebar", @"nav", @"pages/show.html.eoc", 1, 1, error)) {
    return nil;
  }
  return @"body";
}

static NSString *RenderAutoLayoutShell(id ctx, NSError **error) {
  NSMutableString *out = [NSMutableString string];
  [out appendString:@"<main>"];
  if (!ALNEOCAppendYield(out, ctx, @"content", @"layouts/application.html.eoc", 1, 1, error)) {
    return nil;
  }
  [out appendString:@"</main><aside>"];
  if (!ALNEOCAppendYield(out, ctx, @"sidebar", @"layouts/application.html.eoc", 1, 10, error)) {
    return nil;
  }
  [out appendString:@"</aside>"];
  return [NSString stringWithString:out];
}

static NSString *RenderExplicitLayoutShell(id ctx, NSError **error) {
  NSMutableString *out = [NSMutableString stringWithString:@"<explicit>"];
  if (!ALNEOCAppendYield(out, ctx, @"content", @"layouts/explicit.html.eoc", 1, 1, error)) {
    return nil;
  }
  [out appendString:@"</explicit>"];
  return [NSString stringWithString:out];
}

static NSString *RenderAuditThrowingTemplate(id ctx, NSError **error) {
  (void)ctx;
  (void)error;
  ALNEOCSetSlotContent(@"audit-secret", @"previous-request-value");
  [NSException raise:@"AuditRenderFailure" format:@"intentional rendering failure"];
  return nil;
}

static NSString *RenderAuditSlotReader(id ctx, NSError **error) {
  NSMutableString *out = [NSMutableString string];
  if (!ALNEOCAppendYield(out, ctx, @"audit-secret", @"audit/reader.html.eoc", 1, 1, error)) return nil;
  return out;
}

@interface ViewTests : XCTestCase
@end

@implementation ViewTests

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

- (void)testRenderExceptionRestoresThreadOptionsAndDiscardsRequestSlots {
  ALNEOCRegisterTemplate(@"audit/throw.html.eoc", &RenderAuditThrowingTemplate);
  ALNEOCRegisterTemplate(@"audit/reader.html.eoc", &RenderAuditSlotReader);
  ALNEOCRegisterTemplate(@"audit/body.html.eoc", &RenderAutoLayoutPage);
  // Exercise an exception in the body and in the layout. The next direct
  // renderer on this same worker must never inherit the failed render's slots.
  for (NSNumber *throwInLayout in @[ @NO, @YES ]) {
    BOOL caught = NO;
    @try {
      [ALNView renderTemplate:throwInLayout.boolValue ? @"audit/body" : @"audit/throw"
                     context:@{}
                      layout:throwInLayout.boolValue ? @"audit/throw" : nil
                strictLocals:YES strictStringify:YES error:NULL];
    } @catch (NSException *exception) {
      caught = [exception.name isEqualToString:@"AuditRenderFailure"];
    }
    XCTAssertTrue(caught);
    XCTAssertFalse(ALNEOCStrictLocalsEnabled());
    XCTAssertFalse(ALNEOCStrictStringifyEnabled());
    XCTAssertEqualObjects(@"", ALNEOCRenderTemplate(@"audit/reader.html.eoc", @{}, NULL));
  }
}

- (void)testRenderExceptionPreservesEnclosingCompositionAndOptions {
  ALNEOCRegisterTemplate(@"audit/throw.html.eoc", &RenderAuditThrowingTemplate);
  ALNEOCRegisterTemplate(@"audit/reader.html.eoc", &RenderAuditSlotReader);
  NSDictionary *options = ALNEOCPushRenderOptions(YES, NO);
  NSDictionary *composition = ALNEOCPushCompositionState();
  @try {
    ALNEOCSetSlotContent(@"audit-secret", @"outer-render-value");
    BOOL caught = NO;
    @try {
      [ALNView renderTemplate:@"audit/throw" context:@{} layout:nil
                strictLocals:NO strictStringify:YES error:NULL];
    } @catch (NSException *exception) {
      caught = [exception.name isEqualToString:@"AuditRenderFailure"];
    }
    XCTAssertTrue(caught);
    XCTAssertTrue(ALNEOCStrictLocalsEnabled());
    XCTAssertFalse(ALNEOCStrictStringifyEnabled());
    XCTAssertEqualObjects(@"outer-render-value", ALNEOCRenderTemplate(@"audit/reader.html.eoc", @{}, NULL));
  } @finally {
    ALNEOCPopCompositionState(composition);
    ALNEOCPopRenderOptions(options);
  }
}

- (void)testRenderTemplateUsesRegisteredLayoutWhenExplicitLayoutMissing {
  ALNEOCRegisterTemplate(@"pages/show.html.eoc", &RenderAutoLayoutPage);
  ALNEOCRegisterTemplate(@"layouts/application.html.eoc", &RenderAutoLayoutShell);
  ALNEOCRegisterTemplateLayout(@"pages/show.html.eoc", @"layouts/application");

  NSError *error = nil;
  NSString *rendered = [ALNView renderTemplate:@"pages/show"
                                       context:@{}
                                        layout:nil
                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"<main>body</main><aside>nav</aside>", rendered);
}

- (void)testRenderTemplateExplicitLayoutOverridesRegisteredLayout {
  ALNEOCRegisterTemplate(@"pages/show.html.eoc", &RenderAutoLayoutPage);
  ALNEOCRegisterTemplate(@"layouts/application.html.eoc", &RenderAutoLayoutShell);
  ALNEOCRegisterTemplate(@"layouts/explicit.html.eoc", &RenderExplicitLayoutShell);
  ALNEOCRegisterTemplateLayout(@"pages/show.html.eoc", @"layouts/application");

  NSError *error = nil;
  NSString *rendered = [ALNView renderTemplate:@"pages/show"
                                       context:@{}
                                        layout:@"layouts/explicit"
                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"<explicit>body</explicit>", rendered);
}

- (void)testRenderTemplateCanDisableRegisteredDefaultLayout {
  ALNEOCRegisterTemplate(@"pages/show.html.eoc", &RenderAutoLayoutPage);
  ALNEOCRegisterTemplate(@"layouts/application.html.eoc", &RenderAutoLayoutShell);
  ALNEOCRegisterTemplateLayout(@"pages/show.html.eoc", @"layouts/application");

  NSError *error = nil;
  NSString *rendered = [ALNView renderTemplate:@"pages/show"
                                       context:@{}
                                        layout:nil
                          defaultLayoutEnabled:NO
                                  strictLocals:NO
                               strictStringify:NO
                                         error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"body", rendered);
}

@end
