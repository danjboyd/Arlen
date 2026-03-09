#import "ALNAuthProviderPresets.h"

NSString *const ALNAuthProviderPresetsErrorDomain = @"Arlen.AuthProviderPresets.Error";

static NSError *ALNAuthProviderPresetsError(ALNAuthProviderPresetsErrorCode code, NSString *message) {
  return [NSError errorWithDomain:ALNAuthProviderPresetsErrorDomain
                             code:code
                         userInfo:@{
                           NSLocalizedDescriptionKey : message ?: @"provider preset failed",
                         }];
}

static NSString *ALNAuthProviderPresetTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([trimmed length] > 0) ? trimmed : nil;
}

static NSDictionary *ALNAuthProviderPresetRecursiveMerge(NSDictionary *base, NSDictionary *override) {
  NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:base ?: @{}];
  for (id key in override ?: @{}) {
    id baseValue = merged[key];
    id overrideValue = override[key];
    if ([baseValue isKindOfClass:[NSDictionary class]] &&
        [overrideValue isKindOfClass:[NSDictionary class]]) {
      merged[key] = ALNAuthProviderPresetRecursiveMerge(baseValue, overrideValue);
      continue;
    }
    if (overrideValue != nil) {
      merged[key] = overrideValue;
    }
  }
  return merged;
}

static NSDictionary *ALNAuthProviderPresetCatalog(void) {
  static NSDictionary *catalog = nil;
  @synchronized([ALNAuthProviderPresets class]) {
    if (catalog != nil) {
      return catalog;
    }
    catalog = @{
      @"google" : @{
        @"identifier" : @"google",
        @"displayName" : @"Google",
        @"protocol" : @"oidc",
        @"issuer" : @"https://accounts.google.com",
        @"authorizationEndpoint" : @"https://accounts.google.com/o/oauth2/v2/auth",
        @"tokenEndpoint" : @"https://oauth2.googleapis.com/token",
        @"jwksURI" : @"https://www.googleapis.com/oauth2/v3/certs",
        @"userInfoEndpoint" : @"https://openidconnect.googleapis.com/v1/userinfo",
        @"defaultScopes" : @[ @"openid", @"email", @"profile" ],
        @"tokenEndpointAuthMethod" : @"client_secret_post",
        @"callbackMaxAgeSeconds" : @300,
        @"jwksMaxAgeSeconds" : @3600,
      },
      @"github" : @{
        @"identifier" : @"github",
        @"displayName" : @"GitHub",
        @"protocol" : @"oauth2",
        @"authorizationEndpoint" : @"https://github.com/login/oauth/authorize",
        @"tokenEndpoint" : @"https://github.com/login/oauth/access_token",
        @"userInfoEndpoint" : @"https://api.github.com/user",
        @"defaultScopes" : @[ @"read:user", @"user:email" ],
        @"tokenEndpointAuthMethod" : @"client_secret_post",
        @"callbackMaxAgeSeconds" : @300,
      },
      @"microsoft" : @{
        @"identifier" : @"microsoft",
        @"displayName" : @"Microsoft",
        @"protocol" : @"oidc",
        @"issuer" : @"https://login.microsoftonline.com/common/v2.0",
        @"authorizationEndpoint" : @"https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
        @"tokenEndpoint" : @"https://login.microsoftonline.com/common/oauth2/v2.0/token",
        @"jwksURI" : @"https://login.microsoftonline.com/common/discovery/v2.0/keys",
        @"defaultScopes" : @[ @"openid", @"email", @"profile" ],
        @"tokenEndpointAuthMethod" : @"client_secret_post",
        @"callbackMaxAgeSeconds" : @300,
        @"jwksMaxAgeSeconds" : @3600,
      },
      @"apple" : @{
        @"identifier" : @"apple",
        @"displayName" : @"Apple",
        @"protocol" : @"oidc",
        @"issuer" : @"https://appleid.apple.com",
        @"authorizationEndpoint" : @"https://appleid.apple.com/auth/authorize",
        @"tokenEndpoint" : @"https://appleid.apple.com/auth/token",
        @"jwksURI" : @"https://appleid.apple.com/auth/keys",
        @"defaultScopes" : @[ @"openid", @"email", @"name" ],
        @"tokenEndpointAuthMethod" : @"client_secret_post",
        @"callbackMaxAgeSeconds" : @300,
        @"jwksMaxAgeSeconds" : @3600,
      },
      @"okta" : @{
        @"identifier" : @"okta",
        @"displayName" : @"Okta",
        @"protocol" : @"oidc",
        @"issuer" : @"https://example.okta.com/oauth2/default",
        @"authorizationEndpoint" : @"https://example.okta.com/oauth2/default/v1/authorize",
        @"tokenEndpoint" : @"https://example.okta.com/oauth2/default/v1/token",
        @"jwksURI" : @"https://example.okta.com/oauth2/default/v1/keys",
        @"userInfoEndpoint" : @"https://example.okta.com/oauth2/default/v1/userinfo",
        @"defaultScopes" : @[ @"openid", @"email", @"profile" ],
        @"tokenEndpointAuthMethod" : @"client_secret_post",
        @"callbackMaxAgeSeconds" : @300,
        @"jwksMaxAgeSeconds" : @3600,
      },
      @"auth0" : @{
        @"identifier" : @"auth0",
        @"displayName" : @"Auth0",
        @"protocol" : @"oidc",
        @"issuer" : @"https://example.us.auth0.com/",
        @"authorizationEndpoint" : @"https://example.us.auth0.com/authorize",
        @"tokenEndpoint" : @"https://example.us.auth0.com/oauth/token",
        @"jwksURI" : @"https://example.us.auth0.com/.well-known/jwks.json",
        @"userInfoEndpoint" : @"https://example.us.auth0.com/userinfo",
        @"defaultScopes" : @[ @"openid", @"email", @"profile" ],
        @"tokenEndpointAuthMethod" : @"client_secret_post",
        @"callbackMaxAgeSeconds" : @300,
        @"jwksMaxAgeSeconds" : @3600,
      },
    };
  }
  return catalog;
}

