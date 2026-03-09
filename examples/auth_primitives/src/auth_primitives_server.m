#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>

#import "ArlenServer.h"
#import "ALNAuthProviderSessionBridge.h"
#import "ALNOIDCClient.h"
#import "ALNSecurityPrimitives.h"

static NSString *const APProviderAuthStateSessionKey = @"phase12_oidc_state";
static NSString *const APTOTPSecret = @"JBSWY3DPEHPK3PXP";

static NSString *APEnvValue(const char *name) {
  const char *value = getenv(name);
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

static NSString *APResolveAppRoot(void) {
  NSString *override = APEnvValue("ARLEN_APP_ROOT");
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  if ([override length] == 0) {
    return cwd;
  }
  if ([override hasPrefix:@"/"]) {
    return [override stringByStandardizingPath];
  }
  return [[cwd stringByAppendingPathComponent:override] stringByStandardizingPath];
}

static NSString *APTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([trimmed length] > 0) ? trimmed : nil;
}

static NSString *APBase64URLForJSONObject(NSDictionary *object) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:object ?: @{} options:0 error:NULL];
  return ALNBase64URLStringFromData(data) ?: @"";
}

static NSString *APStubHS256JWT(NSDictionary *claims, NSString *sharedSecret) {
  NSDictionary *header = @{
    @"alg" : @"HS256",
    @"typ" : @"JWT",
  };
  NSString *headerPart = APBase64URLForJSONObject(header);
  NSString *payloadPart = APBase64URLForJSONObject(claims);
  NSString *signingInput = [NSString stringWithFormat:@"%@.%@", headerPart, payloadPart];
  NSData *digest = ALNHMACSHA256([signingInput dataUsingEncoding:NSUTF8StringEncoding],
                                 [sharedSecret dataUsingEncoding:NSUTF8StringEncoding]);
  NSString *signaturePart = ALNBase64URLStringFromData(digest) ?: @"";
  return [NSString stringWithFormat:@"%@.%@.%@", headerPart, payloadPart, signaturePart];
}

@interface AuthPrimitivesResolver : NSObject <ALNAuthProviderSessionResolver>
@end

@implementation AuthPrimitivesResolver

- (NSDictionary *)resolveSessionDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                          providerConfiguration:(NSDictionary *)providerConfiguration
                                                          error:(NSError **)error {
  (void)error;
  NSString *email = APTrimmedString(normalizedIdentity[@"email"]);
  NSString *provider = APTrimmedString(providerConfiguration[@"identifier"]) ?: @"provider";
  NSString *providerSubject = APTrimmedString(normalizedIdentity[@"provider_subject"]) ?: @"subject";
  NSString *subject = ([email length] > 0)
                          ? [[NSString stringWithFormat:@"user:%@", [email lowercaseString]] copy]
                          : [NSString stringWithFormat:@"%@:%@", provider, providerSubject];
  return @{
    @"subject" : subject,
    @"provider" : provider,
    @"methods" : @[ @"federated" ],
    @"assuranceLevel" : @1,
  };
}

- (NSDictionary *)accountLinkingDescriptorForNormalizedIdentity:(NSDictionary *)normalizedIdentity
                                          providerConfiguration:(NSDictionary *)providerConfiguration
                                                          error:(NSError **)error {
  (void)providerConfiguration;
  (void)error;
  NSString *candidateKey =
      APTrimmedString(normalizedIdentity[@"email"]) ?:
      APTrimmedString(normalizedIdentity[@"provider_subject"]) ?:
      @"";
  return @{
    @"strategy" : @"email_or_provider_subject",
    @"candidateKey" : candidateKey,
  };
}

@end

@interface AuthPrimitivesController : ALNController
@end

@implementation AuthPrimitivesController

- (NSString *)requestBaseURL:(ALNContext *)ctx {
  NSString *host = APTrimmedString([self headerValueForName:@"host"]);
  if ([host length] == 0) {
    host = @"127.0.0.1:3135";
  }
  NSString *scheme = @"http";
  return [NSString stringWithFormat:@"%@://%@", scheme, host];
}

