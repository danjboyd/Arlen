#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNJobsModule.h"

@interface Phase14AAlphaJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase14AAlphaJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase14a.alpha";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Alpha Job",
    @"queue" : @"default",
    @"maxAttempts" : @4,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([payload[@"message"] isKindOfClass:[NSString class]] &&
      [((NSString *)payload[@"message"]) length] > 0) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"Phase14A"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : @"message is required" }];
  }
  return NO;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)payload;
  (void)context;
  (void)error;
  return YES;
}

@end

@interface Phase14ABetaJob : NSObject <ALNJobsJobDefinition>
@end

@implementation Phase14ABetaJob

- (NSString *)jobsModuleJobIdentifier {
  return @"phase14a.beta";
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Beta Job",
    @"queue" : @"default",
    @"maxAttempts" : @2,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  (void)payload;
  (void)error;
  return YES;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  (void)payload;
  (void)context;
  (void)error;
  return YES;
}

@end

@interface Phase14AJobProvider : NSObject <ALNJobsJobProvider>
@end

@implementation Phase14AJobProvider

- (NSArray<id<ALNJobsJobDefinition>> *)jobsModuleJobDefinitionsForRuntime:(ALNJobsModuleRuntime *)runtime
                                                                    error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[Phase14ABetaJob alloc] init], [[Phase14AAlphaJob alloc] init] ];
}

@end

@interface Phase14ATests : XCTestCase
@end

@implementation Phase14ATests

- (ALNApplication *)applicationWithConfig:(NSDictionary *)extraConfig {
  NSMutableDictionary *config = [NSMutableDictionary dictionaryWithDictionary:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"csrf" : @{
      @"enabled" : @NO,
    },
    @"jobsModule" : @{
      @"providers" : @{
        @"classes" : @[ @"Phase14AJobProvider" ],
      },
    },
  }];
  [config addEntriesFromDictionary:extraConfig ?: @{}];
  return [[ALNApplication alloc] initWithConfig:config];
}

- (void)testJobRegistrationOrderAndConfigSummaryAreDeterministic {
  ALNApplication *app = [self applicationWithConfig:nil];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
  NSDictionary *summary = [runtime resolvedConfigSummary];
  NSArray<NSDictionary *> *definitions = [runtime registeredJobDefinitions];

  XCTAssertEqualObjects(@"/jobs", summary[@"prefix"]);
  XCTAssertEqualObjects(@"/jobs/api", summary[@"apiPrefix"]);
  XCTAssertEqualObjects(@2, summary[@"jobCount"]);
  XCTAssertEqualObjects(@"phase14a.alpha", definitions[0][@"identifier"]);
  XCTAssertEqualObjects(@"phase14a.beta", definitions[1][@"identifier"]);
  XCTAssertEqualObjects(@"Alpha Job", definitions[0][@"title"]);
  XCTAssertEqualObjects(@4, definitions[0][@"maxAttempts"]);
}

- (void)testManagedEnqueueValidatesPayloadBeforeQueueing {
  ALNApplication *app = [self applicationWithConfig:nil];
  NSError *error = nil;
  XCTAssertTrue([[[ALNJobsModule alloc] init] registerWithApplication:app error:&error]);
  XCTAssertNil(error);

  ALNJobsModuleRuntime *runtime = [ALNJobsModuleRuntime sharedRuntime];
  NSString *invalidJobID = [runtime enqueueJobIdentifier:@"phase14a.alpha" payload:@{} options:nil error:&error];
  XCTAssertNil(invalidJobID);
  XCTAssertNotNil(error);

  error = nil;
  NSString *validJobID =
      [runtime enqueueJobIdentifier:@"phase14a.alpha"
                            payload:@{ @"message" : @"ok" }
                            options:@{ @"idempotencyKey" : @"phase14a:alpha:1" }
                              error:&error];
  XCTAssertNotNil(validJobID);
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)1, [[runtime pendingJobs] count]);
}

@end
