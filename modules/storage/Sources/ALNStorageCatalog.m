#import "ALNStorageCatalog.h"
#import "ALNStorageModule.h"
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(_WIN32)
#include <windows.h>
#import "ALNPrivateStorage.h"
#else
#include <dlfcn.h>
#endif

// The stable SQLite C ABI is loaded at runtime, including the OS-provided
// winsqlite3.dll on Windows. No development headers/import libraries required.
typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;
static struct {
  int (*open_v2)(const char *, sqlite3 **, int, const char *);
  int (*close)(sqlite3 *);
  int (*busy_timeout)(sqlite3 *, int);
  int (*prepare_v2)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
  int (*step)(sqlite3_stmt *);
  int (*finalize)(sqlite3_stmt *);
  int (*bind_text)(sqlite3_stmt *, int, const char *, int, void (*)(void *));
  int (*bind_blob)(sqlite3_stmt *, int, const void *, int, void (*)(void *));
  const unsigned char *(*column_text)(sqlite3_stmt *, int);
  const void *(*column_blob)(sqlite3_stmt *, int);
  int (*column_bytes)(sqlite3_stmt *, int);
  const char *(*errmsg)(sqlite3 *);
  int (*errcode)(sqlite3 *);
} SQL;
static BOOL SQLAvailable;

static BOOL LoadSQLite(void) {
  @synchronized([ALNStorageCatalog class]) {
    static BOOL attempted;
    if (attempted) return SQLAvailable;
    attempted = YES;
#if defined(_WIN32)
    HMODULE library = LoadLibraryExW(L"winsqlite3.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
#define SYMBOL(name) GetProcAddress(library, "sqlite3_" #name)
#else
#if defined(__APPLE__)
    void *library = dlopen("libsqlite3.dylib", RTLD_NOW | RTLD_LOCAL);
#else
    void *library = dlopen("libsqlite3.so.0", RTLD_NOW | RTLD_LOCAL);
#endif
#define SYMBOL(name) dlsym(library, "sqlite3_" #name)
#endif
    if (library == NULL) return NO;
#define LOAD(name) SQL.name = (__typeof__(SQL.name))SYMBOL(name); if (SQL.name == NULL) return NO
    LOAD(open_v2); LOAD(close); LOAD(busy_timeout); LOAD(prepare_v2);
    LOAD(step); LOAD(finalize); LOAD(bind_text); LOAD(bind_blob);
    LOAD(column_text); LOAD(column_blob); LOAD(column_bytes); LOAD(errmsg); LOAD(errcode);
#undef LOAD
#undef SYMBOL
    SQLAvailable = YES;
    return YES;
  }
}

static NSError *CatalogError(NSString *message) {
  return [NSError errorWithDomain:ALNStorageModuleErrorDomain
                            code:ALNStorageModuleErrorPersistenceFailed
                        userInfo:@{NSLocalizedDescriptionKey : message ?: @"storage catalog failed"}];
}

static BOOL CatalogValueIsPropertyList(id value, NSUInteger depth) {
  if (depth > 128) return NO;
  if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
      [value isKindOfClass:[NSData class]] || [value isKindOfClass:[NSDate class]]) return YES;
  if ([value isKindOfClass:[NSArray class]]) {
    for (id entry in value) if (!CatalogValueIsPropertyList(entry, depth + 1)) return NO;
    return YES;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    for (id key in value) if (![key isKindOfClass:[NSString class]] || !CatalogValueIsPropertyList(value[key], depth + 1)) return NO;
    return YES;
  }
  return NO;
}

static BOOL CatalogStateIsValid(NSDictionary *state) {
  if (![state isKindOfClass:[NSDictionary class]]) return NO;
  for (NSString *section in @[@"objectsByIdentifier", @"uploadSessionsByIdentifier", @"objectIDsByCollection"]) {
    id values = state[section];
    if (values != nil && ![values isKindOfClass:[NSDictionary class]]) return NO;
    for (id key in values) {
      if (![key isKindOfClass:[NSString class]]) return NO;
      id value = values[key];
      if ([section isEqualToString:@"objectIDsByCollection"]) {
        if (![value isKindOfClass:[NSArray class]]) return NO;
        for (id identifier in value) if (![identifier isKindOfClass:[NSString class]]) return NO;
      } else if (![value isKindOfClass:[NSDictionary class]]) return NO;
    }
  }
  return state[@"activityLog"] == nil || [state[@"activityLog"] isKindOfClass:[NSArray class]];
}