- (NSDictionary *)stubProviderConfigurationForContext:(ALNContext *)ctx {
  NSString *baseURL = [self requestBaseURL:ctx];
  return @{
    @"identifier" : @"stub_oidc",
    @"displayName" : @"Stub OIDC",
    @"protocol" : @"oidc",
    @"issuer" : @"https://stub.arlen.invalid",
    @"authorizationEndpoint" : [baseURL stringByAppendingString:@"/auth/provider/stub/authorize"],
    @"tokenEndpoint" : @"https://stub.arlen.invalid/token",
    @"clientID" : @"phase12-demo-client",
    @"clientSecret" : @"phase12-demo-client-secret-0123456789abcdef",
    @"callbackMaxAgeSeconds" : @300,
    @"defaultScopes" : @[ @"openid", @"email", @"profile" ],
  };
}

- (NSDictionary *)sessionPayload {
  return @{
    @"subject" : [self authSubject] ?: @"",
    @"provider" : [self authProvider] ?: @"",
    @"aal" : @([self authAssuranceLevel]),
    @"mfa" : @([self isMFAAuthenticated]),
    @"methods" : [self authMethods] ?: @[],
    @"session_id" : [self authSessionIdentifier] ?: @"",
  };
}

- (id)root:(ALNContext *)ctx {
  (void)ctx;
  return @{
    @"application" : @"auth_primitives_server",
    @"server" : @"boomhauer",
    @"routes" : @[
      @"/auth/session",
      @"/auth/local/login",
      @"/auth/local/totp/provisioning",
      @"/auth/local/totp/verify",
      @"/auth/provider/stub/login",
      @"/auth/provider/secure",
    ],
  };
}

- (id)health:(ALNContext *)ctx {
  (void)ctx;
  [self renderText:@"ok\n"];
  return nil;
}

- (id)sessionState:(ALNContext *)ctx {
  (void)ctx;
  return [self sessionPayload];
}

- (id)localLogin:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  if (![self startAuthenticatedSessionForSubject:@"local-user-123"
                                        provider:@"local"
                                         methods:@[ @"pwd" ]
                                           error:&error]) {
    [self setStatus:500];
    return @{
      @"error" : @{
        @"code" : @"session_start_failed",
        @"message" : error.localizedDescription ?: @"session start failed",
      }
    };
  }
  return @{
    @"session" : [self sessionPayload],
  };
}

- (id)localTOTPProvisioning:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  NSString *uri = [ALNTOTP provisioningURIForSecret:APTOTPSecret
                                        accountName:@"demo@example.com"
                                             issuer:@"Arlen Auth Primitives"
                                              error:&error];
  if ([uri length] == 0) {
    [self setStatus:500];
    return @{
      @"error" : @{
        @"code" : @"totp_provisioning_failed",
        @"message" : error.localizedDescription ?: @"totp provisioning failed",
      }
    };
  }
  return @{
    @"otpauth_uri" : uri,
    @"session" : [self sessionPayload],
  };
}

- (id)localTOTPVerify:(ALNContext *)ctx {
  (void)ctx;
  NSString *code = APTrimmedString([self stringParamForName:@"code"]);
  if ([[self authSubject] length] == 0) {
    [self setStatus:403];
    return @{
      @"error" : @{
        @"code" : @"authentication_required",
        @"message" : @"Primary authentication is required before TOTP step-up",
      }
    };
  }

  NSError *error = nil;
  BOOL verified = [ALNTOTP verifyCode:code
                               secret:APTOTPSecret
                               atDate:[NSDate date]
                               digits:6
                               period:30
                 allowedPastIntervals:1
               allowedFutureIntervals:1
                                error:&error];
  if (!verified) {
    [self setStatus:401];
    return @{
      @"error" : @{
        @"code" : @"invalid_totp",
        @"message" : error.localizedDescription ?: @"invalid TOTP code",
      }
    };
  }

  if (![self completeStepUpWithMethod:@"totp" assuranceLevel:2 error:&error]) {
    [self setStatus:500];
    return @{
      @"error" : @{
        @"code" : @"step_up_failed",
        @"message" : error.localizedDescription ?: @"step-up failed",
      }
    };
  }

  return @{
    @"session" : [self sessionPayload],
  };
}

