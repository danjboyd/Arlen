#import "ALNAuthModuleOIDC.h"
#import "ALNOIDCClient.h"
#import "ALNHTTPCompat.h"
#import "ALNSecurityPrimitives.h"

static NSString *OS(id value) { return [value isKindOfClass:[NSString class]] ? value : @""; }
static BOOL OFail(NSError **error, NSString *message) {
  if (error) *error = [NSError errorWithDomain:@"Arlen.Modules.Auth.OIDC" code:1
                                    userInfo:@{NSLocalizedDescriptionKey: message}];
  return NO;
}
static BOOL OURL(NSString *value, NSArray *hosts) {
  NSURL *url = [NSURL URLWithString:OS(value)];
  return [url.scheme.lowercaseString isEqual:@"https"] && url.host.length &&
      !url.user.length && !url.password.length && !url.fragment.length &&
      (!hosts || [hosts containsObject:url.host.lowercaseString]);
}
static BOOL OStrings(id values) {
  if (![values isKindOfClass:[NSArray class]] || ![values count]) return NO;
  for (id value in values) if (!OS(value).length) return NO;
  return YES;
}

@interface ALNAuthModuleOIDC ()
@property(nonatomic, copy, readwrite) NSDictionary *configuration;
@property(nonatomic, strong) id<ALNAuthProviderSessionResolver> resolver;
@property(nonatomic, strong) id<ALNAuthModuleOIDCTransport> transport;
@end
@implementation ALNAuthModuleOIDC
- (instancetype)initWithIdentifier:(NSString *)identifier configuration:(NSDictionary *)configuration
                         resolver:(id<ALNAuthProviderSessionResolver>)resolver
                        transport:(id<ALNAuthModuleOIDCTransport>)transport error:(NSError **)error {
  if (!(self = [super init])) return nil;
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"] invertedSet];
  if (!identifier.length || [identifier rangeOfCharacterFromSet:invalid].location != NSNotFound ||
      [identifier isEqual:@"stub"] || !resolver || ![configuration isKindOfClass:[NSDictionary class]]) {
    OFail(error, @"OIDC requires a valid provider identifier and providerSessionResolverClass"); return nil;
  }
  NSMutableDictionary *config = [configuration mutableCopy];
  NSString *host = [NSURL URLWithString:OS(config[@"issuer"])].host.lowercaseString;
  NSArray *hosts = config[@"endpointAllowedHosts"] ?: (host ? @[host] : @[]);
  NSArray *jwksHosts = config[@"jwksAllowedHosts"] ?: hosts;
  if (!OStrings(hosts) || !OStrings(jwksHosts) || !OURL(config[@"issuer"], nil) ||
      !OURL(config[@"discoveryURL"], hosts) || !OURL(config[@"redirectURI"], nil) ||
      !OS(config[@"clientID"]).length) {
    OFail(error, @"OIDC requires HTTPS issuer/discovery/redirect URLs, allowed hosts, and clientID"); return nil;
  }
  NSArray *scopes = config[@"scopes"] ?: @[ @"openid", @"profile", @"email" ];
  if (!OStrings(scopes) || ![scopes containsObject:@"openid"]) {
    OFail(error, @"OIDC scopes must include openid"); return nil;
  }
  NSString *tenantClaim = OS(config[@"tenantClaim"]);
  if ((tenantClaim.length || config[@"allowedTenants"]) &&
      (!tenantClaim.length || !OStrings(config[@"allowedTenants"]))) {
    OFail(error, @"OIDC tenantClaim and nonempty allowedTenants must be configured together"); return nil;
  }
  if (config[@"subjectClaim"] && !OS(config[@"subjectClaim"]).length) {
    OFail(error, @"OIDC subjectClaim must be a nonempty claim name"); return nil;
  }
  NSString *secretKey = OS(config[@"clientSecretEnvironmentKey"]);
  NSString *method = OS(config[@"tokenEndpointAuthMethod"]);
  if (!method.length) method = @"client_secret_post";
  if (![method isEqual:@"client_secret_post"] && ![method isEqual:@"none"]) {
    OFail(error, @"OIDC supports client_secret_post or none token endpoint authentication"); return nil;
  }
  if ([method isEqual:@"client_secret_post"] &&
      (!secretKey.length || !OS([NSProcessInfo processInfo].environment[secretKey]).length)) {
    OFail(error, @"OIDC clientSecretEnvironmentKey must name a nonempty environment secret"); return nil;
  }
  // Never copy arbitrary primitive overrides (HS256 secrets, audience, OAuth2 mode).
  NSMutableDictionary *safe = [NSMutableDictionary dictionary];
  for (NSString *key in @[ @"issuer", @"discoveryURL", @"redirectURI", @"clientID", @"subjectClaim",
                          @"tenantClaim", @"allowedTenants", @"clientSecretEnvironmentKey" ])
    if (config[key]) safe[key] = config[key];
  safe[@"identifier"] = identifier;
  safe[@"protocol"] = @"oidc";
  safe[@"endpointAllowedHosts"] = hosts;
  safe[@"jwksAllowedHosts"] = jwksHosts;
  safe[@"scopes"] = scopes;
  safe[@"tokenEndpointAuthMethod"] = method;
  safe[@"callbackMaxAgeSeconds"] = @300;
  safe[@"timeoutSeconds"] = @5;
  self.configuration = safe;
  self.resolver = resolver;
  self.transport = transport;
  return self;
}