static NSDictionary *RowsForState(NSDictionary *state, NSDictionary *previous) {
  NSMutableDictionary *membership = [NSMutableDictionary dictionary];
  NSDictionary *collections = state[@"objectIDsByCollection"] ?: @{};
  NSDictionary *oldMembership = previous[@"membership"] ?: @{};
  unsigned long long nextRank = 0;
  for (NSArray *entry in [oldMembership allValues]) nextRank = MAX(nextRank, [entry[1] unsignedLongLongValue] + 1);
  for (NSString *collection in collections) {
    for (NSString *objectID in collections[collection]) {
      NSArray *old = oldMembership[objectID];
      NSNumber *rank = [old[0] isEqual:collection] ? old[1] : @(nextRank++);
      membership[objectID] = @[collection, rank];
    }
  }
  return @{
    @"objects" : [NSDictionary dictionaryWithDictionary:state[@"objectsByIdentifier"] ?: @{}],
    @"sessions" : [NSDictionary dictionaryWithDictionary:state[@"uploadSessionsByIdentifier"] ?: @{}],
    @"membership" : membership,
    @"meta" : @{ @"root" : @{
      @"version" : state[@"version"] ?: @1,
      @"nextSequence" : state[@"nextSequence"] ?: @0,
      @"activityLog" : state[@"activityLog"] ?: @[],
    } },
  };
}

static NSDictionary *StateForRows(NSDictionary *rows) {
  NSMutableDictionary *collections = [NSMutableDictionary dictionary];
  NSDictionary *membership = rows[@"membership"] ?: @{};
  NSArray *ordered = [[membership allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
    NSComparisonResult collection = [membership[a][0] compare:membership[b][0]];
    return collection == NSOrderedSame ? [membership[a][1] compare:membership[b][1]] : collection;
  }];
  for (NSString *objectID in ordered) {
    NSString *collection = membership[objectID][0];
    if (collections[collection] == nil) collections[collection] = [NSMutableArray array];
    [collections[collection] addObject:objectID];
  }
  NSMutableDictionary *state = [NSMutableDictionary dictionaryWithDictionary:rows[@"meta"][@"root"] ?: @{}];
  state[@"objectsByIdentifier"] = rows[@"objects"] ?: @{};
  state[@"uploadSessionsByIdentifier"] = rows[@"sessions"] ?: @{};
  state[@"objectIDsByCollection"] = collections;
  return state;
}

@interface ALNStorageCatalog ()
@property(nonatomic, copy, readwrite) NSString *path;
@property(nonatomic, assign) sqlite3 *database;
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic, assign, readwrite) NSUInteger lastWrittenRowCount;
@end

@implementation ALNStorageCatalog

- (BOOL)fail:(NSError **)error {
  if (error != NULL) {
    int code = self.database != NULL ? SQL.errcode(self.database) : 0;
    NSString *message = self.database != NULL ? [NSString stringWithUTF8String:SQL.errmsg(self.database)] : @"SQLite could not open the storage catalog";
    *error = [NSError errorWithDomain:ALNStorageModuleErrorDomain
                                code:(code == 5 || code == 6) ? ALNStorageModuleErrorStateBusy : ALNStorageModuleErrorPersistenceFailed
                            userInfo:@{NSLocalizedDescriptionKey:message}];
  }
  return NO;
}

- (BOOL)execute:(const char *)sql error:(NSError **)error {
  sqlite3_stmt *statement = NULL;
  if (SQL.prepare_v2(self.database, sql, -1, &statement, NULL) != 0) return [self fail:error];
  int rc = SQL.step(statement);
  SQL.finalize(statement);
  return rc == 101 || [self fail:error];
}

