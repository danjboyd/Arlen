#import "ALNRecoveryCodes.h"

#import "ALNPasswordHash.h"
#import "ALNSecurityPrimitives.h"

NSString *const ALNRecoveryCodesErrorDomain = @"Arlen.RecoveryCodes.Error";

static NSError *ALNRecoveryCodesError(ALNRecoveryCodesErrorCode code, NSString *message) {
  return [NSError errorWithDomain:ALNRecoveryCodesErrorDomain
                             code:code
                         userInfo:@{
                           NSLocalizedDescriptionKey : message ?: @"recovery code failure",
                         }];
}

static NSString *const ALNRecoveryCodesAlphabet = @"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

static NSString *ALNRecoveryCodeTrimmed(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([trimmed length] > 0) ? trimmed : nil;
}

static NSString *ALNNormalizeRecoveryCode(NSString *code) {
  NSString *trimmed = ALNRecoveryCodeTrimmed(code);
  if ([trimmed length] == 0) {
    return nil;
  }
  NSMutableString *normalized = [NSMutableString string];
  for (NSUInteger idx = 0; idx < [trimmed length]; idx++) {
    unichar ch = [trimmed characterAtIndex:idx];
    if (ch == '-' || ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
      continue;
    }
    [normalized appendFormat:@"%C", (unichar)toupper((int)ch)];
  }
  return ([normalized length] > 0) ? normalized : nil;
}

@implementation ALNRecoveryCodes

+ (NSArray *)generateCodesWithCount:(NSUInteger)count error:(NSError **)error {
  return [self generateCodesWithCount:count segmentLength:5 error:error];
}

+ (NSArray *)generateCodesWithCount:(NSUInteger)count
                      segmentLength:(NSUInteger)segmentLength
                              error:(NSError **)error {
  if (count == 0 || segmentLength == 0) {
    if (error != NULL) {
      *error = ALNRecoveryCodesError(ALNRecoveryCodesErrorInvalidArgument,
                                     @"Recovery code count and segment length must be greater than zero");
    }
    return nil;
  }

  NSMutableArray *codes = [NSMutableArray arrayWithCapacity:count];
  for (NSUInteger idx = 0; idx < count; idx++) {
    NSData *random = ALNSecureRandomData(segmentLength * 2);
    if ([random length] == 0) {
      if (error != NULL) {
        *error = ALNRecoveryCodesError(ALNRecoveryCodesErrorRandomGenerationFailed,
                                       @"Failed generating recovery codes");
      }
      return nil;
    }
    const unsigned char *bytes = [random bytes];
    NSMutableString *code = [NSMutableString string];
    for (NSUInteger offset = 0; offset < segmentLength * 2; offset++) {
      NSUInteger alphabetIndex = bytes[offset] % [ALNRecoveryCodesAlphabet length];
      [code appendFormat:@"%C", [ALNRecoveryCodesAlphabet characterAtIndex:alphabetIndex]];
      if (offset + 1 == segmentLength && segmentLength * 2 > segmentLength + 1) {
        [code appendString:@"-"];
      }
    }
    [codes addObject:code];
  }
  return [NSArray arrayWithArray:codes];
}

+ (NSArray *)hashCodes:(NSArray *)codes error:(NSError **)error {
  NSMutableArray *encoded = [NSMutableArray array];
  ALNArgon2idOptions options = [ALNPasswordHash defaultArgon2idOptions];
  for (id value in codes ?: @[]) {
    NSString *normalized = ALNNormalizeRecoveryCode(value);
    if ([normalized length] == 0) {
      if (error != NULL) {
        *error = ALNRecoveryCodesError(ALNRecoveryCodesErrorInvalidArgument,
                                       @"Recovery codes must be non-empty strings");
      }
      return nil;
    }
    NSError *hashError = nil;
    NSString *encodedHash = [ALNPasswordHash hashPasswordString:normalized
                                                        options:options
                                                          error:&hashError];
    if ([encodedHash length] == 0 || hashError != nil) {
      if (error != NULL) {
        *error = ALNRecoveryCodesError(ALNRecoveryCodesErrorHashingFailed,
                                       hashError.localizedDescription ?: @"Failed hashing recovery code");
      }
      return nil;
    }
    [encoded addObject:encodedHash];
  }
  return [NSArray arrayWithArray:encoded];
}

+ (BOOL)verifyCode:(NSString *)code againstEncodedHash:(NSString *)encodedHash error:(NSError **)error {
  NSString *normalized = ALNNormalizeRecoveryCode(code);
  if ([normalized length] == 0 || ![encodedHash isKindOfClass:[NSString class]] ||
      [encodedHash length] == 0) {
    if (error != NULL) {
      *error = ALNRecoveryCodesError(ALNRecoveryCodesErrorInvalidArgument,
                                     @"Recovery code verification requires a code and encoded hash");
    }
    return NO;
  }
  NSError *verifyError = nil;
  BOOL verified = [ALNPasswordHash verifyPasswordString:normalized
                                      againstEncodedHash:encodedHash
                                                   error:&verifyError];
  if (error != NULL) {
    *error = verifyError;
  }
  return verified;
}

+ (BOOL)consumeCode:(NSString *)code
againstEncodedHashes:(NSArray *)encodedHashes
remainingEncodedHashes:(NSArray **)remainingEncodedHashes
             error:(NSError **)error {
  NSString *normalized = ALNNormalizeRecoveryCode(code);
  if ([normalized length] == 0 || ![encodedHashes isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNRecoveryCodesError(ALNRecoveryCodesErrorInvalidArgument,
                                     @"Recovery code consumption requires a code and encoded hash array");
    }
    return NO;
  }

  for (NSUInteger idx = 0; idx < [encodedHashes count]; idx++) {
    id value = encodedHashes[idx];
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSError *verifyError = nil;
    BOOL verified = [ALNPasswordHash verifyPasswordString:normalized
                                        againstEncodedHash:(NSString *)value
                                                     error:&verifyError];
    if (verifyError != nil) {
      if (error != NULL) {
        *error = verifyError;
      }
      return NO;
    }
    if (!verified) {
      continue;
    }

    NSMutableArray *remaining = [NSMutableArray arrayWithArray:encodedHashes];
    [remaining removeObjectAtIndex:idx];
    if (remainingEncodedHashes != NULL) {
      *remainingEncodedHashes = [NSArray arrayWithArray:remaining];
    }
    if (error != NULL) {
      *error = nil;
    }
    return YES;
  }

  if (remainingEncodedHashes != NULL) {
    *remainingEncodedHashes = [NSArray arrayWithArray:encodedHashes];
  }
  if (error != NULL) {
    *error = nil;
  }
  return NO;
}

@end
