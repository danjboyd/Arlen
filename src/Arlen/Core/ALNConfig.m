#import "ALNConfig.h"

#import <stdlib.h>

static NSString *const ALNConfigErrorDomain = @"Arlen.Config.Error";

static NSDictionary *ALNMergeDictionaries(NSDictionary *base, NSDictionary *overlay) {
  NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:base ?: @{}];
  for (NSString *key in overlay) {
    id overlayValue = overlay[key];
    id baseValue = merged[key];
    if ([baseValue isKindOfClass:[NSDictionary class]] &&
        [overlayValue isKindOfClass:[NSDictionary class]]) {
      merged[key] = ALNMergeDictionaries(baseValue, overlayValue);
    } else {
      merged[key] = overlayValue;
    }
  }
  return merged;
}

static NSDictionary *ALNLoadPlist(NSString *path, NSError **error) {
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    return @{};
  }

  NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
  if (data == nil) {
    return nil;
  }

  NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
  id plist = [NSPropertyListSerialization propertyListWithData:data
                                                       options:NSPropertyListImmutable
                                                        format:&format
                                                         error:error];
  if (![plist isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:ALNConfigErrorDomain
                                   code:2
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                   [NSString stringWithFormat:@"Config plist is not a dictionary: %@",
                                                              path]
                               }];
    }
    return nil;
  }
  return plist;
}

static NSNumber *ALNParseBooleanString(NSString *value) {
  if ([value length] == 0) {
    return nil;
  }
  NSString *normalized = [[value lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"] ||
      [normalized isEqualToString:@"yes"] || [normalized isEqualToString:@"on"]) {
    return @(YES);
  }
  if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"] ||
      [normalized isEqualToString:@"no"] || [normalized isEqualToString:@"off"]) {
    return @(NO);
  }
  return nil;
}

static void ALNApplyIntegerOverride(NSMutableDictionary *target,
                                    NSString *value,
                                    NSString *key,
                                    NSInteger minimum) {
  if ([value length] == 0) {
    return;
  }
  NSInteger parsed = [value integerValue];
  if (parsed < minimum) {
    return;
  }
  target[key] = @(parsed);
}

static void ALNApplyLimitOverride(NSMutableDictionary *limits, NSString *value, NSString *key) {
  ALNApplyIntegerOverride(limits, value, key, 1);
}

static NSString *ALNEnvValue(const char *name) {
  const char *value = getenv(name);
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  return [NSString stringWithUTF8String:value];
}

static NSString *ALNEnvValueCompat(const char *primary, const char *legacy) {
  NSString *primaryValue = ALNEnvValue(primary);
  if ([primaryValue length] > 0) {
    return primaryValue;
  }
  return ALNEnvValue(legacy);
}

static NSArray *ALNNormalizeExtensionList(NSArray *values) {
  NSMutableArray *normalized = [NSMutableArray array];
  for (id value in values ?: @[]) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *extension = [[(NSString *)value lowercaseString]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([extension hasPrefix:@"."]) {
      extension = [extension substringFromIndex:1];
    }
    if ([extension length] == 0 || [normalized containsObject:extension]) {
      continue;
    }
    [normalized addObject:extension];
  }
  return [NSArray arrayWithArray:normalized];
}

static NSArray *ALNParseCSVExtensions(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return @[];
  }
  NSArray *parts = [value componentsSeparatedByString:@","];
  return ALNNormalizeExtensionList(parts);
}

static NSString *ALNDefaultClusterNodeID(void) {
  NSString *host = [[[NSProcessInfo processInfo] hostName] lowercaseString];
  host = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([host length] == 0) {
    host = @"node";
  }
  return host;
}

static NSString *ALNNormalizedSecurityProfileName(id rawValue) {
  if (![rawValue isKindOfClass:[NSString class]]) {
    return @"balanced";
  }
  NSString *normalized = [[(NSString *)rawValue lowercaseString]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"strict"]) {
    return @"strict";
  }
  if ([normalized isEqualToString:@"edge"]) {
    return @"edge";
  }
  if ([normalized isEqualToString:@"balanced"]) {
    return @"balanced";
  }
  return @"balanced";
}

static NSDictionary *ALNSecurityProfileDefaults(NSString *profileName) {
  NSString *normalized = ALNNormalizedSecurityProfileName(profileName);
  if ([normalized isEqualToString:@"strict"]) {
    return @{
      @"trustedProxy" : @(NO),
      @"sessionEnabled" : @(YES),
      @"csrfEnabled" : @(YES),
      @"securityHeadersEnabled" : @(YES),
    };
  }
  if ([normalized isEqualToString:@"edge"]) {
    return @{
      @"trustedProxy" : @(YES),
      @"sessionEnabled" : @(NO),
      @"csrfEnabled" : @(NO),
      @"securityHeadersEnabled" : @(YES),
    };
  }
  return @{
    @"trustedProxy" : @(NO),
    @"sessionEnabled" : @(NO),
    @"csrfEnabled" : @(NO),
    @"securityHeadersEnabled" : @(YES),
  };
}

@implementation ALNConfig

