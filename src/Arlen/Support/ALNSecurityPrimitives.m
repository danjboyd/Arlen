#import "ALNSecurityPrimitives.h"

#import <openssl/evp.h>
#import <openssl/hmac.h>
#import <openssl/rand.h>
#import <openssl/sha.h>

NSData *ALNSecureRandomData(NSUInteger length) {
  if (length == 0) {
    return [NSData data];
  }
  NSMutableData *data = [NSMutableData dataWithLength:length];
  if (data == nil) {
    return nil;
  }
  if (RAND_bytes((unsigned char *)[data mutableBytes], (int)length) != 1) {
    return nil;
  }
  return [NSData dataWithData:data];
}

NSString *ALNBase64URLStringFromData(NSData *data) {
  if (![data isKindOfClass:[NSData class]]) {
    return nil;
  }
  NSString *base64 = [data base64EncodedStringWithOptions:0];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
  return base64;
}

NSData *ALNDataFromBase64URLString(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return nil;
  }
  NSString *base64 = [value stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
  NSUInteger remainder = [base64 length] % 4;
  if (remainder > 0) {
    base64 = [base64 stringByPaddingToLength:[base64 length] + (4 - remainder)
                                   withString:@"="
                              startingAtIndex:0];
  }
  return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

BOOL ALNConstantTimeDataEquals(NSData *lhs, NSData *rhs) {
  if (![lhs isKindOfClass:[NSData class]] || ![rhs isKindOfClass:[NSData class]]) {
    return NO;
  }
  NSUInteger lhsLength = [lhs length];
  NSUInteger rhsLength = [rhs length];
  const unsigned char *lhsBytes = [lhs bytes];
  const unsigned char *rhsBytes = [rhs bytes];
  NSUInteger maxLength = (lhsLength > rhsLength) ? lhsLength : rhsLength;
  // Keep the full-width length difference: truncating it to a byte would let
  // lengths that differ by a multiple of 256 compare equal against zero padding.
  NSUInteger lengthDiff = lhsLength ^ rhsLength;
  unsigned char diff = 0;
  for (NSUInteger idx = 0; idx < maxLength; idx++) {
    unsigned char lhsByte = (idx < lhsLength) ? lhsBytes[idx] : 0;
    unsigned char rhsByte = (idx < rhsLength) ? rhsBytes[idx] : 0;
    diff |= (unsigned char)(lhsByte ^ rhsByte);
  }
  return (diff == 0 && lengthDiff == 0);
}

static NSData *ALNHMAC(NSData *input, NSData *key, const EVP_MD *(*digestFactory)(void)) {
  if (![input isKindOfClass:[NSData class]] || ![key isKindOfClass:[NSData class]] ||
      [input length] == 0 || [key length] == 0 || digestFactory == NULL) {
    return nil;
  }
  unsigned int digestLength = 0;
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned char *result = HMAC(digestFactory(),
                               [key bytes],
                               (int)[key length],
                               [input bytes],
                               (size_t)[input length],
                               digest,
                               &digestLength);
  if (result == NULL || digestLength == 0) {
    return nil;
  }
  return [NSData dataWithBytes:digest length:(NSUInteger)digestLength];
}

NSData *ALNHMACSHA1(NSData *input, NSData *key) {
  return ALNHMAC(input, key, EVP_sha1);
}

NSData *ALNHMACSHA256(NSData *input, NSData *key) {
  return ALNHMAC(input, key, EVP_sha256);
}

NSData *ALNSHA256FileHandle(NSFileHandle *handle) {
  if (handle == nil) return nil;
  EVP_MD_CTX *context = EVP_MD_CTX_new();
  if (context == NULL) return nil;
  NSData *result = nil;
  unsigned long long offset = 0;
  BOOL haveOffset = NO;
  @try {
    offset = handle.offsetInFile;
    haveOffset = YES;
    [handle seekToFileOffset:0];
    BOOL ok = EVP_DigestInit_ex(context, EVP_sha256(), NULL) == 1;
    while (ok) {
      @autoreleasepool {
        NSData *chunk = [handle readDataOfLength:65536];
        if (chunk.length == 0) break;
        ok = EVP_DigestUpdate(context, chunk.bytes, chunk.length) == 1;
      }
    }
    unsigned char digest[EVP_MAX_MD_SIZE];
    unsigned int length = 0;
    if (ok && EVP_DigestFinal_ex(context, digest, &length) == 1) {
      result = [NSData dataWithBytes:digest length:length];
    }
  } @catch (NSException *exception) {
    (void)exception;
  } @finally {
    if (haveOffset) {
      @try { [handle seekToFileOffset:offset]; } @catch (NSException *exception) { result = nil; }
    }
    EVP_MD_CTX_free(context);
  }
  return result;
}

NSData *ALNSHA256(NSData *input) {
  if (![input isKindOfClass:[NSData class]]) {
    return nil;
  }
  unsigned char digest[SHA256_DIGEST_LENGTH];
  SHA256([input bytes], [input length], digest);
  return [NSData dataWithBytes:digest length:SHA256_DIGEST_LENGTH];
}

NSString *ALNLowercaseHexStringFromData(NSData *data) {
  if (![data isKindOfClass:[NSData class]]) {
    return nil;
  }
  const unsigned char *bytes = [data bytes];
  NSUInteger length = [data length];
  NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
  for (NSUInteger idx = 0; idx < length; idx++) {
    [hex appendFormat:@"%02x", bytes[idx]];
  }
  return hex;
}

NSArray<NSString *> *ALNKnownPublishedSigningSecrets(void) {
  static NSArray<NSString *> *secrets = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    secrets = @[
      // tools/deploy/systemd/site.env.example and `arlen deploy init` (older releases)
      @"replace-with-32-plus-character-secret",
      @"replace-with-distinct-32-plus-character-secret",
      // examples/*/config
      @"api-reference-secret-0123456789ab",
      @"auth-admin-demo-session-secret-0123456789abcdef",
      @"auth-module-stub-provider-secret-0123456789abcdef",
      @"phase12-auth-primitives-session-secret-0123456789abcdef",
      @"phase12-demo-client-secret-0123456789abcdef",
      @"phase14-modules-demo-session-secret-0123456789abcdef",
      @"phase16-modules-demo-session-secret-0123456789abcdef",
      @"phase28-reference-session-secret-0123456789abcdef",
      // tools/
      @"client-secret-0123456789abcdef",
      @"ignored-fixture-secret-01234567890123456789",
      @"phase21-generated-app-matrix-session-secret-0123456789abcdef",
    ];
  });
  return secrets;
}

NSString *ALNInsecureSigningSecretReason(NSString *secret) {
  if (![secret isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [secret stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    return nil;
  }
  NSString *lowered = [trimmed lowercaseString];
  for (NSString *marker in @[ @"replace-with", @"change-me", @"changeme", @"change_me", @"0123456789ab" ]) {
    if ([lowered rangeOfString:marker].location != NSNotFound) {
      return @"placeholder_secret";
    }
  }
  if ([ALNKnownPublishedSigningSecrets() containsObject:trimmed]) {
    return @"published_example_secret";
  }
  return nil;
}

BOOL ALNEnvironmentAllowsInsecureSigningSecrets(NSString *environment) {
  if (![environment isKindOfClass:[NSString class]]) {
    return NO;
  }
  NSString *normalized =
      [[environment stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
  return [normalized isEqualToString:@"development"] || [normalized isEqualToString:@"test"];
}
