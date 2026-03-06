#import "ALNTOTP.h"

#import "ALNSecurityPrimitives.h"

NSString *const ALNTOTPErrorDomain = @"Arlen.TOTP.Error";

static NSError *ALNTOTPError(ALNTOTPErrorCode code, NSString *message) {
  return [NSError errorWithDomain:ALNTOTPErrorDomain
                             code:code
                         userInfo:@{
                           NSLocalizedDescriptionKey : message ?: @"totp failed",
                         }];
}

static NSString *const ALNTOTPBase32Alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

static NSString *ALNTOTPTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([trimmed length] > 0) ? trimmed : nil;
}

static NSString *ALNTOTPPercentEncode(NSString *value) {
  NSString *trimmed = ALNTOTPTrimmedString(value);
  if ([trimmed length] == 0) {
    return @"";
  }
  NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
  return [trimmed stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: trimmed;
}

static NSString *ALNTOTPBase32Encode(NSData *data) {
  if (![data isKindOfClass:[NSData class]]) {
    return nil;
  }
  const unsigned char *bytes = [data bytes];
  NSUInteger length = [data length];
  NSMutableString *encoded = [NSMutableString string];
  NSUInteger buffer = 0;
  NSUInteger bitsLeft = 0;
  for (NSUInteger idx = 0; idx < length; idx++) {
    buffer = (buffer << 8) | bytes[idx];
    bitsLeft += 8;
    while (bitsLeft >= 5) {
      NSUInteger index = (buffer >> (bitsLeft - 5)) & 0x1F;
      [encoded appendFormat:@"%C", [ALNTOTPBase32Alphabet characterAtIndex:index]];
      bitsLeft -= 5;
    }
  }
  if (bitsLeft > 0) {
    NSUInteger index = (buffer << (5 - bitsLeft)) & 0x1F;
    [encoded appendFormat:@"%C", [ALNTOTPBase32Alphabet characterAtIndex:index]];
  }
  return encoded;
}

static NSData *ALNTOTPBase32Decode(NSString *secret) {
  NSString *trimmed = ALNTOTPTrimmedString(secret);
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
  if ([normalized length] == 0) {
    return nil;
  }

  NSMutableData *decoded = [NSMutableData data];
  NSUInteger buffer = 0;
  NSUInteger bitsLeft = 0;
  for (NSUInteger idx = 0; idx < [normalized length]; idx++) {
    unichar ch = [normalized characterAtIndex:idx];
    NSRange range = [ALNTOTPBase32Alphabet rangeOfString:[NSString stringWithFormat:@"%C", ch]];
    if (range.location == NSNotFound) {
      return nil;
    }
    buffer = (buffer << 5) | range.location;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      unsigned char byte = (unsigned char)((buffer >> (bitsLeft - 8)) & 0xFF);
      [decoded appendBytes:&byte length:1];
      bitsLeft -= 8;
    }
  }
  return [NSData dataWithData:decoded];
}

static BOOL ALNTOTPValidateDigitsAndPeriod(NSUInteger digits,
                                           NSUInteger period,
                                           NSError **error) {
  if (digits == 0 || digits > 10 || period == 0) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidArgument,
                            @"TOTP digits and period must be non-zero and within range");
    }
    return NO;
  }
  return YES;
}

static NSString *ALNTOTPCodeForCounter(NSData *secretData,
                                       uint64_t counter,
                                       NSUInteger digits,
                                       NSError **error) {
  if (![secretData isKindOfClass:[NSData class]] || [secretData length] == 0) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidSecret, @"TOTP secret is invalid");
    }
    return nil;
  }

  unsigned char counterBytes[8];
  for (NSInteger idx = 7; idx >= 0; idx--) {
    counterBytes[idx] = (unsigned char)(counter & 0xFF);
    counter >>= 8;
  }
  NSData *counterData = [NSData dataWithBytes:counterBytes length:sizeof(counterBytes)];
  NSData *digest = ALNHMACSHA1(counterData, secretData);
  if ([digest length] < 20) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidSecret, @"Failed generating TOTP digest");
    }
    return nil;
  }

  const unsigned char *bytes = [digest bytes];
  NSUInteger offset = bytes[[digest length] - 1] & 0x0F;
  if (offset + 4 > [digest length]) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidSecret, @"TOTP digest offset is invalid");
    }
    return nil;
  }

  uint32_t truncated = ((uint32_t)(bytes[offset] & 0x7F) << 24) |
                       ((uint32_t)(bytes[offset + 1] & 0xFF) << 16) |
                       ((uint32_t)(bytes[offset + 2] & 0xFF) << 8) |
                       ((uint32_t)(bytes[offset + 3] & 0xFF));
  uint64_t modulus = 1;
  for (NSUInteger idx = 0; idx < digits; idx++) {
    modulus *= 10;
  }
  uint64_t code = ((uint64_t)truncated) % modulus;
  return [NSString stringWithFormat:@"%0*llu", (int)digits, (unsigned long long)code];
}

@implementation ALNTOTP

+ (NSString *)generateSecretWithError:(NSError **)error {
  return [self generateSecretWithLength:20 error:error];
}

