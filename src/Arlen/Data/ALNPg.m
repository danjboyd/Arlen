#import "ALNPg.h"
#import "ALNJSONSerialization.h"
#import "ALNPostgresDialect.h"
#import "ALNSQLBuilder.h"

#import <dispatch/dispatch.h>
#import <ctype.h>
#import <stdlib.h>
#import <stdint.h>
#import <string.h>
#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

NSString *const ALNPgErrorDomain = @"Arlen.Data.Pg.Error";
NSString *const ALNPgErrorDiagnosticsKey = @"pg_diagnostics";
NSString *const ALNPgErrorSQLStateKey = @"sqlstate";
NSString *const ALNPgErrorServerDetailKey = @"server_detail";
NSString *const ALNPgErrorServerHintKey = @"server_hint";
NSString *const ALNPgErrorServerPositionKey = @"server_position";
NSString *const ALNPgErrorServerWhereKey = @"server_where";
NSString *const ALNPgErrorServerTableKey = @"server_table";
NSString *const ALNPgErrorServerColumnKey = @"server_column";
NSString *const ALNPgErrorServerConstraintKey = @"server_constraint";

NSString *const ALNPgQueryStageCompile = @"compile";
NSString *const ALNPgQueryStageExecute = @"execute";
NSString *const ALNPgQueryStageResult = @"result";
NSString *const ALNPgQueryStageError = @"error";

NSString *const ALNPgQueryEventStageKey = @"stage";
NSString *const ALNPgQueryEventSourceKey = @"source";
NSString *const ALNPgQueryEventOperationKey = @"operation";
NSString *const ALNPgQueryEventExecutionModeKey = @"execution_mode";
NSString *const ALNPgQueryEventCacheHitKey = @"cache_hit";
NSString *const ALNPgQueryEventCacheFullKey = @"cache_full";
NSString *const ALNPgQueryEventSQLHashKey = @"sql_hash";
NSString *const ALNPgQueryEventSQLLengthKey = @"sql_length";
NSString *const ALNPgQueryEventSQLTokenKey = @"sql_token";
NSString *const ALNPgQueryEventParameterCountKey = @"parameter_count";
NSString *const ALNPgQueryEventPreparedStatementKey = @"prepared_statement";
NSString *const ALNPgQueryEventDurationMSKey = @"duration_ms";
NSString *const ALNPgQueryEventRowCountKey = @"row_count";
NSString *const ALNPgQueryEventAffectedRowsKey = @"affected_rows";
NSString *const ALNPgQueryEventErrorDomainKey = @"error_domain";
NSString *const ALNPgQueryEventErrorCodeKey = @"error_code";
NSString *const ALNPgQueryEventSQLKey = @"sql";

typedef struct pg_conn PGconn;
typedef struct pg_result PGresult;
typedef unsigned int ALNOid;

typedef enum {
  ALNConnectionOK = 0,
} ALNConnStatusType;

typedef enum {
  ALNPGRES_EMPTY_QUERY = 0,
  ALNPGRES_COMMAND_OK = 1,
  ALNPGRES_TUPLES_OK = 2,
} ALNExecStatusType;

typedef struct {
  const char **paramValues;
  char **ownedParamValues;
  int *paramLengths;
  int *paramFormats;
  NSUInteger count;
} ALNPgExecParamsBuffer;

static void *gLibpqHandle = NULL;
static NSString *gLibpqLoadError = nil;

static NSError *ALNPgMakeError(ALNPgErrorCode code,
                               NSString *message,
                               NSString *detail,
                               NSString *sql);
static void ALNPgClearError(NSError **error);
static NSError *ALNPgMakeErrorWithDiagnostics(ALNPgErrorCode code,
                                              NSString *message,
                                              NSString *detail,
                                              NSString *sql,
                                              NSDictionary *diagnostics);
static BOOL ALNPgBuildExecParamsBuffer(NSArray *parameters,
                                       NSString *sql,
                                       ALNPgExecParamsBuffer *buffer,
                                       NSError **error);
static void ALNPgFreeExecParamsBuffer(ALNPgExecParamsBuffer *buffer);
static uint64_t ALNPgFNV1a64(NSString *value);
static NSString *ALNPgSQLHash(NSString *sql);
static NSString *ALNPgSQLToken(NSString *sql);
static BOOL ALNPgCanonicalizeBuilderValue(NSMutableString *out,
                                          id value,
                                          NSMutableSet *visited);
static NSString *ALNPgBuilderCompilationSignature(ALNSQLBuilder *builder);
static void ALNPgEmitEventToStderr(NSDictionary *event);

static PGconn *(*ALNPQconnectdb)(const char *conninfo) = NULL;
static int (*ALNPQstatus)(const PGconn *conn) = NULL;
static void (*ALNPQfinish)(PGconn *conn) = NULL;
static char *(*ALNPQerrorMessage)(const PGconn *conn) = NULL;
static PGresult *(*ALNPQexec)(PGconn *conn, const char *query) = NULL;
static PGresult *(*ALNPQprepare)(PGconn *conn,
                                 const char *stmtName,
                                 const char *query,
                                 int nParams,
                                 const void *paramTypes) = NULL;
static PGresult *(*ALNPQexecParams)(PGconn *conn,
                                    const char *command,
                                    int nParams,
                                    const void *paramTypes,
                                    const char *const *paramValues,
                                    const int *paramLengths,
                                    const int *paramFormats,
                                    int resultFormat) = NULL;
static PGresult *(*ALNPQexecPrepared)(PGconn *conn,
                                      const char *stmtName,
                                      int nParams,
                                      const char *const *paramValues,
                                      const int *paramLengths,
                                      const int *paramFormats,
                                      int resultFormat) = NULL;
static int (*ALNPQresultStatus)(const PGresult *res) = NULL;
static char *(*ALNPQresultErrorMessage)(const PGresult *res) = NULL;
static char *(*ALNPQresultErrorField)(const PGresult *res, int fieldcode) = NULL;
static void (*ALNPQclear)(PGresult *res) = NULL;
static int (*ALNPQnfields)(const PGresult *res) = NULL;
static int (*ALNPQntuples)(const PGresult *res) = NULL;
static char *(*ALNPQfname)(const PGresult *res, int columnNumber) = NULL;
static ALNOid (*ALNPQftype)(const PGresult *res, int columnNumber) = NULL;
static int (*ALNPQgetisnull)(const PGresult *res, int rowNumber, int columnNumber) = NULL;
static char *(*ALNPQgetvalue)(const PGresult *res, int rowNumber, int columnNumber) = NULL;
static char *(*ALNPQcmdTuples)(PGresult *res) = NULL;

#if defined(_WIN32)
static NSString *ALNLibpqDynamicLoaderLastError(void) {
  DWORD errorCode = GetLastError();
  if (errorCode == 0) {
    return @"unknown Windows loader error";
  }

  char *messageBuffer = NULL;
  DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                FORMAT_MESSAGE_IGNORE_INSERTS;
  DWORD length = FormatMessageA(flags,
                                NULL,
                                errorCode,
                                0,
                                (LPSTR)&messageBuffer,
                                0,
                                NULL);
  if (length == 0 || messageBuffer == NULL) {
    return [NSString stringWithFormat:@"Windows loader error %lu",
                                      (unsigned long)errorCode];
  }

  while (length > 0 &&
         (messageBuffer[length - 1] == '\r' || messageBuffer[length - 1] == '\n')) {
    messageBuffer[length - 1] = '\0';
    length -= 1;
  }
  NSString *message =
      [NSString stringWithUTF8String:messageBuffer] ?: @"unknown Windows loader error";
  LocalFree(messageBuffer);
  return message;
}

static void *ALNOpenLibpqCandidate(const char *candidate) {
  if (candidate == NULL || candidate[0] == '\0') {
    return NULL;
  }
  return (void *)LoadLibraryA(candidate);
}

static void *ALNLookupLibpqSymbol(void *handle, const char *symbolName) {
  return (handle != NULL && symbolName != NULL)
             ? (void *)GetProcAddress((HMODULE)handle, symbolName)
             : NULL;
}

static void ALNCloseLibpqHandle(void *handle) {
  if (handle != NULL) {
    FreeLibrary((HMODULE)handle);
  }
}
#else
static NSString *ALNLibpqDynamicLoaderLastError(void) {
  const char *dlError = dlerror();
  return [NSString stringWithUTF8String:(dlError != NULL) ? dlError : "unknown dynamic loader error"] ?:
         @"unknown dynamic loader error";
}

static void *ALNOpenLibpqCandidate(const char *candidate) {
  if (candidate == NULL || candidate[0] == '\0') {
    return NULL;
  }
  return dlopen(candidate, RTLD_LAZY | RTLD_LOCAL);
}

static void *ALNLookupLibpqSymbol(void *handle, const char *symbolName) {
  return (handle != NULL && symbolName != NULL) ? dlsym(handle, symbolName) : NULL;
}

static void ALNCloseLibpqHandle(void *handle) {
  if (handle != NULL) {
    dlclose(handle);
  }
}
#endif

static BOOL ALNBindLibpqSymbol(void **target, void *handle, const char *symbolName) {
  *target = ALNLookupLibpqSymbol(handle, symbolName);
  return (*target != NULL);
}

static void ALNBindOptionalLibpqSymbol(void **target, void *handle, const char *symbolName) {
  *target = ALNLookupLibpqSymbol(handle, symbolName);
}

static NSLock *ALNLibpqLoadLock(void) {
  static NSLock *lock = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    lock = [[NSLock alloc] init];
  });
  return lock;
}

static BOOL ALNLoadLibpq(NSError **error) {
  NSLock *loadLock = ALNLibpqLoadLock();
  [loadLock lock];
  @try {
    if (gLibpqHandle != NULL) {
      return YES;
    }
    if ([gLibpqLoadError length] > 0) {
      if (error != NULL) {
        *error = ALNPgMakeError(ALNPgErrorConnectionFailed,
                                @"failed to load libpq",
                                gLibpqLoadError,
                                nil);
      }
      return NO;
    }

    const char *envCandidate = getenv("ARLEN_LIBPQ_LIBRARY");
#if defined(_WIN32)
    const char *candidates[] = {
      envCandidate,
      "C:/msys64/clang64/bin/libpq-5.dll",
      "C:/msys64/clang64/bin/libpq.dll",
      "libpq-5.dll",
      "libpq.dll",
    };
#else
    const char *candidates[] = {
      envCandidate,
      "/usr/lib/x86_64-linux-gnu/libpq.so.5",
      "libpq.so.5",
      "libpq.so",
    };
#endif

    void *handle = NULL;
    size_t candidateCount = sizeof(candidates) / sizeof(candidates[0]);
    for (size_t idx = 0; idx < candidateCount; idx++) {
      handle = ALNOpenLibpqCandidate(candidates[idx]);
      if (handle != NULL) {
        break;
      }
    }

    if (handle == NULL) {
      gLibpqLoadError = @"libpq shared library not found";
      if (error != NULL) {
        *error = ALNPgMakeError(ALNPgErrorConnectionFailed,
                                @"failed to load libpq",
                                gLibpqLoadError,
                                nil);
      }
      return NO;
    }

    BOOL ok = YES;
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQconnectdb, handle, "PQconnectdb");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQstatus, handle, "PQstatus");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQfinish, handle, "PQfinish");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQerrorMessage, handle, "PQerrorMessage");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQexec, handle, "PQexec");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQprepare, handle, "PQprepare");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQexecParams, handle, "PQexecParams");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQexecPrepared, handle, "PQexecPrepared");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQresultStatus, handle, "PQresultStatus");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQresultErrorMessage, handle, "PQresultErrorMessage");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQclear, handle, "PQclear");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQnfields, handle, "PQnfields");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQntuples, handle, "PQntuples");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQfname, handle, "PQfname");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQftype, handle, "PQftype");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQgetisnull, handle, "PQgetisnull");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQgetvalue, handle, "PQgetvalue");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQcmdTuples, handle, "PQcmdTuples");
    ALNBindOptionalLibpqSymbol((void **)&ALNPQresultErrorField, handle, "PQresultErrorField");

    if (!ok) {
      gLibpqLoadError =
          [NSString stringWithFormat:@"required libpq symbols missing: %@",
                                     ALNLibpqDynamicLoaderLastError()];
      ALNCloseLibpqHandle(handle);
      if (error != NULL) {
        *error = ALNPgMakeError(ALNPgErrorConnectionFailed,
                                @"failed to load libpq",
                                gLibpqLoadError,
                                nil);
      }
      return NO;
    }

    gLibpqHandle = handle;
    return YES;
  } @finally {
    [loadLock unlock];
  }
}

static NSError *ALNPgMakeError(ALNPgErrorCode code,
                               NSString *message,
                               NSString *detail,
                               NSString *sql) {
  return ALNPgMakeErrorWithDiagnostics(code, message, detail, sql, nil);
}

static void ALNPgClearError(NSError **error) {
  if (error != NULL) {
    *error = nil;
  }
}

static NSString *ALNPgValidatedSavepointName(NSString *name, NSError **error) {
  ALNPgClearError(error);
  NSString *trimmed = [name isKindOfClass:[NSString class]]
                          ? [name stringByTrimmingCharactersInSet:
                                       [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                          : @"";
  if ([trimmed length] == 0) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"savepoint name is required",
                              nil,
                              nil);
    }
    return nil;
  }

  unichar first = [trimmed characterAtIndex:0];
  if (!(first == '_' || (first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z'))) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
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
        *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                                @"savepoint name must contain only letters, digits, and underscores",
                                nil,
                                nil);
      }
      return nil;
    }
  }
  return trimmed;
}

