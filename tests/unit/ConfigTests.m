#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <stdlib.h>
#import <string.h>

#import "ALNConfig.h"

@interface ConfigTests : XCTestCase
@end

@implementation ConfigTests

- (NSString *)createTempAppRoot {
  NSString *templatePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"arlen-config-XXXXXX"];
  const char *templateCString = [templatePath fileSystemRepresentation];
  char *buffer = strdup(templateCString);
  char *created = mkdtemp(buffer);
  NSString *result = created ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:created
                                                                                             length:strlen(created)]
                             : nil;
  free(buffer);
  return result;
}

- (BOOL)writeFile:(NSString *)path content:(NSString *)content {
  NSString *dir = [path stringByDeletingLastPathComponent];
  NSError *error = nil;
  BOOL ok = [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error];
  if (!ok) {
    XCTFail(@"Failed creating directory %@: %@", dir, error.localizedDescription);
    return NO;
  }

  ok = [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
  if (!ok) {
    XCTFail(@"Failed writing file %@: %@", path, error.localizedDescription);
  }
  return ok;
}

- (NSString *)prepareConfigTree {
  NSString *root = [self createTempAppRoot];
  XCTAssertNotNil(root);
  if (root == nil) {
    return nil;
  }

  NSString *appPlist =
      [root stringByAppendingPathComponent:@"config/app.plist"];
  NSString *developmentPlist =
      [root stringByAppendingPathComponent:@"config/environments/development.plist"];

  BOOL ok = YES;
  ok = ok && [self writeFile:appPlist
                     content:@"{\n"
                              "  host = \"127.0.0.1\";\n"
                              "  port = 3000;\n"
                              "  requestLimits = {\n"
                              "    maxRequestLineBytes = 2048;\n"
                              "    maxHeaderBytes = 16384;\n"
                              "    maxBodyBytes = 65536;\n"
                              "  };\n"
                              "}\n"];
  ok = ok && [self writeFile:developmentPlist
                     content:@"{\n"
                              "  logFormat = \"text\";\n"
                              "}\n"];
  XCTAssertTrue(ok);
  return root;
}

- (void)testLoadConfigMergesAndAppliesDefaults {
  NSString *root = [self prepareConfigTree];
  XCTAssertNotNil(root);

  NSError *error = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:root
                                         environment:@"development"
                                               error:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(@"127.0.0.1", config[@"host"]);
  XCTAssertEqual((NSInteger)3000, [config[@"port"] integerValue]);
  XCTAssertEqualObjects(@"text", config[@"logFormat"]);
  XCTAssertEqualObjects(@"development", config[@"environment"]);
  XCTAssertEqualObjects(@(NO), config[@"trustedProxy"]);
  XCTAssertEqualObjects(@(YES), config[@"serveStatic"]);
  XCTAssertEqual((NSInteger)128, [config[@"listenBacklog"] integerValue]);
  XCTAssertEqual((NSInteger)30, [config[@"connectionTimeoutSeconds"] integerValue]);
  XCTAssertEqualObjects(@(NO), config[@"enableReusePort"]);

  NSDictionary *accessories = config[@"propaneAccessories"];
  XCTAssertEqual((NSInteger)4, [accessories[@"workerCount"] integerValue]);
  XCTAssertEqual((NSInteger)10, [accessories[@"gracefulShutdownSeconds"] integerValue]);
  XCTAssertEqual((NSInteger)250, [accessories[@"respawnDelayMs"] integerValue]);
  XCTAssertEqual((NSInteger)1, [accessories[@"reloadOverlapSeconds"] integerValue]);

  NSDictionary *database = config[@"database"];
  XCTAssertEqual((NSInteger)8, [database[@"poolSize"] integerValue]);
  XCTAssertEqualObjects(@"postgresql", database[@"adapter"]);

  NSDictionary *session = config[@"session"];
  XCTAssertEqualObjects(@(NO), session[@"enabled"]);
  XCTAssertEqualObjects(@"arlen_session", session[@"cookieName"]);
  XCTAssertEqual((NSInteger)1209600, [session[@"maxAgeSeconds"] integerValue]);
  XCTAssertEqualObjects(@(NO), session[@"secure"]);
  XCTAssertEqualObjects(@"Lax", session[@"sameSite"]);

  NSDictionary *csrf = config[@"csrf"];
  XCTAssertEqualObjects(@(NO), csrf[@"enabled"]);
  XCTAssertEqualObjects(@"x-csrf-token", csrf[@"headerName"]);
  XCTAssertEqualObjects(@"csrf_token", csrf[@"queryParamName"]);

  NSDictionary *rateLimit = config[@"rateLimit"];
  XCTAssertEqualObjects(@(NO), rateLimit[@"enabled"]);
  XCTAssertEqual((NSInteger)120, [rateLimit[@"requests"] integerValue]);
  XCTAssertEqual((NSInteger)60, [rateLimit[@"windowSeconds"] integerValue]);

  NSDictionary *securityHeaders = config[@"securityHeaders"];
  XCTAssertEqualObjects(@(YES), securityHeaders[@"enabled"]);
  XCTAssertEqualObjects(@"default-src 'self'",
                        securityHeaders[@"contentSecurityPolicy"]);

  NSDictionary *auth = config[@"auth"];
  XCTAssertEqualObjects(@(NO), auth[@"enabled"]);
  XCTAssertEqualObjects(@"", auth[@"bearerSecret"]);
  XCTAssertEqualObjects(@"", auth[@"issuer"]);
  XCTAssertEqualObjects(@"", auth[@"audience"]);

  NSDictionary *openapi = config[@"openapi"];
  XCTAssertEqualObjects(@(YES), openapi[@"enabled"]);
  XCTAssertEqualObjects(@(YES), openapi[@"docsUIEnabled"]);
  XCTAssertEqualObjects(@"interactive", openapi[@"docsUIStyle"]);
  XCTAssertEqualObjects(@"Arlen API", openapi[@"title"]);
  XCTAssertEqualObjects(@"0.1.0", openapi[@"version"]);

  NSDictionary *compatibility = config[@"compatibility"];
  XCTAssertEqualObjects(@(NO), compatibility[@"pageStateEnabled"]);

  NSDictionary *services = config[@"services"];
  NSDictionary *i18n = services[@"i18n"];
  XCTAssertEqualObjects(@"en", i18n[@"defaultLocale"]);
  XCTAssertEqualObjects(@"en", i18n[@"fallbackLocale"]);

  NSDictionary *plugins = config[@"plugins"];
  XCTAssertTrue([plugins[@"classes"] isKindOfClass:[NSArray class]]);
  XCTAssertEqual((NSUInteger)0, [plugins[@"classes"] count]);

  NSDictionary *limits = config[@"requestLimits"];
  XCTAssertEqual((NSInteger)2048, [limits[@"maxRequestLineBytes"] integerValue]);
  XCTAssertEqual((NSInteger)16384, [limits[@"maxHeaderBytes"] integerValue]);
  XCTAssertEqual((NSInteger)65536, [limits[@"maxBodyBytes"] integerValue]);
}

- (void)testEnvironmentOverridesRequestLimitsAndProxyFlags {
  NSString *root = [self prepareConfigTree];
  XCTAssertNotNil(root);

  setenv("ARLEN_MAX_REQUEST_LINE_BYTES", "111", 1);
  setenv("ARLEN_MAX_HEADER_BYTES", "222", 1);
  setenv("ARLEN_MAX_BODY_BYTES", "333", 1);
  setenv("ARLEN_TRUSTED_PROXY", "true", 1);
  setenv("ARLEN_SERVE_STATIC", "0", 1);
  setenv("ARLEN_LISTEN_BACKLOG", "2222", 1);
  setenv("ARLEN_CONNECTION_TIMEOUT_SECONDS", "45", 1);
  setenv("ARLEN_ENABLE_REUSEPORT", "true", 1);
  setenv("ARLEN_PROPANE_WORKERS", "7", 1);
  setenv("ARLEN_PROPANE_GRACEFUL_SHUTDOWN_SECONDS", "12", 1);
  setenv("ARLEN_PROPANE_RESPAWN_DELAY_MS", "555", 1);
  setenv("ARLEN_PROPANE_RELOAD_OVERLAP_SECONDS", "3", 1);
  setenv("ARLEN_DATABASE_URL", "postgresql://localhost/arlen_test", 1);
  setenv("ARLEN_DB_POOL_SIZE", "11", 1);
  setenv("ARLEN_DB_ADAPTER", "gdl2", 1);
  setenv("ARLEN_SESSION_ENABLED", "1", 1);
  setenv("ARLEN_SESSION_SECRET", "super-secret", 1);
  setenv("ARLEN_SESSION_COOKIE_NAME", "sid", 1);
  setenv("ARLEN_SESSION_MAX_AGE_SECONDS", "777", 1);
  setenv("ARLEN_SESSION_SECURE", "1", 1);
  setenv("ARLEN_SESSION_SAMESITE", "Strict", 1);
  setenv("ARLEN_CSRF_ENABLED", "1", 1);
  setenv("ARLEN_CSRF_HEADER_NAME", "x-my-csrf", 1);
  setenv("ARLEN_CSRF_QUERY_PARAM_NAME", "_csrf", 1);
  setenv("ARLEN_RATE_LIMIT_ENABLED", "1", 1);
  setenv("ARLEN_RATE_LIMIT_REQUESTS", "42", 1);
  setenv("ARLEN_RATE_LIMIT_WINDOW_SECONDS", "7", 1);
  setenv("ARLEN_SECURITY_HEADERS_ENABLED", "0", 1);
  setenv("ARLEN_CONTENT_SECURITY_POLICY", "default-src 'none'", 1);
  setenv("ARLEN_AUTH_ENABLED", "1", 1);
  setenv("ARLEN_AUTH_BEARER_SECRET", "jwt-secret", 1);
  setenv("ARLEN_AUTH_ISSUER", "issuer-a", 1);
  setenv("ARLEN_AUTH_AUDIENCE", "audience-a", 1);
  setenv("ARLEN_OPENAPI_ENABLED", "0", 1);
  setenv("ARLEN_OPENAPI_DOCS_UI_ENABLED", "0", 1);
  setenv("ARLEN_OPENAPI_DOCS_UI_STYLE", "viewer", 1);
  setenv("ARLEN_OPENAPI_TITLE", "Custom API", 1);
  setenv("ARLEN_OPENAPI_VERSION", "9.9.9", 1);
  setenv("ARLEN_I18N_DEFAULT_LOCALE", "es", 1);
  setenv("ARLEN_I18N_FALLBACK_LOCALE", "en", 1);
  setenv("ARLEN_PAGE_STATE_COMPAT_ENABLED", "1", 1);

  NSError *error = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:root
                                         environment:@"development"
                                               error:&error];

  unsetenv("ARLEN_MAX_REQUEST_LINE_BYTES");
  unsetenv("ARLEN_MAX_HEADER_BYTES");
  unsetenv("ARLEN_MAX_BODY_BYTES");
  unsetenv("ARLEN_TRUSTED_PROXY");
  unsetenv("ARLEN_SERVE_STATIC");
  unsetenv("ARLEN_LISTEN_BACKLOG");
  unsetenv("ARLEN_CONNECTION_TIMEOUT_SECONDS");
  unsetenv("ARLEN_ENABLE_REUSEPORT");
  unsetenv("ARLEN_PROPANE_WORKERS");
  unsetenv("ARLEN_PROPANE_GRACEFUL_SHUTDOWN_SECONDS");
  unsetenv("ARLEN_PROPANE_RESPAWN_DELAY_MS");
  unsetenv("ARLEN_PROPANE_RELOAD_OVERLAP_SECONDS");
  unsetenv("ARLEN_DATABASE_URL");
  unsetenv("ARLEN_DB_POOL_SIZE");
  unsetenv("ARLEN_DB_ADAPTER");
  unsetenv("ARLEN_SESSION_ENABLED");
  unsetenv("ARLEN_SESSION_SECRET");
  unsetenv("ARLEN_SESSION_COOKIE_NAME");
  unsetenv("ARLEN_SESSION_MAX_AGE_SECONDS");
  unsetenv("ARLEN_SESSION_SECURE");
  unsetenv("ARLEN_SESSION_SAMESITE");
  unsetenv("ARLEN_CSRF_ENABLED");
  unsetenv("ARLEN_CSRF_HEADER_NAME");
  unsetenv("ARLEN_CSRF_QUERY_PARAM_NAME");
  unsetenv("ARLEN_RATE_LIMIT_ENABLED");
  unsetenv("ARLEN_RATE_LIMIT_REQUESTS");
  unsetenv("ARLEN_RATE_LIMIT_WINDOW_SECONDS");
  unsetenv("ARLEN_SECURITY_HEADERS_ENABLED");
  unsetenv("ARLEN_CONTENT_SECURITY_POLICY");
  unsetenv("ARLEN_AUTH_ENABLED");
  unsetenv("ARLEN_AUTH_BEARER_SECRET");
  unsetenv("ARLEN_AUTH_ISSUER");
  unsetenv("ARLEN_AUTH_AUDIENCE");
  unsetenv("ARLEN_OPENAPI_ENABLED");
  unsetenv("ARLEN_OPENAPI_DOCS_UI_ENABLED");
  unsetenv("ARLEN_OPENAPI_DOCS_UI_STYLE");
  unsetenv("ARLEN_OPENAPI_TITLE");
  unsetenv("ARLEN_OPENAPI_VERSION");
  unsetenv("ARLEN_I18N_DEFAULT_LOCALE");
  unsetenv("ARLEN_I18N_FALLBACK_LOCALE");
  unsetenv("ARLEN_PAGE_STATE_COMPAT_ENABLED");

  XCTAssertNil(error);
  NSDictionary *limits = config[@"requestLimits"];
  XCTAssertEqual((NSInteger)111, [limits[@"maxRequestLineBytes"] integerValue]);
  XCTAssertEqual((NSInteger)222, [limits[@"maxHeaderBytes"] integerValue]);
  XCTAssertEqual((NSInteger)333, [limits[@"maxBodyBytes"] integerValue]);
  XCTAssertEqualObjects(@(YES), config[@"trustedProxy"]);
  XCTAssertEqualObjects(@(NO), config[@"serveStatic"]);
  XCTAssertEqual((NSInteger)2222, [config[@"listenBacklog"] integerValue]);
  XCTAssertEqual((NSInteger)45, [config[@"connectionTimeoutSeconds"] integerValue]);
  XCTAssertEqualObjects(@(YES), config[@"enableReusePort"]);

  NSDictionary *accessories = config[@"propaneAccessories"];
  XCTAssertEqual((NSInteger)7, [accessories[@"workerCount"] integerValue]);
  XCTAssertEqual((NSInteger)12, [accessories[@"gracefulShutdownSeconds"] integerValue]);
  XCTAssertEqual((NSInteger)555, [accessories[@"respawnDelayMs"] integerValue]);
  XCTAssertEqual((NSInteger)3, [accessories[@"reloadOverlapSeconds"] integerValue]);

  NSDictionary *database = config[@"database"];
  XCTAssertEqualObjects(@"postgresql://localhost/arlen_test",
                        database[@"connectionString"]);
  XCTAssertEqual((NSInteger)11, [database[@"poolSize"] integerValue]);
  XCTAssertEqualObjects(@"gdl2", database[@"adapter"]);

  NSDictionary *session = config[@"session"];
  XCTAssertEqualObjects(@(YES), session[@"enabled"]);
  XCTAssertEqualObjects(@"super-secret", session[@"secret"]);
  XCTAssertEqualObjects(@"sid", session[@"cookieName"]);
  XCTAssertEqual((NSInteger)777, [session[@"maxAgeSeconds"] integerValue]);
  XCTAssertEqualObjects(@(YES), session[@"secure"]);
  XCTAssertEqualObjects(@"Strict", session[@"sameSite"]);

  NSDictionary *csrf = config[@"csrf"];
  XCTAssertEqualObjects(@(YES), csrf[@"enabled"]);
  XCTAssertEqualObjects(@"x-my-csrf", csrf[@"headerName"]);
  XCTAssertEqualObjects(@"_csrf", csrf[@"queryParamName"]);

  NSDictionary *rateLimit = config[@"rateLimit"];
  XCTAssertEqualObjects(@(YES), rateLimit[@"enabled"]);
  XCTAssertEqual((NSInteger)42, [rateLimit[@"requests"] integerValue]);
  XCTAssertEqual((NSInteger)7, [rateLimit[@"windowSeconds"] integerValue]);

  NSDictionary *securityHeaders = config[@"securityHeaders"];
  XCTAssertEqualObjects(@(NO), securityHeaders[@"enabled"]);
  XCTAssertEqualObjects(@"default-src 'none'",
                        securityHeaders[@"contentSecurityPolicy"]);

  NSDictionary *auth = config[@"auth"];
  XCTAssertEqualObjects(@(YES), auth[@"enabled"]);
  XCTAssertEqualObjects(@"jwt-secret", auth[@"bearerSecret"]);
  XCTAssertEqualObjects(@"issuer-a", auth[@"issuer"]);
  XCTAssertEqualObjects(@"audience-a", auth[@"audience"]);

  NSDictionary *openapi = config[@"openapi"];
  XCTAssertEqualObjects(@(NO), openapi[@"enabled"]);
  XCTAssertEqualObjects(@(NO), openapi[@"docsUIEnabled"]);
  XCTAssertEqualObjects(@"viewer", openapi[@"docsUIStyle"]);
  XCTAssertEqualObjects(@"Custom API", openapi[@"title"]);
  XCTAssertEqualObjects(@"9.9.9", openapi[@"version"]);

  NSDictionary *compatibility = config[@"compatibility"];
  XCTAssertEqualObjects(@(YES), compatibility[@"pageStateEnabled"]);

  NSDictionary *services = config[@"services"];
  NSDictionary *i18n = services[@"i18n"];
  XCTAssertEqualObjects(@"es", i18n[@"defaultLocale"]);
  XCTAssertEqualObjects(@"en", i18n[@"fallbackLocale"]);
}

