#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

@interface Phase3FHelpersController : ALNController
@end

@implementation Phase3FHelpersController

- (id)typed:(ALNContext *)ctx {
  (void)ctx;
  NSNumber *page = [self queryIntegerForName:@"page"];
  NSNumber *enabled = [self queryBooleanForName:@"enabled"];
  NSNumber *limit = [self headerIntegerForName:@"x-limit"];
  NSNumber *debug = [self headerBooleanForName:@"x-debug"];
  return @{
    @"page" : page ?: [NSNull null],
    @"enabled" : enabled ?: [NSNull null],
    @"limit" : limit ?: [NSNull null],
    @"debug" : debug ?: [NSNull null],
  };
}

- (id)etag:(ALNContext *)ctx {
  (void)ctx;
  if ([self applyETagAndReturnNotModifiedIfMatch:@"phase3f-v1"]) {
    return nil;
  }
  return @{
    @"fresh" : @(YES),
  };
}

- (id)envelope:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  BOOL rendered = [self renderJSONEnvelopeWithData:@{
                    @"ok" : @(YES),
                  }
                                             meta:@{
                                               @"source" : @"controller_helper",
                                             }
                                            error:&error];
  if (!rendered || error != nil) {
    [self setStatus:500];
    [self renderText:@"envelope render failed\n"];
  }
  return nil;
}

- (id)implicitSuccess:(ALNContext *)ctx {
  (void)ctx;
  return @{
    @"raw" : @"value",
  };
}

- (id)implicitError:(ALNContext *)ctx {
  (void)ctx;
  [self setStatus:422];
  return @{
    @"code" : @"bad_input",
  };
}

@end

@interface Phase3FTests : XCTestCase
@end

@implementation Phase3FTests

- (ALNApplication *)buildAppWithResponseEnvelopeMiddleware:(BOOL)enabled {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"apiHelpers" : @{
      @"responseEnvelopeEnabled" : @(enabled),
    },
  }];

  [app registerRouteMethod:@"GET"
                      path:@"/helpers/typed"
                      name:@"phase3f_typed"
           controllerClass:[Phase3FHelpersController class]
                    action:@"typed"];
  [app registerRouteMethod:@"GET"
                      path:@"/helpers/etag"
                      name:@"phase3f_etag"
           controllerClass:[Phase3FHelpersController class]
                    action:@"etag"];
  [app registerRouteMethod:@"GET"
                      path:@"/helpers/envelope"
                      name:@"phase3f_envelope_helper"
           controllerClass:[Phase3FHelpersController class]
                    action:@"envelope"];
  [app registerRouteMethod:@"GET"
                      path:@"/helpers/implicit-success"
                      name:@"phase3f_implicit_success"
           controllerClass:[Phase3FHelpersController class]
                    action:@"implicitSuccess"];
  [app registerRouteMethod:@"GET"
                      path:@"/helpers/implicit-error"
                      name:@"phase3f_implicit_error"
           controllerClass:[Phase3FHelpersController class]
                    action:@"implicitError"];
  return app;
}

- (ALNRequest *)requestForPath:(NSString *)path
                   queryString:(NSString *)queryString
                       headers:(NSDictionary *)headers {
  return [[ALNRequest alloc] initWithMethod:@"GET"
                                      path:path ?: @"/"
                               queryString:queryString ?: @""
                                   headers:headers ?: @{}
                                      body:[NSData data]];
}

- (NSDictionary *)jsonFromResponse:(ALNResponse *)response {
  NSError *error = nil;
  id parsed = [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:&error];
  if (error != nil || ![parsed isKindOfClass:[NSDictionary class]]) {
    NSString *body = [[NSString alloc] initWithData:response.bodyData
                                           encoding:NSUTF8StringEncoding] ?: @"";
    XCTFail(@"expected json dictionary error=%@ body=%@",
            error.localizedDescription ?: @"",
            body);
    return @{};
  }
  return parsed;
}

