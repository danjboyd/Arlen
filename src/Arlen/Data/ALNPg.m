#import "ALNPg.h"

#import <dlfcn.h>
#import <stdlib.h>
#import <string.h>

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

typedef struct pg_conn PGconn;
typedef struct pg_result PGresult;

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

static PGconn *(*ALNPQconnectdb)(const char *conninfo) = NULL;
static int (*ALNPQstatus)(const PGconn *conn) = NULL;
static void (*ALNPQfinish)(PGconn *conn) = NULL;
static char *(*ALNPQerrorMessage)(const PGconn *conn) = NULL;
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
static int (*ALNPQgetisnull)(const PGresult *res, int rowNumber, int columnNumber) = NULL;
static char *(*ALNPQgetvalue)(const PGresult *res, int rowNumber, int columnNumber) = NULL;
static char *(*ALNPQcmdTuples)(PGresult *res) = NULL;

static BOOL ALNBindLibpqSymbol(void **target, void *handle, const char *symbolName) {
  *target = dlsym(handle, symbolName);
  return (*target != NULL);
}

static void ALNBindOptionalLibpqSymbol(void **target, void *handle, const char *symbolName) {
  *target = dlsym(handle, symbolName);
}

static BOOL ALNLoadLibpq(NSError **error) {
  @synchronized([NSObject class]) {
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

    const char *candidates[] = {
      "/usr/lib/x86_64-linux-gnu/libpq.so.5",
      "libpq.so.5",
      "libpq.so",
    };

    void *handle = NULL;
    size_t candidateCount = sizeof(candidates) / sizeof(candidates[0]);
    for (size_t idx = 0; idx < candidateCount; idx++) {
      handle = dlopen(candidates[idx], RTLD_LAZY | RTLD_LOCAL);
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
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQprepare, handle, "PQprepare");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQexecParams, handle, "PQexecParams");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQexecPrepared, handle, "PQexecPrepared");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQresultStatus, handle, "PQresultStatus");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQresultErrorMessage, handle, "PQresultErrorMessage");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQclear, handle, "PQclear");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQnfields, handle, "PQnfields");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQntuples, handle, "PQntuples");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQfname, handle, "PQfname");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQgetisnull, handle, "PQgetisnull");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQgetvalue, handle, "PQgetvalue");
    ok = ok && ALNBindLibpqSymbol((void **)&ALNPQcmdTuples, handle, "PQcmdTuples");
    ALNBindOptionalLibpqSymbol((void **)&ALNPQresultErrorField, handle, "PQresultErrorField");

    if (!ok) {
      const char *dlError = dlerror();
      gLibpqLoadError =
          [NSString stringWithFormat:@"required libpq symbols missing: %s", dlError ?: "unknown"];
      dlclose(handle);
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
  }
}

