#import "ALNSessionMiddleware.h"

#import "ALNContext.h"
#import "ALNJSONSerialization.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

static NSString *const ALNSessionVersion = @"v1";

static NSString *ALNHexStringFromUInt64(uint64_t value) {
  return [NSString stringWithFormat:@"%016llx", (unsigned long long)value];
}

static uint64_t ALNFNV1aHash(NSData *data, uint64_t seed) {
  const unsigned char *bytes = [data bytes];
  NSUInteger length = [data length];
  uint64_t hash = 1469598103934665603ULL ^ seed;
  for (NSUInteger idx = 0; idx < length; idx++) {
    hash ^= (uint64_t)bytes[idx];
    hash *= 1099511628211ULL;
  }
  return hash;
}

static NSString *ALNBase64URLFromData(NSData *data) {
  NSString *base64 = [data base64EncodedStringWithOptions:0];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
  base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
  return base64;
}

static NSData *ALNDataFromBase64URL(NSString *value) {
  if ([value length] == 0) {
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

static NSData *ALNXORCipher(NSData *input, NSData *key, NSData *nonce) {
  if ([input length] == 0) {
    return [NSData data];
  }

  NSUInteger keyLength = [key length];
  NSUInteger nonceLength = [nonce length];
  if (keyLength == 0 || nonceLength == 0) {
    return nil;
  }

  const unsigned char *inputBytes = [input bytes];
  const unsigned char *keyBytes = [key bytes];
  const unsigned char *nonceBytes = [nonce bytes];
  NSMutableData *output = [NSMutableData dataWithLength:[input length]];
  unsigned char *outputBytes = [output mutableBytes];

  for (NSUInteger idx = 0; idx < [input length]; idx++) {
    unsigned char mask = keyBytes[idx % keyLength] ^ nonceBytes[idx % nonceLength] ^
                         (unsigned char)((idx * 31U) & 0xFFU);
    outputBytes[idx] = inputBytes[idx] ^ mask;
  }
  return output;
}

@interface ALNSessionMiddleware ()

@property(nonatomic, copy) NSString *cookieName;
@property(nonatomic, assign) NSUInteger maxAgeSeconds;
@property(nonatomic, assign) BOOL secure;
@property(nonatomic, copy) NSString *sameSite;
@property(nonatomic, copy) NSString *secret;
@property(nonatomic, strong) NSData *secretData;

@end

@implementation ALNSessionMiddleware

- (instancetype)initWithSecret:(NSString *)secret
                    cookieName:(NSString *)cookieName
                 maxAgeSeconds:(NSUInteger)maxAgeSeconds
                        secure:(BOOL)secure
                      sameSite:(NSString *)sameSite {
  self = [super init];
  if (self) {
    _secret = [secret copy];
    if ([_secret length] == 0) {
      _secret = @"arlen-insecure-default-secret";
    }
    _secretData = [_secret dataUsingEncoding:NSUTF8StringEncoding];
    if (_secretData == nil) {
      _secretData = [NSData data];
    }

    _cookieName = [cookieName copy];
    if ([_cookieName length] == 0) {
      _cookieName = @"arlen_session";
    }

    _maxAgeSeconds = (maxAgeSeconds > 0) ? maxAgeSeconds : 1209600;
    _secure = secure;
    _sameSite = [sameSite copy];
    if ([_sameSite length] == 0) {
      _sameSite = @"Lax";
    }
  }
  return self;
}

- (NSString *)setCookieHeaderWithValue:(NSString *)value maxAge:(NSUInteger)maxAge {
  NSMutableArray *parts = [NSMutableArray arrayWithObjects:
                                              [NSString stringWithFormat:@"%@=%@", self.cookieName, value ?: @""],
                                              @"Path=/",
                                              @"HttpOnly",
                                              [NSString stringWithFormat:@"SameSite=%@", self.sameSite],
                                              [NSString stringWithFormat:@"Max-Age=%lu", (unsigned long)maxAge],
                                              nil];
  if (self.secure) {
    [parts addObject:@"Secure"];
  }
  return [parts componentsJoinedByString:@"; "];
}

- (NSString *)signatureForPrefix:(NSString *)prefix {
  NSData *prefixData = [prefix dataUsingEncoding:NSUTF8StringEncoding];
  uint64_t hash = ALNFNV1aHash(prefixData, ALNFNV1aHash(self.secretData, 0x9e3779b97f4a7c15ULL));
  return ALNHexStringFromUInt64(hash);
}

- (NSString *)encodeSessionDictionary:(NSDictionary *)session {
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSDictionary *payload = @{
    @"iat" : @((NSInteger)now),
    @"exp" : @((NSInteger)(now + (NSTimeInterval)self.maxAgeSeconds)),
    @"data" : session ?: @{},
  };

  NSError *jsonError = nil;
  NSData *plaintext = [ALNJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
  if (plaintext == nil) {
    return nil;
  }

  uint64_t nonceValue = (((uint64_t)arc4random()) << 32) | (uint64_t)arc4random();
  NSData *nonceData = [NSData dataWithBytes:&nonceValue length:sizeof(nonceValue)];
  NSData *ciphertext = ALNXORCipher(plaintext, self.secretData, nonceData);
  if (ciphertext == nil) {
    return nil;
  }

  NSString *noncePart = ALNBase64URLFromData(nonceData);
  NSString *cipherPart = ALNBase64URLFromData(ciphertext);
  NSString *prefix =
      [NSString stringWithFormat:@"%@.%@.%@", ALNSessionVersion, noncePart, cipherPart];
  NSString *signature = [self signatureForPrefix:prefix];
  return [NSString stringWithFormat:@"%@.%@", prefix, signature];
}

- (nullable NSMutableDictionary *)decodeSessionToken:(NSString *)token {
  NSArray *parts = [token componentsSeparatedByString:@"."];
  if ([parts count] != 4) {
    return nil;
  }
  if (![parts[0] isEqualToString:ALNSessionVersion]) {
    return nil;
  }

  NSString *prefix = [NSString stringWithFormat:@"%@.%@.%@", parts[0], parts[1], parts[2]];
  NSString *expectedSignature = [self signatureForPrefix:prefix];
  NSString *providedSignature = [parts[3] lowercaseString];
  if (![expectedSignature isEqualToString:providedSignature]) {
    return nil;
  }

  NSData *nonceData = ALNDataFromBase64URL(parts[1]);
  NSData *cipherData = ALNDataFromBase64URL(parts[2]);
  if ([nonceData length] == 0 || [cipherData length] == 0) {
    return nil;
  }

  NSData *plaintext = ALNXORCipher(cipherData, self.secretData, nonceData);
  if (plaintext == nil) {
    return nil;
  }

  NSError *jsonError = nil;
  NSDictionary *payload =
      [ALNJSONSerialization JSONObjectWithData:plaintext options:0 error:&jsonError];
  if (![payload isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  NSInteger expiresAt = [payload[@"exp"] integerValue];
  NSInteger now = (NSInteger)[[NSDate date] timeIntervalSince1970];
  if (expiresAt > 0 && expiresAt < now) {
    return nil;
  }

  NSDictionary *data = payload[@"data"];
  if (![data isKindOfClass:[NSDictionary class]]) {
    return [NSMutableDictionary dictionary];
  }
  return [NSMutableDictionary dictionaryWithDictionary:data];
}

- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  (void)error;
  NSString *raw = context.request.cookies[self.cookieName];
  BOOL hadCookie = ([raw length] > 0);

  NSMutableDictionary *session = nil;
  if (hadCookie) {
    session = [self decodeSessionToken:raw];
  }
  if (session == nil) {
    session = [NSMutableDictionary dictionary];
  }

  context.stash[ALNContextSessionStashKey] = session;
  context.stash[ALNContextSessionHadCookieStashKey] = @(hadCookie);
  context.stash[ALNContextSessionDirtyStashKey] = @(NO);

  NSString *csrf = session[@"_csrf_token"];
  if ([csrf isKindOfClass:[NSString class]] && [csrf length] > 0) {
    context.stash[ALNContextCSRFTokenStashKey] = csrf;
  }
  return YES;
}

- (void)didProcessContext:(ALNContext *)context {
  NSMutableDictionary *session = context.stash[ALNContextSessionStashKey];
  if (![session isKindOfClass:[NSMutableDictionary class]]) {
    return;
  }

  BOOL hadCookie = [context.stash[ALNContextSessionHadCookieStashKey] boolValue];
  BOOL dirty = [context.stash[ALNContextSessionDirtyStashKey] boolValue];
  if (!dirty && hadCookie) {
    return;
  }

  if ([session count] == 0) {
    if (hadCookie) {
      [context.response setHeader:@"Set-Cookie"
                            value:[self setCookieHeaderWithValue:@"" maxAge:0]];
    }
    return;
  }

  NSString *token = [self encodeSessionDictionary:session];
  if ([token length] == 0) {
    context.response.statusCode = 500;
    [context.response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
    [context.response setTextBody:@"session encoding failed\n"];
    context.response.committed = YES;
    return;
  }

  [context.response setHeader:@"Set-Cookie"
                        value:[self setCookieHeaderWithValue:token maxAge:self.maxAgeSeconds]];
}

@end
