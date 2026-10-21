#import "ALNPg.h"
#import "ALNJSONSerialization.h"
#import "ALNPlatform.h"
#import "ALNPostgresDialect.h"
#import "ALNSQLBuilder.h"

#import <dispatch/dispatch.h>
#import <ctype.h>
#import <stdlib.h>
#import <stdint.h>
#import <math.h>
#import <string.h>
#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#include <poll.h>
#endif

NSString *const ALNPgErrorDomain = @"Arlen.Data.Pg.Error";
NSString *const ALNPgErrorConnectionLostKey = @"connection_lost";
NSString *const ALNPgErrorStatementNotSentKey = @"statement_not_sent";
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
// Layout-compatible with libpq's PGnotify (libpq-fe.h is not included).
typedef struct ALNPGnotify {
  char *relname;
  int be_pid;
  char *extra;
  struct ALNPGnotify *next;
} ALNPGnotify;
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
static void ALNPgEmitEventToStderr(NSDictionary *event);

static PGconn *(*ALNPQconnectdb)(const char *conninfo) = NULL;
static int (*ALNPQconsumeInput)(PGconn *conn) = NULL;
static ALNPGnotify *(*ALNPQnotifies)(PGconn *conn) = NULL;
static int (*ALNPQsocket)(const PGconn *conn) = NULL;
static void (*ALNPQfreemem)(void *ptr) = NULL;
static int (*ALNPQstatus)(const PGconn *conn) = NULL;
static int (*ALNPQtransactionStatus)(const PGconn *conn) = NULL;
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
typedef void (*ALNPQnoticeReceiver)(void *arg, const PGresult *res);
static ALNPQnoticeReceiver (*ALNPQsetNoticeReceiver)(PGconn *conn, ALNPQnoticeReceiver proc, void *arg) = NULL;
static int (*ALNPQisBusy)(PGconn *conn) = NULL;

// Per-connection state for ALNPgNoticeReceiver. A server that ends a session
// sends an ErrorResponse with severity FATAL; on an idle connection libpq
// hands it to the notice receiver rather than to a result.
typedef struct {
  BOOL serverEndedSession;
  ALNPQnoticeReceiver previous;
  void *previousArg;
} ALNPgNoticeState;

static void ALNPgNoticeReceiver(void *arg, const PGresult *res) {
  ALNPgNoticeState *state = (ALNPgNoticeState *)arg;
  if (state == NULL) {
    return;
  }
  const char *severity = NULL;
  if (ALNPQresultErrorField != NULL) {
    severity = ALNPQresultErrorField(res, 'V');  // PG_DIAG_SEVERITY_NONLOCALIZED
    if (severity == NULL) {
      severity = ALNPQresultErrorField(res, 'S');  // PG_DIAG_SEVERITY
    }
  }
  if (severity != NULL && (strcmp(severity, "FATAL") == 0 || strcmp(severity, "PANIC") == 0)) {
    state->serverEndedSession = YES;
  }
  if (state->previous != NULL) {
    state->previous(state->previousArg, res);
  }
}

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
  // An absolute path (the release's build/dll) also resolves its imports
  // from its own directory; wide-character, so non-ASCII paths load.
  return ALNPlatformLoadWindowsLibrary([NSString stringWithUTF8String:candidate] ?: @"");
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

    void *handle = NULL;
    NSArray<NSString *> *candidates = ALNDefaultLibpqCandidatePaths();
    for (NSString *candidate in candidates) {
      handle = ALNOpenLibpqCandidate([candidate UTF8String]);
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
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQtransactionStatus, handle, "PQtransactionStatus");
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
    // LISTEN/NOTIFY support (waitForNotificationsWithTimeout:); optional so a
    // minimal libpq still serves ordinary queries.
    ALNBindOptionalLibpqSymbol((void **)&ALNPQconsumeInput, handle, "PQconsumeInput");
    ALNBindOptionalLibpqSymbol((void **)&ALNPQnotifies, handle, "PQnotifies");
    ALNBindOptionalLibpqSymbol((void **)&ALNPQsocket, handle, "PQsocket");
    ALNBindOptionalLibpqSymbol((void **)&ALNPQfreemem, handle, "PQfreemem");
    // Detecting a session the server ended while the connection sat idle.
    ALNBindOptionalLibpqSymbol((void **)&ALNPQsetNoticeReceiver, handle, "PQsetNoticeReceiver");
    ALNBindOptionalLibpqSymbol((void **)&ALNPQisBusy, handle, "PQisBusy");

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

// Text codecs for timestamp/date and bytea values. Not static so unit tests
// can call them without a live database; they are not public API.
NSString *ALNPgHexStringFromData(NSData *data);
// In ALNSQLBuilder.m (not public API): trusted expressions compiled so far on
// this thread.
extern NSUInteger ALNSQLBuilderTrustedExpressionCompileCount(void);
NSData *ALNPgDataFromByteaBytes(const char *text, NSUInteger length);
NSData *ALNPgDataFromByteaString(NSString *value);
NSString *ALNPgTimestampStringFromDate(NSDate *value);
NSDate *ALNPgDateFromTimestampString(NSString *value);
NSDate *ALNPgDateFromDateString(NSString *value);

// bytea hex format (`\x` followed by two lowercase hex digits per byte),
// encoded through a lookup table into one C buffer (#234).
NSString *ALNPgHexStringFromData(NSData *data) {
  if (![data isKindOfClass:[NSData class]]) {
    return @"";
  }
  static const char digits[] = "0123456789abcdef";
  const unsigned char *bytes = [data bytes];
  NSUInteger length = [data length];
  if (length > (NSUIntegerMax - 2) / 2) {
    return @"";
  }
  NSUInteger hexLength = (length * 2) + 2;
  char *hex = malloc(hexLength);
  if (hex == NULL) {
    return @"";
  }
  hex[0] = '\\';
  hex[1] = 'x';
  char *out = hex + 2;
  for (NSUInteger idx = 0; idx < length; idx++) {
    unsigned char byte = bytes[idx];
    *out++ = digits[byte >> 4];
    *out++ = digits[byte & 0x0f];
  }
  NSString *encoded = [[NSString alloc] initWithBytesNoCopy:hex
                                                     length:hexLength
                                                   encoding:NSASCIIStringEncoding
                                               freeWhenDone:YES];
  if (encoded == nil) {
    free(hex);
    return @"";
  }
  return encoded;
}

static NSDate *ALNPgDateWithReferenceInterval(NSTimeInterval interval) {
#if defined(GNUSTEP)
  // Some GNUstep tagged-date runtimes misrepresent an exact zero reference
  // interval as two seconds. NSCalendarDate is a Foundation NSDate subclass
  // that retains zero correctly and avoids that tagged representation.
  if (interval == 0) return [[NSCalendarDate alloc] initWithTimeIntervalSinceReferenceDate:0];
#endif
  return [NSDate dateWithTimeIntervalSinceReferenceDate:interval];
}

// Seconds between 1970-01-01 and 2001-01-01 (the NSDate reference date).
static const int64_t ALNPgUnixSecondsAtReferenceDate = 978307200;

// Days since 1970-01-01 for a proleptic Gregorian civil date, the calendar
// PostgreSQL uses (H. Hinnant's days_from_civil). Pure integer arithmetic:
// no calendar object and no allocation per value (#233).
static int64_t ALNPgDaysFromCivil(int64_t year, int64_t month, int64_t day) {
  year -= (month <= 2) ? 1 : 0;
  int64_t era = (year >= 0 ? year : year - 399) / 400;
  int64_t yearOfEra = year - (era * 400);
  int64_t dayOfYear = (((153 * (month + (month > 2 ? -3 : 9))) + 2) / 5) + day - 1;
  int64_t dayOfEra = (yearOfEra * 365) + (yearOfEra / 4) - (yearOfEra / 100) + dayOfYear;
  return (era * 146097) + dayOfEra - 719468;
}

// Inverse of ALNPgDaysFromCivil.
static void ALNPgCivilFromDays(int64_t days, int64_t *yearOut, int *monthOut, int *dayOut) {
  days += 719468;
  int64_t era = (days >= 0 ? days : days - 146096) / 146097;
  int64_t dayOfEra = days - (era * 146097);
  int64_t yearOfEra =
      (dayOfEra - (dayOfEra / 1460) + (dayOfEra / 36524) - (dayOfEra / 146096)) / 365;
  int64_t dayOfYear = dayOfEra - ((365 * yearOfEra) + (yearOfEra / 4) - (yearOfEra / 100));
  int64_t monthPrime = ((5 * dayOfYear) + 2) / 153;
  int day = (int)(dayOfYear - (((153 * monthPrime) + 2) / 5) + 1);
  int month = (int)(monthPrime < 10 ? monthPrime + 3 : monthPrime - 9);
  *yearOut = (yearOfEra + (era * 400)) + (month <= 2 ? 1 : 0);
  *monthOut = month;
  *dayOut = day;
}

