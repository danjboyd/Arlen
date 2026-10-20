#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "ALNApplication.h"
#import "ALNAuthModule.h"
#import "ALNAuthSession.h"
#import "ALNContext.h"
#import "ALNMigrationRunner.h"
#import "ALNPerf.h"
#import "ALNPg.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNTOTP.h"
#import "ALNTestClient.h"

// Login and step-up start a fresh session: pre-login keys (including the CSRF
// token) do not carry over, except the documented `return_to`.
@interface AuthSessionRegenerationTests : XCTestCase
@end

@implementation AuthSessionRegenerationTests

- (NSString *)pgTestDSN {
  const char *value = getenv("ARLEN_PG_TEST_DSN");
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

- (ALNContext *)contextWithSession:(NSDictionary *)session {
  NSMutableDictionary *stash = [NSMutableDictionary dictionary];
  stash[ALNContextSessionStashKey] = [NSMutableDictionary dictionaryWithDictionary:session ?: @{}];
  stash[ALNContextCSRFLazyTokenStashKey] = @YES;
  if ([session[@"_csrf_token"] length] > 0) {
    stash[ALNContextCSRFTokenStashKey] = session[@"_csrf_token"];
  }
  ALNRequest *request = [[ALNRequest alloc] initWithMethod:@"POST"
                                                      path:@"/login"
                                               queryString:@""
                                                   headers:@{}
                                                      body:[NSData data]];
  return [[ALNContext alloc] initWithRequest:request
                                    response:[[ALNResponse alloc] init]
                                      params:@{}
                                       stash:stash
                                      logger:nil
                                   perfTrace:[[ALNPerfTrace alloc] initWithEnabled:NO]
                                   routeName:@""
                              controllerName:@""
                                  actionName:@""];
}

- (void)testEstablishStartsFreshSessionKeepingOnlyReturnTo {
  ALNContext *context = [self contextWithSession:@{
    @"_csrf_token" : @"pre-login-token",
    @"return_to" : @"/billing",
    @"cart" : @"planted",
  }];
  XCTAssertEqualObjects(@"pre-login-token", [context csrfToken]);
  NSError *error = nil;
  XCTAssertTrue([ALNAuthSession establishAuthenticatedSessionForSubject:@"user-1"
                                                               provider:@"local"
                                                                methods:@[ @"pwd" ]
                                                         assuranceLevel:1
                                                        authenticatedAt:nil
                                                                context:context
                                                                  error:&error]);
  XCTAssertNil(error);
  NSDictionary *session = [context session];
  XCTAssertEqualObjects((@[ @"_auth", @"return_to" ]), [[session allKeys] sortedArrayUsingSelector:@selector(compare:)]);
  XCTAssertEqualObjects(@"/billing", session[@"return_to"]);
  XCTAssertEqualObjects(@"user-1", [ALNAuthSession subjectFromContext:context]);
  NSString *fresh = [context csrfToken];
  XCTAssertTrue([fresh length] > 0);
  XCTAssertNotEqualObjects(@"pre-login-token", fresh);
  XCTAssertEqualObjects(fresh, [context session][@"_csrf_token"]);
}

- (void)testElevateStartsFreshSessionAndKeepsAuthState {
  ALNContext *context = [self contextWithSession:@{}];
  XCTAssertTrue([ALNAuthSession establishAuthenticatedSessionForSubject:@"user-2"
                                                               provider:@"local"
                                                                methods:@[ @"pwd" ]
                                                         assuranceLevel:1
                                                        authenticatedAt:nil
                                                                context:context
                                                                  error:NULL]);
  NSString *loginToken = [context csrfToken];
  NSString *loginSessionID = [ALNAuthSession sessionIdentifierFromContext:context];
  [context session][@"return_to"] = @"/settings";
  [context session][@"aln.auth_module.sms_state"] = @{ @"purpose" : @"challenge" };

  NSError *error = nil;
  XCTAssertTrue([ALNAuthSession elevateAuthenticatedSessionForMethod:@"totp"
                                                      assuranceLevel:2
                                                     authenticatedAt:nil
                                                             context:context
                                                               error:&error]);
  XCTAssertNil(error);
  NSDictionary *session = [context session];
  XCTAssertEqualObjects((@[ @"_auth", @"return_to" ]), [[session allKeys] sortedArrayUsingSelector:@selector(compare:)]);
  XCTAssertEqualObjects(@"user-2", [ALNAuthSession subjectFromContext:context]);
  XCTAssertEqual((NSUInteger)2, [ALNAuthSession assuranceLevelFromContext:context]);
  XCTAssertEqualObjects((@[ @"pwd", @"totp" ]), [ALNAuthSession authenticationMethodsFromContext:context]);
  XCTAssertNotEqualObjects(loginSessionID, [ALNAuthSession sessionIdentifierFromContext:context]);
  NSString *stepUpToken = [context csrfToken];
  XCTAssertTrue([stepUpToken length] > 0);
  XCTAssertNotEqualObjects(loginToken, stepUpToken);
}

#pragma mark - Auth module flows

- (ALNApplication *)authApplication {
  NSString *migrationsPath = [[[NSFileManager defaultManager] currentDirectoryPath]
      stringByAppendingPathComponent:@"modules/auth/Migrations"];
  NSError *error = nil;
  ALNPg *database = [[ALNPg alloc] initWithConnectionString:[self pgTestDSN] maxConnections:1 error:&error];
  XCTAssertNotNil(database, @"%@", error);
  XCTAssertTrue([ALNMigrationRunner applyMigrationsAtPath:migrationsPath
                                                 database:database
                                                   dryRun:NO
                                             appliedFiles:NULL
                                                    error:&error],
                @"%@", error);
  XCTAssertTrue([[ALNAuthModuleRuntime sharedRuntime] configureHooksWithModuleConfig:@{} error:&error]);
  ALNApplication *app = [[ALNApplication alloc] initWithConfig:@{
    @"environment" : @"test",
    @"logFormat" : @"json",
    @"session" : @{ @"enabled" : @YES, @"secret" : @"auth-session-regeneration-secret-0123456789abcdef" },
    @"csrf" : @{ @"enabled" : @YES, @"allowQueryParamFallback" : @YES },
    @"database" : @{ @"connectionString" : [self pgTestDSN] ?: @"" },
    @"authModule" : @{ @"registration" : @{ @"autoLogin" : @YES } },
  }];
  XCTAssertTrue([[[ALNAuthModule alloc] init] registerWithApplication:app error:&error], @"%@", error);
  return app;
}

- (ALNTestClient *)manualCSRFClientForApplication:(ALNApplication *)app {
  NSError *error = nil;
  ALNTestClient *client = [[ALNTestClient alloc] initWithApplication:app error:&error];
  XCTAssertNotNil(client, @"%@", error);
  client.automaticCSRF = NO;
  return client;
}

- (ALNResponse *)postJSON:(NSString *)path
                     body:(NSDictionary *)body
                    token:(NSString *)token
                   client:(ALNTestClient *)client {
  NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:@{
    @"content-type" : @"application/json",
    @"accept" : @"application/json",
  }];
  if ([token length] > 0) {
    headers[@"x-csrf-token"] = token;
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:body ?: @{} options:0 error:NULL];
  return [client requestWithMethod:@"POST" path:path query:nil headers:headers body:data];
}

