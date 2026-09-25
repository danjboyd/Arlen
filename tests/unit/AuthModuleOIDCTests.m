#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <openssl/evp.h>
#import <openssl/pem.h>
#import "ALNCryptoCompat.h"
#import "ALNSecurityPrimitives.h"
#import "ALNAuthModule.h"
#import "ALNEOCRuntime.h"
#import "ALNAuthModuleOIDC.h"
#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNLogger.h"
#import "ALNPerf.h"
#import "ALNSessionMiddleware.h"
static NSDictionary *OIDCTestRSAKeyMaterial(NSString *kid) {
  NSMutableDictionary *material = [NSMutableDictionary dictionary];
  EVP_PKEY *privateKey = ALNCryptoGenerateRSAKey(2048);
  NSString *privateKeyPEM = ALNCryptoCopyPEMStringForPrivateKey(privateKey);
  NSDictionary *jwk = ALNCryptoCopyRSAJWK(privateKey, kid);
  if ([privateKeyPEM length] == 0) {
    EVP_PKEY_free(privateKey);
    return material;
  }
  if (![jwk isKindOfClass:[NSDictionary class]]) {
    EVP_PKEY_free(privateKey);
    return material;
  }

  material[@"kid"] = kid ?: @"test-key";
  material[@"privateKeyPEM"] = privateKeyPEM;
  material[@"jwk"] = jwk;
  EVP_PKEY_free(privateKey);
  return material;
}

static NSString *OIDCTestRS256JWT(NSDictionary *claims, NSString *privateKeyPEM, NSString *kid) {
  NSDictionary *header = @{
    @"alg" : @"RS256",
    @"typ" : @"JWT",
    @"kid" : kid ?: @"test-key",
  };
  NSData *headerData = [NSJSONSerialization dataWithJSONObject:header options:0 error:NULL];
  NSData *claimsData = [NSJSONSerialization dataWithJSONObject:claims options:0 error:NULL];
  NSString *headerPart = ALNBase64URLStringFromData(headerData) ?: @"";
  NSString *claimsPart = ALNBase64URLStringFromData(claimsData) ?: @"";
  NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerPart, claimsPart];

  BIO *privateBIO = BIO_new_mem_buf((void *)[privateKeyPEM UTF8String], -1);
  EVP_PKEY *privateKey =
      (privateBIO != NULL) ? PEM_read_bio_PrivateKey(privateBIO, NULL, NULL, NULL) : NULL;
  EVP_MD_CTX *ctx = (privateKey != NULL) ? EVP_MD_CTX_new() : NULL;
  NSMutableData *signature = nil;

  if (ctx != NULL &&
      EVP_DigestSignInit(ctx, NULL, EVP_sha256(), NULL, privateKey) == 1 &&
      EVP_DigestSignUpdate(ctx, [signingInput UTF8String], strlen([signingInput UTF8String])) == 1) {
    size_t signatureLength = 0;
    if (EVP_DigestSignFinal(ctx, NULL, &signatureLength) == 1 && signatureLength > 0) {
      signature = [NSMutableData dataWithLength:signatureLength];
      if (EVP_DigestSignFinal(ctx, [signature mutableBytes], &signatureLength) == 1) {
        [signature setLength:signatureLength];
      } else {
        signature = nil;
      }
    }
  }

  EVP_MD_CTX_free(ctx);
  EVP_PKEY_free(privateKey);
  BIO_free(privateBIO);

  NSString *signaturePart = ALNBase64URLStringFromData(signature) ?: @"";
  return [NSString stringWithFormat:@"%@.%@.%@", headerPart, claimsPart, signaturePart];
}


@interface ModuleOIDCFixture : NSObject <ALNAuthModuleOIDCTransport>
@property(nonatomic, copy) NSDictionary *material;
@property(nonatomic, strong) NSMutableDictionary *metadata;
@property(nonatomic, strong) NSMutableDictionary *claims;
@property(nonatomic, copy) NSString *lastBody;
@property(nonatomic, assign) NSUInteger exchanges;
@property(nonatomic, strong) NSMutableSet *redeemedCodes;
@property(nonatomic, assign) BOOL failTransport;
@property(nonatomic, assign) BOOL badSignature;
@property(nonatomic, assign) BOOL badAlgorithm;
@property(nonatomic, copy) NSString *lastKeysHost;
@end
static ModuleOIDCFixture *OIDCFixture;
@implementation ModuleOIDCFixture
- (instancetype)init {
  if ((self = [super init])) {
    self.redeemedCodes = [NSMutableSet set];
    self.material = OIDCTestRSAKeyMaterial(@"key-1");
    self.metadata = [@{ @"issuer": @"https://issuer.example/tenant/v2.0",
      @"authorization_endpoint": @"https://issuer.example/authorize",
      @"token_endpoint": @"https://issuer.example/token", @"jwks_uri": @"https://issuer.example/keys" } mutableCopy];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    self.claims = [@{ @"iss": self.metadata[@"issuer"], @"aud": @"client", @"sub": @"pairwise",
      @"tid": @"tenant", @"oid": @"known", @"email": @"same@example.test", @"nonce": @"pending",
      @"iat": @(now), @"exp": @(now + 600) } mutableCopy];
    OIDCFixture = self;
  }
  return self;
}
- (NSData *)performOIDCRequest:(NSURLRequest *)request error:(NSError **)error {
  if (self.failTransport) return nil;
  id response = self.metadata;
  if ([request.HTTPMethod isEqual:@"POST"]) {
    self.exchanges++;
    self.lastBody = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
    NSString *token = OIDCTestRS256JWT(self.claims, self.material[@"privateKeyPEM"], @"key-1");
    if (self.badSignature) token = [token stringByAppendingString:@"x"];
    if (self.badAlgorithm) token = @"eyJhbGciOiJIUzI1NiJ9.e30.signature";
    NSString *code = nil;
    for (NSURLQueryItem *item in [NSURLComponents componentsWithString:[@"https://fixture/?" stringByAppendingString:self.lastBody]].queryItems)
      if ([item.name isEqual:@"code"]) code = item.value;
    if (!code || [self.redeemedCodes containsObject:code]) response = @{ @"error": @"invalid_grant" };
    else {
      [self.redeemedCodes addObject:code];
      response = @{ @"id_token": token, @"access_token": @"must-not-be-in-session" };
    }
  } else if ([request.URL.path isEqual:@"/keys"] || [request.URL.path isEqual:@"/oauth2/v3/certs"]) {
    self.lastKeysHost = request.URL.host;
    response = @{ @"keys": @[ self.material[@"jwk"] ] };
  }
  return [NSJSONSerialization dataWithJSONObject:response options:0 error:NULL];
}
@end