static NSError *ALNPgMakeErrorWithDiagnostics(ALNPgErrorCode code,
                                              NSString *message,
                                              NSString *detail,
                                              NSString *sql,
                                              NSDictionary *diagnostics) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"database error";
  if ([detail length] > 0) {
    userInfo[@"detail"] = detail;
  }
  if ([sql length] > 0) {
    userInfo[@"sql"] = sql;
  }

  NSDictionary *normalizedDiagnostics =
      [diagnostics isKindOfClass:[NSDictionary class]] ? diagnostics : @{};
  NSString *sqlState = [normalizedDiagnostics[ALNPgErrorSQLStateKey] isKindOfClass:[NSString class]]
                           ? normalizedDiagnostics[ALNPgErrorSQLStateKey]
                           : @"";
  if ([sqlState length] > 0) {
    userInfo[ALNPgErrorSQLStateKey] = sqlState;
  }
  NSString *serverDetail =
      [normalizedDiagnostics[ALNPgErrorServerDetailKey] isKindOfClass:[NSString class]]
          ? normalizedDiagnostics[ALNPgErrorServerDetailKey]
          : @"";
  if ([serverDetail length] > 0) {
    userInfo[ALNPgErrorServerDetailKey] = serverDetail;
  }
  NSString *serverHint =
      [normalizedDiagnostics[ALNPgErrorServerHintKey] isKindOfClass:[NSString class]]
          ? normalizedDiagnostics[ALNPgErrorServerHintKey]
          : @"";
  if ([serverHint length] > 0) {
    userInfo[ALNPgErrorServerHintKey] = serverHint;
  }
  NSString *serverPosition =
      [normalizedDiagnostics[ALNPgErrorServerPositionKey] isKindOfClass:[NSString class]]
          ? normalizedDiagnostics[ALNPgErrorServerPositionKey]
          : @"";
  if ([serverPosition length] > 0) {
    userInfo[ALNPgErrorServerPositionKey] = serverPosition;
  }
  NSString *serverWhere =
      [normalizedDiagnostics[ALNPgErrorServerWhereKey] isKindOfClass:[NSString class]]
          ? normalizedDiagnostics[ALNPgErrorServerWhereKey]
          : @"";
  if ([serverWhere length] > 0) {
    userInfo[ALNPgErrorServerWhereKey] = serverWhere;
  }
  NSString *serverTable =
      [normalizedDiagnostics[ALNPgErrorServerTableKey] isKindOfClass:[NSString class]]
          ? normalizedDiagnostics[ALNPgErrorServerTableKey]
          : @"";
  if ([serverTable length] > 0) {
    userInfo[ALNPgErrorServerTableKey] = serverTable;
  }
  NSString *serverColumn =
      [normalizedDiagnostics[ALNPgErrorServerColumnKey] isKindOfClass:[NSString class]]
          ? normalizedDiagnostics[ALNPgErrorServerColumnKey]
          : @"";
  if ([serverColumn length] > 0) {
    userInfo[ALNPgErrorServerColumnKey] = serverColumn;
  }
  NSString *serverConstraint =
      [normalizedDiagnostics[ALNPgErrorServerConstraintKey] isKindOfClass:[NSString class]]
          ? normalizedDiagnostics[ALNPgErrorServerConstraintKey]
          : @"";
  if ([serverConstraint length] > 0) {
    userInfo[ALNPgErrorServerConstraintKey] = serverConstraint;
  }
  if ([normalizedDiagnostics count] > 0) {
    userInfo[ALNPgErrorDiagnosticsKey] = normalizedDiagnostics;
  }
  return [NSError errorWithDomain:ALNPgErrorDomain code:code userInfo:userInfo];
}

static NSString *ALNPgResultErrorFieldString(PGresult *result, int fieldCode) {
  if (result == NULL || ALNPQresultErrorField == NULL) {
    return nil;
  }
  const char *value = ALNPQresultErrorField(result, fieldCode);
  if (value == NULL || value[0] == '\0') {
    return nil;
  }
  NSString *text = [NSString stringWithUTF8String:value];
  if (![text isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *trimmed =
      [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return ([trimmed length] > 0) ? trimmed : nil;
}

static NSDictionary *ALNPgDiagnosticsFromResult(PGresult *result) {
  if (result == NULL || ALNPQresultErrorField == NULL) {
    return @{};
  }

  enum {
    ALNPG_DIAG_SQLSTATE = 'C',
    ALNPG_DIAG_DETAIL = 'D',
    ALNPG_DIAG_HINT = 'H',
    ALNPG_DIAG_POSITION = 'P',
    ALNPG_DIAG_WHERE = 'W',
    ALNPG_DIAG_TABLE = 't',
    ALNPG_DIAG_COLUMN = 'c',
    ALNPG_DIAG_CONSTRAINT = 'n',
  };

  NSMutableDictionary *diagnostics = [NSMutableDictionary dictionary];
  NSString *sqlState = ALNPgResultErrorFieldString(result, ALNPG_DIAG_SQLSTATE);
  if ([sqlState length] > 0) {
    diagnostics[ALNPgErrorSQLStateKey] = sqlState;
  }
  NSString *detail = ALNPgResultErrorFieldString(result, ALNPG_DIAG_DETAIL);
  if ([detail length] > 0) {
    diagnostics[ALNPgErrorServerDetailKey] = detail;
  }
  NSString *hint = ALNPgResultErrorFieldString(result, ALNPG_DIAG_HINT);
  if ([hint length] > 0) {
    diagnostics[ALNPgErrorServerHintKey] = hint;
  }
  NSString *position = ALNPgResultErrorFieldString(result, ALNPG_DIAG_POSITION);
  if ([position length] > 0) {
    diagnostics[ALNPgErrorServerPositionKey] = position;
  }
  NSString *where = ALNPgResultErrorFieldString(result, ALNPG_DIAG_WHERE);
  if ([where length] > 0) {
    diagnostics[ALNPgErrorServerWhereKey] = where;
  }
  NSString *table = ALNPgResultErrorFieldString(result, ALNPG_DIAG_TABLE);
  if ([table length] > 0) {
    diagnostics[ALNPgErrorServerTableKey] = table;
  }
  NSString *column = ALNPgResultErrorFieldString(result, ALNPG_DIAG_COLUMN);
  if ([column length] > 0) {
    diagnostics[ALNPgErrorServerColumnKey] = column;
  }
  NSString *constraint = ALNPgResultErrorFieldString(result, ALNPG_DIAG_CONSTRAINT);
  if ([constraint length] > 0) {
    diagnostics[ALNPgErrorServerConstraintKey] = constraint;
  }
  return [NSDictionary dictionaryWithDictionary:diagnostics];
}

static NSArray<NSString *> *ALNPgBuilderSnapshotKeys(void) {
  static NSArray<NSString *> *keys = nil;
  if (keys == nil) {
    keys = @[
      @"kind",
      @"tableName",
      @"tableAlias",
      @"selectColumns",
      @"values",
      @"whereClauses",
      @"havingClauses",
      @"orderByClauses",
      @"joins",
      @"groupByFields",
      @"ctes",
      @"windowClauses",
      @"setOperations",
      @"returningColumns",
      @"limitValue",
      @"offsetValue",
      @"hasLimit",
      @"hasOffset",
      @"rowLockMode",
      @"rowLockTables",
      @"rowLockSkipLocked",
      @"conflictMode",
      @"conflictColumns",
      @"conflictUpdateFields",
      @"conflictUpdateAssignments",
      @"conflictDoUpdateWhereExpression",
      @"conflictDoUpdateWhereParameters",
    ];
  }
  return keys;
}

static id ALNPgBuilderValueForKey(ALNSQLBuilder *builder, NSString *key) {
  if (builder == nil || [key length] == 0) {
    return [NSNull null];
  }
  @try {
    id value = [builder valueForKey:key];
    return value ?: [NSNull null];
  } @catch (NSException *exception) {
    (void)exception;
    return [NSNull null];
  }
}

static BOOL ALNPgCanonicalizeBuilderValue(NSMutableString *out,
                                          id value,
                                          NSMutableSet *visited) {
  if (out == nil) {
    return NO;
  }

  if (value == nil || value == [NSNull null]) {
    [out appendString:@"n;"];
    return YES;
  }

  if ([value isKindOfClass:[NSString class]]) {
    NSString *text = (NSString *)value;
    [out appendFormat:@"s:%lu:%@;", (unsigned long)[text length], text];
    return YES;
  }

  if ([value isKindOfClass:[NSNumber class]]) {
    [out appendFormat:@"#:%@;", [(NSNumber *)value stringValue]];
    return YES;
  }

  if ([value isKindOfClass:[NSDate class]]) {
    [out appendFormat:@"d:%.6f;", [(NSDate *)value timeIntervalSince1970]];
    return YES;
  }

  if ([value isKindOfClass:[NSData class]]) {
    NSString *base64 = [(NSData *)value base64EncodedStringWithOptions:0];
    [out appendFormat:@"b:%lu:%@;", (unsigned long)[base64 length], base64];
    return YES;
  }

  if ([value isKindOfClass:[NSArray class]]) {
    NSArray *array = (NSArray *)value;
    [out appendFormat:@"a:%lu:[", (unsigned long)[array count]];
    for (id element in array) {
      if (!ALNPgCanonicalizeBuilderValue(out, element, visited)) {
        return NO;
      }
    }
    [out appendString:@"];"];
    return YES;
  }

  if ([value isKindOfClass:[NSDictionary class]]) {
    NSDictionary *dictionary = (NSDictionary *)value;
    NSArray *keys = [[dictionary allKeys] sortedArrayUsingComparator:^NSComparisonResult(id lhs, id rhs) {
      NSString *left = [lhs isKindOfClass:[NSString class]] ? lhs : [lhs description];
      NSString *right = [rhs isKindOfClass:[NSString class]] ? rhs : [rhs description];
      return [left compare:right];
    }];
    [out appendFormat:@"m:%lu:{", (unsigned long)[keys count]];
    for (id key in keys) {
      NSString *keyText = [key isKindOfClass:[NSString class]] ? key : [key description];
      [out appendFormat:@"k:%lu:%@=", (unsigned long)[keyText length], keyText];
      if (!ALNPgCanonicalizeBuilderValue(out, dictionary[key], visited)) {
        return NO;
      }
    }
    [out appendString:@"};"];
    return YES;
  }

  if ([value isKindOfClass:[ALNSQLBuilder class]]) {
    NSString *identity = [NSString stringWithFormat:@"%p", value];
    if ([visited containsObject:identity]) {
      [out appendString:@"builder:<cycle>;"];
      return YES;
    }

    [visited addObject:identity];
    [out appendString:@"builder:{"];
    for (NSString *key in ALNPgBuilderSnapshotKeys()) {
      [out appendString:key];
      [out appendString:@"="];
      id nested = ALNPgBuilderValueForKey((ALNSQLBuilder *)value, key);
      if (!ALNPgCanonicalizeBuilderValue(out, nested, visited)) {
        [visited removeObject:identity];
        return NO;
      }
      [out appendString:@"|"];
    }
    [out appendString:@"};"];
    [visited removeObject:identity];
    return YES;
  }

  NSString *text = [value description] ?: @"";
  [out appendFormat:@"o:%@:%lu:%@;",
                    NSStringFromClass([value class]) ?: @"NSObject",
                    (unsigned long)[text length],
                    text];
  return YES;
}

static NSString *ALNPgBuilderCompilationSignature(ALNSQLBuilder *builder) {
  if (builder == nil) {
    return nil;
  }

  NSMutableString *encoded = [NSMutableString string];
  NSMutableSet *visited = [NSMutableSet set];
  if (!ALNPgCanonicalizeBuilderValue(encoded, builder, visited)) {
    return nil;
  }
  return [NSString stringWithString:encoded];
}

static uint64_t ALNPgFNV1a64(NSString *value) {
  static const uint64_t offsetBasis = UINT64_C(14695981039346656037);
  static const uint64_t prime = UINT64_C(1099511628211);

  uint64_t hash = offsetBasis;
  const char *bytes = [[value ?: @"" copy] UTF8String];
  if (bytes == NULL) {
    return hash;
  }
  for (const unsigned char *cursor = (const unsigned char *)bytes; *cursor != '\0'; cursor++) {
    hash ^= (uint64_t)(*cursor);
    hash *= prime;
  }
  return hash;
}

static NSString *ALNPgSQLHash(NSString *sql) {
  uint64_t hash = ALNPgFNV1a64(sql ?: @"");
  return [NSString stringWithFormat:@"%016llx", (unsigned long long)hash];
}

static NSString *ALNPgSQLToken(NSString *sql) {
  NSString *trimmed = [sql isKindOfClass:[NSString class]]
                          ? [sql stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                          : @"";
  if ([trimmed length] == 0) {
    return @"";
  }

  NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSString *first = @"";
  for (NSString *part in parts) {
    if ([part length] > 0) {
      first = part;
      break;
    }
  }
  if ([first length] == 0) {
    return @"";
  }

  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  NSString *token = [first stringByTrimmingCharactersInSet:[allowed invertedSet]];
  if ([token length] == 0) {
    return @"";
  }
  return [[token uppercaseString] substringToIndex:MIN((NSUInteger)24, [token length])];
}

static void ALNPgEmitEventToStderr(NSDictionary *event) {
  if (![event isKindOfClass:[NSDictionary class]]) {
    return;
  }

  NSError *jsonError = nil;
  NSData *json = [ALNJSONSerialization dataWithJSONObject:event options:0 error:&jsonError];
  if (json != nil && jsonError == nil) {
    NSString *line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    if ([line length] > 0) {
      fprintf(stderr, "%s\n", [line UTF8String]);
      return;
    }
  }

  NSMutableArray *pairs = [NSMutableArray array];
  NSArray *keys = [[event allKeys] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *key in keys) {
    NSString *value = [event[key] description] ?: @"";
    [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
  }
  NSString *line = [pairs componentsJoinedByString:@" "];
  if ([line length] > 0) {
    fprintf(stderr, "%s\n", [line UTF8String]);
  }
}

enum {
  ALNPGOIDOID_NAME = 19,
  ALNPGOIDOID_BOOL = 16,
  ALNPGOIDOID_BYTEA = 17,
  ALNPGOIDOID_BOOL_ARRAY = 1000,
  ALNPGOIDOID_BYTEA_ARRAY = 1001,
  ALNPGOIDOID_INT8 = 20,
  ALNPGOIDOID_INT2 = 21,
  ALNPGOIDOID_INT4 = 23,
  ALNPGOIDOID_TEXT = 25,
  ALNPGOIDOID_JSON = 114,
  ALNPGOIDOID_JSON_ARRAY = 199,
  ALNPGOIDOID_FLOAT4 = 700,
  ALNPGOIDOID_FLOAT8 = 701,
  ALNPGOIDOID_INT2_ARRAY = 1005,
  ALNPGOIDOID_INT4_ARRAY = 1007,
  ALNPGOIDOID_TEXT_ARRAY = 1009,
  ALNPGOIDOID_BPCHAR_ARRAY = 1014,
  ALNPGOIDOID_VARCHAR_ARRAY = 1015,
  ALNPGOIDOID_FLOAT4_ARRAY = 1021,
  ALNPGOIDOID_FLOAT8_ARRAY = 1022,
  ALNPGOIDOID_BPCHAR = 1042,
  ALNPGOIDOID_VARCHAR = 1043,
  ALNPGOIDOID_DATE = 1082,
  ALNPGOIDOID_TIME = 1083,
  ALNPGOIDOID_TIMESTAMP = 1114,
  ALNPGOIDOID_TIMESTAMP_ARRAY = 1115,
  ALNPGOIDOID_TIMESTAMPTZ = 1184,
  ALNPGOIDOID_DATE_ARRAY = 1182,
  ALNPGOIDOID_TIME_ARRAY = 1183,
  ALNPGOIDOID_TIMESTAMPTZ_ARRAY = 1185,
  ALNPGOIDOID_NUMERIC_ARRAY = 1231,
  ALNPGOIDOID_NUMERIC = 1700,
  ALNPGOIDOID_UUID = 2950,
  ALNPGOIDOID_UUID_ARRAY = 2951,
  ALNPGOIDOID_JSONB = 3802,
  ALNPGOIDOID_JSONB_ARRAY = 3807,
};

static BOOL ALNPgNSNumberLooksBoolean(NSNumber *value) {
  if (value == nil) {
    return NO;
  }
  const char *type = [value objCType];
  if (type == NULL) {
    return NO;
  }
  return (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, "B") == 0);
}

static NSString *ALNPgHexStringFromData(NSData *data) {
  if (![data isKindOfClass:[NSData class]]) {
    return @"";
  }
  const unsigned char *bytes = [data bytes];
  NSUInteger length = [data length];
  NSMutableString *hex = [NSMutableString stringWithCapacity:(length * 2) + 2];
  [hex appendString:@"\\x"];
  for (NSUInteger idx = 0; idx < length; idx++) {
    [hex appendFormat:@"%02x", bytes[idx]];
  }
  return hex;
}

static NSString *ALNPgTimestampStringFromDate(NSDate *value) {
  if (![value isKindOfClass:[NSDate class]]) {
    return @"";
  }
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
  return [formatter stringFromDate:value] ?: @"";
}

static NSString *ALNPgJSONStringFromObject(id value, NSError **error) {
  NSData *jsonData = [ALNJSONSerialization dataWithJSONObject:value options:0 error:error];
  if (jsonData == nil) {
    return nil;
  }
  NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
  if (json == nil && error != NULL) {
    *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                            @"failed to encode query parameter as JSON",
                            @"JSON payload was not valid UTF-8",
                            nil);
  }
  return json;
}

static NSString *ALNPgEscapedArrayStringLiteral(NSString *value) {
  NSString *escaped = [[value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
      stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  return [NSString stringWithFormat:@"\"%@\"", escaped ?: @""];
}

static NSString *ALNPgArrayElementString(id value, NSError **error) {
  if (value == nil || value == [NSNull null]) {
    return @"NULL";
  }
  if ([value isKindOfClass:[NSString class]]) {
    return ALNPgEscapedArrayStringLiteral((NSString *)value);
  }
  if ([value isKindOfClass:[NSUUID class]]) {
    return ALNPgEscapedArrayStringLiteral([(NSUUID *)value UUIDString] ?: @"");
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    if (ALNPgNSNumberLooksBoolean((NSNumber *)value)) {
      return [((NSNumber *)value) boolValue] ? @"true" : @"false";
    }
    return [value stringValue];
  }
  if ([value isKindOfClass:[NSDate class]]) {
    return ALNPgEscapedArrayStringLiteral(ALNPgTimestampStringFromDate((NSDate *)value));
  }
  if ([value isKindOfClass:[NSData class]]) {
    return ALNPgEscapedArrayStringLiteral(ALNPgHexStringFromData((NSData *)value));
  }
  if ([value isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"failed to encode query parameter as PostgreSQL array",
                              @"nested PostgreSQL array parameters are not supported",
                              nil);
    }
    return nil;
  }
  if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[ALNDatabaseJSONValue class]] ||
      [value isKindOfClass:[ALNDatabaseArrayValue class]]) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"failed to encode query parameter as PostgreSQL array",
                              @"array parameters only support scalar Foundation element values",
                              nil);
    }
    return nil;
  }
  return ALNPgEscapedArrayStringLiteral([value description] ?: @"");
}

