#import "ALNPasswordHash.h"

#include <errno.h>
#include <limits.h>
#include <openssl/crypto.h>
#include <openssl/rand.h>
#include <string.h>

#include "third_party/argon2/include/argon2.h"

NSString *const ALNPasswordHashErrorDomain = @"Arlen.PasswordHash.Error";
NSString *const ALNPasswordHashUnderlyingArgon2ErrorCodeKey =
    @"ALNPasswordHashUnderlyingArgon2ErrorCode";

static NSString *const ALNArgon2VersionString = @"20190702";

static ALNArgon2idOptions ALNDefaultArgon2idOptions(void) {
  ALNArgon2idOptions options;
  options.memoryKiB = 19456;
  options.iterations = 2;
  options.parallelism = 1;
  options.saltLength = 16;
  options.hashLength = 32;
  return options;
}

typedef struct {
  uint32_t version;
  uint32_t memoryKiB;
  uint32_t iterations;
  uint32_t parallelism;
  NSUInteger saltLength;
  NSUInteger hashLength;
} ALNParsedArgon2idHash;

static void ALNSetError(NSError **error,
                        ALNPasswordHashErrorCode code,
                        NSString *message,
                        NSNumber *underlyingArgon2Code) {
  if (error == NULL) {
    return;
  }

  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"password hashing failed";
  if (underlyingArgon2Code != nil) {
    userInfo[ALNPasswordHashUnderlyingArgon2ErrorCodeKey] = underlyingArgon2Code;
  }

  *error = [NSError errorWithDomain:ALNPasswordHashErrorDomain
                               code:code
                           userInfo:userInfo];
}

static void ALNSetArgon2Error(NSError **error,
                              ALNPasswordHashErrorCode code,
                              NSString *prefix,
                              int argon2Code) {
  NSString *detail = nil;
  const char *message = argon2_error_message(argon2Code);
  if (message != NULL) {
    detail = [NSString stringWithUTF8String:message];
  }
  NSString *localized = prefix ?: @"Argon2 operation failed";
  if ([detail length] > 0) {
    localized = [NSString stringWithFormat:@"%@: %@", localized, detail];
  }
  ALNSetError(error, code, localized, @(argon2Code));
}

static void ALNSecureCleanseMutableData(NSMutableData *data) {
  if (data == nil || [data length] == 0) {
    return;
  }
  OPENSSL_cleanse([data mutableBytes], [data length]);
}

static NSMutableData *ALNWorkingPasswordDataFromData(NSData *passwordData,
                                                     NSError **error) {
  if (![passwordData isKindOfClass:[NSData class]]) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Password data is required",
                nil);
    return nil;
  }

  if ((unsigned long long)[passwordData length] > ARGON2_MAX_PWD_LENGTH) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Password data exceeds the maximum supported length",
                nil);
    return nil;
  }

  NSMutableData *working = [passwordData mutableCopy];
  if (working == nil) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Failed to copy password data",
                nil);
    return nil;
  }
  return working;
}

static NSMutableData *ALNWorkingPasswordDataFromString(NSString *password,
                                                       NSError **error) {
  if (![password isKindOfClass:[NSString class]]) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Password string is required",
                nil);
    return nil;
  }

  NSData *utf8 = [password dataUsingEncoding:NSUTF8StringEncoding];
  if (utf8 == nil) {
    ALNSetError(error,
                ALNPasswordHashErrorUTF8EncodingFailed,
                @"Failed to encode password string as UTF-8",
                nil);
    return nil;
  }

  return [utf8 mutableCopy];
}

