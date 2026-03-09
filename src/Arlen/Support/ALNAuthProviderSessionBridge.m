#import "ALNAuthProviderSessionBridge.h"

#import "ALNAuthSession.h"
#import "ALNContext.h"
#import "ALNOIDCClient.h"

NSString *const ALNAuthProviderSessionBridgeErrorDomain = @"Arlen.AuthProviderSessionBridge.Error";

static NSError *ALNAuthProviderSessionBridgeError(ALNAuthProviderSessionBridgeErrorCode code,
                                                  NSString *message) {
  return [NSError errorWithDomain:ALNAuthProviderSessionBridgeErrorDomain
                             code:code
                         userInfo:@{
                           NSLocalizedDescriptionKey : message ?: @"provider login bridge failed",
                         }];
}

static NSString *ALNAuthProviderBridgeTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([trimmed length] > 0) ? trimmed : nil;
}

static NSDate *ALNAuthProviderBridgeDateFromValue(id value) {
  if ([value isKindOfClass:[NSDate class]]) {
    return value;
  }
  if ([value respondsToSelector:@selector(doubleValue)]) {
    return [NSDate dateWithTimeIntervalSince1970:[value doubleValue]];
  }
  return nil;
}

static NSArray *ALNAuthProviderBridgeNormalizedMethods(id value) {
  NSArray *rawValues = [value isKindOfClass:[NSArray class]] ? value : @[];
  NSMutableArray *methods = [NSMutableArray array];
  for (id rawMethod in rawValues) {
    NSString *method = [[ALNAuthProviderBridgeTrimmedString(rawMethod) lowercaseString] copy];
    if ([method length] == 0 || [methods containsObject:method]) {
      continue;
    }
    [methods addObject:method];
  }
  return [NSArray arrayWithArray:methods];
}

@implementation ALNAuthProviderSessionBridge