static NSString *ALNPgArrayLiteralFromItems(NSArray *items, NSError **error) {
  if (items == nil) {
    return nil;
  }
  if (![items isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"failed to encode query parameter as PostgreSQL array",
                              @"array parameters must be NSArray instances",
                              nil);
    }
    return nil;
  }

  NSMutableArray<NSString *> *elements = [NSMutableArray arrayWithCapacity:[items count]];
  for (id item in items) {
    NSError *elementError = nil;
    NSString *element = ALNPgArrayElementString(item, &elementError);
    if (element == nil) {
      if (error != NULL) {
        *error = elementError;
      }
      return nil;
    }
    [elements addObject:element];
  }
  return [NSString stringWithFormat:@"{%@}", [elements componentsJoinedByString:@","]];
}

static NSString *ALNPgStringFromParam(id value, NSError **error) {
  if (value == nil || value == [NSNull null]) {
    return nil;
  }
  if ([value isKindOfClass:[ALNDatabaseJSONValue class]]) {
    return ALNPgJSONStringFromObject(((ALNDatabaseJSONValue *)value).object, error);
  }
  if ([value isKindOfClass:[ALNDatabaseArrayValue class]]) {
    return ALNPgArrayLiteralFromItems(((ALNDatabaseArrayValue *)value).items, error);
  }
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSUUID class]]) {
    return [(NSUUID *)value UUIDString];
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    if (ALNPgNSNumberLooksBoolean((NSNumber *)value)) {
      return [((NSNumber *)value) boolValue] ? @"true" : @"false";
    }
    return [value stringValue];
  }
  if ([value isKindOfClass:[NSDate class]]) {
    return ALNPgTimestampStringFromDate((NSDate *)value);
  }
  if ([value isKindOfClass:[NSData class]]) {
    return ALNPgHexStringFromData((NSData *)value);
  }
  if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]]) {
    return ALNPgJSONStringFromObject(value, error);
  }
  return [value description];
}

static NSNumber *ALNPgIntegerNumberFromString(NSString *value) {
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

static NSNumber *ALNPgDoubleNumberFromString(NSString *value) {
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

static NSDecimalNumber *ALNPgDecimalNumberFromString(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return nil;
  }
  NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:value];
  return [number isEqualToNumber:[NSDecimalNumber notANumber]] ? nil : number;
}

static NSNumber *ALNPgBoolNumberFromString(NSString *value) {
  NSString *normalized = [[value lowercaseString] stringByTrimmingCharactersInSet:
                                                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"t"] || [normalized isEqualToString:@"true"] ||
      [normalized isEqualToString:@"1"]) {
    return @YES;
  }
  if ([normalized isEqualToString:@"f"] || [normalized isEqualToString:@"false"] ||
      [normalized isEqualToString:@"0"]) {
    return @NO;
  }
  return nil;
}

static BOOL ALNPgParseFixedWidthNumber(const char *cursor,
                                       NSUInteger digitCount,
                                       NSInteger *valueOut);
static NSDate *ALNPgUTCDate(NSInteger year,
                            NSInteger month,
                            NSInteger day,
                            NSInteger hour,
                            NSInteger minute,
                            NSInteger second,
                            double fractionalSeconds);
static id ALNPgDecodedValueForFieldType(ALNOid fieldType,
                                        NSString *columnName,
                                        NSString *stringValue,
                                        NSError **error);

static NSDate *ALNPgDateFromDateString(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return nil;
  }

  NSString *trimmed =
      [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  const char *cursor = [trimmed UTF8String];
  if (cursor == NULL) {
    return nil;
  }

  NSInteger year = 0;
  NSInteger month = 0;
  NSInteger day = 0;
  if (!ALNPgParseFixedWidthNumber(cursor, 4, &year) || cursor[4] != '-' ||
      !ALNPgParseFixedWidthNumber(cursor + 5, 2, &month) || cursor[7] != '-' ||
      !ALNPgParseFixedWidthNumber(cursor + 8, 2, &day) || cursor[10] != '\0') {
    return nil;
  }

  return ALNPgUTCDate(year, month, day, 0, 0, 0, 0.0);
}

static BOOL ALNPgParseFixedWidthNumber(const char *cursor,
                                       NSUInteger digitCount,
                                       NSInteger *valueOut) {
  if (cursor == NULL || digitCount == 0) {
    return NO;
  }

  NSInteger parsed = 0;
  for (NSUInteger idx = 0; idx < digitCount; idx++) {
    if (!isdigit((unsigned char)cursor[idx])) {
      return NO;
    }
    parsed = (parsed * 10) + (cursor[idx] - '0');
  }

  if (valueOut != NULL) {
    *valueOut = parsed;
  }
  return YES;
}

static NSDate *ALNPgUTCDate(NSInteger year,
                            NSInteger month,
                            NSInteger day,
                            NSInteger hour,
                            NSInteger minute,
                            NSInteger second,
                            double fractionalSeconds) {
  NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
  calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

  NSDateComponents *components = [[NSDateComponents alloc] init];
  components.year = year;
  components.month = month;
  components.day = day;
  components.hour = hour;
  components.minute = minute;
  components.second = second;

  NSDate *date = [calendar dateFromComponents:components];
  if (date == nil) {
    return nil;
  }

  NSDateComponents *normalized =
      [calendar components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit |
                            NSHourCalendarUnit | NSMinuteCalendarUnit | NSSecondCalendarUnit)
                  fromDate:date];
  if (normalized.year != year || normalized.month != month || normalized.day != day ||
      normalized.hour != hour || normalized.minute != minute || normalized.second != second) {
    return nil;
  }

  if (fractionalSeconds != 0.0) {
    return [date dateByAddingTimeInterval:fractionalSeconds];
  }
  return date;
}

static NSDate *ALNPgDateFromTimestampString(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return nil;
  }

  NSString *trimmed =
      [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  const char *cursor = [trimmed UTF8String];
  if (cursor == NULL) {
    return nil;
  }

  NSInteger year = 0;
  NSInteger month = 0;
  NSInteger day = 0;
  NSInteger hour = 0;
  NSInteger minute = 0;
  NSInteger second = 0;

  if (!ALNPgParseFixedWidthNumber(cursor, 4, &year) || cursor[4] != '-' ||
      !ALNPgParseFixedWidthNumber(cursor + 5, 2, &month) || cursor[7] != '-' ||
      !ALNPgParseFixedWidthNumber(cursor + 8, 2, &day) ||
      (cursor[10] != ' ' && cursor[10] != 'T') ||
      !ALNPgParseFixedWidthNumber(cursor + 11, 2, &hour) || cursor[13] != ':' ||
      !ALNPgParseFixedWidthNumber(cursor + 14, 2, &minute) || cursor[16] != ':' ||
      !ALNPgParseFixedWidthNumber(cursor + 17, 2, &second)) {
    return nil;
  }

  cursor += 19;

  double fractionalSeconds = 0.0;
  if (*cursor == '.') {
    cursor += 1;
    if (!isdigit((unsigned char)*cursor)) {
      return nil;
    }
    double scale = 0.1;
    while (isdigit((unsigned char)*cursor)) {
      fractionalSeconds += ((*cursor - '0') * scale);
      scale /= 10.0;
      cursor += 1;
    }
  }

  while (*cursor == ' ') {
    cursor += 1;
  }

  NSInteger offsetHours = 0;
  NSInteger offsetMinutes = 0;
  NSInteger offsetSeconds = 0;
  NSInteger sign = 1;
  BOOL hasOffset = NO;
  if (*cursor == 'Z' || *cursor == 'z') {
    hasOffset = YES;
    cursor += 1;
  } else if (*cursor == '+' || *cursor == '-') {
    hasOffset = YES;
    sign = (*cursor == '-') ? -1 : 1;
    cursor += 1;
    if (!ALNPgParseFixedWidthNumber(cursor, 2, &offsetHours)) {
      return nil;
    }
    cursor += 2;
    if (*cursor == ':') {
      cursor += 1;
    }
    if (isdigit((unsigned char)*cursor)) {
      if (!ALNPgParseFixedWidthNumber(cursor, 2, &offsetMinutes)) {
        return nil;
      }
      cursor += 2;
      if (*cursor == ':') {
        cursor += 1;
        if (!ALNPgParseFixedWidthNumber(cursor, 2, &offsetSeconds)) {
          return nil;
        }
        cursor += 2;
      }
    }
  }

  while (*cursor == ' ') {
    cursor += 1;
  }
  if (*cursor != '\0') {
    return nil;
  }

  NSDate *date =
      ALNPgUTCDate(year, month, day, hour, minute, second, fractionalSeconds);
  if (date == nil) {
    return nil;
  }

  if (hasOffset) {
    NSInteger offset = ((offsetHours * 60 * 60) + (offsetMinutes * 60) + offsetSeconds) * sign;
    date = [date dateByAddingTimeInterval:-(NSTimeInterval)offset];
  }
  return date;
}

