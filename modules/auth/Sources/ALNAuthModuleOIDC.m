#import "ALNAuthModuleOIDC.h"
#import "ALNOIDCClient.h"
#import "ALNHTTPCompat.h"
#import "ALNSecurityPrimitives.h"

NSString *const ALNAuthModuleOIDCErrorDomain = @"Arlen.Modules.Auth.OIDC";

static NSString *OS(id value) { return [value isKindOfClass:[NSString class]] ? value : @""; }
static BOOL OFail(NSError **error, NSString *message) {
  if (error) *error = [NSError errorWithDomain:ALNAuthModuleOIDCErrorDomain code:ALNAuthModuleOIDCErrorRejected
                                    userInfo:@{NSLocalizedDescriptionKey: message}];
  return NO;
}
static NSString *OLower(id value) {
  return [[OS(value) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
      lowercaseString];
}
// Plist values may arrive as NSNumber or as YES/true/1 strings.
static BOOL OBool(id value, BOOL *valid) {
  *valid = YES;
  if (!value) return NO;
  if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
  NSString *text = OLower(value);
  if ([@[ @"yes", @"true", @"1" ] containsObject:text]) return YES;
  if ([@[ @"no", @"false", @"0" ] containsObject:text]) return NO;
  *valid = NO;
  return NO;
}
// A DNS-style domain: dot-separated labels of letters, digits and hyphens.
static BOOL ODomainIsValid(NSString *domain) {
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:
      @"abcdefghijklmnopqrstuvwxyz0123456789.-"] invertedSet];
  return domain.length && [domain rangeOfString:@"."].location != NSNotFound &&
      [domain rangeOfCharacterFromSet:invalid].location == NSNotFound &&
      ![domain hasPrefix:@"."] && ![domain hasSuffix:@"."] && [domain rangeOfString:@".."].location == NSNotFound;
}
// Deliberately narrow: exactly one `@`, a nonempty local part without whitespace
// or separators, and a valid domain. Allowlist entries are addresses, not patterns.
static BOOL OEmailIsValid(NSString *email) {
  NSArray *parts = [email componentsSeparatedByString:@"@"];
  if (parts.count != 2 || ![parts[0] length]) return NO;
  NSCharacterSet *forbidden = [NSCharacterSet characterSetWithCharactersInString:@" \t\r\n,;:/\\<>()[]\""];
  return [parts[0] rangeOfCharacterFromSet:forbidden].location == NSNotFound && ODomainIsValid(parts[1]);
}
static BOOL OAppendLowered(NSMutableArray *target, id values, BOOL domains) {
  if (!values) return YES;
  if (![values isKindOfClass:[NSArray class]]) return NO;
  for (id value in values) {
    NSString *entry = OLower(value);
    if (domains && [entry hasPrefix:@"@"]) entry = [entry substringFromIndex:1];
    if (!(domains ? ODomainIsValid(entry) : OEmailIsValid(entry))) return NO;
    if (![target containsObject:entry]) [target addObject:entry];
  }
  return YES;
}
// Validates and normalizes a provider `admission` dictionary. Admission is not identity
// linking: accounts stay keyed on the verified provider subject.
static NSDictionary *OAdmissionPolicy(id admission, NSError **error) {
  if (![admission isKindOfClass:[NSDictionary class]]) {
    OFail(error, @"OIDC admission must be a dictionary"); return nil;
  }
  NSSet *known = [NSSet setWithArray:@[ @"requireVerifiedEmail", @"allowedEmails", @"allowedEmailsEnvironmentKey",
                                        @"allowedDomains", @"requireHostedDomain", @"rejectionMessage" ]];
  for (id key in admission) {
    if (![known containsObject:key]) {
      OFail(error, [NSString stringWithFormat:@"OIDC admission has unknown key %@", key]); return nil;
    }
  }
  BOOL validVerified = YES, validHosted = YES;
  BOOL requireVerified = OBool(admission[@"requireVerifiedEmail"], &validVerified);
  BOOL requireHosted = OBool(admission[@"requireHostedDomain"], &validHosted);
  NSMutableArray *emails = [NSMutableArray array];
  NSMutableArray *domains = [NSMutableArray array];
  if (!validVerified || !validHosted || !OAppendLowered(emails, admission[@"allowedEmails"], NO) ||
      !OAppendLowered(domains, admission[@"allowedDomains"], YES)) {
    OFail(error, @"OIDC admission values must be booleans, email addresses, and domains"); return nil;
  }
  id envKey = admission[@"allowedEmailsEnvironmentKey"];
  if (envKey) {
    NSString *list = OS([NSProcessInfo processInfo].environment[OS(envKey)]);
    NSArray *envEmails = [list componentsSeparatedByString:@","];
    NSMutableArray *nonempty = [NSMutableArray array];
    for (NSString *email in envEmails) if (OLower(email).length) [nonempty addObject:email];
    if (!OS(envKey).length || !nonempty.count || !OAppendLowered(emails, nonempty, NO)) {
      OFail(error, @"OIDC admission allowedEmailsEnvironmentKey must name a nonempty comma-separated email list");
      return nil;
    }
  }
  if (requireHosted && !domains.count) {
    OFail(error, @"OIDC admission requireHostedDomain needs allowedDomains"); return nil;
  }
  if (admission[@"rejectionMessage"] && !OS(admission[@"rejectionMessage"]).length) {
    OFail(error, @"OIDC admission rejectionMessage must be a nonempty string"); return nil;
  }
  return @{
    @"requireVerifiedEmail": @(requireVerified),
    @"requireHostedDomain": @(requireHosted),
    @"allowedEmails": emails,
    @"allowedDomains": domains,
    @"rejectionMessage": OS(admission[@"rejectionMessage"]).length ? admission[@"rejectionMessage"]
                                                                  : @"This account is not permitted to sign in.",
  };
}
static BOOL OClaimTrue(id value) {
  if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
  return [OLower(value) isEqual:@"true"];
}
static BOOL OAdmits(NSDictionary *policy, NSDictionary *claims) {
  if (!policy) return YES;
  NSString *email = OLower(claims[@"email"]);
  NSArray *emails = policy[@"allowedEmails"];
  NSArray *domains = policy[@"allowedDomains"];
  BOOL listed = emails.count || domains.count;
  // List matching is only meaningful for provider-verified addresses.
  if (([policy[@"requireVerifiedEmail"] boolValue] || listed) &&
      (!email.length || !OClaimTrue(claims[@"email_verified"]))) return NO;
  if (!listed || [emails containsObject:email]) return YES;
  NSRange at = [email rangeOfString:@"@" options:NSBackwardsSearch];
  NSString *domain = at.location == NSNotFound ? @"" : [email substringFromIndex:at.location + 1];
  NSString *hostedDomain = OLower(claims[@"hd"]);
  if ([policy[@"requireHostedDomain"] boolValue] && !hostedDomain.length) return NO;
  return [domains containsObject:domain] && (!hostedDomain.length || [domains containsObject:hostedDomain]);
}
static BOOL OURL(NSString *value, NSArray *hosts) {
  NSURL *url = [NSURL URLWithString:OS(value)];
  return [url.scheme.lowercaseString isEqual:@"https"] && url.host.length &&
      !url.user.length && !url.password.length && !url.fragment.length &&
      (!hosts || [hosts containsObject:url.host.lowercaseString]);
}
// Loopback redirect URIs (RFC 8252 section 7.3) are a development convenience only.
static BOOL OLoopbackHTTPURL(NSString *value) {
  NSURL *url = [NSURL URLWithString:OS(value)];
  NSString *host = url.host.lowercaseString;
  return [url.scheme.lowercaseString isEqual:@"http"] &&
      ([host isEqual:@"localhost"] || [host isEqual:@"127.0.0.1"] || [host isEqual:@"::1"] ||
       [host isEqual:@"[::1]"]) &&
      !url.user.length && !url.password.length && !url.fragment.length;
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
  return [self initWithIdentifier:identifier configuration:configuration resolver:resolver
                        transport:transport allowLoopbackHTTPRedirect:NO error:error];
}
- (instancetype)initWithIdentifier:(NSString *)identifier configuration:(NSDictionary *)configuration
                         resolver:(id<ALNAuthProviderSessionResolver>)resolver
                        transport:(id<ALNAuthModuleOIDCTransport>)transport
        allowLoopbackHTTPRedirect:(BOOL)allowLoopbackHTTPRedirect error:(NSError **)error {
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
      !OURL(config[@"discoveryURL"], hosts) ||
      !(OURL(config[@"redirectURI"], nil) ||
        (allowLoopbackHTTPRedirect && OLoopbackHTTPURL(config[@"redirectURI"]))) ||
      !OS(config[@"clientID"]).length) {
    OFail(error, allowLoopbackHTTPRedirect
                     ? @"OIDC requires HTTPS issuer/discovery URLs, an HTTPS or loopback http redirect URL, allowed hosts, and clientID"
                     : @"OIDC requires HTTPS issuer/discovery/redirect URLs, allowed hosts, and clientID"); return nil;
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
  NSDictionary *admission = nil;
  if (config[@"admission"]) {
    admission = OAdmissionPolicy(config[@"admission"], error);
    if (!admission) return nil;
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
  if (admission) safe[@"admission"] = admission;
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
  NSDictionary *admission = self.configuration[@"admission"];
  if (!OAdmits(admission, [normalized[@"claims"] isKindOfClass:[NSDictionary class]] ? normalized[@"claims"] : @{})) {
    if (error) *error = [NSError errorWithDomain:ALNAuthModuleOIDCErrorDomain code:ALNAuthModuleOIDCErrorAdmissionDenied
                                        userInfo:@{NSLocalizedDescriptionKey: admission[@"rejectionMessage"]}];
    return nil;
  }
  // Admission only gates sign-in; the application still decides membership, roles and
  // linking. No email fallback.
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
