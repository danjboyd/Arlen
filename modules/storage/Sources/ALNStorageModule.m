#import "ALNConfig.h"
#import "ALNJSONSerialization.h"
#import "ALNPercentDecoding.h"
#import "ALNStorageModule.h"
#import "ALNStorageCatalog.h"

#import "../..//admin-ui/Sources/ALNAdminUIModule.h"
#import "../..//auth/Sources/ALNAuthModule.h"

#import "ALNDataCompat.h"
#import "ALNApplication.h"
#import "ALNContext.h"
#import "ALNController.h"
#import "ALNLogger.h"
#import "ALNPlatform.h"
#import "ALNRequest.h"
#import "ALNResponse.h"
#import "ALNFileResponse.h"
#import "ALNSecurityPrimitives.h"

#include <errno.h>
#include <string.h>
#include <sys/stat.h>
#if defined(_WIN32)
#include <windows.h>
#include <aclapi.h>
#else
#include <fcntl.h>
#include <unistd.h>
#endif

NSString *const ALNStorageModuleErrorDomain = @"Arlen.Modules.Storage.Error";

static NSString *const ALNStorageVariantJobIdentifier = @"storage.generate_variant";
static NSString *const ALNStorageCleanupJobIdentifier = @"storage.cleanup";
static NSUInteger const ALNStorageActivityLimit = 30;

static NSString *SMTrimmedString(id value) {
  if (![value isKindOfClass:[NSString class]]) {
    return @"";
  }
  return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *SMLowerTrimmedString(id value) {
  return [[SMTrimmedString(value) lowercaseString] copy];
}

static NSDictionary *SMNormalizeDictionary(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static NSArray *SMNormalizeArray(id value) {
  return [value isKindOfClass:[NSArray class]] ? value : @[];
}

static id SMPropertyListValue(id value) {
  if (value == nil || value == [NSNull null]) {
    return @"";
  }
  if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
      [value isKindOfClass:[NSData class]] || [value isKindOfClass:[NSDate class]]) {
    return value;
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableArray *items = [NSMutableArray array];
    for (id entry in (NSArray *)value) {
      [items addObject:SMPropertyListValue(entry)];
    }
    return items;
  }
  if ([value isKindOfClass:[NSDictionary class]]) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (id rawKey in [(NSDictionary *)value allKeys]) {
      NSString *key = SMTrimmedString(rawKey);
      if ([key length] == 0) {
        continue;
      }
      dictionary[key] = SMPropertyListValue([(NSDictionary *)value objectForKey:rawKey]);
    }
    return dictionary;
  }
  return [value description] ?: @"";
}

static NSString *SMResolvedPersistencePath(ALNApplication *application, NSDictionary *moduleConfig) {
  NSDictionary *persistence = [moduleConfig[@"persistence"] isKindOfClass:[NSDictionary class]]
                                  ? moduleConfig[@"persistence"]
                                  : @{};
  BOOL enabled = ![persistence[@"enabled"] respondsToSelector:@selector(boolValue)] ||
                 [persistence[@"enabled"] boolValue];
  if (!enabled) {
    return @"";
  }
  NSString *configured = SMTrimmedString(persistence[@"path"]);
  if ([configured length] > 0) {
    if ([configured hasPrefix:@"/"]) {
      return configured;
    }
    // Relative paths belong to the app, not the process working directory, so the
    // server and `arlen jobs worker` (which runs from the framework root) agree.
    return [application pathRelativeToAppRoot:configured];
  }
  NSString *environment = SMLowerTrimmedString(application.environment);
  if (ALNEnvironmentKindForName(environment) == ALNEnvironmentKindTest) {
    return @"";
  }
  return [application pathRelativeToAppRoot:
                   [NSString stringWithFormat:@"var/module_state/storage-%@.plist",
                                              ([environment length] > 0) ? environment : @"development"]];
}

static NSString *SMRandomHexString(NSUInteger byteCount);

// Writes data to path through a temporary file and a rename, with the file
// readable only by its owner (0600 on POSIX; protected token-user DACL on
// Windows): the catalog names every object and its signed-token nonce.
static BOOL SMWritePrivateFileAtomically(NSString *path, NSData *data, NSError **error) {
#if defined(_WIN32)
  NSString *temporaryPath = [NSString stringWithFormat:@"%@.%@.tmp", path, SMRandomHexString(8) ?: @"tmp"];
  NSMutableData *temporaryWide = [[[temporaryPath stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]
      dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
  [temporaryWide appendBytes:"\0\0" length:2];
  NSMutableData *destinationWide = [[[path stringByReplacingOccurrencesOfString:@"/" withString:@"\\"]
      dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
  [destinationWide appendBytes:"\0\0" length:2];
  HANDLE token = NULL;
  HANDLE file = INVALID_HANDLE_VALUE;
  PACL acl = NULL;
  NSMutableData *tokenData = nil;
  SECURITY_DESCRIPTOR security;
  SECURITY_ATTRIBUTES attributes;
  EXPLICIT_ACCESSW entry;
  DWORD failure = ERROR_SUCCESS;
  DWORD size = 0;
  BOOL created = NO;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    failure = GetLastError(); goto done;
  }
  GetTokenInformation(token, TokenUser, NULL, 0, &size);
  if (size == 0) { failure = GetLastError(); goto done; }
  tokenData = [NSMutableData dataWithLength:size];
  if (!GetTokenInformation(token, TokenUser, tokenData.mutableBytes, size, &size)) {
    failure = GetLastError(); goto done;
  }
  memset(&entry, 0, sizeof(entry));
  entry.grfAccessPermissions = FILE_ALL_ACCESS;
  entry.grfAccessMode = SET_ACCESS;
  entry.grfInheritance = NO_INHERITANCE;
  BuildTrusteeWithSidW(&entry.Trustee, ((TOKEN_USER *)tokenData.mutableBytes)->User.Sid);
  failure = SetEntriesInAclW(1, &entry, NULL, &acl);
  if (failure != ERROR_SUCCESS) goto done;
  if (!InitializeSecurityDescriptor(&security, SECURITY_DESCRIPTOR_REVISION) ||
      !SetSecurityDescriptorDacl(&security, TRUE, acl, FALSE) ||
      !SetSecurityDescriptorControl(&security, SE_DACL_PROTECTED, SE_DACL_PROTECTED)) {
    failure = GetLastError(); goto done;
  }
  attributes.nLength = sizeof(attributes);
  attributes.lpSecurityDescriptor = &security;
  attributes.bInheritHandle = FALSE;
  // Private at creation, exclusive, and never inherited by a spawned worker.
  // A collision must fail without modifying or removing the existing path.
  file = CreateFileW((const wchar_t *)temporaryWide.bytes, GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_DELETE, &attributes, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) { failure = GetLastError(); goto done; }
  created = YES;
  for (NSUInteger offset = 0; offset < data.length;) {
    DWORD count = (DWORD)MIN(data.length - offset, (NSUInteger)MAXDWORD);
    DWORD written = 0;
    if (!WriteFile(file, (const uint8_t *)data.bytes + offset, count, &written, NULL)) {
      failure = GetLastError(); goto done;
    }
    if (written == 0) { failure = ERROR_WRITE_FAULT; goto done; }
    offset += written;
  }
  if (!FlushFileBuffers(file)) { failure = GetLastError(); goto done; }
  if (!CloseHandle(file)) {
    failure = GetLastError(); goto done;
  }
  file = INVALID_HANDLE_VALUE;
  // Same-directory rename keeps the private source DACL when replacing an
  // older permissive catalog; the old file survives a failed replacement.
  if (!MoveFileExW((const wchar_t *)temporaryWide.bytes, (const wchar_t *)destinationWide.bytes,
          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    failure = GetLastError(); goto done;
  }
  created = NO;
done:
  if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
  if (created) DeleteFileW((const wchar_t *)temporaryWide.bytes);
  if (acl != NULL) LocalFree(acl);
  if (token != NULL) CloseHandle(token);
  if (failure != ERROR_SUCCESS && error != NULL) {
    *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:failure
        userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"could not write private storage catalog %@", path]}];
  }
  return failure == ERROR_SUCCESS;
#else
  NSString *suffix = SMRandomHexString(8) ?: @"tmp";
  NSString *temporaryPath = [NSString stringWithFormat:@"%@.%@.tmp", path, suffix];
  const char *temporary = [temporaryPath fileSystemRepresentation];
  int descriptor = -1;
  do {
    descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
  } while (descriptor < 0 && errno == EINTR);
  BOOL ok = (descriptor >= 0) && fchmod(descriptor, 0600) == 0;
  const uint8_t *bytes = [data bytes];
  NSUInteger remaining = [data length];
  while (ok && remaining > 0) {
    ssize_t written = write(descriptor, bytes, remaining);
    if (written < 0 && errno == EINTR) {
      continue;
    }
    if (written <= 0) {
      ok = NO;
      break;
    }
    bytes += written;
    remaining -= (NSUInteger)written;
  }
  int savedErrno = ok ? 0 : errno;
  if (descriptor >= 0 && close(descriptor) != 0 && ok) {
    ok = NO;
    savedErrno = errno;
  }
  if (ok && rename(temporary, [path fileSystemRepresentation]) != 0) {
    ok = NO;
    savedErrno = errno;
  }
  if (!ok) {
    (void)unlink(temporary);
    if (error != NULL) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                   code:savedErrno
                               userInfo:@{
                                 NSLocalizedDescriptionKey : [NSString stringWithFormat:@"could not write %@: %s",
                                                                                        path, strerror(savedErrno)],
                               }];
    }
  }
  return ok;
#endif
}

static NSDictionary *SMReadPropertyListAtPath(NSString *path, NSError **error) {
  NSString *statePath = SMTrimmedString(path);
  if ([statePath length] == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:statePath]) {
    return nil;
  }
  NSData *data = ALNDataReadFromFile(statePath, 0, error);
  if (data == nil) {
    return nil;
  }
  NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
  id object = [NSPropertyListSerialization propertyListWithData:data
                                                        options:NSPropertyListMutableContainersAndLeaves
                                                         format:&format
                                                          error:error];
  return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static BOOL SMWritePropertyListAtPath(NSString *path, NSDictionary *payload, NSError **error) {
  NSString *statePath = SMTrimmedString(path);
  if ([statePath length] == 0) {
    return YES;
  }
  NSString *parent = [statePath stringByDeletingLastPathComponent];
  if ([parent length] > 0 &&
      ![[NSFileManager defaultManager] createDirectoryAtPath:parent
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:error]) {
    return NO;
  }
  // XML, not binary: GNUstep's binary writer takes time quadratic in the
  // number of objects (seconds past a few thousand, all under the state
  // lock). Reading detects the format, so older binary files still load.
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:SMPropertyListValue(payload)
                                                            format:NSPropertyListXMLFormat_v1_0
                                                           options:0
                                                             error:error];
  if (data == nil) {
    return NO;
  }
  return SMWritePrivateFileAtomically(statePath, data, error);
}

static NSError *SMError(ALNStorageModuleErrorCode code, NSString *message, NSDictionary *details) {
  NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
  userInfo[NSLocalizedDescriptionKey] = message ?: @"storage module error";
  return [NSError errorWithDomain:ALNStorageModuleErrorDomain code:code userInfo:userInfo];
}

static const NSUInteger SMMinimumSigningSecretLength = 32;

static BOOL SMEnvironmentAllowsEphemeralSigningKey(NSString *environment) {
  return ALNEnvironmentIsDevelopmentLike(environment);
}

static NSData *SMEphemeralSigningKeyData(void) {
  return ALNSecureRandomData(32);
}

// Object and upload-session IDs, and per-object token nonces, are random so
// that processes sharing one state file (propane workers, the jobs worker)
// never hand out the same ID, and an ID never names a different object later.
static NSString *SMRandomHexString(NSUInteger byteCount) {
  NSData *bytes = ALNSecureRandomData(byteCount);
  if ([bytes length] != byteCount) {
    return nil;
  }
  const unsigned char *raw = [bytes bytes];
  NSMutableString *hex = [NSMutableString stringWithCapacity:byteCount * 2];
  for (NSUInteger idx = 0; idx < byteCount; idx++) {
    [hex appendFormat:@"%02x", raw[idx]];
  }
  return hex;
}

static NSString *SMRandomIdentifier(NSString *prefix) {
  NSString *hex = SMRandomHexString(16);
  return ([hex length] > 0) ? [NSString stringWithFormat:@"%@-%@", prefix, hex] : nil;
}

// Changes whenever the state file is replaced (each write is an atomic
// rename), so a process can tell another process wrote it.
static NSString *SMStateFileStamp(NSString *path) {
  if ([path length] == 0) {
    return @"";
  }
#if defined(_WIN32)
  unsigned long long fileIndex = 0;
  unsigned long long writeTime = 0;
  unsigned long long changeTime = 0;
  if (!ALNPlatformFileVersion(path, &fileIndex, &writeTime, &changeTime)) {
    return @"";
  }
  return [NSString stringWithFormat:@"%llu:%llu:%llu", fileIndex, writeTime, changeTime];
#else
  // Nanosecond times: an inode freed by one rename can be reused by the next
  // write, so the inode alone does not tell versions apart.
  struct stat info;
  if (stat([path fileSystemRepresentation], &info) != 0) {
    return @"";
  }
#if defined(__APPLE__)
  long long mtimeNanos = (long long)info.st_mtimespec.tv_nsec;
  long long ctimeNanos = (long long)info.st_ctimespec.tv_nsec;
#else
  long long mtimeNanos = (long long)info.st_mtim.tv_nsec;
  long long ctimeNanos = (long long)info.st_ctim.tv_nsec;
#endif
  return [NSString stringWithFormat:@"%llu:%lld:%lld.%09lld:%lld.%09lld",
                                    (unsigned long long)info.st_ino,
                                    (long long)info.st_size,
                                    (long long)info.st_mtime, mtimeNanos,
                                    (long long)info.st_ctime, ctimeNanos];
#endif
}

static const NSTimeInterval SMDefaultLockTimeoutSeconds = 10.0;
static const NSTimeInterval SMStaleTemporaryStateFileSeconds = 5.0;

static NSString *SMRecordChecksum(NSDictionary *record) {
  NSString *checksum = SMTrimmedString(record[@"checksumSHA256"]);
  if ([checksum length] == 0 && [record[@"analysis"] isKindOfClass:[NSDictionary class]]) {
    checksum = SMTrimmedString(record[@"analysis"][@"checksumSHA256"]);
  }
  return [checksum lowercaseString];
}

// The bytes an adapter returns must be the ones stored for this record: a
// misconfigured or swapped attachment must never be served in its place.
static BOOL SMAttachmentDataMatchesRecord(NSData *data, NSDictionary *record) {
  if (![data isKindOfClass:[NSData class]]) {
    return NO;
  }
  id size = record[@"sizeBytes"];
  if ([size respondsToSelector:@selector(unsignedIntegerValue)] && [size unsignedIntegerValue] != [data length]) {
    return NO;
  }
  NSString *expected = SMRecordChecksum(record);
  if ([expected length] == 0) {
    return YES;
  }
  NSString *actual = ALNLowercaseHexStringFromData(ALNSHA256(data)) ?: @"";
  return [actual isEqualToString:expected];
}

// storageModule.persistence.lockTimeoutSeconds: how long a change waits for
// another process's state lock before failing.
static NSTimeInterval SMConfiguredLockTimeoutSeconds(NSDictionary *moduleConfig) {
  NSDictionary *persistence = [moduleConfig[@"persistence"] isKindOfClass:[NSDictionary class]]
                                  ? moduleConfig[@"persistence"]
                                  : @{};
  id value = persistence[@"lockTimeoutSeconds"];
  if ([value respondsToSelector:@selector(doubleValue)] && [value doubleValue] > 0.0) {
    return [value doubleValue];
  }
  return SMDefaultLockTimeoutSeconds;
}

// storageModule.persistence.startupLockTimeoutSeconds: the longer wait for the
// startup cleanup, at least the request timeout.
static NSTimeInterval SMConfiguredStartupLockTimeoutSeconds(NSDictionary *moduleConfig, NSTimeInterval requestTimeout) {
  NSDictionary *persistence = [moduleConfig[@"persistence"] isKindOfClass:[NSDictionary class]]
                                  ? moduleConfig[@"persistence"]
                                  : @{};
  id value = persistence[@"startupLockTimeoutSeconds"];
  NSTimeInterval timeout = ([value respondsToSelector:@selector(doubleValue)] && [value doubleValue] > 0.0)
                               ? [value doubleValue]
                               : 60.0;
  return MAX(timeout, requestTimeout);
}

static NSError *SMStateLockError(NSString *lockPath, int lockErrno, NSTimeInterval timeoutSeconds) {
  NSString *message =
      (lockErrno == ETIMEDOUT)
          ? [NSString stringWithFormat:@"storage state lock was not released within %.1f seconds", timeoutSeconds]
          : @"storage state lock could not be acquired";
  return [NSError errorWithDomain:ALNStorageModuleErrorDomain
                             code:(lockErrno == ETIMEDOUT) ? ALNStorageModuleErrorStateBusy
                                                           : ALNStorageModuleErrorPersistenceFailed
                         userInfo:@{
                           NSLocalizedDescriptionKey : message,
                           @"path" : lockPath ?: @"",
                           @"errno" : @(lockErrno),
                         }];
}

static NSString *SMPathJoin(NSString *prefix, NSString *suffix) {
  NSString *cleanPrefix = SMTrimmedString(prefix);
  if ([cleanPrefix length] == 0) {
    cleanPrefix = @"/storage";
  }
  if (![cleanPrefix hasPrefix:@"/"]) {
    cleanPrefix = [@"/" stringByAppendingString:cleanPrefix];
  }
  while ([cleanPrefix hasSuffix:@"/"] && [cleanPrefix length] > 1) {
    cleanPrefix = [cleanPrefix substringToIndex:([cleanPrefix length] - 1)];
  }
  NSString *cleanSuffix = SMTrimmedString(suffix);
  while ([cleanSuffix hasPrefix:@"/"]) {
    cleanSuffix = [cleanSuffix substringFromIndex:1];
  }
  if ([cleanSuffix length] == 0) {
    return cleanPrefix;
  }
  return [NSString stringWithFormat:@"%@/%@", cleanPrefix, cleanSuffix];
}

static NSString *SMConfiguredPath(NSDictionary *moduleConfig, NSString *key, NSString *defaultSuffix) {
  NSDictionary *paths = [moduleConfig[@"paths"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"paths"] : @{};
  NSString *prefix = SMTrimmedString(paths[@"prefix"]);
  if ([prefix length] == 0) {
    prefix = @"/storage";
  }
  NSString *override = SMTrimmedString(paths[key]);
  if ([override hasPrefix:@"/"]) {
    return override;
  }
  if ([override length] > 0) {
    return SMPathJoin(prefix, override);
  }
  return SMPathJoin(prefix, defaultSuffix);
}

static NSString *SMQueryDecodeComponent(NSString *component) {
  return ALNPercentDecodedString(component ?: @"", YES) ?: @"";
}

static NSDictionary *SMJSONParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  id object = [ALNJSONSerialization JSONObjectWithData:body options:0 error:NULL];
  return [object isKindOfClass:[NSDictionary class]] ? object : @{};
}

