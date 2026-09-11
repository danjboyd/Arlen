#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <openssl/evp.h>
#import <openssl/pem.h>
#import "ALNCryptoCompat.h"
#import "ALNSecurityPrimitives.h"
#import "ALNOAuthResourceServer.h"
#import "ALNAuth.h"
#import "ALNMCPModule.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNRouter.h"
#import "ALNHTTPCompat.h"
static NSDictionary *OAuthTestRSAKeyMaterial(NSString *kid) {
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

static NSString *OAuthTestSignedJWT(NSDictionary *claims, NSString *privateKeyPEM, NSDictionary *header) {
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

static NSString *OAuthTestRS256JWT(NSDictionary *claims, NSString *pem, NSString *kid) {
  return OAuthTestSignedJWT(claims, pem, @{@"alg":@"RS256", @"typ":@"JWT", @"kid":kid});
}
static NSString *const Tenant = @"11111111-1111-1111-1111-111111111111";
static NSString *const Audience = @"22222222-2222-2222-2222-222222222222";
static NSUInteger OAuthCalls;
@interface OAuthFixtureController : ALNController
@end
@implementation OAuthFixtureController
- (id)read:(ALNContext *)context { OAuthCalls++; return @{@"subject":context.stash[ALNOAuthPrincipalStashKey][@"subject"]}; }
@end
@interface OAuthFalseSession : NSObject <ALNMiddleware>
@end
@implementation OAuthFalseSession
- (BOOL)processContext:(ALNContext *)context error:(NSError **)error {
  [ALNAuth applyClaims:@{@"sub":@"forged-session", @"scope":@"Research.Read"} toContext:context]; return YES;
}
@end
// Foundation transport fixture, including redirect and chunked-size callbacks.
@interface OAuthMetadataProtocol : NSURLProtocol
@end
@implementation OAuthMetadataProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"metadata.fixture.test"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
  NSString *path = self.request.URL.path;
  if ([path isEqual:@"/timeout"]) return;
  NSInteger status = [path isEqual:@"/failure"] ? 500 : ([path isEqual:@"/redirect"] ? 302 : 200);
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{}];
  if (status == 302) {
    [self.client URLProtocol:self wasRedirectedToRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://metadata.fixture.test/ok"]] redirectResponse:response]; return;
  }
  [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
  if (status != 200) return; // The bounded delegate cancels on an error status.
  [self.client URLProtocol:self didLoadData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
  if ([path isEqual:@"/large"]) { [self.client URLProtocol:self didLoadData:[NSMutableData dataWithLength:100]]; return; }
  [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
@interface OAuthResourceServerTests : XCTestCase
@property(nonatomic, strong) NSDictionary *key;
@property(nonatomic, strong) NSDictionary *secondKey;
@property(nonatomic, strong) NSMutableDictionary *documents;
@property(nonatomic, strong) NSMutableArray *requests;
@property(nonatomic, strong) ALNOAuthResourceServer *server;
@end
@implementation OAuthResourceServerTests
- (NSDictionary *)config {
  return [ALNOAuthResourceServer entraConfigurationForTenant:Tenant tokenVersion:@"2.0" audience:Audience
      resourceURL:@"https://mcp.example.test/research/mcp" scopes:@[@"api://research/Research.Read", @"offline_access"] error:NULL];
}
- (ALNOAuthResourceServer *)serverWithConfig:(NSDictionary *)config policy:(ALNOAuthAuthorizationPolicy)policy {
  __weak OAuthResourceServerTests *weakSelf = self;
  NSError *error = nil;
  ALNOAuthResourceServer *server = [[ALNOAuthResourceServer alloc] initWithConfiguration:config
      documentLoader:^NSDictionary *(NSURL *url, NSError **fetchError) {
        [weakSelf.requests addObject:url.absoluteString]; return weakSelf.documents[url.absoluteString];
      } authorizationPolicy:policy error:&error];
  XCTAssertNotNil(server, @"%@", error); return server;
}
- (void)setUp {
  [super setUp]; OAuthCalls = 0;
  self.key = OAuthTestRSAKeyMaterial(@"first"); self.secondKey = OAuthTestRSAKeyMaterial(@"second");
  self.requests = [NSMutableArray array];
  self.documents = [@{[self config][@"discoveryURL"]:@{@"issuer":[self config][@"issuer"], @"jwks_uri":@"https://login.microsoftonline.com/fixture/keys"},
    @"https://login.microsoftonline.com/fixture/keys":@{@"keys":@[self.key[@"jwk"]]}} mutableCopy];
  self.server = [self serverWithConfig:[self config] policy:nil];
}
- (NSMutableDictionary *)claims {
  NSTimeInterval now = [NSDate date].timeIntervalSince1970;
  return [@{@"iss":[self config][@"issuer"], @"aud":Audience, @"tid":Tenant, @"oid":@"user-object-id", @"sub":@"pairwise-subject",
    @"ver":@"2.0", @"azp":@"registered-client", @"exp":@(now+300), @"nbf":@(now-1), @"iat":@(now-1), @"scp":@"Research.Read", @"roles":@[@"Reader"]} mutableCopy];
}
- (NSString *)token:(NSDictionary *)claims { return OAuthTestRS256JWT(claims, self.key[@"privateKeyPEM"], @"first"); }
- (void)testVerifiedPrincipalUsesTenantObjectIdentityAndClient {
  NSDictionary *principal = [self.server principalForAccessToken:[self token:[self claims]] error:NULL];
  XCTAssertEqualObjects([Tenant stringByAppendingString:@":user-object-id"], principal[@"subject"]);
  XCTAssertEqualObjects(@"registered-client", principal[@"clientID"]);
  XCTAssertEqualObjects(@"delegated", principal[@"permissionType"]);
  XCTAssertEqualObjects((@[@"Research.Read"]), principal[@"scopes"]);
  XCTAssertEqualObjects((@[@"Reader"]), principal[@"roles"]);
  XCTAssertNil(principal[@"email"]); XCTAssertEqual(2u, self.requests.count);
}
- (void)testRejectsSignatureIssuerTenantAudienceDatesAndMalformedClaims {
  NSDictionary *bad = @{@"iss":@"https://evil.example", @"tid":@"other-tenant", @"aud":@"00000003-0000-0000-c000-000000000000",
    @"exp":@1, @"nbf":@4102444800, @"iat":@4102444800, @"ver":@"1.0", @"oid":@"", @"azp":@"", @"scp":@[@"Research.Read"], @"roles":@"Reader"};
  for (NSString *key in bad) {
    NSMutableDictionary *claims = [self claims]; claims[key] = bad[key];
    XCTAssertNil([self.server principalForAccessToken:[self token:claims] error:NULL], @"accepted %@", key);
  }
  for (NSString *key in @[@"exp", @"iat", @"nbf", @"sub", @"tid", @"oid", @"azp"]) {
    NSMutableDictionary *claims = [self claims]; [claims removeObjectForKey:key];
    XCTAssertNil([self.server principalForAccessToken:[self token:claims] error:NULL], @"missing %@", key);
  }
  NSMutableDictionary *claims = [self claims]; claims[@"exp"] = @"4102444800";
  XCTAssertNil([self.server principalForAccessToken:[self token:claims] error:NULL]);
  NSString *forged = OAuthTestRS256JWT([self claims], self.secondKey[@"privateKeyPEM"], @"first");
  XCTAssertNil([self.server principalForAccessToken:forged error:NULL]);
  XCTAssertEqual(2u, self.requests.count); // Invalid known-key signatures do not refresh.
}
- (void)testRejectsIDTokensAndApplicationTokensUnlessExplicitPolicy {
  NSMutableDictionary *claims = [self claims]; [claims removeObjectForKey:@"scp"];
  XCTAssertNil([self.server principalForAccessToken:[self token:claims] error:NULL]);
  claims[@"idtyp"] = @"app";
  XCTAssertNil([self.server principalForAccessToken:[self token:claims] error:NULL]);
  NSMutableDictionary *config = [[self config] mutableCopy]; config[@"allowApplicationPermissions"] = @YES;
  XCTAssertNil([[ALNOAuthResourceServer alloc] initWithConfiguration:config documentLoader:nil authorizationPolicy:nil error:NULL]);
  self.server = [self serverWithConfig:config policy:^BOOL(NSDictionary *p, ALNContext *c) { return [p[@"clientID"] isEqual:@"registered-client"]; }];
  XCTAssertEqualObjects(@"application", [self.server principalForAccessToken:[self token:claims] error:NULL][@"permissionType"]);
  claims[@"scp"] = @"Research.Read";
  XCTAssertNil([self.server principalForAccessToken:[self token:claims] error:NULL]);
}
- (void)testRotationCooldownAndExpiredCacheFailClosed {
  XCTAssertNotNil([self.server principalForAccessToken:[self token:[self claims]] error:NULL]);
  NSString *rotated = OAuthTestRS256JWT([self claims], self.secondKey[@"privateKeyPEM"], @"second");
  for (NSUInteger i=0; i<30; i++) XCTAssertNil([self.server principalForAccessToken:rotated error:NULL]);
  XCTAssertEqual(2u, self.requests.count);
  self.documents[@"https://login.microsoftonline.com/fixture/keys"] = @{@"keys":@[self.key[@"jwk"], self.secondKey[@"jwk"]]};
  // Controlled monotonic cache state; no wall-clock sleeps or network in fixture tests.
  [self.server setValue:@0 forKey:@"nextRefresh"];
  XCTAssertNotNil([self.server principalForAccessToken:rotated error:NULL]);
  XCTAssertEqual(4u, self.requests.count);
  [self.documents removeAllObjects];
  XCTAssertNotNil([self.server principalForAccessToken:rotated error:NULL]); // Still-fresh key remains valid.
  [self.server setValue:@0 forKey:@"expires"];
  [self.server setValue:@0 forKey:@"nextRefresh"];
  XCTAssertNil([self.server principalForAccessToken:rotated error:NULL]);
  NSUInteger count = self.requests.count;
  for (NSUInteger i=0; i<30; i++) XCTAssertNil([self.server principalForAccessToken:rotated error:NULL]);
  XCTAssertEqual(count, self.requests.count);
}
- (void)testDiscoveryTrustKeyRestrictionsAndNoTokenURLFetching {
  NSMutableDictionary *metadata = [self.documents[[self config][@"discoveryURL"]] mutableCopy];
  metadata[@"jwks_uri"] = @"https://evil.example/keys";
  self.documents[[self config][@"discoveryURL"]] = metadata;
  XCTAssertNil([self.server principalForAccessToken:[self token:[self claims]] error:NULL]);
  XCTAssertEqual(1u, self.requests.count);
  metadata[@"jwks_uri"] = @"https://login.microsoftonline.com/fixture/keys"; metadata[@"issuer"] = @"https://evil.example";
  [self.server setValue:@0 forKey:@"nextRefresh"];
  XCTAssertNil([self.server principalForAccessToken:[self token:[self claims]] error:NULL]);
  XCTAssertEqual(2u, self.requests.count);
  metadata[@"issuer"] = [self config][@"issuer"];
  for (NSDictionary *override in @[@{@"use":@"enc"}, @{@"alg":@"HS256"}, @{@"key_ops":@[@"sign"]}, @{@"issuer":@"https://evil.example"}, @{@"n":@"AQAB"}, @{@"n":[NSNull null]}, @{@"e":@[]}]) {
    NSMutableDictionary *key = [self.key[@"jwk"] mutableCopy]; [key addEntriesFromDictionary:override];
    self.documents[@"https://login.microsoftonline.com/fixture/keys"] = @{@"keys":@[key]};
    self.server = [self serverWithConfig:[self config] policy:nil];
    XCTAssertNil([self.server principalForAccessToken:[self token:[self claims]] error:NULL]);
  }
  self.documents[@"https://login.microsoftonline.com/fixture/keys"] = @{@"keys":@[self.key[@"jwk"], self.key[@"jwk"]]};
  self.server = [self serverWithConfig:[self config] policy:nil];
  XCTAssertNil([self.server principalForAccessToken:[self token:[self claims]] error:NULL]);
}
- (ALNApplication *)appWithPolicy:(ALNOAuthAuthorizationPolicy)policy {
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{@"environment":@"test", @"logLevel":@"error", @"apiOnly":@YES,
    @"session":@{@"enabled":@NO}, @"csrf":@{@"enabled":@NO}, @"mcp":@{@"enabled":@YES, @"path":@"/research/mcp"}}];
  [app addMiddleware:[OAuthFalseSession new]];
  ALNRoute *route = [app registerRouteMethod:@"GET" path:@"/records" name:@"records" controllerClass:[OAuthFixtureController class] action:@"read"];
  route.requiredScopes = @[@"Research.Read"]; route.requiredRoles = @[@"Reader"];
  ALNMCPModule *mcp = [ALNMCPModule new];
  mcp.resourceServer = [self serverWithConfig:[self config] policy:policy];
  self.server = mcp.resourceServer;
  XCTAssertTrue(([mcp registerRouteTool:@{@"routeName":@"records", @"name":@"research_documents", @"annotations":@{@"readOnlyHint":@YES, @"destructiveHint":@NO, @"idempotentHint":@YES, @"openWorldHint":@NO}} transform:nil error:NULL]));
  NSError *error = nil;
  XCTAssertTrue([app registerPlugin:mcp error:&error], @"%@", error);
  XCTAssertTrue([app startWithError:&error], @"%@", error);
  return app;
}
- (ALNResponse *)request:(ALNApplication *)app path:(NSString *)path token:(NSString *)token {
  NSDictionary *rpc = @{@"jsonrpc":@"2.0", @"id":@1, @"method":@"tools/call", @"params":@{@"name":@"research_documents", @"arguments":@{}}};
  NSMutableDictionary *headers = [@{@"host":@"evil.example", @"forwarded":@"host=evil.example;proto=http", @"x-forwarded-host":@"evil.example", @"x-forwarded-proto":@"http",
    @"accept":@"application/json, text/event-stream", @"content-type":@"application/json", @"mcp-protocol-version":@"2025-11-25"} mutableCopy];
  if (token) headers[@"authorization"] = [@"Bearer " stringByAppendingString:token];
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:[path isEqual:@"/research/mcp"] ? @"POST" : @"GET"
    path:path queryString:@"" headers:headers body:[NSJSONSerialization dataWithJSONObject:rpc options:0 error:NULL]];
  return [app dispatchRequest:request];
}
- (void)testPathDiscoverySpoofedHeadersAndConsistentRESTMCPEnforcement {
  ALNApplication *app = [self appWithPolicy:nil];
  ALNResponse *metadata = [self request:app path:@"/.well-known/oauth-protected-resource/research/mcp" token:nil];
  XCTAssertEqual(200, metadata.statusCode);
  NSDictionary *body = [NSJSONSerialization JSONObjectWithData:metadata.bodyData options:0 error:NULL];
  XCTAssertEqualObjects(@"https://mcp.example.test/research/mcp", body[@"resource"]);
  for (NSString *path in @[@"/research/mcp", @"/records"]) {
    ALNResponse *missing = [self request:app path:path token:nil];
    XCTAssertEqual(401, missing.statusCode);
    XCTAssertTrue([[missing headerForName:@"WWW-Authenticate"] containsString:@"https://mcp.example.test/.well-known/oauth-protected-resource/research/mcp"]);
    XCTAssertFalse([[missing headerForName:@"WWW-Authenticate"] containsString:@"evil"]);
    XCTAssertEqual(401, [self request:app path:path token:@"old-hs256-pilot-token"].statusCode);
    XCTAssertEqual(200, [self request:app path:path token:[self token:[self claims]]].statusCode);
    NSMutableDictionary *claims = [self claims]; claims[@"scp"] = @"Other.Read";
    ALNResponse *denied = [self request:app path:path token:[self token:claims]];
    XCTAssertEqual(403, denied.statusCode);
    XCTAssertTrue([[denied headerForName:@"WWW-Authenticate"] containsString:@"insufficient_scope"]);
    claims = [self claims]; claims[@"roles"] = @[];
    XCTAssertEqual(403, [self request:app path:path token:[self token:claims]].statusCode);
    claims = [self claims]; claims[@"aud"] = @"another-service";
    XCTAssertEqual(401, [self request:app path:path token:[self token:claims]].statusCode);
  }
  XCTAssertEqual(2u, OAuthCalls);
}
- (void)testSuspensionAndRecordPolicyRunOnBothDispatches {
  __block BOOL suspended = NO;
  ALNApplication *app = [self appWithPolicy:^BOOL(NSDictionary *principal, ALNContext *context) {
    return !suspended && ![[context.request headerValueForName:@"x-record-denied"] isEqual:@"yes"];
  }];
  NSString *token = [self token:[self claims]];
  XCTAssertEqual(200, [self request:app path:@"/records" token:token].statusCode);
  suspended = YES;
  XCTAssertEqual(403, [self request:app path:@"/records" token:token].statusCode);
  XCTAssertEqual(403, [self request:app path:@"/research/mcp" token:token].statusCode);
  XCTAssertEqual(1u, OAuthCalls);
  // A record-level denial on the inner REST route must propagate out of tools/call.
  app = [self appWithPolicy:^BOOL(NSDictionary *principal, ALNContext *context) { return ![context.request.path isEqual:@"/records"]; }];
  XCTAssertEqual(403, [self request:app path:@"/records" token:token].statusCode);
  XCTAssertEqual(403, [self request:app path:@"/research/mcp" token:token].statusCode);
  XCTAssertEqual(1u, OAuthCalls);
}
- (void)testVersionOneUsesExplicitAudienceAndVersionedDiscovery {
  NSDictionary *config = [ALNOAuthResourceServer entraConfigurationForTenant:Tenant tokenVersion:@"1.0" audience:@"api://research" resourceURL:@"https://mcp.example.test/research/mcp" scopes:@[@"api://research/Research.Read"] error:NULL];
  self.documents[config[@"discoveryURL"]] = @{@"issuer":config[@"issuer"], @"jwks_uri":@"https://login.microsoftonline.com/fixture/keys"};
  self.server = [self serverWithConfig:config policy:nil];
  NSMutableDictionary *claims = [self claims]; claims[@"ver"] = @"1.0"; claims[@"aud"] = @"api://research";
  claims[@"iss"] = config[@"issuer"]; claims[@"appid"] = @"legacy-client"; [claims removeObjectForKey:@"azp"];
  XCTAssertNotNil([self.server principalForAccessToken:[self token:claims] error:NULL]);
  claims[@"aud"] = Audience;
  XCTAssertNil([self.server principalForAccessToken:[self token:claims] error:NULL]);
}
- (void)testInvalidConfigurationFailsAtConstruction {
  for (NSDictionary *override in @[@{@"issuer":@"http://insecure"}, @{@"resourceURL":@"https://mcp.example.test/research/mcp?evil=1"}, @{@"algorithms":@[@"HS256"]}, @{@"jwksMaxAgeSeconds":@0}, @{@"refreshCooldownSeconds":@0}, @{@"protectedPaths":@[]}, @{@"allowApplicationPermissions":@"yes"}]) {
    NSMutableDictionary *config = [[self config] mutableCopy]; [config addEntriesFromDictionary:override];
    XCTAssertNil([[ALNOAuthResourceServer alloc] initWithConfiguration:config documentLoader:nil authorizationPolicy:nil error:NULL]);
  }
}
- (void)testJOSEHeadersAndProviderNeutralAccessTokenProfile {
  for (NSDictionary *header in @[@{@"alg":@"none", @"kid":@"first", @"typ":@"JWT"}, @{@"alg":@"HS256", @"kid":@"first", @"typ":@"JWT"},
      @{@"alg":@"RS256", @"typ":@"JWT"}, @{@"alg":@"RS256", @"kid":@"first", @"typ":@"JWT", @"crit":@[@"other"]}]) {
    XCTAssertNil([self.server principalForAccessToken:OAuthTestSignedJWT([self claims], self.key[@"privateKeyPEM"], header) error:NULL]);
  }
  XCTAssertEqual(0u, self.requests.count);
  NSDictionary *header = @{@"alg":@"RS256", @"kid":@"first", @"typ":@"JWT", @"jku":@"https://evil.example/keys", @"x5u":@"https://evil.example/cert"};
  XCTAssertNotNil([self.server principalForAccessToken:OAuthTestSignedJWT([self claims], self.key[@"privateKeyPEM"], header) error:NULL]);
  XCTAssertEqual(2u, self.requests.count);
  NSMutableDictionary *config = [[self config] mutableCopy]; config[@"profile"] = @"rfc9068";
  self.server = [self serverWithConfig:config policy:nil];
  NSMutableDictionary *claims = [self claims]; claims[@"scope"] = @"Research.Read"; claims[@"client_id"] = @"neutral-client"; claims[@"idtyp"] = @"user";
  header = @{@"alg":@"RS256", @"kid":@"first", @"typ":@"at+jwt"};
  NSDictionary *principal = [self.server principalForAccessToken:OAuthTestSignedJWT(claims, self.key[@"privateKeyPEM"], header) error:NULL];
  XCTAssertEqualObjects(@"pairwise-subject", principal[@"subject"]);
  XCTAssertEqualObjects(@"neutral-client", principal[@"clientID"]);
  XCTAssertNil([self.server principalForAccessToken:[self token:claims] error:NULL]); // ID-token typ rejected.
  claims[@"idtyp"] = @"app";
  XCTAssertNil([self.server principalForAccessToken:OAuthTestSignedJWT(claims, self.key[@"privateKeyPEM"], header) error:NULL]);
}
- (void)testBoundedFoundationMetadataTransport {
#if !defined(GNUSTEP) // GNUstep production transport is covered by real socket tests.
  [NSURLProtocol registerClass:[OAuthMetadataProtocol class]];
  @try {
    XCTAssertNotNil(ALNBoundedMetadataGET([NSURL URLWithString:@"https://metadata.fixture.test/ok"], 32, 1));
    for (NSString *path in @[@"failure", @"redirect", @"large", @"timeout"]) {
      XCTAssertNil(ALNBoundedMetadataGET([NSURL URLWithString:[@"https://metadata.fixture.test/" stringByAppendingString:path]], 32, 0.15), @"%@", path);
    }
  } @finally { [NSURLProtocol unregisterClass:[OAuthMetadataProtocol class]]; }
#endif
}
- (void)testConcurrentColdValidationCoalescesRefresh {
  NSString *token = [self token:[self claims]];
  NSOperationQueue *queue = [NSOperationQueue new]; queue.maxConcurrentOperationCount = 8;
  NSMutableArray *results = [NSMutableArray array];
  for (NSUInteger i = 0; i < 24; i++) [queue addOperationWithBlock:^{
    @autoreleasepool {
      BOOL valid = [self.server principalForAccessToken:token error:NULL] != nil;
      @synchronized (results) { [results addObject:@(valid)]; }
    }
  }];
  [queue waitUntilAllOperationsAreFinished];
  XCTAssertEqual(24u, results.count);
  XCTAssertFalse([results containsObject:@NO]);
  XCTAssertEqual(2u, self.requests.count);
}
- (void)testMCPRejectsUnprotectedBackingRoutesAndFreezesResource {
  NSMutableDictionary *config = [[self config] mutableCopy]; config[@"protectedPaths"] = @[@"/research/mcp"];
  ALNOAuthResourceServer *server = [self serverWithConfig:config policy:nil];
  XCTAssertTrue([server protectsPath:@"/research/mcp/_tools/tool"]);
  XCTAssertFalse([server protectsPath:@"/research/mcpevil"]);
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{@"environment":@"test", @"logLevel":@"error", @"mcp":@{@"enabled":@YES, @"path":@"/research/mcp"}}];
  [app registerRouteMethod:@"GET" path:@"/records" name:@"records" controllerClass:[OAuthFixtureController class] action:@"read"];
  ALNMCPModule *module = [ALNMCPModule new]; module.resourceServer = server;
  XCTAssertTrue(([module registerRouteTool:@{@"routeName":@"records", @"annotations":@{@"readOnlyHint":@YES, @"destructiveHint":@NO, @"idempotentHint":@YES, @"openWorldHint":@NO}} transform:nil error:NULL]));
  XCTAssertTrue([app registerPlugin:module error:NULL]);
  XCTAssertThrows(module.resourceServer = nil);
  XCTAssertFalse([app startWithError:NULL]);
}
- (void)testApplicationPolicyAndRolesCannotUseDelegatedPermissions {
  NSMutableDictionary *config = [[self config] mutableCopy]; config[@"allowApplicationPermissions"] = @YES;
  self.server = [self serverWithConfig:config policy:^BOOL(NSDictionary *principal, ALNContext *context) {
    return [principal[@"permissionType"] isEqual:@"application"] && [principal[@"clientID"] isEqual:@"registered-client"];
  }];
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{@"environment":@"test", @"logLevel":@"error", @"session":@{@"enabled":@NO}, @"csrf":@{@"enabled":@NO}}];
  ALNRoute *route = [app registerRouteMethod:@"GET" path:@"/records" name:@"records" controllerClass:[OAuthFixtureController class] action:@"read"];
  route.requiredRoles = @[@"Service.Reader"];
  XCTAssertTrue([app registerPlugin:self.server error:NULL]);
  XCTAssertTrue([app startWithError:NULL]);
  NSMutableDictionary *claims = [self claims]; [claims removeObjectForKey:@"scp"];
  claims[@"idtyp"] = @"app"; claims[@"roles"] = @[@"Service.Reader"];
  XCTAssertEqual(200, [self request:app path:@"/records" token:[self token:claims]].statusCode);
  claims[@"azp"] = @"unapproved-client";
  XCTAssertEqual(403, [self request:app path:@"/records" token:[self token:claims]].statusCode);
  claims[@"azp"] = @"registered-client"; claims[@"roles"] = @[@"Other.Role"];
  XCTAssertEqual(403, [self request:app path:@"/records" token:[self token:claims]].statusCode);
  claims = [self claims]; claims[@"roles"] = @[@"Service.Reader"];
  XCTAssertEqual(403, [self request:app path:@"/records" token:[self token:claims]].statusCode);
  XCTAssertEqual(1u, OAuthCalls);
}
- (void)testRefreshErrorsDistinguishFailureAndCooldownWithoutLeakingLoaderDetails {
  self.server = [[ALNOAuthResourceServer alloc] initWithConfiguration:[self config]
      documentLoader:^NSDictionary *(NSURL *url, NSError **error) {
        if (error) *error = [NSError errorWithDomain:@"Arlen.Metadata" code:5
            userInfo:@{NSLocalizedDescriptionKey:@"credential-secret response-body"}];
        return nil;
      } authorizationPolicy:nil error:NULL];
  NSError *error = nil;
  XCTAssertFalse([self.server refreshSigningKeysWithError:&error]);
  XCTAssertTrue([error.localizedDescription containsString:@"discovery fetch failed"]);
  XCTAssertFalse([error.description containsString:@"credential-secret"]);
  XCTAssertFalse([error.description containsString:@"response-body"]);
  XCTAssertFalse(self.server.isReady);
  XCTAssertFalse([self.server refreshSigningKeysWithError:&error]);
  XCTAssertEqualObjects(@"OAuth key refresh in cooldown", error.localizedDescription);
}
- (void)testMaintenanceModePreflightReadinessAndCooldown {
  NSMutableDictionary *config = [[self config] mutableCopy]; config[@"refreshOnRequest"] = @NO; config[@"preflightOnStart"] = @YES;
  self.server = [self serverWithConfig:config policy:nil];
  NSString *token = [self token:[self claims]];
  XCTAssertFalse([self.server isReady]);
  XCTAssertNil([self.server principalForAccessToken:token error:NULL]);
  XCTAssertEqual(0u, self.requests.count);
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{@"environment":@"test", @"logLevel":@"error"}];
  XCTAssertTrue([app registerPlugin:self.server error:NULL]);
  XCTAssertTrue([app startWithError:NULL]);
  XCTAssertTrue([self.server isReady]);
  XCTAssertNotNil([self.server principalForAccessToken:token error:NULL]);
  XCTAssertFalse([self.server refreshSigningKeysWithError:NULL]);
  XCTAssertEqual(2u, self.requests.count);
  [self.server setValue:@0 forKey:@"expires"];
  XCTAssertFalse([self.server isReady]);
  XCTAssertNil([self.server principalForAccessToken:token error:NULL]);
  XCTAssertEqual(2u, self.requests.count);
  [self.documents removeAllObjects];
  [self.server setValue:@0 forKey:@"nextRefresh"];
  XCTAssertFalse([self.server refreshSigningKeysWithError:NULL]);
  XCTAssertFalse([self.server isReady]);
  self.server = [self serverWithConfig:config policy:nil];
  app = [[ALNApplication alloc] initWithConfig:@{@"environment":@"test", @"logLevel":@"error"}];
  XCTAssertTrue([app registerPlugin:self.server error:NULL]);
  XCTAssertFalse([app startWithError:NULL]);
}
- (void)testSlowRefreshDoesNotHoldValidationMonitorAndRotationRecovers {
  NSMutableDictionary *config = [[self config] mutableCopy]; config[@"refreshOnRequest"] = @NO;
  NSCondition *gate = [NSCondition new];
  __block BOOL slow = NO, entered = NO, releaseFetch = NO;
  __block NSUInteger fetches = 0;
  NSDictionary *metadata = self.documents[config[@"discoveryURL"]];
  NSDictionary *initialKeys = @{@"keys":@[self.key[@"jwk"]]};
  NSDictionary *rotatedKeys = @{@"keys":@[self.key[@"jwk"], self.secondKey[@"jwk"]]};
  self.server = [[ALNOAuthResourceServer alloc] initWithConfiguration:config documentLoader:^NSDictionary *(NSURL *url, NSError **error) {
    fetches++;
    if ([url.absoluteString isEqual:config[@"discoveryURL"]]) {
      [gate lock];
      if (slow) {
        entered = YES; [gate broadcast];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (!releaseFetch && [gate waitUntilDate:deadline]) {}
      }
      [gate unlock];
      return metadata;
    }
    return slow ? rotatedKeys : initialKeys;
  } authorizationPolicy:nil error:NULL];
  XCTAssertTrue([self.server refreshSigningKeysWithError:NULL]);
  NSString *token = [self token:[self claims]];
  NSString *rotated = OAuthTestRS256JWT([self claims], self.secondKey[@"privateKeyPEM"], @"second");
  [gate lock]; slow = YES; [gate unlock];
  [self.server setValue:@0 forKey:@"nextRefresh"];
  NSOperationQueue *worker = [NSOperationQueue new];
  [worker addOperationWithBlock:^{ [self.server refreshSigningKeysWithError:NULL]; }];
  [gate lock];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
  while (!entered && [gate waitUntilDate:deadline]) {}
  XCTAssertTrue(entered);
  [gate unlock];
  NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
  XCTAssertNotNil([self.server principalForAccessToken:token error:NULL]);
  XCTAssertNil([self.server principalForAccessToken:rotated error:NULL]);
  [self.server setValue:@0 forKey:@"expires"];
  XCTAssertFalse([self.server isReady]);
  XCTAssertNil([self.server principalForAccessToken:token error:NULL]);
  NSTimeInterval latency = [NSDate timeIntervalSinceReferenceDate] - start;
  XCTAssertLessThan(latency, 0.5); // Loader remains blocked; validation must not wait for it.
  [gate lock]; releaseFetch = YES; [gate broadcast]; [gate unlock];
  [worker waitUntilAllOperationsAreFinished];
  XCTAssertTrue([self.server isReady]);
  XCTAssertNotNil([self.server principalForAccessToken:rotated error:NULL]);
  XCTAssertEqual(4u, fetches);
  NSLog(@"OAuth maintenance fixture validation seconds: %.6f", latency);
}
- (void)testMeasureSynchronousColdFetchLatency {
  NSDictionary *config = [self config];
  NSDictionary *documents = [self.documents copy];
  self.server = [[ALNOAuthResourceServer alloc] initWithConfiguration:config documentLoader:^NSDictionary *(NSURL *url, NSError **error) {
    [NSThread sleepForTimeInterval:0.15];
    return documents[url.absoluteString];
  } authorizationPolicy:nil error:NULL];
  NSString *token = [self token:[self claims]];
  NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
  XCTAssertNotNil([self.server principalForAccessToken:token error:NULL]);
  NSTimeInterval latency = [NSDate timeIntervalSinceReferenceDate] - start;
  XCTAssertGreaterThanOrEqual(latency, 0.29);
  NSLog(@"OAuth synchronous fixture cold validation seconds: %.6f (two 150ms fetches)", latency);
}
@end
