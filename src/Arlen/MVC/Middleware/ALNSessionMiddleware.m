#import "ALNSessionMiddleware.h"

#import "ALNContext.h"
#import "ALNJSONSerialization.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

#import <openssl/evp.h>
#import <openssl/hmac.h>

static NSString *const ALNSessionVersion = @"v2";

static NSData *ALNHMACSHA256(NSData *input, NSData *key) {
  if ([input length] == 0 || [key length] == 0) {
    return nil;
  }
  unsigned int digestLength = 0;
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned char *hmacResult = HMAC(EVP_sha256(),
                                   [key bytes],
                                   (int)[key length],
                                   [input bytes],
                                   (size_t)[input length],
                                   digest,
                                   &digestLength);
  if (hmacResult == NULL || digestLength == 0) {
    return nil;
  }
  return [NSData dataWithBytes:digest length:(NSUInteger)digestLength];
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

static BOOL ALNConstantTimeDataEqual(NSData *lhs, NSData *rhs) {
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
    NSString *normalizedSecret = secret ?: @"";
    _secret = [normalizedSecret
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
  if ([self.secretData length] == 0) {
    return @"";
  }
  NSData *prefixData = [prefix dataUsingEncoding:NSUTF8StringEncoding];
  NSData *digest = ALNHMACSHA256(prefixData, self.secretData);
  if ([digest length] == 0) {
    return @"";
  }
  return ALNBase64URLFromData(digest);
}

- (NSString *)encodeSessionDictionary:(NSDictionary *)session {
  if ([self.secretData length] == 0) {
    return nil;
  }
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

  NSString *payloadPart = ALNBase64URLFromData(plaintext);
  NSString *prefix = [NSString stringWithFormat:@"%@.%@", ALNSessionVersion, payloadPart];
  NSString *signature = [self signatureForPrefix:prefix];
  if ([signature length] == 0) {
    return nil;
  }
  return [NSString stringWithFormat:@"%@.%@", prefix, signature];
}

- (nullable NSMutableDictionary *)decodeSessionToken:(NSString *)token {
  if ([self.secretData length] == 0) {
    return nil;
  }
  NSArray *parts = [token componentsSeparatedByString:@"."];
  if ([parts count] != 3) {
    return nil;
  }
  if (![parts[0] isEqualToString:ALNSessionVersion]) {
    return nil;
  }

  NSString *prefix = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
  NSString *expectedSignature = [self signatureForPrefix:prefix];
  NSData *expectedSignatureData = ALNDataFromBase64URL(expectedSignature);
  NSData *providedSignatureData = ALNDataFromBase64URL(parts[2]);
  if ([expectedSignatureData length] == 0 || [providedSignatureData length] == 0 ||
      !ALNConstantTimeDataEqual(expectedSignatureData, providedSignatureData)) {
    return nil;
  }

  NSData *plaintext = ALNDataFromBase64URL(parts[1]);
  if ([plaintext length] == 0) {
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
