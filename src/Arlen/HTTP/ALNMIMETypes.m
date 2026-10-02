#import "ALNMIMETypes.h"

static NSString *const ALNMIMETypeFallback = @"application/octet-stream";

static NSString *ALNNormalizedMIMEExtension(NSString *extension) {
  if (![extension isKindOfClass:[NSString class]]) {
    return @"";
  }
  NSString *normalized = [[extension stringByTrimmingCharactersInSet:
                                         [NSCharacterSet whitespaceCharacterSet]] lowercaseString];
  while ([normalized hasPrefix:@"."]) {
    normalized = [normalized substringFromIndex:1];
  }
  return normalized;
}

// Header values come from app config, so reject anything that could split headers.
static BOOL ALNMIMETypeValueIsValid(id value) {
  if (![value isKindOfClass:[NSString class]] || [(NSString *)value length] == 0) {
    return NO;
  }
  NSString *string = value;
  for (NSUInteger idx = 0; idx < [string length]; idx++) {
    unichar ch = [string characterAtIndex:idx];
    if (ch < 0x20 || ch == 0x7f || ch > 0x7e) {
      return NO;
    }
  }
  return [string containsString:@"/"];
}

@implementation ALNMIMETypes

+ (NSDictionary<NSString *, NSString *> *)defaultTypes {
  static NSDictionary *types = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    types = @{
      // Text and application documents.
      @"html" : @"text/html; charset=utf-8",
      @"htm" : @"text/html; charset=utf-8",
      @"css" : @"text/css; charset=utf-8",
      @"js" : @"application/javascript; charset=utf-8",
      @"mjs" : @"application/javascript; charset=utf-8",
      @"json" : @"application/json; charset=utf-8",
      @"map" : @"application/json; charset=utf-8",
      @"webmanifest" : @"application/manifest+json; charset=utf-8",
      @"txt" : @"text/plain; charset=utf-8",
      @"csv" : @"text/csv; charset=utf-8",
      @"xml" : @"application/xml; charset=utf-8",
      @"pdf" : @"application/pdf",
      @"wasm" : @"application/wasm",
      // Images.
      @"svg" : @"image/svg+xml",
      @"png" : @"image/png",
      @"jpg" : @"image/jpeg",
      @"jpeg" : @"image/jpeg",
      @"gif" : @"image/gif",
      @"ico" : @"image/x-icon",
      @"webp" : @"image/webp",
      @"avif" : @"image/avif",
      @"heic" : @"image/heic",
      // Fonts.
      @"woff" : @"font/woff",
      @"woff2" : @"font/woff2",
      // Audio.
      @"mp3" : @"audio/mpeg",
      @"m4a" : @"audio/mp4",
      @"aac" : @"audio/aac",
      @"ogg" : @"audio/ogg",
      @"oga" : @"audio/ogg",
      @"opus" : @"audio/ogg",
      @"wav" : @"audio/wav",
      @"weba" : @"audio/webm",
      @"flac" : @"audio/flac",
      // Video.
      @"mp4" : @"video/mp4",
      @"m4v" : @"video/mp4",
      @"webm" : @"video/webm",
      @"mov" : @"video/quicktime",
    };
  });
  return types;
}

+ (NSString *)typeForExtension:(NSString *)extension {
  return [self typeForExtension:extension overrides:nil];
}

+ (NSString *)typeForExtension:(NSString *)extension overrides:(NSDictionary *)overrides {
  NSString *normalized = ALNNormalizedMIMEExtension(extension);
  if ([normalized length] == 0) {
    return nil;
  }
  if ([overrides isKindOfClass:[NSDictionary class]]) {
    for (id key in overrides) {
      if ([ALNNormalizedMIMEExtension(key) isEqualToString:normalized] &&
          ALNMIMETypeValueIsValid(overrides[key])) {
        return overrides[key];
      }
    }
  }
  return [self defaultTypes][normalized];
}

+ (NSString *)contentTypeForFilePath:(NSString *)filePath {
  return [self contentTypeForFilePath:filePath overrides:nil];
}

+ (NSString *)contentTypeForFilePath:(NSString *)filePath overrides:(NSDictionary *)overrides {
  NSString *extension = [filePath isKindOfClass:[NSString class]] ? [filePath pathExtension] : @"";
  return [self typeForExtension:extension overrides:overrides] ?: ALNMIMETypeFallback;
}

@end
