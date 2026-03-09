#import "ALNOIDCClient.h"

#import <openssl/bn.h>
#import <openssl/evp.h>
#import <openssl/rsa.h>

#import "ALNAuth.h"
#import "ALNJSONSerialization.h"
#import "ALNSecurityPrimitives.h"

NSString *const ALNOIDCClientErrorDomain = @"Arlen.OIDCClient.Error";

static NSError *ALNOIDCClientError(ALNOIDCClientErrorCode code, NSString *message) {
  return [NSError errorWithDomain:ALNOIDCClientErrorDomain
                             code:code
                         userInfo:@{
                           NSLocalizedDescriptionKey : message ?: @"oidc client failed",
                         }];
}

static NSString *ALNOIDCTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([trimmed length] > 0) ? trimmed : nil;
}

static NSArray *ALNOIDCNormalizedStringArray(id rawValues) {
  NSMutableArray *values = [NSMutableArray array];
  NSArray *source = [rawValues isKindOfClass:[NSArray class]] ? rawValues : @[];
  for (id value in source) {
    NSString *trimmed = ALNOIDCTrimmedString(value);
    if ([trimmed length] == 0 || [values containsObject:trimmed]) {
      continue;
    }
    [values addObject:trimmed];
  }
  return [NSArray arrayWithArray:values];
}

static NSString *ALNOIDCPercentEscape(NSString *value) {
  NSString *trimmed = ALNOIDCTrimmedString(value);
  if ([trimmed length] == 0) {
    return @"";
  }
  NSMutableCharacterSet *allowed =
      [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
  [allowed removeCharactersInString:@":#[]@!$&'()*+,;=%/?"];
  return [trimmed stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: trimmed;
}

static NSDictionary *ALNOIDCJSONObjectFromJWTPart(NSString *part) {
  NSData *data = ALNDataFromBase64URLString(part);
  if (data == nil) {
    return nil;
  }
  NSError *error = nil;
  id object = [ALNJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error != nil || ![object isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  return object;
}

static NSArray *ALNOIDCScopesFromScopeString(NSString *scopeString) {
  NSString *trimmed = ALNOIDCTrimmedString(scopeString);
  if ([trimmed length] == 0) {
    return @[];
  }
  NSArray *parts =
      [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSMutableArray *scopes = [NSMutableArray array];
  for (id value in parts) {
    NSString *scope = ALNOIDCTrimmedString(value);
    if ([scope length] == 0 || [scopes containsObject:scope]) {
      continue;
    }
    [scopes addObject:scope];
  }
  return [NSArray arrayWithArray:scopes];
}

static BOOL ALNOIDCAudienceMatches(id audienceClaim, NSString *expectedAudience) {
  NSString *trimmed = ALNOIDCTrimmedString(expectedAudience);
  if ([trimmed length] == 0) {
    return YES;
  }
  if ([audienceClaim isKindOfClass:[NSString class]]) {
    return [audienceClaim isEqualToString:trimmed];
  }
  if ([audienceClaim isKindOfClass:[NSArray class]]) {
    for (id candidate in (NSArray *)audienceClaim) {
      if ([candidate isKindOfClass:[NSString class]] && [candidate isEqualToString:trimmed]) {
        return YES;
      }
    }
  }
  return NO;
}

static BOOL ALNOIDCValidateStandardClaims(NSDictionary *claims,
                                          NSString *issuer,
                                          NSString *audience,
                                          NSDate *referenceDate,
                                          NSError **error) {
  if (![claims isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidIDTokenClaims,
                                  @"ID token claims payload is invalid");
    }
    return NO;
  }

  NSTimeInterval now = [(referenceDate ?: [NSDate date]) timeIntervalSince1970];

  id exp = claims[@"exp"];
  if ([exp respondsToSelector:@selector(doubleValue)] && [exp doubleValue] <= now) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidIDTokenClaims,
                                  @"ID token has expired");
    }
    return NO;
  }

  id nbf = claims[@"nbf"];
  if ([nbf respondsToSelector:@selector(doubleValue)] && [nbf doubleValue] > now) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidIDTokenClaims,
                                  @"ID token is not active yet");
    }
    return NO;
  }

  NSString *expectedIssuer = ALNOIDCTrimmedString(issuer);
  if ([expectedIssuer length] > 0) {
    NSString *claimIssuer = ALNOIDCTrimmedString(claims[@"iss"]);
    if (![claimIssuer isEqualToString:expectedIssuer]) {
      if (error != NULL) {
        *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidIDTokenClaims,
                                    @"ID token issuer does not match");
      }
      return NO;
    }
  }

  NSString *expectedAudience = ALNOIDCTrimmedString(audience);
  if ([expectedAudience length] > 0 &&
      !ALNOIDCAudienceMatches(claims[@"aud"], expectedAudience)) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidIDTokenClaims,
                                  @"ID token audience does not match");
    }
    return NO;
  }

  NSString *subject = ALNOIDCTrimmedString(claims[@"sub"]);
  if ([subject length] == 0) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorMissingIdentitySubject,
                                  @"ID token subject is required");
    }
    return NO;
  }

  return YES;
}