@interface ModuleOIDCResolver : NSObject <ALNAuthProviderSessionResolver>
@end
static NSUInteger ResolverCalls;
static NSDictionary *ResolvedIdentity;
@implementation ModuleOIDCResolver
- (NSDictionary *)resolveSessionDescriptorForNormalizedIdentity:(NSDictionary *)identity
                                         providerConfiguration:(NSDictionary *)config error:(NSError **)error {
  ResolverCalls++;
  ResolvedIdentity = identity;
  if (![identity[@"provider_subject"] isEqual:@"tenant:known"]) return nil;
  return @{ @"subject": @"person-42", @"roles": @[ @"staff" ], @"assuranceLevel": @1 };
}
@end

@interface AdmissionOIDCResolver : NSObject <ALNAuthProviderSessionResolver>
@end
@implementation AdmissionOIDCResolver
- (NSDictionary *)resolveSessionDescriptorForNormalizedIdentity:(NSDictionary *)identity
                                         providerConfiguration:(NSDictionary *)config error:(NSError **)error {
  ResolverCalls++;
  ResolvedIdentity = identity;
  return @{ @"subject": [@"person-" stringByAppendingString:identity[@"provider_subject"] ?: @""] };
}
@end

// Other unit cases clear the process-global registry. Register exactly the real
// compiled templates used by this test instead of depending on constructor order.
static void RegisterOIDCLoginTemplates(void) {
  extern NSString *ALNEOCRender_modules_auth_login_index_html_eoc(id, NSError **);
  ALNEOCRegisterTemplate(@"modules/auth/login/index.html.eoc", &ALNEOCRender_modules_auth_login_index_html_eoc);
  extern NSString *ALNEOCRender_modules_auth_layouts_main_html_eoc(id, NSError **);
  ALNEOCRegisterTemplate(@"modules/auth/layouts/main.html.eoc", &ALNEOCRender_modules_auth_layouts_main_html_eoc);
  extern NSString *ALNEOCRender_modules_auth_partials_page_wrapper_html_eoc(id, NSError **);
  ALNEOCRegisterTemplate(@"modules/auth/partials/page_wrapper.html.eoc", &ALNEOCRender_modules_auth_partials_page_wrapper_html_eoc);
  extern NSString *ALNEOCRender_modules_auth_partials_message_block_html_eoc(id, NSError **);
  ALNEOCRegisterTemplate(@"modules/auth/partials/message_block.html.eoc", &ALNEOCRender_modules_auth_partials_message_block_html_eoc);
  extern NSString *ALNEOCRender_modules_auth_partials_error_block_html_eoc(id, NSError **);
  ALNEOCRegisterTemplate(@"modules/auth/partials/error_block.html.eoc", &ALNEOCRender_modules_auth_partials_error_block_html_eoc);
  extern NSString *ALNEOCRender_modules_auth_partials_bodies_login_body_html_eoc(id, NSError **);
  ALNEOCRegisterTemplate(@"modules/auth/partials/bodies/login_body.html.eoc", &ALNEOCRender_modules_auth_partials_bodies_login_body_html_eoc);
  extern NSString *ALNEOCRender_modules_auth_fragments_provider_login_buttons_html_eoc(id, NSError **);
  ALNEOCRegisterTemplate(@"modules/auth/fragments/provider_login_buttons.html.eoc", &ALNEOCRender_modules_auth_fragments_provider_login_buttons_html_eoc);
  extern NSString *ALNEOCRender_modules_auth_partials_provider_row_html_eoc(id, NSError **);
  ALNEOCRegisterTemplate(@"modules/auth/partials/provider_row.html.eoc", &ALNEOCRender_modules_auth_partials_provider_row_html_eoc);
}

