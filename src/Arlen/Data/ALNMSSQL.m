#import "ALNMSSQL.h"

#import "ALNJSONSerialization.h"
#import "ALNMSSQLDialect.h"
#import "ALNSQLBuilder.h"

#import <dlfcn.h>
#import <stdint.h>
#import <stdlib.h>
#import <string.h>

#if __has_include(<sql.h>) && __has_include(<sqlext.h>)
#import <sql.h>
#import <sqlext.h>
#ifdef BOOL
#undef BOOL
#endif
#define ALN_MSSQL_ODBC_HEADERS_AVAILABLE 1
#else
#define ALN_MSSQL_ODBC_HEADERS_AVAILABLE 0
#endif

NSString *const ALNMSSQLErrorDomain = @"Arlen.Data.MSSQL.Error";
NSString *const ALNMSSQLErrorDiagnosticsKey = @"mssql_diagnostics";
NSString *const ALNMSSQLErrorSQLStateKey = @"sqlstate";
NSString *const ALNMSSQLErrorNativeCodeKey = @"native_code";

static NSError *ALNMSSQLMakeError(ALNMSSQLErrorCode code,
                                  NSString *message,
                                  NSString *detail,
                                  NSDictionary *diagnostics) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"MSSQL database error";
  if ([detail length] > 0) {
    userInfo[@"detail"] = detail;
  }
  if ([diagnostics isKindOfClass:[NSDictionary class]] && [diagnostics count] > 0) {
    userInfo[ALNMSSQLErrorDiagnosticsKey] = diagnostics;
    NSString *sqlState =
        [diagnostics[ALNMSSQLErrorSQLStateKey] isKindOfClass:[NSString class]]
            ? diagnostics[ALNMSSQLErrorSQLStateKey]
            : @"";
    if ([sqlState length] > 0) {
      userInfo[ALNMSSQLErrorSQLStateKey] = sqlState;
    }
    if ([diagnostics[ALNMSSQLErrorNativeCodeKey] respondsToSelector:@selector(integerValue)]) {
      userInfo[ALNMSSQLErrorNativeCodeKey] = diagnostics[ALNMSSQLErrorNativeCodeKey];
    }
  }
  return [NSError errorWithDomain:ALNMSSQLErrorDomain code:code userInfo:userInfo];
}

static NSString *ALNMSSQLValidatedSavepointName(NSString *name, NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
  NSString *trimmed = [name isKindOfClass:[NSString class]]
                          ? [name stringByTrimmingCharactersInSet:
                                       [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                          : @"";
  if ([trimmed length] == 0) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                 @"savepoint name is required",
                                 nil,
                                 nil);
    }
    return nil;
  }

  unichar first = [trimmed characterAtIndex:0];
  if (!(first == '_' || (first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z'))) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                 @"savepoint name must start with a letter or underscore",
                                 nil,
                                 nil);
    }
    return nil;
  }
  for (NSUInteger idx = 1; idx < [trimmed length]; idx++) {
    unichar ch = [trimmed characterAtIndex:idx];
    if (!(ch == '_' || (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
          (ch >= '0' && ch <= '9'))) {
      if (error != NULL) {
        *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                   @"savepoint name must contain only letters, digits, and underscores",
                                   nil,
                                   nil);
      }
      return nil;
    }
  }
  return trimmed;
}

#if !ALN_MSSQL_ODBC_HEADERS_AVAILABLE

@interface ALNMSSQLConnection ()
@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite, getter=isOpen) BOOL open;
@end

@implementation ALNMSSQLConnection

- (instancetype)initWithConnectionString:(NSString *)connectionString error:(NSError **)error {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  if (error != NULL) {
    *error = ALNMSSQLMakeError(ALNMSSQLErrorTransportUnavailable,
                               @"MSSQL support requires unixODBC/iODBC headers at build time",
                               @"install sql.h/sqlext.h development headers to enable the MSSQL adapter",
                               nil);
  }
  return nil;
}

- (void)close {
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  (void)sql;
  (void)parameters;
  if (error != NULL) {
    *error = ALNMSSQLMakeError(ALNMSSQLErrorTransportUnavailable,
                               @"MSSQL support is unavailable in this build",
                               @"unixODBC/iODBC headers were not present when Arlen was compiled",
                               nil);
  }
  return nil;
}

- (NSDictionary *)executeQueryOne:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  return [[self executeQuery:sql parameters:parameters error:error] firstObject];
}

- (ALNDatabaseResult *)executeQueryResult:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  NSArray<NSDictionary *> *rows = [self executeQuery:sql parameters:parameters error:error];
  if (rows == nil) {
    return nil;
  }
  return ALNDatabaseResultFromRows(rows);
}

- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  (void)[self executeQuery:sql parameters:parameters error:error];
  return -1;
}

- (NSInteger)executeCommandBatch:(NSString *)sql
                   parameterSets:(NSArray<NSArray *> *)parameterSets
                           error:(NSError **)error {
  (void)sql;
  (void)parameterSets;
  return [self executeCommand:@"" parameters:@[] error:error];
}

- (BOOL)beginTransaction:(NSError **)error {
  if (error != NULL) {
    *error = ALNMSSQLMakeError(ALNMSSQLErrorTransportUnavailable,
                               @"MSSQL support is unavailable in this build",
                               @"unixODBC/iODBC headers were not present when Arlen was compiled",
                               nil);
  }
  return NO;
}

- (BOOL)commitTransaction:(NSError **)error {
  return [self beginTransaction:error];
}

- (BOOL)rollbackTransaction:(NSError **)error {
  return [self beginTransaction:error];
}

- (BOOL)createSavepointNamed:(NSString *)name error:(NSError **)error {
  (void)name;
  return [self beginTransaction:error];
}

- (BOOL)rollbackToSavepointNamed:(NSString *)name error:(NSError **)error {
  (void)name;
  return [self beginTransaction:error];
}

- (BOOL)releaseSavepointNamed:(NSString *)name error:(NSError **)error {
  (void)name;
  return [self beginTransaction:error];
}

- (BOOL)withSavepointNamed:(NSString *)name
                usingBlock:(BOOL (^)(NSError **error))block
                     error:(NSError **)error {
  (void)name;
  (void)block;
  return [self beginTransaction:error];
}

- (NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder error:(NSError **)error {
  (void)builder;
  return [self executeQuery:@"" parameters:@[] error:error];
}

- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder error:(NSError **)error {
  (void)builder;
  return [self executeCommand:@"" parameters:@[] error:error];
}

@end

@interface ALNMSSQL ()
@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite) NSUInteger maxConnections;
@end

@implementation ALNMSSQL

+ (NSDictionary<NSString *, id> *)capabilityMetadata {
  return @{
    @"adapter" : @"mssql",
    @"dialect" : @"mssql",
    @"support_tier" : @"unavailable_at_build_time",
    @"supports_transactions" : @YES,
    @"returning_mode" : @"output",
    @"pagination_syntax" : @"offset_fetch",
    @"supports_upsert" : @NO,
    @"conflict_resolution_mode" : @"unsupported",
    @"json_feature_family" : @"json_value_openjson",
    @"supports_batch_execution" : @NO,
    @"supports_builder_compilation_cache" : @NO,
    @"supports_builder_diagnostics" : @NO,
    @"supports_connection_liveness_checks" : @NO,
    @"supports_result_wrappers" : @YES,
    @"supports_savepoints" : @NO,
    @"supports_savepoint_release" : @NO,
    @"transport" : @"odbc",
    @"transport_available" : @NO,
  };
}