static BOOL ALNOIDCIsJWKSFresh(NSDictionary *jwksDocument,
                               NSDictionary *providerConfiguration,
                               NSDate *referenceDate,
                               NSError **error) {
  if (![jwksDocument isKindOfClass:[NSDictionary class]]) {
    return YES;
  }

  NSTimeInterval now = [(referenceDate ?: [NSDate date]) timeIntervalSince1970];
  id expiresAt = jwksDocument[@"expires_at"];
  if ([expiresAt respondsToSelector:@selector(doubleValue)] &&
      [expiresAt doubleValue] > 0.0 &&
      [expiresAt doubleValue] < now) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorJWKSExpired, @"JWKS document has expired");
    }
    return NO;
  }

  NSUInteger maxAgeSeconds = 0;
  id maxAge = providerConfiguration[@"jwksMaxAgeSeconds"];
  if ([maxAge respondsToSelector:@selector(integerValue)] && [maxAge integerValue] > 0) {
    maxAgeSeconds = (NSUInteger)[maxAge integerValue];
  }
  if (maxAgeSeconds == 0) {
    return YES;
  }

  id fetchedAt = jwksDocument[@"fetched_at"];
  if ([fetchedAt respondsToSelector:@selector(doubleValue)]) {
    NSTimeInterval age = now - [fetchedAt doubleValue];
    if (age < 0.0 || age > (NSTimeInterval)maxAgeSeconds) {
      if (error != NULL) {
        *error = ALNOIDCClientError(ALNOIDCClientErrorJWKSExpired,
                                    @"JWKS document age exceeds configured policy");
      }
      return NO;
    }
  }

  return YES;
}

static NSDictionary *ALNOIDCFindJWKForHeader(NSDictionary *header, NSDictionary *jwksDocument) {
  NSArray *keys = [jwksDocument[@"keys"] isKindOfClass:[NSArray class]] ? jwksDocument[@"keys"] : @[];
  NSString *kid = ALNOIDCTrimmedString(header[@"kid"]);
  NSString *alg = ALNOIDCTrimmedString(header[@"alg"]);
  NSDictionary *fallback = nil;
  for (id value in keys) {
    if (![value isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *candidate = (NSDictionary *)value;
    NSString *candidateKTY = ALNOIDCTrimmedString(candidate[@"kty"]);
    if ([candidateKTY length] == 0) {
      continue;
    }
    if ([kid length] > 0) {
      NSString *candidateKid = ALNOIDCTrimmedString(candidate[@"kid"]);
      if (![candidateKid isEqualToString:kid]) {
        continue;
      }
      return candidate;
    }

    if (fallback == nil) {
      fallback = candidate;
    }

    NSString *candidateAlg = ALNOIDCTrimmedString(candidate[@"alg"]);
    if ([alg length] > 0 && [candidateAlg isEqualToString:alg]) {
      return candidate;
    }
  }
  return fallback;
}

static EVP_PKEY *ALNOIDCNewRSAPublicKeyFromJWK(NSDictionary *jwk, NSError **error) {
  NSString *kty = ALNOIDCTrimmedString(jwk[@"kty"]);
  if (![kty isEqualToString:@"RSA"]) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorUnsupportedJWKType,
                                  @"Only RSA JWK keys are currently supported");
    }
    return NULL;
  }

  NSData *modulusData = ALNDataFromBase64URLString(ALNOIDCTrimmedString(jwk[@"n"]));
  NSData *exponentData = ALNDataFromBase64URLString(ALNOIDCTrimmedString(jwk[@"e"]));
  if ([modulusData length] == 0 || [exponentData length] == 0) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorJWKMalformed,
                                  @"RSA JWK is missing modulus or exponent data");
    }
    return NULL;
  }

  BIGNUM *modulus = BN_bin2bn([modulusData bytes], (int)[modulusData length], NULL);
  BIGNUM *exponent = BN_bin2bn([exponentData bytes], (int)[exponentData length], NULL);
  RSA *rsa = RSA_new();
  EVP_PKEY *pkey = NULL;

  if (modulus == NULL || exponent == NULL || rsa == NULL ||
      RSA_set0_key(rsa, modulus, exponent, NULL) != 1) {
    BN_free(modulus);
    BN_free(exponent);
    RSA_free(rsa);
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorJWKMalformed,
                                  @"Failed constructing RSA verification key from JWK");
    }
    return NULL;
  }

  pkey = EVP_PKEY_new();
  if (pkey == NULL || EVP_PKEY_assign_RSA(pkey, rsa) != 1) {
    EVP_PKEY_free(pkey);
    RSA_free(rsa);
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorJWKMalformed,
                                  @"Failed assigning RSA key material for verification");
    }
    return NULL;
  }

  return pkey;
}

