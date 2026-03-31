#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "../shared/ALNDataverseTestSupport.h"
#import "../shared/ALNTestSupport.h"
#import "../shared/ALNWebTestSupport.h"

@interface ALNDataverseRuntimeHarnessController : ALNController
@end

@implementation ALNDataverseRuntimeHarnessController

- (id)status:(ALNContext *)ctx {
  NSError *defaultError = nil;
  NSError *salesError = nil;
  ALNDataverseClient *defaultClient = [ctx dataverseClientNamed:nil error:&defaultError];
  ALNDataverseClient *salesClient = [self dataverseClientNamed:@"sales" error:&salesError];

  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"targets"] = [self dataverseTargetNames] ?: @[];
  if (defaultClient != nil) {
    payload[@"default_target"] = defaultClient.target.targetName ?: @"";
  }
  if (salesClient != nil) {
    payload[@"sales_target"] = salesClient.target.targetName ?: @"";
  }
  if (defaultError != nil) {
    payload[@"default_error"] = defaultError.localizedDescription ?: @"";
  }
  if (salesError != nil) {
    payload[@"sales_error"] = salesError.localizedDescription ?: @"";
  }
  [self renderJSON:payload error:NULL];
  return self.context.response;
}

@end

@interface DataverseRuntimeTests : ALNDataverseTestCase
@end

@implementation DataverseRuntimeTests

- (void)testApplicationResolvesDataverseClientsFromConfigAndEnvironment {
  NSArray<NSString *> *environmentNames = @[
    @"ARLEN_DATAVERSE_URL_SUPPORT",
    @"ARLEN_DATAVERSE_TENANT_ID_SUPPORT",
    @"ARLEN_DATAVERSE_CLIENT_ID_SUPPORT",
    @"ARLEN_DATAVERSE_CLIENT_SECRET_SUPPORT",
    @"ARLEN_DATAVERSE_PAGE_SIZE_SUPPORT",
    @"ARLEN_DATAVERSE_TIMEOUT_SUPPORT",
  ];
  NSDictionary<NSString *, NSString *> *snapshot = [self snapshotEnvironmentForNames:environmentNames];

  @try {
    [self setEnvironmentValue:@"https://support.crm.dynamics.com"
                      forName:@"ARLEN_DATAVERSE_URL_SUPPORT"];
    [self setEnvironmentValue:@"support-tenant" forName:@"ARLEN_DATAVERSE_TENANT_ID_SUPPORT"];
    [self setEnvironmentValue:@"support-client" forName:@"ARLEN_DATAVERSE_CLIENT_ID_SUPPORT"];
    [self setEnvironmentValue:@"support-secret" forName:@"ARLEN_DATAVERSE_CLIENT_SECRET_SUPPORT"];
    [self setEnvironmentValue:@"125" forName:@"ARLEN_DATAVERSE_PAGE_SIZE_SUPPORT"];
    [self setEnvironmentValue:@"30" forName:@"ARLEN_DATAVERSE_TIMEOUT_SUPPORT"];

    ALNApplication *application = [[ALNApplication alloc] initWithConfig:[self applicationConfig]];
    NSArray<NSString *> *targets = [application dataverseTargetNames];
    XCTAssertTrue([targets containsObject:@"default"]);
    XCTAssertTrue([targets containsObject:@"sales"]);
    XCTAssertTrue([targets containsObject:@"support"]);

    NSError *error = nil;
    ALNDataverseClient *defaultClient = [application dataverseClient];
    XCTAssertNotNil(defaultClient);
    ALNDataverseClient *cachedDefault = [application dataverseClientNamed:@"default" error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(defaultClient, cachedDefault);
    XCTAssertEqualObjects(defaultClient.target.targetName, @"default");
    XCTAssertEqualObjects(defaultClient.target.serviceRootURLString,
                          @"https://example.crm.dynamics.com/api/data/v9.2");

    ALNDataverseClient *salesClient = [application dataverseClientNamed:@"sales" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(salesClient.target.targetName, @"sales");
    XCTAssertEqualObjects(salesClient.target.serviceRootURLString,
                          @"https://sales.crm.dynamics.com/api/data/v9.2");
    XCTAssertEqual((NSUInteger)100, salesClient.target.pageSize);

    ALNDataverseClient *supportClient = [application dataverseClientNamed:@"support" error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(supportClient.target.targetName, @"support");
    XCTAssertEqualObjects(supportClient.target.serviceRootURLString,
                          @"https://support.crm.dynamics.com/api/data/v9.2");
    XCTAssertEqualObjects(supportClient.target.environmentURLString, @"https://support.crm.dynamics.com");
    XCTAssertEqual((NSUInteger)125, supportClient.target.pageSize);
    XCTAssertEqualWithAccuracy(30.0, supportClient.target.timeoutInterval, 0.001);
  } @finally {
    [self restoreEnvironmentSnapshot:snapshot names:environmentNames];
  }
}

- (void)testApplicationRejectsMissingNamedDataverseTarget {
  ALNApplication *application = [[ALNApplication alloc] initWithConfig:[self applicationConfig]];
  NSError *error = nil;
  ALNDataverseClient *client = [application dataverseClientNamed:@"support" error:&error];
  XCTAssertNil(client);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(error.domain, @"Arlen.Application.Error");
  XCTAssertEqual((NSInteger)305, error.code);
}

- (void)testControllerAndContextHelpersResolveDataverseClientsDuringDispatch {
  ALNWebTestHarness *harness =
      [ALNWebTestHarness harnessWithConfig:[self applicationConfig]
                               routeMethod:@"GET"
                                      path:@"/dataverse"
                                 routeName:@"dataverse.status"
                           controllerClass:[ALNDataverseRuntimeHarnessController class]
                                    action:@"status"
                               middlewares:nil];

  ALNResponse *response = [harness dispatchMethod:@"GET" path:@"/dataverse"];
  ALNAssertResponseStatus(response, 200);

  NSError *error = nil;
  NSDictionary *payload = ALNTestJSONDictionaryFromResponse(response, &error);
  XCTAssertNil(error);
  XCTAssertEqualObjects(payload[@"default_target"], @"default");
  XCTAssertEqualObjects(payload[@"sales_target"], @"sales");
  NSArray *targets = [payload[@"targets"] isKindOfClass:[NSArray class]] ? payload[@"targets"] : @[];
  XCTAssertTrue([targets containsObject:@"default"]);
  XCTAssertTrue([targets containsObject:@"sales"]);
}

@end