- (NSDictionary *)documentForRequest:(NSURLRequest *)request error:(NSError **)error {
  NSData *data = self.transport ? [self.transport performOIDCRequest:request error:NULL] :
                                 ALNBoundedJSONRequest(request, 262144, NULL);
  id json = data && data.length <= 262144 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  if (![json isKindOfClass:[NSDictionary class]]) {
    OFail(error, @"OIDC provider response unavailable or invalid"); return nil;
  }
  return json;
}
- (NSDictionary *)documentAtURL:(NSString *)url error:(NSError **)error {
  return [self documentForRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]
                    cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5] error:error];
}
- (NSDictionary *)discoveredConfigurationWithError:(NSError **)error {
  NSDictionary *metadata = [self documentAtURL:self.configuration[@"discoveryURL"] error:error];
  if (!metadata) return nil;
  if (![metadata[@"issuer"] isEqual:self.configuration[@"issuer"]] ||
      !OURL(metadata[@"authorization_endpoint"], self.configuration[@"endpointAllowedHosts"]) ||
      !OURL(metadata[@"token_endpoint"], self.configuration[@"endpointAllowedHosts"]) ||
      !OURL(metadata[@"jwks_uri"], self.configuration[@"jwksAllowedHosts"])) {
    OFail(error, @"OIDC discovery issuer or endpoint rejected"); return nil;
  }
  NSMutableDictionary *config = [self.configuration mutableCopy];
  config[@"authorizationEndpoint"] = metadata[@"authorization_endpoint"];
  config[@"tokenEndpoint"] = metadata[@"token_endpoint"];
  config[@"jwksURI"] = metadata[@"jwks_uri"];
  return config;
}
- (NSDictionary *)beginLoginWithError:(NSError **)error {
  NSDictionary *config = [self discoveredConfigurationWithError:error];
  if (!config) return nil;
  NSMutableDictionary *state = [[ALNOIDCClient authorizationRequestForProviderConfiguration:config
      redirectURI:config[@"redirectURI"] scopes:config[@"scopes"] referenceDate:nil error:error] mutableCopy];
  state[@"provider"] = config[@"identifier"];
  return state;
}
- (NSDictionary *)completeLoginWithParameters:(NSDictionary *)parameters callbackState:(NSDictionary *)state
                                    context:(ALNContext *)context error:(NSError **)error {
  NSTimeInterval issued = [state[@"issuedAt"] respondsToSelector:@selector(doubleValue)] ? [state[@"issuedAt"] doubleValue] : 0;
  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  if (![state[@"provider"] isEqual:self.configuration[@"identifier"]] ||
      ![state[@"redirectURI"] isEqual:self.configuration[@"redirectURI"]] ||
      !OS(state[@"nonce"]).length || !OS(state[@"codeVerifier"]).length || issued <= 0 || issued > now ||
      (parameters[@"iss"] && ![parameters[@"iss"] isEqual:self.configuration[@"issuer"]])) {
    OFail(error, @"OIDC callback binding rejected"); return nil;
  }
  NSDictionary *callback = [ALNOIDCClient validateAuthorizationCallbackParameters:parameters
      expectedState:state[@"state"] issuedAtDate:[NSDate dateWithTimeIntervalSince1970:issued]
      maxAgeSeconds:300 error:error];
  if (!callback) return nil;
  NSMutableDictionary *config = [[self discoveredConfigurationWithError:error] mutableCopy];
  if (!config) return nil;
  NSString *secretKey = OS(config[@"clientSecretEnvironmentKey"]);
  if ([config[@"tokenEndpointAuthMethod"] isEqual:@"client_secret_post"]) {
    NSString *secret = OS([NSProcessInfo processInfo].environment[secretKey]);
    if (!secret.length) { OFail(error, @"OIDC client secret unavailable"); return nil; }
    config[@"clientSecret"] = secret;
  }
  NSDictionary *exchange = [ALNOIDCClient tokenExchangeRequestForProviderConfiguration:config
      authorizationCode:callback[@"code"] redirectURI:config[@"redirectURI"]
      codeVerifier:state[@"codeVerifier"] error:error];
  if (!exchange) return nil;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:exchange[@"url"]]
      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
  request.HTTPMethod = @"POST";
  request.HTTPBody = [exchange[@"bodyString"] dataUsingEncoding:NSUTF8StringEncoding];
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
  NSDictionary *token = [self documentForRequest:request error:error];
  [config removeObjectForKey:@"clientSecret"];
  if (!token) return nil;
  NSArray *parts = [OS(token[@"id_token"]) componentsSeparatedByString:@"."];
  NSData *headerData = parts.count == 3 ? ALNDataFromBase64URLString(parts[0]) : nil;
  id header = headerData ? [NSJSONSerialization JSONObjectWithData:headerData options:0 error:NULL] : nil;
  if (token[@"error"] || ![header isKindOfClass:[NSDictionary class]] || ![header[@"alg"] isEqual:@"RS256"]) {
    OFail(error, @"OIDC requires a successful token response with an RS256 ID token"); return nil;
  }
  NSDictionary *keys = [self documentAtURL:config[@"jwksURI"] error:error];
  if (!keys) return nil;
  // Fetch keys on each callback so rotation does not depend on process-local cache freshness.
  NSMutableDictionary *result = [[ALNAuthProviderSessionBridge completeLoginWithCallbackParameters:parameters callbackState:state
      tokenResponse:token userInfoResponse:nil providerConfiguration:config jwksDocument:keys
      resolver:self context:context error:error] mutableCopy];
  if (result) result[@"normalizedIdentity"] = [self principalIdentity:result[@"normalizedIdentity"] configuration:config error:NULL];
  return result;
}
- (NSDictionary *)principalIdentity:(NSDictionary *)identity configuration:(NSDictionary *)config error:(NSError **)error {
  NSDictionary *claims = identity[@"claims"];
  NSString *subject = OS(claims[self.configuration[@"subjectClaim"] ?: @"sub"]);
  NSString *tenantClaim = OS(self.configuration[@"tenantClaim"]);
  NSString *tenant = tenantClaim.length ? OS(claims[tenantClaim]) : @"";
  id audience = claims[@"aud"];
  if ((claims[@"azp"] && ![claims[@"azp"] isEqual:config[@"clientID"]]) ||
      ([audience isKindOfClass:[NSArray class]] && [audience count] > 1 && !claims[@"azp"])) {
    OFail(error, @"OIDC authorized party rejected"); return nil;
  }
  if (!subject.length || (tenantClaim.length &&
      (!tenant.length || [tenant containsString:@":"] || [subject containsString:@":"] ||
       ![self.configuration[@"allowedTenants"] containsObject:tenant]))) {
    OFail(error, @"OIDC identity subject or tenant rejected"); return nil;
  }
  NSMutableDictionary *normalized = [identity mutableCopy];
  normalized[@"provider_subject"] = tenantClaim.length ? [NSString stringWithFormat:@"%@:%@", tenant, subject] : subject;
  return normalized;
}
- (NSDictionary *)resolveSessionDescriptorForNormalizedIdentity:(NSDictionary *)identity
                                         providerConfiguration:(NSDictionary *)config error:(NSError **)error {
  NSDictionary *normalized = [self principalIdentity:identity configuration:config error:error];
  if (!normalized) return nil;
  // The application alone decides membership, roles and linking. No email fallback.
  return [self.resolver resolveSessionDescriptorForNormalizedIdentity:normalized
                                              providerConfiguration:config error:error];
}
- (NSDictionary *)accountLinkingDescriptorForNormalizedIdentity:(NSDictionary *)identity
                                         providerConfiguration:(NSDictionary *)config error:(NSError **)error {
  if (![self.resolver respondsToSelector:_cmd]) return nil;
  NSDictionary *normalized = [self principalIdentity:identity configuration:config error:error];
  if (!normalized) return nil;
  return [self.resolver accountLinkingDescriptorForNormalizedIdentity:normalized
                                              providerConfiguration:config error:error];
}
@end