- (void)testTypedQueryAndHeaderParsingHelpersCoverPositiveAndRejectionPaths {
  ALNApplication *app = [self buildAppWithResponseEnvelopeMiddleware:NO];

  ALNResponse *okResponse = [app dispatchRequest:[self requestForPath:@"/helpers/typed"
                                                          queryString:@"page=7&enabled=on"
                                                              headers:@{
                                                                @"x-limit" : @"15",
                                                                @"x-debug" : @"false",
                                                              }]];
  XCTAssertEqual((NSInteger)200, okResponse.statusCode);
  NSDictionary *okJSON = [self jsonFromResponse:okResponse];
  XCTAssertEqualObjects(@7, okJSON[@"page"]);
  XCTAssertEqualObjects(@(YES), okJSON[@"enabled"]);
  XCTAssertEqualObjects(@15, okJSON[@"limit"]);
  XCTAssertEqualObjects(@(NO), okJSON[@"debug"]);

  ALNResponse *invalidResponse = [app dispatchRequest:[self requestForPath:@"/helpers/typed"
                                                               queryString:@"page=abc&enabled=maybe"
                                                                   headers:@{
                                                                     @"x-limit" : @"NaN",
                                                                     @"x-debug" : @"perhaps",
                                                                   }]];
  XCTAssertEqual((NSInteger)200, invalidResponse.statusCode);
  NSDictionary *invalidJSON = [self jsonFromResponse:invalidResponse];
  XCTAssertEqualObjects([NSNull null], invalidJSON[@"page"]);
  XCTAssertEqualObjects([NSNull null], invalidJSON[@"enabled"]);
  XCTAssertEqualObjects([NSNull null], invalidJSON[@"limit"]);
  XCTAssertEqualObjects([NSNull null], invalidJSON[@"debug"]);
}

- (void)testETagHelperReturns304ForMatchingIfNoneMatch {
  ALNApplication *app = [self buildAppWithResponseEnvelopeMiddleware:NO];

  ALNResponse *first = [app dispatchRequest:[self requestForPath:@"/helpers/etag"
                                                     queryString:@""
                                                         headers:@{}]];
  XCTAssertEqual((NSInteger)200, first.statusCode);
  XCTAssertEqualObjects(@"\"phase3f-v1\"", [first headerForName:@"ETag"]);
  NSDictionary *firstJSON = [self jsonFromResponse:first];
  XCTAssertEqualObjects(@(YES), firstJSON[@"fresh"]);

  ALNResponse *matched = [app dispatchRequest:[self requestForPath:@"/helpers/etag"
                                                       queryString:@""
                                                           headers:@{
                                                             @"if-none-match" : @"W/\"phase3f-v1\"",
                                                           }]];
  XCTAssertEqual((NSInteger)304, matched.statusCode);
  XCTAssertEqual((NSUInteger)0, [matched.bodyData length]);
  XCTAssertEqualObjects(@"\"phase3f-v1\"", [matched headerForName:@"ETag"]);

  ALNResponse *nonMatch = [app dispatchRequest:[self requestForPath:@"/helpers/etag"
                                                        queryString:@""
                                                            headers:@{
                                                              @"if-none-match" : @"\"phase3f-v2\"",
                                                            }]];
  XCTAssertEqual((NSInteger)200, nonMatch.statusCode);
  NSDictionary *nonMatchJSON = [self jsonFromResponse:nonMatch];
  XCTAssertEqualObjects(@(YES), nonMatchJSON[@"fresh"]);
}

- (void)testEnvelopeControllerHelperAddsDataAndRequestIDMeta {
  ALNApplication *app = [self buildAppWithResponseEnvelopeMiddleware:NO];
  ALNResponse *response = [app dispatchRequest:[self requestForPath:@"/helpers/envelope"
                                                        queryString:@""
                                                            headers:@{}]];
  XCTAssertEqual((NSInteger)200, response.statusCode);
  NSDictionary *json = [self jsonFromResponse:response];
  NSDictionary *data = [json[@"data"] isKindOfClass:[NSDictionary class]] ? json[@"data"] : @{};
  NSDictionary *meta = [json[@"meta"] isKindOfClass:[NSDictionary class]] ? json[@"meta"] : @{};
  XCTAssertEqualObjects(@(YES), data[@"ok"]);
  XCTAssertEqualObjects(@"controller_helper", meta[@"source"]);
  XCTAssertTrue([meta[@"request_id"] length] > 0);
}