static NSInteger ALNPgDaysInMonth(NSInteger year, NSInteger month) {
  static const NSInteger days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  if (month == 2) {
    BOOL leap = ((year % 4) == 0 && (year % 100) != 0) || (year % 400) == 0;
    return leap ? 29 : 28;
  }
  return days[month - 1];
}

// ISO-8601 UTC text for an NSDate parameter, e.g. `2026-09-17T12:34:56.123456Z`.
// Formatted with integer arithmetic over the proleptic Gregorian calendar
// PostgreSQL uses, instead of an NSDateFormatter, NSCalendar and NSLocale per
// parameter (#233). Dates before year 1 get PostgreSQL's ` BC` suffix.
NSString *ALNPgTimestampStringFromDate(NSDate *value) {
  if (![value isKindOfClass:[NSDate class]]) {
    return @"";
  }
  // Split before rounding: multiplying an epoch-sized double by a million
  // needlessly loses precision. floor also handles dates before the epoch.
  NSTimeInterval interval = [value timeIntervalSinceReferenceDate];
  double seconds = floor(interval);
  long microseconds = lround((interval - seconds) * 1000000.0);
  if (microseconds == 1000000) {
    seconds += 1;
    microseconds = 0;
  }
  // Far outside anything PostgreSQL stores (it stops at year 294276); the
  // bound keeps the integer arithmetic below from overflowing.
  if (!isfinite(seconds) || fabs(seconds) > 1.0e15) {
    return @"";
  }
  int64_t unixSeconds = (int64_t)seconds + ALNPgUnixSecondsAtReferenceDate;
  int64_t days = unixSeconds / 86400;
  int64_t secondOfDay = unixSeconds % 86400;
  if (secondOfDay < 0) {
    secondOfDay += 86400;
    days -= 1;
  }
  int64_t year = 0;
  int month = 0;
  int day = 0;
  ALNPgCivilFromDays(days, &year, &month, &day);
  // Astronomical year 0 is 1 BC in PostgreSQL's notation.
  BOOL beforeCommonEra = (year <= 0);
  long long displayYear = beforeCommonEra ? (long long)(1 - year) : (long long)year;
  char buffer[64];
  int written = snprintf(buffer,
                         sizeof(buffer),
                         "%04lld-%02d-%02dT%02d:%02d:%02d.%06ldZ%s",
                         displayYear,
                         month,
                         day,
                         (int)(secondOfDay / 3600),
                         (int)((secondOfDay / 60) % 60),
                         (int)(secondOfDay % 60),
                         microseconds,
                         beforeCommonEra ? " BC" : "");
  if (written <= 0 || (size_t)written >= sizeof(buffer)) {
    return @"";
  }
  return [[NSString alloc] initWithBytes:buffer
                                  length:(NSUInteger)written
                                encoding:NSASCIIStringEncoding]
             ?: @"";
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
    if (ALNNumberIsBoolean(value)) {
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
    if (ALNNumberIsBoolean(value)) {
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
  // GNUstep's decimal parser has a fixed-size mantissa. Bound the textual
  // driver value before entering Foundation; oversized values fail decoding.
  if ([value length] > 40) return nil;
  NSUInteger digits = 0;
  for (NSUInteger index = 0; index < [value length]; index++) {
    unichar ch = [value characterAtIndex:index];
    if (ch >= '0' && ch <= '9' && ++digits > 38) return nil;
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
static BOOL ALNPgUTCReferenceSeconds(NSInteger year,
                                     NSInteger month,
                                     NSInteger day,
                                     NSInteger hour,
                                     NSInteger minute,
                                     NSInteger second,
                                     NSTimeInterval *secondsOut);
static id ALNPgDecodedValueForFieldType(ALNOid fieldType,
                                        NSString *columnName,
                                        NSString *stringValue,
                                        NSError **error);

NSDate *ALNPgDateFromDateString(NSString *value) {
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

  NSTimeInterval seconds = 0;
  if (!ALNPgUTCReferenceSeconds(year, month, day, 0, 0, 0, &seconds)) {
    return nil;
  }
  return ALNPgDateWithReferenceInterval(seconds);
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

// Seconds since the NSDate reference date for a UTC civil date-time, or NO
// when the fields do not name a real proleptic Gregorian instant (month 13,
// February 30, hour 24, second 60, year 0). Replaces a per-value NSCalendar
// (#233); the parser that feeds it is fixed-width, so this is all arithmetic.
static BOOL ALNPgUTCReferenceSeconds(NSInteger year,
                                     NSInteger month,
                                     NSInteger day,
                                     NSInteger hour,
                                     NSInteger minute,
                                     NSInteger second,
                                     NSTimeInterval *secondsOut) {
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > ALNPgDaysInMonth(year, month) ||
      hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) {
    return NO;
  }
  int64_t days = ALNPgDaysFromCivil(year, month, day);
  int64_t unixSeconds = (days * 86400) + (hour * 3600) + (minute * 60) + second;
  *secondsOut = (NSTimeInterval)(unixSeconds - ALNPgUnixSecondsAtReferenceDate);
  return YES;
}

NSDate *ALNPgDateFromTimestampString(NSString *value) {
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

  NSTimeInterval interval = 0;
  if (!ALNPgUTCReferenceSeconds(year, month, day, hour, minute, second, &interval)) {
    return nil;
  }
  // Same order of floating-point operations as before: whole seconds, plus
  // the fraction, minus the zone offset.
  if (fractionalSeconds != 0.0) {
    interval = interval + fractionalSeconds;
  }
  if (hasOffset) {
    NSInteger offset = ((offsetHours * 60 * 60) + (offsetMinutes * 60) + offsetSeconds) * sign;
    interval = interval - (NSTimeInterval)offset;
  }
  return ALNPgDateWithReferenceInterval(interval);
}

// Value of one hex digit, or -1. Built once; used by the bytea decoder.
static const int8_t *ALNPgHexDigitTable(void) {
  static int8_t table[256];
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    memset(table, -1, sizeof(table));
    for (int idx = 0; idx < 10; idx++) {
      table['0' + idx] = (int8_t)idx;
    }
    for (int idx = 0; idx < 6; idx++) {
      table['a' + idx] = (int8_t)(10 + idx);
      table['A' + idx] = (int8_t)(10 + idx);
    }
  });
  return table;
}

// Decode bytea hex text (`\x` prefix optional) straight from a C buffer with
// a lookup table (#234). nil for an odd digit count or any non-hex byte.
NSData *ALNPgDataFromByteaBytes(const char *text, NSUInteger length) {
  if (text == NULL) {
    return nil;
  }
  if (length >= 2 && text[0] == '\\' && text[1] == 'x') {
    text += 2;
    length -= 2;
  }
  if ((length % 2) != 0) {
    return nil;
  }
  const int8_t *table = ALNPgHexDigitTable();
  NSUInteger byteCount = length / 2;
  NSMutableData *data = [NSMutableData dataWithLength:byteCount];
  if (data == nil) {
    return nil;
  }
  unsigned char *out = [data mutableBytes];
  const unsigned char *in = (const unsigned char *)text;
  for (NSUInteger idx = 0; idx < byteCount; idx++) {
    // The table is deliberately signed: -1 marks a non-hex byte. The index is
    // already unsigned char, so the signed-char widening below is intended.
    // NOLINTBEGIN(bugprone-signed-char-misuse,cert-str34-c)
    int high = table[in[idx * 2]];
    int low = table[in[(idx * 2) + 1]];
    // NOLINTEND(bugprone-signed-char-misuse,cert-str34-c)
    if (high < 0 || low < 0) {
      return nil;
    }
    out[idx] = (unsigned char)((high << 4) | low);
  }
  return data;
}

NSData *ALNPgDataFromByteaString(NSString *value) {
  if (![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  const char *text = [value UTF8String];
  if (text == NULL) {
    return nil;
  }
  return ALNPgDataFromByteaBytes(text, (NSUInteger)strlen(text));
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
      // json/jsonb columns may hold scalar documents ('"s"', '42', 'true', 'null').
      decoded = [ALNJSONSerialization JSONObjectWithData:jsonData
                                                 options:NSJSONReadingAllowFragments
                                                   error:error];
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

// libpq takes SQL text and statement names as C strings, so a U+0000 inside
// one would silently end it early. Callers refuse such text up front.
static BOOL ALNPgTextContainsNUL(NSString *text) {
  return [text isKindOfClass:[NSString class]] &&
         [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0, 1)]].location !=
             NSNotFound;
}

static BOOL ALNPgFailIfTextContainsNUL(NSString *text, NSString *what, NSError **error) {
  if (!ALNPgTextContainsNUL(text)) {
    return NO;
  }
  if (error != NULL) {
    *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                            [NSString stringWithFormat:@"%@ contains a NUL character (U+0000)", what],
                            nil,
                            nil);
  }
  return YES;
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
    // libpq reads text parameters as C strings, so an embedded U+0000 would
    // silently cut the value short (PostgreSQL text cannot hold it anyway).
    // Refuse it; binary values go through NSData, which is sent as bytea hex.
    if (utf8Length > 0 && memchr([utf8 bytes], 0, utf8Length) != NULL) {
      if (error != NULL) {
        NSString *detail = [NSString stringWithFormat:@"parameter %lu contains a NUL character (U+0000); "
                                                      @"pass binary data as NSData",
                                                      (unsigned long)(idx + 1)];
        *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                                @"failed to encode query parameter",
                                detail,
                                sql);
      }
      ALNPgFreeExecParamsBuffer(buffer);
      return NO;
    }
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

  ALNOid fieldType = (ALNPQftype != NULL) ? ALNPQftype(result, field) : 0;
  if (fieldType == ALNPGOIDOID_BYTEA) {
    // Decode bytea from libpq's buffer without first copying it into an
    // NSString (#234). Malformed text falls through to the generic path,
    // which reports the usual decode error.
    NSData *bytes = ALNPgDataFromByteaBytes(value, (NSUInteger)strlen(value));
    if (bytes != nil) {
      return bytes;
    }
  }

  NSString *stringValue = [NSString stringWithUTF8String:value];
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
  ALNPgNoticeState _noticeState;
}

@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite, getter=isOpen) BOOL open;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *builderCompilationCache;
@property(nonatomic, strong) NSMutableArray<NSString *> *builderCompilationCacheOrder;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *preparedStatementNamesByKey;
@property(nonatomic, strong) NSMutableArray<NSString *> *preparedStatementCacheOrder;
@property(nonatomic, assign) NSUInteger preparedStatementSequence;
// Pool bookkeeping: wall-clock time (seconds since the NSDate reference date)
// when the connection last went back to the idle list (0 = never), and how
// many SELECT 1 liveness probes it has run. Read by the pool and by tests.
@property(nonatomic, assign) NSTimeInterval poolIdleSince;
@property(nonatomic, assign) NSUInteger livenessCheckCount;
// YES when the pool handed this connection out from its idle list (it may have
// been closed by the server while idle); NO for a freshly opened connection.
@property(nonatomic, assign) BOOL reusedFromPool;
// YES once this borrower ran SQL the pool did not generate itself: any
// executeQuery/executeCommand/script/prepare with caller SQL, a transaction,
// or a builder statement that spliced trusted expression text. Only a dirty
// connection needs the session reset on release. builderExecutionDepth is
// non-zero while a purely generated builder statement runs through the
// public entry points, so those do not mark the connection.
@property(nonatomic, assign) BOOL sessionStateDirty;
@property(nonatomic, assign) NSUInteger builderExecutionDepth;