static BOOL ALNOIDCVerifyRS256Signature(NSString *signingInput,
                                        NSString *encodedSignature,
                                        NSDictionary *jwk,
                                        NSError **error) {
  NSData *signingData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];
  NSData *signatureData = ALNDataFromBase64URLString(encodedSignature);
  if ([signingData length] == 0 || [signatureData length] == 0) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidIDTokenSignature,
                                  @"ID token signature payload is malformed");
    }
    return NO;
  }

  EVP_PKEY *publicKey = ALNOIDCNewRSAPublicKeyFromJWK(jwk, error);
  if (publicKey == NULL) {
    return NO;
  }

  EVP_MD_CTX *ctx = EVP_MD_CTX_new();
  BOOL verified =
      (ctx != NULL &&
       EVP_DigestVerifyInit(ctx, NULL, EVP_sha256(), NULL, publicKey) == 1 &&
       EVP_DigestVerifyUpdate(ctx, [signingData bytes], [signingData length]) == 1 &&
       EVP_DigestVerifyFinal(ctx, [signatureData bytes], [signatureData length]) == 1);

  EVP_MD_CTX_free(ctx);
  EVP_PKEY_free(publicKey);

  if (!verified && error != NULL && *error == NULL) {
    *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidIDTokenSignature,
                                @"ID token signature verification failed");
  }
  return verified;
}

