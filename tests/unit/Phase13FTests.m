#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNAuthModule.h"

static NSUInteger gPhase13FRegistrationCalls = 0;
static NSUInteger gPhase13FProviderMappingCalls = 0;

@interface Phase13FRegistrationPolicyHook : NSObject <ALNAuthModuleRegistrationPolicy>
@end

@implementation Phase13FRegistrationPolicyHook

- (BOOL)authModuleShouldAllowRegistration:(NSDictionary *)registrationRequest
                                    error:(NSError **)error {
  gPhase13FRegistrationCalls += 1;
  NSString *email = [registrationRequest[@"email"] isKindOfClass:[NSString class]]
                        ? registrationRequest[@"email"]
                        : @"";
  if ([email hasPrefix:@"blocked@"]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"Phase13F.Registration"
                                   code:1
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"registration policy denied this address",
                               }];
    }
    return NO;
  }
  return YES;
}

@end

@interface Phase13FProviderMappingHook : NSObject <ALNAuthModuleProviderMappingHook>
@end

@implementation Phase13FProviderMappingHook

- (NSDictionary *)authModuleProviderMappingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                                         defaultDescriptor:(NSDictionary *)defaultDescriptor {
  gPhase13FProviderMappingCalls += 1;
  NSMutableDictionary *descriptor = [NSMutableDictionary dictionaryWithDictionary:defaultDescriptor ?: @{}];
  descriptor[@"create_user"] = @NO;
  descriptor[@"subject"] = [NSString stringWithFormat:@"mapped:%@",
                                                      normalizedIdentity[@"provider_subject"] ?: @"unknown"];
  return descriptor;
}

@end

@interface Phase13FTests : XCTestCase
@end

@implementation Phase13FTests

- (void)setUp {
  [super setUp];
  gPhase13FRegistrationCalls = 0;
  gPhase13FProviderMappingCalls = 0;
  NSError *error = nil;
  XCTAssertTrue([[ALNAuthModuleRuntime sharedRuntime] configureHooksWithModuleConfig:@{} error:&error]);
  XCTAssertNil(error);
}

- (void)testRegistrationPolicyHookIsDeterministic {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *config = @{
    @"hooks" : @{
      @"registrationPolicyClass" : @"Phase13FRegistrationPolicyHook",
    },
  };
  XCTAssertTrue([runtime configureHooksWithModuleConfig:config error:&error]);
  XCTAssertNil(error);

  XCTAssertTrue([runtime registrationAllowedForRequest:@{ @"email" : @"allowed@example.test" } error:&error]);
  XCTAssertNil(error);

  NSError *blockedError = nil;
  XCTAssertFalse([runtime registrationAllowedForRequest:@{ @"email" : @"blocked@example.test" }
                                                  error:&blockedError]);
  XCTAssertNotNil(blockedError);
  XCTAssertEqualObjects(@"registration policy denied this address", blockedError.localizedDescription);
  XCTAssertEqual((NSUInteger)2, gPhase13FRegistrationCalls);
}

- (void)testProviderMappingHookIsDeterministic {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  NSError *error = nil;
  NSDictionary *config = @{
    @"hooks" : @{
      @"providerMappingClass" : @"Phase13FProviderMappingHook",
    },
  };
  XCTAssertTrue([runtime configureHooksWithModuleConfig:config error:&error]);
  XCTAssertNil(error);

  NSDictionary *resolved = [runtime providerMappingDescriptorForNormalizedIdentity:@{
                               @"provider_subject" : @"stub-123",
                               @"email" : @"mapped@example.test",
                             }
                                                            defaultDescriptor:@{
                                                              @"create_user" : @YES,
                                                              @"subject" : @"user:default",
                                                            }];
  XCTAssertEqualObjects(@NO, resolved[@"create_user"]);
  XCTAssertEqualObjects(@"mapped:stub-123", resolved[@"subject"]);
  XCTAssertEqual((NSUInteger)1, gPhase13FProviderMappingCalls);
}

@end