static NSData *ALNPgDataFromByteaString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *normalized = [value hasPrefix:@"\\x"] ? [value substringFromIndex:2] : value;
  if (([normalized length] % 2) != 0) {
    return nil;
  }
  NSMutableData *data = [NSMutableData dataWithCapacity:([normalized length] / 2)];
  for (NSUInteger idx = 0; idx < [normalized length]; idx += 2) {
    NSString *pair = [normalized substringWithRange:NSMakeRange(idx, 2)];
    NSScanner *scanner = [NSScanner scannerWithString:pair];
    unsigned int byte = 0;
    if (![scanner scanHexInt:&byte] || ![scanner isAtEnd]) {
      return nil;
    }
    unsigned char valueByte = (unsigned char)byte;
    [data appendBytes:&valueByte length:1];
  }
  return data;
}

static ALNOid ALNPgElementFieldTypeForArrayFieldType(ALNOid fieldType) {
  switch (fieldType) {
  case ALNPGOIDOID_BOOL_ARRAY:
    return ALNPGOIDOID_BOOL;
  case ALNPGOIDOID_BYTEA_ARRAY:
    return ALNPGOIDOID_BYTEA;
  case ALNPGOIDOID_INT2_ARRAY:
    return ALNPGOIDOID_INT2;
  case ALNPGOIDOID_INT4_ARRAY:
    return ALNPGOIDOID_INT4;
  case ALNPGOIDOID_TEXT_ARRAY:
    return ALNPGOIDOID_TEXT;
  case ALNPGOIDOID_JSON_ARRAY:
    return ALNPGOIDOID_JSON;
  case ALNPGOIDOID_FLOAT4_ARRAY:
    return ALNPGOIDOID_FLOAT4;
  case ALNPGOIDOID_FLOAT8_ARRAY:
    return ALNPGOIDOID_FLOAT8;
  case ALNPGOIDOID_BPCHAR_ARRAY:
    return ALNPGOIDOID_BPCHAR;
  case ALNPGOIDOID_VARCHAR_ARRAY:
    return ALNPGOIDOID_VARCHAR;
  case ALNPGOIDOID_DATE_ARRAY:
    return ALNPGOIDOID_DATE;
  case ALNPGOIDOID_TIME_ARRAY:
    return ALNPGOIDOID_TIME;
  case ALNPGOIDOID_TIMESTAMP_ARRAY:
    return ALNPGOIDOID_TIMESTAMP;
  case ALNPGOIDOID_TIMESTAMPTZ_ARRAY:
    return ALNPGOIDOID_TIMESTAMPTZ;
  case ALNPGOIDOID_NUMERIC_ARRAY:
    return ALNPGOIDOID_NUMERIC;
  case ALNPGOIDOID_UUID_ARRAY:
    return ALNPGOIDOID_UUID;
  case ALNPGOIDOID_JSONB_ARRAY:
    return ALNPGOIDOID_JSONB;
  default:
    return 0;
  }
}

static NSArray *ALNPgArrayTokensFromString(NSString *value, NSError **error) {
  if (![value isKindOfClass:[NSString class]]) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"failed decoding PostgreSQL array result",
                              @"array payload was not a string",
                              nil);
    }
    return nil;
  }

  NSString *trimmed =
      [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([trimmed length] < 2 || ![trimmed hasPrefix:@"{"] || ![trimmed hasSuffix:@"}"]) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"failed decoding PostgreSQL array result",
                              @"array payload was not wrapped in braces",
                              nil);
    }
    return nil;
  }
  if ([trimmed isEqualToString:@"{}"]) {
    return @[];
  }

  NSMutableArray *tokens = [NSMutableArray array];
  NSMutableString *buffer = [NSMutableString string];
  BOOL inQuotes = NO;
  BOOL escaping = NO;
  BOOL tokenStarted = NO;
  BOOL tokenQuoted = NO;
  BOOL afterQuotedToken = NO;

  for (NSUInteger idx = 1; idx + 1 < [trimmed length]; idx++) {
    unichar ch = [trimmed characterAtIndex:idx];
    if (inQuotes) {
      tokenStarted = YES;
      if (escaping) {
        [buffer appendFormat:@"%C", ch];
        escaping = NO;
        continue;
      }
      if (ch == '\\') {
        escaping = YES;
        continue;
      }
      if (ch == '"') {
        inQuotes = NO;
        afterQuotedToken = YES;
        continue;
      }
      [buffer appendFormat:@"%C", ch];
      continue;
    }

    if (afterQuotedToken) {
      if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:ch]) {
        continue;
      }
      if (ch != ',') {
        if (error != NULL) {
          *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                                  @"failed decoding PostgreSQL array result",
                                  @"quoted array element was followed by unexpected characters",
                                  nil);
        }
        return nil;
      }
    }

    if (ch == '"') {
      inQuotes = YES;
      tokenStarted = YES;
      tokenQuoted = YES;
      afterQuotedToken = NO;
      continue;
    }
    if (ch == '{' || ch == '}') {
      if (error != NULL) {
        *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                                @"failed decoding PostgreSQL array result",
                                @"nested PostgreSQL array values are not supported",
                                nil);
      }
      return nil;
    }
    if (ch == ',') {
      NSString *token = tokenQuoted ? [NSString stringWithString:buffer]
                                    : [[NSString stringWithString:buffer]
                                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (!tokenStarted && !tokenQuoted) {
        if (error != NULL) {
          *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                                  @"failed decoding PostgreSQL array result",
                                  @"array contained an empty unquoted element",
                                  nil);
        }
        return nil;
      }
      if (!tokenQuoted && [token isEqualToString:@"NULL"]) {
        [tokens addObject:[NSNull null]];
      } else {
        [tokens addObject:token ?: @""];
      }
      [buffer setString:@""];
      tokenStarted = NO;
      tokenQuoted = NO;
      afterQuotedToken = NO;
      continue;
    }

    tokenStarted = YES;
    [buffer appendFormat:@"%C", ch];
  }

  if (inQuotes || escaping) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"failed decoding PostgreSQL array result",
                              @"array payload ended inside a quoted element",
                              nil);
    }
    return nil;
  }

  NSString *token = tokenQuoted ? [NSString stringWithString:buffer]
                                : [[NSString stringWithString:buffer]
                                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (!tokenStarted && !tokenQuoted) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"failed decoding PostgreSQL array result",
                              @"array contained an empty trailing element",
                              nil);
    }
    return nil;
  }
  if (!tokenQuoted && [token isEqualToString:@"NULL"]) {
    [tokens addObject:[NSNull null]];
  } else {
    [tokens addObject:token ?: @""];
  }

  return [NSArray arrayWithArray:tokens];
}

static NSArray *ALNPgDecodedArrayValueForFieldType(ALNOid fieldType,
                                                   NSString *columnName,
                                                   NSString *stringValue,
                                                   NSError **error) {
  ALNOid elementType = ALNPgElementFieldTypeForArrayFieldType(fieldType);
  if (elementType == 0) {
    if (error != NULL) {
      NSString *detail = [NSString stringWithFormat:@"column %@ uses unsupported PostgreSQL array OID %u",
                                                    columnName ?: @"",
                                                    fieldType];
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"failed decoding PostgreSQL result value",
                              detail,
                              nil);
    }
    return nil;
  }

  NSError *tokenError = nil;
  NSArray *tokens = ALNPgArrayTokensFromString(stringValue, &tokenError);
  if (tokens == nil) {
    if (error != NULL) {
      *error = tokenError;
    }
    return nil;
  }

  NSMutableArray *decoded = [NSMutableArray arrayWithCapacity:[tokens count]];
  for (id token in tokens) {
    if (token == [NSNull null]) {
      [decoded addObject:[NSNull null]];
      continue;
    }
    NSError *elementError = nil;
    id element = ALNPgDecodedValueForFieldType(elementType, columnName, token, &elementError);
    if (element == nil) {
      if (error != NULL) {
        if (elementError != nil) {
          *error = elementError;
        } else {
          NSString *detail = [NSString stringWithFormat:@"column %@ array element could not be decoded",
                                                        columnName ?: @""];
          *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                                  @"failed decoding PostgreSQL result value",
                                  detail,
                                  nil);
        }
      }
      return nil;
    }
    [decoded addObject:element];
  }
  return [NSArray arrayWithArray:decoded];
}

static id ALNPgDecodedValueForFieldType(ALNOid fieldType,
                                        NSString *columnName,
                                        NSString *stringValue,
                                        NSError **error) {
  if (fieldType == 0) {
    return stringValue ?: @"";
  }

  id decoded = nil;
  switch (fieldType) {
  case ALNPGOIDOID_BOOL:
    decoded = ALNPgBoolNumberFromString(stringValue);
    break;
  case ALNPGOIDOID_INT2:
  case ALNPGOIDOID_INT4:
  case ALNPGOIDOID_INT8:
    decoded = ALNPgIntegerNumberFromString(stringValue);
    break;
  case ALNPGOIDOID_NUMERIC:
    decoded = ALNPgDecimalNumberFromString(stringValue);
    break;
  case ALNPGOIDOID_FLOAT4:
  case ALNPGOIDOID_FLOAT8:
    decoded = ALNPgDoubleNumberFromString(stringValue);
    break;
  case ALNPGOIDOID_DATE:
    decoded = ALNPgDateFromDateString(stringValue);
    break;
  case ALNPGOIDOID_TIMESTAMP:
  case ALNPGOIDOID_TIMESTAMPTZ:
    decoded = ALNPgDateFromTimestampString(stringValue);
    break;
  case ALNPGOIDOID_BYTEA:
    decoded = ALNPgDataFromByteaString(stringValue);
    break;
  case ALNPGOIDOID_JSON:
  case ALNPGOIDOID_JSONB: {
    NSData *jsonData = [stringValue dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    if (jsonData != nil) {
      decoded = [ALNJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
      if (decoded == nil && error != NULL && *error != nil) {
        NSError *jsonError = *error;
        NSString *detail = [NSString stringWithFormat:@"column %@ JSON decode failed: %@",
                                                      columnName ?: @"",
                                                      [jsonError localizedDescription] ?: @"invalid JSON"];
        *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                                @"failed decoding PostgreSQL result value",
                                detail,
                                nil);
      }
    }
    break;
  }
  case ALNPGOIDOID_BOOL_ARRAY:
  case ALNPGOIDOID_BYTEA_ARRAY:
  case ALNPGOIDOID_INT2_ARRAY:
  case ALNPGOIDOID_INT4_ARRAY:
  case ALNPGOIDOID_TEXT_ARRAY:
  case ALNPGOIDOID_JSON_ARRAY:
  case ALNPGOIDOID_FLOAT4_ARRAY:
  case ALNPGOIDOID_FLOAT8_ARRAY:
  case ALNPGOIDOID_BPCHAR_ARRAY:
  case ALNPGOIDOID_VARCHAR_ARRAY:
  case ALNPGOIDOID_DATE_ARRAY:
  case ALNPGOIDOID_TIME_ARRAY:
  case ALNPGOIDOID_TIMESTAMP_ARRAY:
  case ALNPGOIDOID_TIMESTAMPTZ_ARRAY:
  case ALNPGOIDOID_NUMERIC_ARRAY:
  case ALNPGOIDOID_UUID_ARRAY:
  case ALNPGOIDOID_JSONB_ARRAY:
    decoded = ALNPgDecodedArrayValueForFieldType(fieldType, columnName, stringValue, error);
    break;
  case ALNPGOIDOID_NAME:
  case ALNPGOIDOID_TEXT:
  case ALNPGOIDOID_BPCHAR:
  case ALNPGOIDOID_VARCHAR:
  case ALNPGOIDOID_UUID:
  case ALNPGOIDOID_TIME:
    return stringValue ?: @"";
  default:
    return stringValue ?: @"";
  }

  if (decoded != nil) {
    return decoded;
  }
  if (error != NULL && *error == nil) {
    NSString *detail = [NSString stringWithFormat:@"column %@ could not be decoded for PostgreSQL OID %u",
                                                  columnName ?: @"",
                                                  fieldType];
    *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                            @"failed decoding PostgreSQL result value",
                            detail,
                            nil);
  }
  return nil;
}

static void ALNPgFreeExecParamsBuffer(ALNPgExecParamsBuffer *buffer) {
  if (buffer == NULL) {
    return;
  }

  if (buffer->ownedParamValues != NULL) {
    for (NSUInteger idx = 0; idx < buffer->count; idx++) {
      if (buffer->ownedParamValues[idx] != NULL) {
        free(buffer->ownedParamValues[idx]);
      }
    }
    free(buffer->ownedParamValues);
  }
  if (buffer->paramValues != NULL) {
    free((void *)buffer->paramValues);
  }
  if (buffer->paramLengths != NULL) {
    free(buffer->paramLengths);
  }
  if (buffer->paramFormats != NULL) {
    free(buffer->paramFormats);
  }

  buffer->paramValues = NULL;
  buffer->ownedParamValues = NULL;
  buffer->paramLengths = NULL;
  buffer->paramFormats = NULL;
  buffer->count = 0;
}

