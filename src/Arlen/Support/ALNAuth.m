#import "ALNAuth.h"

#import <openssl/evp.h>
#import <openssl/hmac.h>

#import "ALNContext.h"
#import "ALNJSONSerialization.h"
#import "ALNRequest.h"

NSString *const ALNAuthErrorDomain = @"Arlen.Auth.Error";

static NSError *ALNAuthError(ALNAuthErrorCode code, NSString *message) {
  return [NSError errorWithDomain:ALNAuthErrorDomain
                             code:code
                         userInfo:@{
                           NSLocalizedDescriptionKey : message ?: @"authentication failed",
                         }];
}

static NSData *ALNBase64URLDecode(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return nil;
  }

  NSString *normalized = [[value stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
      stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
  NSUInteger remainder = [normalized length] % 4;
  if (remainder == 2) {
    normalized = [normalized stringByAppendingString:@"=="];
  } else if (remainder == 3) {
    normalized = [normalized stringByAppendingString:@"="];
  } else if (remainder != 0) {
    return nil;
  }

  return [[NSData alloc] initWithBase64EncodedString:normalized
                                             options:0];
}

static BOOL ALNConstantTimeEquals(NSData *lhs, NSData *rhs) {
  if ([lhs length] != [rhs length]) {
    return NO;
  }
  const uint8_t *l = [lhs bytes];
  const uint8_t *r = [rhs bytes];
  uint8_t diff = 0;
  for (NSUInteger idx = 0; idx < [lhs length]; idx++) {
    diff |= (l[idx] ^ r[idx]);
  }
  return diff == 0;
}

static NSDictionary *ALNJSONObjectFromBase64URLPart(NSString *part) {
  NSData *decoded = ALNBase64URLDecode(part);
  if (decoded == nil) {
    return nil;
  }
  NSError *error = nil;
  id object = [ALNJSONSerialization JSONObjectWithData:decoded options:0 error:&error];
  if (error != nil || ![object isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  return object;
}

static NSArray *ALNNormalizedUniqueStringsFromArray(NSArray *values) {
  NSMutableArray *out = [NSMutableArray array];
  for (id value in values ?: @[]) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *trimmed = [(NSString *)value
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0 || [out containsObject:trimmed]) {
      continue;
    }
    [out addObject:trimmed];
  }
  return [NSArray arrayWithArray:out];
}

static NSArray *ALNScopesFromScopeString(NSString *scopeString) {
  if (![scopeString isKindOfClass:[NSString class]] || [scopeString length] == 0) {
    return @[];
  }
  NSArray *parts = [scopeString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ALNNormalizedUniqueStringsFromArray(parts);
}

static BOOL ALNJWTAudienceMatches(id audienceClaim, NSString *expectedAudience) {
  if ([expectedAudience length] == 0) {
    return YES;
  }
  if ([audienceClaim isKindOfClass:[NSString class]]) {
    return [audienceClaim isEqualToString:expectedAudience];
  }
  if ([audienceClaim isKindOfClass:[NSArray class]]) {
    for (id candidate in (NSArray *)audienceClaim) {
      if ([candidate isKindOfClass:[NSString class]] &&
          [candidate isEqualToString:expectedAudience]) {
        return YES;
      }
    }
  }
  return NO;
}

static BOOL ALNHasAllValues(NSArray *available, NSArray *required) {
  NSSet *availableSet = [NSSet setWithArray:available ?: @[]];
  for (id value in required ?: @[]) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    if (![availableSet containsObject:value]) {
      return NO;
    }
  }
  return YES;
}

@implementation ALNAuth

+ (NSString *)bearerTokenFromAuthorizationHeader:(NSString *)authorizationHeader
                                           error:(NSError **)error {
  if (![authorizationHeader isKindOfClass:[NSString class]] ||
      [authorizationHeader length] == 0) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorMissingBearerToken, @"Missing bearer token");
    }
    return nil;
  }

  NSString *trimmed =
      [authorizationHeader stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] == 0) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorMissingBearerToken, @"Missing bearer token");
    }
    return nil;
  }

  NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  NSMutableArray *compact = [NSMutableArray array];
  for (NSString *part in parts) {
    if ([part length] > 0) {
      [compact addObject:part];
    }
  }
  if ([compact count] != 2 || ![[compact[0] lowercaseString] isEqualToString:@"bearer"]) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorInvalidAuthorizationHeader, @"Invalid Authorization header");
    }
    return nil;
  }
  return compact[1];
}

