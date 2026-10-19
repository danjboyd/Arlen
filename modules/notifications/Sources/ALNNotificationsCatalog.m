#import "ALNNotificationsCatalog.h"
#import "ALNNotificationsModule.h"
#import "ALNPlatform.h"
#include <fcntl.h>
#include <errno.h>
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
  long long (*column_int64)(sqlite3_stmt *, int);
  const char *(*errmsg)(sqlite3 *);
  int (*errcode)(sqlite3 *);
} SQL;
static BOOL SQLAvailable;

static NSString *CatalogFileIdentity(NSString *path) {
#if defined(_WIN32)
  unsigned long long index = 0;
  if (!ALNPlatformFileVersion(path, &index, NULL, NULL)) return nil;
  return [NSString stringWithFormat:@"%llu", index];
#else
  struct stat info;
  if (lstat(path.fileSystemRepresentation, &info) != 0 || !S_ISREG(info.st_mode)) return nil;
  return [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)info.st_dev, (unsigned long long)info.st_ino];
#endif
}

static BOOL LoadSQLite(void) {
  @synchronized([ALNNotificationsCatalog class]) {
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
    LOAD(column_text); LOAD(column_blob); LOAD(column_bytes); LOAD(column_int64); LOAD(errmsg); LOAD(errcode);
#undef LOAD
#undef SYMBOL
    SQLAvailable = YES;
    return YES;
  }
}

static NSError *CatalogError(NSString *message) {
  return [NSError errorWithDomain:ALNNotificationsModuleErrorDomain
                            code:ALNNotificationsModuleErrorDeliveryFailed
                        userInfo:@{NSLocalizedDescriptionKey : message ?: @"notification catalog failed"}];
}

