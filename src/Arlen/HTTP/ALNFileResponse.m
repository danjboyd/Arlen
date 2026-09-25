#import "ALNFileResponseInternal.h"

#import <errno.h>
#import <limits.h>
#import <math.h>
#import <string.h>

#import "ALNMIMETypes.h"
#import "ALNRequest.h"
#import "ALNResponse.h"

NSString *const ALNFileResponseCacheControlOption = @"cacheControl";
NSString *const ALNFileResponseDownloadNameOption = @"downloadName";
NSString *const ALNFileResponseETagOption = @"etag";
NSString *const ALNFileResponseMIMETypesOption = @"mimeTypes";

static long ALNFileResponseMTimeNanoseconds(const struct stat *fileStat) {
#if defined(__linux__)
  return fileStat->st_mtim.tv_nsec;
#elif defined(__APPLE__)
  return fileStat->st_mtimespec.tv_nsec;
#else
  return 0;
#endif
}

static long ALNFileResponseCTimeNanoseconds(const struct stat *fileStat) {
#if defined(__linux__)
  return fileStat->st_ctim.tv_nsec;
#elif defined(__APPLE__)
  return fileStat->st_ctimespec.tv_nsec;
#else
  return 0;
#endif
}

// HTTP dates are locale-independent and have whole-second precision. Formatters
// are request-local because NSDateFormatter is mutable and requests run concurrently.
static NSDateFormatter *ALNFileResponseDateFormatter(NSString *format) {
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
  formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  formatter.dateFormat = format;
  formatter.lenient = NO;
  return formatter;
}

static NSString *ALNFileResponseHTTPDate(NSTimeInterval seconds) {
  return [ALNFileResponseDateFormatter(@"EEE, dd MMM yyyy HH:mm:ss 'GMT'")
      stringFromDate:[NSDate dateWithTimeIntervalSince1970:seconds]];
}

static NSDate *ALNFileResponseParseHTTPDate(NSString *value) {
  if ([value length] == 0) return nil;
  for (NSString *format in @[@"EEE, dd MMM yyyy HH:mm:ss 'GMT'",
                             @"EEEE, dd-MMM-yy HH:mm:ss 'GMT'",
                             @"EEE MMM d HH:mm:ss yyyy"]) {
    NSDateFormatter *formatter = ALNFileResponseDateFormatter(format);
    NSDate *date = [formatter dateFromString:value];
    // Round-trip validation rejects trailing garbage and normalized invalid dates.
    NSString *normalized = [value stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    if (date != nil && [[formatter stringFromDate:date] isEqualToString:normalized]) return date;
  }
  return nil;
}

static BOOL ALNFileResponseETagCharacter(unichar ch) {
  return ch == 0x21 || (ch >= 0x23 && ch <= 0x7e) || (ch >= 0x80 && ch <= 0xff);
}

// Accepts `"opaque"`, `W/"opaque"`, or a bare opaque value that is quoted here.
static NSString *ALNFileResponseNormalizedETag(id value) {
  if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
    return nil;
  }
  NSString *tag = value;
  BOOL weak = [tag hasPrefix:@"W/"];
  NSString *opaque = weak ? [tag substringFromIndex:2] : tag;
  if ([opaque length] >= 2 && [opaque hasPrefix:@"\""] && [opaque hasSuffix:@"\""]) {
    opaque = [opaque substringWithRange:NSMakeRange(1, [opaque length] - 2)];
  } else if (weak) {
    return nil;
  }
  if ([opaque length] == 0) {
    return nil;
  }
  for (NSUInteger idx = 0; idx < [opaque length]; idx++) {
    if (!ALNFileResponseETagCharacter([opaque characterAtIndex:idx])) {
      return nil;
    }
  }
  return [NSString stringWithFormat:@"%@\"%@\"", weak ? @"W/" : @"", opaque];
}