static BOOL ALNValidateOptions(ALNArgon2idOptions options, NSError **error) {
  if (options.memoryKiB < ARGON2_MIN_MEMORY || options.memoryKiB > ARGON2_MAX_MEMORY) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Argon2 memoryKiB is outside the supported range",
                nil);
    return NO;
  }
  if (options.iterations < ARGON2_MIN_TIME || options.iterations > ARGON2_MAX_TIME) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Argon2 iterations is outside the supported range",
                nil);
    return NO;
  }
  if (options.parallelism < ARGON2_MIN_LANES || options.parallelism > ARGON2_MAX_LANES) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Argon2 parallelism is outside the supported range",
                nil);
    return NO;
  }
  if (options.saltLength < ARGON2_MIN_SALT_LENGTH ||
      (unsigned long long)options.saltLength > ARGON2_MAX_SALT_LENGTH) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Argon2 saltLength is outside the supported range",
                nil);
    return NO;
  }
  if (options.saltLength > INT_MAX) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Argon2 saltLength exceeds the secure random API limit",
                nil);
    return NO;
  }
  if (options.hashLength < ARGON2_MIN_OUTLEN ||
      (unsigned long long)options.hashLength > ARGON2_MAX_OUTLEN) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Argon2 hashLength is outside the supported range",
                nil);
    return NO;
  }
  return YES;
}

static BOOL ALNParseUInt32String(NSString *value, uint32_t *outValue) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }

  const char *bytes = [value UTF8String];
  if (bytes == NULL) {
    return NO;
  }

  errno = 0;
  char *end = NULL;
  unsigned long long parsed = strtoull(bytes, &end, 10);
  if (errno != 0 || end == bytes || end == NULL || *end != '\0' || parsed > UINT32_MAX) {
    return NO;
  }

  if (outValue != NULL) {
    *outValue = (uint32_t)parsed;
  }
  return YES;
}

static NSData *ALNDecodeArgon2Base64Segment(NSString *segment) {
  if (![segment isKindOfClass:[NSString class]] || [segment length] == 0) {
    return nil;
  }

  NSMutableString *normalized = [segment mutableCopy];
  NSUInteger remainder = [normalized length] % 4;
  if (remainder == 1) {
    return nil;
  }
  if (remainder > 0) {
    NSUInteger padCount = 4 - remainder;
    for (NSUInteger idx = 0; idx < padCount; idx++) {
      [normalized appendString:@"="];
    }
  }

  return [[NSData alloc] initWithBase64EncodedString:normalized options:0];
}

static BOOL ALNParseArgon2idParameters(NSString *segment,
                                       ALNParsedArgon2idHash *parsed,
                                       NSError **error) {
  NSArray *parts = [segment componentsSeparatedByString:@","];
  NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:[parts count]];
  for (NSString *part in parts) {
    NSArray *pair = [part componentsSeparatedByString:@"="];
    if ([pair count] != 2 || [pair[0] length] == 0 || [pair[1] length] == 0) {
      ALNSetError(error,
                  ALNPasswordHashErrorMalformedEncodedHash,
                  @"Encoded Argon2id hash has invalid parameter formatting",
                  nil);
      return NO;
    }
    params[pair[0]] = pair[1];
  }

  if (!ALNParseUInt32String(params[@"m"], &parsed->memoryKiB) ||
      !ALNParseUInt32String(params[@"t"], &parsed->iterations) ||
      !ALNParseUInt32String(params[@"p"], &parsed->parallelism)) {
    ALNSetError(error,
                ALNPasswordHashErrorMalformedEncodedHash,
                @"Encoded Argon2id hash is missing required numeric parameters",
                nil);
    return NO;
  }

  return YES;
}