- (BOOL)hasActiveTransaction;
- (BOOL)reportConnectionLossForError:(NSError **)error;
- (BOOL)isInsideTransaction;
- (BOOL)failIfConnectionClosedBeforeSend:(NSError **)error;
- (BOOL)checkConnectionLiveness:(NSError **)error;
- (BOOL)isConnectionUsable;
- (BOOL)deallocatePreparedStatementNamed:(NSString *)name error:(NSError **)error;
- (BOOL)resetSessionStateDiscardingAll:(BOOL)discardAll;
- (BOOL)discardQueuedNotifications;
- (void)noteCallerStatement;

@end


@interface ALNPgConnection (ALNORMGeneratedExecution)
- (NSArray *)aln_executeGeneratedQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error;
- (NSInteger)aln_executeGeneratedCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error;
@end
@interface ALNPg (ALNORMGeneratedExecution)
- (NSArray *)aln_executeGeneratedQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error;
- (NSInteger)aln_executeGeneratedCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error;
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
  _noticeState.serverEndedSession = NO;
  _noticeState.previous = NULL;
  _noticeState.previousArg = NULL;
  if (ALNPQsetNoticeReceiver != NULL) {
    // A NULL proc returns the current receiver without changing it. On a new
    // connection that is libpq's default receiver, whose arg is NULL; chaining
    // to it keeps notices going to the notice processor as before.
    _noticeState.previous = ALNPQsetNoticeReceiver(_conn, NULL, NULL);
    _noticeState.previousArg = NULL;
    (void)ALNPQsetNoticeReceiver(_conn, ALNPgNoticeReceiver, &_noticeState);
  }
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

- (NSArray<NSDictionary *> *)drainNotifications {
  NSMutableArray<NSDictionary *> *notifications = [NSMutableArray array];
  ALNPGnotify *notify = NULL;
  while ((notify = ALNPQnotifies(_conn)) != NULL) {
    NSString *channel = notify->relname != NULL ? [NSString stringWithUTF8String:notify->relname] : @"";
    NSString *payload = notify->extra != NULL ? [NSString stringWithUTF8String:notify->extra] : @"";
    [notifications addObject:@{ @"channel" : channel ?: @"", @"payload" : payload ?: @"", @"pid" : @(notify->be_pid) }];
    ALNPQfreemem(notify);
  }
  return notifications;
}

- (NSArray<NSDictionary *> *)waitForNotificationsWithTimeout:(NSTimeInterval)timeout error:(NSError **)error {
  NSError *openError = [self checkOpenError];
  if (openError != nil) {
    if (error != NULL) *error = openError;
    return nil;
  }
  if (ALNPQconsumeInput == NULL || ALNPQnotifies == NULL || ALNPQsocket == NULL || ALNPQfreemem == NULL) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorConnectionFailed, @"libpq lacks LISTEN/NOTIFY support", nil, nil);
    }
    return nil;
  }
  NSArray<NSDictionary *> *queued = [self drainNotifications];
  if ([queued count] > 0) {
    return queued;
  }
  int socketFD = ALNPQsocket(_conn);
  if (socketFD < 0) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorConnectionFailed, @"PostgreSQL connection has no socket", nil, nil);
    }
    return nil;
  }
#if defined(_WIN32)
  fd_set readable;
  FD_ZERO(&readable);
  FD_SET((SOCKET)socketFD, &readable);
  struct timeval wait = { (long)timeout, (long)((timeout - floor(timeout)) * 1000000.0) };
  (void)select(0, &readable, NULL, NULL, &wait);
#else
  struct pollfd pollDescriptor = { .fd = socketFD, .events = POLLIN, .revents = 0 };
  (void)poll(&pollDescriptor, 1, (int)MAX(0.0, timeout * 1000.0));
#endif
  if (ALNPQconsumeInput(_conn) != 1) {
    const char *message = ALNPQerrorMessage(_conn);
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorConnectionFailed,
                              @"lost PostgreSQL connection while waiting for notifications",
                              message != NULL ? [NSString stringWithUTF8String:message] : nil,
                              nil);
    }
    return nil;
  }
  return [self drainNotifications];
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

// Authoritative health of the underlying socket. Unlike `isOpen` (a cached
// flag flipped only by an explicit -close), this asks libpq directly and is
// free of a round-trip: libpq marks a connection CONNECTION_BAD as soon as a
// send/recv on it fails, so a connection killed while pooled (server restart,
// idle timeout, network drop) reports NO here even though `isOpen` is still
// YES. A connection that merely returned a SQL error keeps CONNECTION_OK and
// stays usable.
- (BOOL)isConnectionUsable {
  return _conn != NULL && self.isOpen && ALNPQstatus(_conn) == ALNConnectionOK;
}

// Close the connection if libpq has marked the socket dead. Called on the
// query-failure path so a poisoned connection is torn down immediately
// instead of being handed back to the pool.
- (void)closeIfConnectionLost {
  if (_conn != NULL && ALNPQstatus(_conn) != ALNConnectionOK) {
    [self close];
  }
}