+ (NSDictionary *)loadConfigAtRoot:(NSString *)rootPath
                       environment:(NSString *)environment
                             error:(NSError **)error {
  NSString *env = ([environment length] > 0) ? environment : @"development";
  NSString *configRoot = [rootPath stringByAppendingPathComponent:@"config"];
  NSString *basePath = [configRoot stringByAppendingPathComponent:@"app.plist"];
  NSString *envPath =
      [[configRoot stringByAppendingPathComponent:@"environments"]
          stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", env]];

  NSError *baseError = nil;
  NSDictionary *base = ALNLoadPlist(basePath, &baseError);
  if (base == nil) {
    if (error != NULL) {
      *error = baseError;
    }
    return nil;
  }

  NSError *envError = nil;
  NSDictionary *overlay = ALNLoadPlist(envPath, &envError);
  if (overlay == nil) {
    if (error != NULL) {
      *error = envError;
    }
    return nil;
  }

  NSMutableDictionary *config =
      [NSMutableDictionary dictionaryWithDictionary:ALNMergeDictionaries(base, overlay)];
  config[@"environment"] = env;

  NSString *host = ALNEnvValueCompat("ARLEN_HOST", "MOJOOBJC_HOST");
  NSString *port = ALNEnvValueCompat("ARLEN_PORT", "MOJOOBJC_PORT");
  NSString *logFormat = ALNEnvValueCompat("ARLEN_LOG_FORMAT", "MOJOOBJC_LOG_FORMAT");
  NSString *trustedProxy =
      ALNEnvValueCompat("ARLEN_TRUSTED_PROXY", "MOJOOBJC_TRUSTED_PROXY");
  NSString *performanceLogging = ALNEnvValueCompat("ARLEN_PERFORMANCE_LOGGING",
                                                   "MOJOOBJC_PERFORMANCE_LOGGING");
  NSString *tracePropagationEnabled =
      ALNEnvValueCompat("ARLEN_TRACE_PROPAGATION_ENABLED",
                        "MOJOOBJC_TRACE_PROPAGATION_ENABLED");
  NSString *healthDetailsEnabled =
      ALNEnvValueCompat("ARLEN_HEALTH_DETAILS_ENABLED",
                        "MOJOOBJC_HEALTH_DETAILS_ENABLED");
  NSString *readinessRequiresStartup =
      ALNEnvValueCompat("ARLEN_READINESS_REQUIRES_STARTUP",
                        "MOJOOBJC_READINESS_REQUIRES_STARTUP");
  NSString *readinessRequiresClusterQuorum =
      ALNEnvValueCompat("ARLEN_READINESS_REQUIRES_CLUSTER_QUORUM",
                        "MOJOOBJC_READINESS_REQUIRES_CLUSTER_QUORUM");
  NSString *serveStatic = ALNEnvValueCompat("ARLEN_SERVE_STATIC", "MOJOOBJC_SERVE_STATIC");
  NSString *staticAllowExtensions =
      ALNEnvValueCompat("ARLEN_STATIC_ALLOW_EXTENSIONS", "MOJOOBJC_STATIC_ALLOW_EXTENSIONS");
  NSString *apiOnly = ALNEnvValueCompat("ARLEN_API_ONLY", "MOJOOBJC_API_ONLY");
  NSString *securityProfile =
      ALNEnvValueCompat("ARLEN_SECURITY_PROFILE", "MOJOOBJC_SECURITY_PROFILE");
  NSString *maxRequestLineBytes =
      ALNEnvValueCompat("ARLEN_MAX_REQUEST_LINE_BYTES", "MOJOOBJC_MAX_REQUEST_LINE_BYTES");
  NSString *maxHeaderBytes =
      ALNEnvValueCompat("ARLEN_MAX_HEADER_BYTES", "MOJOOBJC_MAX_HEADER_BYTES");
  NSString *maxBodyBytes =
      ALNEnvValueCompat("ARLEN_MAX_BODY_BYTES", "MOJOOBJC_MAX_BODY_BYTES");
  NSString *maxWebSocketSessions =
      ALNEnvValueCompat("ARLEN_MAX_WEBSOCKET_SESSIONS", "MOJOOBJC_MAX_WEBSOCKET_SESSIONS");

  NSString *listenBacklog =
      ALNEnvValueCompat("ARLEN_LISTEN_BACKLOG", "MOJOOBJC_LISTEN_BACKLOG");
  NSString *connectionTimeoutSeconds = ALNEnvValueCompat("ARLEN_CONNECTION_TIMEOUT_SECONDS",
                                                         "MOJOOBJC_CONNECTION_TIMEOUT_SECONDS");
  NSString *enableReusePort =
      ALNEnvValueCompat("ARLEN_ENABLE_REUSEPORT", "MOJOOBJC_ENABLE_REUSEPORT");

  NSString *propaneWorkers =
      ALNEnvValueCompat("ARLEN_PROPANE_WORKERS", "MOJOOBJC_PROPANE_WORKERS");
  NSString *propaneGracefulShutdownSeconds =
      ALNEnvValueCompat("ARLEN_PROPANE_GRACEFUL_SHUTDOWN_SECONDS",
                        "MOJOOBJC_PROPANE_GRACEFUL_SHUTDOWN_SECONDS");
  NSString *propaneRespawnDelayMs =
      ALNEnvValueCompat("ARLEN_PROPANE_RESPAWN_DELAY_MS", "MOJOOBJC_PROPANE_RESPAWN_DELAY_MS");
  NSString *propaneReloadOverlapSeconds =
      ALNEnvValueCompat("ARLEN_PROPANE_RELOAD_OVERLAP_SECONDS",
                        "MOJOOBJC_PROPANE_RELOAD_OVERLAP_SECONDS");

  NSString *databaseConnectionString =
      ALNEnvValueCompat("ARLEN_DATABASE_URL", "MOJOOBJC_DATABASE_URL");
  NSString *databasePoolSize =
      ALNEnvValueCompat("ARLEN_DB_POOL_SIZE", "MOJOOBJC_DB_POOL_SIZE");
  NSString *databaseAdapter =
      ALNEnvValueCompat("ARLEN_DB_ADAPTER", "MOJOOBJC_DB_ADAPTER");

  NSString *sessionEnabled =
      ALNEnvValueCompat("ARLEN_SESSION_ENABLED", "MOJOOBJC_SESSION_ENABLED");
  NSString *sessionSecret =
      ALNEnvValueCompat("ARLEN_SESSION_SECRET", "MOJOOBJC_SESSION_SECRET");
  NSString *sessionCookieName =
      ALNEnvValueCompat("ARLEN_SESSION_COOKIE_NAME", "MOJOOBJC_SESSION_COOKIE_NAME");
  NSString *sessionMaxAge =
      ALNEnvValueCompat("ARLEN_SESSION_MAX_AGE_SECONDS", "MOJOOBJC_SESSION_MAX_AGE_SECONDS");
  NSString *sessionSecure =
      ALNEnvValueCompat("ARLEN_SESSION_SECURE", "MOJOOBJC_SESSION_SECURE");
  NSString *sessionSameSite =
      ALNEnvValueCompat("ARLEN_SESSION_SAMESITE", "MOJOOBJC_SESSION_SAMESITE");

  NSString *csrfEnabled = ALNEnvValueCompat("ARLEN_CSRF_ENABLED", "MOJOOBJC_CSRF_ENABLED");
  NSString *csrfHeaderName =
      ALNEnvValueCompat("ARLEN_CSRF_HEADER_NAME", "MOJOOBJC_CSRF_HEADER_NAME");
  NSString *csrfQueryParamName =
      ALNEnvValueCompat("ARLEN_CSRF_QUERY_PARAM_NAME", "MOJOOBJC_CSRF_QUERY_PARAM_NAME");

  NSString *rateLimitEnabled =
      ALNEnvValueCompat("ARLEN_RATE_LIMIT_ENABLED", "MOJOOBJC_RATE_LIMIT_ENABLED");
  NSString *rateLimitRequests =
      ALNEnvValueCompat("ARLEN_RATE_LIMIT_REQUESTS", "MOJOOBJC_RATE_LIMIT_REQUESTS");
  NSString *rateLimitWindowSeconds =
      ALNEnvValueCompat("ARLEN_RATE_LIMIT_WINDOW_SECONDS", "MOJOOBJC_RATE_LIMIT_WINDOW_SECONDS");

  NSString *securityHeadersEnabled =
      ALNEnvValueCompat("ARLEN_SECURITY_HEADERS_ENABLED", "MOJOOBJC_SECURITY_HEADERS_ENABLED");
  NSString *securityHeadersCSP =
      ALNEnvValueCompat("ARLEN_CONTENT_SECURITY_POLICY", "MOJOOBJC_CONTENT_SECURITY_POLICY");
  NSString *authEnabled =
      ALNEnvValueCompat("ARLEN_AUTH_ENABLED", "MOJOOBJC_AUTH_ENABLED");
  NSString *authBearerSecret =
      ALNEnvValueCompat("ARLEN_AUTH_BEARER_SECRET", "MOJOOBJC_AUTH_BEARER_SECRET");
  NSString *authIssuer =
      ALNEnvValueCompat("ARLEN_AUTH_ISSUER", "MOJOOBJC_AUTH_ISSUER");
  NSString *authAudience =
      ALNEnvValueCompat("ARLEN_AUTH_AUDIENCE", "MOJOOBJC_AUTH_AUDIENCE");
  NSString *openapiEnabled =
      ALNEnvValueCompat("ARLEN_OPENAPI_ENABLED", "MOJOOBJC_OPENAPI_ENABLED");
  NSString *openapiDocsUIEnabled =
      ALNEnvValueCompat("ARLEN_OPENAPI_DOCS_UI_ENABLED", "MOJOOBJC_OPENAPI_DOCS_UI_ENABLED");
  NSString *openapiTitle =
      ALNEnvValueCompat("ARLEN_OPENAPI_TITLE", "MOJOOBJC_OPENAPI_TITLE");
  NSString *openapiVersion =
      ALNEnvValueCompat("ARLEN_OPENAPI_VERSION", "MOJOOBJC_OPENAPI_VERSION");
  NSString *openapiDocsUIStyle =
      ALNEnvValueCompat("ARLEN_OPENAPI_DOCS_UI_STYLE", "MOJOOBJC_OPENAPI_DOCS_UI_STYLE");
  NSString *i18nDefaultLocale =
      ALNEnvValueCompat("ARLEN_I18N_DEFAULT_LOCALE", "MOJOOBJC_I18N_DEFAULT_LOCALE");
  NSString *i18nFallbackLocale =
      ALNEnvValueCompat("ARLEN_I18N_FALLBACK_LOCALE", "MOJOOBJC_I18N_FALLBACK_LOCALE");
  NSString *compatibilityPageStateEnabled =
      ALNEnvValueCompat("ARLEN_PAGE_STATE_COMPAT_ENABLED", "MOJOOBJC_PAGE_STATE_COMPAT_ENABLED");
  NSString *responseEnvelopeEnabled =
      ALNEnvValueCompat("ARLEN_RESPONSE_ENVELOPE_ENABLED", "MOJOOBJC_RESPONSE_ENVELOPE_ENABLED");
  NSString *clusterEnabled =
      ALNEnvValueCompat("ARLEN_CLUSTER_ENABLED", "MOJOOBJC_CLUSTER_ENABLED");
  NSString *clusterName =
      ALNEnvValueCompat("ARLEN_CLUSTER_NAME", "MOJOOBJC_CLUSTER_NAME");
  NSString *clusterNodeID =
      ALNEnvValueCompat("ARLEN_CLUSTER_NODE_ID", "MOJOOBJC_CLUSTER_NODE_ID");
  NSString *clusterExpectedNodes =
      ALNEnvValueCompat("ARLEN_CLUSTER_EXPECTED_NODES", "MOJOOBJC_CLUSTER_EXPECTED_NODES");
  NSString *clusterObservedNodes =
      ALNEnvValueCompat("ARLEN_CLUSTER_OBSERVED_NODES", "MOJOOBJC_CLUSTER_OBSERVED_NODES");
  NSString *clusterEmitHeaders =
      ALNEnvValueCompat("ARLEN_CLUSTER_EMIT_HEADERS", "MOJOOBJC_CLUSTER_EMIT_HEADERS");
  NSString *eocStrictLocals =
      ALNEnvValueCompat("ARLEN_EOC_STRICT_LOCALS", "MOJOOBJC_EOC_STRICT_LOCALS");
  NSString *eocStrictStringify =
      ALNEnvValueCompat("ARLEN_EOC_STRICT_STRINGIFY", "MOJOOBJC_EOC_STRICT_STRINGIFY");

  if ([host length] > 0) {
    config[@"host"] = host;
  }
  if ([port length] > 0) {
    config[@"port"] = @([port integerValue]);
  }
  if ([logFormat length] > 0) {
    config[@"logFormat"] = [logFormat lowercaseString];
  }

  NSNumber *trustedProxyValue = ALNParseBooleanString(trustedProxy);
  if (trustedProxyValue != nil) {
    config[@"trustedProxy"] = trustedProxyValue;
  }
  NSNumber *performanceLoggingValue = ALNParseBooleanString(performanceLogging);
  if (performanceLoggingValue != nil) {
    config[@"performanceLogging"] = performanceLoggingValue;
  }
  NSNumber *serveStaticValue = ALNParseBooleanString(serveStatic);
  if (serveStaticValue != nil) {
    config[@"serveStatic"] = serveStaticValue;
  }
  NSArray *staticAllowExtensionsValue = ALNParseCSVExtensions(staticAllowExtensions);
  if ([staticAllowExtensionsValue count] > 0) {
    config[@"staticAllowExtensions"] = staticAllowExtensionsValue;
  }
  NSNumber *apiOnlyValue = ALNParseBooleanString(apiOnly);
  if (apiOnlyValue != nil) {
    config[@"apiOnly"] = apiOnlyValue;
  }
  if ([securityProfile length] > 0) {
    config[@"securityProfile"] = ALNNormalizedSecurityProfileName(securityProfile);
  }
  NSNumber *enableReusePortValue = ALNParseBooleanString(enableReusePort);
  if (enableReusePortValue != nil) {
    config[@"enableReusePort"] = enableReusePortValue;
  }

  NSMutableDictionary *limits =
      [NSMutableDictionary dictionaryWithDictionary:config[@"requestLimits"] ?: @{}];
  ALNApplyLimitOverride(limits, maxRequestLineBytes, @"maxRequestLineBytes");
  ALNApplyLimitOverride(limits, maxHeaderBytes, @"maxHeaderBytes");
  ALNApplyLimitOverride(limits, maxBodyBytes, @"maxBodyBytes");
  config[@"requestLimits"] = limits;

  NSMutableDictionary *runtimeLimits =
      [NSMutableDictionary dictionaryWithDictionary:config[@"runtimeLimits"] ?: @{}];
  ALNApplyIntegerOverride(runtimeLimits,
                          maxWebSocketSessions,
                          @"maxConcurrentWebSocketSessions",
                          1);
  config[@"runtimeLimits"] = runtimeLimits;

  NSMutableDictionary *propaneAccessories =
      [NSMutableDictionary dictionaryWithDictionary:config[@"propaneAccessories"] ?: @{}];
  ALNApplyIntegerOverride(propaneAccessories, propaneWorkers, @"workerCount", 1);
  ALNApplyIntegerOverride(propaneAccessories,
                          propaneGracefulShutdownSeconds,
                          @"gracefulShutdownSeconds",
                          1);
  ALNApplyIntegerOverride(propaneAccessories,
                          propaneRespawnDelayMs,
                          @"respawnDelayMs",
                          0);
  ALNApplyIntegerOverride(propaneAccessories,
                          propaneReloadOverlapSeconds,
                          @"reloadOverlapSeconds",
                          0);
  config[@"propaneAccessories"] = propaneAccessories;

  NSMutableDictionary *database =
      [NSMutableDictionary dictionaryWithDictionary:config[@"database"] ?: @{}];
  if ([databaseConnectionString length] > 0) {
    database[@"connectionString"] = databaseConnectionString;
  }
  if ([databaseAdapter length] > 0) {
    database[@"adapter"] = [databaseAdapter lowercaseString];
  }
  ALNApplyIntegerOverride(database, databasePoolSize, @"poolSize", 1);
  config[@"database"] = database;

  NSMutableDictionary *session =
      [NSMutableDictionary dictionaryWithDictionary:config[@"session"] ?: @{}];
  NSNumber *sessionEnabledValue = ALNParseBooleanString(sessionEnabled);
  if (sessionEnabledValue != nil) {
    session[@"enabled"] = sessionEnabledValue;
  }
  NSNumber *sessionSecureValue = ALNParseBooleanString(sessionSecure);
  if (sessionSecureValue != nil) {
    session[@"secure"] = sessionSecureValue;
  }
  if ([sessionSecret length] > 0) {
    session[@"secret"] = sessionSecret;
  }
  if ([sessionCookieName length] > 0) {
    session[@"cookieName"] = sessionCookieName;
  }
  if ([sessionSameSite length] > 0) {
    session[@"sameSite"] = sessionSameSite;
  }
  ALNApplyIntegerOverride(session, sessionMaxAge, @"maxAgeSeconds", 1);
  config[@"session"] = session;

  NSMutableDictionary *csrf =
      [NSMutableDictionary dictionaryWithDictionary:config[@"csrf"] ?: @{}];
  NSNumber *csrfEnabledValue = ALNParseBooleanString(csrfEnabled);
  if (csrfEnabledValue != nil) {
    csrf[@"enabled"] = csrfEnabledValue;
  }
  if ([csrfHeaderName length] > 0) {
    csrf[@"headerName"] = [csrfHeaderName lowercaseString];
  }
  if ([csrfQueryParamName length] > 0) {
    csrf[@"queryParamName"] = csrfQueryParamName;
  }
  config[@"csrf"] = csrf;

  NSMutableDictionary *rateLimit =
      [NSMutableDictionary dictionaryWithDictionary:config[@"rateLimit"] ?: @{}];
  NSNumber *rateLimitEnabledValue = ALNParseBooleanString(rateLimitEnabled);
  if (rateLimitEnabledValue != nil) {
    rateLimit[@"enabled"] = rateLimitEnabledValue;
  }
  ALNApplyIntegerOverride(rateLimit, rateLimitRequests, @"requests", 1);
  ALNApplyIntegerOverride(rateLimit, rateLimitWindowSeconds, @"windowSeconds", 1);
  config[@"rateLimit"] = rateLimit;

  NSMutableDictionary *securityHeaders =
      [NSMutableDictionary dictionaryWithDictionary:config[@"securityHeaders"] ?: @{}];
  NSNumber *securityHeadersEnabledValue = ALNParseBooleanString(securityHeadersEnabled);
  if (securityHeadersEnabledValue != nil) {
    securityHeaders[@"enabled"] = securityHeadersEnabledValue;
  }
  if ([securityHeadersCSP length] > 0) {
    securityHeaders[@"contentSecurityPolicy"] = securityHeadersCSP;
  }
  config[@"securityHeaders"] = securityHeaders;

  NSMutableDictionary *auth =
      [NSMutableDictionary dictionaryWithDictionary:config[@"auth"] ?: @{}];
  NSNumber *authEnabledValue = ALNParseBooleanString(authEnabled);
  if (authEnabledValue != nil) {
    auth[@"enabled"] = authEnabledValue;
  }
  if ([authBearerSecret length] > 0) {
    auth[@"bearerSecret"] = authBearerSecret;
  }
  if ([authIssuer length] > 0) {
    auth[@"issuer"] = authIssuer;
  }
  if ([authAudience length] > 0) {
    auth[@"audience"] = authAudience;
  }
  config[@"auth"] = auth;

  NSMutableDictionary *openapi =
      [NSMutableDictionary dictionaryWithDictionary:config[@"openapi"] ?: @{}];
  NSNumber *openapiEnabledValue = ALNParseBooleanString(openapiEnabled);
  if (openapiEnabledValue != nil) {
    openapi[@"enabled"] = openapiEnabledValue;
  }
  NSNumber *openapiDocsUIEnabledValue = ALNParseBooleanString(openapiDocsUIEnabled);
  if (openapiDocsUIEnabledValue != nil) {
    openapi[@"docsUIEnabled"] = openapiDocsUIEnabledValue;
  }
  if ([openapiTitle length] > 0) {
    openapi[@"title"] = openapiTitle;
  }
  if ([openapiVersion length] > 0) {
    openapi[@"version"] = openapiVersion;
  }
  if ([openapiDocsUIStyle length] > 0) {
    openapi[@"docsUIStyle"] = [openapiDocsUIStyle lowercaseString];
  }
  config[@"openapi"] = openapi;

  NSMutableDictionary *services =
      [NSMutableDictionary dictionaryWithDictionary:config[@"services"] ?: @{}];
  NSMutableDictionary *i18n =
      [NSMutableDictionary dictionaryWithDictionary:services[@"i18n"] ?: @{}];
  if ([i18nDefaultLocale length] > 0) {
    i18n[@"defaultLocale"] = [i18nDefaultLocale lowercaseString];
  }
  if ([i18nFallbackLocale length] > 0) {
    i18n[@"fallbackLocale"] = [i18nFallbackLocale lowercaseString];
  }
  services[@"i18n"] = i18n;
  config[@"services"] = services;

  NSMutableDictionary *compatibility =
      [NSMutableDictionary dictionaryWithDictionary:config[@"compatibility"] ?: @{}];
  NSNumber *compatibilityPageStateEnabledValue =
      ALNParseBooleanString(compatibilityPageStateEnabled);
  if (compatibilityPageStateEnabledValue != nil) {
    compatibility[@"pageStateEnabled"] = compatibilityPageStateEnabledValue;
  }
  config[@"compatibility"] = compatibility;

  NSMutableDictionary *apiHelpers =
      [NSMutableDictionary dictionaryWithDictionary:config[@"apiHelpers"] ?: @{}];
  NSNumber *responseEnvelopeEnabledValue = ALNParseBooleanString(responseEnvelopeEnabled);
  if (responseEnvelopeEnabledValue != nil) {
    apiHelpers[@"responseEnvelopeEnabled"] = responseEnvelopeEnabledValue;
  }
  config[@"apiHelpers"] = apiHelpers;

  NSMutableDictionary *observability =
      [NSMutableDictionary dictionaryWithDictionary:config[@"observability"] ?: @{}];
  NSNumber *tracePropagationEnabledValue = ALNParseBooleanString(tracePropagationEnabled);
  if (tracePropagationEnabledValue != nil) {
    observability[@"tracePropagationEnabled"] = tracePropagationEnabledValue;
  }
  NSNumber *healthDetailsEnabledValue = ALNParseBooleanString(healthDetailsEnabled);
  if (healthDetailsEnabledValue != nil) {
    observability[@"healthDetailsEnabled"] = healthDetailsEnabledValue;
  }
  NSNumber *readinessRequiresStartupValue = ALNParseBooleanString(readinessRequiresStartup);
  if (readinessRequiresStartupValue != nil) {
    observability[@"readinessRequiresStartup"] = readinessRequiresStartupValue;
  }
  NSNumber *readinessRequiresClusterQuorumValue =
      ALNParseBooleanString(readinessRequiresClusterQuorum);
  if (readinessRequiresClusterQuorumValue != nil) {
    observability[@"readinessRequiresClusterQuorum"] = readinessRequiresClusterQuorumValue;
  }
  config[@"observability"] = observability;

  NSMutableDictionary *cluster =
      [NSMutableDictionary dictionaryWithDictionary:config[@"cluster"] ?: @{}];
  NSNumber *clusterEnabledValue = ALNParseBooleanString(clusterEnabled);
  if (clusterEnabledValue != nil) {
    cluster[@"enabled"] = clusterEnabledValue;
  }
  if ([clusterName length] > 0) {
    cluster[@"name"] = clusterName;
  }
  if ([clusterNodeID length] > 0) {
    cluster[@"nodeID"] = clusterNodeID;
  }
  ALNApplyIntegerOverride(cluster, clusterExpectedNodes, @"expectedNodes", 1);
  ALNApplyIntegerOverride(cluster, clusterObservedNodes, @"observedNodes", 0);
  NSNumber *clusterEmitHeadersValue = ALNParseBooleanString(clusterEmitHeaders);
  if (clusterEmitHeadersValue != nil) {
    cluster[@"emitHeaders"] = clusterEmitHeadersValue;
  }
  config[@"cluster"] = cluster;

  NSMutableDictionary *eoc =
      [NSMutableDictionary dictionaryWithDictionary:config[@"eoc"] ?: @{}];
  NSNumber *eocStrictLocalsValue = ALNParseBooleanString(eocStrictLocals);
  if (eocStrictLocalsValue != nil) {
    eoc[@"strictLocals"] = eocStrictLocalsValue;
  }
  NSNumber *eocStrictStringifyValue = ALNParseBooleanString(eocStrictStringify);
  if (eocStrictStringifyValue != nil) {
    eoc[@"strictStringify"] = eocStrictStringifyValue;
  }
  config[@"eoc"] = eoc;

  NSMutableDictionary *topLevel = [NSMutableDictionary dictionaryWithDictionary:config];
  ALNApplyIntegerOverride(topLevel, listenBacklog, @"listenBacklog", 1);
  ALNApplyIntegerOverride(topLevel,
                          connectionTimeoutSeconds,
                          @"connectionTimeoutSeconds",
                          1);
  config = topLevel;

  if (config[@"host"] == nil) {
    config[@"host"] = @"127.0.0.1";
  }
  if (config[@"apiOnly"] == nil) {
    config[@"apiOnly"] = @(NO);
  }
  BOOL apiOnlyMode = [config[@"apiOnly"] boolValue];
  if (config[@"port"] == nil) {
    config[@"port"] = @(3000);
  }
  if (config[@"logFormat"] == nil) {
    config[@"logFormat"] =
        (apiOnlyMode || ![env isEqualToString:@"development"]) ? @"json" : @"text";
  }
  NSString *securityProfileName = ALNNormalizedSecurityProfileName(config[@"securityProfile"]);
  NSDictionary *securityProfileDefaults = ALNSecurityProfileDefaults(securityProfileName);
  config[@"securityProfile"] = securityProfileName;

  NSMutableDictionary *finalLimits =
      [NSMutableDictionary dictionaryWithDictionary:config[@"requestLimits"] ?: @{}];
  if (finalLimits[@"maxRequestLineBytes"] == nil) {
    finalLimits[@"maxRequestLineBytes"] = @(4096);
  }
  if (finalLimits[@"maxHeaderBytes"] == nil) {
    finalLimits[@"maxHeaderBytes"] = @(32768);
  }
  if (finalLimits[@"maxBodyBytes"] == nil) {
    finalLimits[@"maxBodyBytes"] = @(1048576);
  }
  config[@"requestLimits"] = finalLimits;

  NSMutableDictionary *finalRuntimeLimits =
      [NSMutableDictionary dictionaryWithDictionary:config[@"runtimeLimits"] ?: @{}];
  if (finalRuntimeLimits[@"maxConcurrentWebSocketSessions"] == nil) {
    finalRuntimeLimits[@"maxConcurrentWebSocketSessions"] = @(256);
  }
  config[@"runtimeLimits"] = finalRuntimeLimits;

  if (config[@"trustedProxy"] == nil) {
    config[@"trustedProxy"] = securityProfileDefaults[@"trustedProxy"] ?: @(NO);
  }
  if (config[@"performanceLogging"] == nil) {
    config[@"performanceLogging"] = @(YES);
  }
  if (config[@"serveStatic"] == nil) {
    config[@"serveStatic"] = @([env isEqualToString:@"development"] && !apiOnlyMode);
  }
  NSArray *defaultStaticAllowExtensions = @[
    @"css", @"js",   @"json", @"txt",  @"html", @"htm", @"svg",
    @"png", @"jpg",  @"jpeg", @"gif",  @"ico",  @"webp", @"woff",
    @"woff2", @"map", @"xml"
  ];
  NSArray *configuredStaticAllowExtensions =
      [config[@"staticAllowExtensions"] isKindOfClass:[NSArray class]]
          ? ALNNormalizeExtensionList(config[@"staticAllowExtensions"])
          : @[];
  if ([configuredStaticAllowExtensions count] == 0) {
    config[@"staticAllowExtensions"] = defaultStaticAllowExtensions;
  } else {
    config[@"staticAllowExtensions"] = configuredStaticAllowExtensions;
  }
  if (config[@"listenBacklog"] == nil) {
    config[@"listenBacklog"] = @(128);
  }
  if (config[@"connectionTimeoutSeconds"] == nil) {
    config[@"connectionTimeoutSeconds"] = @(30);
  }
  if (config[@"enableReusePort"] == nil) {
    config[@"enableReusePort"] = @(NO);
  }

  NSMutableDictionary *finalAccessories =
      [NSMutableDictionary dictionaryWithDictionary:config[@"propaneAccessories"] ?: @{}];
  if (finalAccessories[@"workerCount"] == nil) {
    finalAccessories[@"workerCount"] = @(4);
  }
  if (finalAccessories[@"gracefulShutdownSeconds"] == nil) {
    finalAccessories[@"gracefulShutdownSeconds"] = @(10);
  }
  if (finalAccessories[@"respawnDelayMs"] == nil) {
    finalAccessories[@"respawnDelayMs"] = @(250);
  }
  if (finalAccessories[@"reloadOverlapSeconds"] == nil) {
    finalAccessories[@"reloadOverlapSeconds"] = @(1);
  }
  config[@"propaneAccessories"] = finalAccessories;

  NSMutableDictionary *finalDatabase =
      [NSMutableDictionary dictionaryWithDictionary:config[@"database"] ?: @{}];
  if (finalDatabase[@"poolSize"] == nil) {
    finalDatabase[@"poolSize"] = @(8);
  }
  if (![finalDatabase[@"adapter"] isKindOfClass:[NSString class]] ||
      [finalDatabase[@"adapter"] length] == 0) {
    finalDatabase[@"adapter"] = @"postgresql";
  }
  config[@"database"] = finalDatabase;

  NSMutableDictionary *finalSession =
      [NSMutableDictionary dictionaryWithDictionary:config[@"session"] ?: @{}];
  if (finalSession[@"enabled"] == nil) {
    finalSession[@"enabled"] = securityProfileDefaults[@"sessionEnabled"] ?: @(NO);
  }
  if (finalSession[@"cookieName"] == nil) {
    finalSession[@"cookieName"] = @"arlen_session";
  }
  if (finalSession[@"maxAgeSeconds"] == nil) {
    finalSession[@"maxAgeSeconds"] = @(1209600);
  }
  if (finalSession[@"secure"] == nil) {
    finalSession[@"secure"] = @([env isEqualToString:@"production"]);
  }
  if (finalSession[@"sameSite"] == nil) {
    finalSession[@"sameSite"] = @"Lax";
  }
  config[@"session"] = finalSession;

  NSMutableDictionary *finalCSRF =
      [NSMutableDictionary dictionaryWithDictionary:config[@"csrf"] ?: @{}];
  if (finalCSRF[@"enabled"] == nil) {
    finalCSRF[@"enabled"] = securityProfileDefaults[@"csrfEnabled"] ?: @([finalSession[@"enabled"] boolValue]);
  }
  if (finalCSRF[@"headerName"] == nil) {
    finalCSRF[@"headerName"] = @"x-csrf-token";
  }
  if (finalCSRF[@"queryParamName"] == nil) {
    finalCSRF[@"queryParamName"] = @"csrf_token";
  }
  config[@"csrf"] = finalCSRF;

  NSMutableDictionary *finalRateLimit =
      [NSMutableDictionary dictionaryWithDictionary:config[@"rateLimit"] ?: @{}];
  if (finalRateLimit[@"enabled"] == nil) {
    finalRateLimit[@"enabled"] = @(NO);
  }
  if (finalRateLimit[@"requests"] == nil) {
    finalRateLimit[@"requests"] = @(120);
  }
  if (finalRateLimit[@"windowSeconds"] == nil) {
    finalRateLimit[@"windowSeconds"] = @(60);
  }
  config[@"rateLimit"] = finalRateLimit;

  NSMutableDictionary *finalSecurityHeaders =
      [NSMutableDictionary dictionaryWithDictionary:config[@"securityHeaders"] ?: @{}];
  if (finalSecurityHeaders[@"enabled"] == nil) {
    finalSecurityHeaders[@"enabled"] = securityProfileDefaults[@"securityHeadersEnabled"] ?: @(YES);
  }
  if (finalSecurityHeaders[@"contentSecurityPolicy"] == nil) {
    finalSecurityHeaders[@"contentSecurityPolicy"] = @"default-src 'self'";
  }
  config[@"securityHeaders"] = finalSecurityHeaders;

  NSMutableDictionary *finalAuth =
      [NSMutableDictionary dictionaryWithDictionary:config[@"auth"] ?: @{}];
  if (finalAuth[@"enabled"] == nil) {
    finalAuth[@"enabled"] = @(NO);
  }
  if (finalAuth[@"bearerSecret"] == nil) {
    finalAuth[@"bearerSecret"] = @"";
  }
  if (finalAuth[@"issuer"] == nil) {
    finalAuth[@"issuer"] = @"";
  }
  if (finalAuth[@"audience"] == nil) {
    finalAuth[@"audience"] = @"";
  }
  config[@"auth"] = finalAuth;

  NSMutableDictionary *finalOpenAPI =
      [NSMutableDictionary dictionaryWithDictionary:config[@"openapi"] ?: @{}];
  if (finalOpenAPI[@"enabled"] == nil) {
    finalOpenAPI[@"enabled"] = @(YES);
  }
  if (finalOpenAPI[@"docsUIEnabled"] == nil) {
    finalOpenAPI[@"docsUIEnabled"] = @(![env isEqualToString:@"production"]);
  }
  if (finalOpenAPI[@"title"] == nil) {
    finalOpenAPI[@"title"] = @"Arlen API";
  }
  if (finalOpenAPI[@"version"] == nil) {
    finalOpenAPI[@"version"] = @"0.1.0";
  }
  if (finalOpenAPI[@"description"] == nil) {
    finalOpenAPI[@"description"] = @"Generated by Arlen";
  }
  if (![finalOpenAPI[@"docsUIStyle"] isKindOfClass:[NSString class]] ||
      [finalOpenAPI[@"docsUIStyle"] length] == 0) {
    finalOpenAPI[@"docsUIStyle"] = @"interactive";
  }
  config[@"openapi"] = finalOpenAPI;

  NSMutableDictionary *finalServices =
      [NSMutableDictionary dictionaryWithDictionary:config[@"services"] ?: @{}];
  NSMutableDictionary *finalI18n =
      [NSMutableDictionary dictionaryWithDictionary:finalServices[@"i18n"] ?: @{}];
  if (![finalI18n[@"defaultLocale"] isKindOfClass:[NSString class]] ||
      [finalI18n[@"defaultLocale"] length] == 0) {
    finalI18n[@"defaultLocale"] = @"en";
  }
  if (![finalI18n[@"fallbackLocale"] isKindOfClass:[NSString class]] ||
      [finalI18n[@"fallbackLocale"] length] == 0) {
    finalI18n[@"fallbackLocale"] = finalI18n[@"defaultLocale"];
  }
  finalServices[@"i18n"] = finalI18n;
  config[@"services"] = finalServices;

  NSMutableDictionary *finalPlugins =
      [NSMutableDictionary dictionaryWithDictionary:config[@"plugins"] ?: @{}];
  if (![finalPlugins[@"classes"] isKindOfClass:[NSArray class]]) {
    finalPlugins[@"classes"] = @[];
  }
  config[@"plugins"] = finalPlugins;

  NSMutableDictionary *finalEOC =
      [NSMutableDictionary dictionaryWithDictionary:config[@"eoc"] ?: @{}];
  if (finalEOC[@"strictLocals"] == nil) {
    finalEOC[@"strictLocals"] = @(NO);
  }
  if (finalEOC[@"strictStringify"] == nil) {
    finalEOC[@"strictStringify"] = @(NO);
  }
  config[@"eoc"] = finalEOC;

  NSMutableDictionary *finalCompatibility =
      [NSMutableDictionary dictionaryWithDictionary:config[@"compatibility"] ?: @{}];
  if (finalCompatibility[@"pageStateEnabled"] == nil) {
    finalCompatibility[@"pageStateEnabled"] = @(NO);
  }
  config[@"compatibility"] = finalCompatibility;

  NSMutableDictionary *finalAPIHelpers =
      [NSMutableDictionary dictionaryWithDictionary:config[@"apiHelpers"] ?: @{}];
  if (finalAPIHelpers[@"responseEnvelopeEnabled"] == nil) {
    finalAPIHelpers[@"responseEnvelopeEnabled"] = @(NO);
  }
  config[@"apiHelpers"] = finalAPIHelpers;

  NSMutableDictionary *finalObservability =
      [NSMutableDictionary dictionaryWithDictionary:config[@"observability"] ?: @{}];
  if (finalObservability[@"tracePropagationEnabled"] == nil) {
    finalObservability[@"tracePropagationEnabled"] = @(YES);
  }
  if (finalObservability[@"healthDetailsEnabled"] == nil) {
    finalObservability[@"healthDetailsEnabled"] = @(YES);
  }
  if (finalObservability[@"readinessRequiresStartup"] == nil) {
    finalObservability[@"readinessRequiresStartup"] = @(NO);
  }
  if (finalObservability[@"readinessRequiresClusterQuorum"] == nil) {
    finalObservability[@"readinessRequiresClusterQuorum"] = @(NO);
  }
  config[@"observability"] = finalObservability;

  NSMutableDictionary *finalCluster =
      [NSMutableDictionary dictionaryWithDictionary:config[@"cluster"] ?: @{}];
  if (finalCluster[@"enabled"] == nil) {
    finalCluster[@"enabled"] = @(NO);
  }
  if (![finalCluster[@"name"] isKindOfClass:[NSString class]] ||
      [finalCluster[@"name"] length] == 0) {
    finalCluster[@"name"] = @"default";
  }
  if (![finalCluster[@"nodeID"] isKindOfClass:[NSString class]] ||
      [finalCluster[@"nodeID"] length] == 0) {
    finalCluster[@"nodeID"] = ALNDefaultClusterNodeID();
  }
  if (finalCluster[@"expectedNodes"] == nil) {
    finalCluster[@"expectedNodes"] = @(1);
  }
  if (finalCluster[@"observedNodes"] == nil) {
    NSInteger expectedNodesDefault =
        [finalCluster[@"expectedNodes"] respondsToSelector:@selector(integerValue)]
            ? [finalCluster[@"expectedNodes"] integerValue]
            : 1;
    if (expectedNodesDefault < 1) {
      expectedNodesDefault = 1;
    }
    finalCluster[@"observedNodes"] = @(expectedNodesDefault);
  }
  if (finalCluster[@"emitHeaders"] == nil) {
    finalCluster[@"emitHeaders"] = @(YES);
  }
  config[@"cluster"] = finalCluster;

  config[@"port"] = @([config[@"port"] integerValue]);
  config[@"apiOnly"] = @([config[@"apiOnly"] boolValue]);
  config[@"securityProfile"] = ALNNormalizedSecurityProfileName(config[@"securityProfile"]);
  config[@"trustedProxy"] = @([config[@"trustedProxy"] boolValue]);
  config[@"performanceLogging"] = @([config[@"performanceLogging"] boolValue]);
  config[@"serveStatic"] = @([config[@"serveStatic"] boolValue]);
  NSArray *normalizedStaticAllowExtensions =
      ALNNormalizeExtensionList([config[@"staticAllowExtensions"] isKindOfClass:[NSArray class]]
                                    ? config[@"staticAllowExtensions"]
                                    : @[]);
  if ([normalizedStaticAllowExtensions count] == 0) {
    normalizedStaticAllowExtensions = @[
      @"css", @"js",   @"json", @"txt",  @"html", @"htm", @"svg",
      @"png", @"jpg",  @"jpeg", @"gif",  @"ico",  @"webp", @"woff",
      @"woff2", @"map", @"xml"
    ];
  }
  config[@"staticAllowExtensions"] = normalizedStaticAllowExtensions;
  config[@"listenBacklog"] = @([config[@"listenBacklog"] integerValue]);
  config[@"connectionTimeoutSeconds"] = @([config[@"connectionTimeoutSeconds"] integerValue]);
  config[@"enableReusePort"] = @([config[@"enableReusePort"] boolValue]);

  finalLimits[@"maxRequestLineBytes"] = @([finalLimits[@"maxRequestLineBytes"] integerValue]);
  finalLimits[@"maxHeaderBytes"] = @([finalLimits[@"maxHeaderBytes"] integerValue]);
  finalLimits[@"maxBodyBytes"] = @([finalLimits[@"maxBodyBytes"] integerValue]);
  config[@"requestLimits"] = finalLimits;

  finalRuntimeLimits[@"maxConcurrentWebSocketSessions"] =
      @([finalRuntimeLimits[@"maxConcurrentWebSocketSessions"] integerValue]);
  config[@"runtimeLimits"] = finalRuntimeLimits;

  finalAccessories[@"workerCount"] = @([finalAccessories[@"workerCount"] integerValue]);
  finalAccessories[@"gracefulShutdownSeconds"] =
      @([finalAccessories[@"gracefulShutdownSeconds"] integerValue]);
  finalAccessories[@"respawnDelayMs"] = @([finalAccessories[@"respawnDelayMs"] integerValue]);
  finalAccessories[@"reloadOverlapSeconds"] =
      @([finalAccessories[@"reloadOverlapSeconds"] integerValue]);
  config[@"propaneAccessories"] = finalAccessories;

  finalDatabase[@"poolSize"] = @([finalDatabase[@"poolSize"] integerValue]);
  if (![finalDatabase[@"adapter"] isKindOfClass:[NSString class]] ||
      [finalDatabase[@"adapter"] length] == 0) {
    finalDatabase[@"adapter"] = @"postgresql";
  } else {
    finalDatabase[@"adapter"] = [finalDatabase[@"adapter"] lowercaseString];
  }
  config[@"database"] = finalDatabase;

  finalSession[@"enabled"] = @([finalSession[@"enabled"] boolValue]);
  finalSession[@"maxAgeSeconds"] = @([finalSession[@"maxAgeSeconds"] integerValue]);
  finalSession[@"secure"] = @([finalSession[@"secure"] boolValue]);
  config[@"session"] = finalSession;

  finalCSRF[@"enabled"] = @([finalCSRF[@"enabled"] boolValue]);
  if ([finalCSRF[@"headerName"] isKindOfClass:[NSString class]]) {
    finalCSRF[@"headerName"] = [finalCSRF[@"headerName"] lowercaseString];
  }
  config[@"csrf"] = finalCSRF;

  finalRateLimit[@"enabled"] = @([finalRateLimit[@"enabled"] boolValue]);
  finalRateLimit[@"requests"] = @([finalRateLimit[@"requests"] integerValue]);
  finalRateLimit[@"windowSeconds"] = @([finalRateLimit[@"windowSeconds"] integerValue]);
  config[@"rateLimit"] = finalRateLimit;

  finalSecurityHeaders[@"enabled"] = @([finalSecurityHeaders[@"enabled"] boolValue]);
  config[@"securityHeaders"] = finalSecurityHeaders;

  finalAuth[@"enabled"] = @([finalAuth[@"enabled"] boolValue]);
  if (![finalAuth[@"bearerSecret"] isKindOfClass:[NSString class]]) {
    finalAuth[@"bearerSecret"] = @"";
  }
  if (![finalAuth[@"issuer"] isKindOfClass:[NSString class]]) {
    finalAuth[@"issuer"] = @"";
  }
  if (![finalAuth[@"audience"] isKindOfClass:[NSString class]]) {
    finalAuth[@"audience"] = @"";
  }
  config[@"auth"] = finalAuth;

  finalOpenAPI[@"enabled"] = @([finalOpenAPI[@"enabled"] boolValue]);
  finalOpenAPI[@"docsUIEnabled"] = @([finalOpenAPI[@"docsUIEnabled"] boolValue]);
  if (![finalOpenAPI[@"title"] isKindOfClass:[NSString class]]) {
    finalOpenAPI[@"title"] = @"Arlen API";
  }
  if (![finalOpenAPI[@"version"] isKindOfClass:[NSString class]]) {
    finalOpenAPI[@"version"] = @"0.1.0";
  }
  if (![finalOpenAPI[@"description"] isKindOfClass:[NSString class]]) {
    finalOpenAPI[@"description"] = @"Generated by Arlen";
  }
  NSString *docsStyle = [finalOpenAPI[@"docsUIStyle"] isKindOfClass:[NSString class]]
                            ? [finalOpenAPI[@"docsUIStyle"] lowercaseString]
                            : @"interactive";
  if (![docsStyle isEqualToString:@"interactive"] &&
      ![docsStyle isEqualToString:@"viewer"] &&
      ![docsStyle isEqualToString:@"swagger"]) {
    docsStyle = @"interactive";
  }
  finalOpenAPI[@"docsUIStyle"] = docsStyle;
  config[@"openapi"] = finalOpenAPI;

  NSMutableDictionary *normalizedI18n =
      [NSMutableDictionary dictionaryWithDictionary:finalServices[@"i18n"] ?: @{}];
  NSString *defaultLocale = [normalizedI18n[@"defaultLocale"] isKindOfClass:[NSString class]]
                                ? [normalizedI18n[@"defaultLocale"] lowercaseString]
                                : @"en";
  if ([defaultLocale length] == 0) {
    defaultLocale = @"en";
  }
  NSString *fallbackLocale = [normalizedI18n[@"fallbackLocale"] isKindOfClass:[NSString class]]
                                 ? [normalizedI18n[@"fallbackLocale"] lowercaseString]
                                 : defaultLocale;
  if ([fallbackLocale length] == 0) {
    fallbackLocale = defaultLocale;
  }
  normalizedI18n[@"defaultLocale"] = defaultLocale;
  normalizedI18n[@"fallbackLocale"] = fallbackLocale;
  finalServices[@"i18n"] = normalizedI18n;
  config[@"services"] = finalServices;

  if (![finalPlugins[@"classes"] isKindOfClass:[NSArray class]]) {
    finalPlugins[@"classes"] = @[];
  }
  config[@"plugins"] = finalPlugins;

  finalEOC[@"strictLocals"] = @([finalEOC[@"strictLocals"] boolValue]);
  finalEOC[@"strictStringify"] = @([finalEOC[@"strictStringify"] boolValue]);
  config[@"eoc"] = finalEOC;

  finalCompatibility[@"pageStateEnabled"] =
      @([finalCompatibility[@"pageStateEnabled"] boolValue]);
  config[@"compatibility"] = finalCompatibility;

  finalAPIHelpers[@"responseEnvelopeEnabled"] =
      @([finalAPIHelpers[@"responseEnvelopeEnabled"] boolValue]);
  config[@"apiHelpers"] = finalAPIHelpers;

  finalObservability[@"tracePropagationEnabled"] =
      @([finalObservability[@"tracePropagationEnabled"] boolValue]);
  finalObservability[@"healthDetailsEnabled"] =
      @([finalObservability[@"healthDetailsEnabled"] boolValue]);
  finalObservability[@"readinessRequiresStartup"] =
      @([finalObservability[@"readinessRequiresStartup"] boolValue]);
  finalObservability[@"readinessRequiresClusterQuorum"] =
      @([finalObservability[@"readinessRequiresClusterQuorum"] boolValue]);
  config[@"observability"] = finalObservability;

  finalCluster[@"enabled"] = @([finalCluster[@"enabled"] boolValue]);
  NSInteger expectedNodes = [finalCluster[@"expectedNodes"] integerValue];
  if (expectedNodes < 1) {
    expectedNodes = 1;
  }
  finalCluster[@"expectedNodes"] = @(expectedNodes);
  NSInteger observedNodes = [finalCluster[@"observedNodes"] integerValue];
  if (observedNodes < 0) {
    observedNodes = 0;
  }
  finalCluster[@"observedNodes"] = @(observedNodes);
  finalCluster[@"emitHeaders"] = @([finalCluster[@"emitHeaders"] boolValue]);
  NSString *normalizedClusterName =
      [finalCluster[@"name"] isKindOfClass:[NSString class]] ? finalCluster[@"name"] : @"default";
  normalizedClusterName =
      [normalizedClusterName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalizedClusterName length] == 0) {
    normalizedClusterName = @"default";
  }
  finalCluster[@"name"] = normalizedClusterName;
  NSString *normalizedNodeID =
      [finalCluster[@"nodeID"] isKindOfClass:[NSString class]]
          ? finalCluster[@"nodeID"]
          : ALNDefaultClusterNodeID();
  normalizedNodeID =
      [normalizedNodeID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalizedNodeID length] == 0) {
    normalizedNodeID = ALNDefaultClusterNodeID();
  }
  finalCluster[@"nodeID"] = normalizedNodeID;
  config[@"cluster"] = finalCluster;

  return [NSDictionary dictionaryWithDictionary:config];
}

@end
