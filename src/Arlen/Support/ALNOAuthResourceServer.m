#import "ALNOAuthResourceServer.h"
#import "ALNAuth.h"
#import "ALNOIDCClient.h"
#import "ALNHTTPCompat.h"
#import "ALNJSONSerialization.h"
#import "ALNSecurityPrimitives.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRouter.h"
#import "ALNResponseEnvelopeMiddleware.h"
#include <math.h>

NSString *const ALNOAuthPrincipalStashKey = @"Arlen.OAuth.principal";
static NSString *const ServerKey = @"Arlen.OAuth.server";
static BOOL D(id x) { return [x isKindOfClass:[NSDictionary class]]; }
static BOOL S(id x) { return [x isKindOfClass:[NSString class]] && [x length] > 0; }
static id Fail(NSError **error, NSString *message) {
  if (error) *error = [NSError errorWithDomain:@"Arlen.OAuth" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
  return nil;
}
static BOOL Strings(id x) {
  if (![x isKindOfClass:[NSArray class]]) return NO;
  for (id value in x) if (!S(value) || [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"\\\r\n\t "]].location != NSNotFound) return NO;
  return YES;
}
static BOOL HTTPS(id value) {
  if (!S(value) || [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"\\\r\n\t "]].location != NSNotFound) return NO;
  NSURL *url = [NSURL URLWithString:value];
  return [url.scheme isEqual:@"https"] && url.host.length && !url.user && !url.password && !url.fragment && !url.query;
}
static BOOL Path(NSString *path) {
  return S(path) && [path hasPrefix:@"/"] && ![path containsString:@"//"] &&
    ![[path componentsSeparatedByString:@"/"] containsObject:@"."] && ![[path componentsSeparatedByString:@"/"] containsObject:@".."] &&
    [path rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/._-"] invertedSet]].location == NSNotFound &&
    ([path isEqual:@"/"] || ![path hasSuffix:@"/"]);
}
static BOOL Number(id x) {
  return [x isKindOfClass:[NSNumber class]] && strcmp([x objCType], @encode(BOOL)) != 0 && isfinite([x doubleValue]);
}
static NSDictionary *Part(NSString *part) {
  NSData *data = ALNDataFromBase64URLString(part);
  id value = data ? [ALNJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
  return D(value) ? value : nil;
}
@interface ALNOAuthResourceServer ()
@property(nonatomic, copy) NSDictionary *configuration;
@property(nonatomic, copy) NSString *metadataPath;
@property(nonatomic, copy) NSString *metadataURL;
@property(nonatomic, copy) ALNOAuthDocumentLoader loader;
@property(nonatomic, assign) BOOL usesDefaultLoader;
@property(nonatomic, copy) ALNOAuthAuthorizationPolicy policy;
@property(nonatomic, strong) NSDictionary *jwks;
@property(nonatomic, strong) NSLock *refreshLock;
@property(nonatomic, strong) NSLock *cacheLock;
@property(nonatomic, assign) NSTimeInterval expires;
@property(nonatomic, assign) NSTimeInterval nextRefresh;
@property(nonatomic, weak) ALNApplication *application;
@end
@interface ALNOAuthMetadataController : ALNController
@end
@implementation ALNOAuthMetadataController
- (id)metadata:(ALNContext *)context {
  ALNOAuthResourceServer *server = context.stash[ServerKey];
  if (!server) { context.response.statusCode = 503; return @{}; }
  return [server protectedResourceMetadata];
}
@end
@implementation ALNOAuthResourceServer
- (instancetype)initWithConfiguration:(NSDictionary *)configuration documentLoader:(ALNOAuthDocumentLoader)loader
                  authorizationPolicy:(ALNOAuthAuthorizationPolicy)policy error:(NSError **)error {
  if (!(self = [super init])) return nil;
  if (!D(configuration)) return Fail(error, @"OAuth configuration must be an object");
  NSMutableDictionary *c = [configuration mutableCopy];
  for (NSString *key in @[@"issuer", @"discoveryURL", @"resourceURL", @"authorizationServer"]) if (!HTTPS(c[key])) return Fail(error, @"OAuth requires explicit trusted HTTPS issuer, discovery, resource and authorization server URLs");
  if (!S(c[@"audience"])) return Fail(error, @"OAuth audience is required");
  c[@"algorithms"] = c[@"algorithms"] ?: @[@"RS256"];
  if (![c[@"algorithms"] isEqual:@[@"RS256"]]) return Fail(error, @"OAuth currently supports only the explicit RS256 algorithm allowlist");
  c[@"protectedPaths"] = c[@"protectedPaths"] ?: @[@"/"];
  c[@"scopesSupported"] = c[@"scopesSupported"] ?: @[];
  c[@"jwksAllowedHosts"] = c[@"jwksAllowedHosts"] ?: @[[NSURL URLWithString:c[@"discoveryURL"]].host];
  for (NSString *key in @[@"protectedPaths", @"scopesSupported", @"jwksAllowedHosts"]) if (!Strings(c[key])) return Fail(error, @"OAuth lists must contain nonempty safe strings");
  if (![c[@"protectedPaths"] count] || ![c[@"jwksAllowedHosts"] count]) return Fail(error, @"OAuth protected paths and JWKS hosts cannot be empty");
  for (NSString *path in c[@"protectedPaths"]) if (!Path(path)) return Fail(error, @"OAuth protected paths must be literal path prefixes");
  NSURL *resource = [NSURL URLWithString:c[@"resourceURL"]];
  if (!Path(resource.path) || [resource.path isEqual:@"/"]) return Fail(error, @"OAuth resource requires a canonical non-root path");
  c[@"jwksMaxAgeSeconds"] = c[@"jwksMaxAgeSeconds"] ?: @300;
  c[@"refreshCooldownSeconds"] = c[@"refreshCooldownSeconds"] ?: @30;
  if (!Number(c[@"jwksMaxAgeSeconds"]) || [c[@"jwksMaxAgeSeconds"] doubleValue] < 30 || [c[@"jwksMaxAgeSeconds"] doubleValue] > 3600 ||
      !Number(c[@"refreshCooldownSeconds"]) || [c[@"refreshCooldownSeconds"] doubleValue] < 5 || [c[@"refreshCooldownSeconds"] doubleValue] > [c[@"jwksMaxAgeSeconds"] doubleValue]) return Fail(error, @"OAuth cache age must be 30..3600 seconds and refresh cooldown 5..cache age");
  for (NSString *key in @[@"refreshOnRequest", @"preflightOnStart"]) {
    if (c[key] && ![c[key] isKindOfClass:[NSNumber class]]) return Fail(error, @"OAuth refresh/preflight settings must be booleans");
  }
  c[@"refreshOnRequest"] = c[@"refreshOnRequest"] ?: @YES;
  c[@"preflightOnStart"] = c[@"preflightOnStart"] ?: @NO;
  _refreshLock = [NSLock new];
  // Guards the key cache; libobjc2's first @synchronized on an instance can
  // race (gnustep/libobjc2#424).
  _cacheLock = [NSLock new];
  c[@"profile"] = c[@"profile"] ?: @"rfc9068";
  if (![@[@"rfc9068", @"entra"] containsObject:c[@"profile"]]) return Fail(error, @"Unknown access-token profile");
  if ([c[@"profile"] isEqual:@"rfc9068"]) {
    c[@"permissionTypeClaim"] = c[@"permissionTypeClaim"] ?: @"idtyp";
    c[@"delegatedPermissionValue"] = c[@"delegatedPermissionValue"] ?: @"user";
    c[@"applicationPermissionValue"] = c[@"applicationPermissionValue"] ?: @"app";
    if (!S(c[@"permissionTypeClaim"]) || !S(c[@"delegatedPermissionValue"]) || !S(c[@"applicationPermissionValue"]) ||
        [c[@"delegatedPermissionValue"] isEqual:c[@"applicationPermissionValue"]]) return Fail(error, @"Invalid OAuth permission-type claim mapping");
  }
  if ([c[@"profile"] isEqual:@"entra"] && (!S(c[@"tenantID"]) || ![@[@"1.0", @"2.0"] containsObject:c[@"tokenVersion"]])) return Fail(error, @"Entra requires tenantID and tokenVersion");
  if (c[@"allowApplicationPermissions"] && ![c[@"allowApplicationPermissions"] isKindOfClass:[NSNumber class]]) return Fail(error, @"allowApplicationPermissions must be boolean");
  if ([c[@"allowApplicationPermissions"] boolValue] && !policy) return Fail(error, @"Application permissions require an explicit authorization policy");
  NSData *encoded = [ALNJSONSerialization dataWithJSONObject:c options:0 error:NULL];
  if (!encoded) return Fail(error, @"OAuth configuration must be JSON serializable");
  _configuration = [ALNJSONSerialization JSONObjectWithData:encoded options:0 error:NULL];
  _metadataPath = [@"/.well-known/oauth-protected-resource" stringByAppendingString:resource.path];
  NSString *origin = [c[@"resourceURL"] substringToIndex:[c[@"resourceURL"] length] - resource.path.length];
  _metadataURL = [origin stringByAppendingString:_metadataPath];
  _policy = [policy copy];
  _loader = ^NSDictionary *(NSURL *url, NSError **fetchError) {
    NSData *data = ALNBoundedMetadataGETWithError(url, 262144, 5, fetchError);
    id result = data ? [ALNJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (data && !D(result)) Fail(fetchError, @"Metadata JSON object invalid");
    return D(result) ? result : nil;
  };
  _usesDefaultLoader = loader == nil;
  if (loader) _loader = [loader copy];
  return self;
}
+ (NSDictionary *)entraConfigurationForTenant:(NSString *)tenant tokenVersion:(NSString *)version audience:(NSString *)audience
                                 resourceURL:(NSString *)resourceURL scopes:(NSArray *)scopes error:(NSError **)error {
  if (![[NSUUID alloc] initWithUUIDString:tenant] || ![@[@"1.0", @"2.0"] containsObject:version] || !S(audience) ||
      ([version isEqual:@"2.0"] && ![[NSUUID alloc] initWithUUIDString:audience])) return Fail(error, @"Entra preset requires tenant GUID, version 1.0/2.0 and matching API audience (GUID for v2)");
  NSString *authority = [@"https://login.microsoftonline.com/" stringByAppendingString:[tenant lowercaseString]];
  BOOL v2 = [version isEqual:@"2.0"];
  return @{@"profile":@"entra", @"tenantID":[tenant lowercaseString], @"tokenVersion":version, @"audience":audience,
    @"issuer":v2 ? [authority stringByAppendingString:@"/v2.0"] : [NSString stringWithFormat:@"https://sts.windows.net/%@/", [tenant lowercaseString]],
    @"discoveryURL":[authority stringByAppendingString:v2 ? @"/v2.0/.well-known/openid-configuration" : @"/.well-known/openid-configuration"],
    @"authorizationServer":[authority stringByAppendingString:@"/v2.0"], @"resourceURL":resourceURL,
    @"scopesSupported":scopes, @"algorithms":@[@"RS256"], @"allowApplicationPermissions":@NO};
}
- (NSDictionary *)keyForID:(NSString *)kid {
  NSDictionary *selected = nil;
  for (NSDictionary *key in self.jwks[@"keys"]) if ([key[@"kid"] isEqual:kid]) {
    if (selected) return nil; // Ambiguous key IDs fail closed.
    selected = key;
  }
  return selected;
}
- (BOOL)fetchSigningKeysWithError:(NSError **)error {
  [self.cacheLock lock];
  @try {
    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    if (now < self.nextRefresh) { Fail(error, @"OAuth key refresh in cooldown"); return NO; }
    self.nextRefresh = now + [self.configuration[@"refreshCooldownSeconds"] doubleValue];
  } @finally {
    [self.cacheLock unlock];
  }
  NSError *fetchError = nil;
  NSDictionary *metadata = self.loader([NSURL URLWithString:self.configuration[@"discoveryURL"]], &fetchError);
  if (!metadata) {
    Fail(error, [@"OAuth discovery fetch failed: " stringByAppendingString:
        self.usesDefaultLoader && [fetchError.domain isEqual:@"Arlen.Metadata"] ? fetchError.localizedDescription : @"metadata unavailable or invalid"]);
    return NO;
  }
  Fail(error, @"OAuth discovery validation failed");
  if (!D(metadata) || ![metadata[@"issuer"] isEqual:self.configuration[@"issuer"]] || !HTTPS(metadata[@"jwks_uri"])) return NO;
  NSURL *url = [NSURL URLWithString:metadata[@"jwks_uri"]];
  if (![self.configuration[@"jwksAllowedHosts"] containsObject:url.host]) return NO;
  fetchError = nil;
  NSDictionary *keys = self.loader(url, &fetchError);
  if (!keys) {
    Fail(error, [@"OAuth JWKS fetch failed: " stringByAppendingString:
        self.usesDefaultLoader && [fetchError.domain isEqual:@"Arlen.Metadata"] ? fetchError.localizedDescription : @"metadata unavailable or invalid"]);
    return NO;
  }
  Fail(error, @"OAuth JWKS validation failed");
  if (!D(keys) || ![keys[@"keys"] isKindOfClass:[NSArray class]] || ![keys[@"keys"] count] || [keys[@"keys"] count] > 64) return NO;
  for (id key in keys[@"keys"]) if (!D(key)) return NO;
  NSData *snapshot = [ALNJSONSerialization dataWithJSONObject:keys options:0 error:NULL];
  if (!snapshot || snapshot.length > 262144) return NO;
  [self.cacheLock lock];
  @try {
    self.jwks = [ALNJSONSerialization JSONObjectWithData:snapshot options:0 error:NULL];
    self.expires = [NSProcessInfo processInfo].systemUptime + [self.configuration[@"jwksMaxAgeSeconds"] doubleValue];
  } @finally {
    [self.cacheLock unlock];
  }
  return YES;
}
- (BOOL)refreshSigningKeysWithError:(NSError **)error {
  // Serialize fetchers separately from cache readers. No network under the cache monitor.
  [self.refreshLock lock];
  @try {
    if ([self fetchSigningKeysWithError:error]) { if (error) *error = nil; return YES; }
    return NO;
  } @finally { [self.refreshLock unlock]; }
}
- (BOOL)isReady {
  [self.cacheLock lock];
  @try {
    return self.jwks != nil && [NSProcessInfo processInfo].systemUptime < self.expires;
  } @finally {
    [self.cacheLock unlock];
  }
}
- (BOOL)applicationWillStart:(ALNApplication *)application error:(NSError **)error {
  if (![self.configuration[@"preflightOnStart"] boolValue]) return YES;
  if (![self isReady]) [self refreshSigningKeysWithError:error];
  return [self isReady];
}
- (NSDictionary *)principalForAccessToken:(NSString *)token error:(NSError **)error {
  if (!S(token) || token.length > 32768) return Fail(error, @"Invalid access token");
  NSArray *parts = [token componentsSeparatedByString:@"."];
  if (parts.count != 3) return Fail(error, @"Invalid access token");
  NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"] invertedSet];
  for (NSString *part in parts) if (!part.length || [part rangeOfCharacterFromSet:invalid].location != NSNotFound) return Fail(error, @"Invalid access token encoding");
  NSDictionary *header = Part(parts[0]);
  BOOL entra = [self.configuration[@"profile"] isEqual:@"entra"];
  if (![header[@"alg"] isEqual:@"RS256"] || !S(header[@"kid"]) || [header[@"kid"] length] > 256 || header[@"crit"] || header[@"b64"] ||
      !(entra ? [header[@"typ"] isEqual:@"JWT"] : [@[@"at+jwt", @"application/at+jwt"] containsObject:header[@"typ"] ?: @""])) return Fail(error, @"Unsupported access token header");
  NSDictionary *key;
  BOOL needsRefresh;
  [self.cacheLock lock];
  @try {
    needsRefresh = [NSProcessInfo processInfo].systemUptime >= self.expires || ![self keyForID:header[@"kid"]];
  } @finally {
    [self.cacheLock unlock];
  }
  if (needsRefresh && [self.configuration[@"refreshOnRequest"] boolValue]) [self refreshSigningKeysWithError:NULL];
  [self.cacheLock lock];
  @try {
    key = [NSProcessInfo processInfo].systemUptime < self.expires ? [self keyForID:header[@"kid"]] : nil;
  } @finally {
    [self.cacheLock unlock];
  }
  if (!key || !S(key[@"n"]) || !S(key[@"e"]) || [key[@"e"] length] > 16 || ![key[@"kty"] isEqual:@"RSA"] || (key[@"use"] && ![key[@"use"] isEqual:@"sig"]) ||
      (key[@"alg"] && ![key[@"alg"] isEqual:@"RS256"]) || (key[@"key_ops"] && ![key[@"key_ops"] isEqual:@[@"verify"]]) ||
      ALNDataFromBase64URLString(key[@"n"]).length < 256 || ALNDataFromBase64URLString(key[@"n"]).length > 1024) return Fail(error, @"No trusted signing key");
  if (key[@"issuer"]) {
    NSString *issuer = S(key[@"issuer"]) ? key[@"issuer"] : @"";
    if (entra) issuer = [issuer stringByReplacingOccurrencesOfString:@"{tenantid}" withString:self.configuration[@"tenantID"]];
    if (![issuer isEqual:self.configuration[@"issuer"]]) return Fail(error, @"Signing key issuer mismatch");
  }
  if (![ALNOIDCClient verifyRS256Token:token jwk:key error:NULL]) return Fail(error, @"Invalid access token signature");
  NSDictionary *claims = Part(parts[1]);
  NSTimeInterval now = [NSDate date].timeIntervalSince1970;
  if (![claims[@"iss"] isEqual:self.configuration[@"issuer"]] || ![claims[@"aud"] isEqual:self.configuration[@"audience"]] ||
      !S(claims[@"sub"]) || !Number(claims[@"exp"]) || [claims[@"exp"] doubleValue] <= now ||
      !Number(claims[@"iat"]) || [claims[@"iat"] doubleValue] > now ||
      (claims[@"nbf"] && (!Number(claims[@"nbf"]) || [claims[@"nbf"] doubleValue] > now))) return Fail(error, @"Invalid access token claims");
  NSString *scope = claims[entra ? @"scp" : @"scope"];
  if (scope && ![scope isKindOfClass:[NSString class]]) return Fail(error, @"Invalid access token permissions");
  NSArray *roles = claims[@"roles"] ?: @[];
  if (!Strings(roles)) return Fail(error, @"Invalid access token roles");
  // RFC 9068 does not standardize a grant-type claim. Require an explicit
  // provider claim mapping instead of mistaking client-credentials scopes for users.
  NSString *typeClaim = self.configuration[@"permissionTypeClaim"];
  BOOL delegated = entra ? scope.length > 0 : [claims[typeClaim] isEqual:self.configuration[@"delegatedPermissionValue"]];
  if (!entra && !delegated && ![claims[typeClaim] isEqual:self.configuration[@"applicationPermissionValue"]]) return Fail(error, @"Unknown access token permission type");
  NSString *client = claims[entra ? ([self.configuration[@"tokenVersion"] isEqual:@"2.0"] ? @"azp" : @"appid") : @"client_id"];
  if (!S(client)) return Fail(error, @"Access token client identity required");
  if (entra && (![claims[@"tid"] isEqual:self.configuration[@"tenantID"]] || !S(claims[@"oid"]) ||
                ![claims[@"ver"] isEqual:self.configuration[@"tokenVersion"]] || !Number(claims[@"nbf"]) ||
                (delegated && [claims[@"idtyp"] isEqual:@"app"]) || (!delegated && ![claims[@"idtyp"] isEqual:@"app"]))) return Fail(error, @"Invalid Entra access token profile");
  if (!delegated && (![self.configuration[@"allowApplicationPermissions"] boolValue] || !roles.count)) return Fail(error, @"Application access is disabled");
  // Entra ID tokens cannot satisfy the delegated scp profile or app-only idtyp profile.
  // API and interactive client registrations MUST have different audiences.
  NSArray *scopes = [ALNAuth scopesFromClaims:@{@"scope":scope ?: @""}];
  NSString *subject = entra ? [NSString stringWithFormat:@"%@:%@", claims[@"tid"], claims[@"oid"]] : claims[@"sub"];
  return @{@"subject":subject, @"issuer":claims[@"iss"], @"tenantID":entra ? claims[@"tid"] : @"",
    @"objectID":entra ? claims[@"oid"] : @"", @"tokenSubject":claims[@"sub"], @"clientID":client,
    @"permissionType":delegated ? @"delegated" : @"application", @"scopes":delegated ? scopes : @[], @"roles":roles,
    @"expiresAt":claims[@"exp"], @"resource":self.configuration[@"resourceURL"]};
}
- (NSDictionary *)protectedResourceMetadata {
  return @{@"resource":self.configuration[@"resourceURL"], @"authorization_servers":@[self.configuration[@"authorizationServer"]],
    @"scopes_supported":self.configuration[@"scopesSupported"], @"bearer_methods_supported":@[@"header"]};
}
- (NSString *)challengeForError:(NSString *)error {
  NSMutableString *value = [NSMutableString stringWithFormat:@"Bearer resource_metadata=\"%@\"", self.metadataURL];
  if ([@[@"invalid_token", @"insufficient_scope"] containsObject:error ?: @""]) [value appendFormat:@", error=\"%@\"", error];
  if ([self.configuration[@"scopesSupported"] count]) [value appendFormat:@", scope=\"%@\"", [self.configuration[@"scopesSupported"] componentsJoinedByString:@" "]];
  return value;
}
- (BOOL)protectsPath:(NSString *)path {
  for (NSString *prefix in self.configuration[@"protectedPaths"]) if ([prefix isEqual:@"/"] || [path isEqual:prefix] || [path hasPrefix:[prefix stringByAppendingString:@"/"]]) return YES;
  return NO;
}
- (NSString *)pluginName { return @"oauth-resource-server"; }
- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  if (self.application) { Fail(error, @"OAuth resource server already installed"); return NO; }
  for (ALNRoute *route in [application.router allRoutes]) if ([route.pathPattern isEqual:self.metadataPath]) { Fail(error, @"OAuth metadata route collision"); return NO; }
  self.application = application;
  ALNRoute *route = [application registerRouteMethod:@"GET" path:self.metadataPath name:@"oauth.resource.metadata" controllerClass:[ALNOAuthMetadataController class] action:@"metadata"];
  route.includeInOpenAPI = NO;
  [application addMiddleware:self];
  [application registerLifecycleHook:self];
  return YES;
}
- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  if ([context.request.path isEqual:self.metadataPath]) {
    context.stash[ServerKey] = self;
    context.stash[ALNResponseEnvelopeDisabledStashKey] = @YES;
    [context.response setHeader:@"Cache-Control" value:@"no-store"];
    return YES;
  }
  if (![self protectsPath:context.request.path]) return YES;
  // Always validate original bearer credentials; session/HS256 identities cannot bypass this mode.
  NSString *header = [context.request headerValueForName:@"authorization"];
  NSString *token = [ALNAuth bearerTokenFromAuthorizationHeader:header error:NULL];
  NSDictionary *principal = [self principalForAccessToken:token error:NULL];
  if (!principal) {
    [context.response setHeader:@"WWW-Authenticate" value:[self challengeForError:header.length ? @"invalid_token" : nil]];
    context.response.statusCode = 401; context.response.committed = YES; return NO;
  }
  context.stash[ALNOAuthPrincipalStashKey] = principal;
  [ALNAuth applyClaims:@{@"sub":principal[@"subject"], @"scopes":principal[@"scopes"], @"roles":principal[@"roles"]} toContext:context];
  if (self.policy && !self.policy(principal, context)) {
    context.response.statusCode = 403; context.response.committed = YES; return NO;
  }
  return YES;
}
- (void)didProcessContext:(ALNContext *)context {
  if (![self protectsPath:context.request.path] || [context.request.path isEqual:self.metadataPath]) return;
  [context.response setHeader:@"Cache-Control" value:@"no-store"];
  if (context.response.statusCode == 401 && ![context.request headerValueForName:@"authorization"].length) {
    [context.response setHeader:@"WWW-Authenticate" value:[self challengeForError:nil]];
  } else if (context.response.statusCode == 401 || context.response.statusCode == 403) {
    [context.response setHeader:@"WWW-Authenticate" value:[self challengeForError:context.response.statusCode == 401 ? @"invalid_token" : @"insufficient_scope"]];
  }
}
@end