// After a failed statement: when libpq reports the connection dead (the server
// closed it, restarted or failed over), report the failure as
// ALNPgErrorConnectionFailed with ALNPgErrorConnectionLostKey = YES, whatever
// SQLSTATE (or none) the last result carried, and close the connection so the
// pool discards it instead of reusing it. Returns YES when a lost connection
// was detected and closed, even if the caller did not request an error.
- (BOOL)reportConnectionLossForError:(NSError **)error {
  if (_conn == NULL || ALNPQstatus(_conn) == ALNConnectionOK) {
    return NO;
  }
  if (error != NULL && *error != nil) {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:(*error).userInfo ?: @{}];
    userInfo[ALNPgErrorConnectionLostKey] = @YES;
    *error = [NSError errorWithDomain:ALNPgErrorDomain code:ALNPgErrorConnectionFailed userInfo:userInfo];
  }
  [self close];
  return YES;
}

// YES while a transaction is open on this connection: one started with
// -beginTransaction, or one the caller opened by sending BEGIN by hand
// (libpq's transaction status is anything but PQTRANS_IDLE).
- (BOOL)isInsideTransaction {
  if (_inTransaction) {
    return YES;
  }
  // PGTransactionStatusType: 0 = PQTRANS_IDLE, 4 = PQTRANS_UNKNOWN (bad
  // connection); 1-3 = a command or transaction in progress.
  int status = (_conn != NULL) ? ALNPQtransactionStatus(_conn) : 0;
  return status >= 1 && status <= 3;
}

// Called just before a statement is sent. ALNPg executes with the synchronous
// PQexec/PQexecParams/PQprepare/PQexecPrepared calls, which send and then wait
// in one step: when they fail, the caller cannot tell whether the statement
// reached the server. So the "never reached the server" case is decided here,
// before sending. libpq keeps its socket non-blocking, so PQconsumeInput reads
// whatever the server already sent without waiting. A server that ended the
// session while the connection sat idle (restart, failover, idle timeout,
// pg_terminate_backend) has already sent its FATAL message or closed the
// socket; reading it marks the connection CONNECTION_BAD. In that case the
// statement is not sent at all, the connection is closed, and the error
// carries ALNPgErrorStatementNotSentKey, which is what makes a write safe to
// retry. A connection that fails after this check (the send went out and the
// failure came while waiting for the result) is reported without that key.
- (BOOL)failIfConnectionClosedBeforeSend:(NSError **)error {
  if (_conn == NULL) {
    return NO;
  }
  if (ALNPQconsumeInput == NULL) {
    return NO;
  }
  // A server that ends a session sends a FATAL message and then closes the
  // socket. Either one is enough: the end of stream marks the connection
  // CONNECTION_BAD, and the FATAL message, once PQisBusy parses it, reaches
  // ALNPgNoticeReceiver (libpq routes errors on an idle connection to the
  // notice receiver).
  BOOL alive = (ALNPQconsumeInput(_conn) != 0 && ALNPQstatus(_conn) == ALNConnectionOK);
  if (alive && ALNPQisBusy != NULL) {
    (void)ALNPQisBusy(_conn);
    alive = (ALNPQstatus(_conn) == ALNConnectionOK);
  }
  if (alive && _noticeState.serverEndedSession) {
    alive = NO;
  }
  if (alive) {
    return NO;
  }
  if (error != NULL) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQerrorMessage(_conn) ?: ""];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
      NSLocalizedDescriptionKey : @"connection was closed by the server before the statement was sent",
      ALNPgErrorConnectionLostKey : @YES,
      ALNPgErrorStatementNotSentKey : @YES,
    }];
    if ([detail length] > 0) {
      userInfo[@"detail"] = detail;
    }
    *error = [NSError errorWithDomain:ALNPgErrorDomain code:ALNPgErrorConnectionFailed userInfo:userInfo];
  }
  [self close];
  return YES;
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

  self.livenessCheckCount += 1;
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

- (void)noteCallerStatement {
  if (self.builderExecutionDepth == 0) {
    self.sessionStateDirty = YES;
  }
}

// The SQL text the statement cache believes each of its names was prepared
// with. Cache keys are "operation|parameterCount|sql".
- (NSDictionary<NSString *, NSString *> *)cachedPreparedStatementSQLByName {
  NSMutableDictionary<NSString *, NSString *> *byName = [NSMutableDictionary dictionary];
  [self.preparedStatementNamesByKey enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *name, BOOL *stop) {
    (void)stop;
    NSRange first = [key rangeOfString:@"|"];
    NSRange second = (first.location == NSNotFound)
                         ? first
                         : [key rangeOfString:@"|" options:0 range:NSMakeRange(NSMaxRange(first), [key length] - NSMaxRange(first))];
    byName[name] = (second.location == NSNotFound) ? @"" : [key substringFromIndex:NSMaxRange(second)];
  }];
  return byName;
}

// Called by the pool before a released connection is reused, so settings,
// role, temp tables, cursors, sequences, LISTENs, queued notifications and
// advisory locks from one borrower do not reach the next. A connection that
// only ran SQL the pool generated itself (sessionStateDirty == NO) cannot
// have changed any of that and is reused as is.
//
// The session reset keeps the pool's cached prepared statements, but checks
// them in the same round trip: a borrower who ran its own SQL could have
// DEALLOCATEd a cached name and PREPAREd different SQL under it, so the next
// borrower would run that instead. Any statement the cache does not know,
// any statement created by SQL PREPARE, any text that differs from the
// cached SQL, or a cached name that is gone, drops every prepared statement
// and clears the cache. DISCARD ALL drops them unconditionally. NO means the
// reset failed and the connection must not be reused.
- (BOOL)resetSessionStateDiscardingAll:(BOOL)discardAll {
  if (_conn == NULL || !self.isOpen) {
    return NO;
  }
  if (!self.sessionStateDirty) {
    return YES;
  }
  const char *sql = discardAll ? "DISCARD ALL"
                               : "RESET ALL; SET SESSION AUTHORIZATION DEFAULT; CLOSE ALL; DISCARD TEMP; "
                                 "DISCARD SEQUENCES; UNLISTEN *; SELECT pg_advisory_unlock_all(); "
                                 "SELECT name, statement, from_sql FROM pg_prepared_statements";
  PGresult *result = ALNPQexec(_conn, sql);
  int status = (result != NULL) ? ALNPQresultStatus(result) : -1;
  BOOL ok = (status == ALNPGRES_COMMAND_OK || status == ALNPGRES_TUPLES_OK) &&
            ALNPQstatus(_conn) == ALNConnectionOK;
  BOOL cacheTrusted = !discardAll;
  if (ok && !discardAll && status == ALNPGRES_TUPLES_OK) {
    NSDictionary<NSString *, NSString *> *expected = [self cachedPreparedStatementSQLByName];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    int rows = ALNPQntuples(result);
    for (int row = 0; row < rows && cacheTrusted; row++) {
      NSString *name = [NSString stringWithUTF8String:ALNPQgetvalue(result, row, 0) ?: ""] ?: @"";
      NSString *statement = [NSString stringWithUTF8String:ALNPQgetvalue(result, row, 1) ?: ""] ?: @"";
      const char *fromSQL = ALNPQgetvalue(result, row, 2);
      BOOL createdBySQL = (fromSQL != NULL && fromSQL[0] == 't');
      NSString *cachedSQL = expected[name];
      if (createdBySQL || cachedSQL == nil || ![cachedSQL isEqualToString:statement]) {
        cacheTrusted = NO;
      }
      [seen addObject:name];
    }
    if ([seen count] != [expected count]) {
      cacheTrusted = NO;
    }
  }
  if (result != NULL) {
    ALNPQclear(result);
  }
  if (ok && !cacheTrusted) {
    if (!discardAll) {
      PGresult *deallocate = ALNPQexec(_conn, "DEALLOCATE ALL");
      int deallocateStatus = (deallocate != NULL) ? ALNPQresultStatus(deallocate) : -1;
      if (deallocate != NULL) {
        ALNPQclear(deallocate);
      }
      ok = (deallocateStatus == ALNPGRES_COMMAND_OK) && ALNPQstatus(_conn) == ALNConnectionOK;
    }
    [self.preparedStatementNamesByKey removeAllObjects];
    [self.preparedStatementCacheOrder removeAllObjects];
  }
  if (ok) {
    ok = [self discardQueuedNotifications];
  }
  if (ok) {
    self.sessionStateDirty = NO;
  }
  return ok;
}

