#import "ALNPercentDecoding.h"

#include <stdint.h>
#include <string.h>

static int ALNPercentHexDigit(unsigned char byte) {
  if (byte >= '0' && byte <= '9') return byte - '0';
  if (byte >= 'a' && byte <= 'f') return byte - 'a' + 10;
  if (byte >= 'A' && byte <= 'F') return byte - 'A' + 10;
  return -1;
}

static BOOL ALNPercentBytesAreStrictUTF8(const unsigned char *bytes, NSUInteger length) {
  NSUInteger index = 0;
  while (index < length) {
    unsigned char lead = bytes[index];
    if (lead < 0x80) {
      index++;
      continue;
    }
    NSUInteger continuationCount = 0;
    uint32_t codePoint = 0;
    uint32_t minimum = 0;
    if (lead >= 0xC2 && lead <= 0xDF) {
      continuationCount = 1;
      codePoint = lead & 0x1F;
      minimum = 0x80;
    } else if (lead >= 0xE0 && lead <= 0xEF) {
      continuationCount = 2;
      codePoint = lead & 0x0F;
      minimum = 0x800;
    } else if (lead >= 0xF0 && lead <= 0xF4) {
      continuationCount = 3;
      codePoint = lead & 0x07;
      minimum = 0x10000;
    } else {
      return NO;
    }
    if (length - index <= continuationCount) return NO;
    for (NSUInteger offset = 1; offset <= continuationCount; offset++) {
      unsigned char next = bytes[index + offset];
      if ((next & 0xC0) != 0x80) return NO;
      codePoint = (codePoint << 6) | (next & 0x3F);
    }
    if (codePoint < minimum || codePoint > 0x10FFFF ||
        (codePoint >= 0xD800 && codePoint <= 0xDFFF)) return NO;
    index += continuationCount + 1;
  }
  return YES;
}

NSString *ALNPercentDecodedString(NSString *value, BOOL plusAsSpace) {
  if (![value isKindOfClass:[NSString class]]) return nil;
  NSString *normalized = plusAsSpace ? [value stringByReplacingOccurrencesOfString:@"+" withString:@" "] : value;
  NSData *encoded = [normalized dataUsingEncoding:NSUTF8StringEncoding];
  if (encoded == nil) return nil;
  const unsigned char *bytes = encoded.bytes;
  NSUInteger length = encoded.length;
  if ([normalized rangeOfString:@"%"].location == NSNotFound) {
    if ((length > 0 && memchr(bytes, 0, length) != NULL) ||
        !ALNPercentBytesAreStrictUTF8(bytes, length)) return nil;
    return normalized;
  }
  NSMutableData *decoded = [NSMutableData dataWithCapacity:length];
  for (NSUInteger index = 0; index < length; index++) {
    unsigned char byte = bytes[index];
    if (byte == '%') {
      if (length - index < 3) return nil;
      int high = ALNPercentHexDigit(bytes[index + 1]);
      int low = ALNPercentHexDigit(bytes[index + 2]);
      if (high < 0 || low < 0) return nil;
      byte = (unsigned char)((high << 4) | low);
      index += 2;
    }
    if (byte == 0) return nil;
    [decoded appendBytes:&byte length:1];
  }
  if (!ALNPercentBytesAreStrictUTF8(decoded.bytes, decoded.length)) return nil;
  return [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
}