- (NSString *)uniqueEmail {
  return [NSString stringWithFormat:@"session-regen-%@@example.test", [[[NSUUID UUID] UUIDString] lowercaseString]];
}

- (NSString *)hiddenCSRFTokenInHTML:(NSString *)html {
  NSString *marker = @"name=\"csrf_token\" value=\"";
  NSRange start = [html rangeOfString:marker];
  if (start.location == NSNotFound) {
    return nil;
  }
  NSUInteger from = NSMaxRange(start);
  NSRange end = [html rangeOfString:@"\"" options:0 range:NSMakeRange(from, [html length] - from)];
  return (end.location == NSNotFound) ? nil : [html substringWithRange:NSMakeRange(from, end.location - from)];
}

- (void)testPreLoginCSRFTokenIsRejectedAfterLoginAndStepUp {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self authApplication];
  NSString *email = [self uniqueEmail];
  NSString *password = @"session-regen-password-123";

  ALNTestClient *setup = [self manualCSRFClientForApplication:app];
  NSString *setupToken = [setup csrfToken];
  ALNResponse *registered = [self postJSON:@"/auth/api/register"
                                      body:@{ @"email" : email, @"display_name" : @"Regen", @"password" : password }
                                     token:setupToken
                                    client:setup];
  XCTAssertEqual((NSInteger)200, registered.statusCode, @"%@", [registered bodyText]);
  NSString *registeredToken = [registered JSONObject][@"csrf_token"];
  XCTAssertTrue([registeredToken length] > 0);
  XCTAssertNotEqualObjects(setupToken, registeredToken);
  NSString *secret = [[setup get:@"/auth/api/mfa/totp"] JSONObject][@"mfa"][@"provisioning"][@"secret"];
  XCTAssertTrue([secret length] > 0);
  NSString *enrollCode = [ALNTOTP codeForSecret:secret atDate:[NSDate dateWithTimeIntervalSinceNow:-30] error:NULL];
  ALNResponse *enrolled = [self postJSON:@"/auth/api/mfa/totp/verify"
                                    body:@{ @"code" : enrollCode }
                                   token:registeredToken
                                  client:setup];
  XCTAssertEqual((NSInteger)200, enrolled.statusCode, @"%@", [enrolled bodyText]);

  // A visitor's session (with a planted key and a known token) logs in.
  ALNTestClient *client = [self manualCSRFClientForApplication:app];
  NSString *preLoginToken = [client csrfToken];
  XCTAssertTrue([client updateSession:^(NSMutableDictionary *session) {
    session[@"return_to"] = @"/after-login";
    session[@"planted"] = @"value";
  }
                                error:NULL]);
  ALNResponse *login = [self postJSON:@"/auth/api/login"
                                 body:@{ @"email" : email, @"password" : password }
                                token:preLoginToken
                               client:client];
  XCTAssertEqual((NSInteger)200, login.statusCode, @"%@", [login bodyText]);
  NSString *loginToken = [login JSONObject][@"csrf_token"];
  XCTAssertTrue([loginToken length] > 0);
  XCTAssertNotEqualObjects(preLoginToken, loginToken);
  NSDictionary *session = [client session];
  XCTAssertEqualObjects(loginToken, session[@"_csrf_token"]);
  XCTAssertEqualObjects(@"/after-login", session[@"return_to"]);
  XCTAssertNil(session[@"planted"]);

  ALNResponse *stale = [self postJSON:@"/auth/api/mfa/totp/verify"
                                 body:@{ @"code" : @"000000" }
                                token:preLoginToken
                               client:client];
  XCTAssertEqual((NSInteger)403, stale.statusCode, @"%@", [stale bodyText]);

  // Step-up with the login token, then the login token stops working too.
  NSString *code = [ALNTOTP codeForSecret:secret atDate:[NSDate date] error:NULL];
  ALNResponse *stepUp = [self postJSON:@"/auth/api/mfa/totp/verify" body:@{ @"code" : code } token:loginToken client:client];
  XCTAssertEqual((NSInteger)200, stepUp.statusCode, @"%@", [stepUp bodyText]);
  NSString *stepUpToken = [stepUp JSONObject][@"csrf_token"];
  XCTAssertTrue([stepUpToken length] > 0);
  XCTAssertNotEqualObjects(loginToken, stepUpToken);
  XCTAssertEqualObjects(stepUpToken, [stepUp JSONObject][@"session"][@"csrf_token"]);
  XCTAssertEqualObjects(@"/after-login", [client session][@"return_to"]);

  XCTAssertEqual((NSInteger)403, [self postJSON:@"/auth/api/logout" body:@{} token:loginToken client:client].statusCode);
  XCTAssertEqual((NSInteger)403, [self postJSON:@"/auth/api/logout" body:@{} token:preLoginToken client:client].statusCode);
  XCTAssertEqualObjects(@2, [[client get:@"/auth/api/session"] JSONObject][@"aal"]);
  XCTAssertEqual((NSInteger)200, [self postJSON:@"/auth/api/logout" body:@{} token:stepUpToken client:client].statusCode);
  XCTAssertEqualObjects(@NO, [[client get:@"/auth/api/session"] JSONObject][@"authenticated"]);
}