// Notifications for a borrower's LISTENs can still be queued in libpq or
// unread on the socket after it releases the connection. Read and drop them
// (no round trip) so the next borrower's waitForNotifications does not see
// them. NO means the connection turned out to be unusable.
- (BOOL)discardQueuedNotifications {
  if (_conn == NULL) {
    return NO;
  }
  if (ALNPQconsumeInput != NULL && ALNPQconsumeInput(_conn) == 0) {
    return NO;
  }
  if (ALNPQnotifies != NULL && ALNPQfreemem != NULL) {
    (void)[self drainNotifications];
  }
  return YES;
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
  // Events cost three dictionaries plus an SQL hash and token per query, so
  // build none when nothing consumes them; callers message the nil result
  // harmlessly (#232).
  if (self.queryDiagnosticsListener == nil && !self.emitDiagnosticsEventsToStderr) {
    return nil;
  }
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
  if (event == nil) {
    return;
  }
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

  NSUInteger trustedBefore = ALNSQLBuilderTrustedExpressionCompileCount();
  NSError *buildError = nil;
  NSDictionary *built = [builder buildWithDialect:[ALNPostgresDialect sharedDialect] error:&buildError];
  // Trusted expressions are app SQL text, which can change session state even
  // inside a plain SELECT (set_config, advisory locks, nextval), so a
  // statement that holds one marks the connection for a reset on release.
  BOOL trustedSQL = ALNSQLBuilderTrustedExpressionCompileCount() != trustedBefore;
  if (trustedSQL) {
    self.sessionStateDirty = YES;
  }
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

  // Compile current values on every invocation, but retain only the SQL shape.
  // This avoids a second KVC traversal of the builder and never retains a
  // borrower's parameter values in the connection cache.
  NSString *signature = [NSString stringWithFormat:@"%lu:%@", (unsigned long)[parameters count], sql];
  NSString *cachedSQL = self.builderCompilationCache[signature];
  if (cacheHit != NULL) *cacheHit = cachedSQL != nil;
  if (cachedSQL != nil) sql = cachedSQL;
  NSDictionary *normalized = @{
    @"sql" : sql,
    @"parameters" : [NSArray arrayWithArray:parameters],
    @"trusted_sql" : @(trustedSQL),
  };
  if (self.builderCompilationCacheLimit > 0) {
    if (cachedSQL == nil && [self.builderCompilationCache count] >= self.builderCompilationCacheLimit) {
      NSString *oldest = self.builderCompilationCacheOrder.firstObject;
      if (oldest != nil) {
        [self.builderCompilationCache removeObjectForKey:oldest];
        [self.builderCompilationCacheOrder removeObjectAtIndex:0];
      }
    }
    self.builderCompilationCache[signature] = sql;
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
  if (ALNPgFailIfTextContainsNUL(sql, @"sql", error) ||
      ALNPgFailIfTextContainsNUL(name, @"statement name", error)) {
    return NO;
  }

  if ([self failIfConnectionClosedBeforeSend:error]) {
    return NO;
  }
  [self noteCallerStatement];
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
    [self reportConnectionLossForError:error];
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
    [self reportConnectionLossForError:error];
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
  if (ALNPgFailIfTextContainsNUL(sql, @"sql", error)) {
    return NULL;
  }

  NSUInteger count = [parameters count];
  ALNPgExecParamsBuffer paramBuffer;
  if (!ALNPgBuildExecParamsBuffer(parameters ?: @[], sql, &paramBuffer, error)) {
    return NULL;
  }

  if ([self failIfConnectionClosedBeforeSend:error]) {
    ALNPgFreeExecParamsBuffer(&paramBuffer);
    return NULL;
  }
  [self noteCallerStatement];
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
    [self reportConnectionLossForError:error];
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
  if (ALNPgFailIfTextContainsNUL(sql, @"sql script", error)) {
    return NULL;
  }

  if ([self failIfConnectionClosedBeforeSend:error]) {
    return NULL;
  }
  [self noteCallerStatement];
  PGresult *result = ALNPQexec(_conn, [sql UTF8String]);
  if (result == NULL) {
    if (error != NULL) {
      NSString *detail = [NSString stringWithUTF8String:ALNPQerrorMessage(_conn) ?: ""];
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"script execution failed",
                              detail,
                              sql);
    }
    [self reportConnectionLossForError:error];
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
  if (ALNPgFailIfTextContainsNUL(name, @"statement name", error)) {
    return NULL;
  }

  NSUInteger count = [parameters count];
  ALNPgExecParamsBuffer paramBuffer;
  if (!ALNPgBuildExecParamsBuffer(parameters ?: @[], name, &paramBuffer, error)) {
    return NULL;
  }

  if ([self failIfConnectionClosedBeforeSend:error]) {
    ALNPgFreeExecParamsBuffer(&paramBuffer);
    return NULL;
  }
  [self noteCallerStatement];
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
  if (result == NULL) {
    [self reportConnectionLossForError:error];
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

// Called only with ORM compiler-proven generated SQL; raw/trusted fragments
// stay on the ordinary execution path. Never clear an already-dirty session.
- (NSArray *)aln_executeGeneratedQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  self.builderExecutionDepth += 1;
  @try { return [self executeQuery:sql parameters:parameters error:error]; }
  @finally { self.builderExecutionDepth -= 1; }
}
- (NSInteger)aln_executeGeneratedCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  self.builderExecutionDepth += 1;
  @try { return [self executeCommand:sql parameters:parameters error:error]; }
  @finally { self.builderExecutionDepth -= 1; }
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
    [self reportConnectionLossForError:error];
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
    [self reportConnectionLossForError:error];
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
    [self reportConnectionLossForError:error];
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
    [self reportConnectionLossForError:error];
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
    [self reportConnectionLossForError:error];
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

// Generated builder SQL runs through the public statement methods without
// marking the connection dirty; compiledBuilder: marks it when the statement
// holds a trusted expression.
- (NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder
                                            error:(NSError **)error {
  self.builderExecutionDepth += 1;
  @try {
    return [self aln_executeBuilderQuery:builder error:error];
  } @finally {
    self.builderExecutionDepth -= 1;
  }
}

- (NSInteger)executeBuilderCommand:(ALNSQLBuilder *)builder
                             error:(NSError **)error {
  self.builderExecutionDepth += 1;
  @try {
    return [self aln_executeBuilderCommand:builder error:error];
  } @finally {
    self.builderExecutionDepth -= 1;
  }
}

- (NSArray<NSDictionary *> *)aln_executeBuilderQuery:(ALNSQLBuilder *)builder
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

- (NSInteger)aln_executeBuilderCommand:(ALNSQLBuilder *)builder
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

  // A statement that failed inside the transaction aborts it, and PostgreSQL
  // then answers COMMIT with a successful ROLLBACK. Report that as a failed
  // commit instead of success with every write discarded (#230).
  // PQTRANS_INERROR is 3 in libpq's PGTransactionStatusType.
  BOOL aborted = (_conn != NULL && ALNPQtransactionStatus(_conn) == 3);
  NSError *runError = nil;
  BOOL ok = [self runTransactionSQL:(aborted ? @"ROLLBACK" : @"COMMIT") error:&runError];
  _inTransaction = NO;
  if (aborted) {
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorTransactionFailed,
                              @"transaction was aborted by an earlier failed statement and was rolled back",
                              nil,
                              nil);
    }
    return NO;
  }
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
  BOOL success = NO;
  @try {
    success = block(&blockError);
  } @catch (NSException *exception) {
    // Preserve the outer transaction while undoing the throwing inner scope.
    if (![self rollbackToSavepointNamed:name error:NULL] ||
        ![self releaseSavepointNamed:name error:NULL]) {
      [self close];
    }
    @throw;
  }
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
@property(nonatomic, strong) NSCondition *poolCondition;
@property(nonatomic, assign) NSUInteger acquireWaitCount;
@property(nonatomic, assign) NSTimeInterval acquireWaitSecondsTotal;
@property(nonatomic, assign) NSUInteger poolExhaustedCount;
@property(nonatomic, assign) NSUInteger connectionRetryCount;
@property(nonatomic, assign) NSUInteger releasedInTransactionCount;
@property(nonatomic, assign) NSUInteger sessionResetFailureCount;
@property(nonatomic, assign) NSUInteger sessionResetCount;

@end

@implementation ALNPg

- (NSDictionary<NSString *, id> *)capabilityMetadata {
  NSMutableDictionary<NSString *, id> *metadata =
      [NSMutableDictionary dictionaryWithDictionary:[[self class] capabilityMetadata]];
  metadata[@"connection_liveness_checks_enabled"] = @(self.connectionLivenessChecksEnabled);
  metadata[@"connection_liveness_check_idle_threshold_seconds"] =
      @(self.connectionLivenessCheckIdleThreshold);
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

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    // Created before the pool is shared; libobjc2's first @synchronized on an
    // instance can race (gnustep/libobjc2#424). Guards pool bookkeeping only
    // (slot count and idle list). Connects, on-borrow liveness checks and
    // release-time rollbacks run outside it, so one slow checkout does not
    // stall every other borrower and diagnostics listeners never run under
    // it. acquireTimeout waiters block on it for a released slot.
    _poolCondition = [[NSCondition alloc] init];
  }
  return self;
}