static NSDictionary *ALNOIDCVerifiedClaimsFromJWT(NSString *token,
                                                   NSDictionary *providerConfiguration,
                                                   NSString *expectedNonce,
                                                   NSDictionary *jwksDocument,
                                                   NSDate *referenceDate,
                                                   NSError **error) {
  NSString *trimmedToken = ALNOIDCTrimmedString(token);
  if ([trimmedToken length] == 0) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorMissingIDToken, @"Missing ID token");
    }
    return nil;
  }

  NSArray *parts = [trimmedToken componentsSeparatedByString:@"."];
  if ([parts count] != 3) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidIDTokenHeader,
                                  @"ID token format is invalid");
    }
    return nil;
  }

  NSDictionary *header = ALNOIDCJSONObjectFromJWTPart(parts[0]);
  NSDictionary *claims = ALNOIDCJSONObjectFromJWTPart(parts[1]);
  if (header == nil || claims == nil) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidIDTokenHeader,
                                  @"ID token header or payload is invalid JSON");
    }
    return nil;
  }

  NSString *algorithm = ALNOIDCTrimmedString(header[@"alg"]);
  NSString *issuer = ALNOIDCTrimmedString(providerConfiguration[@"issuer"]);
  NSString *audience =
      ALNOIDCTrimmedString(providerConfiguration[@"audience"]) ?:
      ALNOIDCTrimmedString(providerConfiguration[@"clientID"]);

  if ([algorithm isEqualToString:@"HS256"]) {
    NSString *sharedSecret =
        ALNOIDCTrimmedString(providerConfiguration[@"idTokenSharedSecret"]) ?:
        ALNOIDCTrimmedString(providerConfiguration[@"clientSecret"]);
    if ([sharedSecret length] == 0) {
      if (error != NULL) {
        *error = ALNOIDCClientError(ALNOIDCClientErrorMissingVerificationKey,
                                    @"HS256 ID token verification requires a shared secret");
      }
      return nil;
    }
    NSError *jwtError = nil;
    NSDictionary *verified = [ALNAuth verifyJWTToken:trimmedToken
                                              secret:sharedSecret
                                              issuer:issuer
                                            audience:audience
                                               error:&jwtError];
    if (verified == nil) {
      if (error != NULL) {
        ALNOIDCClientErrorCode code = ALNOIDCClientErrorInvalidIDTokenClaims;
        if (jwtError.code == ALNAuthErrorInvalidSignature) {
          code = ALNOIDCClientErrorInvalidIDTokenSignature;
        }
        *error = ALNOIDCClientError(code,
                                    jwtError.localizedDescription ?: @"ID token verification failed");
      }
      return nil;
    }
    claims = verified;
  } else if ([algorithm isEqualToString:@"RS256"]) {
    NSError *jwksError = nil;
    if (!ALNOIDCIsJWKSFresh(jwksDocument, providerConfiguration, referenceDate, &jwksError)) {
      if (error != NULL) {
        *error = jwksError;
      }
      return nil;
    }

    NSDictionary *jwk = ALNOIDCFindJWKForHeader(header, jwksDocument ?: @{});
    if (jwk == nil) {
      if (error != NULL) {
        *error = ALNOIDCClientError(ALNOIDCClientErrorJWKNotFound,
                                    @"No verification key matches the ID token header");
      }
      return nil;
    }

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", parts[0], parts[1]];
    NSError *signatureError = nil;
    if (!ALNOIDCVerifyRS256Signature(signingInput, parts[2], jwk, &signatureError)) {
      if (error != NULL) {
        *error = signatureError ?: ALNOIDCClientError(ALNOIDCClientErrorInvalidIDTokenSignature,
                                                      @"ID token signature verification failed");
      }
      return nil;
    }

    if (!ALNOIDCValidateStandardClaims(claims, issuer, audience, referenceDate, error)) {
      return nil;
    }
  } else {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorUnsupportedIDTokenAlgorithm,
                                  @"Only HS256 and RS256 ID tokens are supported");
    }
    return nil;
  }

  NSString *subject = ALNOIDCTrimmedString(claims[@"sub"]);
  if ([subject length] == 0) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorMissingIdentitySubject,
                                  @"ID token subject is required");
    }
    return nil;
  }

  NSString *nonce = ALNOIDCTrimmedString(expectedNonce);
  if ([nonce length] > 0) {
    NSString *claimNonce = ALNOIDCTrimmedString(claims[@"nonce"]);
    if (![claimNonce isEqualToString:nonce]) {
      if (error != NULL) {
        *error = ALNOIDCClientError(ALNOIDCClientErrorNonceMismatch,
                                    @"ID token nonce does not match the authorization request");
      }
      return nil;
    }
  }

  return claims;
}

static NSString *ALNOIDCURLWithQueryParameters(NSString *baseURL, NSArray *orderedPairs) {
  NSString *trimmedBase = ALNOIDCTrimmedString(baseURL);
  if ([trimmedBase length] == 0) {
    return nil;
  }

  NSMutableArray *components = [NSMutableArray array];
  for (NSDictionary *entry in orderedPairs ?: @[]) {
    NSString *name = ALNOIDCTrimmedString(entry[@"name"]);
    if ([name length] == 0) {
      continue;
    }
    NSString *value = [entry[@"value"] isKindOfClass:[NSString class]] ? entry[@"value"] : @"";
    [components addObject:[NSString stringWithFormat:@"%@=%@",
                                                     ALNOIDCPercentEscape(name),
                                                     ALNOIDCPercentEscape(value)]];
  }

  NSString *separator = [trimmedBase containsString:@"?"] ? @"&" : @"?";
  if ([components count] == 0) {
    return trimmedBase;
  }
  return [NSString stringWithFormat:@"%@%@%@",
                                    trimmedBase,
                                    separator,
                                    [components componentsJoinedByString:@"&"]];
}