static BOOL ALNPgBuildExecParamsBuffer(NSArray *parameters,
                                       NSString *sql,
                                       ALNPgExecParamsBuffer *buffer,
                                       NSError **error) {
  if (buffer == NULL) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"query parameter buffer is required",
                              nil,
                              sql);
    }
    return NO;
  }

  memset(buffer, 0, sizeof(*buffer));
  NSUInteger count = [parameters count];
  buffer->count = count;
  if (count == 0) {
    return YES;
  }

  buffer->paramValues = calloc(count, sizeof(const char *));
  buffer->ownedParamValues = calloc(count, sizeof(char *));
  buffer->paramLengths = calloc(count, sizeof(int));
  buffer->paramFormats = calloc(count, sizeof(int));
  if (buffer->paramValues == NULL || buffer->ownedParamValues == NULL ||
      buffer->paramLengths == NULL || buffer->paramFormats == NULL) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"failed to prepare query parameters",
                              @"parameter buffer allocation failed",
                              sql);
    }
    ALNPgFreeExecParamsBuffer(buffer);
    return NO;
  }

  for (NSUInteger idx = 0; idx < count; idx++) {
    id value = parameters[idx];
    NSError *parameterError = nil;
    NSString *stringValue = ALNPgStringFromParam(value, &parameterError);
    if (parameterError != nil) {
      if (error != NULL) {
        NSString *detail = [NSString stringWithFormat:@"parameter %lu: %@",
                                                      (unsigned long)(idx + 1),
                                                      [parameterError localizedDescription] ?: @"invalid value"];
        *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                                @"failed to encode query parameter",
                                detail,
                                sql);
      }
      ALNPgFreeExecParamsBuffer(buffer);
      return NO;
    }
    if (stringValue == nil) {
      buffer->paramValues[idx] = NULL;
      buffer->paramLengths[idx] = 0;
      buffer->paramFormats[idx] = 0;
      continue;
    }

    NSData *utf8 = [stringValue dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
    if (utf8 == nil) {
      if (error != NULL) {
        NSString *detail = [NSString stringWithFormat:@"parameter %lu is not valid UTF-8",
                                                      (unsigned long)(idx + 1)];
        *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                                @"failed to encode query parameter",
                                detail,
                                sql);
      }
      ALNPgFreeExecParamsBuffer(buffer);
      return NO;
    }

    NSUInteger utf8Length = [utf8 length];
    char *bytes = calloc(utf8Length + 1, sizeof(char));
    if (bytes == NULL) {
      if (error != NULL) {
        *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                                @"failed to prepare query parameters",
                                @"parameter value allocation failed",
                                sql);
      }
      ALNPgFreeExecParamsBuffer(buffer);
      return NO;
    }

    if (utf8Length > 0) {
      memcpy(bytes, [utf8 bytes], utf8Length);
    }
    bytes[utf8Length] = '\0';

    buffer->ownedParamValues[idx] = bytes;
    buffer->paramValues[idx] = bytes;
    // Text format parameters are consumed as C strings by libpq.
    buffer->paramLengths[idx] = 0;
    buffer->paramFormats[idx] = 0;
  }

  return YES;
}

static NSArray<NSString *> *ALNPgOrderedColumnNames(PGresult *result) {
  int fieldCount = ALNPQnfields(result);
  NSMutableArray<NSString *> *columns = [NSMutableArray arrayWithCapacity:(NSUInteger)fieldCount];
  for (int field = 0; field < fieldCount; field++) {
    const char *name = ALNPQfname(result, field);
    NSString *key = (name != NULL) ? [NSString stringWithUTF8String:name] : nil;
    if ([key length] == 0) {
      key = [NSString stringWithFormat:@"col_%d", field];
    }
    [columns addObject:key];
  }
  return [NSArray arrayWithArray:columns];
}

static id ALNPgDecodedFieldValue(PGresult *result,
                                 int rowIndex,
                                 int field,
                                 NSString *key,
                                 NSError **error) {
  if (ALNPQgetisnull(result, rowIndex, field)) {
    return [NSNull null];
  }

  const char *value = ALNPQgetvalue(result, rowIndex, field);
  if (value == NULL) {
    return [NSNull null];
  }

  NSString *stringValue = [NSString stringWithUTF8String:value];
  ALNOid fieldType = (ALNPQftype != NULL) ? ALNPQftype(result, field) : 0;
  NSError *decodeError = nil;
  id decoded = ALNPgDecodedValueForFieldType(fieldType, key, stringValue ?: @"", &decodeError);
  if (decoded == nil && decodeError != nil) {
    if (error != NULL) {
      *error = decodeError;
    }
    return nil;
  }
  return decoded ?: @"";
}

static NSDictionary *ALNPgRowDictionary(PGresult *result,
                                        NSArray<NSString *> *columnNames,
                                        int rowIndex,
                                        NSArray **orderedValuesOut,
                                        NSError **error) {
  int fieldCount = ALNPQnfields(result);
  NSMutableDictionary *row = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)fieldCount];
  NSMutableArray *orderedValues = [NSMutableArray arrayWithCapacity:(NSUInteger)fieldCount];
  for (int field = 0; field < fieldCount; field++) {
    NSString *key = (field < (int)[columnNames count]) ? columnNames[(NSUInteger)field] : [NSString stringWithFormat:@"col_%d", field];
    id decoded = ALNPgDecodedFieldValue(result, rowIndex, field, key, error);
    if (decoded == nil && error != NULL && *error != nil) {
      return nil;
    }
    row[key] = decoded ?: (id)[NSNull null];
    [orderedValues addObject:decoded ?: (id)[NSNull null]];
  }
  if (orderedValuesOut != NULL) {
    *orderedValuesOut = [NSArray arrayWithArray:orderedValues];
  }
  return row;
}

@interface ALNPgConnection () {
  PGconn *_conn;
  BOOL _inTransaction;
}

@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite, getter=isOpen) BOOL open;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *builderCompilationCache;
@property(nonatomic, strong) NSMutableArray<NSString *> *builderCompilationCacheOrder;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *preparedStatementNamesByKey;
@property(nonatomic, strong) NSMutableArray<NSString *> *preparedStatementCacheOrder;
@property(nonatomic, assign) NSUInteger preparedStatementSequence;

- (BOOL)hasActiveTransaction;
- (BOOL)checkConnectionLiveness:(NSError **)error;
- (BOOL)deallocatePreparedStatementNamed:(NSString *)name error:(NSError **)error;

@end

@implementation ALNPgConnection

- (instancetype)initWithConnectionString:(NSString *)connectionString
                                   error:(NSError **)error {
  self = [super init];
  if (!self) {
    return nil;
  }

  ALNPgClearError(error);

  if ([connectionString length] == 0) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"connection string is required",
                              nil,
                              nil);
    }
    return nil;
  }

  if (!ALNLoadLibpq(error)) {
    return nil;
  }

  _connectionString = [connectionString copy];
  _conn = ALNPQconnectdb([_connectionString UTF8String]);
  if (_conn == NULL || ALNPQstatus(_conn) != ALNConnectionOK) {
    NSString *detail = nil;
    if (_conn != NULL) {
      const char *message = ALNPQerrorMessage(_conn);
      if (message != NULL) {
        detail = [NSString stringWithUTF8String:message];
      }
      ALNPQfinish(_conn);
      _conn = NULL;
    }
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorConnectionFailed,
                              @"failed to connect to PostgreSQL",
                              detail,
                              nil);
    }
    return nil;
  }

  _open = YES;
  _inTransaction = NO;
  _preparedStatementReusePolicy = ALNPgPreparedStatementReusePolicyAuto;
  _preparedStatementCacheLimit = 128;
  _builderCompilationCacheLimit = 128;
  _includeSQLInDiagnosticsEvents = NO;
  _emitDiagnosticsEventsToStderr = NO;
  _queryDiagnosticsListener = nil;
  _builderCompilationCache = [NSMutableDictionary dictionary];
  _builderCompilationCacheOrder = [NSMutableArray array];
  _preparedStatementNamesByKey = [NSMutableDictionary dictionary];
  _preparedStatementCacheOrder = [NSMutableArray array];
  _preparedStatementSequence = 0;
  return self;
}

- (void)dealloc {
  [self close];
}

- (void)close {
  if (_conn != NULL) {
    ALNPQfinish(_conn);
    _conn = NULL;
  }
  [self resetExecutionCaches];
  self.open = NO;
  _inTransaction = NO;
}

- (nullable NSError *)checkOpenError {
  if (_conn == NULL || !self.isOpen) {
    return ALNPgMakeError(ALNPgErrorConnectionFailed,
                          @"connection is closed",
                          nil,
                          nil);
  }
  return nil;
}

- (BOOL)hasActiveTransaction {
  return _inTransaction;
}

- (BOOL)checkConnectionLiveness:(NSError **)error {
  ALNPgClearError(error);
  NSError *openError = [self checkOpenError];
  if (openError != nil) {
    if (error != NULL) {
      *error = openError;
    }
    return NO;
  }

  PGresult *result = ALNPQexec(_conn, "SELECT 1");
  if (result == NULL) {
    if (error != NULL) {
      NSString *detail = [NSString stringWithUTF8String:ALNPQerrorMessage(_conn) ?: ""];
      *error = ALNPgMakeError(ALNPgErrorConnectionFailed,
                              @"connection liveness check failed",
                              detail,
                              @"SELECT 1");
    }
    return NO;
  }

  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_TUPLES_OK && status != ALNPGRES_COMMAND_OK) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQresultErrorMessage(result) ?: ""];
    NSDictionary *diagnostics = ALNPgDiagnosticsFromResult(result);
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeErrorWithDiagnostics(ALNPgErrorConnectionFailed,
                                             @"connection liveness check failed",
                                             detail,
                                             @"SELECT 1",
                                             diagnostics);
    }
    return NO;
  }

  ALNPQclear(result);
  return YES;
}

- (void)resetExecutionCaches {
  if (_conn != NULL && self.isOpen) {
    PGresult *result = ALNPQexec(_conn, "DEALLOCATE ALL");
    if (result != NULL) {
      ALNPQclear(result);
    }
  }
  [self.builderCompilationCache removeAllObjects];
  [self.builderCompilationCacheOrder removeAllObjects];
  [self.preparedStatementNamesByKey removeAllObjects];
  [self.preparedStatementCacheOrder removeAllObjects];
  self.preparedStatementSequence = 0;
}

- (BOOL)shouldUsePreparedStatementForParameterCount:(NSUInteger)parameterCount {
  switch (self.preparedStatementReusePolicy) {
  case ALNPgPreparedStatementReusePolicyAlways:
    return YES;
  case ALNPgPreparedStatementReusePolicyAuto:
    return (parameterCount > 0);
  case ALNPgPreparedStatementReusePolicyDisabled:
  default:
    return NO;
  }
}

- (NSMutableDictionary *)baseQueryEventWithStage:(NSString *)stage
                                          source:(NSString *)source
                                       operation:(NSString *)operation
                                   executionMode:(NSString *)executionMode
                                             sql:(NSString *)sql
                                      parameters:(NSArray *)parameters {
  NSMutableDictionary *event = [NSMutableDictionary dictionary];
  event[ALNPgQueryEventStageKey] = stage ?: @"";
  event[ALNPgQueryEventSourceKey] = source ?: @"";
  event[ALNPgQueryEventOperationKey] = operation ?: @"";
  event[ALNPgQueryEventExecutionModeKey] = executionMode ?: @"";
  event[ALNPgQueryEventSQLHashKey] = ALNPgSQLHash(sql ?: @"");
  event[ALNPgQueryEventSQLLengthKey] = @([sql length]);
  event[ALNPgQueryEventParameterCountKey] = @([parameters count]);
  NSString *token = ALNPgSQLToken(sql ?: @"");
  if ([token length] > 0) {
    event[ALNPgQueryEventSQLTokenKey] = token;
  }
  if (self.includeSQLInDiagnosticsEvents && [sql length] > 0) {
    event[ALNPgQueryEventSQLKey] = sql;
  }
  return event;
}

- (void)emitQueryEvent:(NSDictionary *)event {
  NSDictionary *immutable = [NSDictionary dictionaryWithDictionary:event ?: @{}];
  ALNPgQueryDiagnosticsListener listener = self.queryDiagnosticsListener;
  if (listener != nil) {
    listener(immutable);
  }
  if (self.emitDiagnosticsEventsToStderr) {
    ALNPgEmitEventToStderr(immutable);
  }
}

- (nullable NSDictionary *)compiledBuilder:(ALNSQLBuilder *)builder
                                  cacheHit:(BOOL *)cacheHit
                                     error:(NSError **)error {
  ALNPgClearError(error);
  if (![builder isKindOfClass:[ALNSQLBuilder class]]) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"builder must be an ALNSQLBuilder",
                              nil,
                              nil);
    }
    return nil;
  }

  if (cacheHit != NULL) {
    *cacheHit = NO;
  }

  NSString *signature = ALNPgBuilderCompilationSignature(builder);
  if ([signature length] > 0) {
    NSDictionary *cached = self.builderCompilationCache[signature];
    if ([cached isKindOfClass:[NSDictionary class]]) {
      if (cacheHit != NULL) {
        *cacheHit = YES;
      }
      return cached;
    }
  }

  NSError *buildError = nil;
  NSDictionary *built = [builder buildWithDialect:[ALNPostgresDialect sharedDialect] error:&buildError];
  if (built == nil) {
    if (error != NULL) {
      *error = buildError ?: ALNPgMakeError(ALNPgErrorQueryFailed,
                                            @"builder compilation failed",
                                            nil,
                                            nil);
    }
    return nil;
  }

  NSString *sql = [built[@"sql"] isKindOfClass:[NSString class]] ? built[@"sql"] : @"";
  NSArray *parameters = [built[@"parameters"] isKindOfClass:[NSArray class]] ? built[@"parameters"] : @[];
  if ([sql length] == 0) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"builder produced empty SQL",
                              nil,
                              nil);
    }
    return nil;
  }

  NSDictionary *normalized = @{
    @"sql" : sql,
    @"parameters" : [NSArray arrayWithArray:parameters],
  };

  if ([signature length] > 0 && self.builderCompilationCacheLimit > 0) {
    if (self.builderCompilationCache[signature] == nil &&
        [self.builderCompilationCache count] >= self.builderCompilationCacheLimit) {
      NSString *oldest = [self.builderCompilationCacheOrder firstObject];
      if ([oldest length] > 0) {
        [self.builderCompilationCache removeObjectForKey:oldest];
        [self.builderCompilationCacheOrder removeObjectAtIndex:0];
      }
    }
    self.builderCompilationCache[signature] = normalized;
    [self.builderCompilationCacheOrder removeObject:signature];
    [self.builderCompilationCacheOrder addObject:signature];
  }

  return normalized;
}