// Parse quoted tags explicitly: commas are legal inside an opaque entity tag.
static BOOL ALNFileResponseETagMatches(NSString *field, NSString *etag, BOOL weak) {
  NSString *value = [field stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if ([value isEqualToString:@"*"]) return YES;
  NSString *target = [etag hasPrefix:@"W/"] ? [etag substringFromIndex:2] : etag;
  NSUInteger cursor = 0;
  BOOL matched = NO;
  while (cursor < [value length]) {
    while (cursor < [value length] && ([value characterAtIndex:cursor] == ' ' ||
                                      [value characterAtIndex:cursor] == '\t')) cursor++;
    BOOL tagWeak = NO;
    if (cursor + 2 <= [value length] && [[value substringWithRange:NSMakeRange(cursor, 2)] isEqualToString:@"W/"]) {
      tagWeak = YES;
      cursor += 2;
    }
    NSUInteger start = cursor;
    if (cursor >= [value length] || [value characterAtIndex:cursor++] != '"') return NO;
    while (cursor < [value length] && [value characterAtIndex:cursor] != '"') {
      unichar ch = [value characterAtIndex:cursor++];
      if (ch < 0x21 || ch == 0x7f || ch > 0xff) return NO;
    }
    if (cursor >= [value length]) return NO;
    cursor++;
    if ((weak || (!tagWeak && ![etag hasPrefix:@"W/"])) &&
        [[value substringWithRange:NSMakeRange(start, cursor - start)] isEqualToString:target]) matched = YES;
    while (cursor < [value length] && ([value characterAtIndex:cursor] == ' ' ||
                                      [value characterAtIndex:cursor] == '\t')) cursor++;
    if (cursor == [value length]) return matched;
    if ([value characterAtIndex:cursor++] != ',' || cursor == [value length]) return NO;
  }
  return NO;
}

static BOOL ALNFileResponseDecimal(NSString *value, unsigned long long *result) {
  if ([value length] == 0) return NO;
  unsigned long long number = 0;
  for (NSUInteger idx = 0; idx < [value length]; idx++) {
    unichar ch = [value characterAtIndex:idx];
    if (ch < '0' || ch > '9' || number > (ULLONG_MAX - (ch - '0')) / 10) return NO;
    number = number * 10 + (ch - '0');
  }
  *result = number;
  return YES;
}

// 0: ignore malformed/unsupported range; 1: selected range; -1: unsatisfiable.
static NSInteger ALNFileResponseByteRange(NSString *field, unsigned long long size,
                                          unsigned long long *offset, unsigned long long *length) {
  if (![field hasPrefix:@"bytes="]) return 0;
  NSString *value = [field substringFromIndex:6];
  if ([value containsString:@","]) return 0; // Multipart ranges are deliberately unsupported.
  NSArray *parts = [value componentsSeparatedByString:@"-"];
  if ([parts count] != 2) return 0;
  unsigned long long first = 0, last = 0;
  if ([parts[0] length] == 0) {
    if (!ALNFileResponseDecimal(parts[1], &last)) return 0;
    if (last == 0 || size == 0) return -1;
    *length = MIN(last, size);
    *offset = size - *length;
    return 1;
  }
  if (!ALNFileResponseDecimal(parts[0], &first)) return 0;
  if ([parts[1] length] != 0) {
    if (!ALNFileResponseDecimal(parts[1], &last) || last < first) return 0;
  } else {
    last = size == 0 ? 0 : size - 1;
  }
  if (first >= size) return -1;
  *offset = first;
  *length = MIN(last, size - 1) - first + 1;
  return 1;
}

static BOOL ALNFileResponseHeaderValueIsSafe(NSString *value) {
  for (NSUInteger idx = 0; idx < [value length]; idx++) {
    unichar ch = [value characterAtIndex:idx];
    if ((ch < 0x20 && ch != '\t') || ch == 0x7f) {
      return NO;
    }
  }
  return YES;
}

// RFC 6266: an ASCII quoted fallback plus an RFC 5987 UTF-8 filename*.
static NSString *ALNFileResponseContentDisposition(NSString *name) {
  NSString *baseName = [[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] lastPathComponent];
  if ([baseName length] == 0 || [baseName isEqualToString:@"/"]) {
    return nil;
  }
  NSMutableString *fallback = [NSMutableString string];
  NSMutableString *encoded = [NSMutableString string];
  for (NSUInteger idx = 0; idx < [baseName length]; idx++) {
    unichar ch = [baseName characterAtIndex:idx];
    BOOL printable = ch >= 0x20 && ch < 0x7f;
    [fallback appendFormat:@"%C", (unichar)((printable && ch != '"' && ch != '\\') ? ch : '_')];
  }
  NSData *utf8 = [baseName dataUsingEncoding:NSUTF8StringEncoding];
  const unsigned char *bytes = [utf8 bytes];
  for (NSUInteger idx = 0; idx < [utf8 length]; idx++) {
    unsigned char byte = bytes[idx];
    BOOL attrChar = (byte >= 'A' && byte <= 'Z') || (byte >= 'a' && byte <= 'z') ||
                    (byte >= '0' && byte <= '9') || strchr("!#$&+-.^_`|~", byte) != NULL;
    if (attrChar && byte != 0) {
      [encoded appendFormat:@"%c", byte];
    } else {
      [encoded appendFormat:@"%%%02X", byte];
    }
  }
  return [NSString stringWithFormat:@"attachment; filename=\"%@\"; filename*=UTF-8''%@",
                                    fallback, encoded];
}

// Parsed request header names are lowercase. Absent fields must stay nil: an
// empty If-Match is still a precondition, unlike -headerValueForName:'s "".
static NSString *ALNFileResponseRequestHeader(ALNRequest *request, NSString *name) {
  id value = request.headers[name];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

static void ALNFileResponseCommitNotFound(ALNResponse *response) {
  [response clearBody];
  [response removeHeaderForName:@"Content-Range"];
  [response removeHeaderForName:@"Content-Length"];
  response.statusCode = 404;
  [response setTextBody:@"not found\n"];
  [response setHeader:@"Content-Type" value:@"text/plain; charset=utf-8"];
  response.committed = YES;
}

void ALNFileResponseApplyStat(ALNResponse *response,
                              ALNRequest *request,
                              NSString *filePath,
                              const struct stat *fileStat,
                              NSString *contentType,
                              NSDictionary *options) {
  NSDictionary *resolvedOptions = [options isKindOfClass:[NSDictionary class]] ? options : @{};
  [response clearBody];
  [response removeHeaderForName:@"Content-Range"];
  [response removeHeaderForName:@"Content-Length"];

  unsigned long long size = (unsigned long long)fileStat->st_size;
  NSTimeInterval now = floor([[NSDate date] timeIntervalSince1970]);
  NSTimeInterval modified = MIN((NSTimeInterval)fileStat->st_mtime, now);
  NSString *customETag = ALNFileResponseNormalizedETag(resolvedOptions[ALNFileResponseETagOption]);
  NSString *etag = customETag ?: [NSString stringWithFormat:@"W/\"%llx-%llx-%llx-%llx-%lx-%llx-%lx\"",
      (unsigned long long)fileStat->st_dev, (unsigned long long)fileStat->st_ino, size,
      (unsigned long long)fileStat->st_mtime, (unsigned long)ALNFileResponseMTimeNanoseconds(fileStat),
      (unsigned long long)fileStat->st_ctime, (unsigned long)ALNFileResponseCTimeNanoseconds(fileStat)];
  NSString *resolvedContentType = ([contentType length] > 0 && ALNFileResponseHeaderValueIsSafe(contentType))
                                      ? contentType
                                      : [ALNMIMETypes contentTypeForFilePath:filePath
                                                                   overrides:resolvedOptions[ALNFileResponseMIMETypesOption]];

  response.statusCode = 200;
  [response setHeader:@"Content-Type" value:resolvedContentType];
  [response setHeader:@"ETag" value:etag];
  [response setHeader:@"Last-Modified" value:ALNFileResponseHTTPDate(modified)];
  [response setHeader:@"Date" value:ALNFileResponseHTTPDate(now)];
  [response setHeader:@"Accept-Ranges" value:@"bytes"];
  NSString *cacheControl = resolvedOptions[ALNFileResponseCacheControlOption];
  if ([cacheControl isKindOfClass:[NSString class]] && [cacheControl length] > 0 &&
      ALNFileResponseHeaderValueIsSafe(cacheControl)) {
    [response setHeader:@"Cache-Control" value:cacheControl];
  }
  NSString *downloadName = resolvedOptions[ALNFileResponseDownloadNameOption];
  NSString *disposition = [downloadName isKindOfClass:[NSString class]]
                              ? ALNFileResponseContentDisposition(downloadName)
                              : nil;
  if ([disposition length] > 0) {
    [response setHeader:@"Content-Disposition" value:disposition];
  }

  NSString *ifMatch = ALNFileResponseRequestHeader(request, @"if-match");
  NSString *ifNoneMatch = ALNFileResponseRequestHeader(request, @"if-none-match");
  NSDate *unmodifiedSince = ALNFileResponseParseHTTPDate(ALNFileResponseRequestHeader(request, @"if-unmodified-since"));
  NSDate *modifiedSince = ALNFileResponseParseHTTPDate(ALNFileResponseRequestHeader(request, @"if-modified-since"));
  if ((ifMatch != nil && !ALNFileResponseETagMatches(ifMatch, etag, NO)) ||
      (ifMatch == nil && unmodifiedSince != nil && modified > [unmodifiedSince timeIntervalSince1970])) {
    response.statusCode = 412;
  } else if ((ifNoneMatch != nil && ALNFileResponseETagMatches(ifNoneMatch, etag, YES)) ||
             (ifNoneMatch == nil && modifiedSince != nil && modified <= [modifiedSince timeIntervalSince1970])) {
    response.statusCode = 304;
  }
  if (response.statusCode != 200) {
    response.committed = YES;
    return;
  }

  unsigned long long offset = 0, length = size;
  NSString *range = ALNFileResponseRequestHeader(request, @"range");
  NSString *ifRange = ALNFileResponseRequestHeader(request, @"if-range");
  BOOL rangeAllowed = YES;
  if (ifRange != nil) {
    NSString *trimmedIfRange = [ifRange stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmedIfRange hasPrefix:@"\""] || [trimmedIfRange hasPrefix:@"W/"]) {
      // If-Range uses strong comparison; only a caller-supplied strong tag can match.
      rangeAllowed = ![etag hasPrefix:@"W/"] && [trimmedIfRange isEqualToString:etag];
    } else {
      // A date is strong only when sufficiently older than the response Date.
      NSDate *rangeDate = ALNFileResponseParseHTTPDate(ifRange);
      rangeAllowed = rangeDate != nil && [rangeDate timeIntervalSince1970] == modified &&
                     now - modified >= 60;
    }
  }
  if ([request.method isEqualToString:@"GET"] && range != nil && rangeAllowed) {
    NSInteger selection = ALNFileResponseByteRange(range, size, &offset, &length);
    if (selection < 0) {
      response.statusCode = 416;
      [response setHeader:@"Content-Range" value:[NSString stringWithFormat:@"bytes */%llu", size]];
      response.committed = YES;
      return;
    }
    if (selection > 0) {
      response.statusCode = 206;
      [response setHeader:@"Content-Range" value:[NSString stringWithFormat:@"bytes %llu-%llu/%llu",
          offset, offset + length - 1, size]];
    }
  }
  response.fileBodyPath = filePath;
  response.fileBodyLength = length;
  response.fileBodyOffset = offset;
  response.fileBodyFullLength = size;
  response.fileBodyDevice = (unsigned long long)fileStat->st_dev;
  response.fileBodyInode = (unsigned long long)fileStat->st_ino;
  response.fileBodyMTimeSeconds = (long long)fileStat->st_mtime;
  response.fileBodyMTimeNanoseconds = ALNFileResponseMTimeNanoseconds(fileStat);
  response.committed = YES;
}

@implementation ALNFileResponse

+ (BOOL)prepareResponse:(ALNResponse *)response
             forRequest:(ALNRequest *)request
               filePath:(NSString *)filePath
            contentType:(NSString *)contentType
                options:(NSDictionary *)options {
  if (response == nil) {
    return NO;
  }
  const char *fsPath = ([filePath isKindOfClass:[NSString class]] && [filePath length] > 0)
                           ? [filePath UTF8String]
                           : NULL;
  struct stat fileStat;
  int rc = -1;
  if (fsPath != NULL) {
    do {
      rc = stat(fsPath, &fileStat);
    } while (rc != 0 && errno == EINTR);
  }
  if (rc != 0 || !S_ISREG(fileStat.st_mode)) {
    ALNFileResponseCommitNotFound(response);
    return NO;
  }
  ALNFileResponseApplyStat(response, request, filePath, &fileStat, contentType, options);
  return YES;
}

@end