- (instancetype)initWithConnectionString:(NSString *)connectionString
                           maxConnections:(NSUInteger)maxConnections
                                    error:(NSError **)error {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  if (error != NULL) {
    *error = ALNMSSQLMakeError(ALNMSSQLErrorTransportUnavailable,
                               @"MSSQL support requires unixODBC/iODBC headers at build time",
                               @"install sql.h/sqlext.h development headers to enable the MSSQL adapter",
                               nil);
  }
  return nil;
}

- (NSString *)adapterName {
  return @"mssql";
}

- (id<ALNSQLDialect>)sqlDialect {
  return [ALNMSSQLDialect sharedDialect];
}

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  NSMutableDictionary<NSString *, id> *metadata =
      [NSMutableDictionary dictionaryWithDictionary:[[self class] capabilityMetadata]];
  metadata[@"connection_liveness_checks_enabled"] = @(self.connectionLivenessChecksEnabled);
  return [NSDictionary dictionaryWithDictionary:metadata];
}

- (ALNMSSQLConnection *)acquireConnection:(NSError **)error {
  if (error != NULL) {
    *error = ALNMSSQLMakeError(ALNMSSQLErrorTransportUnavailable,
                               @"MSSQL support is unavailable in this build",
                               @"unixODBC/iODBC headers were not present when Arlen was compiled",
                               nil);
  }
  return nil;
}

- (void)releaseConnection:(ALNMSSQLConnection *)connection {
  (void)connection;
}

- (id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError **)error {
  return [self acquireConnection:error];
}

- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection {
  if ([connection isKindOfClass:[ALNMSSQLConnection class]]) {
    [self releaseConnection:(ALNMSSQLConnection *)connection];
  }
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  ALNMSSQLConnection *connection = [self acquireConnection:error];
  return [connection executeQuery:sql parameters:parameters error:error];
}

- (ALNDatabaseResult *)executeQueryResult:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  NSArray<NSDictionary *> *rows = [self executeQuery:sql parameters:parameters error:error];
  if (rows == nil) {
    return nil;
  }
  return ALNDatabaseResultFromRows(rows);
}

- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  ALNMSSQLConnection *connection = [self acquireConnection:error];
  return [connection executeCommand:sql parameters:parameters error:error];
}

- (NSInteger)executeCommandBatch:(NSString *)sql
                   parameterSets:(NSArray<NSArray *> *)parameterSets
                           error:(NSError **)error {
  ALNMSSQLConnection *connection = [self acquireConnection:error];
  if (connection == nil) {
    return -1;
  }
  return [connection executeCommandBatch:sql parameterSets:parameterSets error:error];
}

- (NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder error:(NSError **)error {
  ALNMSSQLConnection *connection = [self acquireConnection:error];
  return [connection executeBuilderQuery:builder error:error];
}

- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder error:(NSError **)error {
  ALNMSSQLConnection *connection = [self acquireConnection:error];
  return [connection executeBuilderCommand:builder error:error];
}

- (BOOL)withTransaction:(BOOL (^)(ALNMSSQLConnection *connection, NSError **error))block
                  error:(NSError **)error {
  if (error != NULL) {
    *error = ALNMSSQLMakeError(ALNMSSQLErrorTransportUnavailable,
                               @"MSSQL support is unavailable in this build",
                               @"unixODBC/iODBC headers were not present when Arlen was compiled",
                               nil);
  }
  return NO;
}

- (BOOL)withTransactionUsingBlock:(BOOL (^)(id<ALNDatabaseConnection> connection,
                                            NSError **error))block
                            error:(NSError **)error {
  (void)block;
  return [self withTransaction:nil error:error];
}

@end

#else

typedef struct {
  SQLPOINTER value;
  SQLLEN indicator;
} ALNMSSQLBoundParameter;

static void *gODBCHandle = NULL;
static NSString *gODBCLoadError = nil;

static SQLRETURN (*ALNSQLAllocHandle)(SQLSMALLINT, SQLHANDLE, SQLHANDLE *) = NULL;
static SQLRETURN (*ALNSQLFreeHandle)(SQLSMALLINT, SQLHANDLE) = NULL;
static SQLRETURN (*ALNSQLSetEnvAttr)(SQLHENV, SQLINTEGER, SQLPOINTER, SQLINTEGER) = NULL;
static SQLRETURN (*ALNSQLDriverConnect)(SQLHDBC,
                                        SQLHWND,
                                        SQLCHAR *,
                                        SQLSMALLINT,
                                        SQLCHAR *,
                                        SQLSMALLINT,
                                        SQLSMALLINT *,
                                        SQLUSMALLINT) = NULL;
static SQLRETURN (*ALNSQLDisconnect)(SQLHDBC) = NULL;
static SQLRETURN (*ALNSQLExecDirect)(SQLHSTMT, SQLCHAR *, SQLINTEGER) = NULL;
static SQLRETURN (*ALNSQLPrepare)(SQLHSTMT, SQLCHAR *, SQLINTEGER) = NULL;
static SQLRETURN (*ALNSQLBindParameter)(SQLHSTMT,
                                        SQLUSMALLINT,
                                        SQLSMALLINT,
                                        SQLSMALLINT,
                                        SQLSMALLINT,
                                        SQLULEN,
                                        SQLSMALLINT,
                                        SQLPOINTER,
                                        SQLLEN,
                                        SQLLEN *) = NULL;
static SQLRETURN (*ALNSQLExecute)(SQLHSTMT) = NULL;
static SQLRETURN (*ALNSQLNumResultCols)(SQLHSTMT, SQLSMALLINT *) = NULL;
static SQLRETURN (*ALNSQLFetch)(SQLHSTMT) = NULL;
static SQLRETURN (*ALNSQLGetData)(SQLHSTMT, SQLUSMALLINT, SQLSMALLINT, SQLPOINTER, SQLLEN, SQLLEN *) = NULL;
static SQLRETURN (*ALNSQLRowCount)(SQLHSTMT, SQLLEN *) = NULL;
static SQLRETURN (*ALNSQLDescribeCol)(SQLHSTMT,
                                      SQLUSMALLINT,
                                      SQLCHAR *,
                                      SQLSMALLINT,
                                      SQLSMALLINT *,
                                      SQLSMALLINT *,
                                      SQLULEN *,
                                      SQLSMALLINT *,
                                      SQLSMALLINT *) = NULL;
static SQLRETURN (*ALNSQLGetDiagRec)(SQLSMALLINT,
                                     SQLHANDLE,
                                     SQLSMALLINT,
                                     SQLCHAR *,
                                     SQLINTEGER *,
                                     SQLCHAR *,
                                     SQLSMALLINT,
                                     SQLSMALLINT *) = NULL;
static SQLRETURN (*ALNSQLSetConnectAttr)(SQLHDBC, SQLINTEGER, SQLPOINTER, SQLINTEGER) = NULL;
static SQLRETURN (*ALNSQLEndTran)(SQLSMALLINT, SQLHANDLE, SQLSMALLINT) = NULL;

static BOOL ALNMSSQLBindODBCSymbol(void **target, void *handle, const char *symbolName) {
  *target = dlsym(handle, symbolName);
  return (*target != NULL);
}

static NSObject *ALNMSSQLODBCLockToken(void) {
  static NSObject *token = nil;
  @synchronized([ALNMSSQL class]) {
    if (token == nil) {
      token = [[NSObject alloc] init];
    }
  }
  return token;
}

static BOOL ALNMSSQLLoadODBC(NSError **error) {
  @synchronized(ALNMSSQLODBCLockToken()) {
    if (gODBCHandle != NULL) {
      return YES;
    }
    if ([gODBCLoadError length] > 0) {
      if (error != NULL) {
        *error = ALNMSSQLMakeError(ALNMSSQLErrorTransportUnavailable,
                                   @"failed to load ODBC transport",
                                   gODBCLoadError,
                                   nil);
      }
      return NO;
    }

    const char *candidates[] = {
      "/usr/lib/x86_64-linux-gnu/libodbc.so.2",
      "libodbc.so.2",
      "libodbc.so",
    };
    size_t candidateCount = sizeof(candidates) / sizeof(candidates[0]);
    void *handle = NULL;
    for (size_t idx = 0; idx < candidateCount; idx++) {
      handle = dlopen(candidates[idx], RTLD_LAZY | RTLD_LOCAL);
      if (handle != NULL) {
        break;
      }
    }
    if (handle == NULL) {
      gODBCLoadError = @"ODBC shared library not found";
      if (error != NULL) {
        *error = ALNMSSQLMakeError(ALNMSSQLErrorTransportUnavailable,
                                   @"failed to load ODBC transport",
                                   gODBCLoadError,
                                   nil);
      }
      return NO;
    }

    BOOL ok = YES;
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLAllocHandle, handle, "SQLAllocHandle");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLFreeHandle, handle, "SQLFreeHandle");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLSetEnvAttr, handle, "SQLSetEnvAttr");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLDriverConnect, handle, "SQLDriverConnect");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLDisconnect, handle, "SQLDisconnect");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLExecDirect, handle, "SQLExecDirect");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLPrepare, handle, "SQLPrepare");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLBindParameter, handle, "SQLBindParameter");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLExecute, handle, "SQLExecute");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLNumResultCols, handle, "SQLNumResultCols");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLFetch, handle, "SQLFetch");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLGetData, handle, "SQLGetData");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLRowCount, handle, "SQLRowCount");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLDescribeCol, handle, "SQLDescribeCol");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLGetDiagRec, handle, "SQLGetDiagRec");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLSetConnectAttr, handle, "SQLSetConnectAttr");
    ok = ok && ALNMSSQLBindODBCSymbol((void **)&ALNSQLEndTran, handle, "SQLEndTran");
    if (!ok) {
      const char *dlError = dlerror();
      gODBCLoadError =
          [NSString stringWithFormat:@"required ODBC symbols missing: %s", dlError ?: "unknown"];
      dlclose(handle);
      if (error != NULL) {
        *error = ALNMSSQLMakeError(ALNMSSQLErrorTransportUnavailable,
                                   @"failed to load ODBC transport",
                                   gODBCLoadError,
                                   nil);
      }
      return NO;
    }

    gODBCHandle = handle;
    return YES;
  }
}