static BOOL ALNParseEncodedArgon2idHash(NSString *encodedHash,
                                        ALNParsedArgon2idHash *parsed,
                                        NSError **error) {
  if (![encodedHash isKindOfClass:[NSString class]] || [encodedHash length] == 0) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Encoded hash is required",
                nil);
    return NO;
  }

  NSArray *segments = [encodedHash componentsSeparatedByString:@"$"];
  if ([segments count] != 5 && [segments count] != 6) {
    ALNSetError(error,
                ALNPasswordHashErrorMalformedEncodedHash,
                @"Encoded Argon2id hash has an invalid PHC format",
                nil);
    return NO;
  }
  if ([segments count] < 2 || ![segments[0] isEqualToString:@""]) {
    ALNSetError(error,
                ALNPasswordHashErrorMalformedEncodedHash,
                @"Encoded Argon2id hash has an invalid PHC prefix",
                nil);
    return NO;
  }
  if (![segments[1] isEqualToString:@"argon2id"]) {
    ALNSetError(error,
                ALNPasswordHashErrorUnsupportedEncodedHash,
                @"Encoded hash is not an Argon2id PHC string",
                nil);
    return NO;
  }

  NSUInteger parameterIndex = 2;
  parsed->version = 0;
  if ([segments count] == 6) {
    NSString *versionSegment = segments[2];
    if (![versionSegment hasPrefix:@"v="] ||
        !ALNParseUInt32String([versionSegment substringFromIndex:2], &parsed->version)) {
      ALNSetError(error,
                  ALNPasswordHashErrorMalformedEncodedHash,
                  @"Encoded Argon2id hash has an invalid version segment",
                  nil);
      return NO;
    }
    parameterIndex = 3;
  }

  if (!ALNParseArgon2idParameters(segments[parameterIndex], parsed, error)) {
    return NO;
  }

  NSData *salt = ALNDecodeArgon2Base64Segment(segments[parameterIndex + 1]);
  NSData *hash = ALNDecodeArgon2Base64Segment(segments[parameterIndex + 2]);
  if (salt == nil || hash == nil) {
    ALNSetError(error,
                ALNPasswordHashErrorMalformedEncodedHash,
                @"Encoded Argon2id hash has invalid salt or digest encoding",
                nil);
    return NO;
  }

  parsed->saltLength = [salt length];
  parsed->hashLength = [hash length];
  return YES;
}

static NSString *ALNHashWorkingPassword(NSMutableData *workingPassword,
                                        ALNArgon2idOptions options,
                                        NSError **error) {
  if (workingPassword == nil) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Password data is required",
                nil);
    return nil;
  }
  if (!ALNValidateOptions(options, error)) {
    ALNSecureCleanseMutableData(workingPassword);
    return nil;
  }

  NSMutableData *salt = [NSMutableData dataWithLength:options.saltLength];
  if (salt == nil || RAND_bytes([salt mutableBytes], (int)[salt length]) != 1) {
    ALNSecureCleanseMutableData(workingPassword);
    ALNSetError(error,
                ALNPasswordHashErrorSaltGenerationFailed,
                @"Failed to generate a secure Argon2 salt",
                nil);
    return nil;
  }

  size_t encodedLength = argon2_encodedlen(options.iterations,
                                           options.memoryKiB,
                                           options.parallelism,
                                           options.saltLength,
                                           options.hashLength,
                                           Argon2_id) + 1;
  char *encoded = calloc(encodedLength, sizeof(char));
  if (encoded == NULL) {
    ALNSecureCleanseMutableData(workingPassword);
    ALNSetError(error,
                ALNPasswordHashErrorHashingFailed,
                @"Failed to allocate Argon2 output buffer",
                nil);
    return nil;
  }

  int result = argon2id_hash_encoded(options.iterations,
                                     options.memoryKiB,
                                     options.parallelism,
                                     [workingPassword bytes],
                                     [workingPassword length],
                                     [salt bytes],
                                     [salt length],
                                     options.hashLength,
                                     encoded,
                                     encodedLength);
  ALNSecureCleanseMutableData(workingPassword);
  if (result != ARGON2_OK) {
    free(encoded);
    ALNSetArgon2Error(error,
                      ALNPasswordHashErrorHashingFailed,
                      @"Argon2id password hashing failed",
                      result);
    return nil;
  }

  NSString *encodedHash = [NSString stringWithUTF8String:encoded];
  free(encoded);
  if (encodedHash == nil) {
    ALNSetError(error,
                ALNPasswordHashErrorHashingFailed,
                @"Failed to decode encoded Argon2 hash as UTF-8",
                nil);
    return nil;
  }

  return encodedHash;
}