+ (NSDictionary *)verifyJWTToken:(NSString *)token
                          secret:(NSString *)secret
                          issuer:(NSString *)issuer
                        audience:(NSString *)audience
                           error:(NSError **)error {
  if (![token isKindOfClass:[NSString class]] || [token length] == 0) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorInvalidTokenFormat, @"Invalid JWT token");
    }
    return nil;
  }
  if (![secret isKindOfClass:[NSString class]] || [secret length] == 0) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorMissingVerifierSecret, @"Missing JWT verifier secret");
    }
    return nil;
  }

  NSArray *parts = [token componentsSeparatedByString:@"."];
  if ([parts count] != 3) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorInvalidTokenFormat, @"Invalid JWT token format");
    }
    return nil;
  }

  NSString *headerPart = parts[0];
  NSString *payloadPart = parts[1];
  NSString *signaturePart = parts[2];

  NSDictionary *header = ALNJSONObjectFromBase64URLPart(headerPart);
  if (header == nil) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorInvalidTokenHeader, @"Invalid JWT header");
    }
    return nil;
  }

  NSString *alg = [header[@"alg"] isKindOfClass:[NSString class]] ? header[@"alg"] : @"";
  if (![alg isEqualToString:@"HS256"]) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorUnsupportedAlgorithm, @"Only HS256 tokens are supported");
    }
    return nil;
  }

  NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerPart, payloadPart];
  NSData *signingBytes = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
  NSData *secretData = [secret dataUsingEncoding:NSUTF8StringEncoding];

  unsigned int digestLength = EVP_MAX_MD_SIZE;
  unsigned char digest[EVP_MAX_MD_SIZE];
  unsigned char *hmac = HMAC(EVP_sha256(), [secretData bytes], (int)[secretData length],
                             [signingBytes bytes], [signingBytes length], digest,
                             &digestLength);
  if (hmac == NULL || digestLength == 0) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorInvalidSignature, @"Failed to verify JWT signature");
    }
    return nil;
  }

  NSData *expectedSignature = [NSData dataWithBytes:digest length:digestLength];
  NSData *providedSignature = ALNBase64URLDecode(signaturePart);
  if (providedSignature == nil ||
      !ALNConstantTimeEquals(expectedSignature, providedSignature)) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorInvalidSignature, @"Invalid JWT signature");
    }
    return nil;
  }

  NSDictionary *claims = ALNJSONObjectFromBase64URLPart(payloadPart);
  if (claims == nil) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorInvalidPayload, @"Invalid JWT payload");
    }
    return nil;
  }

  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  id exp = claims[@"exp"];
  if ([exp respondsToSelector:@selector(doubleValue)] &&
      [exp doubleValue] <= now) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorTokenExpired, @"JWT token has expired");
    }
    return nil;
  }

  id nbf = claims[@"nbf"];
  if ([nbf respondsToSelector:@selector(doubleValue)] &&
      [nbf doubleValue] > now) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorTokenNotActive, @"JWT token is not active yet");
    }
    return nil;
  }

  if ([issuer length] > 0) {
    NSString *claimIssuer = [claims[@"iss"] isKindOfClass:[NSString class]] ? claims[@"iss"] : @"";
    if (![claimIssuer isEqualToString:issuer]) {
      if (error != NULL) {
        *error = ALNAuthError(ALNAuthErrorInvalidIssuer, @"JWT issuer does not match");
      }
      return nil;
    }
  }

  if (![self.class verifyAudienceForClaims:claims expectedAudience:audience error:error]) {
    return nil;
  }

  return claims;
}

+ (BOOL)verifyAudienceForClaims:(NSDictionary *)claims
               expectedAudience:(NSString *)audience
                          error:(NSError **)error {
  if ([audience length] == 0) {
    return YES;
  }
  if (ALNJWTAudienceMatches(claims[@"aud"], audience)) {
    return YES;
  }
  if (error != NULL) {
    *error = ALNAuthError(ALNAuthErrorInvalidAudience, @"JWT audience does not match");
  }
  return NO;
}

