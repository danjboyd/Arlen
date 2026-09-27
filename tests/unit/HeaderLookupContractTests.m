#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

// GitHub issue 80: header lookup never returns nil at any layer.
@interface HeaderLookupContractTests : XCTestCase
@end

@implementation HeaderLookupContractTests

- (ALNRequest *)request {
  return [[ALNRequest alloc] initWithMethod:@"GET"
                                       path:@"/"
                                queryString:@""
                                    headers:@{ @"x-present" : @"value", @"x-empty" : @"" }
                                       body:[NSData data]];
}

- (ALNContext *)contextForRequest:(ALNRequest *)request {
  return [[ALNContext alloc] initWithRequest:request
                                    response:[ALNResponse new]
                                      params:@{}
                                       stash:[NSMutableDictionary dictionary]
                                      logger:[[ALNLogger alloc] initWithFormat:@"text"]
                                   perfTrace:[[ALNPerfTrace alloc] initWithEnabled:NO]
                                   routeName:@"r"
                              controllerName:@"C"
                                  actionName:@"a"];
}

- (void)assertContractForLookup:(NSString *(^)(NSString *name))lookup label:(NSString *)label {
  XCTAssertEqualObjects(@"value", lookup(@"x-present"), @"%@", label);
  XCTAssertEqualObjects(@"value", lookup(@"X-Present"), @"%@ case-insensitive", label);
  XCTAssertEqualObjects(@"", lookup(@"x-empty"), @"%@ present-empty", label);
  XCTAssertEqualObjects(@"", lookup(@"x-absent"), @"%@ absent", label);
  XCTAssertEqualObjects(@"", lookup(@""), @"%@ empty name", label);
  XCTAssertNotNil(lookup(@"x-absent"), @"%@", label);
}

- (void)testRequestContextAndControllerShareTheNonnullContract {
  ALNRequest *request = [self request];
  ALNContext *context = [self contextForRequest:request];
  ALNController *controller = [[ALNController alloc] init];
  controller.context = context;
  [self assertContractForLookup:^NSString *(NSString *name) { return [request headerValueForName:name]; }
                          label:@"request"];
  [self assertContractForLookup:^NSString *(NSString *name) { return [context headerValueForName:name]; }
                          label:@"context"];
  [self assertContractForLookup:^NSString *(NSString *name) { return [controller headerValueForName:name]; }
                          label:@"controller"];
}

@end