static NSDictionary *ALNMSSQLDiagnosticsFromHandle(SQLSMALLINT handleType, SQLHANDLE handle) {
  if (handle == SQL_NULL_HANDLE || ALNSQLGetDiagRec == NULL) {
    return @{};
  }

  SQLCHAR state[6] = { 0 };
  SQLINTEGER nativeCode = 0;
  SQLCHAR message[1024] = { 0 };
  SQLSMALLINT messageLength = 0;
  SQLRETURN rc =
      ALNSQLGetDiagRec(handleType,
                       handle,
                       1,
                       state,
                       &nativeCode,
                       message,
                       (SQLSMALLINT)(sizeof(message) - 1),
                       &messageLength);
  if (!SQL_SUCCEEDED(rc)) {
    return @{};
  }

  NSString *sqlState =
      [NSString stringWithUTF8String:(const char *)state] ?: @"";
  NSString *detail =
      [NSString stringWithUTF8String:(const char *)message] ?: @"";
  NSMutableDictionary *diagnostics = [NSMutableDictionary dictionary];
  if ([sqlState length] > 0) {
    diagnostics[ALNMSSQLErrorSQLStateKey] = sqlState;
  }
  if ([detail length] > 0) {
    diagnostics[@"message"] = detail;
  }
  diagnostics[ALNMSSQLErrorNativeCodeKey] = @(nativeCode);
  return diagnostics;
}

static NSError *ALNMSSQLErrorForHandle(ALNMSSQLErrorCode code,
                                       NSString *message,
                                       SQLSMALLINT handleType,
                                       SQLHANDLE handle) {
  NSDictionary *diagnostics = ALNMSSQLDiagnosticsFromHandle(handleType, handle);
  NSString *detail = [diagnostics[@"message"] isKindOfClass:[NSString class]]
                         ? diagnostics[@"message"]
                         : nil;
  return ALNMSSQLMakeError(code, message, detail, diagnostics);
}

static BOOL ALNMSSQLNSNumberLooksBoolean(NSNumber *value) {
  if (value == nil) {
    return NO;
  }
  const char *type = [value objCType];
  if (type == NULL) {
    return NO;
  }
  return (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, "B") == 0);
}

static BOOL ALNMSSQLNSNumberLooksFloatingPoint(NSNumber *value) {
  if (value == nil) {
    return NO;
  }
  const char *type = [value objCType];
  if (type == NULL) {
    return NO;
  }
  return (strcmp(type, @encode(float)) == 0 || strcmp(type, @encode(double)) == 0);
}

static NSString *ALNMSSQLTimestampStringFromDate(NSDate *value) {
  if (![value isKindOfClass:[NSDate class]]) {
    return @"";
  }
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
  return [formatter stringFromDate:value] ?: @"";
}

static NSString *ALNMSSQLJSONStringFromObject(id value, NSError **error) {
  NSData *jsonData = [ALNJSONSerialization dataWithJSONObject:value options:0 error:error];
  if (jsonData == nil) {
    return nil;
  }
  NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
  if (json == nil && error != NULL) {
    *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                               @"failed to encode MSSQL parameter as JSON",
                               @"JSON payload was not valid UTF-8",
                               nil);
  }
  return json;
}

static SQLSMALLINT ALNMSSQLDecimalDigitsFromString(NSString *value) {
  NSRange decimalPoint = [value rangeOfString:@"."];
  if (decimalPoint.location == NSNotFound) {
    return 0;
  }
  NSUInteger digits = [value length] - (decimalPoint.location + 1);
  return (SQLSMALLINT)MIN((NSUInteger)38, digits);
}