+ (NSString *)generateSecretWithLength:(NSUInteger)length error:(NSError **)error {
  if (length == 0) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidArgument,
                            @"TOTP secret length must be greater than zero");
    }
    return nil;
  }
  NSData *random = ALNSecureRandomData(length);
  NSString *secret = ALNTOTPBase32Encode(random);
  if ([secret length] == 0) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorRandomGenerationFailed,
                            @"Failed generating a TOTP secret");
    }
    return nil;
  }
  return secret;
}

+ (NSString *)provisioningURIForSecret:(NSString *)secret
                           accountName:(NSString *)accountName
                                issuer:(NSString *)issuer
                                 error:(NSError **)error {
  NSString *normalizedAccount = ALNTOTPTrimmedString(accountName);
  NSData *secretData = ALNTOTPBase32Decode(secret);
  if ([normalizedAccount length] == 0) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidArgument,
                            @"TOTP provisioning requires a non-empty account name");
    }
    return nil;
  }
  if ([secretData length] == 0) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidSecret, @"TOTP secret is invalid");
    }
    return nil;
  }

  NSString *normalizedIssuer = ALNTOTPTrimmedString(issuer);
  NSString *label = ([normalizedIssuer length] > 0)
                        ? [NSString stringWithFormat:@"%@:%@", normalizedIssuer, normalizedAccount]
                        : normalizedAccount;
  NSMutableString *uri =
      [NSMutableString stringWithFormat:@"otpauth://totp/%@?secret=%@",
                                        ALNTOTPPercentEncode(label),
                                        [secret uppercaseString]];
  if ([normalizedIssuer length] > 0) {
    [uri appendFormat:@"&issuer=%@", ALNTOTPPercentEncode(normalizedIssuer)];
  }
  [uri appendString:@"&algorithm=SHA1&digits=6&period=30"];
  return uri;
}

+ (NSString *)codeForSecret:(NSString *)secret atDate:(NSDate *)date error:(NSError **)error {
  return [self codeForSecret:secret atDate:date digits:6 period:30 error:error];
}

+ (NSString *)codeForSecret:(NSString *)secret
                     atDate:(NSDate *)date
                     digits:(NSUInteger)digits
                     period:(NSUInteger)period
                      error:(NSError **)error {
  if (![self validateDigitsAndPeriod:digits period:period error:error]) {
    return nil;
  }
  NSData *secretData = ALNTOTPBase32Decode(secret);
  if ([secretData length] == 0) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidSecret, @"TOTP secret is invalid");
    }
    return nil;
  }
  NSDate *effectiveDate = date ?: [NSDate date];
  uint64_t counter = (uint64_t)floor([effectiveDate timeIntervalSince1970] / (NSTimeInterval)period);
  return ALNTOTPCodeForCounter(secretData, counter, digits, error);
}

+ (BOOL)verifyCode:(NSString *)code secret:(NSString *)secret atDate:(NSDate *)date error:(NSError **)error {
  return [self verifyCode:code
                   secret:secret
                   atDate:date
                   digits:6
                   period:30
     allowedPastIntervals:1
   allowedFutureIntervals:1
                    error:error];
}

+ (BOOL)verifyCode:(NSString *)code
            secret:(NSString *)secret
            atDate:(NSDate *)date
            digits:(NSUInteger)digits
            period:(NSUInteger)period
allowedPastIntervals:(NSUInteger)allowedPastIntervals
allowedFutureIntervals:(NSUInteger)allowedFutureIntervals
             error:(NSError **)error {
  NSString *normalizedCode = ALNTOTPTrimmedString(code);
  if (![self validateDigitsAndPeriod:digits period:period error:error]) {
    return NO;
  }
  if ([normalizedCode length] != digits) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidCode, @"TOTP code has an invalid length");
    }
    return NO;
  }
  NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
  if ([normalizedCode rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidCode, @"TOTP code must contain only digits");
    }
    return NO;
  }

  NSData *secretData = ALNTOTPBase32Decode(secret);
  if ([secretData length] == 0) {
    if (error != NULL) {
      *error = ALNTOTPError(ALNTOTPErrorInvalidSecret, @"TOTP secret is invalid");
    }
    return NO;
  }

  NSDate *effectiveDate = date ?: [NSDate date];
  uint64_t baseCounter = (uint64_t)floor([effectiveDate timeIntervalSince1970] / (NSTimeInterval)period);
  NSData *candidate = [normalizedCode dataUsingEncoding:NSUTF8StringEncoding];

  for (NSInteger delta = -((NSInteger)allowedPastIntervals);
       delta <= (NSInteger)allowedFutureIntervals;
       delta++) {
    uint64_t counter = baseCounter;
    if (delta < 0) {
      if ((uint64_t)(-delta) > counter) {
        continue;
      }
      counter -= (uint64_t)(-delta);
    } else {
      counter += (uint64_t)delta;
    }
    NSString *expected = ALNTOTPCodeForCounter(secretData, counter, digits, error);
    if ([expected length] == 0) {
      return NO;
    }
    NSData *expectedData = [expected dataUsingEncoding:NSUTF8StringEncoding];
    if (ALNConstantTimeDataEquals(candidate, expectedData)) {
      if (error != NULL) {
        *error = nil;
      }
      return YES;
    }
  }

  if (error != NULL) {
    *error = nil;
  }
  return NO;
}

+ (BOOL)validateDigitsAndPeriod:(NSUInteger)digits period:(NSUInteger)period error:(NSError **)error {
  return ALNTOTPValidateDigitsAndPeriod(digits, period, error);
}

@end