- (nullable NSString *)preparedStatementNameForSQL:(NSString *)sql
                                     parameterCount:(NSUInteger)parameterCount
                                          operation:(NSString *)operation
                                           cacheHit:(BOOL *)cacheHit
                                          cacheFull:(BOOL *)cacheFull
                                              error:(NSError **)error {
  ALNPgClearError(error);
  if (cacheHit != NULL) {
    *cacheHit = NO;
  }
  if (cacheFull != NULL) {
    *cacheFull = NO;
  }

  NSString *normalizedOperation = [operation isKindOfClass:[NSString class]] ? operation : @"query";
  NSString *key = [NSString stringWithFormat:@"%@|%lu|%@",
                                             normalizedOperation,
                                             (unsigned long)parameterCount,
                                             sql ?: @""];
  NSString *cachedName = self.preparedStatementNamesByKey[key];
  if ([cachedName length] > 0) {
    [self.preparedStatementCacheOrder removeObject:key];
    [self.preparedStatementCacheOrder addObject:key];
    if (cacheHit != NULL) {
      *cacheHit = YES;
    }
    return cachedName;
  }

  if (self.preparedStatementCacheLimit > 0 &&
      [self.preparedStatementNamesByKey count] >= self.preparedStatementCacheLimit) {
    if (cacheFull != NULL) {
      *cacheFull = YES;
    }
    NSString *oldestKey = [self.preparedStatementCacheOrder firstObject];
    NSString *oldestName = self.preparedStatementNamesByKey[oldestKey];
    if ([oldestKey length] > 0) {
      NSError *evictionError = nil;
      if (![self deallocatePreparedStatementNamed:oldestName error:&evictionError]) {
        if (error != NULL) {
          *error = evictionError;
        }
        return nil;
      }
      [self.preparedStatementNamesByKey removeObjectForKey:oldestKey];
      [self.preparedStatementCacheOrder removeObjectAtIndex:0];
    }
  }

  self.preparedStatementSequence += 1;
  NSString *nameHash = ALNPgSQLHash(key);
  NSString *statementName =
      [NSString stringWithFormat:@"aln_%@_%lu",
                                 [nameHash substringToIndex:MIN((NSUInteger)10, [nameHash length])],
                                 (unsigned long)self.preparedStatementSequence];
  NSError *prepareError = nil;
  BOOL prepared = [self prepareStatementNamed:statementName
                                          sql:sql ?: @""
                               parameterCount:(NSInteger)parameterCount
                                        error:&prepareError];
  if (!prepared) {
    if (error != NULL) {
      *error = prepareError;
    }
    return nil;
  }

  self.preparedStatementNamesByKey[key] = statementName;
  [self.preparedStatementCacheOrder removeObject:key];
  [self.preparedStatementCacheOrder addObject:key];
  return statementName;
}

- (BOOL)deallocatePreparedStatementNamed:(NSString *)name error:(NSError **)error {
  ALNPgClearError(error);
  NSError *openError = [self checkOpenError];
  if (openError != nil) {
    if (error != NULL) {
      *error = openError;
    }
    return NO;
  }
  if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
    return YES;
  }

  NSString *sql = [NSString stringWithFormat:@"DEALLOCATE %@", name];
  PGresult *result = ALNPQexec(_conn, [sql UTF8String]);
  if (result == NULL) {
    if (error != NULL) {
      NSString *detail = [NSString stringWithUTF8String:ALNPQerrorMessage(_conn) ?: ""];
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"failed to deallocate prepared statement",
                              detail,
                              sql);
    }
    return NO;
  }

  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_COMMAND_OK) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQresultErrorMessage(result) ?: ""];
    NSDictionary *diagnostics = ALNPgDiagnosticsFromResult(result);
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeErrorWithDiagnostics(ALNPgErrorQueryFailed,
                                             @"failed to deallocate prepared statement",
                                             detail,
                                             sql,
                                             diagnostics);
    }
    return NO;
  }

  ALNPQclear(result);
  return YES;
}

- (BOOL)prepareStatementNamed:(NSString *)name
                          sql:(NSString *)sql
               parameterCount:(NSInteger)parameterCount
                        error:(NSError **)error {
  ALNPgClearError(error);
  NSError *openError = [self checkOpenError];
  if (openError != nil) {
    if (error != NULL) {
      *error = openError;
    }
    return NO;
  }
  if ([name length] == 0 || [sql length] == 0 || parameterCount < 0) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"invalid prepare statement arguments",
                              nil,
                              sql);
    }
    return NO;
  }

  PGresult *result = ALNPQprepare(_conn,
                               [name UTF8String],
                               [sql UTF8String],
                               (int)parameterCount,
                               NULL);
  if (result == NULL) {
    if (error != NULL) {
      NSString *detail = [NSString stringWithUTF8String:ALNPQerrorMessage(_conn) ?: ""];
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"failed to prepare statement",
                              detail,
                              sql);
    }
    return NO;
  }
  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_COMMAND_OK) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQresultErrorMessage(result) ?: ""];
    NSDictionary *diagnostics = ALNPgDiagnosticsFromResult(result);
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeErrorWithDiagnostics(ALNPgErrorQueryFailed,
                                             @"failed to prepare statement",
                                             detail,
                                             sql,
                                             diagnostics);
    }
    return NO;
  }
  ALNPQclear(result);
  return YES;
}

- (PGresult *)runExecParamsSQL:(NSString *)sql
                    parameters:(NSArray *)parameters
                         error:(NSError **)error {
  ALNPgClearError(error);
  NSError *openError = [self checkOpenError];
  if (openError != nil) {
    if (error != NULL) {
      *error = openError;
    }
    return NULL;
  }
  if ([sql length] == 0) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"sql must not be empty",
                              nil,
                              sql);
    }
    return NULL;
  }

  NSUInteger count = [parameters count];
  ALNPgExecParamsBuffer paramBuffer;
  if (!ALNPgBuildExecParamsBuffer(parameters ?: @[], sql, &paramBuffer, error)) {
    return NULL;
  }

  PGresult *result = ALNPQexecParams(_conn,
                                  [sql UTF8String],
                                  (int)count,
                                  NULL,
                                  paramBuffer.paramValues,
                                  paramBuffer.paramLengths,
                                  paramBuffer.paramFormats,
                                  0);
  ALNPgFreeExecParamsBuffer(&paramBuffer);

  if (result == NULL) {
    if (error != NULL) {
      NSString *detail = [NSString stringWithUTF8String:ALNPQerrorMessage(_conn) ?: ""];
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"query execution failed",
                              detail,
                              sql);
    }
    return NULL;
  }

  return result;
}

- (PGresult *)runExecScriptSQL:(NSString *)sql error:(NSError **)error {
  ALNPgClearError(error);
  NSError *openError = [self checkOpenError];
  if (openError != nil) {
    if (error != NULL) {
      *error = openError;
    }
    return NULL;
  }
  if ([sql length] == 0) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"sql script must not be empty",
                              nil,
                              sql);
    }
    return NULL;
  }

  PGresult *result = ALNPQexec(_conn, [sql UTF8String]);
  if (result == NULL) {
    if (error != NULL) {
      NSString *detail = [NSString stringWithUTF8String:ALNPQerrorMessage(_conn) ?: ""];
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"script execution failed",
                              detail,
                              sql);
    }
    return NULL;
  }

  return result;
}

- (PGresult *)runExecPreparedNamed:(NSString *)name
                        parameters:(NSArray *)parameters
                             error:(NSError **)error {
  ALNPgClearError(error);
  NSError *openError = [self checkOpenError];
  if (openError != nil) {
    if (error != NULL) {
      *error = openError;
    }
    return NULL;
  }
  if ([name length] == 0) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"prepared statement name is required",
                              nil,
                              nil);
    }
    return NULL;
  }

  NSUInteger count = [parameters count];
  ALNPgExecParamsBuffer paramBuffer;
  if (!ALNPgBuildExecParamsBuffer(parameters ?: @[], name, &paramBuffer, error)) {
    return NULL;
  }

  PGresult *result = ALNPQexecPrepared(_conn,
                                    [name UTF8String],
                                    (int)count,
                                    paramBuffer.paramValues,
                                    paramBuffer.paramLengths,
                                    paramBuffer.paramFormats,
                                    0);
  ALNPgFreeExecParamsBuffer(&paramBuffer);

  if (result == NULL && error != NULL) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQerrorMessage(_conn) ?: ""];
    *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                            @"prepared statement execution failed",
                            detail,
                            name);
  }
  return result;
}

- (NSArray<NSDictionary *> *)rowsFromResult:(PGresult *)result error:(NSError **)error {
  int rowCount = ALNPQntuples(result);
  NSArray<NSString *> *columnNames = ALNPgOrderedColumnNames(result);
  NSMutableArray *rows = [NSMutableArray arrayWithCapacity:(NSUInteger)rowCount];
  for (int idx = 0; idx < rowCount; idx++) {
    NSDictionary *row = ALNPgRowDictionary(result, columnNames, idx, NULL, error);
    if (row == nil) {
      return nil;
    }
    [rows addObject:row];
  }
  return rows;
}

- (ALNDatabaseResult *)databaseResultFromResult:(PGresult *)result error:(NSError **)error {
  int rowCount = ALNPQntuples(result);
  NSArray<NSString *> *columnNames = ALNPgOrderedColumnNames(result);
  NSMutableArray<NSDictionary *> *rows = [NSMutableArray arrayWithCapacity:(NSUInteger)rowCount];
  NSMutableArray<NSArray *> *orderedValues = [NSMutableArray arrayWithCapacity:(NSUInteger)rowCount];
  for (int idx = 0; idx < rowCount; idx++) {
    NSArray *rowValues = nil;
    NSDictionary *row = ALNPgRowDictionary(result, columnNames, idx, &rowValues, error);
    if (row == nil) {
      return nil;
    }
    [rows addObject:row];
    [orderedValues addObject:rowValues ?: @[]];
  }
  return ALNDatabaseResultFromRowsWithOrderedColumns(rows, columnNames, orderedValues);
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  ALNPgClearError(error);
  PGresult *result = [self runExecParamsSQL:sql parameters:parameters ?: @[] error:error];
  if (result == NULL) {
    return nil;
  }

  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_TUPLES_OK) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQresultErrorMessage(result) ?: ""];
    NSDictionary *diagnostics = ALNPgDiagnosticsFromResult(result);
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeErrorWithDiagnostics(ALNPgErrorQueryFailed,
                                             @"query did not return rows",
                                             detail,
                                             sql,
                                             diagnostics);
    }
    return nil;
  }

  NSArray *rows = [self rowsFromResult:result error:error];
  ALNPQclear(result);
  return rows;
}

- (NSDictionary *)executeQueryOne:(NSString *)sql
                       parameters:(NSArray *)parameters
                            error:(NSError **)error {
  ALNPgClearError(error);
  NSArray *rows = [self executeQuery:sql parameters:parameters error:error];
  if (rows == nil || [rows count] == 0) {
    return nil;
  }
  return rows[0];
}

- (ALNDatabaseResult *)executeQueryResult:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  ALNPgClearError(error);
  PGresult *result = [self runExecParamsSQL:sql parameters:parameters ?: @[] error:error];
  if (result == NULL) {
    return nil;
  }

  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_TUPLES_OK) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQresultErrorMessage(result) ?: ""];
    NSDictionary *diagnostics = ALNPgDiagnosticsFromResult(result);
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeErrorWithDiagnostics(ALNPgErrorQueryFailed,
                                             @"query did not return rows",
                                             detail,
                                             sql,
                                             diagnostics);
    }
    return nil;
  }

  ALNDatabaseResult *rows = [self databaseResultFromResult:result error:error];
  ALNPQclear(result);
  return rows;
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  ALNPgClearError(error);
  PGresult *result = [self runExecParamsSQL:sql parameters:parameters ?: @[] error:error];
  if (result == NULL) {
    return -1;
  }

  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_COMMAND_OK && status != ALNPGRES_TUPLES_OK) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQresultErrorMessage(result) ?: ""];
    NSDictionary *diagnostics = ALNPgDiagnosticsFromResult(result);
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeErrorWithDiagnostics(ALNPgErrorQueryFailed,
                                             @"command execution failed",
                                             detail,
                                             sql,
                                             diagnostics);
    }
    return -1;
  }

  const char *tuples = ALNPQcmdTuples(result);
  NSInteger affected = 0;
  if (tuples != NULL && tuples[0] != '\0') {
    affected = (NSInteger)strtol(tuples, NULL, 10);
  } else if (status == ALNPGRES_TUPLES_OK) {
    affected = (NSInteger)ALNPQntuples(result);
  }
  ALNPQclear(result);
  return affected;
}

- (NSArray<NSDictionary *> *)executePreparedQueryNamed:(NSString *)name
                                            parameters:(NSArray *)parameters
                                                 error:(NSError **)error {
  ALNPgClearError(error);
  PGresult *result = [self runExecPreparedNamed:name parameters:parameters ?: @[] error:error];
  if (result == NULL) {
    return nil;
  }

  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_TUPLES_OK) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQresultErrorMessage(result) ?: ""];
    NSDictionary *diagnostics = ALNPgDiagnosticsFromResult(result);
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeErrorWithDiagnostics(ALNPgErrorQueryFailed,
                                             @"prepared query did not return rows",
                                             detail,
                                             name,
                                             diagnostics);
    }
    return nil;
  }

  NSArray *rows = [self rowsFromResult:result error:error];
  ALNPQclear(result);
  return rows;
}

- (NSInteger)executePreparedCommandNamed:(NSString *)name
                              parameters:(NSArray *)parameters
                                   error:(NSError **)error {
  ALNPgClearError(error);
  PGresult *result = [self runExecPreparedNamed:name parameters:parameters ?: @[] error:error];
  if (result == NULL) {
    return -1;
  }

  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_COMMAND_OK && status != ALNPGRES_TUPLES_OK) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQresultErrorMessage(result) ?: ""];
    NSDictionary *diagnostics = ALNPgDiagnosticsFromResult(result);
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeErrorWithDiagnostics(ALNPgErrorQueryFailed,
                                             @"prepared command execution failed",
                                             detail,
                                             name,
                                             diagnostics);
    }
    return -1;
  }

  const char *tuples = ALNPQcmdTuples(result);
  NSInteger affected = 0;
  if (tuples != NULL && tuples[0] != '\0') {
    affected = (NSInteger)strtol(tuples, NULL, 10);
  } else if (status == ALNPGRES_TUPLES_OK) {
    affected = (NSInteger)ALNPQntuples(result);
  }
  ALNPQclear(result);
  return affected;
}