static NSString *ALNMSSQLTextParameterForValue(id value,
                                               SQLSMALLINT *sqlTypeOut,
                                               SQLULEN *columnSizeOut,
                                               SQLSMALLINT *decimalDigitsOut,
                                               NSError **error) {
  if (sqlTypeOut != NULL) {
    *sqlTypeOut = SQL_VARCHAR;
  }
  if (columnSizeOut != NULL) {
    *columnSizeOut = 1;
  }
  if (decimalDigitsOut != NULL) {
    *decimalDigitsOut = 0;
  }
  if (value == nil || value == [NSNull null]) {
    return nil;
  }
  if ([value isKindOfClass:[ALNDatabaseArrayValue class]]) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                 @"failed binding MSSQL statement parameters",
                                 @"MSSQL array parameters are not supported",
                                 nil);
    }
    return nil;
  }

  NSString *text = nil;
  SQLSMALLINT sqlType = SQL_VARCHAR;
  SQLSMALLINT decimalDigits = 0;
  if ([value isKindOfClass:[ALNDatabaseJSONValue class]]) {
    text = ALNMSSQLJSONStringFromObject(((ALNDatabaseJSONValue *)value).object, error);
  } else if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
    text = ALNMSSQLJSONStringFromObject(value, error);
  } else if ([value isKindOfClass:[NSString class]]) {
    text = value;
  } else if ([value isKindOfClass:[NSUUID class]]) {
    text = [(NSUUID *)value UUIDString];
    sqlType = SQL_GUID;
  } else if ([value isKindOfClass:[NSNumber class]]) {
    if (ALNMSSQLNSNumberLooksBoolean((NSNumber *)value)) {
      text = [((NSNumber *)value) boolValue] ? @"1" : @"0";
      sqlType = SQL_BIT;
    } else if (ALNMSSQLNSNumberLooksFloatingPoint((NSNumber *)value)) {
      text = [value stringValue];
      sqlType = SQL_DOUBLE;
    } else if ([value isKindOfClass:[NSDecimalNumber class]]) {
      text = [value stringValue];
      sqlType = SQL_DECIMAL;
      decimalDigits = ALNMSSQLDecimalDigitsFromString(text);
    } else {
      text = [value stringValue];
      sqlType = SQL_BIGINT;
    }
  } else if ([value isKindOfClass:[NSDate class]]) {
    text = ALNMSSQLTimestampStringFromDate((NSDate *)value);
    sqlType = SQL_TYPE_TIMESTAMP;
    decimalDigits = 3;
  } else if ([value isKindOfClass:[NSData class]]) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                 @"failed binding MSSQL statement parameters",
                                 @"NSData parameters are not yet supported by the MSSQL adapter",
                                 nil);
    }
    return nil;
  } else if ([value respondsToSelector:@selector(stringValue)]) {
    text = [value stringValue];
  } else {
    text = [value description];
  }

  if (text == nil) {
    return nil;
  }
  if (sqlTypeOut != NULL) {
    *sqlTypeOut = sqlType;
  }
  if (columnSizeOut != NULL) {
    *columnSizeOut = (SQLULEN)MAX((NSUInteger)1, [text length]);
  }
  if (decimalDigitsOut != NULL) {
    *decimalDigitsOut = decimalDigits;
  }
  return text;
}

static BOOL ALNMSSQLPrepareStatement(SQLHDBC connection,
                                     NSString *sql,
                                     NSArray *parameters,
                                     SQLHSTMT *statementOut,
                                     NSMutableArray *buffers,
                                     NSMutableData *indicatorStorage,
                                     NSError **error) {
  if (statementOut != NULL) {
    *statementOut = SQL_NULL_HSTMT;
  }

  SQLHSTMT statement = SQL_NULL_HSTMT;
  SQLRETURN rc = ALNSQLAllocHandle(SQL_HANDLE_STMT, connection, (SQLHANDLE *)&statement);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorQueryFailed,
                                      @"failed to allocate MSSQL statement handle",
                                      SQL_HANDLE_DBC,
                                      connection);
    }
    return NO;
  }

  const char *sqlCString = [sql UTF8String];
  if ([parameters count] == 0) {
    rc = ALNSQLExecDirect(statement, (SQLCHAR *)sqlCString, SQL_NTS);
    if (!SQL_SUCCEEDED(rc) && rc != SQL_NO_DATA) {
      if (error != NULL) {
        *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorQueryFailed,
                                        @"MSSQL statement execution failed",
                                        SQL_HANDLE_STMT,
                                        statement);
      }
      ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
      return NO;
    }
    if (statementOut != NULL) {
      *statementOut = statement;
    }
    return YES;
  }

  rc = ALNSQLPrepare(statement, (SQLCHAR *)sqlCString, SQL_NTS);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorQueryFailed,
                                      @"failed preparing MSSQL statement",
                                      SQL_HANDLE_STMT,
                                      statement);
    }
    ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
    return NO;
  }

  SQLLEN *indicatorValues = (SQLLEN *)[indicatorStorage mutableBytes];
  for (NSUInteger idx = 0; idx < [parameters count]; idx++) {
    SQLSMALLINT sqlType = SQL_VARCHAR;
    SQLULEN columnSize = 1;
    SQLSMALLINT decimalDigits = 0;
    NSError *parameterError = nil;
    NSString *text = ALNMSSQLTextParameterForValue(parameters[idx],
                                                   &sqlType,
                                                   &columnSize,
                                                   &decimalDigits,
                                                   &parameterError);
    if (parameterError != nil) {
      if (error != NULL) {
        NSString *detail = [NSString stringWithFormat:@"parameter %lu: %@",
                                                      (unsigned long)(idx + 1),
                                                      [parameterError localizedDescription] ?: @"invalid value"];
        *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                   @"failed binding MSSQL statement parameters",
                                   detail,
                                   nil);
      }
      ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
      return NO;
    }
    SQLLEN indicator = SQL_NULL_DATA;
    SQLPOINTER valuePointer = NULL;
    SQLLEN bufferLength = 0;
    if ([text length] > 0) {
      NSMutableData *mutableData =
          [NSMutableData dataWithData:[text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data]];
      const char terminator = '\0';
      [mutableData appendBytes:&terminator length:1];
      [buffers addObject:mutableData];
      indicator = SQL_NTS;
      valuePointer = (SQLPOINTER)[[buffers lastObject] bytes];
      bufferLength = (SQLLEN)[[buffers lastObject] length];
    }

    indicatorValues[idx] = indicator;
    SQLLEN *indicatorPointer = &indicatorValues[idx];

    rc = ALNSQLBindParameter(statement,
                             (SQLUSMALLINT)(idx + 1),
                             SQL_PARAM_INPUT,
                             SQL_C_CHAR,
                             sqlType,
                             columnSize,
                             decimalDigits,
                             valuePointer,
                             bufferLength,
                             indicatorPointer);
    if (!SQL_SUCCEEDED(rc)) {
      if (error != NULL) {
        *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorQueryFailed,
                                        @"failed binding MSSQL statement parameters",
                                        SQL_HANDLE_STMT,
                                        statement);
      }
      ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
      return NO;
    }
  }

  rc = ALNSQLExecute(statement);
  if (!SQL_SUCCEEDED(rc) && rc != SQL_NO_DATA) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorQueryFailed,
                                      @"MSSQL statement execution failed",
                                      SQL_HANDLE_STMT,
                                      statement);
    }
    ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
    return NO;
  }

  if (statementOut != NULL) {
    *statementOut = statement;
  }
  return YES;
}

static NSNumber *ALNMSSQLIntegerNumberFromString(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return nil;
  }
  NSScanner *scanner = [NSScanner scannerWithString:value];
  long long parsed = 0;
  if (![scanner scanLongLong:&parsed] || ![scanner isAtEnd]) {
    return nil;
  }
  return @(parsed);
}

static NSNumber *ALNMSSQLDoubleNumberFromString(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return nil;
  }
  NSScanner *scanner = [NSScanner scannerWithString:value];
  double parsed = 0;
  if (![scanner scanDouble:&parsed] || ![scanner isAtEnd]) {
    return nil;
  }
  return @(parsed);
}

static NSDecimalNumber *ALNMSSQLDecimalNumberFromString(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return nil;
  }
  NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:value];
  return [number isEqualToNumber:[NSDecimalNumber notANumber]] ? nil : number;
}

static NSDate *ALNMSSQLDateFromString(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return nil;
  }
  NSString *trimmed =
      [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSArray<NSString *> *formats = @[
    @"yyyy-MM-dd",
    @"yyyy-MM-dd HH:mm:ss",
    @"yyyy-MM-dd HH:mm:ss.SSS",
    @"yyyy-MM-dd'T'HH:mm:ss",
    @"yyyy-MM-dd'T'HH:mm:ss.SSS",
    @"yyyy-MM-dd'T'HH:mm:ssZ",
    @"yyyy-MM-dd'T'HH:mm:ss.SSSZ",
  ];
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  for (NSString *format in formats) {
    formatter.dateFormat = format;
    NSDate *date = [formatter dateFromString:trimmed];
    if (date != nil) {
      return date;
    }
  }
  return nil;
}