- (id)stubProviderLogin:(ALNContext *)ctx {
  NSDictionary *providerConfiguration = [self stubProviderConfigurationForContext:ctx];
  NSString *redirectURI = [[self requestBaseURL:ctx] stringByAppendingString:@"/auth/provider/stub/callback"];
  NSError *error = nil;
  NSDictionary *authorizationRequest =
      [ALNOIDCClient authorizationRequestForProviderConfiguration:providerConfiguration
                                                      redirectURI:redirectURI
                                                           scopes:nil
                                                    referenceDate:[NSDate date]
                                                            error:&error];
  if (authorizationRequest == nil) {
    [self setStatus:500];
    return @{
      @"error" : @{
        @"code" : @"authorization_request_failed",
        @"message" : error.localizedDescription ?: @"authorization request failed",
      }
    };
  }

  NSMutableDictionary *session = [self session];
  session[APProviderAuthStateSessionKey] = authorizationRequest;
  [self markSessionDirty];
  [self redirectTo:authorizationRequest[@"authorizationURL"] status:302];
  return nil;
}

- (id)stubProviderAuthorize:(ALNContext *)ctx {
  (void)ctx;
  NSString *redirectURI = APTrimmedString([self stringParamForName:@"redirect_uri"]);
  NSString *state = APTrimmedString([self stringParamForName:@"state"]);
  if ([redirectURI length] == 0 || [state length] == 0) {
    [self setStatus:400];
    return @{
      @"error" : @{
        @"code" : @"invalid_authorize_request",
        @"message" : @"redirect_uri and state are required",
      }
    };
  }
  NSString *location = [NSString stringWithFormat:@"%@?code=stub-provider-code&state=%@",
                                                  redirectURI,
                                                  state];
  [self redirectTo:location status:302];
  return nil;
}

- (id)stubProviderCallback:(ALNContext *)ctx {
  NSDictionary *providerConfiguration = [self stubProviderConfigurationForContext:ctx];
  NSMutableDictionary *session = [self session];
  NSDictionary *callbackState = [session[APProviderAuthStateSessionKey] isKindOfClass:[NSDictionary class]]
                                     ? session[APProviderAuthStateSessionKey]
                                     : nil;
  if (callbackState != nil) {
    [session removeObjectForKey:APProviderAuthStateSessionKey];
    [self markSessionDirty];
  }
  if (callbackState == nil) {
    [self setStatus:400];
    return @{
      @"error" : @{
        @"code" : @"missing_callback_state",
        @"message" : @"No OIDC callback state is present in the session",
      }
    };
  }

  NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
  NSDictionary *claims = @{
    @"iss" : providerConfiguration[@"issuer"] ?: @"",
    @"sub" : @"provider-user-123",
    @"aud" : providerConfiguration[@"clientID"] ?: @"",
    @"exp" : @((NSInteger)(now + 300)),
    @"iat" : @((NSInteger)now),
    @"nonce" : callbackState[@"nonce"] ?: @"",
    @"email" : @"oidc-user@example.com",
    @"email_verified" : @(YES),
    @"name" : @"OIDC Demo User",
  };
  NSString *idToken = APStubHS256JWT(claims, providerConfiguration[@"clientSecret"] ?: @"");
  NSDictionary *tokenResponse = @{
    @"access_token" : @"stub-access-token",
    @"token_type" : @"Bearer",
    @"expires_in" : @300,
    @"scope" : @"openid email profile",
    @"id_token" : idToken ?: @"",
  };

  AuthPrimitivesResolver *resolver = [[AuthPrimitivesResolver alloc] init];
  NSError *error = nil;
  NSDictionary *result =
      [ALNAuthProviderSessionBridge completeLoginWithCallbackParameters:[self params]
                                                         callbackState:callbackState
                                                         tokenResponse:tokenResponse
                                                      userInfoResponse:nil
                                                 providerConfiguration:providerConfiguration
                                                          jwksDocument:nil
                                                              resolver:resolver
                                                               context:ctx
                                                                 error:&error];
  if (result == nil) {
    [self setStatus:400];
    return @{
      @"error" : @{
        @"code" : @"provider_login_failed",
        @"message" : error.localizedDescription ?: @"provider login failed",
      }
    };
  }
  return result;
}

- (id)secure:(ALNContext *)ctx {
  (void)ctx;
  return @{
    @"ok" : @(YES),
    @"session" : [self sessionPayload],
  };
}

@end