@interface AuthModuleOIDCTests : XCTestCase
@end
@implementation AuthModuleOIDCTests
- (void)setUp { ResolverCalls = 0; ResolvedIdentity = nil; OIDCFixture = nil; }
- (NSDictionary *)config {
  return @{ @"enabled": @YES, @"type": @"oidc", @"issuer": @"https://issuer.example/tenant/v2.0",
    @"discoveryURL": @"https://issuer.example/discovery", @"redirectURI": @"https://app.example/context/auth/provider/entra/callback",
    @"clientID": @"client", @"tokenEndpointAuthMethod": @"none", @"scopes": @[ @"openid", @"profile", @"email" ],
    @"subjectClaim": @"oid", @"tenantClaim": @"tid", @"allowedTenants": @[ @"tenant" ],
    @"jwksAllowedHosts": @[ @"issuer.example" ] };
}
- (ALNAuthModuleOIDC *)provider {
  NSError *error = nil;
  ALNAuthModuleOIDC *provider = [[ALNAuthModuleOIDC alloc] initWithIdentifier:@"entra" configuration:[self config]
     resolver:[ModuleOIDCResolver new] transport:[ModuleOIDCFixture new] error:&error];
  XCTAssertNotNil(provider); XCTAssertNil(error);
  return provider;
}
- (ALNContext *)context {
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET" path:@"/auth/provider/entra/callback"
      queryString:@"" headers:@{} body:[NSData data]];
  return [[ALNContext alloc] initWithRequest:request response:[ALNResponse new] params:@{}
     stash:[NSMutableDictionary dictionary] logger:[[ALNLogger alloc] initWithFormat:@"text"]
     perfTrace:[[ALNPerfTrace alloc] initWithEnabled:NO] routeName:@"callback" controllerName:@"Auth" actionName:@"callback"];
}
- (NSMutableDictionary *)stateForProvider:(ALNAuthModuleOIDC *)provider {
  NSError *error = nil;
  NSMutableDictionary *state = [[provider beginLoginWithError:&error] mutableCopy];
  XCTAssertNotNil(state); XCTAssertNil(error);
  OIDCFixture.claims[@"nonce"] = state[@"nonce"];
  return state;
}
- (NSDictionary *)complete:(ALNAuthModuleOIDC *)provider state:(NSDictionary *)state context:(ALNContext *)context error:(NSError **)error {
  return [provider completeLoginWithParameters:@{ @"code": @"authorization-code", @"state": state[@"state"] ?: @"" }
      callbackState:state context:context error:error];
}
- (void)testPKCEAndVerifiedTenantIdentityEstablishApplicationSession {
  ALNAuthModuleOIDC *provider = [self provider];
  NSDictionary *state = [self stateForProvider:provider];
  XCTAssertTrue([state[@"authorizationURL"] containsString:@"code_challenge_method=S256"]);
  XCTAssertTrue([state[@"codeVerifier"] length] >= 43);
  ALNContext *context = [self context];
  NSError *error = nil;
  NSDictionary *completed = [self complete:provider state:state context:context error:&error];
  XCTAssertNotNil(completed);
  XCTAssertEqualObjects(@"tenant:known", completed[@"normalizedIdentity"][@"provider_subject"]);
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"person-42", [context authSubject]);
  XCTAssertEqualObjects(@[ @"staff" ], [context authRoles]);
  XCTAssertEqualObjects(@"tenant:known", ResolvedIdentity[@"provider_subject"]);
  XCTAssertTrue([OIDCFixture.lastBody containsString:state[@"codeVerifier"]]);
  XCTAssertTrue([OIDCFixture.lastBody containsString:@"grant_type=authorization_code"]);
  XCTAssertFalse([[context.session description] containsString:@"must-not-be-in-session"]);
}
- (void)testIdentityAndTokenFailuresNeverEstablishSession {
  for (NSString *scenario in @[ @"tenant", @"unknown", @"subject", @"nonce", @"issuer", @"audience", @"expired", @"signature", @"algorithm", @"azp", @"multi-audience" ]) {
    ALNAuthModuleOIDC *provider = [self provider];
    NSDictionary *state = [self stateForProvider:provider];
    if ([scenario isEqual:@"tenant"]) OIDCFixture.claims[@"tid"] = @"other";
    if ([scenario isEqual:@"unknown"]) OIDCFixture.claims[@"oid"] = @"unknown-same-email";
    if ([scenario isEqual:@"subject"]) [OIDCFixture.claims removeObjectForKey:@"oid"];
    if ([scenario isEqual:@"nonce"]) OIDCFixture.claims[@"nonce"] = @"wrong";
    if ([scenario isEqual:@"issuer"]) OIDCFixture.claims[@"iss"] = @"https://other.example";
    if ([scenario isEqual:@"audience"]) OIDCFixture.claims[@"aud"] = @"other-client";
    if ([scenario isEqual:@"expired"]) OIDCFixture.claims[@"exp"] = @1;
    if ([scenario isEqual:@"azp"]) OIDCFixture.claims[@"azp"] = @"wrong-client";
    if ([scenario isEqual:@"multi-audience"]) OIDCFixture.claims[@"aud"] = @[ @"client", @"other" ];
    OIDCFixture.badSignature = [scenario isEqual:@"signature"];
    OIDCFixture.badAlgorithm = [scenario isEqual:@"algorithm"];
    ALNContext *context = [self context];
    NSError *error = nil;
    XCTAssertNil([self complete:provider state:state context:context error:&error], @"%@", scenario);
    XCTAssertNotNil(error, @"%@", scenario);
    XCTAssertFalse([context authSubject].length > 0, @"%@", scenario);
  }
}
- (void)testCallbackBindingFailsBeforeNetwork {
  for (NSString *key in @[ @"nonce", @"codeVerifier", @"provider", @"redirectURI", @"issuedAt" ]) {
    ALNAuthModuleOIDC *provider = [self provider];
    NSMutableDictionary *state = [self stateForProvider:provider];
    [state removeObjectForKey:key];
    XCTAssertNil([self complete:provider state:state context:[self context] error:NULL]);
    XCTAssertEqual((NSUInteger)0, OIDCFixture.exchanges);
  }
  ALNAuthModuleOIDC *provider = [self provider];
  NSMutableDictionary *state = [self stateForProvider:provider];
  XCTAssertNil(([provider completeLoginWithParameters:@{ @"code": @"x", @"state": @"wrong" }
      callbackState:state context:[self context] error:NULL]));
  state[@"issuedAt"] = @([[NSDate date] timeIntervalSince1970] - 301);
  XCTAssertNil([self complete:provider state:state context:[self context] error:NULL]);
  XCTAssertEqual((NSUInteger)0, OIDCFixture.exchanges);
}
- (void)testDiscoveryRejectsIssuerAndUntrustedEndpoints {
  for (NSString *key in @[ @"issuer", @"authorization_endpoint", @"token_endpoint", @"jwks_uri" ]) {
    ALNAuthModuleOIDC *provider = [self provider];
    OIDCFixture.metadata[key] = @"https://attacker.example/steal";
    XCTAssertNil([provider beginLoginWithError:NULL]);
    XCTAssertEqual((NSUInteger)0, OIDCFixture.exchanges);
  }
}
- (void)testConfigurationRejectsMissingSecretAndInvalidTenantPolicy {
  for (NSDictionary *change in @[ @{ @"tokenEndpointAuthMethod": @"client_secret_post", @"clientSecretEnvironmentKey": @"ARLEN_TEST_MISSING_OIDC_SECRET" },
                                  @{ @"allowedTenants": @[] }, @{ @"scopes": @[ @"email" ] },
                                  @{ @"redirectURI": @"http://app.example/callback" }, @{ @"type": @"ignored", @"subjectClaim": @"" } ]) {
    NSMutableDictionary *config = [[self config] mutableCopy]; [config addEntriesFromDictionary:change];
    NSError *error = nil;
    XCTAssertNil([[ALNAuthModuleOIDC alloc] initWithIdentifier:@"entra" configuration:config
        resolver:[ModuleOIDCResolver new] transport:nil error:&error]);
    XCTAssertNotNil(error);
  }
}