@implementation ALNOIDCClient

+ (NSDictionary *)authorizationRequestForProviderConfiguration:(NSDictionary *)providerConfiguration
                                                   redirectURI:(NSString *)redirectURI
                                                        scopes:(NSArray *)scopes
                                                 referenceDate:(NSDate *)referenceDate
                                                         error:(NSError **)error {
  NSString *authorizationEndpoint =
      ALNOIDCTrimmedString(providerConfiguration[@"authorizationEndpoint"]);
  NSString *clientID = ALNOIDCTrimmedString(providerConfiguration[@"clientID"]);
  NSString *trimmedRedirectURI = ALNOIDCTrimmedString(redirectURI);
  if ([authorizationEndpoint length] == 0 || [clientID length] == 0 ||
      [trimmedRedirectURI length] == 0) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidArgument,
                                  @"Authorization request requires endpoint, client ID, and redirect URI");
    }
    return nil;
  }

  NSData *stateData = ALNSecureRandomData(24);
  NSData *nonceData = ALNSecureRandomData(24);
  NSData *verifierData = ALNSecureRandomData(32);
  if ([stateData length] == 0 || [nonceData length] == 0 || [verifierData length] == 0) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorRandomGenerationFailed,
                                  @"Failed generating PKCE/state material");
    }
    return nil;
  }

  NSString *state = ALNBase64URLStringFromData(stateData);
  NSString *nonce = ALNBase64URLStringFromData(nonceData);
  NSString *codeVerifier = ALNBase64URLStringFromData(verifierData);
  NSData *challengeDigest = ALNSHA256([codeVerifier dataUsingEncoding:NSUTF8StringEncoding]);
  NSString *codeChallenge = ALNBase64URLStringFromData(challengeDigest);

  NSString *protocolValue = ALNOIDCTrimmedString(providerConfiguration[@"protocol"]);
  NSString *protocol = [(protocolValue ?: @"oidc") lowercaseString];
  NSArray *requestedScopes = ALNOIDCNormalizedStringArray(scopes);
  if ([requestedScopes count] == 0) {
    requestedScopes = ALNOIDCNormalizedStringArray(providerConfiguration[@"defaultScopes"]);
  }
  if ([requestedScopes count] == 0 && ![protocol isEqualToString:@"oauth2"]) {
    requestedScopes = @[ @"openid" ];
  }

  NSMutableArray *queryPairs = [NSMutableArray arrayWithArray:@[
    @{ @"name" : @"response_type", @"value" : @"code" },
    @{ @"name" : @"client_id", @"value" : clientID },
    @{ @"name" : @"redirect_uri", @"value" : trimmedRedirectURI },
    @{ @"name" : @"state", @"value" : state ?: @"" },
    @{ @"name" : @"code_challenge", @"value" : codeChallenge ?: @"" },
    @{ @"name" : @"code_challenge_method", @"value" : @"S256" },
  ]];
  if ([requestedScopes count] > 0) {
    [queryPairs addObject:@{
      @"name" : @"scope",
      @"value" : [requestedScopes componentsJoinedByString:@" "],
    }];
  }
  if (![protocol isEqualToString:@"oauth2"]) {
    [queryPairs addObject:@{ @"name" : @"nonce", @"value" : nonce ?: @"" }];
  }

  NSDictionary *extraParams =
      [providerConfiguration[@"extraAuthorizationParameters"] isKindOfClass:[NSDictionary class]]
          ? providerConfiguration[@"extraAuthorizationParameters"]
          : @{};
  NSArray *sortedExtraKeys = [[extraParams allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (id rawKey in sortedExtraKeys) {
    NSString *name = ALNOIDCTrimmedString(rawKey);
    NSString *value = ALNOIDCTrimmedString(extraParams[rawKey]);
    if ([name length] == 0 || [value length] == 0) {
      continue;
    }
    [queryPairs addObject:@{ @"name" : name, @"value" : value }];
  }

  NSString *authorizationURL = ALNOIDCURLWithQueryParameters(authorizationEndpoint, queryPairs);
  NSDate *now = referenceDate ?: [NSDate date];
  return @{
    @"authorizationURL" : authorizationURL ?: @"",
    @"state" : state ?: @"",
    @"nonce" : nonce ?: @"",
    @"codeVerifier" : codeVerifier ?: @"",
    @"codeChallenge" : codeChallenge ?: @"",
    @"codeChallengeMethod" : @"S256",
    @"redirectURI" : trimmedRedirectURI,
    @"scopes" : requestedScopes ?: @[],
    @"issuedAt" : @([now timeIntervalSince1970]),
  };
}

+ (NSDictionary *)validateAuthorizationCallbackParameters:(NSDictionary *)parameters
                                            expectedState:(NSString *)expectedState
                                              issuedAtDate:(NSDate *)issuedAtDate
                                             maxAgeSeconds:(NSUInteger)maxAgeSeconds
                                                     error:(NSError **)error {
  NSString *providerError = ALNOIDCTrimmedString(parameters[@"error"]);
  if ([providerError length] > 0) {
    NSString *description =
        ALNOIDCTrimmedString(parameters[@"error_description"]) ?: providerError;
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorCallbackErrorResponse,
                                  [NSString stringWithFormat:@"Provider rejected authorization callback: %@",
                                                             description]);
    }
    return nil;
  }

  NSString *state = ALNOIDCTrimmedString(parameters[@"state"]);
  NSString *expected = ALNOIDCTrimmedString(expectedState);
  if ([expected length] == 0 || ![state isEqualToString:expected]) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorCallbackStateMismatch,
                                  @"Authorization callback state does not match");
    }
    return nil;
  }

  if (maxAgeSeconds > 0 && issuedAtDate != nil) {
    NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:issuedAtDate];
    if (age < 0.0 || age > (NSTimeInterval)maxAgeSeconds) {
      if (error != NULL) {
        *error = ALNOIDCClientError(ALNOIDCClientErrorCallbackExpired,
                                    @"Authorization callback exceeded the configured age window");
      }
      return nil;
    }
  }

  NSString *code = ALNOIDCTrimmedString(parameters[@"code"]);
  if ([code length] == 0) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorMissingAuthorizationCode,
                                  @"Authorization callback is missing the code parameter");
    }
    return nil;
  }

  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"state"] = state ?: @"";
  result[@"code"] = code ?: @"";
  NSString *scope = ALNOIDCTrimmedString(parameters[@"scope"]);
  if ([scope length] > 0) {
    result[@"scopes"] = ALNOIDCScopesFromScopeString(scope);
  }
  NSString *issuer = ALNOIDCTrimmedString(parameters[@"iss"]);
  if ([issuer length] > 0) {
    result[@"issuer"] = issuer;
  }
  return result;
}