static NSDictionary *SMFormParametersFromBody(NSData *body) {
  if ([body length] == 0) {
    return @{};
  }
  NSString *raw = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
  if ([raw length] == 0) {
    return @{};
  }
  NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
  for (NSString *pair in [raw componentsSeparatedByString:@"&"]) {
    if ([pair length] == 0) {
      continue;
    }
    NSRange separator = [pair rangeOfString:@"="];
    NSString *name = (separator.location == NSNotFound) ? pair : [pair substringToIndex:separator.location];
    NSString *value = (separator.location == NSNotFound) ? @"" : [pair substringFromIndex:(separator.location + 1)];
    NSString *decodedName = SMQueryDecodeComponent(name);
    if ([decodedName length] == 0) {
      continue;
    }
    parameters[decodedName] = SMQueryDecodeComponent(value);
  }
  return parameters;
}

// Where to send a user who needs higher assurance: the auth module's configurable
// step-up target (authModule.paths.stepUp). An older auth module has only
// totpPath, so fall back to it.
@protocol SMStepUpPathSource <NSObject>
@optional
- (nullable NSString *)stepUpPath;
- (nullable NSString *)totpPath;
@end

static NSString *SMStepUpPath(id runtime) {
  id<SMStepUpPathSource> source = runtime;
  NSString *path = [source respondsToSelector:@selector(stepUpPath)] ? [source stepUpPath] : nil;
  if ([path length] == 0 && [source respondsToSelector:@selector(totpPath)]) {
    path = [source totpPath];
  }
  return ([path length] > 0) ? path : @"/auth/mfa/totp";
}

static NSString *SMStepUpLocation(id runtime, NSString *encodedReturnTo) {
  NSString *path = SMStepUpPath(runtime);
  NSString *separator = [path containsString:@"?"] ? @"&" : @"?";
  return [NSString stringWithFormat:@"%@%@return_to=%@", path, separator, encodedReturnTo ?: @""];
}

static NSString *SMPercentEncodedQueryComponent(NSString *value) {
  NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
  [allowed removeCharactersInString:@"&=+"];
  return [SMTrimmedString(value) stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

// RFC 9110 token characters.
static BOOL SMIsMediaTypeTokenString(NSString *value) {
  static NSCharacterSet *invalid = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    invalid = [[NSCharacterSet
        characterSetWithCharactersInString:
            @"!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"] invertedSet];
  });
  return [value length] > 0 && [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

// Parses a declared content type as exactly one media type: `type/subtype`
// with optional `; name=value` token parameters. Commas (media type lists),
// quoted strings, control and non-ASCII characters are rejected. Returns the
// lowercased `type/subtype`, plus `; charset=<value>` when a well-formed
// charset parameter is present; other parameters are dropped. Returns nil when
// the value is not a single well-formed media type, and
// `application/octet-stream` when it is empty.
static NSString *SMNormalizedDeclaredContentType(NSString *rawValue) {
  NSString *value = [rawValue isKindOfClass:[NSString class]] ? SMTrimmedString(rawValue) : @"";
  if ([value length] == 0) {
    return @"application/octet-stream";
  }
  for (NSUInteger index = 0; index < [value length]; index++) {
    unichar character = [value characterAtIndex:index];
    if (character < 0x20 || character >= 0x7f || character == ',' || character == '"' || character == '\\') {
      return nil;
    }
  }
  NSArray<NSString *> *parts = [value componentsSeparatedByString:@";"];
  NSArray<NSString *> *typeParts = [SMTrimmedString(parts[0]) componentsSeparatedByString:@"/"];
  if ([typeParts count] != 2 || !SMIsMediaTypeTokenString(typeParts[0]) || !SMIsMediaTypeTokenString(typeParts[1])) {
    return nil;
  }
  NSString *charset = nil;
  for (NSUInteger index = 1; index < [parts count]; index++) {
    NSString *parameter = SMTrimmedString(parts[index]);
    NSRange equals = [parameter rangeOfString:@"="];
    if (equals.location == NSNotFound) {
      return nil;
    }
    NSString *name = [parameter substringToIndex:equals.location];
    NSString *parameterValue = [parameter substringFromIndex:NSMaxRange(equals)];
    if (!SMIsMediaTypeTokenString(name) || !SMIsMediaTypeTokenString(parameterValue)) {
      return nil;
    }
    if ([[name lowercaseString] isEqualToString:@"charset"]) {
      charset = [parameterValue lowercaseString];
    }
  }
  NSString *mediaType = [[NSString stringWithFormat:@"%@/%@", typeParts[0], typeParts[1]] lowercaseString];
  return (charset != nil) ? [NSString stringWithFormat:@"%@; charset=%@", mediaType, charset] : mediaType;
}

// The media type without parameters, lowercased: "Image/PNG; q=1" -> "image/png".
static NSString *SMBaseContentType(NSString *contentType) {
  NSString *type = SMLowerTrimmedString(contentType);
  NSRange separator = [type rangeOfString:@";"];
  if (separator.location != NSNotFound) {
    type = SMTrimmedString([type substringToIndex:separator.location]);
  }
  return type;
}

// Types a browser renders as an active document (markup that can run script).
// Wildcard patterns such as `*/*` or `image/*` never admit them; a collection
// must list them explicitly.
static BOOL SMContentTypeIsActiveDocument(NSString *contentType) {
  static NSSet<NSString *> *activeTypes = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    activeTypes = [NSSet setWithArray:@[ @"text/html", @"image/svg+xml", @"application/xhtml+xml" ]];
  });
  return [activeTypes containsObject:SMBaseContentType(contentType)];
}

static BOOL SMContentTypeMatches(NSString *candidate, NSString *allowedPattern) {
  NSString *type = SMBaseContentType(candidate);
  NSString *pattern = SMBaseContentType(allowedPattern);
  if ([pattern length] == 0 || [pattern isEqualToString:@"*/*"]) {
    return !SMContentTypeIsActiveDocument(type);
  }
  if ([pattern hasSuffix:@"/*"]) {
    NSString *prefix = [pattern substringToIndex:([pattern length] - 1)];
    return [type hasPrefix:prefix] && !SMContentTypeIsActiveDocument(type);
  }
  return [type isEqualToString:pattern];
}

// Downloads are served inline only for media types browsers display without
// running script. Everything else is sent as an attachment.
static BOOL SMContentTypeAllowsInlineDownload(NSString *contentType) {
  static NSSet<NSString *> *inlineTypes = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    inlineTypes = [NSSet setWithArray:@[
      @"image/png", @"image/jpeg", @"image/gif", @"image/webp", @"image/avif", @"application/pdf"
    ]];
  });
  NSString *type = SMBaseContentType(contentType);
  if ([inlineTypes containsObject:type]) {
    return YES;
  }
  return ([type hasPrefix:@"audio/"] || [type hasPrefix:@"video/"]) && [type length] > 6;
}

// An ASCII filename safe to quote in Content-Disposition: letters, digits and
// `._-`; anything else becomes `_`. Leading dots are dropped.
static NSString *SMSafeDownloadFilename(NSString *name) {
  NSString *base = [SMTrimmedString(name) lastPathComponent] ?: @"";
  NSMutableString *safe = [NSMutableString string];
  for (NSUInteger index = 0; index < [base length] && [safe length] < 150; index++) {
    unichar character = [base characterAtIndex:index];
    BOOL allowed = (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') ||
                   (character >= '0' && character <= '9') || character == '.' || character == '-' ||
                   character == '_';
    if (character == '.' && [safe length] == 0) {
      continue;
    }
    [safe appendString:allowed ? [NSString stringWithCharacters:&character length:1] : @"_"];
  }
  return ([safe length] > 0) ? [NSString stringWithString:safe] : @"download";
}

static NSString *SMContentDispositionForDownload(NSString *name, BOOL inlineDisposition) {
  NSString *fallback = SMSafeDownloadFilename(name);
  NSString *disposition = [NSString stringWithFormat:@"%@; filename=\"%@\"",
                                                     inlineDisposition ? @"inline" : @"attachment",
                                                     fallback];
  NSString *original = [SMTrimmedString(name) lastPathComponent] ?: @"";
  NSCharacterSet *unreserved =
      [NSCharacterSet characterSetWithCharactersInString:
                          @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
  NSString *encoded = [original stringByAddingPercentEncodingWithAllowedCharacters:unreserved];
  if ([encoded length] > 0 && ![encoded isEqualToString:fallback] && [encoded length] <= 600) {
    disposition = [disposition stringByAppendingFormat:@"; filename*=UTF-8''%@", encoded];
  }
  return disposition;
}

static NSArray<NSString *> *SMNormalizedContentTypes(id rawValue) {
  NSMutableArray<NSString *> *types = [NSMutableArray array];
  for (id entry in SMNormalizeArray(rawValue)) {
    NSString *type = SMLowerTrimmedString(entry);
    if ([type length] == 0 || [types containsObject:type]) {
      continue;
    }
    [types addObject:type];
  }
  if ([types count] == 0) {
    [types addObject:@"*/*"];
  }
  return [NSArray arrayWithArray:types];
}

static NSArray<NSDictionary *> *SMNormalizedVariantDefinitions(id rawVariants) {
  NSMutableArray<NSDictionary *> *variants = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  NSArray *entries = [rawVariants isKindOfClass:[NSArray class]] ? rawVariants : @[];
  for (id entry in entries) {
    if (![entry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSString *identifier = SMLowerTrimmedString(entry[@"identifier"]);
    if ([identifier length] == 0 || [seen containsObject:identifier]) {
      continue;
    }
    [seen addObject:identifier];
    [variants addObject:@{
      @"identifier" : identifier,
      @"label" : ([SMTrimmedString(entry[@"label"]) length] > 0) ? SMTrimmedString(entry[@"label"]) : [identifier capitalizedString],
      @"contentType" : ([SMLowerTrimmedString(entry[@"contentType"]) length] > 0) ? SMLowerTrimmedString(entry[@"contentType"]) : @"application/octet-stream",
      @"strategy" : ([SMLowerTrimmedString(entry[@"strategy"]) length] > 0) ? SMLowerTrimmedString(entry[@"strategy"]) : @"copy",
      @"async" : @([entry[@"async"] respondsToSelector:@selector(boolValue)] ? [entry[@"async"] boolValue] : YES),
    }];
  }
  return [variants sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    return [SMTrimmedString(left[@"identifier"]) compare:SMTrimmedString(right[@"identifier"])];
  }];
}

static NSDictionary *SMTokenPayloadDecode(NSString *token, NSData *keyData, NSError **error) {
  NSArray<NSString *> *parts = [SMTrimmedString(token) componentsSeparatedByString:@"."];
  if ([parts count] != 2) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token format is invalid", nil);
    }
    return nil;
  }
  NSString *payloadPart = parts[0] ?: @"";
  NSString *signaturePart = parts[1] ?: @"";
  NSData *expectedDigest = ALNHMACSHA256([payloadPart dataUsingEncoding:NSUTF8StringEncoding], keyData ?: [NSData data]);
  NSString *expectedSignature = ALNBase64URLStringFromData(expectedDigest) ?: @"";
  NSData *expectedData = [expectedSignature dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  NSData *actualData = [signaturePart dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
  if (!ALNConstantTimeDataEquals(expectedData, actualData)) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token signature was rejected", nil);
    }
    return nil;
  }
  NSData *payloadData = ALNDataFromBase64URLString(payloadPart);
  if (payloadData == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token payload could not be decoded", nil);
    }
    return nil;
  }
  id object = [ALNJSONSerialization JSONObjectWithData:payloadData options:0 error:NULL];
  if (![object isKindOfClass:[NSDictionary class]]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token payload is invalid", nil);
    }
    return nil;
  }
  return object;
}

static NSString *SMCreateSignedToken(NSDictionary *payload, NSData *keyData) {
  NSData *payloadData = [NSJSONSerialization dataWithJSONObject:(payload ?: @{}) options:0 error:NULL];
  NSString *payloadPart = ALNBase64URLStringFromData(payloadData ?: [NSData data]) ?: @"";
  NSData *digest = ALNHMACSHA256([payloadPart dataUsingEncoding:NSUTF8StringEncoding], keyData ?: [NSData data]);
  NSString *signaturePart = ALNBase64URLStringFromData(digest ?: [NSData data]) ?: @"";
  return [NSString stringWithFormat:@"%@.%@", payloadPart, signaturePart];
}

static NSDictionary *SMAnalyzeObjectData(NSString *name,
                                         NSString *contentType,
                                         NSData *data,
                                         NSDictionary *metadata,
                                         NSArray<NSDictionary *> *variants) {
  NSString *normalizedName = SMTrimmedString(name);
  NSString *normalizedContentType = ([SMLowerTrimmedString(contentType) length] > 0)
                                        ? SMLowerTrimmedString(contentType)
                                        : @"application/octet-stream";
  NSString *extension = [[[normalizedName pathExtension] lowercaseString] copy] ?: @"";
  BOOL previewable = [normalizedContentType hasPrefix:@"image/"] || [normalizedContentType isEqualToString:@"application/pdf"];
  NSMutableDictionary *analysis = [@{
    @"sizeBytes" : @([data length]),
    @"checksumSHA256" : ALNLowercaseHexStringFromData(ALNSHA256(data ?: [NSData data])) ?: @"",
    @"fileExtension" : extension ?: @"",
    @"previewable" : @(previewable),
    @"variantCapable" : @([(variants ?: @[]) count] > 0),
    @"contentType" : normalizedContentType,
  } mutableCopy];
  NSNumber *width = [metadata[@"width"] respondsToSelector:@selector(integerValue)] ? metadata[@"width"] : nil;
  NSNumber *height = [metadata[@"height"] respondsToSelector:@selector(integerValue)] ? metadata[@"height"] : nil;
  if (width != nil || height != nil) {
    analysis[@"dimensions"] = @{
      @"width" : width ?: @0,
      @"height" : height ?: @0,
    };
  }
  return [NSDictionary dictionaryWithDictionary:analysis];
}

static NSDictionary *SMAttachmentAdapterCapabilities(id<ALNAttachmentAdapter> adapter) {
  NSDictionary *capabilities =
      [adapter respondsToSelector:@selector(attachmentAdapterCapabilities)]
          ? [adapter attachmentAdapterCapabilities]
          : nil;
  if (![capabilities isKindOfClass:[NSDictionary class]]) {
    capabilities = @{};
  }
  NSMutableDictionary *normalized = [NSMutableDictionary dictionaryWithDictionary:@{
    @"temporaryDownloadURL" : @NO,
    @"readOnly" : @NO,
    @"scoped" : @NO,
    @"mirroring" : @NO,
  }];
  [normalized addEntriesFromDictionary:capabilities];
  return [NSDictionary dictionaryWithDictionary:normalized];
}

@interface ALNStorageModuleRuntime (JobSupport)

- (nullable NSDictionary *)runMaintenanceAt:(NSDate *)timestamp
                                      error:(NSError **)error;
- (nullable NSDictionary *)processVariantJobPayload:(NSDictionary *)payload
                                         jobContext:(NSDictionary *)jobContext
                                              error:(NSError **)error;

@end

@interface ALNStorageVariantJob : NSObject <ALNJobsJobDefinition>
@end

@implementation ALNStorageVariantJob

- (NSString *)jobsModuleJobIdentifier {
  return ALNStorageVariantJobIdentifier;
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Storage variant generation",
    @"description" : @"Generates first-party storage variants",
    @"queue" : @"default",
    @"maxAttempts" : @3,
    @"allowManualEnqueue" : @NO,
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  if ([SMTrimmedString(payload[@"objectID"]) length] == 0 || [SMTrimmedString(payload[@"variant"]) length] == 0) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed,
                       @"variant job requires objectID and variant",
                       nil);
    }
    return NO;
  }
  return YES;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  return ([[ALNStorageModuleRuntime sharedRuntime] processVariantJobPayload:payload
                                                                  jobContext:context
                                                                       error:error] != nil);
}

@end

@interface ALNStorageCleanupJob : NSObject <ALNJobsJobDefinition>
@end

@implementation ALNStorageCleanupJob

- (NSString *)jobsModuleJobIdentifier {
  return ALNStorageCleanupJobIdentifier;
}

- (NSDictionary *)jobsModuleJobMetadata {
  return @{
    @"title" : @"Storage cleanup",
    @"description" : @"Prunes expired upload sessions and retention-expired objects",
    @"queue" : @"maintenance",
    @"maxAttempts" : @2,
    @"allowManualEnqueue" : @NO,
    @"tags" : @[ @"storage", @"maintenance" ],
  };
}

- (BOOL)jobsModuleValidatePayload:(NSDictionary *)payload error:(NSError **)error {
  (void)payload;
  (void)error;
  return YES;
}

- (BOOL)jobsModulePerformPayload:(NSDictionary *)payload context:(NSDictionary *)context error:(NSError **)error {
  NSDate *now = [context[@"scheduledAt"] isKindOfClass:[NSDate class]] ? context[@"scheduledAt"] : [NSDate date];
  id runtime = [ALNStorageModuleRuntime sharedRuntime];
  return ([runtime runMaintenanceAt:now error:error] != nil);
}

@end

@interface ALNStorageModuleRuntime ()

@property(nonatomic, strong, readwrite) ALNApplication *application;
@property(nonatomic, strong, readwrite) id<ALNAttachmentAdapter> attachmentAdapter;
@property(nonatomic, copy, readwrite) NSString *prefix;
@property(nonatomic, copy, readwrite) NSString *apiPrefix;
@property(nonatomic, assign, readwrite) NSTimeInterval defaultUploadSessionTTLSeconds;
@property(nonatomic, assign, readwrite) NSTimeInterval defaultDownloadTokenTTLSeconds;
@property(nonatomic, assign) NSTimeInterval defaultCleanupIntervalSeconds;
@property(nonatomic, copy) NSDictionary *moduleConfig;
@property(nonatomic, strong) NSData *signingKeyData;
@property(nonatomic, strong) NSLock *lock;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id<ALNStorageCollectionDefinition>> *collectionDefinitionsByIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *collectionMetadataByIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *objectIDsByCollection;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *objectsByIdentifier;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *uploadSessionsByIdentifier;
@property(nonatomic, assign) NSUInteger nextSequence;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *activityLog;
@property(nonatomic, assign) BOOL persistenceEnabled;
@property(nonatomic, strong) ALNStorageCatalog *catalog;
@property(nonatomic, copy) NSString *statePath;
// Serializes state transactions in this process; the lock file next to the
// state file serializes them across processes.
@property(nonatomic, strong) NSRecursiveLock *transactionLock;
@property(nonatomic, assign) NSUInteger transactionDepth;
@property(nonatomic, assign) int stateLockDescriptor;
@property(nonatomic, copy) NSString *loadedStateStamp;
// Readers that cannot take transactionLock must still observe failed state.
@property(atomic, assign) BOOL stateReloadRequired;
@property(nonatomic, assign) NSTimeInterval lockTimeoutSeconds;
@property(nonatomic, copy) NSArray<NSDictionary *> *configurationWarnings;

