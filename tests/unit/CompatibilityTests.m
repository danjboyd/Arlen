#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "MOApplication.h"
#import "MOContext.h"
#import "MOController.h"
#import "MOJOEOCRuntime.h"
#import "MORequest.h"
#import "MOResponse.h"

static NSString *LegacyTemplateRender(id ctx, NSError **error) {
  (void)error;
  return [NSString stringWithFormat:@"legacy-%@", ctx ?: @"none"];
}

@interface LegacyCompatController : MOController
@end

@implementation LegacyCompatController

- (id)show:(MOContext *)ctx {
  (void)ctx;
  return @{ @"legacy" : @(YES) };
}

@end

@interface CompatibilityTests : XCTestCase
@end

@implementation CompatibilityTests

- (void)setUp {
  [super setUp];
  MOJOEOCClearTemplateRegistry();
}

- (void)tearDown {
  MOJOEOCClearTemplateRegistry();
  [super tearDown];
}

- (NSDictionary *)baseConfig {
  return @{
    @"environment" : @"test",
    @"logFormat" : @"text",
    @"requestLimits" : @{
      @"maxRequestLineBytes" : @(4096),
      @"maxHeaderBytes" : @(32768),
      @"maxBodyBytes" : @(1048576),
    },
    @"trustedProxy" : @(NO),
    @"performanceLogging" : @(YES),
    @"serveStatic" : @(NO),
  };
}

- (void)testLegacyClassPrefixesRouteAndJSONResponse {
  MOApplication *app = [[MOApplication alloc] initWithConfig:[self baseConfig]];
  XCTAssertNotNil(app);

  [app registerRouteMethod:@"GET"
                      path:@"/legacy"
                      name:@"legacy_show"
           controllerClass:[LegacyCompatController class]
                    action:@"show"];

  NSData *raw = [@"GET /legacy HTTP/1.1\r\nHost: localhost\r\n\r\n"
      dataUsingEncoding:NSUTF8StringEncoding];
  NSError *requestError = nil;
  MORequest *request = [MORequest requestFromRawData:raw error:&requestError];
  XCTAssertNil(requestError);
  XCTAssertNotNil(request);

  MOResponse *response = [app dispatchRequest:request];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  XCTAssertEqualObjects(@"application/json; charset=utf-8", [response headerForName:@"Content-Type"]);

  NSError *jsonError = nil;
  NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:response.bodyData
                                                          options:0
                                                            error:&jsonError];
  XCTAssertNil(jsonError);
  XCTAssertEqualObjects(@(YES), payload[@"legacy"]);
}

- (void)testLegacyEOCSymbolsRenderTemplate {
  MOJOEOCRegisterTemplate(@"legacy/template.html.eoc", &LegacyTemplateRender);

  NSError *renderError = nil;
  NSString *rendered = MOJOEOCRenderTemplate(@"legacy/template.html.eoc", @"ok", &renderError);
  XCTAssertNil(renderError);
  XCTAssertEqualObjects(@"legacy-ok", rendered);

  NSMutableString *out = [NSMutableString stringWithString:@"["];
  NSError *includeError = nil;
  BOOL included = MOJOEOCInclude(out, @"ok", @"legacy/template.html.eoc", &includeError);
  XCTAssertTrue(included);
  XCTAssertNil(includeError);
  XCTAssertEqualObjects(@"[legacy-ok", out);
}

@end
