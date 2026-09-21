#import "ALNMultipart.h"
#import "ALNPositiveInteger.h"
#include <string.h>
NSString *const ALNMultipartErrorDomain = @"Arlen.HTTP.Multipart.Error";
@interface ALNMultipartPart ()
@property(nonatomic, copy, readwrite) NSString *fieldName;
@property(nonatomic, copy, readwrite) NSString *originalFilename;
@property(nonatomic, copy, readwrite) NSString *contentType;
@property(nonatomic, copy, readwrite) NSData *data;
@end
@implementation ALNMultipartPart
- (NSUInteger)size { return [self.data length]; }
- (NSString *)text { return [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding]; }
@end
@implementation ALNUpload
- (BOOL)writeToFile:(NSString *)path error:(NSError **)error {
  return [self.data writeToFile:path options:NSDataWritingAtomic error:error];
}
@end

static NSString *Trim(NSString *s) {
  return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}
// Explicit parameter scanner: quoted semicolons and quoted-pair escapes are data.
static NSDictionary *Parameters(NSString *s, NSString **kind) {
  NSUInteger n = s.length, i = 0;
  while (i < n && [s characterAtIndex:i] != ';') i++;
  *kind = [Trim([s substringToIndex:i]) lowercaseString];
  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  while (i < n) {
    i++;
    while (i < n && ([s characterAtIndex:i] == ' ' || [s characterAtIndex:i] == '\t')) i++;
    NSUInteger start = i;
    while (i < n && [s characterAtIndex:i] != '=' && [s characterAtIndex:i] != ';') i++;
    if (i == n || [s characterAtIndex:i] != '=') return nil;
    NSString *key = [Trim([s substringWithRange:NSMakeRange(start, i-start)]) lowercaseString];
    if (!key.length || out[key]) return nil;
    i++;
    while (i < n && ([s characterAtIndex:i] == ' ' || [s characterAtIndex:i] == '\t')) i++;
    NSMutableString *value = [NSMutableString string];
    if (i < n && [s characterAtIndex:i] == '"') {
      i++;
      BOOL closed = NO;
      while (i < n) {
        unichar c = [s characterAtIndex:i++];
        if (c == '"') { closed = YES; break; }
        if (c == '\\') { if (i == n) return nil; c = [s characterAtIndex:i++]; }
        if (c < 32 || c == 127) return nil;
        [value appendFormat:@"%C", c];
      }
      if (!closed) return nil;
      while (i < n && ([s characterAtIndex:i] == ' ' || [s characterAtIndex:i] == '\t')) i++;
      if (i < n && [s characterAtIndex:i] != ';') return nil;
    } else {
      start = i;
      while (i < n && [s characterAtIndex:i] != ';') i++;
      [value appendString:Trim([s substringWithRange:NSMakeRange(start, i-start)])];
      if (!value.length) return nil;
    }
    out[key] = value;
  }
  return out;
}
static NSArray *Failure(NSError **error, ALNMultipartErrorCode code, NSString *message) {
  if (error) *error = [NSError errorWithDomain:ALNMultipartErrorDomain code:code
                                    userInfo:@{NSLocalizedDescriptionKey:message}];
  return nil;
}
static BOOL Match(NSData *body, NSUInteger offset, NSData *needle) {
  return offset <= body.length && needle.length <= body.length-offset &&
         memcmp((const char *)body.bytes+offset, needle.bytes, needle.length) == 0;
}
@implementation ALNMultipart
+ (NSDictionary *)defaultLimits {
  return @{ @"maxBodyBytes":@1048576, @"maxMultipartParts":@128,
            @"maxMultipartFieldBytes":@65536, @"maxMultipartFileBytes":@1048576,
            @"maxMultipartHeaderBytes":@16384 };
}
+ (NSArray *)parseBody:(NSData *)body contentType:(NSString *)contentType
                limits:(NSDictionary *)limits error:(NSError **)error {
  if (error) *error = nil;
  if (limits != nil && ![limits isKindOfClass:[NSDictionary class]])
    return Failure(error, ALNMultipartErrorLimitExceeded, @"Multipart limits must be a dictionary");
  NSMutableDictionary *policy = [[self defaultLimits] mutableCopy];
  for (NSString *key in policy.allKeys) {
    if (limits[key]) {
      NSNumber *value = ALNPositiveInteger(limits[key]);
      if (value == nil)
        return Failure(error, ALNMultipartErrorLimitExceeded,
                       [NSString stringWithFormat:@"requestLimits.%@ must be a positive integer in range", key]);
      policy[key] = value;
    }
  }
  if (body.length > [policy[@"maxBodyBytes"] unsignedLongLongValue])
    return Failure(error, ALNMultipartErrorLimitExceeded, @"Multipart request body limit exceeded");
  NSString *kind = nil;
  NSDictionary *params = Parameters(contentType, &kind);
  NSString *boundary = params[@"boundary"];
  NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
      @"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'()+_,-./:=? "];
  if (!params || ![kind isEqual:@"multipart/form-data"] || !boundary.length || boundary.length > 70 ||
      [boundary hasSuffix:@" "] || [boundary rangeOfCharacterFromSet:[allowed invertedSet]].location != NSNotFound)
    return Failure(error, ALNMultipartErrorMalformed, @"Invalid multipart boundary");
  NSData *marker = [[@"--" stringByAppendingString:boundary] dataUsingEncoding:NSASCIIStringEncoding];
  NSData *delimiter = [[@"\r\n--" stringByAppendingString:boundary] dataUsingEncoding:NSASCIIStringEncoding];
  NSData *crlf = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
  NSData *close = [@"--" dataUsingEncoding:NSASCIIStringEncoding];
  NSData *headerEnd = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
  if (!Match(body, 0, marker)) return Failure(error, ALNMultipartErrorMalformed, @"Missing initial multipart boundary");
  NSUInteger pos = marker.length;
  NSMutableArray *parts = [NSMutableArray array];
  while (YES) {
    if (Match(body, pos, close)) {
      pos += 2;
      if (pos == body.length || (Match(body, pos, crlf) && pos+2 == body.length)) return [parts copy];
      return Failure(error, ALNMultipartErrorMalformed, @"Unexpected bytes after multipart closing boundary");
    }
    if (!Match(body, pos, crlf)) return Failure(error, ALNMultipartErrorTruncated, @"Incomplete multipart delimiter");
    pos += 2;
    if (parts.count >= [policy[@"maxMultipartParts"] unsignedLongLongValue])
      return Failure(error, ALNMultipartErrorLimitExceeded, @"Multipart part count limit exceeded");
    NSUInteger headerLimit = [policy[@"maxMultipartHeaderBytes"] unsignedIntegerValue];
    NSUInteger searchLength = MIN(body.length-pos, headerLimit > NSUIntegerMax-4 ? headerLimit : headerLimit+4);
    NSRange end = [body rangeOfData:headerEnd options:0 range:NSMakeRange(pos, searchLength)];
    if (end.location == NSNotFound)
      return Failure(error, body.length-pos > headerLimit ? ALNMultipartErrorLimitExceeded : ALNMultipartErrorTruncated,
                     @"Multipart headers exceed limit or are incomplete");
    NSString *headers = [[NSString alloc] initWithBytes:(const char *)body.bytes+pos
                                               length:end.location-pos encoding:NSUTF8StringEncoding];
    if (!headers) return Failure(error, ALNMultipartErrorMalformed, @"Multipart headers must be UTF-8");
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *line in [headers componentsSeparatedByString:@"\r\n"]) {
      NSRange colon = [line rangeOfString:@":"];
      if (colon.location == NSNotFound || colon.location == 0)
        return Failure(error, ALNMultipartErrorMalformed, @"Invalid multipart header");
      NSString *name = [[line substringToIndex:colon.location] lowercaseString];
      NSCharacterSet *tokens = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-.^_`|~"];
      NSString *value = Trim([line substringFromIndex:colon.location+1]);
      if ([name rangeOfCharacterFromSet:tokens.invertedSet].location != NSNotFound || values[name] ||
          [value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound)
        return Failure(error, ALNMultipartErrorMalformed, @"Invalid or duplicate multipart header");
      values[name] = value;
    }
    NSString *disposition = nil;
    NSDictionary *attributes = Parameters(values[@"content-disposition"] ?: @"", &disposition);
    if (!attributes || ![disposition isEqual:@"form-data"] || ![attributes[@"name"] length] ||
        values[@"content-transfer-encoding"])
      return Failure(error, ALNMultipartErrorMalformed, @"Invalid multipart content disposition or transfer encoding");
    BOOL file = attributes[@"filename"] != nil;
    NSUInteger start = end.location+4;
    NSUInteger cursor = start;
    NSRange next = NSMakeRange(NSNotFound, 0);
    while (cursor < body.length) {
      next = [body rangeOfData:delimiter options:0 range:NSMakeRange(cursor, body.length-cursor)];
      if (next.location == NSNotFound) break;
      NSUInteger suffix = next.location+delimiter.length;
      if (Match(body, suffix, crlf) ||
          (Match(body, suffix, close) && (suffix+2 == body.length || Match(body, suffix+2, crlf)))) break;
      cursor = next.location+1;
      next.location = NSNotFound;
    }
    if (next.location == NSNotFound) return Failure(error, ALNMultipartErrorTruncated, @"Missing multipart closing boundary");
    NSUInteger length = next.location-start;
    if (length > [policy[file ? @"maxMultipartFileBytes" : @"maxMultipartFieldBytes"] unsignedLongLongValue])
      return Failure(error, ALNMultipartErrorLimitExceeded, file ? @"Multipart file limit exceeded" : @"Multipart field limit exceeded");
    ALNMultipartPart *part = file ? [[ALNUpload alloc] init] : [[ALNMultipartPart alloc] init];
    part.fieldName = attributes[@"name"];
    part.originalFilename = attributes[@"filename"];
    part.contentType = values[@"content-type"] ?: @"";
    part.data = [body subdataWithRange:NSMakeRange(start, length)];
    if (!file && part.text == nil) return Failure(error, ALNMultipartErrorMalformed, @"Multipart text fields must be UTF-8");
    [parts addObject:part];
    pos = next.location+delimiter.length;
  }
}
@end