- (nullable NSDictionary *)normalizedCollectionMetadataForDefinition:(id<ALNStorageCollectionDefinition>)definition
                                                               error:(NSError **)error;
- (BOOL)registerCollectionDefinition:(id<ALNStorageCollectionDefinition>)definition
                              source:(NSString *)source
                               error:(NSError **)error;
- (nullable NSDictionary *)internalObjectRecordForIdentifier:(NSString *)objectID;
- (NSDictionary *)publicObjectRecordFromInternalRecord:(NSDictionary *)record;
- (NSArray<NSDictionary *> *)publicObjectRecordsFromIDs:(NSArray<NSString *> *)objectIDs;
- (nullable NSDictionary *)validatedTokenPayload:(NSString *)token
                                         purpose:(NSString *)purpose
                                   expectedField:(NSString *)expectedField
                                   expectedValue:(NSString *)expectedValue
                                           error:(NSError **)error;
- (BOOL)loadPersistedStateWithError:(NSError **)error;
- (BOOL)persistStateWithError:(NSError **)error;
- (BOOL)performStateTransaction:(BOOL (^)(NSError **blockError))block error:(NSError **)error;
- (BOOL)refreshStateIfChanged:(NSError **)error;
- (void)recordActivityNamed:(NSString *)event details:(NSDictionary *)details;
- (NSUInteger)pruneExpiredUploadSessionsAt:(NSDate *)timestamp
                            recordActivity:(BOOL)recordActivity;
- (BOOL)deleteObjectIdentifier:(NSString *)objectID
                        reason:(NSString *)reason
                         error:(NSError **)error;
- (nullable NSDictionary *)runMaintenanceAt:(NSDate *)timestamp
                                       error:(NSError **)error;
- (nullable NSDictionary *)processVariantJobPayload:(NSDictionary *)payload
                                         jobContext:(NSDictionary *)jobContext
                                              error:(NSError **)error;

@end

@implementation ALNStorageModuleRuntime

+ (instancetype)sharedRuntime {
  static ALNStorageModuleRuntime *runtime = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    runtime = [[ALNStorageModuleRuntime alloc] init];
  });
  return runtime;
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _prefix = @"/storage";
    _apiPrefix = @"/storage/api";
    _defaultUploadSessionTTLSeconds = 900.0;
    _defaultDownloadTokenTTLSeconds = 300.0;
    _defaultCleanupIntervalSeconds = 300.0;
    _moduleConfig = @{};
    _signingKeyData = SMEphemeralSigningKeyData();
    _lock = [[NSLock alloc] init];
    _collectionDefinitionsByIdentifier = [NSMutableDictionary dictionary];
    _collectionMetadataByIdentifier = [NSMutableDictionary dictionary];
    _objectIDsByCollection = [NSMutableDictionary dictionary];
    _objectsByIdentifier = [NSMutableDictionary dictionary];
    _uploadSessionsByIdentifier = [NSMutableDictionary dictionary];
    _nextSequence = 0;
    _activityLog = [NSMutableArray array];
    _persistenceEnabled = NO;
    _statePath = @"";
    _transactionLock = [[NSRecursiveLock alloc] init];
    _transactionDepth = 0;
    _stateLockDescriptor = -1;
    _loadedStateStamp = @"";
    _lockTimeoutSeconds = SMDefaultLockTimeoutSeconds;
    _configurationWarnings = @[];
  }
  return self;
}

// The catalog is shared through the state file, so attachment data must be
// shared too: a process-local adapter would let one worker's catalog entry
// name another worker's bytes. With persistence on and no adapter configured,
// the in-memory default is replaced by a filesystem adapter next to the state
// file; a process-local adapter configured explicitly is refused.
- (id<ALNAttachmentAdapter>)sharedAttachmentAdapterForApplication:(ALNApplication *)application
                                                     moduleConfig:(NSDictionary *)moduleConfig
                                                            error:(NSError **)error {
  id<ALNAttachmentAdapter> adapter = application.attachmentAdapter;
  BOOL processLocal = [SMAttachmentAdapterCapabilities(adapter)[@"processLocal"] boolValue];
  // Without persistence each process keeps its own catalog, and object IDs
  // are random, so another process's token finds nothing rather than other
  // bytes.
  if (!processLocal || !self.persistenceEnabled) {
    return adapter;
  }
  if (application.usesDefaultAttachmentAdapter) {
    NSDictionary *attachments = [moduleConfig[@"attachments"] isKindOfClass:[NSDictionary class]]
                                    ? moduleConfig[@"attachments"]
                                    : @{};
    NSString *root = SMTrimmedString(attachments[@"path"]);
    if ([root length] == 0) {
      root = [[self.statePath stringByDeletingPathExtension] stringByAppendingString:@"-attachments"];
    } else if (![root isAbsolutePath]) {
      root = [application pathRelativeToAppRoot:root];
    }
    NSError *adapterError = nil;
    ALNFileSystemAttachmentAdapter *filesystem =
        [[ALNFileSystemAttachmentAdapter alloc] initWithRootDirectory:root
                                                          adapterName:@"storage_filesystem"
                                                                error:&adapterError];
    if (filesystem == nil) {
      if (error != NULL) {
        *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                         @"storage module could not create its attachment directory",
                         @{
                           @"path" : root ?: @"",
                           @"reason" : adapterError.localizedDescription ?: @"",
                         });
      }
      return nil;
    }
    [application setAttachmentAdapter:filesystem];
    [application.logger info:@"storage attachments use the filesystem"
                      fields:@{
                        @"path" : root ?: @"",
                        @"detail" : @"no attachment adapter was configured and the in-memory default is not shared "
                                    @"between processes",
                      }];
    return filesystem;
  }
  if (error != NULL) {
    *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                     @"storage module persistence needs an attachment adapter that every process shares; "
                     @"the configured adapter keeps attachments in process memory. Configure a filesystem or "
                     @"object-store attachment adapter, or set storageModule.persistence.enabled = NO",
                     @{
                       @"adapter" : [adapter adapterName] ?: @"",
                       @"reason" : @"process_local_attachment_adapter",
                     });
  }
  return nil;
}

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError **)error {
  if (application == nil || application.attachmentAdapter == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                       @"storage module requires an application with an attachment adapter",
                       nil);
    }
    return NO;
  }

  ALNJobsModuleRuntime *jobsRuntime = [ALNJobsModuleRuntime sharedRuntime];
  if (jobsRuntime.application == nil || jobsRuntime.jobsAdapter == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                       @"storage module requires the jobs module to be configured first",
                       nil);
    }
    return NO;
  }

  NSDictionary *moduleConfig =
      [application.config[@"storageModule"] isKindOfClass:[NSDictionary class]] ? application.config[@"storageModule"] : @{};
  NSString *signingSecret = SMTrimmedString(moduleConfig[@"signingSecret"]);
  NSData *signingKeyData = nil;
  if ([signingSecret length] > 0) {
    if ([signingSecret length] < SMMinimumSigningSecretLength) {
      if (error != NULL) {
        *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"storageModule.signingSecret (ARLEN_STORAGE_SIGNING_SECRET) must be "
                                                    @"at least %lu characters; generate one with `openssl rand -hex 32`",
                                                    (unsigned long)SMMinimumSigningSecretLength],
                         @{ @"config_key" : @"storageModule.signingSecret", @"reason" : @"weak_secret" });
      }
      return NO;
    }
    NSString *insecureReason = ALNInsecureSigningSecretReason(signingSecret);
    if (insecureReason != nil && !ALNEnvironmentAllowsInsecureSigningSecrets(application.environment)) {
      if (error != NULL) {
        NSString *kind = [insecureReason isEqualToString:@"published_example_secret"]
                             ? @"is an example value published in the Arlen repository"
                             : @"looks like a placeholder value";
        *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"storageModule.signingSecret (ARLEN_STORAGE_SIGNING_SECRET) %@ and is "
                                                    @"refused in the %@ environment; generate one with "
                                                    @"`openssl rand -hex 32`",
                                                    kind, application.environment ?: @"current"],
                         @{ @"config_key" : @"storageModule.signingSecret", @"reason" : insecureReason });
      }
      return NO;
    }
    signingKeyData = [signingSecret dataUsingEncoding:NSUTF8StringEncoding];
  } else if (SMEnvironmentAllowsEphemeralSigningKey(application.environment)) {
    signingKeyData = SMEphemeralSigningKeyData();
    [application.logger warn:@"storage signing secret not configured"
                      fields:@{
                        @"config_key" : @"storageModule.signingSecret",
                        @"environment" : application.environment ?: @"",
                        @"detail" : @"using a random per-process key; storage tokens will not survive a restart. "
                                    @"Set ARLEN_STORAGE_SIGNING_SECRET or storageModule.signingSecret.",
                      }];
  } else {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                       @"storage module requires storageModule.signingSecret (or ARLEN_STORAGE_SIGNING_SECRET) "
                       @"outside development and test",
                       @{ @"config_key" : @"storageModule.signingSecret", @"reason" : @"missing_required_secret" });
    }
    return NO;
  }
  if (signingKeyData == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                       @"storage module could not initialize its signing key",
                       @{ @"config_key" : @"storageModule.signingSecret" });
    }
    return NO;
  }

  [self.lock lock];
  self.application = application;
  self.attachmentAdapter = application.attachmentAdapter;
  self.moduleConfig = moduleConfig;
  self.prefix = SMConfiguredPath(moduleConfig, @"prefix", @"");
  self.apiPrefix = SMConfiguredPath(moduleConfig, @"apiPrefix", @"api");
  self.defaultUploadSessionTTLSeconds =
      [moduleConfig[@"uploadSessionTTLSeconds"] respondsToSelector:@selector(doubleValue)]
          ? [moduleConfig[@"uploadSessionTTLSeconds"] doubleValue]
          : 900.0;
  if (self.defaultUploadSessionTTLSeconds <= 0.0) {
    self.defaultUploadSessionTTLSeconds = 900.0;
  }
  self.defaultDownloadTokenTTLSeconds =
      [moduleConfig[@"downloadTokenTTLSeconds"] respondsToSelector:@selector(doubleValue)]
          ? [moduleConfig[@"downloadTokenTTLSeconds"] doubleValue]
          : 300.0;
  if (self.defaultDownloadTokenTTLSeconds <= 0.0) {
    self.defaultDownloadTokenTTLSeconds = 300.0;
  }
  NSDictionary *cleanupConfig =
      [moduleConfig[@"cleanup"] isKindOfClass:[NSDictionary class]] ? moduleConfig[@"cleanup"] : @{};
  self.defaultCleanupIntervalSeconds =
      [cleanupConfig[@"intervalSeconds"] respondsToSelector:@selector(doubleValue)]
          ? [cleanupConfig[@"intervalSeconds"] doubleValue]
          : 300.0;
  if (self.defaultCleanupIntervalSeconds <= 0.0) {
    self.defaultCleanupIntervalSeconds = 300.0;
  }
  self.signingKeyData = signingKeyData;
  [self.collectionDefinitionsByIdentifier removeAllObjects];
  [self.collectionMetadataByIdentifier removeAllObjects];
  [self.objectIDsByCollection removeAllObjects];
  [self.objectsByIdentifier removeAllObjects];
  [self.uploadSessionsByIdentifier removeAllObjects];
  [self.activityLog removeAllObjects];
  self.nextSequence = 0;
  self.statePath = SMResolvedPersistencePath(application, moduleConfig);
  self.persistenceEnabled = ([self.statePath length] > 0);
  self.loadedStateStamp = @"";
  self.stateReloadRequired = NO;
  self.lockTimeoutSeconds = SMConfiguredLockTimeoutSeconds(moduleConfig);
  [self.lock unlock];

  id<ALNAttachmentAdapter> attachmentAdapter =
      [self sharedAttachmentAdapterForApplication:application moduleConfig:moduleConfig error:error];
  if (attachmentAdapter == nil) {
    return NO;
  }
  [self.lock lock];
  self.attachmentAdapter = attachmentAdapter;
  [self.lock unlock];

  self.catalog = nil;
  NSString *backend = SMLowerTrimmedString(moduleConfig[@"persistence"][@"backend"]);
  if (backend.length > 0 && ![backend isEqualToString:@"sqlite"] && ![backend isEqualToString:@"plist"]) {
    if (error != NULL) *error = SMError(ALNStorageModuleErrorInvalidConfiguration, @"storage persistence.backend must be sqlite or plist", nil);
    return NO;
  }
  if (self.persistenceEnabled && [backend isEqualToString:@"plist"] &&
      [[NSFileManager defaultManager] fileExistsAtPath:[self.statePath stringByAppendingString:@".sqlite3"]]) {
    if (error != NULL) *error = SMError(ALNStorageModuleErrorInvalidConfiguration, @"cannot switch a migrated SQLite catalog back to its stale legacy plist", nil);
    return NO;
  }
  if (self.persistenceEnabled && ![backend isEqualToString:@"plist"]) {
    self.catalog = [[ALNStorageCatalog alloc] initWithPath:[self.statePath stringByAppendingString:@".sqlite3"] legacyPath:self.statePath error:error];
    if (self.catalog == nil) return NO;
  }
  if (![self loadPersistedStateWithError:error]) {
    return NO;
  }

  if (![jobsRuntime registerSystemJobDefinition:[[ALNStorageVariantJob alloc] init] error:error]) {
    return NO;
  }
  if (![jobsRuntime registerSystemJobDefinition:[[ALNStorageCleanupJob alloc] init] error:error]) {
    return NO;
  }
  if (![jobsRuntime registerSystemScheduleDefinition:@{
        @"identifier" : @"storage.cleanup.default",
        @"job" : ALNStorageCleanupJobIdentifier,
        @"intervalSeconds" : @(self.defaultCleanupIntervalSeconds),
        @"queue" : @"maintenance",
      }
                                        error:error]) {
    return NO;
  }

  NSArray *providerClasses =
      [moduleConfig[@"collectionProviderClasses"] isKindOfClass:[NSArray class]]
          ? moduleConfig[@"collectionProviderClasses"]
          : ([moduleConfig[@"collections"] isKindOfClass:[NSDictionary class]] &&
                     [moduleConfig[@"collections"][@"classes"] isKindOfClass:[NSArray class]]
                 ? moduleConfig[@"collections"][@"classes"]
                 : @[]);
  for (id rawClassName in providerClasses) {
    NSString *className = SMTrimmedString(rawClassName);
    if ([className length] == 0) {
      continue;
    }
    Class klass = NSClassFromString(className);
    id provider = (klass != Nil) ? [[klass alloc] init] : nil;
    if (provider == nil || ![provider conformsToProtocol:@protocol(ALNStorageCollectionProvider)]) {
      if (error != NULL) {
        *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                         [NSString stringWithFormat:@"storage collection provider %@ is invalid", className],
                         @{ @"class" : className ?: @"" });
      }
      return NO;
    }
    NSArray *definitions = [(id<ALNStorageCollectionProvider>)provider storageModuleCollectionsForRuntime:self error:error];
    if (definitions == nil && error != NULL && *error != NULL) {
      return NO;
    }
    for (id definition in definitions ?: @[]) {
      if (![self registerCollectionDefinition:definition source:className error:error]) {
        return NO;
      }
    }
  }
  [self warnAboutUnsharedStateForApplication:application];

  // Startup cleanup waits longer for the lock than a request does, and a
  // busy lock (other workers under load) skips it rather than failing
  // startup: production treats a module load error as fatal, so failing here
  // would restart workers in a loop. The catalog itself was already loaded.
  NSTimeInterval requestTimeout = self.lockTimeoutSeconds;
  self.lockTimeoutSeconds = SMConfiguredStartupLockTimeoutSeconds(moduleConfig, requestTimeout);
  NSError *startupError = nil;
  BOOL cleaned = [self performStateTransaction:^BOOL(NSError **blockError) {
    [self removeStaleTemporaryStateFiles];
    [self pruneUnknownCollectionState];
    [self pruneExpiredUploadSessionsAt:[NSDate date] recordActivity:YES];
    return [self persistStateWithError:blockError];
  }
                                         error:&startupError];
  self.lockTimeoutSeconds = requestTimeout;
  if (!cleaned && startupError.code == ALNStorageModuleErrorStateBusy) {
    [application.logger warn:@"storage state lock busy at startup; skipped startup cleanup"
                      fields:@{
                        @"path" : [self stateLockPath] ?: @"",
                        @"detail" : startupError.localizedDescription ?: @"",
                      }];
    return YES;
  }
  if (!cleaned && error != NULL) {
    *error = startupError;
  }
  return cleaned;
}

// A process killed between writing its temporary state file and renaming it
// leaves <state file>.<hex>.tmp behind. Runs under the state lock, so no
// write is in progress; the age check also spares any just-created file.
- (void)removeStaleTemporaryStateFiles {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return;
  }
  NSString *directory = [self.statePath stringByDeletingLastPathComponent];
  NSString *prefix = [[self.statePath lastPathComponent] stringByAppendingString:@"."];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-SMStaleTemporaryStateFileSeconds];
  for (NSString *name in [fileManager contentsOfDirectoryAtPath:directory error:NULL] ?: @[]) {
    if (![name hasPrefix:prefix] || ![name hasSuffix:@".tmp"]) {
      continue;
    }
    NSString *path = [directory stringByAppendingPathComponent:name];
    NSDate *modified = [[fileManager attributesOfItemAtPath:path error:NULL] fileModificationDate];
    if (modified != nil && [modified compare:cutoff] == NSOrderedAscending) {
      (void)[fileManager removeItemAtPath:path error:NULL];
    }
  }
}