- (void)testLoopbackHTTPRedirectURIRequiresExplicitAllowance {
  for (NSString *redirect in @[ @"http://localhost:3000/auth/provider/entra/callback",
                                @"http://127.0.0.1:3000/auth/provider/entra/callback",
                                @"http://[::1]:3000/auth/provider/entra/callback" ]) {
    NSMutableDictionary *config = [[self config] mutableCopy];
    config[@"redirectURI"] = redirect;
    NSError *error = nil;
    XCTAssertNotNil([[ALNAuthModuleOIDC alloc] initWithIdentifier:@"entra" configuration:config
        resolver:[ModuleOIDCResolver new] transport:nil allowLoopbackHTTPRedirect:YES error:&error], @"%@ %@", redirect, error);
    XCTAssertNil([[ALNAuthModuleOIDC alloc] initWithIdentifier:@"entra" configuration:config
        resolver:[ModuleOIDCResolver new] transport:nil allowLoopbackHTTPRedirect:NO error:NULL], @"%@", redirect);
    XCTAssertNil([[ALNAuthModuleOIDC alloc] initWithIdentifier:@"entra" configuration:config
        resolver:[ModuleOIDCResolver new] transport:nil error:NULL], @"%@", redirect);
  }
  NSArray *refused = @[
    @{ @"redirectURI": @"http://app.example/callback" },
    @{ @"redirectURI": @"http://localhost.evil.example/callback" },
    @{ @"redirectURI": @"http://127.0.0.2/callback" },
    @{ @"redirectURI": @"http://user:pass@localhost/callback" },
    @{ @"redirectURI": @"ftp://localhost/callback" },
    @{ @"issuer": @"http://localhost/tenant/v2.0" },
    @{ @"discoveryURL": @"http://localhost/discovery", @"endpointAllowedHosts": @[ @"localhost" ] },
  ];
  for (NSDictionary *change in refused) {
    NSMutableDictionary *config = [[self config] mutableCopy];
    config[@"redirectURI"] = @"http://localhost:3000/auth/provider/entra/callback";
    [config addEntriesFromDictionary:change];
    XCTAssertNil([[ALNAuthModuleOIDC alloc] initWithIdentifier:@"entra" configuration:config
        resolver:[ModuleOIDCResolver new] transport:nil allowLoopbackHTTPRedirect:YES error:NULL], @"%@", change);
  }
}
- (void)testModuleAllowsLoopbackRedirectOnlyInDevelopmentAndTest {
  NSMutableDictionary *provider = [[self config] mutableCopy];
  provider[@"redirectURI"] = @"http://localhost:3000/context/auth/provider/entra/callback";
  for (NSString *environment in @[ @"development", @"test", @"production", @"staging" ]) {
    ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
      @"environment": environment, @"csrf": @{ @"enabled": @NO },
      @"database": @{ @"connectionString": @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
      @"authModule": @{ @"paths": @{ @"prefix": @"/context/auth" }, @"providers": @{ @"entra": provider },
        @"hooks": @{ @"providerSessionResolverClass": @"ModuleOIDCResolver", @"oidcTransportClass": @"ModuleOIDCFixture" } }
    }];
    NSError *error = nil;
    BOOL registered = [[[ALNAuthModule alloc] init] registerWithApplication:app error:&error];
    BOOL expected = [environment isEqualToString:@"development"] || [environment isEqualToString:@"test"];
    XCTAssertEqual(expected, registered, @"%@ %@", environment, error);
    if (!expected) {
      XCTAssertTrue([error.localizedDescription containsString:@"redirect"], @"%@ %@", environment, error);
    }
  }
}