// A zero-byte marker records that this path has been initialized. It is never
// removed during normal operation. Creation follows the initial SQLite commit
// and must be durable before a constructor exposes the catalog to any writer.
static BOOL CatalogMarkerExists(NSString *path) {
#if defined(_WIN32)
  NSMutableData *wide = [[path dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
  [wide appendBytes:"\0\0" length:2];
  DWORD attributes = GetFileAttributesW((const wchar_t *)wide.bytes);
  return attributes != INVALID_FILE_ATTRIBUTES ||
         (GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND);
#else
  struct stat info;
  return lstat(path.fileSystemRepresentation, &info) == 0 || errno != ENOENT;
#endif
}

static BOOL EnsureCatalogMarker(NSString *path, NSError **error) {
  BOOL success = NO;
#if defined(_WIN32)
  NSMutableData *wide = [[path dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
  [wide appendBytes:"\0\0" length:2];
  HANDLE file = CreateFileW((const wchar_t *)wide.bytes, GENERIC_READ | GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS,
      FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_WRITE_THROUGH, NULL);
  if (file != INVALID_HANDLE_VALUE) {
    BY_HANDLE_FILE_INFORMATION info;
    success = GetFileInformationByHandle(file, &info) &&
        !(info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) &&
        ALNWindowsSecurePrivatePath(path, NO, error) && FlushFileBuffers(file);
    CloseHandle(file);
  }
#else
  int fd = open(path.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
  struct stat info;
  if (fd >= 0) {
    success = fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && fchmod(fd, 0600) == 0 && fsync(fd) == 0;
    close(fd);
  }
  if (success) {
    // Also persist the directory entry, not just the empty marker's inode.
    int directory = open(path.stringByDeletingLastPathComponent.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    success = directory >= 0 && fsync(directory) == 0;
    if (directory >= 0) close(directory);
  }
#endif
  if (!success && error != NULL && *error == nil) *error = CatalogError(@"could not durably create notification catalog initialization marker");
  return success;
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

static BOOL CatalogEntriesAreValid(id entries) {
  if (![entries isKindOfClass:[NSArray class]]) return NO;
  NSMutableSet *seen = [NSMutableSet set];
  for (id entry in entries) {
    if (![entry isKindOfClass:[NSDictionary class]]) return NO;
    NSString *identifier = entry[@"entryID"];
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0 || [seen containsObject:identifier]) return NO;
    [seen addObject:identifier];
  }
  return YES;
}

static BOOL CatalogStateIsValid(NSDictionary *state) {
  if (![state isKindOfClass:[NSDictionary class]]) return NO;
  if (state[@"version"] != nil && ![state[@"version"] isEqual:@1]) return NO;
  for (NSString *section in @[@"outboxEntries", @"recentFanoutEvents"]) {
    if (state[section] != nil && !CatalogEntriesAreValid(state[section])) return NO;
  }
  for (NSString *section in @[@"inboxByRecipient", @"preferencesByRecipient"]) {
    id values = state[section];
    if (values != nil && ![values isKindOfClass:[NSDictionary class]]) return NO;
    for (id key in values) {
      if (![key isKindOfClass:[NSString class]]) return NO;
      if ([section isEqualToString:@"inboxByRecipient"]) {
        if (!CatalogEntriesAreValid(values[key])) return NO;
      } else if (![values[key] isKindOfClass:[NSDictionary class]]) return NO;
    }
  }
  for (NSString *key in @[@"version", @"nextEntrySequence"]) {
    if (state[key] != nil && ![state[key] isKindOfClass:[NSNumber class]]) return NO;
  }
  return YES;
}

static id CatalogImmutableValue(id value) {
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *copy = [NSMutableDictionary dictionary];
    for (NSString *key in value) copy[key] = CatalogImmutableValue(value[key]);
    return [NSDictionary dictionaryWithDictionary:copy];
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *copy = [NSMutableArray array];
    for (id entry in value) [copy addObject:CatalogImmutableValue(entry)];
    return [NSArray arrayWithArray:copy];
  }
  return [value copy];
}

static NSDictionary *CatalogSnapshot(NSDictionary *rows, NSDictionary *previous) {
  NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
  for (NSString *kind in rows) {
    NSMutableDictionary *section = [NSMutableDictionary dictionary];
    for (NSString *key in rows[kind]) {
      id value = rows[kind][key];
      id old = previous[kind][key];
      section[key] = [value isEqual:old] ? old : CatalogImmutableValue(value);
    }
    snapshot[kind] = [NSDictionary dictionaryWithDictionary:section];
  }
  return [NSDictionary dictionaryWithDictionary:snapshot];
}

// Base64 is injective for UTF-8 strings and contains no NUL or separator.
static NSString *CatalogKey(NSString *value) {
  return [[value dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}

static void AddEntries(NSMutableDictionary *rows, NSArray *entries, NSString *recipient,
                       NSDictionary *previous, unsigned long long *nextRank) {
  for (NSDictionary *entry in entries) {
    NSString *key = [NSString stringWithFormat:@"%@:%@", CatalogKey(recipient), CatalogKey(entry[@"entryID"])];
    NSArray *old = previous[key];
    NSNumber *rank = old != nil ? old[1] : @((*nextRank)++);
    rows[key] = @[recipient, rank, entry];
  }
}

static NSDictionary *RowsForState(NSDictionary *state, NSDictionary *previous) {
  NSMutableDictionary *rows = [NSMutableDictionary dictionary];
  for (NSString *kind in @[@"outbox", @"inbox", @"fanout"]) {
    NSDictionary *old = previous[kind] ?: @{};
    unsigned long long nextRank = 0;
    for (NSArray *entry in [old allValues]) nextRank = MAX(nextRank, [entry[1] unsignedLongLongValue] + 1);
    NSMutableDictionary *current = [NSMutableDictionary dictionary];
    if ([kind isEqualToString:@"inbox"]) {
      for (NSString *recipient in state[@"inboxByRecipient"]) {
        AddEntries(current, state[@"inboxByRecipient"][recipient], recipient, old, &nextRank);
      }
    } else {
      AddEntries(current, state[[kind isEqualToString:@"outbox"] ? @"outboxEntries" : @"recentFanoutEvents"] ?: @[], @"", old, &nextRank);
    }
    rows[kind] = current;
  }
  NSMutableDictionary *preferences = [NSMutableDictionary dictionary];
  for (NSString *recipient in state[@"preferencesByRecipient"]) {
    preferences[CatalogKey(recipient)] = @{ @"recipient":recipient, @"value":state[@"preferencesByRecipient"][recipient] };
  }
  rows[@"preferences"] = preferences;
  rows[@"meta"] = @{ @"root":@{ @"version":state[@"version"] ?: @1,
                                 @"nextEntrySequence":state[@"nextEntrySequence"] ?: @0 } };
  return rows;
}

static NSDictionary *StateForRows(NSDictionary *rows) {
  NSMutableDictionary *state = [NSMutableDictionary dictionaryWithDictionary:rows[@"meta"][@"root"] ?: @{}];
  NSMutableDictionary *inbox = [NSMutableDictionary dictionary];
  for (NSString *kind in @[@"outbox", @"inbox", @"fanout"]) {
    NSArray *ordered = [[rows[kind] allValues] sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
      NSComparisonResult recipient = [a[0] compare:b[0]];
      return recipient == NSOrderedSame ? [a[1] compare:b[1]] : recipient;
    }];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSArray *row in ordered) {
      if ([kind isEqualToString:@"inbox"]) {
        if (inbox[row[0]] == nil) inbox[row[0]] = [NSMutableArray array];
        [inbox[row[0]] addObject:row[2]];
      } else [entries addObject:row[2]];
    }
    if (![kind isEqualToString:@"inbox"]) state[[kind isEqualToString:@"outbox"] ? @"outboxEntries" : @"recentFanoutEvents"] = entries;
  }
  state[@"inboxByRecipient"] = inbox;
  NSMutableDictionary *preferences = [NSMutableDictionary dictionary];
  for (NSDictionary *row in [rows[@"preferences"] allValues]) preferences[row[@"recipient"]] = row[@"value"];
  state[@"preferencesByRecipient"] = preferences;
  return CatalogImmutableValue(state);
}

@interface ALNNotificationsCatalog ()
@property(nonatomic, copy, readwrite) NSString *path;
@property(nonatomic, assign) sqlite3 *database;
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, copy) NSDictionary *cachedState;
@property(nonatomic, copy) NSString *fileIdentity;
@property(nonatomic, assign) long long cachedDataVersion;
@property(nonatomic, assign, readwrite) NSUInteger lastWrittenByteCount;
@property(nonatomic, assign, readwrite) NSUInteger lastReadRowCount;
@property(nonatomic, assign, readwrite) NSUInteger lastWrittenRowCount;
@end

@implementation ALNNotificationsCatalog

- (BOOL)fail:(NSError **)error {
  if (error != NULL) {
    NSString *message = self.database != NULL ? [NSString stringWithUTF8String:SQL.errmsg(self.database)] : @"SQLite could not open the notification catalog";
    *error = [NSError errorWithDomain:ALNNotificationsModuleErrorDomain
                                code:ALNNotificationsModuleErrorDeliveryFailed
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
  if (!ALNPlatformPathHasNoControlCharacters(path) || !ALNPlatformPathHasNoControlCharacters(legacyPath)) {
    if (error != NULL) *error = CatalogError(@"notification persistence paths must be nonempty and contain no control characters");
    return nil;
  }
  NSString *markerPath = [path stringByAppendingString:@".initialized"];
  if (CatalogMarkerExists(markerPath) && ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    if (error != NULL) *error = CatalogError(@"initialized notification catalog is missing; refusing stale legacy import");
    return nil;
  }
  _lock = [[NSLock alloc] init];
  _cachedDataVersion = -1;
  if (!LoadSQLite()) {
    if (error != NULL) *error = CatalogError(@"SQLite runtime is required for notification persistence (libsqlite3.so.0, libsqlite3.dylib, or Windows winsqlite3.dll)");
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
    if (error != NULL) *error = CatalogError(@"notification catalog could not be created");
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
    if (error != NULL) *error = CatalogError(@"notification catalog must be an owner-only regular file");
    return nil;
  }
  close(fd);
#endif
  sqlite3 *db = NULL;
  int rc = SQL.open_v2(path.UTF8String, &db, 0x00000002 | 0x00000004 | 0x00010000, NULL);
  self.database = db;
  if (rc != 0) { [self fail:error]; return nil; }
  self.fileIdentity = CatalogFileIdentity(path);
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
      if (existed || CatalogMarkerExists(markerPath)) {
        if (error != NULL) *error = CatalogError(@"notification catalog is missing its committed metadata; refusing stale legacy import");
        return nil;
      }
      NSDictionary *legacy = @{};
      if ([[NSFileManager defaultManager] fileExistsAtPath:legacyPath]) {
        NSData *data = [NSData dataWithContentsOfFile:legacyPath];
        id decoded = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error] : nil;
        if (!CatalogStateIsValid(decoded)) {
          if (error != NULL && *error == nil) *error = CatalogError(@"legacy notification state could not be imported");
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
  // A crash before this point leaves either an uncommitted import (safe to
  // retry) or a complete SQLite catalog (install its marker on the next open).
  // No runtime can acknowledge mutations until this durable marker exists.
  if (!EnsureCatalogMarker(markerPath, error)) return nil;
  SQL.busy_timeout(db, 100);
  if ([self readStateWithError:error] == nil) return nil;
  return self;
}

- (void)dealloc {
  if (_database != NULL) SQL.close(_database);
}

- (NSDictionary *)readRowsWithError:(NSError **)error {
  sqlite3_stmt *statement = NULL;
  if (SQL.prepare_v2(self.database, "SELECT kind,key,value FROM catalog", -1, &statement, NULL) != 0) { [self fail:error]; return nil; }
  NSMutableDictionary *rows = [NSMutableDictionary dictionary];
  self.lastReadRowCount = 0;
  int rc;
  BOOL valid = YES;
  while ((rc = SQL.step(statement)) == 100) {
    {
      NSString *kind = [[NSString alloc] initWithBytes:SQL.column_text(statement, 0)
                                               length:(NSUInteger)SQL.column_bytes(statement, 0) encoding:NSUTF8StringEncoding];
      NSString *key = [[NSString alloc] initWithBytes:SQL.column_text(statement, 1)
                                              length:(NSUInteger)SQL.column_bytes(statement, 1) encoding:NSUTF8StringEncoding];
      NSData *blob = [NSData dataWithBytes:SQL.column_blob(statement, 2) length:(NSUInteger)SQL.column_bytes(statement, 2)];
      id value = [NSPropertyListSerialization propertyListWithData:blob options:NSPropertyListImmutable format:NULL error:error];
      BOOL entryKind = [@[@"outbox", @"inbox", @"fanout"] containsObject:kind ?: @""];
      BOOL validValue = NO;
      if (entryKind && [value isKindOfClass:[NSArray class]] && [value count] == 3 &&
          [value[0] isKindOfClass:[NSString class]] && [value[1] isKindOfClass:[NSNumber class]] &&
          CatalogEntriesAreValid(@[value[2]])) {
        NSString *expected = [NSString stringWithFormat:@"%@:%@", CatalogKey(value[0]), CatalogKey(value[2][@"entryID"])];
        validValue = [key isEqual:expected] && ([kind isEqualToString:@"inbox"] || [value[0] length] == 0);
      } else if ([kind isEqualToString:@"preferences"] && [value isKindOfClass:[NSDictionary class]]) {
        validValue = [value[@"recipient"] isKindOfClass:[NSString class]] &&
                     [value[@"value"] isKindOfClass:[NSDictionary class]] &&
                     [key isEqual:CatalogKey(value[@"recipient"])];
      } else if ([kind isEqualToString:@"meta"] && [key isEqualToString:@"root"]) {
        validValue = [value isKindOfClass:[NSDictionary class]] && [value[@"version"] isEqual:@1] &&
                     [value[@"nextEntrySequence"] isKindOfClass:[NSNumber class]];
      }
      if (!validValue || kind == nil || key == nil) {
        if (error != NULL) *error = CatalogError(@"notification catalog contains an invalid record");
        valid = NO; break;
      }
      if (rows[kind] == nil) rows[kind] = [NSMutableDictionary dictionary];
      rows[kind][key] = value;
      self.lastReadRowCount += 1;
    }
  }
  SQL.finalize(statement);
  if (!valid || rc != 101) { if (valid) [self fail:error]; return nil; }
  NSMutableDictionary *immutable = [NSMutableDictionary dictionary];
  for (NSString *kind in rows) immutable[kind] = [NSDictionary dictionaryWithDictionary:rows[kind]];
  return [NSDictionary dictionaryWithDictionary:immutable];
}

- (BOOL)checkFileIdentity:(NSError **)error {
  if (![self.fileIdentity isEqual:CatalogFileIdentity(self.path)]) {
    if (error != NULL) *error = CatalogError(@"notification catalog was removed or replaced; refusing stale state");
    return NO;
  }
  return YES;
}

- (long long)dataVersionWithError:(NSError **)error {
  if (![self checkFileIdentity:error]) return -1;
  sqlite3_stmt *statement = NULL;
  if (SQL.prepare_v2(self.database, "PRAGMA data_version", -1, &statement, NULL) != 0) { [self fail:error]; return -1; }
  int rc = SQL.step(statement);
  long long version = rc == 100 ? SQL.column_int64(statement, 0) : -1;
  SQL.finalize(statement);
  if (rc != 100) [self fail:error];
  return version;
}

// The caller's process-shared state lock surrounds read/merge/write. SQLite's
// data_version invalidates the snapshot after another connection commits.
- (NSDictionary *)readStateWithError:(NSError **)error {
  [self.lock lock];
  @try {
    self.lastReadRowCount = 0;
    long long version = [self dataVersionWithError:error];
    if (version < 0) return nil;
    if (self.cachedState != nil && version == self.cachedDataVersion) return self.cachedState;
    NSDictionary *rows = [self readRowsWithError:error];
    if (rows == nil) return nil;
    if (rows[@"meta"][@"root"] == nil) {
      if (error != NULL) *error = CatalogError(@"notification catalog is missing its committed metadata");
      return nil;
    }
    self.snapshot = rows;
    self.cachedState = StateForRows(rows);
    // Capture the version before the SELECT: a racing commit must force the
    // following read to refresh, never label old rows with a newer version.
    self.cachedDataVersion = version;
    return self.cachedState;
  } @finally { [self.lock unlock]; }
}

- (BOOL)writeRows:(NSDictionary *)rows error:(NSError **)error {
  self.lastWrittenRowCount = 0;
  self.lastWrittenByteCount = 0;
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
            if (error != NULL) *error = CatalogError(@"notification catalog record is not a property list");
            return NO;
          }
          @try {
            data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
          } @catch (NSException *exception) {
            if (error != NULL) *error = CatalogError(@"notification catalog record is not a property list");
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
        self.lastWrittenByteCount += data.length;
      }
    }
  }
  return YES;
}

- (BOOL)writeState:(NSDictionary *)state error:(NSError **)error {
  [self.lock lock];
  @try {
    if (![self checkFileIdentity:error]) return NO;
    if (!CatalogStateIsValid(state)) {
      if (error != NULL) *error = CatalogError(@"notification catalog state has an invalid shape");
      return NO;
    }
    NSDictionary *rows = RowsForState(state, self.snapshot);
    SQL.busy_timeout(self.database, (int)MIN((double)INT_MAX, MAX(0, self.writeTimeoutSeconds * 1000)));
    if (![self execute:"BEGIN IMMEDIATE" error:error]) { SQL.busy_timeout(self.database, 100); return NO; }
    BOOL committed = NO;
    @try {
      if (![self writeRows:rows error:error]) return NO;
      committed = [self execute:"COMMIT" error:error];
      if (committed) {
        self.snapshot = CatalogSnapshot(rows, self.snapshot);
        self.cachedState = StateForRows(self.snapshot);
        // Own commits do not change data_version. Keep the previous version;
        // external commits still invalidate this snapshot on the next read.
      }
      return committed;
    } @finally {
      if (!committed) (void)[self execute:"ROLLBACK" error:NULL];
      SQL.busy_timeout(self.database, 100);
    }
  } @finally { [self.lock unlock]; }
}
@end