// Without persistence each process keeps its own catalog, which is fine for
// one process but means propane workers (and the jobs worker) each see only
// their own objects.
- (void)warnAboutUnsharedStateForApplication:(ALNApplication *)application {
  NSMutableArray<NSDictionary *> *warnings = [NSMutableArray array];
  NSDictionary *propane = [application.config[@"propaneAccessories"] isKindOfClass:[NSDictionary class]]
                              ? application.config[@"propaneAccessories"]
                              : @{};
  NSUInteger workerCount = ALNUnsignedIntegerValueOrDefault(propane[@"workerCount"], 1);
  NSString *environment = SMLowerTrimmedString(application.environment);
  BOOL singleProcessEnvironment = [environment isEqualToString:@"test"] || [environment isEqualToString:@"development"];
  if (!self.persistenceEnabled && workerCount > 1 && !singleProcessEnvironment) {
    NSDictionary *warning = @{
      @"code" : @"storage_unshared_state",
      @"message" : [NSString stringWithFormat:@"storage persistence is off but propaneAccessories.workerCount = %lu; "
                                              @"each worker keeps its own catalog, so most downloads and variant "
                                              @"jobs will not find their objects",
                                              (unsigned long)workerCount],
      @"hint" : @"Enable storageModule.persistence (the default) or run a single worker.",
    };
    [warnings addObject:warning];
    [application.logger warn:warning[@"message"] fields:@{ @"code" : warning[@"code"], @"hint" : warning[@"hint"] }];
  }
  [self.lock lock];
  self.configurationWarnings = [NSArray arrayWithArray:warnings];
  [self.lock unlock];
}

- (void)pruneUnknownCollectionState {
  [self.lock lock];
  NSSet *knownCollections = [NSSet setWithArray:[self.collectionMetadataByIdentifier allKeys]];
  NSArray *storedObjectIDs = [NSArray arrayWithArray:[self.objectsByIdentifier allKeys]];
  for (NSString *objectID in storedObjectIDs) {
    NSDictionary *record = [self.objectsByIdentifier[objectID] isKindOfClass:[NSDictionary class]]
                               ? self.objectsByIdentifier[objectID]
                               : nil;
    if (record == nil || ![knownCollections containsObject:SMLowerTrimmedString(record[@"collection"])]) {
      [self.objectsByIdentifier removeObjectForKey:objectID];
    }
  }
  NSArray *sessionIDs = [NSArray arrayWithArray:[self.uploadSessionsByIdentifier allKeys]];
  for (NSString *sessionID in sessionIDs) {
    NSDictionary *session = [self.uploadSessionsByIdentifier[sessionID] isKindOfClass:[NSDictionary class]]
                                ? self.uploadSessionsByIdentifier[sessionID]
                                : nil;
    if (session == nil || ![knownCollections containsObject:SMLowerTrimmedString(session[@"collection"])]) {
      [self.uploadSessionsByIdentifier removeObjectForKey:sessionID];
    }
  }
  for (NSString *collection in [NSArray arrayWithArray:[self.objectIDsByCollection allKeys]]) {
    if (![knownCollections containsObject:collection]) {
      [self.objectIDsByCollection removeObjectForKey:collection];
    }
  }
  [self.lock unlock];
}

- (BOOL)loadPersistedStateWithError:(NSError **)error {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return YES;
  }
  // Record only the stamp of the content actually loaded. Failed loads never
  // make cached state current, including when the caller omits NSError.
  @try {
    for (NSUInteger attempt = 0; attempt < 3; attempt++) {
      NSString *stamp = SMStateFileStamp(self.catalog != nil ? self.catalog.path : self.statePath);
      if (![self loadPersistedStateVersionWithError:error]) {
        self.stateReloadRequired = YES;
        return NO;
      }
      self.loadedStateStamp = stamp;
      if ([SMStateFileStamp(self.catalog != nil ? self.catalog.path : self.statePath) isEqualToString:stamp]) {
        break;
      }
    }
    self.stateReloadRequired = NO;
    return YES;
  } @catch (NSException *exception) {
    self.stateReloadRequired = YES;
    @throw;
  }
}

- (BOOL)loadPersistedStateVersionWithError:(NSError **)error {
  NSError *readError = nil;
  NSDictionary *state = self.catalog != nil ? [self.catalog readStateWithError:&readError] : SMReadPropertyListAtPath(self.statePath, &readError);
  if (state == nil) {
    if (readError != nil) {
      if (error != NULL) *error = readError;
      return NO;
    }
    // An absent legacy file is an empty catalog, not the previous snapshot.
    state = @{};
  }
  // The file is the shared truth: replace the in-memory copy rather than merge
  // into it, so objects another process deleted stay deleted here.
  [self.lock lock];
  @try {
    NSDictionary *objects = [state[@"objectsByIdentifier"] isKindOfClass:[NSDictionary class]] ? state[@"objectsByIdentifier"] : @{};
    NSDictionary *sessions = [state[@"uploadSessionsByIdentifier"] isKindOfClass:[NSDictionary class]] ? state[@"uploadSessionsByIdentifier"] : @{};
    NSDictionary *objectIDsByCollection = [state[@"objectIDsByCollection"] isKindOfClass:[NSDictionary class]] ? state[@"objectIDsByCollection"] : @{};
    [self.objectIDsByCollection removeAllObjects];
    for (NSString *collection in self.collectionMetadataByIdentifier) {
      self.objectIDsByCollection[collection] = [NSMutableArray array];
    }
    for (NSString *collection in objectIDsByCollection) {
      NSArray *objectIDs = [objectIDsByCollection[collection] isKindOfClass:[NSArray class]] ? objectIDsByCollection[collection] : @[];
      self.objectIDsByCollection[collection] = [NSMutableArray arrayWithArray:objectIDs];
    }
    [self.objectsByIdentifier removeAllObjects];
    for (NSString *objectID in objects) {
      NSDictionary *record = [objects[objectID] isKindOfClass:[NSDictionary class]] ? objects[objectID] : nil;
      if (record == nil) {
        continue;
      }
      if ([SMTrimmedString(record[@"tokenNonce"]) length] == 0) {
        // State written before tokens were bound to the object.
        NSMutableDictionary *upgraded = [NSMutableDictionary dictionaryWithDictionary:record];
        upgraded[@"tokenNonce"] = SMRandomHexString(16) ?: @"";
        record = [NSDictionary dictionaryWithDictionary:upgraded];
      }
      self.objectsByIdentifier[objectID] = record;
    }
    [self.uploadSessionsByIdentifier removeAllObjects];
    [self.uploadSessionsByIdentifier addEntriesFromDictionary:sessions];
    NSArray *activity = [state[@"activityLog"] isKindOfClass:[NSArray class]] ? state[@"activityLog"] : @[];
    [self.activityLog removeAllObjects];
    [self.activityLog addObjectsFromArray:activity];
    NSUInteger storedSequence = [state[@"nextSequence"] respondsToSelector:@selector(unsignedIntegerValue)]
                                    ? [state[@"nextSequence"] unsignedIntegerValue]
                                    : 0;
    self.nextSequence = MAX(self.nextSequence, storedSequence);
  } @finally {
    [self.lock unlock];
  }
  return YES;
}

- (NSString *)stateLockPath {
  return [self.statePath stringByAppendingString:@".lock"];
}

// Runs block as one read-modify-write of the shared state. The outermost
// transaction takes the cross-process lock, reloads the state file, and
// releases the lock after block's writes; nested transactions (a method that
// calls another) join it.
- (BOOL)performStateTransaction:(BOOL (^)(NSError **blockError))block error:(NSError **)error {
  [self.transactionLock lock];
  BOOL outermost = (self.transactionDepth == 0);
  BOOL sharedState = (self.persistenceEnabled && [self.statePath length] > 0);
  BOOL entered = NO;
  @try {
    if (outermost && sharedState) {
      NSString *parent = [self.statePath stringByDeletingLastPathComponent];
      if ([parent length] > 0) {
        (void)[[NSFileManager defaultManager] createDirectoryAtPath:parent
                                        withIntermediateDirectories:YES
                                                         attributes:nil
                                                              error:NULL];
      }
      int descriptor = ALNPlatformOpenExclusiveLockWithTimeout([self stateLockPath], self.lockTimeoutSeconds);
      if (descriptor < 0) {
        int lockErrno = errno;
        if (error != NULL) {
          *error = SMStateLockError([self stateLockPath], lockErrno, self.lockTimeoutSeconds);
        }
        return NO;
      }
      self.stateLockDescriptor = descriptor;
      BOOL current = !self.stateReloadRequired &&
          [SMStateFileStamp(self.catalog != nil ? self.catalog.path : self.statePath)
              isEqualToString:self.loadedStateStamp ?: @""];
      if (!current && ![self loadPersistedStateWithError:error]) {
        return NO;
      }
    }
    self.transactionDepth += 1;
    entered = YES;
    NSError *blockError = nil;
    BOOL ok = block(&blockError);
    if (!ok) {
      if (sharedState) self.stateReloadRequired = YES;
      if (error != NULL) *error = blockError;
    }
    return ok;
  } @catch (NSException *exception) {
    if (sharedState) self.stateReloadRequired = YES;
    @throw;
  } @finally {
    if (entered) self.transactionDepth -= 1;
    if (outermost && self.stateLockDescriptor >= 0) {
      ALNPlatformReleaseExclusiveLock(self.stateLockDescriptor);
      self.stateLockDescriptor = -1;
    }
    [self.transactionLock unlock];
  }
}

// Keep the nonblocking read policy, but never serve a snapshot known to have
// failed to load or persist. A later successful reload permits reads again.
- (BOOL)refreshStateIfChanged:(NSError **)error {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return YES;
  }
  if (![self.transactionLock tryLock]) {
    if (!self.stateReloadRequired) return YES;
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorPersistenceFailed, @"storage catalog reload is required", nil);
    }
    return NO;
  }
  @try {
    if (self.transactionDepth == 0 &&
        (self.stateReloadRequired ||
         ![SMStateFileStamp(self.catalog != nil ? self.catalog.path : self.statePath)
             isEqualToString:self.loadedStateStamp ?: @""])) {
      return [self loadPersistedStateWithError:error];
    }
    if (self.stateReloadRequired) {
      if (error != NULL) {
        *error = SMError(ALNStorageModuleErrorPersistenceFailed, @"storage catalog reload is required", nil);
      }
      return NO;
    }
    return YES;
  } @finally {
    [self.transactionLock unlock];
  }
}

- (BOOL)persistStateWithError:(NSError **)error {
  if (!self.persistenceEnabled || [self.statePath length] == 0) {
    return YES;
  }
  // The outer transaction normally owns the shared lock. Direct writes still
  // take one, and both paths release every acquired guard on exceptions.
  [self.transactionLock lock];
  int bareDescriptor = -1;
  @try {
    if (self.transactionDepth == 0) {
      bareDescriptor = ALNPlatformOpenExclusiveLockWithTimeout([self stateLockPath], self.lockTimeoutSeconds);
      if (bareDescriptor < 0) {
        int lockErrno = errno;
        self.stateReloadRequired = YES;
        if (error != NULL) {
          *error = SMStateLockError([self stateLockPath], lockErrno, self.lockTimeoutSeconds);
        }
        return NO;
      }
    }
    NSDictionary *payload = nil;
    [self.lock lock];
    @try {
      NSMutableDictionary *objectIDsByCollection = [NSMutableDictionary dictionary];
      for (NSString *collection in self.objectIDsByCollection) {
        objectIDsByCollection[collection] = [[NSArray alloc] initWithArray:self.objectIDsByCollection[collection] ?: @[] copyItems:YES] ?: @[];
      }
      payload = @{
        @"version" : @1,
        @"nextSequence" : @(self.nextSequence),
        @"objectIDsByCollection" : objectIDsByCollection,
        @"objectsByIdentifier" : [NSDictionary dictionaryWithDictionary:self.objectsByIdentifier ?: @{}],
        @"uploadSessionsByIdentifier" : [NSDictionary dictionaryWithDictionary:self.uploadSessionsByIdentifier ?: @{}],
        @"activityLog" : [[NSArray alloc] initWithArray:self.activityLog copyItems:YES] ?: @[],
      };
    } @finally {
      [self.lock unlock];
    }
    self.catalog.writeTimeoutSeconds = self.lockTimeoutSeconds;
    BOOL written = self.catalog != nil ? [self.catalog writeState:payload error:error] : SMWritePropertyListAtPath(self.statePath, payload, error);
    self.stateReloadRequired = !written;
    if (written) {
      self.loadedStateStamp = SMStateFileStamp(self.catalog != nil ? self.catalog.path : self.statePath);
    }
    return written;
  } @catch (NSException *exception) {
    self.stateReloadRequired = YES;
    @throw;
  } @finally {
    ALNPlatformReleaseExclusiveLock(bareDescriptor);
    [self.transactionLock unlock];
  }
}

- (void)recordActivityNamed:(NSString *)event details:(NSDictionary *)details {
  [self.lock lock];
  [self.activityLog addObject:@{
    @"event" : SMLowerTrimmedString(event),
    @"timestamp" : @([[NSDate date] timeIntervalSince1970]),
    @"details" : SMNormalizeDictionary(details),
  }];
  while ([self.activityLog count] > ALNStorageActivityLimit) {
    [self.activityLog removeObjectAtIndex:0];
  }
  [self.lock unlock];
}

- (NSUInteger)pruneExpiredUploadSessionsAt:(NSDate *)timestamp
                            recordActivity:(BOOL)recordActivity {
  // Most calls find nothing to prune; don't take the state lock for those.
  if (self.transactionDepth == 0 && ![self hasExpiredUploadSessionsAt:timestamp]) {
    return 0;
  }
  __block NSUInteger count = 0;
  (void)[self performStateTransaction:^BOOL(NSError **blockError) {
    (void)blockError;
    count = [self pruneExpiredUploadSessionsInTransactionAt:timestamp recordActivity:recordActivity];
    return YES;
  }
                                error:NULL];
  return count;
}

- (BOOL)hasExpiredUploadSessionsAt:(NSDate *)timestamp {
  if (![self refreshStateIfChanged:NULL]) return NO;
  NSTimeInterval now = [(timestamp ?: [NSDate date]) timeIntervalSince1970];
  BOOL found = NO;
  [self.lock lock];
  for (NSDictionary *session in [self.uploadSessionsByIdentifier allValues]) {
    if (![session isKindOfClass:[NSDictionary class]] || ![[session[@"status"] description] isEqualToString:@"pending"]) {
      continue;
    }
    NSTimeInterval expiresAt = [session[@"expiresAt"] respondsToSelector:@selector(doubleValue)]
                                   ? [session[@"expiresAt"] doubleValue]
                                   : 0.0;
    if (expiresAt > 0.0 && expiresAt <= now) {
      found = YES;
      break;
    }
  }
  [self.lock unlock];
  return found;
}

- (NSUInteger)pruneExpiredUploadSessionsInTransactionAt:(NSDate *)timestamp
                                         recordActivity:(BOOL)recordActivity {
  NSDate *now = timestamp ?: [NSDate date];
  NSMutableArray<NSString *> *expired = [NSMutableArray array];
  [self.lock lock];
  for (NSString *sessionID in [self.uploadSessionsByIdentifier allKeys]) {
    NSDictionary *session = [self.uploadSessionsByIdentifier[sessionID] isKindOfClass:[NSDictionary class]]
                                ? self.uploadSessionsByIdentifier[sessionID]
                                : nil;
    if (session == nil || ![[session[@"status"] description] isEqualToString:@"pending"]) {
      continue;
    }
    NSTimeInterval expiresAt = [session[@"expiresAt"] respondsToSelector:@selector(doubleValue)]
                                   ? [session[@"expiresAt"] doubleValue]
                                   : 0.0;
    if (expiresAt > 0.0 && expiresAt <= [now timeIntervalSince1970]) {
      [expired addObject:sessionID];
    }
  }
  for (NSString *sessionID in expired) {
    [self.uploadSessionsByIdentifier removeObjectForKey:sessionID];
  }
  [self.lock unlock];
  if (recordActivity) {
    for (NSString *sessionID in expired) {
      [self recordActivityNamed:@"upload_session_expired" details:@{ @"sessionID" : sessionID ?: @"" }];
    }
  }
  if ([expired count] > 0) {
    (void)[self persistStateWithError:NULL];
  }
  return [expired count];
}

- (NSDictionary *)resolvedConfigSummary {
  [self pruneExpiredUploadSessionsAt:[NSDate date] recordActivity:NO];
  return @{
    @"prefix" : self.prefix ?: @"/storage",
    @"apiPrefix" : self.apiPrefix ?: @"/storage/api",
    @"uploadSessionTTLSeconds" : @(self.defaultUploadSessionTTLSeconds),
    @"downloadTokenTTLSeconds" : @(self.defaultDownloadTokenTTLSeconds),
    @"cleanupIntervalSeconds" : @(self.defaultCleanupIntervalSeconds),
    @"collections" : [self registeredCollections],
    @"objectCount" : @([[self listObjectsForCollection:nil query:nil] count]),
    @"uploadSessionCount" : @([self.uploadSessionsByIdentifier count]),
    @"activityCount" : @([self.activityLog count]),
    @"attachmentAdapter" : @{
      @"name" : (self.attachmentAdapter != nil) ? [self.attachmentAdapter adapterName] : @"",
      @"capabilities" : SMAttachmentAdapterCapabilities(self.attachmentAdapter),
    },
    @"persistenceEnabled" : @(self.persistenceEnabled),
    @"statePath" : self.statePath ?: @"",
    @"warnings" : self.configurationWarnings ?: @[],
  };
}

- (NSDictionary *)normalizedCollectionMetadataForDefinition:(id<ALNStorageCollectionDefinition>)definition
                                                      error:(NSError **)error {
  NSString *identifier = SMLowerTrimmedString([definition storageModuleCollectionIdentifier]);
  if ([identifier length] == 0) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration, @"storage collection identifier is required", nil);
    }
    return nil;
  }
  NSDictionary *rawMetadata = SMNormalizeDictionary([definition storageModuleCollectionMetadata]);
  NSUInteger maxBytes = ALNUnsignedIntegerValueOrDefault(rawMetadata[@"maxBytes"], (5U * 1024U * 1024U));
  if (maxBytes == 0) {
    maxBytes = 5U * 1024U * 1024U;
  }
  NSArray<NSString *> *acceptedContentTypes = SMNormalizedContentTypes(rawMetadata[@"acceptedContentTypes"]);
  NSString *visibility = SMLowerTrimmedString(rawMetadata[@"visibility"]);
  if (![visibility isEqualToString:@"public"] && ![visibility isEqualToString:@"private"]) {
    visibility = @"private";
  }
  NSArray<NSDictionary *> *variants = SMNormalizedVariantDefinitions(rawMetadata[@"variants"]);
  return @{
    @"identifier" : identifier,
    @"title" : ([SMTrimmedString(rawMetadata[@"title"]) length] > 0) ? SMTrimmedString(rawMetadata[@"title"]) : [identifier capitalizedString],
    @"description" : SMTrimmedString(rawMetadata[@"description"]),
    @"acceptedContentTypes" : acceptedContentTypes ?: @[ @"*/*" ],
    @"maxBytes" : @(maxBytes),
    @"visibility" : visibility,
    @"retentionDays" : @([rawMetadata[@"retentionDays"] respondsToSelector:@selector(integerValue)] ? [rawMetadata[@"retentionDays"] integerValue] : 0),
    @"variants" : variants ?: @[],
    @"adminResourceIdentifier" : [NSString stringWithFormat:@"storage_%@", identifier],
  };
}

