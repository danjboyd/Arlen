#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNAuthModule.h"
#import "ALNPasswordHash.h"

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

// Stands in for ALNPg so local-password login runs without a database.
@interface Phase13FFakeAuthDatabase : NSObject
@property(nonatomic, copy) NSArray<NSDictionary *> *rows;
@end

@implementation Phase13FFakeAuthDatabase

- (NSArray *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  (void)sql;
  (void)parameters;
  if (error != NULL) {
    *error = nil;
  }
  return self.rows ?: @[];
}

@end

@interface ALNAuthModuleRuntime (Phase13FLoginTiming)
- (nullable NSDictionary *)authenticateLocalEmail:(NSString *)email
                                         password:(NSString *)password
                                            error:(NSError **)error;
- (NSUInteger)dummyPasswordVerificationCount;
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

- (void)testUnknownEmailLoginStillVerifiesADummyPasswordHash {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime sharedRuntime];
  id originalDatabase = [runtime valueForKey:@"database"];
  Phase13FFakeAuthDatabase *database = [[Phase13FFakeAuthDatabase alloc] init];
  [runtime setValue:database forKey:@"database"];
  @try {
    NSError *error = nil;
    NSString *knownHash = [ALNPasswordHash hashPasswordString:@"correct horse battery staple"
                                                      options:[ALNPasswordHash defaultArgon2idOptions]
                                                        error:&error];
    XCTAssertNotNil(knownHash, @"%@", error);

    database.rows = @[];
    NSUInteger before = [runtime dummyPasswordVerificationCount];
    error = nil;
    XCTAssertNil([runtime authenticateLocalEmail:@"nobody@example.test" password:@"guess" error:&error]);
    XCTAssertEqual(ALNAuthModuleErrorAuthenticationFailed, error.code);
    XCTAssertEqualObjects(@"Invalid email or password", error.localizedDescription);
    XCTAssertEqual(before + 1U, [runtime dummyPasswordVerificationCount]);

    NSDate *started = [NSDate date];
    XCTAssertNil([runtime authenticateLocalEmail:@"nobody@example.test" password:@"guess" error:NULL]);
    NSTimeInterval unknownElapsed = -[started timeIntervalSinceNow];
    XCTAssertEqual(before + 2U, [runtime dummyPasswordVerificationCount]);

    database.rows = @[ @{
      @"id" : @"1",
      @"subject" : @"user:1",
      @"email" : @"known@example.test",
      @"display_name" : @"Known",
      @"roles_json" : @"[]",
      @"email_verified_at" : @"",
      @"password_hash" : knownHash ?: @"",
    } ];
    started = [NSDate date];
    XCTAssertNil([runtime authenticateLocalEmail:@"known@example.test" password:@"guess" error:NULL]);
    NSTimeInterval knownElapsed = -[started timeIntervalSinceNow];
    XCTAssertEqual(before + 2U, [runtime dummyPasswordVerificationCount]);
    // Both paths run one Argon2 verification; allow generous scheduling noise.
    XCTAssertGreaterThan(unknownElapsed, knownElapsed * 0.25,
                         @"unknown=%f known=%f", unknownElapsed, knownElapsed);

    XCTAssertNotNil([runtime authenticateLocalEmail:@"known@example.test"
                                           password:@"correct horse battery staple"
                                              error:NULL]);
  } @finally {
    [runtime setValue:originalDatabase forKey:@"database"];
  }
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