- (void)testLegacyEnvironmentPrefixFallback {
  NSString *root = [self prepareConfigTree];
  XCTAssertNotNil(root);

  unsetenv("ARLEN_HOST");
  unsetenv("ARLEN_PORT");
  unsetenv("ARLEN_MAX_REQUEST_LINE_BYTES");
  unsetenv("ARLEN_MAX_HEADER_BYTES");
  unsetenv("ARLEN_MAX_BODY_BYTES");

  setenv("MOJOOBJC_HOST", "0.0.0.0", 1);
  setenv("MOJOOBJC_PORT", "3999", 1);
  setenv("MOJOOBJC_MAX_REQUEST_LINE_BYTES", "9001", 1);
  setenv("MOJOOBJC_MAX_HEADER_BYTES", "9002", 1);
  setenv("MOJOOBJC_MAX_BODY_BYTES", "9003", 1);
  setenv("MOJOOBJC_LISTEN_BACKLOG", "9004", 1);
  setenv("MOJOOBJC_CONNECTION_TIMEOUT_SECONDS", "31", 1);
  setenv("MOJOOBJC_ENABLE_REUSEPORT", "1", 1);
  setenv("MOJOOBJC_PROPANE_WORKERS", "6", 1);
  setenv("MOJOOBJC_DATABASE_URL", "postgresql://legacy/db", 1);
  setenv("MOJOOBJC_DB_POOL_SIZE", "5", 1);
  setenv("MOJOOBJC_DB_ADAPTER", "gdl2", 1);
  setenv("MOJOOBJC_SESSION_ENABLED", "1", 1);
  setenv("MOJOOBJC_SESSION_SECRET", "legacy-secret", 1);
  setenv("MOJOOBJC_CSRF_ENABLED", "1", 1);
  setenv("MOJOOBJC_RATE_LIMIT_ENABLED", "1", 1);
  setenv("MOJOOBJC_RATE_LIMIT_REQUESTS", "55", 1);

  NSError *error = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:root
                                         environment:@"development"
                                               error:&error];

  unsetenv("MOJOOBJC_HOST");
  unsetenv("MOJOOBJC_PORT");
  unsetenv("MOJOOBJC_MAX_REQUEST_LINE_BYTES");
  unsetenv("MOJOOBJC_MAX_HEADER_BYTES");
  unsetenv("MOJOOBJC_MAX_BODY_BYTES");
  unsetenv("MOJOOBJC_LISTEN_BACKLOG");
  unsetenv("MOJOOBJC_CONNECTION_TIMEOUT_SECONDS");
  unsetenv("MOJOOBJC_ENABLE_REUSEPORT");
  unsetenv("MOJOOBJC_PROPANE_WORKERS");
  unsetenv("MOJOOBJC_DATABASE_URL");
  unsetenv("MOJOOBJC_DB_POOL_SIZE");
  unsetenv("MOJOOBJC_DB_ADAPTER");
  unsetenv("MOJOOBJC_SESSION_ENABLED");
  unsetenv("MOJOOBJC_SESSION_SECRET");
  unsetenv("MOJOOBJC_CSRF_ENABLED");
  unsetenv("MOJOOBJC_RATE_LIMIT_ENABLED");
  unsetenv("MOJOOBJC_RATE_LIMIT_REQUESTS");

  XCTAssertNil(error);
  XCTAssertEqualObjects(@"0.0.0.0", config[@"host"]);
  XCTAssertEqual((NSInteger)3999, [config[@"port"] integerValue]);
  NSDictionary *limits = config[@"requestLimits"];
  XCTAssertEqual((NSInteger)9001, [limits[@"maxRequestLineBytes"] integerValue]);
  XCTAssertEqual((NSInteger)9002, [limits[@"maxHeaderBytes"] integerValue]);
  XCTAssertEqual((NSInteger)9003, [limits[@"maxBodyBytes"] integerValue]);
  XCTAssertEqual((NSInteger)9004, [config[@"listenBacklog"] integerValue]);
  XCTAssertEqual((NSInteger)31, [config[@"connectionTimeoutSeconds"] integerValue]);
  XCTAssertEqualObjects(@(YES), config[@"enableReusePort"]);
  NSDictionary *accessories = config[@"propaneAccessories"];
  XCTAssertEqual((NSInteger)6, [accessories[@"workerCount"] integerValue]);
  NSDictionary *database = config[@"database"];
  XCTAssertEqualObjects(@"postgresql://legacy/db", database[@"connectionString"]);
  XCTAssertEqual((NSInteger)5, [database[@"poolSize"] integerValue]);
  XCTAssertEqualObjects(@"gdl2", database[@"adapter"]);
  NSDictionary *session = config[@"session"];
  XCTAssertEqualObjects(@(YES), session[@"enabled"]);
  XCTAssertEqualObjects(@"legacy-secret", session[@"secret"]);
  NSDictionary *csrf = config[@"csrf"];
  XCTAssertEqualObjects(@(YES), csrf[@"enabled"]);
  NSDictionary *rateLimit = config[@"rateLimit"];
  XCTAssertEqualObjects(@(YES), rateLimit[@"enabled"]);
  XCTAssertEqual((NSInteger)55, [rateLimit[@"requests"] integerValue]);
}