- (BOOL)registerCollectionDefinition:(id<ALNStorageCollectionDefinition>)definition
                              source:(NSString *)source
                               error:(NSError **)error {
  if (definition == nil || ![definition conformsToProtocol:@protocol(ALNStorageCollectionDefinition)]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                       @"storage collection definition must conform to ALNStorageCollectionDefinition",
                       nil);
    }
    return NO;
  }
  NSDictionary *metadata = [self normalizedCollectionMetadataForDefinition:definition error:error];
  if (metadata == nil) {
    return NO;
  }
  NSString *identifier = metadata[@"identifier"] ?: @"";
  NSMutableDictionary *storedMetadata = [NSMutableDictionary dictionaryWithDictionary:metadata];
  storedMetadata[@"source"] = SMTrimmedString(source);
  [self.lock lock];
  if (self.collectionDefinitionsByIdentifier[identifier] != nil) {
    [self.lock unlock];
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorInvalidConfiguration,
                       [NSString stringWithFormat:@"duplicate storage collection %@", identifier],
                       @{ @"identifier" : identifier });
    }
    return NO;
  }
  self.collectionDefinitionsByIdentifier[identifier] = definition;
  self.collectionMetadataByIdentifier[identifier] = [NSDictionary dictionaryWithDictionary:storedMetadata];
  if (![self.objectIDsByCollection[identifier] isKindOfClass:[NSMutableArray class]]) {
    self.objectIDsByCollection[identifier] = [NSMutableArray array];
  }
  [self.lock unlock];
  return YES;
}

- (NSArray<NSDictionary *> *)registeredCollections {
  [self.lock lock];
  NSArray<NSString *> *keys = [[self.collectionMetadataByIdentifier allKeys] sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray *collections = [NSMutableArray array];
  for (NSString *identifier in keys) {
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:self.collectionMetadataByIdentifier[identifier] ?: @{}];
    metadata[@"objectCount"] = @([self.objectIDsByCollection[identifier] count]);
    [collections addObject:[NSDictionary dictionaryWithDictionary:metadata]];
  }
  [self.lock unlock];
  return [NSArray arrayWithArray:collections];
}

- (NSDictionary *)collectionMetadataForIdentifier:(NSString *)identifier {
  NSString *collectionID = SMLowerTrimmedString(identifier);
  [self.lock lock];
  NSDictionary *metadata = self.collectionMetadataByIdentifier[collectionID];
  NSUInteger objectCount = [self.objectIDsByCollection[collectionID] count];
  [self.lock unlock];
  if (metadata == nil) {
    return nil;
  }
  NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithDictionary:metadata];
  copy[@"objectCount"] = @(objectCount);
  return [NSDictionary dictionaryWithDictionary:copy];
}

- (NSDictionary *)internalObjectRecordForIdentifier:(NSString *)objectID {
  [self.lock lock];
  NSDictionary *record = self.objectsByIdentifier[SMTrimmedString(objectID)];
  [self.lock unlock];
  return record;
}

- (NSDictionary *)publicObjectRecordFromInternalRecord:(NSDictionary *)record {
  NSString *collection = SMLowerTrimmedString(record[@"collection"]);
  NSString *objectID = SMTrimmedString(record[@"objectID"]);
  NSMutableDictionary *publicRecord = [NSMutableDictionary dictionaryWithDictionary:record ?: @{}];
  [publicRecord removeObjectForKey:@"tokenNonce"];
  publicRecord[@"paths"] = @{
    @"html" : SMPathJoin(self.prefix, [NSString stringWithFormat:@"collections/%@/objects/%@", collection, objectID]),
    @"api" : SMPathJoin(self.apiPrefix, [NSString stringWithFormat:@"collections/%@/objects/%@", collection, objectID]),
    @"download_token" : SMPathJoin(self.apiPrefix, [NSString stringWithFormat:@"collections/%@/objects/%@/download-token", collection, objectID]),
  };
  return [NSDictionary dictionaryWithDictionary:publicRecord];
}

- (NSArray<NSDictionary *> *)publicObjectRecordsFromIDs:(NSArray<NSString *> *)objectIDs {
  NSMutableArray *records = [NSMutableArray array];
  NSMutableArray<NSDictionary *> *internalRecords = [NSMutableArray array];
  [self.lock lock];
  for (NSString *objectID in objectIDs ?: @[]) {
    NSDictionary *record = self.objectsByIdentifier[SMTrimmedString(objectID)];
    if ([record isKindOfClass:[NSDictionary class]]) {
      [internalRecords addObject:record];
    }
  }
  [self.lock unlock];
  for (NSDictionary *record in internalRecords) {
    [records addObject:[self publicObjectRecordFromInternalRecord:record]];
  }
  [records sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
    NSNumber *leftSequence = [left[@"sequence"] respondsToSelector:@selector(integerValue)] ? left[@"sequence"] : @0;
    NSNumber *rightSequence = [right[@"sequence"] respondsToSelector:@selector(integerValue)] ? right[@"sequence"] : @0;
    return [rightSequence compare:leftSequence];
  }];
  return [NSArray arrayWithArray:records];
}

- (NSArray<NSDictionary *> *)listObjectsForCollection:(NSString *)collection
                                                query:(NSString *)query {
  NSString *collectionID = SMLowerTrimmedString(collection);
  NSString *search = SMLowerTrimmedString(query);
  if (![self refreshStateIfChanged:NULL]) return @[];
  [self.lock lock];
  NSArray<NSString *> *objectIDs = nil;
  if ([collectionID length] > 0) {
    objectIDs = [NSArray arrayWithArray:self.objectIDsByCollection[collectionID] ?: @[]];
  } else {
    objectIDs = [[self.objectsByIdentifier allKeys] sortedArrayUsingSelector:@selector(compare:)];
  }
  [self.lock unlock];
  NSArray<NSDictionary *> *records = [self publicObjectRecordsFromIDs:objectIDs];
  if ([search length] == 0) {
    return records;
  }
  NSMutableArray *filtered = [NSMutableArray array];
  for (NSDictionary *record in records) {
    if ([SMLowerTrimmedString(record[@"name"]) containsString:search] ||
        [SMLowerTrimmedString(record[@"collection"]) containsString:search] ||
        [SMLowerTrimmedString(record[@"contentType"]) containsString:search] ||
        [SMTrimmedString(record[@"objectID"]) containsString:search]) {
      [filtered addObject:record];
    }
  }
  return [NSArray arrayWithArray:filtered];
}

- (NSDictionary *)objectRecordForIdentifier:(NSString *)objectID
                                      error:(NSError **)error {
  NSString *normalizedObjectID = SMTrimmedString(objectID);
  if (![self refreshStateIfChanged:error]) return nil;
  [self.lock lock];
  NSDictionary *record = self.objectsByIdentifier[normalizedObjectID];
  [self.lock unlock];
  if (record == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"storage object %@ was not found", normalizedObjectID ?: @""],
                       @{ @"objectID" : normalizedObjectID ?: @"" });
    }
    return nil;
  }
  return [self publicObjectRecordFromInternalRecord:record];
}

- (BOOL)validateCollection:(NSString *)collection
                      name:(NSString *)name
               contentType:(NSString *)contentType
                 sizeBytes:(NSUInteger)sizeBytes
                  metadata:(NSDictionary *)metadata
                     error:(NSError **)error {
  NSString *collectionID = SMLowerTrimmedString(collection);
  NSDictionary *collectionMetadata = [self collectionMetadataForIdentifier:collectionID];
  id<ALNStorageCollectionDefinition> definition = self.collectionDefinitionsByIdentifier[collectionID];
  if (collectionMetadata == nil || definition == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"storage collection %@ was not found", collectionID ?: @""],
                       @{ @"collection" : collectionID ?: @"" });
    }
    return NO;
  }
  NSString *normalizedName = SMTrimmedString(name);
  if ([normalizedName length] == 0) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed, @"object name is required", @{ @"field" : @"name" });
    }
    return NO;
  }
  NSString *normalizedContentType = SMNormalizedDeclaredContentType(contentType);
  if (normalizedContentType == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed,
                       @"content type must be a single media type such as image/png",
                       @{ @"field" : @"contentType", @"collection" : collectionID ?: @"" });
    }
    return NO;
  }
  BOOL contentTypeAllowed = NO;
  for (NSString *allowed in (collectionMetadata[@"acceptedContentTypes"] ?: @[])) {
    if (SMContentTypeMatches(normalizedContentType, allowed)) {
      contentTypeAllowed = YES;
      break;
    }
  }
  if (!contentTypeAllowed) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed,
                       @"content type is not allowed for this collection",
                       @{ @"field" : @"contentType", @"collection" : collectionID ?: @"" });
    }
    return NO;
  }
  NSUInteger maxBytes = [collectionMetadata[@"maxBytes"] unsignedIntegerValue];
  if (sizeBytes > maxBytes) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed,
                       @"object exceeds the collection size limit",
                       @{ @"field" : @"sizeBytes", @"collection" : collectionID ?: @"" });
    }
    return NO;
  }
  if ([definition respondsToSelector:@selector(storageModuleValidateObjectNamed:contentType:sizeBytes:metadata:runtime:error:)]) {
    return [definition storageModuleValidateObjectNamed:normalizedName
                                            contentType:normalizedContentType
                                              sizeBytes:sizeBytes
                                               metadata:(metadata ?: @{})
                                                runtime:self
                                                  error:error];
  }
  return YES;
}

- (NSDictionary *)createUploadSessionForCollection:(NSString *)collection
                                              name:(NSString *)name
                                       contentType:(NSString *)contentType
                                         sizeBytes:(NSUInteger)sizeBytes
                                          metadata:(NSDictionary *)metadata
                                         expiresIn:(NSTimeInterval)expiresIn
                                             error:(NSError **)error {
  [self pruneExpiredUploadSessionsAt:[NSDate date] recordActivity:YES];
  if (![self validateCollection:collection
                           name:name
                    contentType:contentType
                      sizeBytes:sizeBytes
                       metadata:(metadata ?: @{})
                          error:error]) {
    return nil;
  }
  NSTimeInterval ttl = (expiresIn > 0.0) ? expiresIn : self.defaultUploadSessionTTLSeconds;
  NSString *sessionID = SMRandomIdentifier(@"upload");
  if ([sessionID length] == 0) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorPersistenceFailed, @"upload session identifier could not be generated", nil);
    }
    return nil;
  }
  NSDictionary *session = @{
    @"sessionID" : sessionID,
    @"collection" : SMLowerTrimmedString(collection),
    @"name" : SMTrimmedString(name),
    @"contentType" : SMNormalizedDeclaredContentType(contentType) ?: @"application/octet-stream",
    @"sizeBytes" : @(sizeBytes),
    @"metadata" : SMNormalizeDictionary(metadata),
    @"createdAt" : @([[NSDate date] timeIntervalSince1970]),
    @"expiresAt" : @([[NSDate dateWithTimeIntervalSinceNow:ttl] timeIntervalSince1970]),
    @"status" : @"pending",
  };
  BOOL saved = [self performStateTransaction:^BOOL(NSError **blockError) {
    [self.lock lock];
    self.uploadSessionsByIdentifier[sessionID] = session;
    [self.lock unlock];
    [self recordActivityNamed:@"upload_session_created"
                      details:@{
                        @"sessionID" : sessionID ?: @"",
                        @"collection" : SMLowerTrimmedString(collection),
                        @"name" : SMTrimmedString(name),
                      }];
    return [self persistStateWithError:blockError];
  }
                                       error:error];
  if (!saved) {
    return nil;
  }
  NSString *token = SMCreateSignedToken(@{
    @"purpose" : @"upload",
    @"sessionID" : sessionID,
    @"collection" : SMLowerTrimmedString(collection),
    @"exp" : session[@"expiresAt"] ?: @0,
  }, self.signingKeyData);
  return @{
    @"sessionID" : sessionID,
    @"collection" : session[@"collection"] ?: @"",
    @"name" : session[@"name"] ?: @"",
    @"contentType" : session[@"contentType"] ?: @"application/octet-stream",
    @"sizeBytes" : session[@"sizeBytes"] ?: @0,
    @"expiresAt" : session[@"expiresAt"] ?: @0,
    @"token" : token ?: @"",
    @"uploadPath" : SMPathJoin(self.apiPrefix, [NSString stringWithFormat:@"upload-sessions/%@/upload", sessionID]),
  };
}

- (NSDictionary *)storeObjectInCollection:(NSString *)collection
                                     name:(NSString *)name
                              contentType:(NSString *)contentType
                                     data:(NSData *)data
                                 metadata:(NSDictionary *)metadata
                                    error:(NSError **)error {
  return [self storeObjectInCollection:collection
                                  name:name
                           contentType:contentType
                                  data:data
                              metadata:metadata
               completingUploadSession:nil
                      alreadyCompleted:NULL
                                 error:error];
}

// Writes the attachment and computes its checksum before taking the state
// lock; only the catalog update (and, for an upload, completing its session)
// runs under the lock. If that update fails, the attachment is deleted again
// so a failed write leaves nothing behind.
- (NSDictionary *)storeObjectInCollection:(NSString *)collection
                                     name:(NSString *)name
                              contentType:(NSString *)contentType
                                     data:(NSData *)data
                                 metadata:(NSDictionary *)metadata
                  completingUploadSession:(NSString *)sessionID
                         alreadyCompleted:(BOOL *)alreadyCompleted
                                    error:(NSError **)error {
  NSUInteger sizeBytes = [data isKindOfClass:[NSData class]] ? [data length] : 0;
  if (![self validateCollection:collection
                           name:name
                    contentType:contentType
                      sizeBytes:sizeBytes
                       metadata:(metadata ?: @{})
                          error:error]) {
    return nil;
  }
  NSString *storedContentType = SMNormalizedDeclaredContentType(contentType) ?: @"application/octet-stream";
  NSString *attachmentID = [self.attachmentAdapter saveAttachmentNamed:SMTrimmedString(name)
                                                           contentType:storedContentType
                                                                  data:data ?: [NSData data]
                                                              metadata:metadata
                                                                 error:error];
  if ([attachmentID length] == 0) {
    if (error != NULL && *error == NULL) {
      *error = SMError(ALNStorageModuleErrorPersistenceFailed, @"object data could not be persisted", nil);
    }
    return nil;
  }
  NSDictionary *collectionMetadata = [self collectionMetadataForIdentifier:collection] ?: @{};
  NSArray<NSDictionary *> *variantDefinitions = collectionMetadata[@"variants"] ?: @[];
  NSMutableArray *variants = [NSMutableArray array];
  for (NSDictionary *variant in variantDefinitions) {
    [variants addObject:[@{
      @"identifier" : SMTrimmedString(variant[@"identifier"]),
      @"label" : SMTrimmedString(variant[@"label"]),
      @"contentType" : SMTrimmedString(variant[@"contentType"]),
      @"strategy" : SMTrimmedString(variant[@"strategy"]),
      @"status" : @"pending",
      @"error" : @"",
      @"attachmentID" : @"",
      @"sizeBytes" : @0,
    } mutableCopy]];
  }
  NSDictionary *analysis = SMAnalyzeObjectData(name, storedContentType, data ?: [NSData data], metadata ?: @{}, variantDefinitions);

  NSString *objectID = SMRandomIdentifier(@"obj");
  NSString *tokenNonce = SMRandomHexString(16);
  if ([objectID length] == 0 || [tokenNonce length] == 0) {
    (void)[self.attachmentAdapter deleteAttachmentID:attachmentID error:NULL];
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorPersistenceFailed, @"storage object identifier could not be generated", nil);
    }
    return nil;
  }
  __block NSDictionary *record = nil;
  __block BOOL sessionAlreadyCompleted = NO;
  BOOL saved = NO;
  @try {
    saved = [self performStateTransaction:^BOOL(NSError **blockError) {
      [self.lock lock];
      NSDictionary *currentSession = nil;
      if ([sessionID length] > 0) {
        // Another process may have completed (or expired) the session while
        // this one wrote the data.
        currentSession = self.uploadSessionsByIdentifier[sessionID];
        if (currentSession == nil || [[currentSession[@"status"] description] isEqualToString:@"complete"]) {
          [self.lock unlock];
          sessionAlreadyCompleted = YES;
          if (blockError != NULL) {
            *blockError = SMError(ALNStorageModuleErrorValidationFailed, @"upload session has already been completed", nil);
          }
          return NO;
        }
      }
      // The sequence only orders listings; under the transaction it is unique
      // across processes too.
      self.nextSequence += 1;
      record = @{
        @"objectID" : objectID,
        @"tokenNonce" : tokenNonce,
        @"sequence" : @(self.nextSequence),
        @"collection" : SMLowerTrimmedString(collection),
        @"name" : SMTrimmedString(name),
        @"contentType" : storedContentType,
        @"sizeBytes" : @(sizeBytes),
        @"visibility" : collectionMetadata[@"visibility"] ?: @"private",
        @"attachmentID" : attachmentID ?: @"",
        @"checksumSHA256" : SMTrimmedString(analysis[@"checksumSHA256"]),
        @"metadata" : SMNormalizeDictionary(metadata),
        @"analysis" : analysis ?: @{},
        @"createdAt" : @([[NSDate date] timeIntervalSince1970]),
        @"variantState" : ([variants count] > 0) ? @"pending" : @"none",
        @"variants" : [NSArray arrayWithArray:variants],
      };
      self.objectsByIdentifier[objectID] = record;
      NSMutableArray *collectionIDs = self.objectIDsByCollection[SMLowerTrimmedString(collection)];
      if (![collectionIDs isKindOfClass:[NSMutableArray class]]) {
        collectionIDs = [NSMutableArray array];
        self.objectIDsByCollection[SMLowerTrimmedString(collection)] = collectionIDs;
      }
      [collectionIDs addObject:objectID];
      if (currentSession != nil) {
        NSMutableDictionary *updatedSession = [NSMutableDictionary dictionaryWithDictionary:currentSession];
        updatedSession[@"status"] = @"complete";
        updatedSession[@"objectID"] = objectID;
        self.uploadSessionsByIdentifier[sessionID] = [NSDictionary dictionaryWithDictionary:updatedSession];
      }
      [self.lock unlock];
      [self recordActivityNamed:@"object_stored"
                        details:@{
                          @"objectID" : record[@"objectID"] ?: @"",
                          @"collection" : record[@"collection"] ?: @"",
                          @"name" : record[@"name"] ?: @"",
                        }];
      if (currentSession != nil) {
        [self recordActivityNamed:@"upload_session_completed"
                          details:@{
                            @"sessionID" : sessionID ?: @"",
                            @"objectID" : objectID ?: @"",
                          }];
      }
      if (![self persistStateWithError:blockError]) {
        // Nothing was written; put memory back so it matches the file.
        [self.lock lock];
        [self.objectsByIdentifier removeObjectForKey:objectID];
        [collectionIDs removeObject:objectID];
        if (currentSession != nil) {
          self.uploadSessionsByIdentifier[sessionID] = currentSession;
        }
        [self.lock unlock];
        self.loadedStateStamp = @"";
        return NO;
      }
      return YES;
    }
                                         error:error];
  } @finally {
    if (!saved) {
      (void)[self.attachmentAdapter deleteAttachmentID:attachmentID error:NULL];
    }
  }
  if (!saved) {
    if (alreadyCompleted != NULL) {
      *alreadyCompleted = sessionAlreadyCompleted;
    }
    return nil;
  }

  if ([variants count] > 0) {
    (void)[self queueVariantGenerationForObjectID:record[@"objectID"] error:NULL];
  }
  return [self publicObjectRecordFromInternalRecord:record];
}