static BOOL ALNMSSQLColumnTypeIsInteger(SQLSMALLINT dataType) {
  return (dataType == SQL_TINYINT || dataType == SQL_SMALLINT || dataType == SQL_INTEGER ||
          dataType == SQL_BIGINT);
}

static BOOL ALNMSSQLColumnTypeIsDecimal(SQLSMALLINT dataType) {
  return (dataType == SQL_DECIMAL || dataType == SQL_NUMERIC);
}

static BOOL ALNMSSQLColumnTypeIsFloat(SQLSMALLINT dataType) {
  return (dataType == SQL_REAL || dataType == SQL_FLOAT || dataType == SQL_DOUBLE);
}

static BOOL ALNMSSQLColumnTypeIsDateLike(SQLSMALLINT dataType) {
  return (dataType == SQL_TYPE_DATE || dataType == SQL_DATE || dataType == SQL_TYPE_TIMESTAMP ||
          dataType == SQL_TIMESTAMP);
}

static id ALNMSSQLDecodedTextColumnValue(SQLSMALLINT dataType,
                                         NSString *columnName,
                                         NSString *value,
                                         NSError **error) {
  if (dataType == SQL_BIT) {
    NSString *normalized = [[value lowercaseString] stringByTrimmingCharactersInSet:
                                                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([normalized isEqualToString:@"1"] || [normalized isEqualToString:@"true"] ||
        [normalized isEqualToString:@"t"]) {
      return @YES;
    }
    if ([normalized isEqualToString:@"0"] || [normalized isEqualToString:@"false"] ||
        [normalized isEqualToString:@"f"]) {
      return @NO;
    }
  } else if (ALNMSSQLColumnTypeIsInteger(dataType)) {
    NSNumber *number = ALNMSSQLIntegerNumberFromString(value);
    if (number != nil) {
      return number;
    }
  } else if (ALNMSSQLColumnTypeIsDecimal(dataType)) {
    NSDecimalNumber *number = ALNMSSQLDecimalNumberFromString(value);
    if (number != nil) {
      return number;
    }
  } else if (ALNMSSQLColumnTypeIsFloat(dataType)) {
    NSNumber *number = ALNMSSQLDoubleNumberFromString(value);
    if (number != nil) {
      return number;
    }
  } else if (ALNMSSQLColumnTypeIsDateLike(dataType)) {
    NSDate *date = ALNMSSQLDateFromString(value);
    if (date != nil) {
      return date;
    }
  }

  if (dataType == SQL_GUID || dataType == SQL_TYPE_TIME || dataType == SQL_TIME || dataType == SQL_CHAR ||
      dataType == SQL_VARCHAR || dataType == SQL_LONGVARCHAR || dataType == SQL_WCHAR ||
      dataType == SQL_WVARCHAR || dataType == SQL_WLONGVARCHAR) {
    return value ?: @"";
  }

  if (error != NULL && value != nil &&
      (dataType == SQL_BIT || ALNMSSQLColumnTypeIsInteger(dataType) || ALNMSSQLColumnTypeIsDecimal(dataType) ||
       ALNMSSQLColumnTypeIsFloat(dataType) || ALNMSSQLColumnTypeIsDateLike(dataType))) {
    NSString *detail = [NSString stringWithFormat:@"column %@ could not be decoded for MSSQL type %d",
                                                  columnName ?: @"",
                                                  (int)dataType];
    *error = ALNMSSQLMakeError(ALNMSSQLErrorQueryFailed,
                               @"failed fetching MSSQL result column",
                               detail,
                               nil);
    return nil;
  }
  return value ?: @"";
}

static id ALNMSSQLFetchColumnValue(SQLHSTMT statement,
                                   SQLUSMALLINT columnIndex,
                                   SQLSMALLINT dataType,
                                   NSString *columnName,
                                   NSError **error) {
  NSMutableData *data = [NSMutableData data];
  SQLLEN indicator = 0;
  char buffer[4096];
  memset(buffer, 0, sizeof(buffer));
  BOOL sawData = NO;

  while (YES) {
    SQLRETURN rc = ALNSQLGetData(statement,
                                 columnIndex,
                                 SQL_C_CHAR,
                                 buffer,
                                 (SQLLEN)(sizeof(buffer) - 1),
                                 &indicator);
    if (rc == SQL_NO_DATA) {
      break;
    }
    if (indicator == SQL_NULL_DATA) {
      return [NSNull null];
    }
    if (!SQL_SUCCEEDED(rc) && rc != SQL_SUCCESS_WITH_INFO) {
      if (error != NULL) {
        *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorQueryFailed,
                                        @"failed fetching MSSQL result column",
                                        SQL_HANDLE_STMT,
                                        statement);
      }
      return nil;
    }

    sawData = YES;
    NSUInteger chunkLength = strlen(buffer);
    if (chunkLength > 0) {
      [data appendBytes:buffer length:chunkLength];
    }
    if (rc == SQL_SUCCESS) {
      break;
    }
    memset(buffer, 0, sizeof(buffer));
  }

  if (!sawData) {
    return @"";
  }
  NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (value == nil) {
    if (error != NULL) {
      NSString *detail = [NSString stringWithFormat:@"column %@ result payload was not valid UTF-8",
                                                    columnName ?: @""];
      *error = ALNMSSQLMakeError(ALNMSSQLErrorQueryFailed,
                                 @"failed fetching MSSQL result column",
                                 detail,
                                 nil);
    }
    return nil;
  }
  return ALNMSSQLDecodedTextColumnValue(dataType, columnName, value, error);
}

@interface ALNMSSQLConnection ()

@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite, getter=isOpen) BOOL open;
@property(nonatomic, assign) BOOL inTransaction;
@property(nonatomic, assign) SQLHENV environmentHandle;
@property(nonatomic, assign) SQLHDBC connectionHandle;

- (BOOL)checkConnectionLiveness:(NSError **)error;

@end

@implementation ALNMSSQLConnection

- (instancetype)initWithConnectionString:(NSString *)connectionString error:(NSError **)error {
  self = [super init];
  if (self == nil) {
    return nil;
  }

  if ([connectionString length] == 0) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                 @"connection string is required",
                                 nil,
                                 nil);
    }
    return nil;
  }
  if (!ALNMSSQLLoadODBC(error)) {
    return nil;
  }

  _connectionString = [connectionString copy];
  _environmentHandle = SQL_NULL_HENV;
  _connectionHandle = SQL_NULL_HDBC;
  _open = NO;
  _inTransaction = NO;

  SQLRETURN rc =
      ALNSQLAllocHandle(SQL_HANDLE_ENV, SQL_NULL_HANDLE, (SQLHANDLE *)&_environmentHandle);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorConnectionFailed,
                                 @"failed to allocate ODBC environment handle",
                                 nil,
                                 nil);
    }
    return nil;
  }

  rc = ALNSQLSetEnvAttr(_environmentHandle,
                        SQL_ATTR_ODBC_VERSION,
                        (SQLPOINTER)(intptr_t)SQL_OV_ODBC3,
                        0);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorConnectionFailed,
                                      @"failed to set ODBC version to 3.x",
                                      SQL_HANDLE_ENV,
                                      _environmentHandle);
    }
    [self close];
    return nil;
  }

  rc = ALNSQLAllocHandle(SQL_HANDLE_DBC, _environmentHandle, (SQLHANDLE *)&_connectionHandle);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorConnectionFailed,
                                      @"failed to allocate ODBC connection handle",
                                      SQL_HANDLE_ENV,
                                      _environmentHandle);
    }
    [self close];
    return nil;
  }

  SQLCHAR outBuffer[1024] = { 0 };
  SQLSMALLINT outLength = 0;
  rc = ALNSQLDriverConnect(_connectionHandle,
                           NULL,
                           (SQLCHAR *)[_connectionString UTF8String],
                           SQL_NTS,
                           outBuffer,
                           (SQLSMALLINT)(sizeof(outBuffer) - 1),
                           &outLength,
                           SQL_DRIVER_NOPROMPT);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorConnectionFailed,
                                      @"failed connecting to MSSQL via ODBC",
                                      SQL_HANDLE_DBC,
                                      _connectionHandle);
    }
    [self close];
    return nil;
  }

  _open = YES;
  return self;
}

