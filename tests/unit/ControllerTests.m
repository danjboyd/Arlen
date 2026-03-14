#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNController.h"
#import "ALNContext.h"
#import "ALNEOCRuntime.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

static NSString *RenderControllerPage(id ctx, NSError **error) {
  (void)ctx;
  (void)error;
  return @"body";
}

static NSString *RenderControllerDefaultLayout(id ctx, NSError **error) {
  NSMutableString *out = [NSMutableString stringWithString:@"<main>"];
  if (!ALNEOCAppendYield(out, ctx, @"content", @"layouts/application.html.eoc", 1, 1, error)) {
    return nil;
  }
  [out appendString:@"</main>"];
  return [NSString stringWithString:out];
}

static NSString *RenderControllerAlternateLayout(id ctx, NSError **error) {
  NSMutableString *out = [NSMutableString stringWithString:@"<alt>"];
  if (!ALNEOCAppendYield(out, ctx, @"content", @"layouts/alternate.html.eoc", 1, 1, error)) {
    return nil;
  }
  [out appendString:@"</alt>"];
  return [NSString stringWithString:out];
}

@interface ControllerTestHarness : ALNController
@end

@implementation ControllerTestHarness
@end

@interface ControllerTests : XCTestCase
@end

@implementation ControllerTests

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

- (ALNContext *)freshContext {
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET"
                                                      path:@"/"
                                               queryString:@""
                                                   headers:@{}
                                                      body:[NSData data]];
  ALNResponse *response = [[ALNResponse alloc] init];
  ALNLogger *logger = [[ALNLogger alloc] initWithFormat:@"json"];
  ALNPerfTrace *trace = [[ALNPerfTrace alloc] initWithEnabled:NO];
  return [[ALNContext alloc] initWithRequest:request
                                    response:response
                                      params:@{}
                                       stash:[NSMutableDictionary dictionary]
                                      logger:logger
                                   perfTrace:trace
                                   routeName:@""
                              controllerName:@""
                                  actionName:@""];
}

- (ControllerTestHarness *)freshController {
  ControllerTestHarness *controller = [[ControllerTestHarness alloc] init];
  controller.context = [self freshContext];
  return controller;
}

- (NSString *)responseBodyText:(ALNResponse *)response {
  return [[NSString alloc] initWithData:[response bodyDataForTransmission]
                               encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)registerLayoutFixtureTemplates {
  ALNEOCRegisterTemplate(@"pages/show.html.eoc", &RenderControllerPage);
  ALNEOCRegisterTemplate(@"layouts/application.html.eoc", &RenderControllerDefaultLayout);
  ALNEOCRegisterTemplate(@"layouts/alternate.html.eoc", &RenderControllerAlternateLayout);
  ALNEOCRegisterTemplateLayout(@"pages/show.html.eoc", @"layouts/application");
}

- (void)testRenderTemplateUsesRegisteredLayoutFromTemplateMetadata {
  [self registerLayoutFixtureTemplates];
  ControllerTestHarness *controller = [self freshController];

  NSError *error = nil;
  BOOL rendered = [controller renderTemplate:@"pages/show" context:@{} error:&error];

  XCTAssertTrue(rendered);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"<main>body</main>", [self responseBodyText:controller.context.response]);
  XCTAssertEqualObjects(@"text/html; charset=utf-8",
                        [controller.context.response headerForName:@"Content-Type"]);
}

- (void)testUseTemplateLayoutOverridesRegisteredLayout {
  [self registerLayoutFixtureTemplates];
  ControllerTestHarness *controller = [self freshController];
  [controller useTemplateLayout:@"layouts/alternate"];

  NSError *error = nil;
  BOOL rendered = [controller renderTemplate:@"pages/show" context:@{} error:&error];

  XCTAssertTrue(rendered);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"<alt>body</alt>", [self responseBodyText:controller.context.response]);
}

- (void)testDisableTemplateLayoutSkipsRegisteredLayout {
  [self registerLayoutFixtureTemplates];
  ControllerTestHarness *controller = [self freshController];
  [controller disableTemplateLayout];

  NSError *error = nil;
  BOOL rendered = [controller renderTemplate:@"pages/show" context:@{} error:&error];

  XCTAssertTrue(rendered);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"body", [self responseBodyText:controller.context.response]);
}

- (void)testRenderTemplateWithoutLayoutBypassesTemplatePreference {
  [self registerLayoutFixtureTemplates];
  ControllerTestHarness *controller = [self freshController];
  [controller useTemplateLayout:@"layouts/alternate"];

  NSError *error = nil;
  BOOL rendered = [controller renderTemplateWithoutLayout:@"pages/show" context:@{} error:&error];

  XCTAssertTrue(rendered);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"body", [self responseBodyText:controller.context.response]);
}

- (void)testClearTemplateLayoutPreferenceRestoresRegisteredLayout {
  [self registerLayoutFixtureTemplates];
  ControllerTestHarness *controller = [self freshController];
  [controller useTemplateLayout:@"layouts/alternate"];
  [controller clearTemplateLayoutPreference];

  NSError *error = nil;
  BOOL rendered = [controller renderTemplate:@"pages/show" context:@{} error:&error];

  XCTAssertTrue(rendered);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"<main>body</main>", [self responseBodyText:controller.context.response]);
}

- (void)testTemplateContextOmitsInternalStashKeys {
  ControllerTestHarness *controller = [self freshController];
  [controller stashValues:@{
    @"title" : @"Welcome",
    @"user" : @"Peggy",
    @"request_id" : @"req-123",
    ALNContextEOCStrictLocalsStashKey : @(YES),
  }];

  NSDictionary *context = [controller templateContext];

  XCTAssertEqualObjects(@"Welcome", context[@"title"]);
  XCTAssertEqualObjects(@"Peggy", context[@"user"]);
  XCTAssertNil(context[@"request_id"]);
  XCTAssertNil(context[ALNContextEOCStrictLocalsStashKey]);
}

@end