- (NSDictionary *)validatedTokenPayload:(NSString *)token
                                purpose:(NSString *)purpose
                          expectedField:(NSString *)expectedField
                          expectedValue:(NSString *)expectedValue
                                  error:(NSError **)error {
  NSDictionary *payload = SMTokenPayloadDecode(token, self.signingKeyData, error);
  if (payload == nil) {
    return nil;
  }
  if (![SMTrimmedString(payload[@"purpose"]) isEqualToString:SMTrimmedString(purpose)]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token purpose was rejected", nil);
    }
    return nil;
  }
  NSTimeInterval expiry = [payload[@"exp"] respondsToSelector:@selector(doubleValue)] ? [payload[@"exp"] doubleValue] : 0.0;
  if (expiry <= [[NSDate date] timeIntervalSince1970]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token expired", nil);
    }
    return nil;
  }
  if ([SMTrimmedString(expectedField) length] > 0 &&
      ![SMTrimmedString(payload[expectedField]) isEqualToString:SMTrimmedString(expectedValue)]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token payload does not match the requested target", nil);
    }
    return nil;
  }
  return payload;
}

- (NSDictionary *)storeUploadData:(NSData *)data
                  forUploadSessionID:(NSString *)sessionID
                               token:(NSString *)token
                               error:(NSError **)error {
  NSString *normalizedSessionID = SMTrimmedString(sessionID);
  [self pruneExpiredUploadSessionsAt:[NSDate date] recordActivity:YES];
  NSDictionary *tokenPayload = [self validatedTokenPayload:token
                                                   purpose:@"upload"
                                             expectedField:@"sessionID"
                                             expectedValue:normalizedSessionID
                                                     error:error];
  if (tokenPayload == nil) {
    return nil;
  }
  if (![self refreshStateIfChanged:error]) return nil;
  [self.lock lock];
  NSDictionary *session = self.uploadSessionsByIdentifier[normalizedSessionID];
  [self.lock unlock];
  if (session == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"upload session %@ was not found", normalizedSessionID ?: @""],
                       @{ @"sessionID" : normalizedSessionID ?: @"" });
    }
    return nil;
  }
  if ([[session[@"status"] description] isEqualToString:@"complete"]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed, @"upload session has already been completed", nil);
    }
    return nil;
  }
  NSUInteger expectedSize = [session[@"sizeBytes"] respondsToSelector:@selector(unsignedIntegerValue)]
                                ? [session[@"sizeBytes"] unsignedIntegerValue]
                                : 0;
  if (expectedSize > 0 && [data length] != expectedSize) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorValidationFailed,
                       @"upload data does not match the signed session size",
                       @{ @"field" : @"sizeBytes" });
    }
    return nil;
  }
  NSDictionary *object = [self storeObjectInCollection:session[@"collection"]
                                                  name:session[@"name"]
                                           contentType:session[@"contentType"]
                                                  data:data
                                              metadata:session[@"metadata"]
                               completingUploadSession:normalizedSessionID
                                      alreadyCompleted:NULL
                                                 error:error];
  if (object == nil) {
    return nil;
  }
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:object];
  result[@"sessionID"] = normalizedSessionID;
  return [NSDictionary dictionaryWithDictionary:result];
}

- (NSString *)issueDownloadTokenForObjectID:(NSString *)objectID
                                  expiresIn:(NSTimeInterval)expiresIn
                                      error:(NSError **)error {
  if (![self refreshStateIfChanged:error]) return nil;
  NSString *normalizedObjectID = SMTrimmedString(objectID);
  // One lookup, so the ID and nonce come from the same version of the record.
  NSDictionary *record = [self internalObjectRecordForIdentifier:normalizedObjectID];
  if (record == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"storage object %@ was not found", normalizedObjectID ?: @""],
                       @{ @"objectID" : normalizedObjectID ?: @"" });
    }
    return nil;
  }
  NSString *tokenNonce = SMTrimmedString(record[@"tokenNonce"]);
  NSTimeInterval ttl = (expiresIn > 0.0) ? expiresIn : self.defaultDownloadTokenTTLSeconds;
  // objectNonce ties the token to this object, not just to its ID.
  return SMCreateSignedToken(@{
    @"purpose" : @"download",
    @"objectID" : record[@"objectID"] ?: @"",
    @"objectNonce" : tokenNonce ?: @"",
    @"exp" : @([[NSDate dateWithTimeIntervalSinceNow:ttl] timeIntervalSince1970]),
  }, self.signingKeyData);
}

- (NSDictionary *)payloadForDownloadToken:(NSString *)token
                                    error:(NSError **)error {
  return [self validatedTokenPayload:token purpose:@"download" expectedField:nil expectedValue:nil error:error];
}

- (NSFileHandle *)openDownloadFileForToken:(NSString *)token
                        metadata:(NSDictionary **)metadata
                           error:(NSError **)error {
  if (![self.attachmentAdapter respondsToSelector:@selector(openAttachmentFileForID:metadata:error:)]) return nil;
  NSDictionary *payload = [self validatedTokenPayload:token
                                              purpose:@"download"
                                        expectedField:nil
                                        expectedValue:nil
                                                error:error];
  if (payload == nil) {
    return nil;
  }
  if (![self refreshStateIfChanged:error]) return nil;
  NSString *objectID = SMTrimmedString(payload[@"objectID"]);
  NSDictionary *stored = [self internalObjectRecordForIdentifier:objectID];
  if (stored == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"storage object %@ was not found", objectID ?: @""],
                       @{ @"objectID" : objectID ?: @"" });
    }
    return nil;
  }
  NSDictionary *record = [self publicObjectRecordFromInternalRecord:stored];
  NSString *tokenNonce = SMTrimmedString(stored[@"tokenNonce"]);
  if ([tokenNonce length] == 0 || ![SMTrimmedString(payload[@"objectNonce"]) isEqualToString:tokenNonce]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token does not match the stored object", nil);
    }
    return nil;
  }
  NSDictionary *adapterMetadata = nil;
  NSFileHandle *handle = [self.attachmentAdapter openAttachmentFileForID:stored[@"attachmentID"] metadata:&adapterMetadata error:error];
  if (handle == nil) return nil;
  struct stat fileStat;
  NSString *expected = SMTrimmedString(stored[@"checksumSHA256"]);
  BOOL valid = fstat(handle.fileDescriptor, &fileStat) == 0 && S_ISREG(fileStat.st_mode) &&
               (unsigned long long)fileStat.st_size == [stored[@"sizeBytes"] unsignedLongLongValue] &&
               expected.length > 0 &&
               [expected isEqualToString:ALNLowercaseHexStringFromData(ALNSHA256FileHandle(handle))];
  if (!valid) {
    [handle closeFile];
    if (error != NULL) *error = SMError(ALNStorageModuleErrorNotFound, @"stored object data does not match its record", nil);
    return nil;
  }
  if (metadata != NULL) {
    NSMutableDictionary *combined = [NSMutableDictionary dictionaryWithDictionary:adapterMetadata ?: @{}];
    combined[@"object"] = record;
    *metadata = [NSDictionary dictionaryWithDictionary:combined];
  }
  return handle;
}

- (NSData *)downloadDataForToken:(NSString *)token
                        metadata:(NSDictionary **)metadata
                           error:(NSError **)error {
  NSDictionary *payload = [self validatedTokenPayload:token
                                              purpose:@"download"
                                        expectedField:nil
                                        expectedValue:nil
                                                error:error];
  if (payload == nil) {
    return nil;
  }
  if (![self refreshStateIfChanged:error]) return nil;
  NSString *objectID = SMTrimmedString(payload[@"objectID"]);
  NSDictionary *stored = [self internalObjectRecordForIdentifier:objectID];
  if (stored == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"storage object %@ was not found", objectID ?: @""],
                       @{ @"objectID" : objectID ?: @"" });
    }
    return nil;
  }
  NSDictionary *record = [self publicObjectRecordFromInternalRecord:stored];
  NSString *tokenNonce = SMTrimmedString(stored[@"tokenNonce"]);
  if ([tokenNonce length] == 0 || ![SMTrimmedString(payload[@"objectNonce"]) isEqualToString:tokenNonce]) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorTokenRejected, @"token does not match the stored object", nil);
    }
    return nil;
  }
  NSDictionary *adapterMetadata = nil;
  NSData *data = [self.attachmentAdapter attachmentDataForID:stored[@"attachmentID"] metadata:&adapterMetadata error:error];
  if (data == nil) {
    return nil;
  }
  if (!SMAttachmentDataMatchesRecord(data, stored)) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       @"stored object data does not match its record",
                       @{ @"objectID" : objectID ?: @"" });
    }
    return nil;
  }
  if (metadata != NULL) {
    NSMutableDictionary *combined = [NSMutableDictionary dictionaryWithDictionary:adapterMetadata ?: @{}];
    combined[@"object"] = record;
    *metadata = [NSDictionary dictionaryWithDictionary:combined];
  }
  return data;
}

- (BOOL)deleteObjectIdentifier:(NSString *)objectID
                         error:(NSError **)error {
  return [self deleteObjectIdentifier:objectID reason:@"manual" error:error];
}

- (BOOL)deleteObjectIdentifier:(NSString *)objectID
                        reason:(NSString *)reason
                         error:(NSError **)error {
  NSString *normalizedObjectID = SMTrimmedString(objectID);
  if (![self refreshStateIfChanged:error]) return NO;
  [self.lock lock];
  NSDictionary *record = self.objectsByIdentifier[normalizedObjectID];
  [self.lock unlock];
  if (record == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"storage object %@ was not found", normalizedObjectID ?: @""],
                       @{ @"objectID" : normalizedObjectID ?: @"" });
    }
    return NO;
  }
  // Read and hash the attachments before taking the state lock, and only
  // delete the ones whose bytes are this object's.
  NSArray<NSString *> *attachmentIDs = [self attachmentIDsOwnedByRecord:record];
  __block BOOL removed = NO;
  BOOL saved = [self performStateTransaction:^BOOL(NSError **blockError) {
    [self.lock lock];
    NSDictionary *current = self.objectsByIdentifier[normalizedObjectID];
    if (current == nil) {
      [self.lock unlock];
      if (blockError != NULL) {
        *blockError = SMError(ALNStorageModuleErrorNotFound,
                              [NSString stringWithFormat:@"storage object %@ was not found", normalizedObjectID ?: @""],
                              @{ @"objectID" : normalizedObjectID ?: @"" });
      }
      return NO;
    }
    removed = [SMTrimmedString(current[@"attachmentID"]) isEqualToString:SMTrimmedString(record[@"attachmentID"])];
    [self.objectsByIdentifier removeObjectForKey:normalizedObjectID];
    NSMutableArray *collectionIDs = self.objectIDsByCollection[SMLowerTrimmedString(current[@"collection"])];
    [collectionIDs removeObject:normalizedObjectID];
    [self.lock unlock];
    [self recordActivityNamed:@"object_deleted"
                      details:@{
                        @"objectID" : normalizedObjectID ?: @"",
                        @"collection" : SMLowerTrimmedString(current[@"collection"]),
                        @"reason" : SMLowerTrimmedString(reason),
                      }];
    return [self persistStateWithError:blockError];
  }
                                       error:error];
  if (!saved) {
    return NO;
  }
  // Only once the catalog no longer names them. If the record changed in
  // between (another process re-pointed it), leave its attachments alone.
  if (removed) {
    for (NSString *attachmentID in attachmentIDs) {
      (void)[self.attachmentAdapter deleteAttachmentID:attachmentID error:NULL];
    }
  }
  return YES;
}

// The attachments (original and variants) whose stored bytes match this
// record's size and SHA-256. Bytes that don't match belong to something else.
- (NSArray<NSString *> *)attachmentIDsOwnedByRecord:(NSDictionary *)record {
  NSMutableArray<NSString *> *attachmentIDs = [NSMutableArray array];
  NSMutableArray<NSDictionary *> *candidates = [NSMutableArray arrayWithObject:record];
  for (NSDictionary *variant in ([record[@"variants"] isKindOfClass:[NSArray class]] ? record[@"variants"] : @[])) {
    if ([variant isKindOfClass:[NSDictionary class]]) {
      [candidates addObject:variant];
    }
  }
  for (NSDictionary *candidate in candidates) {
    NSString *attachmentID = SMTrimmedString(candidate[@"attachmentID"]);
    if ([attachmentID length] == 0) {
      continue;
    }
    NSData *data = [self.attachmentAdapter attachmentDataForID:attachmentID metadata:NULL error:NULL];
    if (data != nil && SMAttachmentDataMatchesRecord(data, candidate)) {
      [attachmentIDs addObject:attachmentID];
    }
  }
  return attachmentIDs;
}

- (NSDictionary *)runMaintenanceAt:(NSDate *)timestamp
                              error:(NSError **)error {
  NSDate *now = timestamp ?: [NSDate date];
  NSUInteger expiredSessions = [self pruneExpiredUploadSessionsAt:now recordActivity:YES];
  NSArray *objects = [self listObjectsForCollection:nil query:nil];
  NSUInteger deletedObjects = 0;
  for (NSDictionary *record in objects) {
    NSString *collectionID = SMLowerTrimmedString(record[@"collection"]);
    NSDictionary *collection = [self collectionMetadataForIdentifier:collectionID] ?: @{};
    NSInteger retentionDays = [collection[@"retentionDays"] respondsToSelector:@selector(integerValue)]
                                  ? [collection[@"retentionDays"] integerValue]
                                  : 0;
    if (retentionDays <= 0) {
      continue;
    }
    NSTimeInterval createdAt = [record[@"createdAt"] respondsToSelector:@selector(doubleValue)]
                                   ? [record[@"createdAt"] doubleValue]
                                   : 0.0;
    if (createdAt <= 0.0) {
      continue;
    }
    NSTimeInterval retentionAge = (NSTimeInterval)retentionDays * 86400.0;
    if ((createdAt + retentionAge) > [now timeIntervalSince1970]) {
      continue;
    }
    NSError *deleteError = nil;
    if ([self deleteObjectIdentifier:record[@"objectID"] reason:@"retention_expired" error:&deleteError]) {
      deletedObjects += 1;
    } else if (error != NULL && *error == nil) {
      *error = deleteError;
    }
  }
  NSDictionary *summary = @{
    @"expiredUploadSessions" : @(expiredSessions),
    @"deletedObjects" : @(deletedObjects),
    @"timestamp" : @([now timeIntervalSince1970]),
  };
  BOOL saved = [self performStateTransaction:^BOOL(NSError **blockError) {
    [self recordActivityNamed:@"maintenance_completed" details:summary];
    return [self persistStateWithError:blockError];
  }
                                       error:error];
  if (!saved) {
    return nil;
  }
  return summary;
}

- (NSDictionary *)queueVariantGenerationForObjectID:(NSString *)objectID
                                              error:(NSError **)error {
  NSDictionary *record = [self objectRecordForIdentifier:objectID error:error];
  if (record == nil) {
    return nil;
  }
  NSArray *variants = [record[@"variants"] isKindOfClass:[NSArray class]] ? record[@"variants"] : @[];
  if ([variants count] == 0) {
    return @{ @"objectID" : record[@"objectID"] ?: @"", @"queuedCount" : @0, @"status" : @"no_variants" };
  }
  BOOL reset = [self performStateTransaction:^BOOL(NSError **blockError) {
    [self.lock lock];
    // Update the stored record, which carries fields the public copy omits.
    NSDictionary *stored = self.objectsByIdentifier[record[@"objectID"] ?: @""];
    if (stored == nil) {
      [self.lock unlock];
      if (blockError != NULL) {
        *blockError = SMError(ALNStorageModuleErrorNotFound, @"storage object was not found",
                              @{ @"objectID" : record[@"objectID"] ?: @"" });
      }
      return NO;
    }
    NSMutableArray *resetVariants = [NSMutableArray array];
    for (NSDictionary *variant in ([stored[@"variants"] isKindOfClass:[NSArray class]] ? stored[@"variants"] : @[])) {
      NSMutableDictionary *mutableVariant = [NSMutableDictionary dictionaryWithDictionary:variant];
      mutableVariant[@"status"] = @"pending";
      mutableVariant[@"error"] = @"";
      [resetVariants addObject:mutableVariant];
    }
    NSMutableDictionary *mutableRecord = [NSMutableDictionary dictionaryWithDictionary:stored];
    mutableRecord[@"variants"] = [NSArray arrayWithArray:resetVariants];
    mutableRecord[@"variantState"] = @"pending";
    self.objectsByIdentifier[record[@"objectID"]] = [NSDictionary dictionaryWithDictionary:mutableRecord];
    [self.lock unlock];
    return [self persistStateWithError:blockError];
  }
                                       error:error];
  if (!reset) {
    return nil;
  }
  NSUInteger queuedCount = 0;
  for (NSDictionary *variant in variants) {
    NSString *variantID = SMTrimmedString(variant[@"identifier"]);
    if ([variantID length] == 0) {
      continue;
    }
    NSError *jobError = nil;
    NSString *jobID = [[ALNJobsModuleRuntime sharedRuntime] enqueueJobIdentifier:ALNStorageVariantJobIdentifier
                                                                         payload:@{ @"objectID" : record[@"objectID"] ?: @"", @"variant" : variantID }
                                                                         options:@{ @"queue" : @"default", @"source" : @"storage" }
                                                                           error:&jobError];
    if ([jobID length] > 0) {
      queuedCount += 1;
    } else if (error != NULL && *error == nil) {
      *error = jobError;
    }
  }
  NSDictionary *summary = @{ @"objectID" : record[@"objectID"] ?: @"", @"queuedCount" : @(queuedCount), @"status" : @"queued" };
  (void)[self performStateTransaction:^BOOL(NSError **blockError) {
    [self recordActivityNamed:@"variant_generation_queued"
                      details:@{
                        @"objectID" : record[@"objectID"] ?: @"",
                        @"queuedCount" : @(queuedCount),
                      }];
    return [self persistStateWithError:blockError];
  }
                                error:NULL];
  return summary;
}