- (void)dealloc {
  [self close];
}

- (void)close {
  if (_connectionHandle != SQL_NULL_HDBC) {
    if (_inTransaction) {
      (void)ALNSQLEndTran(SQL_HANDLE_DBC, _connectionHandle, SQL_ROLLBACK);
      (void)ALNSQLSetConnectAttr(_connectionHandle,
                                 SQL_ATTR_AUTOCOMMIT,
                                 (SQLPOINTER)(intptr_t)SQL_AUTOCOMMIT_ON,
                                 0);
      _inTransaction = NO;
    }
    (void)ALNSQLDisconnect(_connectionHandle);
    (void)ALNSQLFreeHandle(SQL_HANDLE_DBC, _connectionHandle);
    _connectionHandle = SQL_NULL_HDBC;
  }
  if (_environmentHandle != SQL_NULL_HENV) {
    (void)ALNSQLFreeHandle(SQL_HANDLE_ENV, _environmentHandle);
    _environmentHandle = SQL_NULL_HENV;
  }
  _open = NO;
}

- (BOOL)checkConnectionLiveness:(NSError **)error {
  if (![self isOpen]) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorConnectionFailed,
                                 @"MSSQL connection is not open",
                                 nil,
                                 nil);
    }
    return NO;
  }

  NSArray<NSDictionary *> *rows = [self executeQuery:@"SELECT 1 AS liveness_probe"
                                          parameters:@[]
                                               error:error];
  if (rows == nil) {
    if (error != NULL && *error == nil) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorConnectionFailed,
                                 @"MSSQL connection liveness check failed",
                                 nil,
                                 nil);
    }
    return NO;
  }
  return YES;
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  if (![self isOpen]) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorConnectionFailed,
                                 @"MSSQL connection is not open",
                                 nil,
                                 nil);
    }
    return nil;
  }

  NSMutableArray *buffers = [NSMutableArray array];
  NSMutableData *indicatorStorage =
      [NSMutableData dataWithLength:MAX((NSUInteger)1, [parameters count]) * sizeof(SQLLEN)];
  SQLHSTMT statement = SQL_NULL_HSTMT;
  if (!ALNMSSQLPrepareStatement(_connectionHandle,
                                sql ?: @"",
                                parameters ?: @[],
                                &statement,
                                buffers,
                                indicatorStorage,
                                error)) {
    return nil;
  }

  NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
  SQLSMALLINT columnCount = 0;
  SQLRETURN rc = ALNSQLNumResultCols(statement, &columnCount);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorQueryFailed,
                                      @"failed reading MSSQL result column metadata",
                                      SQL_HANDLE_STMT,
                                      statement);
    }
    ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
    return nil;
  }
  if (columnCount <= 0) {
    ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
    return @[];
  }

  NSMutableArray<NSString *> *columnNames = [NSMutableArray arrayWithCapacity:(NSUInteger)columnCount];
  NSMutableArray<NSNumber *> *columnTypes = [NSMutableArray arrayWithCapacity:(NSUInteger)columnCount];
  for (SQLUSMALLINT idx = 1; idx <= (SQLUSMALLINT)columnCount; idx++) {
    SQLCHAR nameBuffer[256] = { 0 };
    SQLSMALLINT nameLength = 0;
    SQLSMALLINT dataType = 0;
    SQLULEN columnSize = 0;
    SQLSMALLINT decimalDigits = 0;
    SQLSMALLINT nullable = 0;
    rc = ALNSQLDescribeCol(statement,
                           idx,
                           nameBuffer,
                           (SQLSMALLINT)(sizeof(nameBuffer) - 1),
                           &nameLength,
                           &dataType,
                           &columnSize,
                           &decimalDigits,
                           &nullable);
    if (!SQL_SUCCEEDED(rc)) {
      if (error != NULL) {
        *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorQueryFailed,
                                        @"failed describing MSSQL result columns",
                                        SQL_HANDLE_STMT,
                                        statement);
      }
      ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
      return nil;
    }
    NSString *columnName = [NSString stringWithUTF8String:(const char *)nameBuffer] ?: @"";
    [columnNames addObject:columnName];
    [columnTypes addObject:@(dataType)];
  }

  while ((rc = ALNSQLFetch(statement)) != SQL_NO_DATA) {
    if (!SQL_SUCCEEDED(rc)) {
      if (error != NULL) {
        *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorQueryFailed,
                                        @"failed fetching MSSQL result rows",
                                        SQL_HANDLE_STMT,
                                        statement);
      }
      ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
      return nil;
    }

    NSMutableDictionary *row = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)columnCount];
    for (SQLUSMALLINT idx = 1; idx <= (SQLUSMALLINT)columnCount; idx++) {
      NSError *columnError = nil;
      id value = ALNMSSQLFetchColumnValue(statement,
                                          idx,
                                          [columnTypes[(NSUInteger)(idx - 1)] shortValue],
                                          columnNames[(NSUInteger)(idx - 1)],
                                          &columnError);
      if (value == nil && columnError != nil) {
        if (error != NULL) {
          *error = columnError;
        }
        ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
        return nil;
      }
      row[columnNames[(NSUInteger)(idx - 1)]] = value ?: (id)[NSNull null];
    }
    [rows addObject:[NSDictionary dictionaryWithDictionary:row]];
  }

  ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
  return rows;
}

- (NSDictionary *)executeQueryOne:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  return [[self executeQuery:sql parameters:parameters error:error] firstObject];
}

- (ALNDatabaseResult *)executeQueryResult:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  NSArray<NSDictionary *> *rows = [self executeQuery:sql parameters:parameters error:error];
  if (rows == nil) {
    return nil;
  }
  return ALNDatabaseResultFromRows(rows);
}

- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  if (![self isOpen]) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorConnectionFailed,
                                 @"MSSQL connection is not open",
                                 nil,
                                 nil);
    }
    return -1;
  }

  NSMutableArray *buffers = [NSMutableArray array];
  NSMutableData *indicatorStorage =
      [NSMutableData dataWithLength:MAX((NSUInteger)1, [parameters count]) * sizeof(SQLLEN)];
  SQLHSTMT statement = SQL_NULL_HSTMT;
  if (!ALNMSSQLPrepareStatement(_connectionHandle,
                                sql ?: @"",
                                parameters ?: @[],
                                &statement,
                                buffers,
                                indicatorStorage,
                                error)) {
    return -1;
  }

  SQLLEN affectedRows = 0;
  SQLRETURN rc = ALNSQLRowCount(statement, &affectedRows);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorQueryFailed,
                                      @"failed reading MSSQL row count",
                                      SQL_HANDLE_STMT,
                                      statement);
    }
    ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
    return -1;
  }

  ALNSQLFreeHandle(SQL_HANDLE_STMT, statement);
  return (NSInteger)MAX((SQLLEN)0, affectedRows);
}