static NSError *ALNPgMakeError(ALNPgErrorCode code,
                               NSString *message,
                               NSString *detail,
                               NSString *sql) {
  return ALNPgMakeErrorWithDiagnostics(code, message, detail, sql, nil);
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

static NSString *ALNPgStringFromParam(id value) {
  if (value == nil || value == [NSNull null]) {
    return nil;
  }
  if ([value isKindOfClass:[NSString class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    return [value stringValue];
  }
  if ([value isKindOfClass:[NSDate class]]) {
    return [NSString stringWithFormat:@"%.3f", [(NSDate *)value timeIntervalSince1970]];
  }
  if ([value isKindOfClass:[NSData class]]) {
    return [(NSData *)value base64EncodedStringWithOptions:0];
  }
  return [value description];
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
    NSString *stringValue = ALNPgStringFromParam(value);
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

static NSDictionary *ALNPgRowDictionary(PGresult *result, int rowIndex) {
  int fieldCount = ALNPQnfields(result);
  NSMutableDictionary *row = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)fieldCount];
  for (int field = 0; field < fieldCount; field++) {
    const char *name = ALNPQfname(result, field);
    NSString *key = (name != NULL) ? [NSString stringWithUTF8String:name] : nil;
    if ([key length] == 0) {
      key = [NSString stringWithFormat:@"col_%d", field];
    }

    if (ALNPQgetisnull(result, rowIndex, field)) {
      row[key] = [NSNull null];
      continue;
    }

    const char *value = ALNPQgetvalue(result, rowIndex, field);
    if (value == NULL) {
      row[key] = [NSNull null];
      continue;
    }

    NSString *stringValue = [NSString stringWithUTF8String:value];
    row[key] = stringValue ?: @"";
  }
  return row;
}

@interface ALNPgConnection () {
  PGconn *_conn;
  BOOL _inTransaction;
}

@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite, getter=isOpen) BOOL open;

@end

@implementation ALNPgConnection

- (instancetype)initWithConnectionString:(NSString *)connectionString
                                   error:(NSError **)error {
  self = [super init];
  if (!self) {
    return nil;
  }

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

- (BOOL)prepareStatementNamed:(NSString *)name
                          sql:(NSString *)sql
               parameterCount:(NSInteger)parameterCount
                        error:(NSError **)error {
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

- (PGresult *)runExecPreparedNamed:(NSString *)name
                        parameters:(NSArray *)parameters
                             error:(NSError **)error {
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

- (NSArray<NSDictionary *> *)rowsFromResult:(PGresult *)result {
  int rowCount = ALNPQntuples(result);
  NSMutableArray *rows = [NSMutableArray arrayWithCapacity:(NSUInteger)rowCount];
  for (int idx = 0; idx < rowCount; idx++) {
    [rows addObject:ALNPgRowDictionary(result, idx)];
  }
  return rows;
}

- (NSArray<NSDictionary *> *)executeQuery:(NSString *)sql
                               parameters:(NSArray *)parameters
                                    error:(NSError **)error {
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

  NSArray *rows = [self rowsFromResult:result];
  ALNPQclear(result);
  return rows;
}

- (NSDictionary *)executeQueryOne:(NSString *)sql
                       parameters:(NSArray *)parameters
                            error:(NSError **)error {
  NSArray *rows = [self executeQuery:sql parameters:parameters error:error];
  if (rows == nil || [rows count] == 0) {
    return nil;
  }
  return rows[0];
}

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
  PGresult *result = [self runExecParamsSQL:sql parameters:parameters ?: @[] error:error];
  if (result == NULL) {
    return -1;
  }

  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_COMMAND_OK) {
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
  }
  ALNPQclear(result);
  return affected;
}

- (NSArray<NSDictionary *> *)executePreparedQueryNamed:(NSString *)name
                                            parameters:(NSArray *)parameters
                                                 error:(NSError **)error {
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

  NSArray *rows = [self rowsFromResult:result];
  ALNPQclear(result);
  return rows;
}

- (NSInteger)executePreparedCommandNamed:(NSString *)name
                              parameters:(NSArray *)parameters
                                   error:(NSError **)error {
  PGresult *result = [self runExecPreparedNamed:name parameters:parameters ?: @[] error:error];
  if (result == NULL) {
    return -1;
  }

  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_COMMAND_OK) {
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
  }
  ALNPQclear(result);
  return affected;
}

- (BOOL)runTransactionSQL:(NSString *)sql error:(NSError **)error {
  NSInteger affected = [self executeCommand:sql parameters:@[] error:error];
  return (affected >= 0);
}

- (BOOL)beginTransaction:(NSError **)error {
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

@end

@interface ALNPg ()

@property(nonatomic, copy, readwrite) NSString *connectionString;
@property(nonatomic, assign, readwrite) NSUInteger maxConnections;
@property(nonatomic, strong) NSMutableArray *idleConnections;
@property(nonatomic, assign) NSUInteger inUseConnections;

@end

@implementation ALNPg

- (NSString *)adapterName {
  return @"postgresql";
}

- (instancetype)initWithConnectionString:(NSString *)connectionString
                           maxConnections:(NSUInteger)maxConnections
                                    error:(NSError **)error {
  self = [super init];
  if (!self) {
    return nil;
  }

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
  @synchronized(self) {
    if ([self.idleConnections count] > 0) {
      ALNPgConnection *connection = [self.idleConnections lastObject];
      [self.idleConnections removeLastObject];
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

- (NSInteger)executeCommand:(NSString *)sql
                 parameters:(NSArray *)parameters
                      error:(NSError **)error {
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

- (BOOL)withTransaction:(BOOL (^)(ALNPgConnection *connection, NSError **error))block
                  error:(NSError **)error {
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