static ALNApplication *BuildApplication(NSString *environment, NSString *appRoot) {
  NSError *error = nil;
  ALNApplication *app = [[ALNApplication alloc] initWithEnvironment:environment
                                                         configRoot:appRoot
                                                              error:&error];
  if (app == nil) {
    fprintf(stderr, "auth-primitives-server: failed loading config from %s: %s\n",
            [appRoot UTF8String], [[error localizedDescription] UTF8String]);
    return nil;
  }

  [app registerRouteMethod:@"GET"
                      path:@"/"
                      name:@"auth_primitives_root"
           controllerClass:[AuthPrimitivesController class]
                    action:@"root"];
  [app registerRouteMethod:@"GET"
                      path:@"/healthz"
                      name:@"healthz"
           controllerClass:[AuthPrimitivesController class]
                    action:@"health"];
  [app registerRouteMethod:@"GET"
                      path:@"/auth/session"
                      name:@"auth_session"
           controllerClass:[AuthPrimitivesController class]
                    action:@"sessionState"];
  [app registerRouteMethod:@"GET"
                      path:@"/auth/local/login"
                      name:@"auth_local_login"
           controllerClass:[AuthPrimitivesController class]
                    action:@"localLogin"];
  [app registerRouteMethod:@"GET"
                      path:@"/auth/local/totp/provisioning"
                      name:@"auth_local_totp_provisioning"
           controllerClass:[AuthPrimitivesController class]
                    action:@"localTOTPProvisioning"];
  [app registerRouteMethod:@"GET"
                      path:@"/auth/local/totp/verify"
                      name:@"auth_local_totp_verify"
           controllerClass:[AuthPrimitivesController class]
                    action:@"localTOTPVerify"];
  [app registerRouteMethod:@"GET"
                      path:@"/auth/provider/stub/login"
                      name:@"auth_provider_stub_login"
           controllerClass:[AuthPrimitivesController class]
                    action:@"stubProviderLogin"];
  [app registerRouteMethod:@"GET"
                      path:@"/auth/provider/stub/authorize"
                      name:@"auth_provider_stub_authorize"
           controllerClass:[AuthPrimitivesController class]
                    action:@"stubProviderAuthorize"];
  [app registerRouteMethod:@"GET"
                      path:@"/auth/provider/stub/callback"
                      name:@"auth_provider_stub_callback"
           controllerClass:[AuthPrimitivesController class]
                    action:@"stubProviderCallback"];
  [app registerRouteMethod:@"GET"
                      path:@"/auth/provider/secure"
                      name:@"auth_provider_secure"
           controllerClass:[AuthPrimitivesController class]
                    action:@"secure"];

  if (![app configureAuthAssuranceForRouteNamed:@"auth_provider_secure"
                      minimumAuthAssuranceLevel:2
                maximumAuthenticationAgeSeconds:0
                                     stepUpPath:@"/auth/local/totp/verify"
                                          error:&error]) {
    fprintf(stderr, "auth-primitives-server: failed configuring auth assurance: %s\n",
            [[error localizedDescription] UTF8String]);
    return nil;
  }

  return app;
}

static void PrintUsage(void) {
  fprintf(stdout,
          "Usage: auth-primitives-server [--port <port>] [--host <addr>] [--env <env>] [--once] [--print-routes]\n");
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    int portOverride = 0;
    NSString *host = nil;
    NSString *environment = @"development";
    BOOL once = NO;
    BOOL printRoutes = NO;

    for (int idx = 1; idx < argc; idx++) {
      NSString *arg = [NSString stringWithUTF8String:argv[idx]];
      if ([arg isEqualToString:@"--port"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        portOverride = atoi(argv[++idx]);
      } else if ([arg isEqualToString:@"--host"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        host = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--env"]) {
        if (idx + 1 >= argc) {
          PrintUsage();
          return 2;
        }
        environment = [NSString stringWithUTF8String:argv[++idx]];
      } else if ([arg isEqualToString:@"--once"]) {
        once = YES;
      } else if ([arg isEqualToString:@"--print-routes"]) {
        printRoutes = YES;
      } else if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
        PrintUsage();
        return 0;
      } else {
        fprintf(stderr, "Unknown argument: %s\n", argv[idx]);
        return 2;
      }
    }

    NSString *appRoot = APResolveAppRoot();
    ALNApplication *app = BuildApplication(environment, appRoot);
    if (app == nil) {
      return 1;
    }

    NSString *publicRoot = [appRoot stringByAppendingPathComponent:@"public"];
    ALNHTTPServer *server = [[ALNHTTPServer alloc] initWithApplication:app
                                                             publicRoot:publicRoot];
    server.serverName = @"auth-primitives-server";

    if (printRoutes) {
      [server printRoutesToFile:stdout];
      return 0;
    }

    return [server runWithHost:host portOverride:portOverride once:once];
  }
}