- (instancetype)initWithConnectionString:(NSString *)connectionString
                           maxConnections:(NSUInteger)maxConnections
                                    error:(NSError **)error {
  self = [self init];
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
  // Default ON: validate a pooled connection before handing it out. The
  // release-time status gate and failure-path teardown evict connections
  // that die while checked out, but a connection can also die while sitting
  // idle in the pool (server restart, idle/firewall timeout during a quiet
  // period). The on-borrow SELECT 1 is the only thing that catches that case
  // before a request fails. Previously NO, which let a single weekend
  // network blip silently poison the whole pool until a manual restart.
  _connectionLivenessChecksEnabled = YES;
  // Only connections idle at least this long get the SELECT 1 probe. One
  // that was returned moments ago is almost certainly still alive, and the
  // probe would add a round trip to every pooled statement (#236).
  // PQstatus still screens every reused connection for free.
  _connectionLivenessCheckIdleThreshold = 30.0;
  _includeSQLInDiagnosticsEvents = NO;
  _emitDiagnosticsEventsToStderr = NO;
  _queryDiagnosticsListener = nil;
  return self;
}

- (void)dealloc {
  [self.poolCondition lock];
  @try {
    for (ALNPgConnection *connection in self.idleConnections) {
      [connection close];
    }
    [self.idleConnections removeAllObjects];
  } @finally {
    [self.poolCondition unlock];
  }
}

- (void)configurePooledConnection:(ALNPgConnection *)connection {
  connection.preparedStatementReusePolicy = self.preparedStatementReusePolicy;
  connection.preparedStatementCacheLimit = self.preparedStatementCacheLimit;
  connection.builderCompilationCacheLimit = self.builderCompilationCacheLimit;
  connection.includeSQLInDiagnosticsEvents = self.includeSQLInDiagnosticsEvents;
  connection.emitDiagnosticsEventsToStderr = self.emitDiagnosticsEventsToStderr;
  connection.queryDiagnosticsListener = self.queryDiagnosticsListener;
}

// YES when a reused idle connection should get the SELECT 1 probe: checks
// are on and it has sat idle for at least the threshold (or the threshold
// is 0 or less, which probes every reuse).
- (BOOL)shouldProbeIdleConnection:(ALNPgConnection *)connection {
  if (!self.connectionLivenessChecksEnabled) {
    return NO;
  }
  NSTimeInterval threshold = self.connectionLivenessCheckIdleThreshold;
  NSTimeInterval idleSince = connection.poolIdleSince;
  if (!(threshold > 0) || idleSince <= 0) {
    return YES;
  }
  // Wall clock rather than an uptime clock, so time the host spent asleep
  // counts as idle time. If the clock stepped backwards, probe to be safe.
  NSTimeInterval idleFor = [NSDate timeIntervalSinceReferenceDate] - idleSince;
  return idleFor < 0 || idleFor >= threshold;
}

// Give back a slot reserved by acquireConnection: whose connection could not
// be handed out, and wake any acquireTimeout waiter.
- (void)returnReservedSlot {
  [self.poolCondition lock];
  if (self.inUseConnections > 0) {
    self.inUseConnections -= 1;
  }
  [self.poolCondition broadcast];
  [self.poolCondition unlock];
}

- (ALNPgConnection *)acquireConnection:(NSError **)error {
  ALNPgClearError(error);
  NSTimeInterval timeout = self.acquireTimeout;
  NSDate *deadline = nil;
  NSTimeInterval waited = 0;

  while (YES) {
    ALNPgConnection *candidate = nil;
    BOOL createNew = NO;

    // Reserve a slot: either an idle connection or room to open a new one.
    // The slot counts as in use from here until it is handed out or returned.
    [self.poolCondition lock];
    @try {
      while (YES) {
        if ([self.idleConnections count] > 0) {
          candidate = [self.idleConnections lastObject];
          [self.idleConnections removeLastObject];
          self.inUseConnections += 1;
          break;
        }
        if (self.inUseConnections < self.maxConnections) {
          self.inUseConnections += 1;
          createNew = YES;
          break;
        }
        if (timeout <= 0 || (deadline != nil && [deadline timeIntervalSinceNow] <= 0)) {
          self.poolExhaustedCount += 1;
          if (error != NULL) {
            NSString *message =
                (deadline != nil)
                    ? [NSString stringWithFormat:@"connection pool exhausted after waiting %.3fs",
                                                 waited]
                    : @"connection pool exhausted";
            *error = ALNPgMakeErrorWithDiagnostics(ALNPgErrorPoolExhausted,
                                                   message,
                                                   nil,
                                                   nil,
                                                   @{
                                                     @"max_connections" : @(self.maxConnections),
                                                     @"acquire_timeout_seconds" : @(timeout),
                                                     @"acquire_wait_seconds" : @(waited),
                                                   });
          }
          return nil;
        }
        if (deadline == nil) {
          deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
          self.acquireWaitCount += 1;
        }
        // The loop re-checks the pool after every wakeup, so spurious wakeups
        // and a slot taken first by another borrower are both harmless.
        NSDate *sliceStarted = [NSDate date];
        (void)[self.poolCondition waitUntilDate:deadline];
        NSTimeInterval slice = -[sliceStarted timeIntervalSinceNow];
        waited += slice;
        self.acquireWaitSecondsTotal += slice;
      }
    } @finally {
      [self.poolCondition unlock];
    }

    BOOL handedOut = NO;
    @try {
      if (createNew) {
        NSError *connectionError = nil;
        ALNPgConnection *connection =
            [[ALNPgConnection alloc] initWithConnectionString:self.connectionString
                                                        error:&connectionError];
        if (connection == nil) {
          if (error != NULL) {
            *error = connectionError;
          }
          return nil;
        }
        [self configurePooledConnection:connection];
        connection.reusedFromPool = NO;
        handedOut = YES;
        return connection;
      }

      // Drop a locally-known-dead idle connection with zero round-trip
      // before doing any further work. This self-heals the pool: dead
      // connections are discarded here and the create-new path refills
      // capacity, so the pool recovers its size instead of handing out
      // poison. Works even when liveness checks are disabled.
      if ([candidate isConnectionUsable]) {
        [self configurePooledConnection:candidate];
        NSError *livenessError = nil;
        if (![self shouldProbeIdleConnection:candidate] ||
            [candidate checkConnectionLiveness:&livenessError]) {
          candidate.reusedFromPool = YES;
          handedOut = YES;
          return candidate;
        }
      }
      [candidate close];
    } @finally {
      if (!handedOut) {
        [self returnReservedSlot];
      }
    }
  }
}