- (ALNApplication *)application {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment": @"test", @"csrf": @{ @"enabled": @NO },
    @"database": @{ @"connectionString": @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
    @"authModule": @{ @"paths": @{ @"prefix": @"/context/auth" },
      @"providers": @{ @"entra": [self config] },
      @"hooks": @{ @"providerSessionResolverClass": @"ModuleOIDCResolver", @"oidcTransportClass": @"ModuleOIDCFixture" } }
  }];
  [app addMiddleware:[[ALNSessionMiddleware alloc] initWithSecret:@"test-oidc-session-secret-long-enough-for-signing"
      cookieName:@"oidc_session" maxAgeSeconds:3600 secure:NO sameSite:@"Lax"]];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  XCTAssertNil(error);
  return app;
}
- (ALNResponse *)request:(ALNApplication *)app method:(NSString *)method path:(NSString *)path query:(NSString *)query cookie:(NSString *)cookie {
  return [app dispatchRequest:[[ALNRequest alloc] initWithMethod:method path:path queryString:query
      headers:cookie ? @{ @"cookie": cookie, @"accept": @"application/json" } : @{ @"accept": @"application/json" }
      body:[NSData data]]];
}
- (NSDictionary *)json:(ALNResponse *)response {
  return [NSJSONSerialization JSONObjectWithData:response.bodyData options:0 error:NULL];
}
- (NSString *)cookie:(ALNResponse *)response {
  for (NSString *value in [response headerValuesForName:@"Set-Cookie"])
    if ([value hasPrefix:@"oidc_session="]) return [value componentsSeparatedByString:@";"][0];
  return nil;
}
- (void)testModuleRoutesCompleteLoginAndDisableLocalAndStubByDefault {
  ALNApplication *app = [self application];
  for (NSString *path in @[ @"/login", @"/register", @"/password/forgot", @"/password/reset", @"/password/change" ]) {
    for (NSString *prefix in @[ @"/context/auth", @"/context/auth/api" ]) {
      ALNResponse *response = [self request:app method:@"POST" path:[prefix stringByAppendingString:path] query:@"" cookie:nil];
      XCTAssertEqual((NSInteger)404, response.statusCode, @"%@%@", prefix, path);
    }
  }
  XCTAssertEqual((NSInteger)404, [self request:app method:@"GET" path:@"/context/auth/provider/stub/login" query:@"" cookie:nil].statusCode);
  ALNResponse *login = [self request:app method:@"GET" path:@"/context/auth/api/provider/entra/login" query:@"return_to=%2Fconfirm" cookie:nil];
  XCTAssertEqual((NSInteger)200, login.statusCode, @"%@", [self json:login]);
  NSString *url = [self json:login][@"authorize_url"];
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  for (NSURLQueryItem *item in [NSURLComponents componentsWithString:url].queryItems) parameters[item.name] = item.value;
  OIDCFixture.claims[@"nonce"] = parameters[@"nonce"];
  NSString *cookie = [self cookie:login]; XCTAssertNotNil(cookie);
  NSString *query = [NSString stringWithFormat:@"code=code&state=%@", parameters[@"state"]];
  ALNResponse *callback = [self request:app method:@"GET" path:@"/context/auth/provider/entra/callback" query:query cookie:cookie];
  XCTAssertEqual((NSInteger)200, callback.statusCode, @"%@", [self json:callback]);
  XCTAssertEqualObjects(@"person-42", [self json:callback][@"session"][@"subject"]);
  XCTAssertEqualObjects(@"/confirm", [self json:callback][@"redirect_to"]);
  NSString *authenticatedCookie = [self cookie:callback]; XCTAssertNotNil(authenticatedCookie);
  ALNResponse *session = [self request:app method:@"GET" path:@"/context/auth/api/session" query:@"" cookie:authenticatedCookie];
  XCTAssertTrue([[self json:session][@"authenticated"] boolValue]);
  ALNResponse *replay = [self request:app method:@"GET" path:@"/context/auth/provider/entra/callback" query:query cookie:authenticatedCookie];
  XCTAssertEqual((NSInteger)401, replay.statusCode);
  XCTAssertEqual((NSUInteger)1, OIDCFixture.exchanges);
  // Replaying an older signed cookie still fails at the provider's one-time code exchange.
  replay = [self request:app method:@"GET" path:@"/context/auth/provider/entra/callback" query:query cookie:cookie];
  XCTAssertEqual((NSInteger)401, replay.statusCode);
  XCTAssertEqual((NSUInteger)2, OIDCFixture.exchanges);
}
- (void)testProviderDefaultsAndExplicitOptIns {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime new];
  XCTAssertTrue([runtime configureHooksWithModuleConfig:@{} error:NULL]);
  XCTAssertTrue([runtime isProviderEnabled:@"stub"]);
  XCTAssertTrue(runtime.localPasswordEnabled);
  NSDictionary *hooks = @{ @"providerSessionResolverClass": @"ModuleOIDCResolver", @"oidcTransportClass": @"ModuleOIDCFixture" };
  NSDictionary *config = @{ @"providers": @{ @"entra": [self config] }, @"hooks": hooks };
  XCTAssertTrue([runtime configureHooksWithModuleConfig:config error:NULL]);
  XCTAssertFalse([runtime isProviderEnabled:@"stub"]);
  XCTAssertTrue([runtime isProviderEnabled:@"entra"]);
  XCTAssertFalse(runtime.localPasswordEnabled);
  config = @{ @"providers": @{ @"entra": [self config], @"stub": @{ @"enabled": @YES } },
              @"localPassword": @{ @"enabled": @YES }, @"hooks": hooks };
  XCTAssertTrue([runtime configureHooksWithModuleConfig:config error:NULL]);
  XCTAssertTrue([runtime isProviderEnabled:@"stub"]);
  XCTAssertTrue(runtime.localPasswordEnabled);
}
- (void)testModuleBrowserRedirectAndSafeReturnTarget {
  ALNApplication *app = [self application];
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"GET" path:@"/context/auth/provider/entra/login"
      queryString:@"return_to=https%3A%2F%2Fevil.example" headers:@{} body:[NSData data]];
  ALNResponse *login = [app dispatchRequest:request];
  XCTAssertEqual((NSInteger)302, login.statusCode);
  NSString *url = [login headerForName:@"Location"];
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  for (NSURLQueryItem *item in [NSURLComponents componentsWithString:url].queryItems) parameters[item.name] = item.value;
  OIDCFixture.claims[@"nonce"] = parameters[@"nonce"];
  request = [[ALNRequest alloc] initWithMethod:@"GET" path:@"/context/auth/provider/entra/callback"
      queryString:[NSString stringWithFormat:@"code=code&state=%@", parameters[@"state"]]
      headers:@{ @"cookie": [self cookie:login] ?: @"" } body:[NSData data]];
  ALNResponse *callback = [app dispatchRequest:request];
  XCTAssertEqual((NSInteger)302, callback.statusCode);
  XCTAssertEqualObjects(@"/", [callback headerForName:@"Location"]);
}
- (void)testConfidentialClientSecretIsSentOnlyToTokenEndpoint {
  NSMutableDictionary *config = [[self config] mutableCopy];
  // PATH is a harmless existing environment value, used as a synthetic secret.
  config[@"clientSecretEnvironmentKey"] = @"PATH";
  config[@"tokenEndpointAuthMethod"] = @"client_secret_post";
  ALNAuthModuleOIDC *provider = [[ALNAuthModuleOIDC alloc] initWithIdentifier:@"entra" configuration:config
      resolver:[ModuleOIDCResolver new] transport:[ModuleOIDCFixture new] error:NULL];
  XCTAssertNotNil(provider);
  NSDictionary *state = [self stateForProvider:provider];
  XCTAssertFalse([state[@"authorizationURL"] containsString:@"client_secret"]);
  XCTAssertNotNil([self complete:provider state:state context:[self context] error:NULL]);
  XCTAssertTrue([OIDCFixture.lastBody containsString:@"client_secret="]);
  XCTAssertNil(provider.configuration[@"clientSecret"]);
}
- (void)testEnterpriseLoginPageHasProviderButtonWithoutPasswordForm {
  RegisterOIDCLoginTemplates();
  ALNApplication *app = [self application];
  ALNResponse *response = [app dispatchRequest:[[ALNRequest alloc] initWithMethod:@"GET"
      path:@"/context/auth/login" queryString:@"" headers:@{} body:[NSData data]]];
  NSString *html = [[NSString alloc] initWithData:response.bodyData encoding:NSUTF8StringEncoding];
  XCTAssertEqual((NSInteger)200, response.statusCode, @"%@", html);
  XCTAssertTrue([html containsString:@"/context/auth/provider/entra/login"]);
  XCTAssertFalse([html containsString:@"type=\"password\""]);
  XCTAssertFalse([html containsString:@"provider/stub"]);
}
#pragma mark - Provider presets (issue 60)