- (void)testResponseEnvelopeMiddlewareIsOptInForSuccessAndErrorPayloads {
  ALNApplication *disabled = [self buildAppWithResponseEnvelopeMiddleware:NO];
  ALNResponse *disabledSuccess =
      [disabled dispatchRequest:[self requestForPath:@"/helpers/implicit-success"
                                         queryString:@""
                                             headers:@{}]];
  XCTAssertEqual((NSInteger)200, disabledSuccess.statusCode);
  NSDictionary *disabledSuccessJSON = [self jsonFromResponse:disabledSuccess];
  XCTAssertEqualObjects(@"value", disabledSuccessJSON[@"raw"]);
  XCTAssertNil(disabledSuccessJSON[@"data"]);
  XCTAssertNil(disabledSuccessJSON[@"meta"]);

  ALNResponse *disabledError =
      [disabled dispatchRequest:[self requestForPath:@"/helpers/implicit-error"
                                         queryString:@""
                                             headers:@{}]];
  XCTAssertEqual((NSInteger)422, disabledError.statusCode);
  NSDictionary *disabledErrorJSON = [self jsonFromResponse:disabledError];
  XCTAssertEqualObjects(@"bad_input", disabledErrorJSON[@"code"]);
  XCTAssertNil(disabledErrorJSON[@"error"]);

  ALNApplication *enabled = [self buildAppWithResponseEnvelopeMiddleware:YES];
  ALNResponse *enabledSuccess =
      [enabled dispatchRequest:[self requestForPath:@"/helpers/implicit-success"
                                        queryString:@""
                                            headers:@{}]];
  XCTAssertEqual((NSInteger)200, enabledSuccess.statusCode);
  NSDictionary *enabledSuccessJSON = [self jsonFromResponse:enabledSuccess];
  NSDictionary *successData = [enabledSuccessJSON[@"data"] isKindOfClass:[NSDictionary class]]
                                  ? enabledSuccessJSON[@"data"]
                                  : @{};
  NSDictionary *successMeta = [enabledSuccessJSON[@"meta"] isKindOfClass:[NSDictionary class]]
                                  ? enabledSuccessJSON[@"meta"]
                                  : @{};
  XCTAssertEqualObjects(@"value", successData[@"raw"]);
  XCTAssertTrue([successMeta[@"request_id"] length] > 0);

  ALNResponse *enabledError =
      [enabled dispatchRequest:[self requestForPath:@"/helpers/implicit-error"
                                        queryString:@""
                                            headers:@{}]];
  XCTAssertEqual((NSInteger)422, enabledError.statusCode);
  NSDictionary *enabledErrorJSON = [self jsonFromResponse:enabledError];
  NSDictionary *errorObject = [enabledErrorJSON[@"error"] isKindOfClass:[NSDictionary class]]
                                  ? enabledErrorJSON[@"error"]
                                  : @{};
  NSDictionary *errorMeta = [enabledErrorJSON[@"meta"] isKindOfClass:[NSDictionary class]]
                                ? enabledErrorJSON[@"meta"]
                                : @{};
  XCTAssertEqualObjects(@"bad_input", errorObject[@"code"]);
  XCTAssertNil(enabledErrorJSON[@"data"]);
  XCTAssertTrue([errorMeta[@"request_id"] length] > 0);
}

- (void)testStaticMountRegistrationContractNormalizesAndRejectsDuplicates {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"text",
    @"staticMounts" : @[
      @{
        @"prefix" : @"/assets",
        @"directory" : @"public",
        @"allowExtensions" : @[ @"TXT", @".json", @"txt" ],
      },
      @{
        @"prefix" : @"/assets",
        @"directory" : @"ignored",
        @"allowExtensions" : @[ @"txt" ],
      },
      @{
        @"prefix" : @"",
        @"directory" : @"ignored",
      },
    ],
  }];

  NSArray *configured = app.staticMounts;
  XCTAssertEqual((NSUInteger)1, [configured count]);
  NSDictionary *entry = [configured firstObject];
  XCTAssertEqualObjects(@"/assets", entry[@"prefix"]);
  XCTAssertEqualObjects(@"public", entry[@"directory"]);
  XCTAssertEqualObjects((@[ @"txt", @"json" ]), entry[@"allowExtensions"]);

  XCTAssertFalse([app mountStaticDirectory:@""
                                  atPrefix:@"/media"
                           allowExtensions:@[ @"txt" ]]);
  XCTAssertFalse([app mountStaticDirectory:@"public"
                                  atPrefix:@"/assets"
                           allowExtensions:@[ @"txt" ]]);
}

@end