- (void)releaseConnection:(ALNPgConnection *)connection {
  if (connection == nil) {
    return;
  }
  BOOL reusable = NO;
  BOOL closedInTransaction = NO;
  BOOL resetFailed = NO;
  BOOL dirty = NO;
  @try {
    // A connection still inside a transaction (an unfinished -beginTransaction:
    // or a BEGIN sent by hand) is closed, which rolls the transaction back
    // server-side. Re-pooling it would put the next borrower's statements into
    // this borrower's transaction.
    if (connection.isOpen && ([connection hasActiveTransaction] || [connection isInsideTransaction])) {
      [connection close];
      closedInTransaction = YES;
    }
    // Gate re-pooling on the real libpq socket status, not the cached
    // `isOpen` flag. A connection whose socket died while checked out (server
    // restart, idle/firewall drop) still reports isOpen == YES; returning it
    // here poisons the pool and every subsequent borrower fails the same way
    // until the worker is restarted. isConnectionUsable asks libpq directly,
    // so a dead connection is torn down instead of recirculated.
    reusable = !closedInTransaction && [connection isConnectionUsable];
    // A connection that only ran SQL the pool generated is reused without a
    // reset; the connection skips the round trip itself when it is clean.
    dirty = connection.sessionStateDirty;
    if (reusable && self.sessionResetPolicy != ALNPgSessionResetPolicyNone) {
      if (![connection resetSessionStateDiscardingAll:(self.sessionResetPolicy == ALNPgSessionResetPolicyDiscardAll)]) {
        reusable = NO;
        resetFailed = YES;
      }
    } else if (reusable && dirty && ![connection discardQueuedNotifications]) {
      // ALNPgSessionResetPolicyNone still drops queued notifications.
      reusable = NO;
    }
    if (!reusable && !closedInTransaction) {
      [connection close];
    }
  } @finally {
    [self.poolCondition lock];
    if (closedInTransaction) {
      self.releasedInTransactionCount += 1;
    }
    if (resetFailed) {
      self.sessionResetFailureCount += 1;
    } else if (reusable && dirty && self.sessionResetPolicy != ALNPgSessionResetPolicyNone) {
      self.sessionResetCount += 1;
    }
    if (self.inUseConnections > 0) {
      self.inUseConnections -= 1;
    }
    if (reusable) {
      connection.poolIdleSince = [NSDate timeIntervalSinceReferenceDate];
      [self.idleConnections addObject:connection];
    }
    [self.poolCondition broadcast];
    [self.poolCondition unlock];
  }
}

// Closes every idle connection. Called when one pooled connection turns out to
// have been closed by the server: the others very likely were too (restart,
// failover), so they are reopened on demand rather than tried one by one.
- (void)discardIdleConnections {
  NSArray *idle = nil;
  [self.poolCondition lock];
  idle = [self.idleConnections copy];
  [self.idleConnections removeAllObjects];
  [self.poolCondition broadcast];
  [self.poolCondition unlock];
  for (ALNPgConnection *connection in idle) {
    [connection close];
  }
}

static BOOL ALNPgErrorIsConnectionLost(NSError *error) {
  return [error.domain isEqualToString:ALNPgErrorDomain] && error.code == ALNPgErrorConnectionFailed &&
         [error.userInfo[ALNPgErrorConnectionLostKey] boolValue];
}

// Conservative: YES only for a statement that starts with SELECT, WITH,
// VALUES, TABLE, SHOW or EXPLAIN (without ANALYZE) and contains none of the
// words that write or take locks or change session state (INSERT, UPDATE,
// DELETE, MERGE, TRUNCATE, COPY, CALL, DO, INTO, LOCK, SHARE, NOTIFY,
// LISTEN, NEXTVAL, SETVAL, SET_CONFIG, ANALYZE, and the pg_advisory and
// pg_try_advisory lock functions). String literals, quoted identifiers and
// comments are skipped. A SELECT that calls a user function with side
// effects is still classified as a read; run such statements with
// executeCommand, which is never retried once sent.
static BOOL ALNPgSQLIsPlainRead(NSString *sql) {
  static NSSet *firstWords = nil;
  static NSSet *writeWords = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    firstWords = [NSSet setWithArray:@[ @"SELECT", @"WITH", @"VALUES", @"TABLE", @"SHOW", @"EXPLAIN" ]];
    writeWords = [NSSet setWithArray:@[
      @"INSERT", @"UPDATE", @"DELETE", @"MERGE", @"TRUNCATE", @"COPY", @"CALL", @"DO", @"INTO", @"LOCK",
      @"SHARE", @"NOTIFY", @"LISTEN", @"NEXTVAL", @"SETVAL", @"SET_CONFIG", @"ANALYZE",
    ]];
  });
  NSUInteger length = [sql length];
  if (length == 0) {
    return NO;
  }
  NSMutableString *word = [NSMutableString string];
  __block BOOL sawFirst = NO;
  NSUInteger index = 0;
  BOOL (^finishWord)(void) = ^BOOL {
    if ([word length] == 0) {
      return YES;
    }
    NSString *upper = [word uppercaseString];
    [word setString:@""];
    if (!sawFirst) {
      sawFirst = YES;
      return [firstWords containsObject:upper];
    }
    return !([writeWords containsObject:upper] || [upper hasPrefix:@"PG_ADVISORY"] ||
             [upper hasPrefix:@"PG_TRY_ADVISORY"]);
  };
  while (index < length) {
    unichar ch = [sql characterAtIndex:index];
    if (ch == '\'' || ch == '"') {
      if (!finishWord()) {
        return NO;
      }
      unichar quote = ch;
      index += 1;
      while (index < length && [sql characterAtIndex:index] != quote) {
        index += 1;
      }
      index += 1;
      continue;
    }
    if (ch == '-' && index + 1 < length && [sql characterAtIndex:index + 1] == '-') {
      if (!finishWord()) {
        return NO;
      }
      while (index < length && [sql characterAtIndex:index] != '\n') {
        index += 1;
      }
      continue;
    }
    if (ch == '/' && index + 1 < length && [sql characterAtIndex:index + 1] == '*') {
      if (!finishWord()) {
        return NO;
      }
      index += 2;
      while (index + 1 < length &&
             !([sql characterAtIndex:index] == '*' && [sql characterAtIndex:index + 1] == '/')) {
        index += 1;
      }
      index += 2;
      continue;
    }
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' || (ch >= '0' && ch <= '9' && [word length] > 0)) {
      [word appendFormat:@"%C", ch];
    } else if (!finishWord()) {
      return NO;
    }
    index += 1;
  }
  return finishWord() && sawFirst;
}

static BOOL ALNPgErrorStatementNotSent(NSError *error) {
  return ALNPgErrorIsConnectionLost(error) && [error.userInfo[ALNPgErrorStatementNotSentKey] boolValue];
}

// Runs `work` on a pooled connection, retrying once on a new connection when a
// connection reused from the idle list turns out to have been closed by the
// server. The retry policy:
//   - never when a transaction was open on the connection (an earlier
//     statement of it would be lost and this one would run on its own);
//   - never for a connection that was opened for this call;
//   - reads (`readOnly`, see ALNPgSQLIsPlainRead): when the connection was lost
//     at any point;
//   - writes: only when the statement was never sent
//     (ALNPgErrorStatementNotSentKey, see -failIfConnectionClosedBeforeSend:).
//     If it was sent and the connection failed while waiting for the result,
//     the server may have run it, so the error is returned instead of running
//     the write a second time.
// Idle connections are closed before a retry: the same server event very
// likely ended them too.
- (BOOL)runOnPooledConnection:(BOOL (^)(ALNPgConnection *connection, NSError **error))work
                     readOnly:(BOOL)readOnly
                        error:(NSError **)error {
  for (NSUInteger attempt = 0; attempt < 2; attempt++) {
    NSError *acquireError = nil;
    ALNPgConnection *connection = [self acquireConnection:&acquireError];
    if (connection == nil) {
      if (error != NULL) {
        *error = acquireError;
      }
      return NO;
    }
    BOOL reused = connection.reusedFromPool;
    BOOL insideTransaction = [connection isInsideTransaction];
    NSError *runError = nil;
    BOOL ok = NO;
    @try {
      ok = work(connection, &runError);
    } @finally {
      [self releaseConnection:connection];
    }
    if (ok) {
      return YES;
    }
    BOOL retryable = (attempt == 0 && reused && !insideTransaction &&
                      (readOnly ? ALNPgErrorIsConnectionLost(runError) : ALNPgErrorStatementNotSent(runError)));
    if (retryable) {
      [self.poolCondition lock];
      self.connectionRetryCount += 1;
      [self.poolCondition unlock];
      [self discardIdleConnections];
      continue;
    }
    if (error != NULL) {
      *error = runError;
    }
    return NO;
  }
  return NO;
}