- (NSDictionary *)processVariantJobPayload:(NSDictionary *)payload
                                     error:(NSError **)error {
  return [self processVariantJobPayload:payload jobContext:@{} error:error];
}

- (NSDictionary *)processVariantJobPayload:(NSDictionary *)payload
                                 jobContext:(NSDictionary *)jobContext
                                      error:(NSError **)error {
  NSString *objectID = SMTrimmedString(payload[@"objectID"]);
  NSString *variantID = SMLowerTrimmedString(payload[@"variant"]);
  if (![self refreshStateIfChanged:error]) return nil;
  [self.lock lock];
  NSDictionary *record = self.objectsByIdentifier[objectID];
  [self.lock unlock];
  if (record == nil) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound, @"storage object was not found", @{ @"objectID" : objectID ?: @"" });
    }
    return nil;
  }
  // Variant hooks accept NSData, so bound their source before materialization.
  NSUInteger inputLimit = [self.moduleConfig[@"maxVariantInputBytes"] respondsToSelector:@selector(unsignedIntegerValue)]
      ? [self.moduleConfig[@"maxVariantInputBytes"] unsignedIntegerValue] : 16 * 1024 * 1024;
  if (inputLimit == 0) inputLimit = 16 * 1024 * 1024;
  inputLimit = MIN(inputLimit, NSUIntegerMax - 1);
  if ([record[@"sizeBytes"] unsignedLongLongValue] > inputLimit) {
    if (error != NULL) *error = SMError(ALNStorageModuleErrorValidationFailed, @"variant source exceeds maxVariantInputBytes", nil);
    return nil;
  }
  NSDictionary *originalMetadata = nil;
  NSData *data = nil;
  NSFileHandle *source = nil;
  if ([self.attachmentAdapter respondsToSelector:@selector(openAttachmentFileForID:metadata:error:)]) {
    source = [self.attachmentAdapter openAttachmentFileForID:record[@"attachmentID"] metadata:&originalMetadata error:error];
    if (source == nil && error != NULL && *error != nil) return nil;
  }
  if (source != nil) {
    @try { data = [source readDataOfLength:inputLimit + 1]; }
    @catch (NSException *exception) {
      if (error != NULL) *error = SMError(ALNStorageModuleErrorNotFound, @"variant source could not be read", nil);
    } @finally { [source closeFile]; }
  } else {
    data = [self.attachmentAdapter attachmentDataForID:record[@"attachmentID"] metadata:&originalMetadata error:error];
  }
  if (data.length > inputLimit) {
    if (error != NULL) *error = SMError(ALNStorageModuleErrorValidationFailed, @"variant source exceeds maxVariantInputBytes", nil);
    return nil;
  }
  if (data == nil) {
    return nil;
  }
  if (!SMAttachmentDataMatchesRecord(data, record)) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       @"stored object data does not match its record",
                       @{ @"objectID" : objectID ?: @"" });
    }
    return nil;
  }
  NSString *collectionID = SMLowerTrimmedString(record[@"collection"]);
  id<ALNStorageCollectionDefinition> definition = self.collectionDefinitionsByIdentifier[collectionID];
  NSMutableArray *updatedVariants = [NSMutableArray array];
  BOOL found = NO;
  NSString *generatedAttachmentID = nil;
  NSError *processingError = nil;
  for (NSDictionary *variant in (record[@"variants"] ?: @[])) {
    NSMutableDictionary *mutableVariant = [NSMutableDictionary dictionaryWithDictionary:variant];
    if ([SMLowerTrimmedString(variant[@"identifier"]) isEqualToString:variantID]) {
      found = YES;
      NSData *variantData = data;
      NSString *variantContentType = ([SMLowerTrimmedString(variant[@"contentType"]) length] > 0)
                                         ? SMLowerTrimmedString(variant[@"contentType"])
                                         : SMLowerTrimmedString(record[@"contentType"]);
      NSDictionary *variantMetadata = @{
        @"sourceObjectID" : objectID ?: @"",
        @"variant" : variantID ?: @"",
      };
      if (definition != nil &&
          [definition respondsToSelector:@selector(storageModuleVariantRepresentationForObject:variantDefinition:originalData:originalMetadata:runtime:error:)]) {
        NSDictionary *representation =
            [definition storageModuleVariantRepresentationForObject:[self publicObjectRecordFromInternalRecord:record]
                                                 variantDefinition:variant
                                                      originalData:data
                                                  originalMetadata:originalMetadata ?: @{}
                                                           runtime:self
                                                             error:&processingError];
        if ([representation isKindOfClass:[NSDictionary class]]) {
          NSData *candidateData = [representation[@"data"] isKindOfClass:[NSData class]] ? representation[@"data"] : nil;
          if (candidateData != nil) {
            variantData = candidateData;
          }
          NSString *candidateContentType = SMLowerTrimmedString(representation[@"contentType"]);
          if ([candidateContentType length] > 0) {
            variantContentType = candidateContentType;
          }
          NSDictionary *candidateMetadata = [representation[@"metadata"] isKindOfClass:[NSDictionary class]]
                                                ? representation[@"metadata"]
                                                : nil;
          if (candidateMetadata != nil) {
            NSMutableDictionary *mergedMetadata = [NSMutableDictionary dictionaryWithDictionary:variantMetadata];
            [mergedMetadata addEntriesFromDictionary:candidateMetadata];
            variantMetadata = mergedMetadata;
          }
        } else if (representation == nil && processingError != nil) {
          mutableVariant[@"status"] = @"failed";
          mutableVariant[@"error"] = processingError.localizedDescription ?: @"variant generation failed";
        }
      }
      if (processingError == nil) {
        generatedAttachmentID = [self.attachmentAdapter saveAttachmentNamed:[NSString stringWithFormat:@"%@-%@", record[@"name"] ?: @"object", variantID]
                                                                contentType:variantContentType
                                                                       data:variantData
                                                                   metadata:variantMetadata
                                                                      error:&processingError];
        if ([generatedAttachmentID length] == 0) {
          mutableVariant[@"status"] = @"failed";
          mutableVariant[@"error"] = processingError.localizedDescription ?: @"variant generation failed";
        }
      }
      if (processingError == nil) {
        mutableVariant[@"status"] = @"ready";
        mutableVariant[@"attachmentID"] = generatedAttachmentID;
        mutableVariant[@"sizeBytes"] = @([variantData length]);
        mutableVariant[@"checksumSHA256"] = ALNLowercaseHexStringFromData(ALNSHA256(variantData)) ?: @"";
        mutableVariant[@"generatedAt"] = @([[NSDate date] timeIntervalSince1970]);
        mutableVariant[@"error"] = @"";
      }
    }
    [updatedVariants addObject:mutableVariant];
  }
  if (!found) {
    if (error != NULL) {
      *error = SMError(ALNStorageModuleErrorNotFound,
                       [NSString stringWithFormat:@"variant %@ was not found", variantID ?: @""],
                       @{ @"variant" : variantID ?: @"" });
    }
    return nil;
  }
  BOOL allReady = YES;
  BOOL anyFailed = NO;
  for (NSDictionary *variant in updatedVariants) {
    if (![SMTrimmedString(variant[@"status"]) isEqualToString:@"ready"]) {
      allReady = NO;
    }
    if ([SMTrimmedString(variant[@"status"]) isEqualToString:@"failed"]) {
      anyFailed = YES;
    }
  }
  NSString *variantState = allReady ? @"ready" : (anyFailed ? @"failed" : @"pending");
  NSDictionary *analysis = SMAnalyzeObjectData(record[@"name"],
                                               record[@"contentType"],
                                               data ?: [NSData data],
                                               record[@"metadata"] ?: @{},
                                               updatedVariants);
  NSString *sourceAttachmentID = SMTrimmedString(record[@"attachmentID"]);
  NSError *saveError = nil;
  BOOL saved = [self performStateTransaction:^BOOL(NSError **blockError) {
    [self.lock lock];
    // The object may have been deleted (or replaced) while the variant was
    // generated; only update the record this job started from.
    NSDictionary *current = self.objectsByIdentifier[objectID];
    if (current == nil || ![SMTrimmedString(current[@"attachmentID"]) isEqualToString:sourceAttachmentID]) {
      [self.lock unlock];
      if (blockError != NULL) {
        *blockError = SMError(ALNStorageModuleErrorNotFound, @"storage object was not found",
                              @{ @"objectID" : objectID ?: @"" });
      }
      return NO;
    }
    NSMutableDictionary *updatedRecord = [NSMutableDictionary dictionaryWithDictionary:current];
    updatedRecord[@"variants"] = [NSArray arrayWithArray:updatedVariants];
    updatedRecord[@"variantState"] = variantState;
    updatedRecord[@"analysis"] = analysis ?: @{};
    self.objectsByIdentifier[objectID] = [NSDictionary dictionaryWithDictionary:updatedRecord];
    [self.lock unlock];
    return [self persistStateWithError:blockError];
  }
                                       error:&saveError];
  if (!saved) {
    // Whether the object went away or the catalog write failed, nothing
    // names the generated attachment.
    if ([generatedAttachmentID length] > 0) {
      (void)[self.attachmentAdapter deleteAttachmentID:generatedAttachmentID error:NULL];
    }
    if (error != NULL) {
      *error = saveError;
    }
    return nil;
  }
  NSUInteger attempt = [jobContext[@"attempt"] respondsToSelector:@selector(unsignedIntegerValue)]
                           ? [jobContext[@"attempt"] unsignedIntegerValue]
                           : 1;
  NSUInteger maxAttempts = [jobContext[@"maxAttempts"] respondsToSelector:@selector(unsignedIntegerValue)]
                               ? [jobContext[@"maxAttempts"] unsignedIntegerValue]
                               : 1;
  if (processingError != nil) {
    (void)[self performStateTransaction:^BOOL(NSError **blockError) {
      [self recordActivityNamed:@"variant_failed"
                        details:@{
                          @"objectID" : objectID ?: @"",
                          @"variant" : variantID ?: @"",
                          @"attempt" : @(attempt),
                          @"maxAttempts" : @(maxAttempts),
                          @"error" : processingError.localizedDescription ?: @"variant generation failed",
                        }];
      return [self persistStateWithError:blockError];
    }
                                  error:NULL];
    if (error != NULL) {
      *error = processingError;
    }
    return nil;
  }
  NSDictionary *summary = @{
    @"objectID" : objectID ?: @"",
    @"variant" : variantID ?: @"",
    @"status" : @"ready",
    @"attachmentID" : generatedAttachmentID ?: @"",
  };
  BOOL recorded = [self performStateTransaction:^BOOL(NSError **blockError) {
    [self recordActivityNamed:@"variant_ready"
                      details:@{
                        @"objectID" : objectID ?: @"",
                        @"variant" : variantID ?: @"",
                      }];
    return [self persistStateWithError:blockError];
  }
                                          error:error];
  if (!recorded) {
    return nil;
  }
  return summary;
}

- (NSDictionary *)dashboardSummary {
  if (![self refreshStateIfChanged:NULL]) return @{};
  [self pruneExpiredUploadSessionsAt:[NSDate date] recordActivity:NO];
  NSArray *collections = [self registeredCollections];
  NSArray *allObjects = [self listObjectsForCollection:nil query:nil];
  NSUInteger pendingVariantCount = 0;
  for (NSDictionary *record in allObjects) {
    for (NSDictionary *variant in (record[@"variants"] ?: @[])) {
      if ([SMTrimmedString(variant[@"status"]) isEqualToString:@"pending"]) {
        pendingVariantCount += 1;
      }
    }
  }
  return @{
    @"cards" : @[
      @{ @"label" : @"Collections", @"value" : @([collections count]) },
      @{ @"label" : @"Objects", @"value" : @([allObjects count]) },
      @{ @"label" : @"Upload sessions", @"value" : @([self.uploadSessionsByIdentifier count]) },
      @{ @"label" : @"Pending variants", @"value" : @(pendingVariantCount) },
      @{ @"label" : @"Activity", @"value" : @([self.activityLog count]) },
    ],
    @"collections" : collections ?: @[],
    @"attachmentAdapter" : @{
      @"name" : (self.attachmentAdapter != nil) ? [self.attachmentAdapter adapterName] : @"",
      @"capabilities" : SMAttachmentAdapterCapabilities(self.attachmentAdapter),
    },
    @"recentObjects" : ([allObjects count] > 5) ? [allObjects subarrayWithRange:NSMakeRange(0, 5)] : allObjects,
    @"recentActivity" : ([[NSArray alloc] initWithArray:self.activityLog copyItems:YES] ?: @[]),
  };
}

@end

@interface ALNStorageModuleController : ALNController

@property(nonatomic, strong) ALNStorageModuleRuntime *runtime;
@property(nonatomic, strong) ALNAuthModuleRuntime *authRuntime;

- (BOOL)requireStorageHTML:(ALNContext *)ctx;

@end

@interface ALNStorageAdminResource : NSObject <ALNAdminUIResource>

@property(nonatomic, strong) ALNStorageModuleRuntime *runtime;

- (instancetype)initWithRuntime:(ALNStorageModuleRuntime *)runtime;

@end

@interface ALNStorageAdminResourceProvider : NSObject <ALNAdminUIResourceProvider>
@end

@implementation ALNStorageModuleController

// A busy state lock is temporary: answer 503 and say when to retry.
- (void)setStorageErrorStatus:(NSError *)error otherwise:(NSInteger)status {
  if (error.code == ALNStorageModuleErrorStateBusy) {
    [self setStatus:503];
    [self.context.response setHeader:@"Retry-After" value:@"1"];
    return;
  }
  [self setStatus:status];
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    _runtime = [ALNStorageModuleRuntime sharedRuntime];
    _authRuntime = [ALNAuthModuleRuntime sharedRuntime];
  }
  return self;
}

- (NSDictionary *)requestParameters {
  NSMutableDictionary *parameters = [NSMutableDictionary dictionaryWithDictionary:self.context.request.queryParams ?: @{}];
  NSString *contentType = [[[self headerValueForName:@"content-type"] lowercaseString] componentsSeparatedByString:@";"][0];
  NSDictionary *bodyParameters = @{};
  if ([contentType containsString:@"application/json"]) {
    bodyParameters = SMJSONParametersFromBody(self.context.request.body);
  } else if ([contentType containsString:@"application/x-www-form-urlencoded"]) {
    bodyParameters = SMFormParametersFromBody(self.context.request.body);
  }
  [parameters addEntriesFromDictionary:bodyParameters ?: @{}];
  return parameters;
}

- (NSString *)storageReturnPathForContext:(ALNContext *)ctx {
  NSString *path = ctx.request.path ?: @"/";
  NSString *query = SMTrimmedString(ctx.request.queryString);
  if ([query length] > 0) {
    return [NSString stringWithFormat:@"%@?%@", path, query];
  }
  return path;
}

- (NSDictionary *)pageContextWithTitle:(NSString *)title
                               heading:(NSString *)heading
                               message:(NSString *)message
                                errors:(NSArray *)errors
                                 extra:(NSDictionary *)extra {
  NSMutableDictionary *context = [NSMutableDictionary dictionary];
  context[@"pageTitle"] = title ?: @"Arlen Storage";
  context[@"pageHeading"] = heading ?: context[@"pageTitle"];
  context[@"message"] = message ?: @"";
  context[@"errors"] = [errors isKindOfClass:[NSArray class]] ? errors : @[];
  context[@"storagePrefix"] = self.runtime.prefix ?: @"/storage";
  context[@"storageAPIPrefix"] = self.runtime.apiPrefix ?: @"/storage/api";
  context[@"authLoginPath"] = [self.authRuntime loginPath] ?: @"/auth/login";
  context[@"authLogoutPath"] = [self.authRuntime logoutPath] ?: @"/auth/logout";
  context[@"csrfToken"] = [self csrfToken] ?: @"";
  context[@"summary"] = [self.runtime dashboardSummary] ?: @{};
  if ([extra isKindOfClass:[NSDictionary class]]) {
    [context addEntriesFromDictionary:extra];
  }
  return context;
}

- (BOOL)requireStorageHTML:(ALNContext *)ctx {
  NSString *returnTo = [self storageReturnPathForContext:ctx];
  if ([[ctx authSubject] length] == 0) {
    NSString *location = [NSString stringWithFormat:@"%@?return_to=%@",
                                                    [self.authRuntime loginPath] ?: @"/auth/login",
                                                    SMPercentEncodedQueryComponent(returnTo)];
    [self redirectTo:location status:302];
    return NO;
  }
  if (![self.authRuntime isAdminContext:ctx error:NULL]) {
    [self setStatus:403];
    [self renderTemplate:@"modules/storage/result/index"
                 context:[self pageContextWithTitle:@"Storage Access"
                                            heading:@"Access denied"
                                            message:@"You do not have the operator/admin role required for storage."
                                             errors:nil
                                              extra:nil]
                  layout:@"modules/storage/layouts/main"
                   error:NULL];
    return NO;
  }
  if ([ctx authAssuranceLevel] < 2) {
    NSString *location = SMStepUpLocation(self.authRuntime, SMPercentEncodedQueryComponent(returnTo));
    [self redirectTo:location status:302];
    return NO;
  }
  return YES;
}

- (id)dashboard:(ALNContext *)ctx {
  (void)ctx;
  [self renderTemplate:@"modules/storage/dashboard/index"
               context:[self pageContextWithTitle:@"Storage"
                                          heading:@"Storage"
                                          message:@""
                                           errors:nil
                                            extra:nil]
                layout:@"modules/storage/layouts/main"
                 error:NULL];
  return nil;
}

- (id)collectionIndex:(ALNContext *)ctx {
  NSString *collection = [self stringParamForName:@"collection"] ?: @"";
  NSDictionary *metadata = [self.runtime collectionMetadataForIdentifier:collection];
  if (metadata == nil) {
    [self setStatus:404];
    [self renderTemplate:@"modules/storage/result/index"
                 context:[self pageContextWithTitle:@"Storage"
                                            heading:@"Collection not found"
                                            message:@"The requested storage collection does not exist."
                                             errors:nil
                                              extra:@{
                                                @"resultActionPath" : self.runtime.prefix ?: @"/storage",
                                                @"resultActionLabel" : @"Back to storage",
                                              }]
                  layout:@"modules/storage/layouts/main"
                   error:NULL];
    return nil;
  }
  [self renderTemplate:@"modules/storage/collections/index"
               context:[self pageContextWithTitle:metadata[@"title"]
                                          heading:metadata[@"title"]
                                          message:@""
                                           errors:nil
                                            extra:@{
                                              @"collection" : metadata,
                                              @"objects" : [self.runtime listObjectsForCollection:collection query:[self queryValueForName:@"q"]] ?: @[],
                                              @"query" : [self queryValueForName:@"q"] ?: @"",
                                            }]
                layout:@"modules/storage/layouts/main"
                 error:NULL];
  return nil;
}