+ (NSDictionary *)tokenExchangeRequestForProviderConfiguration:(NSDictionary *)providerConfiguration
                                             authorizationCode:(NSString *)authorizationCode
                                                   redirectURI:(NSString *)redirectURI
                                                  codeVerifier:(NSString *)codeVerifier
                                                         error:(NSError **)error {
  NSString *tokenEndpoint = ALNOIDCTrimmedString(providerConfiguration[@"tokenEndpoint"]);
  NSString *clientID = ALNOIDCTrimmedString(providerConfiguration[@"clientID"]);
  NSString *code = ALNOIDCTrimmedString(authorizationCode);
  NSString *trimmedRedirectURI = ALNOIDCTrimmedString(redirectURI);
  NSString *trimmedVerifier = ALNOIDCTrimmedString(codeVerifier);
  if ([tokenEndpoint length] == 0 || [clientID length] == 0 ||
      [code length] == 0 || [trimmedRedirectURI length] == 0 ||
      [trimmedVerifier length] == 0) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidArgument,
                                  @"Token exchange requires endpoint, client ID, code, redirect URI, and verifier");
    }
    return nil;
  }

  NSString *clientSecret = ALNOIDCTrimmedString(providerConfiguration[@"clientSecret"]);
  NSString *authMethodValue =
      ALNOIDCTrimmedString(providerConfiguration[@"tokenEndpointAuthMethod"]);
  NSString *authMethod = [(authMethodValue ?: @"client_secret_post") lowercaseString];
  NSNumber *timeoutSeconds = [providerConfiguration[@"timeoutSeconds"] respondsToSelector:@selector(integerValue)] &&
                                     [providerConfiguration[@"timeoutSeconds"] integerValue] > 0
                                 ? @([providerConfiguration[@"timeoutSeconds"] integerValue])
                                 : @30;

  NSMutableArray *orderedPairs = [NSMutableArray arrayWithArray:@[
    @{ @"name" : @"grant_type", @"value" : @"authorization_code" },
    @{ @"name" : @"code", @"value" : code },
    @{ @"name" : @"redirect_uri", @"value" : trimmedRedirectURI },
    @{ @"name" : @"client_id", @"value" : clientID },
    @{ @"name" : @"code_verifier", @"value" : trimmedVerifier },
  ]];
  if ([clientSecret length] > 0 && ![authMethod isEqualToString:@"none"]) {
    [orderedPairs addObject:@{ @"name" : @"client_secret", @"value" : clientSecret }];
  }

  NSMutableDictionary *formParameters = [NSMutableDictionary dictionary];
  NSMutableArray *encodedPairs = [NSMutableArray array];
  NSMutableArray *redactedPairs = [NSMutableArray array];
  for (NSDictionary *entry in orderedPairs) {
    NSString *name = entry[@"name"];
    NSString *value = entry[@"value"];
    formParameters[name] = value ?: @"";
    [encodedPairs addObject:[NSString stringWithFormat:@"%@=%@",
                                                       ALNOIDCPercentEscape(name),
                                                       ALNOIDCPercentEscape(value)]];
    NSString *logValue = [name isEqualToString:@"client_secret"] ? @"[REDACTED]" : (value ?: @"");
    [redactedPairs addObject:[NSString stringWithFormat:@"%@=%@", name, logValue]];
  }

  NSString *bodyString = [encodedPairs componentsJoinedByString:@"&"];
  return @{
    @"method" : @"POST",
    @"url" : tokenEndpoint,
    @"headers" : @{
      @"accept" : @"application/json",
      @"content-type" : @"application/x-www-form-urlencoded",
    },
    @"formParameters" : formParameters,
    @"bodyString" : bodyString,
    @"timeoutSeconds" : timeoutSeconds,
    @"redactedDescription" : [NSString stringWithFormat:@"POST %@ %@", tokenEndpoint,
                                                        [redactedPairs componentsJoinedByString:@"&"]],
  };
}

