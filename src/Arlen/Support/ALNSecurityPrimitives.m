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
  unsigned char diff = (unsigned char)(lhsLength ^ rhsLength);
  for (NSUInteger idx = 0; idx < maxLength; idx++) {
    unsigned char lhsByte = (idx < lhsLength) ? lhsBytes[idx] : 0;
    unsigned char rhsByte = (idx < rhsLength) ? rhsBytes[idx] : 0;
    diff |= (unsigned char)(lhsByte ^ rhsByte);
  }
  return (diff == 0);
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