- (instancetype)initWithPath:(NSString *)path legacyPath:(NSString *)legacyPath error:(NSError **)error {
  self = [super init];
  if (self == nil) return nil;
  if (!LoadSQLite()) {
    if (error != NULL) *error = CatalogError(@"SQLite runtime is required for storage persistence (libsqlite3.so.0, libsqlite3.dylib, or Windows winsqlite3.dll)");
    return nil;
  }
  _path = [path copy];
  _writeTimeoutSeconds = 10;
  NSString *parent = [path stringByDeletingLastPathComponent];
#if defined(_WIN32)
  if (![[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:error] ||
      !ALNWindowsSecurePrivatePath(parent, YES, error)) return nil;
  NSMutableData *wide = [[path dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
  [wide appendBytes:"\0\0" length:2];
  HANDLE file = CreateFileW((const wchar_t *)wide.bytes, GENERIC_READ | GENERIC_WRITE,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                            OPEN_ALWAYS, FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  if (file == INVALID_HANDLE_VALUE) {
    if (error != NULL) *error = CatalogError(@"storage catalog could not be created");
    return nil;
  }
  CloseHandle(file);
  if (!ALNWindowsSecurePrivatePath(path, NO, error)) return nil;
#else
  if (![[NSFileManager defaultManager] createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return nil;
  // Create owner-only before SQLite opens it (its journal inherits this mode).
  int fd = open(path.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
  struct stat info;
  if (fd < 0 || fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || fchmod(fd, 0600) != 0) {
    if (fd >= 0) close(fd);
    if (error != NULL) *error = CatalogError(@"storage catalog must be an owner-only regular file");
    return nil;
  }
  close(fd);
#endif
  sqlite3 *db = NULL;
  int rc = SQL.open_v2(path.UTF8String, &db, 0x00000002 | 0x00000004 | 0x00010000, NULL);
  self.database = db;
  if (rc != 0) { [self fail:error]; return nil; }
  SQL.busy_timeout(db, 10000);
  if (![self execute:"PRAGMA synchronous=FULL" error:error] ||
      ![self execute:"BEGIN IMMEDIATE" error:error]) return nil;
  BOOL committed = NO;
  @try {
    sqlite3_stmt *schema = NULL;
    if (SQL.prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name='catalog'", -1, &schema, NULL) != 0) { [self fail:error]; return nil; }
    BOOL existed = SQL.step(schema) == 100;
    SQL.finalize(schema);
    if (![self execute:"CREATE TABLE IF NOT EXISTS catalog(kind TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, PRIMARY KEY(kind,key))" error:error]) return nil;
    NSDictionary *state = [self readRowsWithError:error];
    if (state == nil) return nil;
    self.snapshot = state;
    if (state[@"meta"][@"root"] == nil) {
      if (existed) {
        if (error != NULL) *error = CatalogError(@"storage catalog is missing its committed metadata; refusing stale legacy import");
        return nil;
      }
      NSDictionary *legacy = @{};
      if ([[NSFileManager defaultManager] fileExistsAtPath:legacyPath]) {
        NSData *data = [NSData dataWithContentsOfFile:legacyPath];
        id decoded = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error] : nil;
        if (!CatalogStateIsValid(decoded)) {
          if (error != NULL && *error == nil) *error = CatalogError(@"legacy storage state could not be imported");
          return nil;
        }
        legacy = decoded;
      }
      if (![self writeRows:RowsForState(legacy, @{}) error:error]) return nil;
    }
    committed = [self execute:"COMMIT" error:error];
    if (!committed) return nil;
  } @finally {
    if (!committed) (void)[self execute:"ROLLBACK" error:NULL];
  }
  SQL.busy_timeout(db, 100);
  return self;
}

- (void)dealloc {
  if (_database != NULL) SQL.close(_database);
}

- (NSDictionary *)readRowsWithError:(NSError **)error {
  sqlite3_stmt *statement = NULL;
  if (SQL.prepare_v2(self.database, "SELECT kind,key,value FROM catalog", -1, &statement, NULL) != 0) { [self fail:error]; return nil; }
  NSMutableDictionary *rows = [NSMutableDictionary dictionary];
  int rc;
  BOOL valid = YES;
  while ((rc = SQL.step(statement)) == 100) {
    {
      NSString *kind = [NSString stringWithUTF8String:(const char *)SQL.column_text(statement, 0)];
      NSString *key = [NSString stringWithUTF8String:(const char *)SQL.column_text(statement, 1)];
      NSData *blob = [NSData dataWithBytes:SQL.column_blob(statement, 2) length:(NSUInteger)SQL.column_bytes(statement, 2)];
      id value = [NSPropertyListSerialization propertyListWithData:blob options:NSPropertyListImmutable format:NULL error:error];
      BOOL recordKind = [kind isEqualToString:@"objects"] || [kind isEqualToString:@"sessions"] || [kind isEqualToString:@"meta"];
      BOOL membershipKind = [kind isEqualToString:@"membership"];
      BOOL validValue = (recordKind && [value isKindOfClass:[NSDictionary class]]) ||
          (membershipKind && [value isKindOfClass:[NSArray class]] && [value count] == 2 &&
           [value[0] isKindOfClass:[NSString class]] && [value[1] isKindOfClass:[NSNumber class]]);
      if (!validValue || kind == nil || key == nil) {
        if (error != NULL) *error = CatalogError(@"storage catalog contains an invalid record");
        valid = NO; break;
      }
      if (rows[kind] == nil) rows[kind] = [NSMutableDictionary dictionary];
      rows[kind][key] = value;
    }
  }
  SQL.finalize(statement);
  if (!valid || rc != 101) { if (valid) [self fail:error]; return nil; }
  NSMutableDictionary *immutable = [NSMutableDictionary dictionary];
  for (NSString *kind in rows) immutable[kind] = [NSDictionary dictionaryWithDictionary:rows[kind]];
  return [NSDictionary dictionaryWithDictionary:immutable];
}

- (NSDictionary *)readStateWithError:(NSError **)error {
  @synchronized(self) {
    NSDictionary *rows = [self readRowsWithError:error];
    if (rows == nil) return nil;
    self.snapshot = rows;
    return StateForRows(rows);
  }
}

- (BOOL)writeRows:(NSDictionary *)rows error:(NSError **)error {
  self.lastWrittenRowCount = 0;
  for (NSString *kind in rows) {
    NSDictionary *old = self.snapshot[kind] ?: @{};
    NSDictionary *current = rows[kind];
    NSMutableSet *keys = [NSMutableSet setWithArray:[old allKeys]];
    [keys addObjectsFromArray:[current allKeys]];
    for (NSString *key in keys) {
      {
        id value = current[key];
        if (value != nil && [value isEqual:old[key]]) continue;
        NSData *data = nil;
        if (value != nil) {
          if (!CatalogValueIsPropertyList(value, 0)) {
            if (error != NULL) *error = CatalogError(@"storage catalog record is not a property list");
            return NO;
          }
          @try {
            data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
          } @catch (NSException *exception) {
            if (error != NULL) *error = CatalogError(@"storage catalog record is not a property list");
            return NO;
          }
          if (data == nil || data.length > INT_MAX) return NO;
        }
        sqlite3_stmt *statement = NULL;
        const char *sql = value == nil ? "DELETE FROM catalog WHERE kind=? AND key=?" :
            "INSERT OR REPLACE INTO catalog(kind,key,value) VALUES(?,?,?)";
        if (SQL.prepare_v2(self.database, sql, -1, &statement, NULL) != 0) return [self fail:error];
        BOOL bound = SQL.bind_text(statement, 1, kind.UTF8String, -1, (void (*)(void *))-1) == 0 &&
                     SQL.bind_text(statement, 2, key.UTF8String, -1, (void (*)(void *))-1) == 0;
        if (value != nil) bound = bound && SQL.bind_blob(statement, 3, data.bytes, (int)data.length, (void (*)(void *))-1) == 0;
        int rc = bound ? SQL.step(statement) : -1;
        SQL.finalize(statement);
        if (rc != 101) return [self fail:error];
        self.lastWrittenRowCount += 1;
      }
    }
  }
  return YES;
}

- (BOOL)writeState:(NSDictionary *)state error:(NSError **)error {
  @synchronized(self) {
    if (!CatalogStateIsValid(state)) {
      if (error != NULL) *error = CatalogError(@"storage catalog state has an invalid shape");
      return NO;
    }
    NSDictionary *rows = RowsForState(state, self.snapshot);
    SQL.busy_timeout(self.database, (int)MIN((double)INT_MAX, MAX(0, self.writeTimeoutSeconds * 1000)));
    if (![self execute:"BEGIN IMMEDIATE" error:error]) { SQL.busy_timeout(self.database, 100); return NO; }
    BOOL committed = NO;
    @try {
      if (![self writeRows:rows error:error]) return NO;
      committed = [self execute:"COMMIT" error:error];
      if (committed) self.snapshot = rows;
      return committed;
    } @finally {
      if (!committed) (void)[self execute:"ROLLBACK" error:NULL];
      SQL.busy_timeout(self.database, 100);
    }
  }
}
@end