+ (NSDictionary *)completeLoginWithCallbackParameters:(NSDictionary *)callbackParameters
                                        callbackState:(NSDictionary *)callbackState
                                        tokenResponse:(NSDictionary *)tokenResponse
                                     userInfoResponse:(NSDictionary *)userInfoResponse
                                providerConfiguration:(NSDictionary *)providerConfiguration
                                         jwksDocument:(NSDictionary *)jwksDocument
                                             resolver:(id<ALNAuthProviderSessionResolver>)resolver
                                              context:(ALNContext *)context
                                                error:(NSError **)error {
  if (context == nil || resolver == nil || ![providerConfiguration isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNAuthProviderSessionBridgeError(ALNAuthProviderSessionBridgeErrorInvalidArgument,
                                                 @"Provider login bridge requires context, resolver, and configuration");
    }
    return nil;
  }

  NSDate *issuedAtDate = ALNAuthProviderBridgeDateFromValue(callbackState[@"issuedAt"]);
  NSUInteger maxAgeSeconds =
      [providerConfiguration[@"callbackMaxAgeSeconds"] respondsToSelector:@selector(integerValue)] &&
              [providerConfiguration[@"callbackMaxAgeSeconds"] integerValue] > 0
          ? (NSUInteger)[providerConfiguration[@"callbackMaxAgeSeconds"] integerValue]
          : 300U;

  NSDictionary *validatedCallback = [ALNOIDCClient validateAuthorizationCallbackParameters:callbackParameters
                                                                             expectedState:callbackState[@"state"]
                                                                              issuedAtDate:issuedAtDate
                                                                             maxAgeSeconds:maxAgeSeconds
                                                                                     error:error];
  if (validatedCallback == nil) {
    return nil;
  }

  NSString *protocolValue = ALNAuthProviderBridgeTrimmedString(providerConfiguration[@"protocol"]);
  NSString *protocol = [(protocolValue ?: @"oidc") lowercaseString];
  NSString *expectedNonce = ALNAuthProviderBridgeTrimmedString(callbackState[@"nonce"]);
  NSDictionary *verifiedClaims = nil;
  if (![protocol isEqualToString:@"oauth2"] ||
      [ALNAuthProviderBridgeTrimmedString(tokenResponse[@"id_token"]) length] > 0) {
    verifiedClaims = [ALNOIDCClient verifyIDToken:tokenResponse[@"id_token"]
                            providerConfiguration:providerConfiguration
                                    expectedNonce:expectedNonce
                                     jwksDocument:jwksDocument
                                    referenceDate:[NSDate date]
                                            error:error];
    if (verifiedClaims == nil) {
      return nil;
    }
  }

  NSDictionary *normalizedIdentity =
      [ALNOIDCClient normalizedIdentityFromVerifiedClaims:verifiedClaims
                                            tokenResponse:tokenResponse
                                         userInfoResponse:userInfoResponse
                                    providerConfiguration:providerConfiguration
                                                    error:error];
  if (normalizedIdentity == nil) {
    return nil;
  }

  NSDictionary *sessionDescriptor =
      [resolver resolveSessionDescriptorForNormalizedIdentity:normalizedIdentity
                                        providerConfiguration:providerConfiguration
                                                        error:error];
  if (![sessionDescriptor isKindOfClass:[NSDictionary class]]) {
    if (error != NULL && *error == NULL) {
      *error = ALNAuthProviderSessionBridgeError(
          ALNAuthProviderSessionBridgeErrorResolverRejectedIdentity,
          @"Resolver did not return a session descriptor");
    }
    return nil;
  }

  NSString *subject = ALNAuthProviderBridgeTrimmedString(sessionDescriptor[@"subject"]);
  if ([subject length] == 0) {
    if (error != NULL) {
      *error = ALNAuthProviderSessionBridgeError(ALNAuthProviderSessionBridgeErrorMissingLocalSubject,
                                                 @"Resolved provider login requires a non-empty local subject");
    }
    return nil;
  }

  NSString *provider =
      ALNAuthProviderBridgeTrimmedString(sessionDescriptor[@"provider"]) ?:
      ALNAuthProviderBridgeTrimmedString(normalizedIdentity[@"provider"]) ?:
      ALNAuthProviderBridgeTrimmedString(providerConfiguration[@"identifier"]);
  NSArray *methods = ALNAuthProviderBridgeNormalizedMethods(sessionDescriptor[@"methods"]);
  if ([methods count] == 0) {
    methods = @[ @"federated" ];
  }

  NSUInteger assuranceLevel =
      [sessionDescriptor[@"assuranceLevel"] respondsToSelector:@selector(integerValue)] &&
              [sessionDescriptor[@"assuranceLevel"] integerValue] > 0
          ? (NSUInteger)[sessionDescriptor[@"assuranceLevel"] integerValue]
          : 1U;
  NSDate *authenticatedAt =
      ALNAuthProviderBridgeDateFromValue(sessionDescriptor[@"authenticatedAt"]) ?:
      ALNAuthProviderBridgeDateFromValue(verifiedClaims[@"auth_time"]) ?:
      ALNAuthProviderBridgeDateFromValue(verifiedClaims[@"iat"]) ?:
      [NSDate date];

  if (![ALNAuthSession establishAuthenticatedSessionForSubject:subject
                                                      provider:provider
                                                       methods:methods
                                                assuranceLevel:assuranceLevel
                                               authenticatedAt:authenticatedAt
                                                       context:context
                                                         error:error]) {
    return nil;
  }

  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"normalizedIdentity"] = normalizedIdentity;
  result[@"session"] = @{
    @"subject" : [ALNAuthSession subjectFromContext:context] ?: @"",
    @"provider" : [ALNAuthSession providerFromContext:context] ?: @"",
    @"methods" : [ALNAuthSession authenticationMethodsFromContext:context] ?: @[],
    @"aal" : @([ALNAuthSession assuranceLevelFromContext:context]),
    @"session_id" : [ALNAuthSession sessionIdentifierFromContext:context] ?: @"",
  };

  NSDictionary *linking = [self accountLinkingDescriptorForNormalizedIdentity:normalizedIdentity
                                                         providerConfiguration:providerConfiguration
                                                                      resolver:resolver
                                                                         error:NULL];
  if ([linking isKindOfClass:[NSDictionary class]]) {
    result[@"accountLinking"] = linking;
  }

  return result;
}

+ (NSDictionary *)accountLinkingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                          providerConfiguration:(NSDictionary *)providerConfiguration
                                                       resolver:(id<ALNAuthProviderSessionResolver>)resolver
                                                          error:(NSError **)error {
  if ([resolver respondsToSelector:@selector(accountLinkingDescriptorForNormalizedIdentity:providerConfiguration:error:)]) {
    return [resolver accountLinkingDescriptorForNormalizedIdentity:normalizedIdentity
                                             providerConfiguration:providerConfiguration
                                                             error:error];
  }
  return nil;
}

@end
