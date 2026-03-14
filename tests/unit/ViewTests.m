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
