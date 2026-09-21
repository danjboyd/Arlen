#ifndef ALN_POSITIVE_INTEGER_H
#define ALN_POSITIVE_INTEGER_H

#import <Foundation/Foundation.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>

// Internal config/parser seam: old-style plists represent bare integers as strings.
// Reject partial conversions, fractions and overflow instead of truncating limits.
static inline NSNumber *ALNPositiveInteger(id value) {
  NSString *text = nil;
  if ([value isKindOfClass:[NSNumber class]]) {
    text = [value stringValue];
  } else if ([value isKindOfClass:[NSString class]]) {
    text = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  if (text.length == 0 ||
      [text rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) {
    return nil;
  }
  errno = 0;
  unsigned long long parsed = strtoull(text.UTF8String, NULL, 10);
  if (errno == ERANGE || parsed == 0 || parsed > LLONG_MAX || parsed > NSUIntegerMax) {
    return nil;
  }
  return @(parsed);
}

#endif