- (id)objectDetail:(ALNContext *)ctx {
  NSString *collection = [self stringParamForName:@"collection"] ?: @"";
  NSError *error = nil;
  NSDictionary *record = [self.runtime objectRecordForIdentifier:[self stringParamForName:@"objectID"] ?: @"" error:&error];
  if (record == nil || ![SMLowerTrimmedString(record[@"collection"]) isEqualToString:SMLowerTrimmedString(collection)]) {
    [self setStatus:404];
    [self renderTemplate:@"modules/storage/result/index"
                 context:[self pageContextWithTitle:@"Storage"
                                            heading:@"Object not found"
                                            message:error.localizedDescription ?: @"The requested object could not be found."
                                             errors:nil
                                              extra:@{
                                                @"resultActionPath" : SMPathJoin(self.runtime.prefix, [NSString stringWithFormat:@"collections/%@", collection]),
                                                @"resultActionLabel" : @"Back to collection",
                                              }]
                  layout:@"modules/storage/layouts/main"
                   error:NULL];
    return nil;
  }
  [self renderTemplate:@"modules/storage/objects/show"
               context:[self pageContextWithTitle:record[@"name"]
                                          heading:record[@"name"]
                                          message:@""
                                           errors:nil
                                            extra:@{
                                              @"object" : record,
                                            }]
                layout:@"modules/storage/layouts/main"
                 error:NULL];
  return nil;
}

- (id)deleteObjectHTML:(ALNContext *)ctx {
  NSError *error = nil;
  BOOL ok = [self.runtime deleteObjectIdentifier:[self stringParamForName:@"objectID"] ?: @"" error:&error];
  if (!ok) {
    [self setStatus:422];
    [self renderTemplate:@"modules/storage/result/index"
                 context:[self pageContextWithTitle:@"Storage"
                                            heading:@"Delete failed"
                                            message:error.localizedDescription ?: @"Delete failed."
                                             errors:nil
                                              extra:@{
                                                @"resultActionPath" : self.runtime.prefix ?: @"/storage",
                                                @"resultActionLabel" : @"Back to storage",
                                              }]
                  layout:@"modules/storage/layouts/main"
                   error:NULL];
    return nil;
  }
  [self redirectTo:SMPathJoin(self.runtime.prefix, [NSString stringWithFormat:@"collections/%@", [self stringParamForName:@"collection"] ?: @""]) status:302];
  return nil;
}

- (id)regenerateVariantsHTML:(ALNContext *)ctx {
  (void)[self.runtime queueVariantGenerationForObjectID:[self stringParamForName:@"objectID"] ?: @"" error:NULL];
  [self redirectTo:SMPathJoin(self.runtime.prefix,
                              [NSString stringWithFormat:@"collections/%@/objects/%@",
                                                         [self stringParamForName:@"collection"] ?: @"",
                                                         [self stringParamForName:@"objectID"] ?: @""]) status:302];
  return nil;
}

- (id)apiCollections:(ALNContext *)ctx {
  (void)ctx;
  [self renderJSONEnvelopeWithData:@{ @"collections" : [self.runtime registeredCollections] ?: @[] } meta:nil error:NULL];
  return nil;
}

- (id)apiObjects:(ALNContext *)ctx {
  NSString *collection = [self stringParamForName:@"collection"] ?: @"";
  [self renderJSONEnvelopeWithData:@{
    @"collection" : [self.runtime collectionMetadataForIdentifier:collection] ?: @{},
    @"objects" : [self.runtime listObjectsForCollection:collection query:[self queryValueForName:@"q"]] ?: @[],
  } meta:nil error:NULL];
  return nil;
}

- (id)apiObjectDetail:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  NSDictionary *record = [self.runtime objectRecordForIdentifier:[self stringParamForName:@"objectID"] ?: @"" error:&error];
  if (record == nil) {
    [self setStatus:404];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Object not found" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"object" : record } meta:nil error:NULL];
  return nil;
}

- (id)apiCreateUploadSession:(ALNContext *)ctx {
  (void)ctx;
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSDictionary *session = [self.runtime createUploadSessionForCollection:SMTrimmedString(parameters[@"collection"])
                                                                    name:SMTrimmedString(parameters[@"name"])
                                                             contentType:SMLowerTrimmedString(parameters[@"contentType"])
                                                               sizeBytes:ALNUnsignedIntegerValueOrDefault(parameters[@"sizeBytes"], 0)
                                                                metadata:SMNormalizeDictionary(parameters[@"metadata"])
                                                               expiresIn:[parameters[@"expiresIn"] respondsToSelector:@selector(doubleValue)] ? [parameters[@"expiresIn"] doubleValue] : 0.0
                                                                   error:&error];
  if (session == nil) {
    [self setStorageErrorStatus:error otherwise:(error.code == ALNStorageModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Upload session failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:session meta:nil error:NULL];
  return nil;
}

- (id)apiUpload:(ALNContext *)ctx {
  (void)ctx;
  // Upload tokens are accepted only in the header; query strings end up in logs.
  NSString *token = [self headerValueForName:@"x-upload-token"];
  NSError *error = nil;
  NSDictionary *object = [self.runtime storeUploadData:self.context.request.body ?: [NSData data]
                                    forUploadSessionID:[self stringParamForName:@"sessionID"] ?: @""
                                                 token:token
                                                 error:&error];
  if (object == nil) {
    [self setStorageErrorStatus:error otherwise:(error.code == ALNStorageModuleErrorNotFound || error.code == ALNStorageModuleErrorTokenRejected) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Upload failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"object" : object } meta:nil error:NULL];
  return nil;
}

- (id)apiIssueDownloadToken:(ALNContext *)ctx {
  NSDictionary *parameters = [self requestParameters];
  NSError *error = nil;
  NSString *token = [self.runtime issueDownloadTokenForObjectID:[self stringParamForName:@"objectID"] ?: @""
                                                      expiresIn:[parameters[@"expiresIn"] respondsToSelector:@selector(doubleValue)] ? [parameters[@"expiresIn"] doubleValue] : 0.0
                                                          error:&error];
  if ([token length] == 0) {
    [self setStorageErrorStatus:error otherwise:(error.code == ALNStorageModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Download token failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{
    @"token" : token,
    @"downloadPath" : SMPathJoin(self.runtime.apiPrefix, [NSString stringWithFormat:@"download/%@", token]),
  } meta:nil error:NULL];
  return nil;
}

- (id)apiDownload:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  NSDictionary *metadata = nil;
  NSString *token = [self stringParamForName:@"token"] ?: @"";
  NSFileHandle *handle = [self.runtime openDownloadFileForToken:token metadata:&metadata error:&error];
  NSData *data = (handle == nil && error == nil) ? [self.runtime downloadDataForToken:token metadata:&metadata error:&error] : nil;
  if (data == nil && handle == nil) {
    [self setStorageErrorStatus:error otherwise:(error.code == ALNStorageModuleErrorTokenRejected || error.code == ALNStorageModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Download failed" } error:NULL];
    return nil;
  }
  // Send only the media type parsed and classified here, never the stored
  // string itself; a value that does not parse is served as opaque bytes.
  NSString *contentType = SMNormalizedDeclaredContentType(metadata[@"object"][@"contentType"]) ?: @"application/octet-stream";
  // Stored objects carry the uploader-declared content type, so only a small
  // set of passive media types is displayed inline; everything else is a
  // download. A sandbox policy keeps any document that is rendered from
  // running script on the app origin, and nosniff stops type guessing.
  // Inline PDF keeps the app policy: browser PDF viewers refuse to run in a
  // sandboxed document.
  BOOL inlineDisposition = SMContentTypeAllowsInlineDownload(contentType);
  ALNResponse *response = self.context.response;
  [response setHeader:@"Content-Disposition"
                value:SMContentDispositionForDownload(metadata[@"object"][@"name"], inlineDisposition)];
  [response setHeader:@"X-Content-Type-Options" value:@"nosniff"];
  if (!(inlineDisposition && [SMBaseContentType(contentType) isEqualToString:@"application/pdf"])) {
    [response setHeader:@"Content-Security-Policy" value:@"sandbox"];
  }
  if (handle != nil) {
    NSString *checksum = metadata[@"object"][@"checksumSHA256"];
    NSDictionary *options = checksum.length > 0 ? @{ ALNFileResponseETagOption : [NSString stringWithFormat:@"\"%@\"", checksum] } : @{};
    [ALNFileResponse prepareResponse:response forRequest:self.context.request fileHandle:handle contentType:contentType options:options];
  } else {
    [self renderData:data contentType:contentType];
  }
  return nil;
}

- (id)apiDeleteObject:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  BOOL ok = [self.runtime deleteObjectIdentifier:[self stringParamForName:@"objectID"] ?: @"" error:&error];
  if (!ok) {
    [self setStorageErrorStatus:error otherwise:(error.code == ALNStorageModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Delete failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:@{ @"deleted" : @YES } meta:nil error:NULL];
  return nil;
}

- (id)apiRegenerateVariants:(ALNContext *)ctx {
  (void)ctx;
  NSError *error = nil;
  NSDictionary *summary = [self.runtime queueVariantGenerationForObjectID:[self stringParamForName:@"objectID"] ?: @"" error:&error];
  if (summary == nil) {
    [self setStorageErrorStatus:error otherwise:(error.code == ALNStorageModuleErrorNotFound) ? 404 : 422];
    [self renderJSONEnvelopeWithData:nil meta:@{ @"error" : error.localizedDescription ?: @"Variant queue failed" } error:NULL];
    return nil;
  }
  [self renderJSONEnvelopeWithData:summary meta:nil error:NULL];
  return nil;
}

@end

@implementation ALNStorageAdminResource

- (instancetype)initWithRuntime:(ALNStorageModuleRuntime *)runtime {
  self = [super init];
  if (self != nil) {
    _runtime = runtime;
  }
  return self;
}

- (NSString *)adminUIResourceIdentifier {
  return @"storage_objects";
}

- (NSDictionary *)adminUIResourceMetadata {
  return @{
    @"label" : @"Storage Objects",
    @"singularLabel" : @"Storage Object",
    @"summary" : @"Inspect uploaded objects, metadata, download-token paths, and variant state.",
    @"identifierField" : @"objectID",
    @"primaryField" : @"name",
    @"legacyPath" : @"storage/objects",
    @"fields" : @[
      @{ @"name" : @"name", @"label" : @"Name", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"collection", @"label" : @"Collection", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"contentType", @"label" : @"Content Type", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"sizeBytes", @"label" : @"Size", @"kind" : @"integer", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"visibility", @"label" : @"Visibility", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"variantState", @"label" : @"Variants", @"list" : @YES, @"detail" : @YES },
      @{ @"name" : @"objectID", @"label" : @"Object ID", @"list" : @NO, @"detail" : @YES },
    ],
    @"filters" : @[ @{ @"name" : @"q", @"label" : @"Search", @"type" : @"search", @"placeholder" : @"name, collection, type" } ],
    @"actions" : @[
      @{ @"name" : @"delete", @"label" : @"Delete", @"scope" : @"row", @"method" : @"POST" },
      @{ @"name" : @"regenerate_variants", @"label" : @"Regenerate variants", @"scope" : @"row", @"method" : @"POST" },
    ],
  };
}

- (NSArray<NSDictionary *> *)adminUIListRecordsMatching:(NSString *)query
                                                  limit:(NSUInteger)limit
                                                 offset:(NSUInteger)offset
                                                  error:(NSError **)error {
  (void)error;
  NSArray *records = [self.runtime listObjectsForCollection:nil query:query];
  if (offset >= [records count]) {
    return @[];
  }
  NSUInteger sliceLength = MIN(limit, [records count] - offset);
  return [records subarrayWithRange:NSMakeRange(offset, sliceLength)];
}

- (NSDictionary *)adminUIDetailRecordForIdentifier:(NSString *)identifier
                                             error:(NSError **)error {
  return [self.runtime objectRecordForIdentifier:identifier error:error];
}

- (NSDictionary *)adminUIUpdateRecordWithIdentifier:(NSString *)identifier
                                         parameters:(NSDictionary *)parameters
                                              error:(NSError **)error {
  (void)identifier;
  (void)parameters;
  if (error != NULL) {
    *error = SMError(ALNStorageModuleErrorValidationFailed, @"storage objects are not directly editable", nil);
  }
  return nil;
}

- (NSDictionary *)adminUIDashboardSummaryWithError:(NSError **)error {
  (void)error;
  NSDictionary *summary = [self.runtime dashboardSummary];
  return @{ @"cards" : summary[@"cards"] ?: @[] };
}

- (NSDictionary *)adminUIPerformActionNamed:(NSString *)actionName
                                 identifier:(NSString *)identifier
                                 parameters:(NSDictionary *)parameters
                                      error:(NSError **)error {
  (void)parameters;
  NSString *normalizedAction = SMLowerTrimmedString(actionName);
  if ([normalizedAction isEqualToString:@"delete"]) {
    if (![self.runtime deleteObjectIdentifier:identifier error:error]) {
      return nil;
    }
    return @{ @"record" : @{}, @"message" : @"Storage object deleted." };
  }
  if ([normalizedAction isEqualToString:@"regenerate_variants"]) {
    NSDictionary *summary = [self.runtime queueVariantGenerationForObjectID:identifier error:error];
    return (summary != nil) ? @{ @"record" : [self.runtime objectRecordForIdentifier:identifier error:NULL] ?: @{}, @"message" : @"Variant generation queued." }
                            : nil;
  }
  if (error != NULL) {
    *error = SMError(ALNStorageModuleErrorNotFound,
                     [NSString stringWithFormat:@"unknown storage action %@", normalizedAction ?: @""],
                     @{ @"action" : normalizedAction ?: @"" });
  }
  return nil;
}

@end

@implementation ALNStorageAdminResourceProvider

- (NSArray<id<ALNAdminUIResource>> *)adminUIResourcesForRuntime:(ALNAdminUIModuleRuntime *)runtime
                                                          error:(NSError **)error {
  (void)runtime;
  (void)error;
  return @[ [[ALNStorageAdminResource alloc] initWithRuntime:[ALNStorageModuleRuntime sharedRuntime]] ];
}

@end

@implementation ALNStorageModule

- (NSString *)moduleIdentifier {
  return @"storage";
}

- (BOOL)registerWithApplication:(ALNApplication *)application error:(NSError **)error {
  ALNStorageModuleRuntime *runtime = [ALNStorageModuleRuntime sharedRuntime];
  if (![runtime configureWithApplication:application error:error]) {
    return NO;
  }

  [application beginRouteGroupWithPrefix:runtime.prefix guardAction:@"requireStorageHTML" formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/"
                              name:@"storage_dashboard"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"dashboard"];
  [application registerRouteMethod:@"GET"
                              path:@"/collections/:collection"
                              name:@"storage_collection"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"collectionIndex"];
  [application registerRouteMethod:@"GET"
                              path:@"/collections/:collection/objects/:objectID"
                              name:@"storage_object"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"objectDetail"];
  [application registerRouteMethod:@"POST"
                              path:@"/collections/:collection/objects/:objectID/delete"
                              name:@"storage_object_delete_html"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"deleteObjectHTML"];
  [application registerRouteMethod:@"POST"
                              path:@"/collections/:collection/objects/:objectID/regenerate-variants"
                              name:@"storage_object_regenerate_variants_html"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"regenerateVariantsHTML"];
  [application endRouteGroup];

  [application beginRouteGroupWithPrefix:runtime.apiPrefix guardAction:nil formats:nil];
  [application registerRouteMethod:@"GET"
                              path:@"/collections"
                              name:@"storage_api_collections"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiCollections"];
  [application registerRouteMethod:@"GET"
                              path:@"/collections/:collection/objects"
                              name:@"storage_api_objects"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiObjects"];
  [application registerRouteMethod:@"GET"
                              path:@"/collections/:collection/objects/:objectID"
                              name:@"storage_api_object_detail"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiObjectDetail"];
  [application registerRouteMethod:@"POST"
                              path:@"/upload-sessions"
                              name:@"storage_api_upload_sessions"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiCreateUploadSession"];
  [application registerRouteMethod:@"POST"
                              path:@"/upload-sessions/:sessionID/upload"
                              name:@"storage_api_upload"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiUpload"];
  [application registerRouteMethod:@"POST"
                              path:@"/collections/:collection/objects/:objectID/download-token"
                              name:@"storage_api_download_token"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiIssueDownloadToken"];
  [application registerRouteMethod:@"GET"
                              path:@"/download/:token"
                              name:@"storage_api_download"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiDownload"];
  [application registerRouteMethod:@"POST"
                              path:@"/collections/:collection/objects/:objectID/delete"
                              name:@"storage_api_delete"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiDeleteObject"];
  [application registerRouteMethod:@"POST"
                              path:@"/collections/:collection/objects/:objectID/regenerate-variants"
                              name:@"storage_api_regenerate_variants"
                   controllerClass:[ALNStorageModuleController class]
                            action:@"apiRegenerateVariants"];
  [application endRouteGroup];

  NSArray *adminRoutes = @[
    @"storage_api_collections",
    @"storage_api_objects",
    @"storage_api_object_detail",
    @"storage_api_upload_sessions",
    @"storage_api_upload",
    @"storage_api_download_token",
    @"storage_api_delete",
    @"storage_api_regenerate_variants",
  ];
  for (NSString *routeName in adminRoutes) {
    [application configureRouteNamed:routeName
                       requestSchema:nil
                      responseSchema:nil
                             summary:@"Storage module API"
                         operationID:routeName
                                tags:@[ @"storage" ]
                      requiredScopes:nil
                       requiredRoles:@[ @"admin" ]
                     includeInOpenAPI:YES
                                error:NULL];
    [application configureAuthAssuranceForRouteNamed:routeName
                           minimumAuthAssuranceLevel:2
                     maximumAuthenticationAgeSeconds:0
                                          stepUpPath:SMStepUpPath([ALNAuthModuleRuntime sharedRuntime])
                                               error:NULL];
  }
  [application configureRouteNamed:@"storage_api_download"
                     requestSchema:nil
                    responseSchema:nil
                           summary:@"Storage download token route"
                       operationID:@"storage_api_download"
                              tags:@[ @"storage" ]
                    requiredScopes:nil
                     requiredRoles:nil
                   includeInOpenAPI:YES
                              error:NULL];
  return YES;
}

@end