+ (NSDictionary *)parseTokenResponseData:(NSData *)data error:(NSError **)error {
  NSError *jsonError = nil;
  id object = [ALNJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
  if (jsonError != nil || ![object isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidTokenResponse,
                                  @"Token endpoint response is not valid JSON");
    }
    return nil;
  }

  NSDictionary *response = (NSDictionary *)object;
  NSString *providerError = ALNOIDCTrimmedString(response[@"error"]);
  if ([providerError length] > 0) {
    NSString *message =
        ALNOIDCTrimmedString(response[@"error_description"]) ?: providerError;
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorInvalidTokenResponse,
                                  [NSString stringWithFormat:@"Token endpoint returned an error: %@",
                                                             message]);
    }
    return nil;
  }

  return response;
}

+ (NSDictionary *)verifyIDToken:(NSString *)idToken
          providerConfiguration:(NSDictionary *)providerConfiguration
                  expectedNonce:(NSString *)expectedNonce
                   jwksDocument:(NSDictionary *)jwksDocument
                  referenceDate:(NSDate *)referenceDate
                          error:(NSError **)error {
  return ALNOIDCVerifiedClaimsFromJWT(idToken,
                                      providerConfiguration ?: @{},
                                      expectedNonce,
                                      jwksDocument,
                                      referenceDate ?: [NSDate date],
                                      error);
}