- (NSInteger)executeCommandBatch:(NSString *)sql
                   parameterSets:(NSArray<NSArray *> *)parameterSets
                           error:(NSError **)error {
  ALNPgClearError(error);
  if (parameterSets != nil && ![parameterSets isKindOfClass:[NSArray class]]) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
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
        *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
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

- (BOOL)executeScript:(NSString *)sql error:(NSError **)error {
  ALNPgClearError(error);
  PGresult *result = [self runExecScriptSQL:sql error:error];
  if (result == NULL) {
    return NO;
  }

  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status == ALNPGRES_COMMAND_OK || status == ALNPGRES_TUPLES_OK) {
    ALNPQclear(result);
    return YES;
  }

  NSString *detail = [NSString stringWithUTF8String:ALNPQresultErrorMessage(result) ?: ""];
  NSDictionary *diagnostics = ALNPgDiagnosticsFromResult(result);
  ALNPQclear(result);
  if (error != NULL) {
    NSString *message = (status == ALNPGRES_EMPTY_QUERY) ? @"script does not contain executable SQL"
                                                         : @"script execution failed";
    ALNPgErrorCode code =
        (status == ALNPGRES_EMPTY_QUERY) ? ALNPgErrorInvalidArgument : ALNPgErrorQueryFailed;
    *error = ALNPgMakeErrorWithDiagnostics(code, message, detail, sql, diagnostics);
  }
  return NO;
}

- (NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder
                                            error:(NSError **)error {
  ALNPgClearError(error);
  NSArray *normalizedParameters = @[];
  NSString *sql = @"";
  NSError *compileError = nil;
  BOOL compileCacheHit = NO;
  NSTimeInterval compileStarted = [NSDate timeIntervalSinceReferenceDate];
  NSDictionary *compiled = [self compiledBuilder:builder
                                        cacheHit:&compileCacheHit
                                           error:&compileError];
  NSTimeInterval compileDurationMS =
      ([NSDate timeIntervalSinceReferenceDate] - compileStarted) * 1000.0;
  if ([compiled isKindOfClass:[NSDictionary class]]) {
    sql = [compiled[@"sql"] isKindOfClass:[NSString class]] ? compiled[@"sql"] : @"";
    normalizedParameters =
        [compiled[@"parameters"] isKindOfClass:[NSArray class]] ? compiled[@"parameters"] : @[];
  }

  NSMutableDictionary *compileEvent = [self baseQueryEventWithStage:ALNPgQueryStageCompile
                                                              source:@"builder"
                                                           operation:@"query"
                                                       executionMode:@"compile"
                                                                 sql:sql
                                                          parameters:normalizedParameters];
  compileEvent[ALNPgQueryEventCacheHitKey] = @(compileCacheHit);
  compileEvent[ALNPgQueryEventDurationMSKey] = @(compileDurationMS);
  if (compileError != nil) {
    compileEvent[ALNPgQueryEventErrorDomainKey] = compileError.domain ?: @"";
    compileEvent[ALNPgQueryEventErrorCodeKey] = @(compileError.code);
  }
  [self emitQueryEvent:compileEvent];

  if (compiled == nil) {
    if (error != NULL) {
      *error = compileError;
    }
    NSMutableDictionary *errorEvent = [self baseQueryEventWithStage:ALNPgQueryStageError
                                                              source:@"builder"
                                                           operation:@"query"
                                                       executionMode:@"compile"
                                                                 sql:sql
                                                          parameters:normalizedParameters];
    if (compileError != nil) {
      errorEvent[ALNPgQueryEventErrorDomainKey] = compileError.domain ?: @"";
      errorEvent[ALNPgQueryEventErrorCodeKey] = @(compileError.code);
      NSString *sqlState =
          [compileError.userInfo[ALNPgErrorSQLStateKey] isKindOfClass:[NSString class]]
              ? compileError.userInfo[ALNPgErrorSQLStateKey]
              : @"";
      if ([sqlState length] > 0) {
        errorEvent[ALNPgErrorSQLStateKey] = sqlState;
      }
    }
    [self emitQueryEvent:errorEvent];
    return nil;
  }

  BOOL shouldPrepare = [self shouldUsePreparedStatementForParameterCount:[normalizedParameters count]];
  BOOL preparedCacheHit = NO;
  BOOL preparedCacheFull = NO;
  NSString *preparedName = nil;
  NSError *prepareError = nil;
  if (shouldPrepare) {
    preparedName = [self preparedStatementNameForSQL:sql
                                      parameterCount:[normalizedParameters count]
                                           operation:@"query"
                                            cacheHit:&preparedCacheHit
                                           cacheFull:&preparedCacheFull
                                               error:&prepareError];
  }

  NSString *executionMode = ([preparedName length] > 0) ? @"prepared" : @"direct";
  NSMutableDictionary *executeEvent = [self baseQueryEventWithStage:ALNPgQueryStageExecute
                                                              source:@"builder"
                                                           operation:@"query"
                                                       executionMode:executionMode
                                                                 sql:sql
                                                          parameters:normalizedParameters];
  if ([preparedName length] > 0) {
    executeEvent[ALNPgQueryEventPreparedStatementKey] = preparedName;
    executeEvent[ALNPgQueryEventCacheHitKey] = @(preparedCacheHit);
  }
  if (preparedCacheFull) {
    executeEvent[ALNPgQueryEventCacheFullKey] = @YES;
  }
  [self emitQueryEvent:executeEvent];

  if (prepareError != nil) {
    if (error != NULL) {
      *error = prepareError;
    }
    NSMutableDictionary *errorEvent = [self baseQueryEventWithStage:ALNPgQueryStageError
                                                              source:@"builder"
                                                           operation:@"query"
                                                       executionMode:@"prepare"
                                                                 sql:sql
                                                          parameters:normalizedParameters];
    errorEvent[ALNPgQueryEventErrorDomainKey] = prepareError.domain ?: @"";
    errorEvent[ALNPgQueryEventErrorCodeKey] = @(prepareError.code);
    [self emitQueryEvent:errorEvent];
    return nil;
  }

  NSError *queryError = nil;
  NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
  NSArray *rows = nil;
  if ([preparedName length] > 0) {
    rows = [self executePreparedQueryNamed:preparedName
                                parameters:normalizedParameters
                                     error:&queryError];
  } else {
    rows = [self executeQuery:sql parameters:normalizedParameters error:&queryError];
  }
  NSTimeInterval durationMS = ([NSDate timeIntervalSinceReferenceDate] - started) * 1000.0;

  if (rows == nil) {
    if (error != NULL) {
      *error = queryError;
    }
    NSMutableDictionary *errorEvent = [self baseQueryEventWithStage:ALNPgQueryStageError
                                                              source:@"builder"
                                                           operation:@"query"
                                                       executionMode:executionMode
                                                                 sql:sql
                                                          parameters:normalizedParameters];
    errorEvent[ALNPgQueryEventDurationMSKey] = @(durationMS);
    if ([preparedName length] > 0) {
      errorEvent[ALNPgQueryEventPreparedStatementKey] = preparedName;
      errorEvent[ALNPgQueryEventCacheHitKey] = @(preparedCacheHit);
    }
    if (preparedCacheFull) {
      errorEvent[ALNPgQueryEventCacheFullKey] = @YES;
    }
    if (queryError != nil) {
      errorEvent[ALNPgQueryEventErrorDomainKey] = queryError.domain ?: @"";
      errorEvent[ALNPgQueryEventErrorCodeKey] = @(queryError.code);
      NSString *sqlState =
          [queryError.userInfo[ALNPgErrorSQLStateKey] isKindOfClass:[NSString class]]
              ? queryError.userInfo[ALNPgErrorSQLStateKey]
              : @"";
      if ([sqlState length] > 0) {
        errorEvent[ALNPgErrorSQLStateKey] = sqlState;
      }
    }
    [self emitQueryEvent:errorEvent];
    return nil;
  }

  NSMutableDictionary *resultEvent = [self baseQueryEventWithStage:ALNPgQueryStageResult
                                                             source:@"builder"
                                                          operation:@"query"
                                                      executionMode:executionMode
                                                                sql:sql
                                                         parameters:normalizedParameters];
  resultEvent[ALNPgQueryEventDurationMSKey] = @(durationMS);
  resultEvent[ALNPgQueryEventRowCountKey] = @([rows count]);
  if ([preparedName length] > 0) {
    resultEvent[ALNPgQueryEventPreparedStatementKey] = preparedName;
    resultEvent[ALNPgQueryEventCacheHitKey] = @(preparedCacheHit);
  }
  if (preparedCacheFull) {
    resultEvent[ALNPgQueryEventCacheFullKey] = @YES;
  }
  [self emitQueryEvent:resultEvent];
  return rows;
}

- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder
                             error:(NSError **)error {
  ALNPgClearError(error);
  NSArray *normalizedParameters = @[];
  NSString *sql = @"";
  NSError *compileError = nil;
  BOOL compileCacheHit = NO;
  NSTimeInterval compileStarted = [NSDate timeIntervalSinceReferenceDate];
  NSDictionary *compiled = [self compiledBuilder:builder
                                        cacheHit:&compileCacheHit
                                           error:&compileError];
  NSTimeInterval compileDurationMS =
      ([NSDate timeIntervalSinceReferenceDate] - compileStarted) * 1000.0;
  if ([compiled isKindOfClass:[NSDictionary class]]) {
    sql = [compiled[@"sql"] isKindOfClass:[NSString class]] ? compiled[@"sql"] : @"";
    normalizedParameters =
        [compiled[@"parameters"] isKindOfClass:[NSArray class]] ? compiled[@"parameters"] : @[];
  }

  NSMutableDictionary *compileEvent = [self baseQueryEventWithStage:ALNPgQueryStageCompile
                                                              source:@"builder"
                                                           operation:@"command"
                                                       executionMode:@"compile"
                                                                 sql:sql
                                                          parameters:normalizedParameters];
  compileEvent[ALNPgQueryEventCacheHitKey] = @(compileCacheHit);
  compileEvent[ALNPgQueryEventDurationMSKey] = @(compileDurationMS);
  if (compileError != nil) {
    compileEvent[ALNPgQueryEventErrorDomainKey] = compileError.domain ?: @"";
    compileEvent[ALNPgQueryEventErrorCodeKey] = @(compileError.code);
  }
  [self emitQueryEvent:compileEvent];

  if (compiled == nil) {
    if (error != NULL) {
      *error = compileError;
    }
    NSMutableDictionary *errorEvent = [self baseQueryEventWithStage:ALNPgQueryStageError
                                                              source:@"builder"
                                                           operation:@"command"
                                                       executionMode:@"compile"
                                                                 sql:sql
                                                          parameters:normalizedParameters];
    if (compileError != nil) {
      errorEvent[ALNPgQueryEventErrorDomainKey] = compileError.domain ?: @"";
      errorEvent[ALNPgQueryEventErrorCodeKey] = @(compileError.code);
    }
    [self emitQueryEvent:errorEvent];
    return -1;
  }

  BOOL shouldPrepare = [self shouldUsePreparedStatementForParameterCount:[normalizedParameters count]];
  BOOL preparedCacheHit = NO;
  BOOL preparedCacheFull = NO;
  NSString *preparedName = nil;
  NSError *prepareError = nil;
  if (shouldPrepare) {
    preparedName = [self preparedStatementNameForSQL:sql
                                      parameterCount:[normalizedParameters count]
                                           operation:@"command"
                                            cacheHit:&preparedCacheHit
                                           cacheFull:&preparedCacheFull
                                               error:&prepareError];
  }

  NSString *executionMode = ([preparedName length] > 0) ? @"prepared" : @"direct";
  NSMutableDictionary *executeEvent = [self baseQueryEventWithStage:ALNPgQueryStageExecute
                                                              source:@"builder"
                                                           operation:@"command"
                                                       executionMode:executionMode
                                                                 sql:sql
                                                          parameters:normalizedParameters];
  if ([preparedName length] > 0) {
    executeEvent[ALNPgQueryEventPreparedStatementKey] = preparedName;
    executeEvent[ALNPgQueryEventCacheHitKey] = @(preparedCacheHit);
  }
  if (preparedCacheFull) {
    executeEvent[ALNPgQueryEventCacheFullKey] = @YES;
  }
  [self emitQueryEvent:executeEvent];

  if (prepareError != nil) {
    if (error != NULL) {
      *error = prepareError;
    }
    NSMutableDictionary *errorEvent = [self baseQueryEventWithStage:ALNPgQueryStageError
                                                              source:@"builder"
                                                           operation:@"command"
                                                       executionMode:@"prepare"
                                                                 sql:sql
                                                          parameters:normalizedParameters];
    errorEvent[ALNPgQueryEventErrorDomainKey] = prepareError.domain ?: @"";
    errorEvent[ALNPgQueryEventErrorCodeKey] = @(prepareError.code);
    [self emitQueryEvent:errorEvent];
    return -1;
  }

  NSError *commandError = nil;
  NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
  NSInteger affected = -1;
  if ([preparedName length] > 0) {
    affected = [self executePreparedCommandNamed:preparedName
                                      parameters:normalizedParameters
                                           error:&commandError];
  } else {
    affected = [self executeCommand:sql parameters:normalizedParameters error:&commandError];
  }
  NSTimeInterval durationMS = ([NSDate timeIntervalSinceReferenceDate] - started) * 1000.0;

  if (affected < 0) {
    if (error != NULL) {
      *error = commandError;
    }
    NSMutableDictionary *errorEvent = [self baseQueryEventWithStage:ALNPgQueryStageError
                                                              source:@"builder"
                                                           operation:@"command"
                                                       executionMode:executionMode
                                                                 sql:sql
                                                          parameters:normalizedParameters];
    errorEvent[ALNPgQueryEventDurationMSKey] = @(durationMS);
    if ([preparedName length] > 0) {
      errorEvent[ALNPgQueryEventPreparedStatementKey] = preparedName;
      errorEvent[ALNPgQueryEventCacheHitKey] = @(preparedCacheHit);
    }
    if (preparedCacheFull) {
      errorEvent[ALNPgQueryEventCacheFullKey] = @YES;
    }
    if (commandError != nil) {
      errorEvent[ALNPgQueryEventErrorDomainKey] = commandError.domain ?: @"";
      errorEvent[ALNPgQueryEventErrorCodeKey] = @(commandError.code);
      NSString *sqlState =
          [commandError.userInfo[ALNPgErrorSQLStateKey] isKindOfClass:[NSString class]]
              ? commandError.userInfo[ALNPgErrorSQLStateKey]
              : @"";
      if ([sqlState length] > 0) {
        errorEvent[ALNPgErrorSQLStateKey] = sqlState;
      }
    }
    [self emitQueryEvent:errorEvent];
    return -1;
  }

  NSMutableDictionary *resultEvent = [self baseQueryEventWithStage:ALNPgQueryStageResult
                                                             source:@"builder"
                                                          operation:@"command"
                                                      executionMode:executionMode
                                                                sql:sql
                                                         parameters:normalizedParameters];
  resultEvent[ALNPgQueryEventDurationMSKey] = @(durationMS);
  resultEvent[ALNPgQueryEventAffectedRowsKey] = @(affected);
  if ([preparedName length] > 0) {
    resultEvent[ALNPgQueryEventPreparedStatementKey] = preparedName;
    resultEvent[ALNPgQueryEventCacheHitKey] = @(preparedCacheHit);
  }
  if (preparedCacheFull) {
    resultEvent[ALNPgQueryEventCacheFullKey] = @YES;
  }
  [self emitQueryEvent:resultEvent];
  return affected;
}

- (BOOL)runTransactionSQL:(NSString *)sql error:(NSError **)error {
  ALNPgClearError(error);
  NSInteger affected = [self executeCommand:sql parameters:@[] error:error];
  return (affected >= 0);
}

- (BOOL)beginTransaction:(NSError **)error {
  ALNPgClearError(error);
  if (_inTransaction) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorTransactionFailed,
                              @"transaction already active on connection",
                              nil,
                              nil);
    }
    return NO;
  }

  NSError *runError = nil;
  BOOL ok = [self runTransactionSQL:@"BEGIN" error:&runError];
  if (!ok) {
    if (error != NULL) {
      *error = runError;
    }
    return NO;
  }
  _inTransaction = YES;
  return YES;
}

