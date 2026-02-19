#import "ALNPg.h"

#import <dlfcn.h>
#import <stdlib.h>

NSString *const ALNPgErrorDomain = @"Arlen.Data.Pg.Error";

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

static void *gLibpqHandle = NULL;
static NSString *gLibpqLoadError = nil;

static NSError *ALNPgMakeError(ALNPgErrorCode code,
                               NSString *message,
                               NSString *detail,
                               NSString *sql);

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
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"database error";
  if ([detail length] > 0) {
    userInfo[@"detail"] = detail;
  }
  if ([sql length] > 0) {
    userInfo[@"sql"] = sql;
  }
  return [NSError errorWithDomain:ALNPgErrorDomain code:code userInfo:userInfo];
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
  ALNExecStatusType status = ALNPQresultStatus(result);
  if (status != ALNPGRES_COMMAND_OK) {
    NSString *detail = [NSString stringWithUTF8String:ALNPQresultErrorMessage(result) ?: ""];
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"failed to prepare statement",
                              detail,
                              sql);
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
  const char **paramValues = NULL;
  int *paramLengths = NULL;
  int *paramFormats = NULL;
  NSMutableArray *buffers = [NSMutableArray arrayWithCapacity:count];

  if (count > 0) {
    paramValues = calloc(count, sizeof(const char *));
    paramLengths = calloc(count, sizeof(int));
    paramFormats = calloc(count, sizeof(int));
    for (NSUInteger idx = 0; idx < count; idx++) {
      id value = parameters[idx];
      NSString *stringValue = ALNPgStringFromParam(value);
      if (stringValue == nil) {
        paramValues[idx] = NULL;
        paramLengths[idx] = 0;
        paramFormats[idx] = 0;
        continue;
      }
      NSData *data = [stringValue dataUsingEncoding:NSUTF8StringEncoding];
      [buffers addObject:data ?: [NSData data]];
      paramValues[idx] = (const char *)[[buffers lastObject] bytes];
      paramLengths[idx] = (int)[[buffers lastObject] length];
      paramFormats[idx] = 0;
    }
  }

  PGresult *result = ALNPQexecParams(_conn,
                                  [sql UTF8String],
                                  (int)count,
                                  NULL,
                                  paramValues,
                                  paramLengths,
                                  paramFormats,
                                  0);

  if (paramValues != NULL) {
    free(paramValues);
  }
  if (paramLengths != NULL) {
    free(paramLengths);
  }
  if (paramFormats != NULL) {
    free(paramFormats);
  }

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
  const char **paramValues = NULL;
  int *paramLengths = NULL;
  int *paramFormats = NULL;
  NSMutableArray *buffers = [NSMutableArray arrayWithCapacity:count];

  if (count > 0) {
    paramValues = calloc(count, sizeof(const char *));
    paramLengths = calloc(count, sizeof(int));
    paramFormats = calloc(count, sizeof(int));
    for (NSUInteger idx = 0; idx < count; idx++) {
      id value = parameters[idx];
      NSString *stringValue = ALNPgStringFromParam(value);
      if (stringValue == nil) {
        paramValues[idx] = NULL;
        paramLengths[idx] = 0;
        paramFormats[idx] = 0;
        continue;
      }
      NSData *data = [stringValue dataUsingEncoding:NSUTF8StringEncoding];
      [buffers addObject:data ?: [NSData data]];
      paramValues[idx] = (const char *)[[buffers lastObject] bytes];
      paramLengths[idx] = (int)[[buffers lastObject] length];
      paramFormats[idx] = 0;
    }
  }

  PGresult *result = ALNPQexecPrepared(_conn,
                                    [name UTF8String],
                                    (int)count,
                                    paramValues,
                                    paramLengths,
                                    paramFormats,
                                    0);

  if (paramValues != NULL) {
    free(paramValues);
  }
  if (paramLengths != NULL) {
    free(paramLengths);
  }
  if (paramFormats != NULL) {
    free(paramFormats);
  }

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
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"query did not return rows",
                              detail,
                              sql);
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
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"command execution failed",
                              detail,
                              sql);
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
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"prepared query did not return rows",
                              detail,
                              name);
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
    ALNPQclear(result);
    if (error != NULL) {
      *error = ALNPgMakeError(ALNPgErrorQueryFailed,
                              @"prepared command execution failed",
                              detail,
                              name);
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

@end