@implementation ALNAuthProviderPresets

+ (NSDictionary *)availablePresets {
  return ALNAuthProviderPresetCatalog();
}

+ (NSDictionary *)presetNamed:(NSString *)presetName error:(NSError **)error {
  NSString *trimmedPreset = [ALNAuthProviderPresetTrimmedString(presetName) lowercaseString];
  NSDictionary *preset = [ALNAuthProviderPresetCatalog()[trimmedPreset] isKindOfClass:[NSDictionary class]]
                             ? ALNAuthProviderPresetCatalog()[trimmedPreset]
                             : nil;
  if (preset == nil && error != NULL) {
    *error = ALNAuthProviderPresetsError(ALNAuthProviderPresetsErrorInvalidPreset,
                                         [NSString stringWithFormat:@"Unknown provider preset: %@",
                                                                    presetName ?: @""]);
  }
  return preset;
}

+ (NSDictionary *)providerConfigurationFromPresetNamed:(NSString *)presetName
                                             overrides:(NSDictionary *)overrides
                                                 error:(NSError **)error {
  NSDictionary *preset = [self presetNamed:presetName error:error];
  if (preset == nil) {
    return nil;
  }
  NSDictionary *overrideDict = [overrides isKindOfClass:[NSDictionary class]] ? overrides : @{};
  NSDictionary *merged = ALNAuthProviderPresetRecursiveMerge(preset, overrideDict);
  return merged;
}

+ (NSDictionary *)normalizedProvidersFromConfiguration:(NSDictionary *)providersConfiguration
                                                 error:(NSError **)error {
  if (![providersConfiguration isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = ALNAuthProviderPresetsError(ALNAuthProviderPresetsErrorInvalidConfiguration,
                                           @"Providers configuration must be a dictionary");
    }
    return nil;
  }

  NSMutableDictionary *normalized = [NSMutableDictionary dictionary];
  NSArray *sortedKeys = [[providersConfiguration allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (id rawKey in sortedKeys) {
    NSString *identifier = ALNAuthProviderPresetTrimmedString(rawKey);
    NSDictionary *rawEntry = [providersConfiguration[rawKey] isKindOfClass:[NSDictionary class]]
                                 ? providersConfiguration[rawKey]
                                 : nil;
    if ([identifier length] == 0 || rawEntry == nil) {
      if (error != NULL) {
        *error = ALNAuthProviderPresetsError(ALNAuthProviderPresetsErrorInvalidConfiguration,
                                             @"Each provider entry must be a non-empty dictionary");
      }
      return nil;
    }

    NSString *presetName = [[ALNAuthProviderPresetTrimmedString(rawEntry[@"preset"]) lowercaseString] copy];
    if ([presetName length] == 0 &&
        [[ALNAuthProviderPresetCatalog() objectForKey:[identifier lowercaseString]]
            isKindOfClass:[NSDictionary class]]) {
      presetName = [identifier lowercaseString];
    }

    NSDictionary *provider = nil;
    if ([presetName length] > 0) {
      provider = [self providerConfigurationFromPresetNamed:presetName overrides:rawEntry error:error];
      if (provider == nil) {
        return nil;
      }
    } else {
      provider = rawEntry;
    }

    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:provider ?: @{}];
    if ([ALNAuthProviderPresetTrimmedString(entry[@"identifier"]) length] == 0) {
      entry[@"identifier"] = identifier;
    }
    if ([ALNAuthProviderPresetTrimmedString(entry[@"displayName"]) length] == 0) {
      entry[@"displayName"] = [identifier capitalizedString];
    }
    normalized[identifier] = entry;
  }
  return normalized;
}

@end