- (BOOL)commitTransaction:(NSError **)error {
  ALNPgClearError(error);
  if (!_inTransaction) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorTransactionFailed,
                              @"no active transaction to commit",
                              nil,
                              nil);
    }
    return NO;
  }

  NSError *runError = nil;
  BOOL ok = [self runTransactionSQL:@"COMMIT" error:&runError];
  _inTransaction = NO;
  if (!ok && error != NULL) {
    *error = runError;
  }
  return ok;
}

- (BOOL)rollbackTransaction:(NSError **)error {
  ALNPgClearError(error);
  if (!_inTransaction) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorTransactionFailed,
                              @"no active transaction to rollback",
                              nil,
                              nil);
    }
    return NO;
  }

  NSError *runError = nil;
  BOOL ok = [self runTransactionSQL:@"ROLLBACK" error:&runError];
  _inTransaction = NO;
  if (!ok && error != NULL) {
    *error = runError;
  }
  return ok;
}

- (BOOL)createSavepointNamed:(NSString *)name error:(NSError **)error {
  ALNPgClearError(error);
  NSString *validatedName = ALNPgValidatedSavepointName(name, error);
  if (validatedName == nil) {
    return NO;
  }
  if (!_inTransaction) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorTransactionFailed,
                              @"savepoints require an active transaction",
                              nil,
                              nil);
    }
    return NO;
  }
  return [self runTransactionSQL:[NSString stringWithFormat:@"SAVEPOINT %@", validatedName]
                           error:error];
}

- (BOOL)rollbackToSavepointNamed:(NSString *)name error:(NSError **)error {
  ALNPgClearError(error);
  NSString *validatedName = ALNPgValidatedSavepointName(name, error);
  if (validatedName == nil) {
    return NO;
  }
  if (!_inTransaction) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorTransactionFailed,
                              @"savepoints require an active transaction",
                              nil,
                              nil);
    }
    return NO;
  }
  return [self runTransactionSQL:[NSString stringWithFormat:@"ROLLBACK TO SAVEPOINT %@", validatedName]
                           error:error];
}

- (BOOL)releaseSavepointNamed:(NSString *)name error:(NSError **)error {
  ALNPgClearError(error);
  NSString *validatedName = ALNPgValidatedSavepointName(name, error);
  if (validatedName == nil) {
    return NO;
  }
  if (!_inTransaction) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorTransactionFailed,
                              @"savepoints require an active transaction",
                              nil,
                              nil);
    }
    return NO;
  }
  return [self runTransactionSQL:[NSString stringWithFormat:@"RELEASE SAVEPOINT %@", validatedName]
                           error:error];
}

- (BOOL)withSavepointNamed:(NSString *)name
                usingBlock:(BOOL (^)(NSError **error))block
                     error:(NSError **)error {
  ALNPgClearError(error);
  if (block == nil) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
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

@end

@interface ALNPg ()

@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite) NSUInteger maxConnections;
@property(nonatomic, strong) NSMutableArray *idleConnections;
@property(nonatomic, assign) NSUInteger inUseConnections;

@end

@implementation ALNPg

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  NSMutableDictionary<NSString *, id> *metadata =
      [NSMutableDictionary dictionaryWithDictionary:[[self class] capabilityMetadata]];
  metadata[@"connection_liveness_checks_enabled"] = @(self.connectionLivenessChecksEnabled);
  return [NSDictionary dictionaryWithDictionary:metadata];
}

+ (NSDictionary<NSString *, id> *)capabilityMetadata {
  return @{
    @"adapter" : @"postgresql",
    @"dialect" : @"postgresql",
    @"supports_transactions" : @YES,
    @"returning_mode" : @"returning",
    @"pagination_syntax" : @"limit_offset",
    @"supports_upsert" : @YES,
    @"conflict_resolution_mode" : @"on_conflict",
    @"json_feature_family" : @"jsonb_ops",
    @"support_tier" : @"first_class",
    @"supports_builder_compilation_cache" : @YES,
    @"supports_builder_diagnostics" : @YES,
    @"supports_batch_execution" : @YES,
    @"supports_connection_liveness_checks" : @YES,
    @"supports_cte" : @YES,
    @"supports_for_update" : @YES,
    @"supports_lateral_join" : @YES,
    @"supports_on_conflict" : @YES,
    @"supports_recursive_cte" : @YES,
    @"supports_result_wrappers" : @YES,
    @"supports_savepoints" : @YES,
    @"supports_savepoint_release" : @YES,
    @"supports_set_operations" : @YES,
    @"supports_skip_locked" : @YES,
    @"supports_window_clauses" : @YES,
    @"batch_execution_mode" : @"sequential_same_connection",
    @"prepared_statement_cache_eviction" : @"lru",
    @"savepoint_release_mode" : @"explicit",
  };
}

- (NSString *)adapterName {
  return @"postgresql";
}

- (id<ALNSQLDialect>)sqlDialect {
  return [ALNPostgresDialect sharedDialect];
}

- (instancetype)initWithConnectionString:(NSString *)connectionString
                           maxConnections:(NSUInteger)maxConnections
                                    error:(NSError **)error {
  self = [super init];
  if (!self) {
    return nil;
  }

  ALNPgClearError(error);

  if ([connectionString length] == 0) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"connection string is required",
                              nil,
                              nil);
    }
    return nil;
  }

  _connectionString = [connectionString copy];
  _maxConnections = (maxConnections > 0) ? maxConnections : 8;
  _idleConnections = [NSMutableArray array];
  _inUseConnections = 0;
  _preparedStatementReusePolicy = ALNPgPreparedStatementReusePolicyAuto;
  _preparedStatementCacheLimit = 128;
  _builderCompilationCacheLimit = 128;
  _connectionLivenessChecksEnabled = NO;
  _includeSQLInDiagnosticsEvents = NO;
  _emitDiagnosticsEventsToStderr = NO;
  _queryDiagnosticsListener = nil;
  return self;
}

- (void)dealloc {
  @synchronized(self) {
    for (ALNPgConnection *connection in self.idleConnections) {
      [connection close];
    }
    [self.idleConnections removeAllObjects];
  }
}

- (ALNPgConnection *)acquireConnection:(NSError **)error {
  ALNPgClearError(error);
  @synchronized(self) {
    while ([self.idleConnections count] > 0) {
      ALNPgConnection *connection = [self.idleConnections lastObject];
      [self.idleConnections removeLastObject];
      connection.preparedStatementReusePolicy = self.preparedStatementReusePolicy;
      connection.preparedStatementCacheLimit = self.preparedStatementCacheLimit;
      connection.builderCompilationCacheLimit = self.builderCompilationCacheLimit;
      connection.includeSQLInDiagnosticsEvents = self.includeSQLInDiagnosticsEvents;
      connection.emitDiagnosticsEventsToStderr = self.emitDiagnosticsEventsToStderr;
      connection.queryDiagnosticsListener = self.queryDiagnosticsListener;
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
        *error = ALNPgMakeError(ALNPgErrorPoolExhausted,
                                @"connection pool exhausted",
                                nil,
                                nil);
      }
      return nil;
    }

    NSError *connectionError = nil;
    ALNPgConnection *connection =
        [[ALNPgConnection alloc] initWithConnectionString:self.connectionString error:&connectionError];
    if (connection == nil) {
      if (error != NULL) {
        *error = connectionError;
      }
      return nil;
    }
    connection.preparedStatementReusePolicy = self.preparedStatementReusePolicy;
    connection.preparedStatementCacheLimit = self.preparedStatementCacheLimit;
    connection.builderCompilationCacheLimit = self.builderCompilationCacheLimit;
    connection.includeSQLInDiagnosticsEvents = self.includeSQLInDiagnosticsEvents;
    connection.emitDiagnosticsEventsToStderr = self.emitDiagnosticsEventsToStderr;
    connection.queryDiagnosticsListener = self.queryDiagnosticsListener;
    self.inUseConnections += 1;
    return connection;
  }
}

- (void)releaseConnection:(ALNPgConnection *)connection {
  if (connection == nil) {
    return;
  }
  @synchronized(self) {
    if (self.inUseConnections > 0) {
      self.inUseConnections -= 1;
    }
    if (connection.isOpen && [connection hasActiveTransaction]) {
      NSError *rollbackError = nil;
      if (![connection rollbackTransaction:&rollbackError]) {
        [connection close];
      }
    }
    if (connection.isOpen) {
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
  if ([connection isKindOfClass:[ALNPgConnection class]]) {
    [self releaseConnection:(ALNPgConnection *)connection];
  }
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  ALNPgClearError(error);
  NSError *acquireError = nil;
  ALNPgConnection *connection = [self acquireConnection:&acquireError];
  if (connection == nil) {
    if (error != NULL) {
      *error = acquireError;
    }
    return nil;
  }

  NSArray *rows = nil;
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
  ALNPgClearError(error);
  NSError *acquireError = nil;
  ALNPgConnection *connection = [self acquireConnection:&acquireError];
  if (connection == nil) {
    if (error != NULL) {
      *error = acquireError;
    }
    return nil;
  }
  ALNDatabaseResult *result = nil;
  @try {
    result = [connection executeQueryResult:sql parameters:parameters ?: @[] error:error];
  } @finally {
    [self releaseConnection:connection];
  }
  return result;
}

- (NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder
                                            error:(NSError **)error {
  ALNPgClearError(error);
  NSError *acquireError = nil;
  ALNPgConnection *connection = [self acquireConnection:&acquireError];
  if (connection == nil) {
    if (error != NULL) {
      *error = acquireError;
    }
    return nil;
  }

  NSArray *rows = nil;
  @try {
    rows = [connection executeBuilderQuery:builder error:error];
  } @finally {
    [self releaseConnection:connection];
  }
  return rows;
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  ALNPgClearError(error);
  NSError *acquireError = nil;
  ALNPgConnection *connection = [self acquireConnection:&acquireError];
  if (connection == nil) {
    if (error != NULL) {
      *error = acquireError;
    }
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
  ALNPgClearError(error);
  NSError *acquireError = nil;
  ALNPgConnection *connection = [self acquireConnection:&acquireError];
  if (connection == nil) {
    if (error != NULL) {
      *error = acquireError;
    }
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

- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder
                             error:(NSError **)error {
  ALNPgClearError(error);
  NSError *acquireError = nil;
  ALNPgConnection *connection = [self acquireConnection:&acquireError];
  if (connection == nil) {
    if (error != NULL) {
      *error = acquireError;
    }
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

- (BOOL)withTransaction:(BOOL (^)(ALNPgConnection *connection, NSError **error))block
                  error:(NSError **)error {
  ALNPgClearError(error);
  if (block == nil) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"transaction block is required",
                              nil,
                              nil);
    }
    return NO;
  }

  NSError *acquireError = nil;
  ALNPgConnection *connection = [self acquireConnection:&acquireError];
  if (connection == nil) {
    if (error != NULL) {
      *error = acquireError;
    }
    return NO;
  }

  BOOL success = NO;
  NSError *blockError = nil;
  @try {
    NSError *beginError = nil;
    if (![connection beginTransaction:&beginError]) {
      if (error != NULL) {
        *error = beginError;
      }
      return NO;
    }

    success = block(connection, &blockError);
    if (success) {
      NSError *commitError = nil;
      if (![connection commitTransaction:&commitError]) {
        success = NO;
        if (error != NULL) {
          *error = commitError;
        }
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
  ALNPgClearError(error);
  if (block == nil) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"transaction block is required",
                              nil,
                              nil);
    }
    return NO;
  }

  return [self withTransaction:^BOOL(ALNPgConnection *connection, NSError **txError) {
    return block((id<ALNDatabaseConnection>)connection, txError);
  } error:error];
}

@end
