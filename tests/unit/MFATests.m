#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNRecoveryCodes.h"
#import "ALNTOTP.h"

@interface MFATests : XCTestCase
@end

@implementation MFATests

- (void)testTOTPMatchesRFC6238SHA1VectorAt59Seconds {
  NSString *secret = @"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
  NSDate *date = [NSDate dateWithTimeIntervalSince1970:59];
  NSError *error = nil;
  NSString *code = [ALNTOTP codeForSecret:secret
                                   atDate:date
                                   digits:8
                                   period:30
                                    error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"94287082", code);
}

- (void)testTOTPVerificationAllowsAdjacentWindowButRejectsOutsideSkew {
  NSString *secret = @"GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
  NSDate *issueDate = [NSDate dateWithTimeIntervalSince1970:1111111109];
  NSError *error = nil;
  NSString *code = [ALNTOTP codeForSecret:secret
                                   atDate:issueDate
                                   digits:8
                                   period:30
                                    error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"07081804", code);

  BOOL accepted = [ALNTOTP verifyCode:code
                               secret:secret
                               atDate:[NSDate dateWithTimeIntervalSince1970:1111111139]
                               digits:8
                               period:30
                 allowedPastIntervals:1
               allowedFutureIntervals:0
                                error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(accepted);

  BOOL rejected = [ALNTOTP verifyCode:code
                               secret:secret
                               atDate:[NSDate dateWithTimeIntervalSince1970:1111111169]
                               digits:8
                               period:30
                 allowedPastIntervals:1
               allowedFutureIntervals:0
                                error:&error];
  XCTAssertNil(error);
  XCTAssertFalse(rejected);
}

- (void)testProvisioningURIIncludesIssuerAccountAndDefaults {
  NSError *error = nil;
  NSString *uri = [ALNTOTP provisioningURIForSecret:@"JBSWY3DPEHPK3PXP"
                                        accountName:@"user@example.com"
                                             issuer:@"Arlen Demo"
                                              error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([uri hasPrefix:@"otpauth://totp/"]);
  XCTAssertTrue([uri containsString:@"secret=JBSWY3DPEHPK3PXP"]);
  XCTAssertTrue([uri containsString:@"issuer=Arlen%20Demo"]);
  XCTAssertTrue([uri containsString:@"digits=6"]);
  XCTAssertTrue([uri containsString:@"period=30"]);
}

- (void)testRecoveryCodesHashAndConsumeSingleUse {
  NSError *error = nil;
  NSArray *codes = [ALNRecoveryCodes generateCodesWithCount:3 segmentLength:4 error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)3, [codes count]);

  NSArray *hashes = [ALNRecoveryCodes hashCodes:codes error:&error];
  XCTAssertNil(error);
  XCTAssertEqual((NSUInteger)3, [hashes count]);
  XCTAssertTrue([hashes[0] hasPrefix:@"$argon2id$"]);

  NSArray *remaining = nil;
  BOOL consumed = [ALNRecoveryCodes consumeCode:codes[0]
                             againstEncodedHashes:hashes
                           remainingEncodedHashes:&remaining
                                            error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(consumed);
  XCTAssertEqual((NSUInteger)2, [remaining count]);

  BOOL consumedAgain = [ALNRecoveryCodes consumeCode:codes[0]
                                  againstEncodedHashes:remaining
                                remainingEncodedHashes:&remaining
                                                 error:&error];
  XCTAssertNil(error);
  XCTAssertFalse(consumedAgain);
  XCTAssertEqual((NSUInteger)2, [remaining count]);
}

- (void)testRecoveryCodeRegenerationInvalidatesPriorSet {
  NSError *error = nil;
  NSArray *firstCodes = [ALNRecoveryCodes generateCodesWithCount:2 error:&error];
  XCTAssertNil(error);
  NSArray *firstHashes = [ALNRecoveryCodes hashCodes:firstCodes error:&error];
  XCTAssertNil(error);

  NSArray *secondCodes = [ALNRecoveryCodes generateCodesWithCount:2 error:&error];
  XCTAssertNil(error);
  NSArray *secondHashes = [ALNRecoveryCodes hashCodes:secondCodes error:&error];
  XCTAssertNil(error);

  BOOL firstCodeMatchesSecondSet =
      [ALNRecoveryCodes verifyCode:firstCodes[0] againstEncodedHash:secondHashes[0] error:&error];
  XCTAssertNil(error);
  XCTAssertFalse(firstCodeMatchesSecondSet);

  BOOL firstCodeStillMatchesFirstSet =
      [ALNRecoveryCodes verifyCode:firstCodes[0] againstEncodedHash:firstHashes[0] error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(firstCodeStillMatchesFirstSet);
}

@end