static BOOL ALNVerifyWorkingPassword(NSMutableData *workingPassword,
                                     NSString *encodedHash,
                                     NSError **error) {
  if (workingPassword == nil) {
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Password data is required",
                nil);
    return NO;
  }
  if (![encodedHash isKindOfClass:[NSString class]] || [encodedHash length] == 0) {
    ALNSecureCleanseMutableData(workingPassword);
    ALNSetError(error,
                ALNPasswordHashErrorInvalidArgument,
                @"Encoded hash is required",
                nil);
    return NO;
  }

  int result = argon2id_verify([encodedHash UTF8String],
                               [workingPassword bytes],
                               [workingPassword length]);
  ALNSecureCleanseMutableData(workingPassword);
  if (result == ARGON2_OK) {
    return YES;
  }
  if (result == ARGON2_VERIFY_MISMATCH) {
    return NO;
  }
  if (result == ARGON2_DECODING_FAIL || result == ARGON2_DECODING_LENGTH_FAIL) {
    ALNSetArgon2Error(error,
                      ALNPasswordHashErrorMalformedEncodedHash,
                      @"Encoded Argon2id hash could not be parsed",
                      result);
    return NO;
  }
  if (result == ARGON2_INCORRECT_TYPE) {
    ALNSetArgon2Error(error,
                      ALNPasswordHashErrorUnsupportedEncodedHash,
                      @"Encoded hash is not an Argon2id value",
                      result);
    return NO;
  }

  ALNSetArgon2Error(error,
                    ALNPasswordHashErrorVerificationFailed,
                    @"Argon2id password verification failed",
                    result);
  return NO;
}

@implementation ALNPasswordHash

+ (ALNArgon2idOptions)defaultArgon2idOptions {
  return ALNDefaultArgon2idOptions();
}

+ (NSString *)hashPasswordString:(NSString *)password
                         options:(ALNArgon2idOptions)options
                           error:(NSError **)error {
  NSMutableData *workingPassword = ALNWorkingPasswordDataFromString(password, error);
  if (workingPassword == nil) {
    return nil;
  }
  return ALNHashWorkingPassword(workingPassword, options, error);
}

+ (NSString *)hashPasswordData:(NSData *)passwordData
                       options:(ALNArgon2idOptions)options
                         error:(NSError **)error {
  NSMutableData *workingPassword = ALNWorkingPasswordDataFromData(passwordData, error);
  if (workingPassword == nil) {
    return nil;
  }
  return ALNHashWorkingPassword(workingPassword, options, error);
}

+ (BOOL)verifyPasswordString:(NSString *)password
          againstEncodedHash:(NSString *)encodedHash
                       error:(NSError **)error {
  NSMutableData *workingPassword = ALNWorkingPasswordDataFromString(password, error);
  if (workingPassword == nil) {
    return NO;
  }
  return ALNVerifyWorkingPassword(workingPassword, encodedHash, error);
}

+ (BOOL)verifyPasswordData:(NSData *)passwordData
        againstEncodedHash:(NSString *)encodedHash
                     error:(NSError **)error {
  NSMutableData *workingPassword = ALNWorkingPasswordDataFromData(passwordData, error);
  if (workingPassword == nil) {
    return NO;
  }
  return ALNVerifyWorkingPassword(workingPassword, encodedHash, error);
}

+ (BOOL)encodedHashNeedsRehash:(NSString *)encodedHash
                       options:(ALNArgon2idOptions)options
                         error:(NSError **)error {
  if (!ALNValidateOptions(options, error)) {
    return NO;
  }

  ALNParsedArgon2idHash parsed;
  memset(&parsed, 0, sizeof(parsed));
  if (!ALNParseEncodedArgon2idHash(encodedHash, &parsed, error)) {
    return NO;
  }

  if (parsed.version != ARGON2_VERSION_NUMBER) {
    return YES;
  }
  if (parsed.memoryKiB != options.memoryKiB || parsed.iterations != options.iterations ||
      parsed.parallelism != options.parallelism) {
    return YES;
  }
  if (parsed.saltLength != options.saltLength || parsed.hashLength != options.hashLength) {
    return YES;
  }
  return NO;
}

+ (NSString *)argon2Version {
  return ALNArgon2VersionString;
}

@end