+ (NSDictionary *)normalizedIdentityFromVerifiedClaims:(NSDictionary *)verifiedClaims
                                         tokenResponse:(NSDictionary *)tokenResponse
                                      userInfoResponse:(NSDictionary *)userInfoResponse
                                 providerConfiguration:(NSDictionary *)providerConfiguration
                                                 error:(NSError **)error {
  NSDictionary *claims = [verifiedClaims isKindOfClass:[NSDictionary class]] ? verifiedClaims : @{};
  NSDictionary *userInfo = [userInfoResponse isKindOfClass:[NSDictionary class]] ? userInfoResponse : @{};
  NSDictionary *token = [tokenResponse isKindOfClass:[NSDictionary class]] ? tokenResponse : @{};

  NSString *providerIdentifier =
      ALNOIDCTrimmedString(providerConfiguration[@"identifier"]) ?:
      ALNOIDCTrimmedString(providerConfiguration[@"preset"]) ?:
      @"oidc";
  NSString *providerSubject =
      ALNOIDCTrimmedString(claims[@"sub"]) ?:
      ALNOIDCTrimmedString(userInfo[@"sub"]) ?:
      ALNOIDCTrimmedString(userInfo[@"id"]) ?:
      ALNOIDCTrimmedString(token[@"sub"]);
  if ([providerSubject length] == 0) {
    if (error != NULL) {
      *error = ALNOIDCClientError(ALNOIDCClientErrorMissingIdentitySubject,
                                  @"Provider identity is missing a stable subject");
    }
    return nil;
  }

  NSString *email =
      ALNOIDCTrimmedString(claims[@"email"]) ?:
      ALNOIDCTrimmedString(userInfo[@"email"]) ?:
      ALNOIDCTrimmedString(token[@"email"]);
  NSString *name =
      ALNOIDCTrimmedString(claims[@"name"]) ?:
      ALNOIDCTrimmedString(userInfo[@"name"]) ?:
      ALNOIDCTrimmedString(token[@"name"]);
  NSString *givenName =
      ALNOIDCTrimmedString(claims[@"given_name"]) ?:
      ALNOIDCTrimmedString(userInfo[@"given_name"]);
  NSString *familyName =
      ALNOIDCTrimmedString(claims[@"family_name"]) ?:
      ALNOIDCTrimmedString(userInfo[@"family_name"]);
  NSString *preferredUsername =
      ALNOIDCTrimmedString(claims[@"preferred_username"]) ?:
      ALNOIDCTrimmedString(userInfo[@"login"]) ?:
      ALNOIDCTrimmedString(userInfo[@"preferred_username"]);
  NSString *picture =
      ALNOIDCTrimmedString(claims[@"picture"]) ?:
      ALNOIDCTrimmedString(userInfo[@"avatar_url"]) ?:
      ALNOIDCTrimmedString(userInfo[@"picture"]);

  BOOL emailVerified = NO;
  id verifiedValue = (claims[@"email_verified"] != nil) ? claims[@"email_verified"] : userInfo[@"email_verified"];
  if ([verifiedValue respondsToSelector:@selector(boolValue)]) {
    emailVerified = [verifiedValue boolValue];
  }

  NSMutableDictionary *identity = [NSMutableDictionary dictionary];
  identity[@"provider"] = providerIdentifier;
  identity[@"provider_subject"] = providerSubject;
  identity[@"claims"] = claims;
  identity[@"user_info"] = userInfo;
  if ([email length] > 0) {
    identity[@"email"] = email;
  }
  identity[@"email_verified"] = @(emailVerified);
  if ([name length] > 0) {
    identity[@"name"] = name;
  }
  if ([givenName length] > 0) {
    identity[@"given_name"] = givenName;
  }
  if ([familyName length] > 0) {
    identity[@"family_name"] = familyName;
  }
  if ([preferredUsername length] > 0) {
    identity[@"preferred_username"] = preferredUsername;
  }
  if ([picture length] > 0) {
    identity[@"picture"] = picture;
  }

  NSString *scopeString = ALNOIDCTrimmedString(token[@"scope"]);
  if ([scopeString length] > 0) {
    identity[@"scopes"] = ALNOIDCScopesFromScopeString(scopeString);
  }
  return identity;
}

+ (NSDictionary *)redactedProviderConfiguration:(NSDictionary *)providerConfiguration {
  NSMutableDictionary *redacted =
      [NSMutableDictionary dictionaryWithDictionary:providerConfiguration ?: @{}];
  for (NSString *key in @[ @"clientSecret", @"idTokenSharedSecret", @"privateKeyPEM", @"privateKey" ]) {
    if ([redacted[key] isKindOfClass:[NSString class]] && [redacted[key] length] > 0) {
      redacted[key] = @"[REDACTED]";
    }
  }
  return redacted;
}

@end