- (NSDictionary *)googleProvider {
  return @{ @"enabled": @YES, @"preset": @"google", @"clientID": @"client", @"tokenEndpointAuthMethod": @"none",
            @"redirectURI": @"https://app.example/context/auth/provider/google/callback" };
}
- (NSDictionary *)googleHooks {
  return @{ @"providerSessionResolverClass": @"AdmissionOIDCResolver", @"oidcTransportClass": @"ModuleOIDCFixture" };
}
- (void)useGoogleDiscovery {
  OIDCFixture.metadata = [@{ @"issuer": @"https://accounts.google.com",
    @"authorization_endpoint": @"https://accounts.google.com/o/oauth2/v2/auth",
    @"token_endpoint": @"https://oauth2.googleapis.com/token",
    @"jwks_uri": @"https://www.googleapis.com/oauth2/v3/certs" } mutableCopy];
  OIDCFixture.claims[@"iss"] = @"https://accounts.google.com";
  OIDCFixture.claims[@"sub"] = @"google-subject";
  OIDCFixture.claims[@"email"] = @"kid@family.example";
  OIDCFixture.claims[@"email_verified"] = @YES;
}
- (void)testGooglePresetExpandsDiscoveryAndDerivedHosts {
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime new];
  NSError *error = nil;
  NSDictionary *moduleConfig = @{ @"providers": @{ @"google": [self googleProvider] }, @"hooks": [self googleHooks] };
  XCTAssertTrue([runtime configureHooksWithModuleConfig:moduleConfig error:&error], @"%@", error);
  ALNAuthModuleOIDC *google = [runtime valueForKey:@"oidcProviders"][@"google"];
  XCTAssertNotNil(google);
  NSDictionary *config = google.configuration;
  XCTAssertEqualObjects(@"https://accounts.google.com", config[@"issuer"]);
  XCTAssertEqualObjects(@"https://accounts.google.com/.well-known/openid-configuration", config[@"discoveryURL"]);
  NSArray *expectedHosts = @[ @"accounts.google.com", @"oauth2.googleapis.com" ];
  XCTAssertEqualObjects(expectedHosts, config[@"endpointAllowedHosts"]);
  XCTAssertEqualObjects(@[ @"www.googleapis.com" ], config[@"jwksAllowedHosts"]);
  XCTAssertEqualObjects((@[ @"openid", @"email", @"profile" ]), config[@"scopes"]);
  XCTAssertTrue([runtime isProviderEnabled:@"google"]);
  BOOL foundButton = NO;
  for (NSDictionary *entry in runtime.loginProviders)
    if ([entry[@"identifier"] isEqual:@"google"]) foundButton = [entry[@"ctaLabel"] isEqual:@"Continue with Google"];
  XCTAssertTrue(foundButton);
}
- (void)testGooglePresetExplicitKeysOverridePreset {
  NSMutableDictionary *provider = [[self googleProvider] mutableCopy];
  provider[@"scopes"] = @[ @"openid", @"email" ];
  provider[@"jwksAllowedHosts"] = @[ @"keys.example" ];
  provider[@"ctaLabel"] = @"Sign in with Google";
  ALNAuthModuleRuntime *runtime = [ALNAuthModuleRuntime new];
  NSDictionary *moduleConfig = @{ @"providers": @{ @"google": provider }, @"hooks": [self googleHooks] };
  XCTAssertTrue([runtime configureHooksWithModuleConfig:moduleConfig error:NULL]);
  ALNAuthModuleOIDC *google = [runtime valueForKey:@"oidcProviders"][@"google"];
  NSDictionary *config = google.configuration;
  XCTAssertEqualObjects((@[ @"openid", @"email" ]), config[@"scopes"]);
  XCTAssertEqualObjects(@[ @"keys.example" ], config[@"jwksAllowedHosts"]);
  XCTAssertEqualObjects((@[ @"accounts.google.com", @"oauth2.googleapis.com" ]), config[@"endpointAllowedHosts"]);
  for (NSDictionary *entry in runtime.loginProviders)
    if ([entry[@"identifier"] isEqual:@"google"]) XCTAssertEqualObjects(@"Sign in with Google", entry[@"ctaLabel"]);
}
- (void)testUnknownOrUnsupportedPresetIsAClearConfigError {
  for (NSString *preset in @[ @"nope", @"github", @"" ]) {
    NSMutableDictionary *provider = [[self googleProvider] mutableCopy];
    provider[@"preset"] = preset;
    NSError *error = nil;
    NSDictionary *moduleConfig = @{ @"providers": @{ @"google": provider }, @"hooks": [self googleHooks] };
    XCTAssertFalse([[ALNAuthModuleRuntime new] configureHooksWithModuleConfig:moduleConfig error:&error], @"%@", preset);
    XCTAssertTrue([error.localizedDescription containsString:@"preset"], @"%@", error);
    XCTAssertTrue([error.localizedDescription containsString:@"supported: google"], @"%@", error);
  }
}
- (ALNApplication *)googleApplication {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment": @"test", @"csrf": @{ @"enabled": @NO },
    @"database": @{ @"connectionString": @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
    @"authModule": @{ @"paths": @{ @"prefix": @"/context/auth" }, @"providers": @{ @"google": [self googleProvider] },
      @"hooks": [self googleHooks] }
  }];
  [app addMiddleware:[[ALNSessionMiddleware alloc] initWithSecret:@"test-oidc-session-secret-long-enough-for-signing"
      cookieName:@"oidc_session" maxAgeSeconds:3600 secure:NO sameSite:@"Lax"]];
  NSError *error = nil;
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  return app;
}
- (void)testGooglePresetLoginVerifiesIDTokenWithJWKSOnSeparateHost {
  ALNApplication *app = [self googleApplication];
  [self useGoogleDiscovery];
  ALNResponse *login = [self request:app method:@"GET" path:@"/context/auth/api/provider/google/login" query:@"" cookie:nil];
  XCTAssertEqual((NSInteger)200, login.statusCode, @"%@", [self json:login]);
  NSString *url = [self json:login][@"authorize_url"];
  XCTAssertTrue([url hasPrefix:@"https://accounts.google.com/o/oauth2/v2/auth?"], @"%@", url);
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  for (NSURLQueryItem *item in [NSURLComponents componentsWithString:url].queryItems) parameters[item.name] = item.value;
  OIDCFixture.claims[@"nonce"] = parameters[@"nonce"];
  ALNResponse *callback = [self request:app method:@"GET" path:@"/context/auth/provider/google/callback"
      query:[NSString stringWithFormat:@"code=code&state=%@", parameters[@"state"]] cookie:[self cookie:login]];
  XCTAssertEqual((NSInteger)200, callback.statusCode, @"%@", [self json:callback]);
  XCTAssertEqualObjects(@"person-google-subject", [self json:callback][@"session"][@"subject"]);
  XCTAssertEqualObjects(@"www.googleapis.com", OIDCFixture.lastKeysHost);
}