- (NSDictionary<NSString *, id> *)poolDiagnostics {
  [self.poolCondition lock];
  @try {
    return @{
      @"max_connections" : @(self.maxConnections),
      @"in_use_connections" : @(self.inUseConnections),
      @"idle_connections" : @([self.idleConnections count]),
      @"acquire_timeout_seconds" : @(self.acquireTimeout),
      @"acquire_wait_count" : @(self.acquireWaitCount),
      @"acquire_wait_seconds_total" : @(self.acquireWaitSecondsTotal),
      @"pool_exhausted_count" : @(self.poolExhaustedCount),
      @"connection_retry_count" : @(self.connectionRetryCount),
      @"released_in_transaction_count" : @(self.releasedInTransactionCount),
      @"session_reset_failure_count" : @(self.sessionResetFailureCount),
      @"session_reset_count" : @(self.sessionResetCount),
    };
  } @finally {
    [self.poolCondition unlock];
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

- (NSArray *)aln_executeGeneratedQuery:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  ALNPgClearError(error);
  __block NSArray *rows = nil;
  (void)[self runOnPooledConnection:^BOOL(ALNPgConnection *connection, NSError **runError) {
    rows = [connection aln_executeGeneratedQuery:sql parameters:parameters error:runError];
    return rows != nil;
  } readOnly:ALNPgSQLIsPlainRead(sql) error:error];
  return rows;
}
- (NSInteger)aln_executeGeneratedCommand:(NSString *)sql parameters:(NSArray *)parameters error:(NSError **)error {
  ALNPgClearError(error);
  __block NSInteger affected = -1;
  (void)[self runOnPooledConnection:^BOOL(ALNPgConnection *connection, NSError **runError) {
    affected = [connection aln_executeGeneratedCommand:sql parameters:parameters error:runError];
    return affected >= 0;
  } readOnly:NO error:error];
  return affected;
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  ALNPgClearError(error);
  __block NSArray *rows = nil;
  (void)[self runOnPooledConnection:^BOOL(ALNPgConnection *connection, NSError **runError) {
    rows = [connection executeQuery:sql parameters:parameters ?: @[] error:runError];
    return rows != nil;
  } readOnly:ALNPgSQLIsPlainRead(sql) error:error];
  return rows;
}

- (ALNDatabaseResult *)executeQueryResult:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
  ALNPgClearError(error);
  __block ALNDatabaseResult *result = nil;
  (void)[self runOnPooledConnection:^BOOL(ALNPgConnection *connection, NSError **runError) {
    result = [connection executeQueryResult:sql parameters:parameters ?: @[] error:runError];
    return result != nil;
  } readOnly:ALNPgSQLIsPlainRead(sql) error:error];
  return result;
}

- (NSArray<NSDictionary *> *)executeBuilderQuery:(ALNSQLBuilder *)builder
                                            error:(NSError **)error {
  ALNPgClearError(error);
  __block NSArray *rows = nil;
  (void)[self runOnPooledConnection:^BOOL(ALNPgConnection *connection, NSError **runError) {
    rows = [connection executeBuilderQuery:builder error:runError];
    return rows != nil;
  } readOnly:(builder.kind == ALNSQLBuilderKindSelect && ALNPgSQLIsPlainRead([builder buildSQL:NULL]))
        error:error];
  return rows;
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  ALNPgClearError(error);
  __block NSInteger affected = -1;
  (void)[self runOnPooledConnection:^BOOL(ALNPgConnection *connection, NSError **runError) {
    affected = [connection executeCommand:sql parameters:parameters ?: @[] error:runError];
    return affected >= 0;
  } readOnly:NO error:error];
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
  __block NSInteger affected = -1;
  (void)[self runOnPooledConnection:^BOOL(ALNPgConnection *connection, NSError **runError) {
    affected = [connection executeBuilderCommand:builder error:runError];
    return affected >= 0;
  } readOnly:NO error:error];
  return affected;
}

- (BOOL)withTransaction:(BOOL (^)(ALNPgConnection *connection, NSError **error))block
                  error:(NSError **)error {
  return [self runTransaction:block replayOnConnectionLoss:NO error:error];
}

- (BOOL)withTransactionReplayingOnConnectionLoss:(BOOL (^)(ALNPgConnection *connection, NSError **error))block
                                           error:(NSError **)error {
  return [self runTransaction:block replayOnConnectionLoss:YES error:error];
}

// Runs `block` between BEGIN and COMMIT on one pooled connection. When BEGIN
// itself fails because a connection reused from the idle list was closed by
// the server, nothing has run yet, so the transaction restarts once on a new
// connection. When the connection is lost later (inside the block or at
// COMMIT), the server rolled back what had run, and the connection-lost error
// is returned; the block is replayed from BEGIN on a new connection, once,
// only with `replayOnConnectionLoss` (the caller's promise that running the
// whole block again is safe: it is idempotent or compare-and-set guarded,
// including when COMMIT may have succeeded before the connection dropped).
- (BOOL)runTransaction:(BOOL (^)(ALNPgConnection *connection, NSError **error))block
    replayOnConnectionLoss:(BOOL)replayOnConnectionLoss
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

  for (NSUInteger attempt = 0; attempt < 2; attempt++) {
    NSError *acquireError = nil;
    ALNPgConnection *connection = [self acquireConnection:&acquireError];
    if (connection == nil) {
      if (error != NULL) {
        *error = acquireError;
      }
      return NO;
    }

    BOOL reused = connection.reusedFromPool;
    BOOL success = NO;
    BOOL beginFailed = NO;
    NSError *failure = nil;
    @try {
      NSError *beginError = nil;
      if (![connection beginTransaction:&beginError]) {
        beginFailed = YES;
        failure = beginError;
      } else {
        NSError *blockError = nil;
        success = block(connection, &blockError);
        if (success) {
          NSError *commitError = nil;
          if (![connection commitTransaction:&commitError]) {
            success = NO;
            failure = commitError;
          }
        } else {
          NSError *rollbackError = nil;
          (void)[connection rollbackTransaction:&rollbackError];
          failure = blockError ?: rollbackError;
        }
      }
    } @finally {
      [self releaseConnection:connection];
    }
    if (success) {
      return YES;
    }
    BOOL lost = ALNPgErrorIsConnectionLost(failure);
    BOOL restart = (attempt == 0 && lost &&
                    ((beginFailed && reused) || (!beginFailed && replayOnConnectionLoss)));
    if (restart) {
      [self.poolCondition lock];
      self.connectionRetryCount += 1;
      [self.poolCondition unlock];
      [self discardIdleConnections];
      continue;
    }
    if (error != NULL) {
      *error = failure;
    }
    return NO;
  }
  return NO;
}

- (BOOL)enumerateQuery:(NSString *)sql
           parameters:(NSArray *)parameters
            batchSize:(NSUInteger)batchSize
           usingBlock:(void (^)(NSDictionary *row, BOOL *stop))block
                error:(NSError **)error {
  ALNPgClearError(error);
  if (block == nil || batchSize == 0 || batchSize > 10000 || [sql length] == 0 ||
      ALNPgFailIfTextContainsNUL(sql, @"sql", error)) {
    if (error != NULL && *error == nil) {
      *error = ALNPgMakeError(ALNPgErrorInvalidArgument,
                              @"enumeration requires SQL, a callback and batchSize from 1 through 10000", nil, nil);
    }
    return NO;
  }
  ALNPgConnection *connection = [self acquireConnection:error];
  if (connection == nil) return NO;
  BOOL finished = NO;
  @try {
    if (![connection beginTransaction:error]) return NO;
    NSString *name = [@"aln_cursor_" stringByAppendingString:
                        [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""]];
    NSString *declare = [NSString stringWithFormat:@"DECLARE %@ NO SCROLL CURSOR FOR %@", name, sql];
    if ([connection executeCommand:declare parameters:parameters error:error] < 0) return NO;
    NSString *fetch = [NSString stringWithFormat:@"FETCH FORWARD %lu FROM %@", (unsigned long)batchSize, name];
    BOOL stop = NO;
    NSError *failure = nil;
    while (!stop) {
      @autoreleasepool {
        // Keep failures strongly across the per-batch autorelease pool.
        NSError *fetchError = nil;
        NSArray *rows = [connection executeQuery:fetch parameters:@[] error:&fetchError];
        if (rows == nil) {
          failure = fetchError;
          break;
        }
        if ([rows count] == 0) break;
        for (NSDictionary *row in rows) {
          @autoreleasepool { block(row, &stop); }
          if (stop) break;
        }
      }
    }
    if (failure != nil) {
      if (error != NULL) *error = failure;
      return NO;
    }
    if ([connection executeCommand:[@"CLOSE " stringByAppendingString:name] parameters:@[] error:error] < 0) return NO;
    finished = [connection commitTransaction:error];
    return finished;
  } @finally {
    if (!finished) (void)[connection rollbackTransaction:NULL];
    [self releaseConnection:connection];
  }
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