- (NSInteger)executeCommandBatch:(NSString *)sql
                   parameterSets:(NSArray<NSArray *> *)parameterSets
                           error:(NSError **)error {
  if (error != NULL) {
    *error = nil;
  }
  if (parameterSets != nil && ![parameterSets isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                 @"batch parameter sets must be an array",
                                 nil,
                                 nil);
    }
    return -1;
  }

  NSInteger totalAffected = 0;
  for (id item in parameterSets ?: @[]) {
    if (![item isKindOfClass:[NSArray class]]) {
      if (error != NULL) {
        *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                   @"each batch parameter set must be an array",
                                   nil,
                                   nil);
      }
      return -1;
    }
    NSInteger affected = [self executeCommand:sql parameters:item error:error];
    if (affected < 0) {
      return -1;
    }
    totalAffected += affected;
  }
  return totalAffected;
}

- (BOOL)beginTransaction:(NSError **)error {
  if (![self isOpen]) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorConnectionFailed,
                                 @"MSSQL connection is not open",
                                 nil,
                                 nil);
    }
    return NO;
  }
  if (self.inTransaction) {
    return YES;
  }
  SQLRETURN rc = ALNSQLSetConnectAttr(_connectionHandle,
                                      SQL_ATTR_AUTOCOMMIT,
                                      (SQLPOINTER)(intptr_t)SQL_AUTOCOMMIT_OFF,
                                      0);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorTransactionFailed,
                                      @"failed disabling autocommit for MSSQL transaction",
                                      SQL_HANDLE_DBC,
                                      _connectionHandle);
    }
    return NO;
  }
  self.inTransaction = YES;
  return YES;
}

- (BOOL)commitTransaction:(NSError **)error {
  if (![self isOpen]) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorConnectionFailed,
                                 @"MSSQL connection is not open",
                                 nil,
                                 nil);
    }
    return NO;
  }
  if (!self.inTransaction) {
    return YES;
  }
  SQLRETURN rc = ALNSQLEndTran(SQL_HANDLE_DBC, _connectionHandle, SQL_COMMIT);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorTransactionFailed,
                                      @"failed committing MSSQL transaction",
                                      SQL_HANDLE_DBC,
                                      _connectionHandle);
    }
    return NO;
  }
  rc = ALNSQLSetConnectAttr(_connectionHandle,
                            SQL_ATTR_AUTOCOMMIT,
                            (SQLPOINTER)(intptr_t)SQL_AUTOCOMMIT_ON,
                            0);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorTransactionFailed,
                                      @"failed restoring MSSQL autocommit mode after commit",
                                      SQL_HANDLE_DBC,
                                      _connectionHandle);
    }
    return NO;
  }
  self.inTransaction = NO;
  return YES;
}

- (BOOL)rollbackTransaction:(NSError **)error {
  if (![self isOpen]) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorConnectionFailed,
                                 @"MSSQL connection is not open",
                                 nil,
                                 nil);
    }
    return NO;
  }
  if (!self.inTransaction) {
    return YES;
  }
  SQLRETURN rc = ALNSQLEndTran(SQL_HANDLE_DBC, _connectionHandle, SQL_ROLLBACK);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorTransactionFailed,
                                      @"failed rolling back MSSQL transaction",
                                      SQL_HANDLE_DBC,
                                      _connectionHandle);
    }
    return NO;
  }
  rc = ALNSQLSetConnectAttr(_connectionHandle,
                            SQL_ATTR_AUTOCOMMIT,
                            (SQLPOINTER)(intptr_t)SQL_AUTOCOMMIT_ON,
                            0);
  if (!SQL_SUCCEEDED(rc)) {
    if (error != NULL) {
      *error = ALNMSSQLErrorForHandle(ALNMSSQLErrorTransactionFailed,
                                      @"failed restoring MSSQL autocommit mode after rollback",
                                      SQL_HANDLE_DBC,
                                      _connectionHandle);
    }
    return NO;
  }
  self.inTransaction = NO;
  return YES;
}

- (BOOL)createSavepointNamed:(NSString *)name error:(NSError **)error {
  NSString *validatedName = ALNMSSQLValidatedSavepointName(name, error);
  if (validatedName == nil) {
    return NO;
  }
  if (!self.inTransaction) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorTransactionFailed,
                                 @"savepoints require an active MSSQL transaction",
                                 nil,
                                 nil);
    }
    return NO;
  }
  NSString *sql = [NSString stringWithFormat:@"SAVE TRANSACTION %@", validatedName];
  return ([self executeCommand:sql parameters:@[] error:error] >= 0);
}

- (BOOL)rollbackToSavepointNamed:(NSString *)name error:(NSError **)error {
  NSString *validatedName = ALNMSSQLValidatedSavepointName(name, error);
  if (validatedName == nil) {
    return NO;
  }
  if (!self.inTransaction) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorTransactionFailed,
                                 @"savepoints require an active MSSQL transaction",
                                 nil,
                                 nil);
    }
    return NO;
  }
  NSString *sql = [NSString stringWithFormat:@"ROLLBACK TRANSACTION %@", validatedName];
  return ([self executeCommand:sql parameters:@[] error:error] >= 0);
}

- (BOOL)releaseSavepointNamed:(NSString *)name error:(NSError **)error {
  NSString *validatedName = ALNMSSQLValidatedSavepointName(name, error);
  if (validatedName == nil) {
    return NO;
  }
  if (!self.inTransaction) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorTransactionFailed,
                                 @"savepoints require an active MSSQL transaction",
                                 nil,
                                 nil);
    }
    return NO;
  }
  if (error != NULL) {
    *error = nil;
  }
  return YES;
}

- (BOOL)withSavepointNamed:(NSString *)name
                usingBlock:(BOOL (^)(NSError **error))block
                     error:(NSError **)error {
  if (block == nil) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                 @"savepoint block is required",
                                 nil,
                                 nil);
    }
    return NO;
  }
  if (![self createSavepointNamed:name error:error]) {
    return NO;
  }

  NSError *blockError = nil;
  BOOL success = block(&blockError);
  if (success) {
    NSError *releaseError = nil;
    if (![self releaseSavepointNamed:name error:&releaseError]) {
      if (error != NULL) {
        *error = releaseError;
      }
      return NO;
    }
    return YES;
  }

  NSError *rollbackError = nil;
  (void)[self rollbackToSavepointNamed:name error:&rollbackError];
  if (error != NULL) {
    *error = blockError ?: rollbackError;
  }
  return NO;
}

- (NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder error:(NSError **)error {
  NSDictionary *compiled = [builder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:error];
  if (compiled == nil) {
    return nil;
  }
  return [self executeQuery:compiled[@"sql"] parameters:compiled[@"parameters"] error:error];
}

- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder error:(NSError **)error {
  NSDictionary *compiled = [builder buildWithDialect:[ALNMSSQLDialect sharedDialect] error:error];
  if (compiled == nil) {
    return -1;
  }
  return [self executeCommand:compiled[@"sql"] parameters:compiled[@"parameters"] error:error];
}

@end

@interface ALNMSSQL ()

@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite) NSUInteger maxConnections;
@property(nonatomic, strong) NSMutableArray<ALNMSSQLConnection *> *idleConnections;
@property(nonatomic, assign) NSUInteger inUseConnections;

@end

@implementation ALNMSSQL