#pragma mark - Admission policy (issue 61)

- (ALNAuthModuleOIDC *)providerWithAdmission:(NSDictionary *)admission error:(NSError **)error {
  NSMutableDictionary *config = [[self config] mutableCopy];
  config[@"admission"] = admission;
  return [[ALNAuthModuleOIDC alloc] initWithIdentifier:@"entra" configuration:config
      resolver:[ModuleOIDCResolver new] transport:[ModuleOIDCFixture new] error:error];
}
- (BOOL)admitWithAdmission:(NSDictionary *)admission claims:(NSDictionary *)claims error:(NSError **)error {
  ALNAuthModuleOIDC *provider = [self providerWithAdmission:admission error:NULL];
  XCTAssertNotNil(provider, @"%@", admission);
  [OIDCFixture.claims removeObjectForKey:@"email_verified"];
  [OIDCFixture.claims addEntriesFromDictionary:claims];
  for (NSString *key in claims) if (claims[key] == [NSNull null]) [OIDCFixture.claims removeObjectForKey:key];
  ResolverCalls = 0;
  NSDictionary *state = [self stateForProvider:provider];
  return [self complete:provider state:state context:[self context] error:error] != nil;
}
- (void)testAdmissionAllowsVerifiedListedEmailsCaseInsensitively {
  NSDictionary *admission = @{ @"allowedEmails": @[ @"SAME@Example.TEST" ] };
  XCTAssertTrue([self admitWithAdmission:admission claims:@{ @"email_verified": @YES } error:NULL]);
  NSDictionary *stringClaims = @{ @"email_verified": @"true", @"email": @"Same@example.test" };
  XCTAssertTrue([self admitWithAdmission:admission claims:stringClaims error:NULL]);
}
- (void)testAdmissionRejectsUnverifiedAndUnlistedEmailsBeforeResolver {
  NSDictionary *admission = @{ @"allowedEmails": @[ @"same@example.test" ], @"rejectionMessage": @"Family members only." };
  for (NSDictionary *claims in @[ @{}, @{ @"email_verified": @NO }, @{ @"email_verified": @"false" },
                                  @{ @"email_verified": @YES, @"email": @"other@example.test" },
                                  @{ @"email_verified": @YES, @"email": [NSNull null] } ]) {
    NSError *error = nil;
    XCTAssertFalse([self admitWithAdmission:admission claims:claims error:&error], @"%@", claims);
    XCTAssertEqualObjects(ALNAuthModuleOIDCErrorDomain, error.domain);
    XCTAssertEqual((NSInteger)ALNAuthModuleOIDCErrorAdmissionDenied, error.code, @"%@", claims);
    XCTAssertEqualObjects(@"Family members only.", error.localizedDescription);
    XCTAssertEqual((NSUInteger)0, ResolverCalls);
  }
}
- (void)testAdmissionRequireVerifiedEmailWithoutLists {
  NSDictionary *admission = @{ @"requireVerifiedEmail": @"YES" };
  XCTAssertFalse([self admitWithAdmission:admission claims:@{} error:NULL]);
  NSDictionary *claims1 = @{ @"email_verified": @YES, @"email": @"anyone@else.test" };
  XCTAssertTrue([self admitWithAdmission:admission claims:claims1 error:NULL]);
}
- (void)testAdmissionDomainsHonorHostedDomainClaim {
  NSDictionary *admission = @{ @"allowedDomains": @[ @"@example.test" ] };
  XCTAssertTrue([self admitWithAdmission:admission claims:@{ @"email_verified": @YES } error:NULL]);
  NSDictionary *claims2 = @{ @"email_verified": @YES, @"hd": @"example.test" };
  XCTAssertTrue([self admitWithAdmission:admission claims:claims2 error:NULL]);
  NSDictionary *claims3 = @{ @"email_verified": @YES, @"hd": @"other.test" };
  XCTAssertFalse([self admitWithAdmission:admission claims:claims3 error:NULL]);
  NSDictionary *claims4 = @{ @"email_verified": @YES, @"email": @"x@notexample.test" };
  XCTAssertFalse([self admitWithAdmission:admission claims:claims4 error:NULL]);
  NSDictionary *claims5 = @{ @"email_verified": @YES, @"email": @"x@sub.example.test" };
  XCTAssertFalse([self admitWithAdmission:admission claims:claims5 error:NULL]);
  NSDictionary *hosted = @{ @"allowedDomains": @[ @"example.test" ], @"requireHostedDomain": @YES };
  XCTAssertFalse([self admitWithAdmission:hosted claims:@{ @"email_verified": @YES } error:NULL]);
  NSDictionary *claims6 = @{ @"email_verified": @YES, @"hd": @"example.test" };
  XCTAssertTrue([self admitWithAdmission:hosted claims:claims6 error:NULL]);
}
- (void)testAdmissionEnvironmentListAndConfigValidation {
  setenv("ARLEN_TEST_OIDC_ALLOWED_EMAILS", " other@example.test , Same@Example.test ", 1);
  NSDictionary *fromEnvironment = @{ @"allowedEmailsEnvironmentKey": @"ARLEN_TEST_OIDC_ALLOWED_EMAILS" };
  if ([[NSProcessInfo processInfo].environment[@"ARLEN_TEST_OIDC_ALLOWED_EMAILS"] length] > 0) {
    XCTAssertTrue([self admitWithAdmission:fromEnvironment claims:@{ @"email_verified": @YES } error:NULL]);
  }
  for (NSDictionary *admission in @[ @{ @"allowedEmailsEnvironmentKey": @"ARLEN_TEST_OIDC_UNSET_EMAIL_LIST" },
                                     @{ @"allowedEmailsEnvironmentKey": @"PATH" },
                                     @{ @"allowedEmails": @[ @"not-an-email" ] },
                                     @{ @"allowedDomains": @[ @"a@b.test" ] },
                                     @{ @"allowedEmails": @"same@example.test" },
                                     @{ @"requireHostedDomain": @YES },
                                     @{ @"requireVerifiedEmail": @"sometimes" },
                                     @{ @"allowedEmail": @[ @"typo@example.test" ] },
                                     @{ @"rejectionMessage": @"" } ]) {
    NSError *error = nil;
    XCTAssertNil([self providerWithAdmission:admission error:&error], @"%@", admission);
    XCTAssertTrue([error.localizedDescription containsString:@"admission"], @"%@ %@", admission, error);
  }
}
- (void)testModuleCallbackReportsAdmissionDenial {
  RegisterOIDCLoginTemplates();
  NSMutableDictionary *provider = [[self googleProvider] mutableCopy];
  provider[@"admission"] = @{ @"allowedEmails": @[ @"parent@family.example" ], @"rejectionMessage": @"Family members only." };
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment": @"test", @"csrf": @{ @"enabled": @NO },
    @"database": @{ @"connectionString": @"host=127.0.0.1 port=1 dbname=unused connect_timeout=1" },
    @"authModule": @{ @"paths": @{ @"prefix": @"/context/auth" }, @"providers": @{ @"google": provider },
      @"hooks": [self googleHooks] }
  }];
  [app addMiddleware:[[ALNSessionMiddleware alloc] initWithSecret:@"test-oidc-session-secret-long-enough-for-signing"
      cookieName:@"oidc_session" maxAgeSeconds:3600 secure:NO sameSite:@"Lax"]];
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:NULL]);
  [self useGoogleDiscovery];
  for (NSNumber *jsonClient in @[ @YES, @NO ]) {
    ALNResponse *login = [self request:app method:@"GET" path:@"/context/auth/api/provider/google/login" query:@"" cookie:nil];
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in [NSURLComponents componentsWithString:[self json:login][@"authorize_url"]].queryItems)
      parameters[item.name] = item.value;
    OIDCFixture.claims[@"nonce"] = parameters[@"nonce"];
    NSString *query = [NSString stringWithFormat:@"code=code-%@&state=%@", jsonClient, parameters[@"state"]];
    ResolverCalls = 0;
    if ([jsonClient boolValue]) {
      ALNResponse *callback = [self request:app method:@"GET" path:@"/context/auth/provider/google/callback"
                                      query:query cookie:[self cookie:login]];
      XCTAssertEqual((NSInteger)403, callback.statusCode);
      XCTAssertEqualObjects(@"admission_denied", [self json:callback][@"code"]);
      XCTAssertEqualObjects(@"Family members only.", [self json:callback][@"message"]);
    } else {
      ALNResponse *callback = [app dispatchRequest:[[ALNRequest alloc] initWithMethod:@"GET"
          path:@"/context/auth/provider/google/callback" queryString:query
          headers:@{ @"cookie": [self cookie:login] ?: @"", @"accept": @"text/html" } body:[NSData data]]];
      XCTAssertEqual((NSInteger)302, callback.statusCode);
      XCTAssertEqualObjects(@"/context/auth/login", [callback headerForName:@"Location"]);
      ALNResponse *page = [app dispatchRequest:[[ALNRequest alloc] initWithMethod:@"GET" path:@"/context/auth/login"
          queryString:@"" headers:@{ @"cookie": [self cookie:callback] ?: @"", @"accept": @"text/html" } body:[NSData data]]];
      NSString *html = [[NSString alloc] initWithData:page.bodyData encoding:NSUTF8StringEncoding];
      XCTAssertTrue([html containsString:@"Family members only."], @"%@", html);
    }
    XCTAssertEqual((NSUInteger)0, ResolverCalls);
  }
}
@end