- (void)testEOCStrictModeEnvironmentOverrides {
  NSString *root = [self prepareConfigTree];
  XCTAssertNotNil(root);

  setenv("ARLEN_EOC_STRICT_LOCALS", "1", 1);
  setenv("ARLEN_EOC_STRICT_STRINGIFY", "true", 1);

  NSError *error = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:root
                                         environment:@"development"
                                               error:&error];

  unsetenv("ARLEN_EOC_STRICT_LOCALS");
  unsetenv("ARLEN_EOC_STRICT_STRINGIFY");

  XCTAssertNil(error);
  NSDictionary *eoc = config[@"eoc"];
  XCTAssertEqualObjects(@(YES), eoc[@"strictLocals"]);
  XCTAssertEqualObjects(@(YES), eoc[@"strictStringify"]);
}

- (void)testOpenAPIDocsStyleSupportsSwaggerAndRejectsUnknownValues {
  NSString *root = [self prepareConfigTree];
  XCTAssertNotNil(root);

  setenv("ARLEN_OPENAPI_DOCS_UI_STYLE", "swagger", 1);
  NSError *error = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:root
                                         environment:@"development"
                                               error:&error];
  unsetenv("ARLEN_OPENAPI_DOCS_UI_STYLE");

  XCTAssertNil(error);
  NSDictionary *openapi = config[@"openapi"];
  XCTAssertEqualObjects(@"swagger", openapi[@"docsUIStyle"]);

  setenv("ARLEN_OPENAPI_DOCS_UI_STYLE", "invalid-style", 1);
  error = nil;
  config = [ALNConfig loadConfigAtRoot:root
                           environment:@"development"
                                 error:&error];
  unsetenv("ARLEN_OPENAPI_DOCS_UI_STYLE");

  XCTAssertNil(error);
  openapi = config[@"openapi"];
  XCTAssertEqualObjects(@"interactive", openapi[@"docsUIStyle"]);
}

- (void)testAPIOnlyDefaultsDisableStaticAndUseJSONLogs {
  NSString *root = [self createTempAppRoot];
  XCTAssertNotNil(root);
  if (root == nil) {
    return;
  }

  BOOL wrote = YES;
  wrote = wrote && [self writeFile:[root stringByAppendingPathComponent:@"config/app.plist"]
                           content:@"{\n"
                                    "  host = \"127.0.0.1\";\n"
                                    "  port = 3000;\n"
                                    "}\n"];
  wrote = wrote && [self writeFile:[root stringByAppendingPathComponent:@"config/environments/development.plist"]
                           content:@"{\n}\n"];
  XCTAssertTrue(wrote);

  setenv("ARLEN_API_ONLY", "1", 1);
  NSError *error = nil;
  NSDictionary *config = [ALNConfig loadConfigAtRoot:root
                                         environment:@"development"
                                               error:&error];
  unsetenv("ARLEN_API_ONLY");

  XCTAssertNil(error);
  XCTAssertEqualObjects(@(YES), config[@"apiOnly"]);
  XCTAssertEqualObjects(@(NO), config[@"serveStatic"]);
  XCTAssertEqualObjects(@"json", config[@"logFormat"]);
}

@end