+ (NSDictionary<NSString *, id> *)capabilityMetadata {
  return @{
    @"adapter" : @"mssql",
    @"dialect" : @"mssql",
    @"support_tier" : @"supported_subset",
    @"supports_transactions" : @YES,
    @"returning_mode" : @"output",
    @"pagination_syntax" : @"offset_fetch",
    @"supports_upsert" : @NO,
    @"conflict_resolution_mode" : @"unsupported",
    @"json_feature_family" : @"json_value_openjson",
    @"supports_batch_execution" : @YES,
    @"supports_builder_compilation_cache" : @NO,
    @"supports_builder_diagnostics" : @NO,
    @"supports_connection_liveness_checks" : @YES,
    @"supports_result_wrappers" : @YES,
    @"supports_savepoints" : @YES,
    @"supports_savepoint_release" : @YES,
    @"batch_execution_mode" : @"sequential_same_connection",
    @"savepoint_release_mode" : @"no_op",
    @"transport" : @"odbc",
    @"transport_available" : @YES,
  };
}

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  NSMutableDictionary<NSString *, id> *metadata =
      [NSMutableDictionary dictionaryWithDictionary:[[self class] capabilityMetadata]];
  metadata[@"connection_liveness_checks_enabled"] = @(self.connectionLivenessChecksEnabled);
  return [NSDictionary dictionaryWithDictionary:metadata];
}

- (NSString *)adapterName {
  return @"mssql";
}

- (id<ALNSQLDialect>)sqlDialect {
  return [ALNMSSQLDialect sharedDialect];
}

- (instancetype)initWithConnectionString:(NSString *)connectionString
                           maxConnections:(NSUInteger)maxConnections
                                    error:(NSError **)error {
  self = [super init];
  if (self == nil) {
    return nil;
  }
  if ([connectionString length] == 0) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                 @"connection string is required",
                                 nil,
                                 nil);
    }
    return nil;
  }
  if (!ALNMSSQLLoadODBC(error)) {
    return nil;
  }

  _connectionString = [connectionString copy];
  _maxConnections = (maxConnections > 0) ? maxConnections : 8;
  _idleConnections = [NSMutableArray array];
  _inUseConnections = 0;
  _connectionLivenessChecksEnabled = NO;
  return self;
}

- (void)dealloc {
  @synchronized(self) {
    for (ALNMSSQLConnection *connection in self.idleConnections) {
      [connection close];
    }
    [self.idleConnections removeAllObjects];
  }
}

- (ALNMSSQLConnection *)acquireConnection:(NSError **)error {
  @synchronized(self) {
    while ([self.idleConnections count] > 0) {
      ALNMSSQLConnection *connection = [self.idleConnections lastObject];
      [self.idleConnections removeLastObject];
      if (self.connectionLivenessChecksEnabled) {
        NSError *livenessError = nil;
        if (![connection checkConnectionLiveness:&livenessError]) {
          [connection close];
          continue;
        }
      }
      self.inUseConnections += 1;
      return connection;
    }

    NSUInteger total = self.inUseConnections + [self.idleConnections count];
    if (total >= self.maxConnections) {
      if (error != NULL) {
        *error = ALNMSSQLMakeError(ALNMSSQLErrorPoolExhausted,
                                   @"MSSQL connection pool exhausted",
                                   nil,
                                   nil);
      }
      return nil;
    }

    ALNMSSQLConnection *connection =
        [[ALNMSSQLConnection alloc] initWithConnectionString:self.connectionString error:error];
    if (connection == nil) {
      return nil;
    }
    self.inUseConnections += 1;
    return connection;
  }
}

- (void)releaseConnection:(ALNMSSQLConnection *)connection {
  if (connection == nil) {
    return;
  }
  @synchronized(self) {
    if (self.inUseConnections > 0) {
      self.inUseConnections -= 1;
    }
    if ([connection isOpen] && connection.inTransaction) {
      NSError *rollbackError = nil;
      if (![connection rollbackTransaction:&rollbackError]) {
        [connection close];
      }
    }
    if ([connection isOpen]) {
      [self.idleConnections addObject:connection];
    } else {
      [connection close];
    }
  }
}

- (id<ALNDatabaseConnection>)acquireAdapterConnection:(NSError **)error {
  return (id<ALNDatabaseConnection>)[self acquireConnection:error];
}

- (void)releaseAdapterConnection:(id<ALNDatabaseConnection>)connection {
  if ([connection isKindOfClass:[ALNMSSQLConnection class]]) {
    [self releaseConnection:(ALNMSSQLConnection *)connection];
  }
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  ALNMSSQLConnection *connection = [self acquireConnection:error];
  if (connection == nil) {
    return nil;
  }
  NSArray<NSDictionary *> *rows = nil;
  @try {
    rows = [connection executeQuery:sql parameters:parameters ?: @[] error:error];
  } @finally {
    [self releaseConnection:connection];
  }
  return rows;
}

- (ALNDatabaseResult *)executeQueryResult:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  NSArray<NSDictionary *> *rows = [self executeQuery:sql parameters:parameters error:error];
  if (rows == nil) {
    return nil;
  }
  return ALNDatabaseResultFromRows(rows);
}

- (NSInteger)executeCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  ALNMSSQLConnection *connection = [self acquireConnection:error];
  if (connection == nil) {
    return -1;
  }
  NSInteger affected = -1;
  @try {
    affected = [connection executeCommand:sql parameters:parameters ?: @[] error:error];
  } @finally {
    [self releaseConnection:connection];
  }
  return affected;
}

- (NSInteger)executeCommandBatch:(NSString *)sql
                   parameterSets:(NSArray<NSArray *> *)parameterSets
                           error:(NSError **)error {
  ALNMSSQLConnection *connection = [self acquireConnection:error];
  if (connection == nil) {
    return -1;
  }
  NSInteger affected = -1;
  @try {
    affected = [connection executeCommandBatch:sql parameterSets:parameterSets error:error];
  } @finally {
    [self releaseConnection:connection];
  }
  return affected;
}

- (NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder error:(NSError **)error {
  ALNMSSQLConnection *connection = [self acquireConnection:error];
  if (connection == nil) {
    return nil;
  }
  NSArray<NSDictionary *> *rows = nil;
  @try {
    rows = [connection executeBuilderQuery:builder error:error];
  } @finally {
    [self releaseConnection:connection];
  }
  return rows;
}

- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder error:(NSError **)error {
  ALNMSSQLConnection *connection = [self acquireConnection:error];
  if (connection == nil) {
    return -1;
  }
  NSInteger affected = -1;
  @try {
    affected = [connection executeBuilderCommand:builder error:error];
  } @finally {
    [self releaseConnection:connection];
  }
  return affected;
}

- (BOOL)withTransaction:(BOOL (^)(ALNMSSQLConnection *connection, NSError **error))block
                  error:(NSError **)error {
  if (block == nil) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                 @"transaction block is required",
                                 nil,
                                 nil);
    }
    return NO;
  }

  ALNMSSQLConnection *connection = [self acquireConnection:error];
  if (connection == nil) {
    return NO;
  }

  BOOL success = NO;
  NSError *blockError = nil;
  @try {
    if (![connection beginTransaction:error]) {
      return NO;
    }
    success = block(connection, &blockError);
    if (success) {
      if (![connection commitTransaction:error]) {
        success = NO;
      }
    } else {
      NSError *rollbackError = nil;
      (void)[connection rollbackTransaction:&rollbackError];
      if (error != NULL) {
        *error = blockError ?: rollbackError;
      }
    }
  } @finally {
    [self releaseConnection:connection];
  }
  return success;
}

- (BOOL)withTransactionUsingBlock:(BOOL (^)(id<ALNDatabaseConnection> connection,
                                            NSError **error))block
                            error:(NSError **)error {
  if (block == nil) {
    if (error != NULL) {
      *error = ALNMSSQLMakeError(ALNMSSQLErrorInvalidArgument,
                                 @"transaction block is required",
                                 nil,
                                 nil);
    }
    return NO;
  }

  return [self withTransaction:^BOOL(ALNMSSQLConnection *connection, NSError **txError) {
    return block((id<ALNDatabaseConnection>)connection, txError);
  } error:error];
}

@end

#endif