+ (BOOL)authenticateContext:(ALNContext *)context
                authConfig:(NSDictionary *)authConfig
                     error:(NSError **)error {
  if (context == nil) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorInvalidPayload, @"Missing context");
    }
    return NO;
  }

  if ([context.stash[ALNContextAuthClaimsStashKey] isKindOfClass:[NSDictionary class]]) {
    return YES;
  }

  NSString *authorization =
      [context.request.headers[@"authorization"] isKindOfClass:[NSString class]]
          ? context.request.headers[@"authorization"]
          : nil;
  NSError *headerError = nil;
  NSString *token = [self bearerTokenFromAuthorizationHeader:authorization error:&headerError];
  if ([token length] == 0) {
    if (error != NULL) {
      *error = headerError ?: ALNAuthError(ALNAuthErrorMissingBearerToken, @"Missing bearer token");
    }
    return NO;
  }

  NSString *secret = [authConfig[@"bearerSecret"] isKindOfClass:[NSString class]]
                         ? authConfig[@"bearerSecret"]
                         : @"";
  if ([secret length] == 0) {
    if (error != NULL) {
      *error = ALNAuthError(ALNAuthErrorMissingVerifierSecret, @"Missing auth.bearerSecret");
    }
    return NO;
  }

  NSString *issuer = [authConfig[@"issuer"] isKindOfClass:[NSString class]] ? authConfig[@"issuer"] : nil;
  NSString *audience = [authConfig[@"audience"] isKindOfClass:[NSString class]] ? authConfig[@"audience"] : nil;
  NSDictionary *claims = [self verifyJWTToken:token
                                       secret:secret
                                       issuer:issuer
                                     audience:audience
                                        error:error];
  if (claims == nil) {
    return NO;
  }
  [self applyClaims:claims toContext:context];
  return YES;
}

+ (void)applyClaims:(NSDictionary *)claims toContext:(ALNContext *)context {
  if (context == nil || ![claims isKindOfClass:[NSDictionary class]]) {
    return;
  }

  NSArray *scopes = [self scopesFromClaims:claims];
  NSArray *roles = [self rolesFromClaims:claims];
  NSString *subject = [claims[@"sub"] isKindOfClass:[NSString class]] ? claims[@"sub"] : @"";

  context.stash[ALNContextAuthClaimsStashKey] = claims;
  context.stash[ALNContextAuthScopesStashKey] = scopes;
  context.stash[ALNContextAuthRolesStashKey] = roles;
  if ([subject length] > 0) {
    context.stash[ALNContextAuthSubjectStashKey] = subject;
  }
}

+ (NSArray *)scopesFromClaims:(NSDictionary *)claims {
  NSMutableArray *combined = [NSMutableArray array];
  NSArray *stringScopes = ALNScopesFromScopeString(claims[@"scope"]);
  [combined addObjectsFromArray:stringScopes];

  if ([claims[@"scopes"] isKindOfClass:[NSArray class]]) {
    NSArray *scopesArray = ALNNormalizedUniqueStringsFromArray(claims[@"scopes"]);
    for (NSString *scope in scopesArray) {
      if (![combined containsObject:scope]) {
        [combined addObject:scope];
      }
    }
  }
  return [NSArray arrayWithArray:combined];
}

+ (NSArray *)rolesFromClaims:(NSDictionary *)claims {
  NSMutableArray *combined = [NSMutableArray array];

  id singleRole = claims[@"role"];
  if ([singleRole isKindOfClass:[NSString class]] && [singleRole length] > 0) {
    [combined addObject:singleRole];
  }

  if ([claims[@"roles"] isKindOfClass:[NSArray class]]) {
    NSArray *rolesArray = ALNNormalizedUniqueStringsFromArray(claims[@"roles"]);
    for (NSString *role in rolesArray) {
      if (![combined containsObject:role]) {
        [combined addObject:role];
      }
    }
  }
  return [NSArray arrayWithArray:combined];
}

+ (BOOL)context:(ALNContext *)context hasRequiredScopes:(NSArray *)scopes {
  NSArray *required = ALNNormalizedUniqueStringsFromArray(scopes);
  if ([required count] == 0) {
    return YES;
  }
  id current = context.stash[ALNContextAuthScopesStashKey];
  NSArray *available = [current isKindOfClass:[NSArray class]] ? current : @[];
  return ALNHasAllValues(available, required);
}

+ (BOOL)context:(ALNContext *)context hasRequiredRoles:(NSArray *)roles {
  NSArray *required = ALNNormalizedUniqueStringsFromArray(roles);
  if ([required count] == 0) {
    return YES;
  }
  id current = context.stash[ALNContextAuthRolesStashKey];
  NSArray *available = [current isKindOfClass:[NSArray class]] ? current : @[];
  return ALNHasAllValues(available, required);
}

@end