- (void)testHTMLFormsCarryTheNewTokenAfterLogin {
  XCTSkipUnless([[self pgTestDSN] length] > 0, @"ARLEN_PG_TEST_DSN is not set");
  ALNApplication *app = [self authApplication];
  NSString *email = [self uniqueEmail];
  NSString *password = @"session-regen-password-123";
  ALNTestClient *setup = [self manualCSRFClientForApplication:app];
  ALNResponse *registered = [self postJSON:@"/auth/api/register"
                                      body:@{ @"email" : email, @"display_name" : @"Regen", @"password" : password }
                                     token:[setup csrfToken]
                                    client:setup];
  XCTAssertEqual((NSInteger)200, registered.statusCode, @"%@", [registered bodyText]);

  ALNTestClient *browser = [self manualCSRFClientForApplication:app];
  ALNResponse *loginPage = [browser get:@"/auth/login"];
  XCTAssertEqual((NSInteger)200, loginPage.statusCode);
  NSString *preLoginToken = [self hiddenCSRFTokenInHTML:[loginPage bodyText]];
  XCTAssertTrue([preLoginToken length] > 0, @"%@", [loginPage bodyText]);
  NSString *form = [NSString stringWithFormat:@"email=%@&password=%@&csrf_token=%@",
                                              [email stringByAddingPercentEncodingWithAllowedCharacters:
                                                         [NSCharacterSet alphanumericCharacterSet]],
                                              password,
                                              preLoginToken];
  ALNResponse *login = [browser requestWithMethod:@"POST"
                                             path:@"/auth/login"
                                            query:nil
                                          headers:@{ @"content-type" : @"application/x-www-form-urlencoded" }
                                             body:[form dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqual((NSInteger)302, login.statusCode, @"%@", [login bodyText]);

  ALNResponse *totpPage = [browser get:@"/auth/mfa/totp"];
  XCTAssertEqual((NSInteger)200, totpPage.statusCode, @"%@", [totpPage bodyText]);
  NSString *formToken = [self hiddenCSRFTokenInHTML:[totpPage bodyText]];
  XCTAssertTrue([formToken length] > 0);
  XCTAssertNotEqualObjects(preLoginToken, formToken);

  NSString *staleLogout = [NSString stringWithFormat:@"csrf_token=%@", preLoginToken];
  ALNResponse *stale = [browser requestWithMethod:@"POST"
                                             path:@"/auth/logout"
                                            query:nil
                                          headers:@{ @"content-type" : @"application/x-www-form-urlencoded" }
                                             body:[staleLogout dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqual((NSInteger)403, stale.statusCode);
  NSString *logout = [NSString stringWithFormat:@"csrf_token=%@", formToken];
  ALNResponse *loggedOut = [browser requestWithMethod:@"POST"
                                               path:@"/auth/logout"
                                              query:nil
                                            headers:@{ @"content-type" : @"application/x-www-form-urlencoded" }
                                               body:[logout dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqual((NSInteger)302, loggedOut.statusCode, @"%@", [loggedOut bodyText]);
}

@end
