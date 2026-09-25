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
  } else if ([request.URL.path isEqual:@"/keys"]) {
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
@end
