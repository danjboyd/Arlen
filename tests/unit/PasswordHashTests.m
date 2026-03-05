#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNPasswordHash.h"

@interface PasswordHashTests : XCTestCase
@end

@implementation PasswordHashTests

- (void)testDefaultArgon2idOptionsMatchFrameworkPolicy {
  ALNArgon2idOptions options = [ALNPasswordHash defaultArgon2idOptions];
  XCTAssertEqual((uint32_t)19456, options.memoryKiB);
  XCTAssertEqual((uint32_t)2, options.iterations);
  XCTAssertEqual((uint32_t)1, options.parallelism);
  XCTAssertEqual((uint32_t)16, options.saltLength);
  XCTAssertEqual((uint32_t)32, options.hashLength);
}

- (void)testHashAndVerifyPasswordStringRoundTrip {
  NSError *error = nil;
  ALNArgon2idOptions options = [ALNPasswordHash defaultArgon2idOptions];
  NSString *encodedHash = [ALNPasswordHash hashPasswordString:@"s3cr3t-passphrase"
                                                     options:options
                                                       error:&error];
  XCTAssertNotNil(encodedHash);
  XCTAssertNil(error);
  XCTAssertTrue([encodedHash hasPrefix:@"$argon2id$v=19$m=19456,t=2,p=1$"]);

  error = nil;
  BOOL verified = [ALNPasswordHash verifyPasswordString:@"s3cr3t-passphrase"
                                      againstEncodedHash:encodedHash
                                                   error:&error];
  XCTAssertTrue(verified);
  XCTAssertNil(error);
}

- (void)testVerifyWrongPasswordReturnsNoWithoutError {
  NSError *error = nil;
  NSString *encodedHash = [ALNPasswordHash hashPasswordString:@"correct-horse"
                                                     options:[ALNPasswordHash defaultArgon2idOptions]
                                                       error:&error];
  XCTAssertNotNil(encodedHash);
  XCTAssertNil(error);

  error = nil;
  BOOL verified = [ALNPasswordHash verifyPasswordString:@"wrong-battery"
                                      againstEncodedHash:encodedHash
                                                   error:&error];
  XCTAssertFalse(verified);
  XCTAssertNil(error);
}

- (void)testHashAndVerifyPasswordDataRoundTrip {
  NSData *passwordData = [@"binary-safe-password" dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  NSString *encodedHash = [ALNPasswordHash hashPasswordData:passwordData
                                                    options:[ALNPasswordHash defaultArgon2idOptions]
                                                      error:&error];
  XCTAssertNotNil(encodedHash);
  XCTAssertNil(error);

  error = nil;
  BOOL verified = [ALNPasswordHash verifyPasswordData:passwordData
                                    againstEncodedHash:encodedHash
                                                 error:&error];
  XCTAssertTrue(verified);
  XCTAssertNil(error);
}

- (void)testEncodedHashNeedsRehashWhenOptionsChange {
  NSError *error = nil;
  NSString *encodedHash = [ALNPasswordHash hashPasswordString:@"rehash-me"
                                                     options:[ALNPasswordHash defaultArgon2idOptions]
                                                       error:&error];
  XCTAssertNotNil(encodedHash);
  XCTAssertNil(error);

  ALNArgon2idOptions upgraded = [ALNPasswordHash defaultArgon2idOptions];
  upgraded.iterations = 3;

  error = nil;
  BOOL needsRehash = [ALNPasswordHash encodedHashNeedsRehash:encodedHash
                                                     options:upgraded
                                                       error:&error];
  XCTAssertTrue(needsRehash);
  XCTAssertNil(error);
}

- (void)testEncodedHashNeedsRehashIsFalseForMatchingOptions {
  NSError *error = nil;
  ALNArgon2idOptions options = [ALNPasswordHash defaultArgon2idOptions];
  NSString *encodedHash = [ALNPasswordHash hashPasswordString:@"stable-policy"
                                                     options:options
                                                       error:&error];
  XCTAssertNotNil(encodedHash);
  XCTAssertNil(error);

  error = nil;
  BOOL needsRehash = [ALNPasswordHash encodedHashNeedsRehash:encodedHash
                                                     options:options
                                                       error:&error];
  XCTAssertFalse(needsRehash);
  XCTAssertNil(error);
}

- (void)testMalformedEncodedHashReturnsStructuredError {
  NSError *error = nil;
  BOOL verified = [ALNPasswordHash verifyPasswordString:@"password"
                                      againstEncodedHash:@"not-a-valid-phc-string"
                                                   error:&error];
  XCTAssertFalse(verified);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNPasswordHashErrorDomain, [error domain]);
  XCTAssertEqual(ALNPasswordHashErrorMalformedEncodedHash, [error code]);
  XCTAssertNotNil(error.userInfo[ALNPasswordHashUnderlyingArgon2ErrorCodeKey]);
}

- (void)testUnsupportedEncodedHashReturnsStructuredError {
  NSError *error = nil;
  BOOL needsRehash = [ALNPasswordHash encodedHashNeedsRehash:@"$argon2i$v=19$m=19456,t=2,p=1$c2FsdHlzYWx0$YWJjZA"
                                                     options:[ALNPasswordHash defaultArgon2idOptions]
                                                       error:&error];
  XCTAssertFalse(needsRehash);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNPasswordHashErrorDomain, [error domain]);
  XCTAssertEqual(ALNPasswordHashErrorUnsupportedEncodedHash, [error code]);
}

- (void)testInvalidOptionsReturnValidationError {
  ALNArgon2idOptions invalid = [ALNPasswordHash defaultArgon2idOptions];
  invalid.saltLength = 4;

  NSError *error = nil;
  NSString *encodedHash = [ALNPasswordHash hashPasswordString:@"password"
                                                     options:invalid
                                                       error:&error];
  XCTAssertNil(encodedHash);
  XCTAssertNotNil(error);
  XCTAssertEqualObjects(ALNPasswordHashErrorDomain, [error domain]);
  XCTAssertEqual(ALNPasswordHashErrorInvalidArgument, [error code]);
}

- (void)testArgon2VersionMetadataIsPublished {
  XCTAssertEqualObjects(@"20190702", [ALNPasswordHash argon2Version]);
}

- (void)testArgon2APIsAreEncapsulatedToPasswordHashModule {
  NSString *repoRoot = [[NSFileManager defaultManager] currentDirectoryPath];
  NSDirectoryEnumerator *enumerator =
      [[NSFileManager defaultManager] enumeratorAtPath:[repoRoot stringByAppendingPathComponent:@"src/Arlen"]];
  NSString *relativePath = nil;
  while ((relativePath = [enumerator nextObject]) != nil) {
    if (![relativePath hasSuffix:@".m"] && ![relativePath hasSuffix:@".h"]) {
      continue;
    }
    if ([relativePath hasPrefix:@"Support/third_party/argon2/"]) {
      continue;
    }
    if ([relativePath isEqualToString:@"Support/ALNPasswordHash.m"]) {
      continue;
    }

    NSString *path = [[repoRoot stringByAppendingPathComponent:@"src/Arlen"]
        stringByAppendingPathComponent:relativePath];
    NSError *error = nil;
    NSString *contents =
        [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    XCTAssertNotNil(contents, @"file=%@", relativePath);
    XCTAssertNil(error, @"file=%@", relativePath);
    if (contents == nil) {
      continue;
    }
    XCTAssertFalse([contents containsString:@"argon2_"], @"file=%@", relativePath);
  }
}

@end
