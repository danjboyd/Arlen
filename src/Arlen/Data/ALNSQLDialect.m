#import "ALNSQLDialect.h"

BOOL ALNSQLDialectIdentifierIsSafe(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
    return NO;
  }
  NSCharacterSet *allowed =
      [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
  if ([[value stringByTrimmingCharactersInSet:allowed] length] > 0) {
    return NO;
  }
  unichar first = [value characterAtIndex:0];
  return ([[NSCharacterSet letterCharacterSet] characterIsMember:first] || first == '_');
}

NSString *ALNSQLDialectDoubleQuoteIdentifier(NSString *value) {
  return [NSString stringWithFormat:@"\"%@\"", [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""] ?: @""];
}

NSString *ALNSQLDialectBracketQuoteIdentifier(NSString *value) {
  return [NSString stringWithFormat:@"[%@]", [value stringByReplacingOccurrencesOfString:@"]" withString:@"]]"] ?: @""];
}

BOOL ALNSQLDialectIdentifierComponentIsValid(NSString *value) {
  if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
  for (NSUInteger i = 0; i < value.length; i++) {
    if ([value characterAtIndex:i] == 0) return NO;
  }
  return YES;
}

NSString *ALNSQLDialectIdentifierComponent(NSString *value) {
  if (!ALNSQLDialectIdentifierComponentIsValid(value)) return @"";
  return ALNSQLDialectIdentifierIsSafe(value) ? value : ALNSQLDialectDoubleQuoteIdentifier(value);
}

NSArray<NSString *> *ALNSQLDialectIdentifierComponents(NSString *value) {
  if (!ALNSQLDialectIdentifierComponentIsValid(value)) return nil;
  NSMutableArray *parts = [NSMutableArray array];
  NSUInteger i = 0;
  while (i < value.length) {
    NSMutableString *part = [NSMutableString string];
    if ([value characterAtIndex:i] == '"') {
      i++;
      BOOL closed = NO;
      while (i < value.length) {
        unichar c = [value characterAtIndex:i++];
        if (c == '"') {
          if (i < value.length && [value characterAtIndex:i] == '"') {
            i++;
          } else {
            closed = YES;
            break;
          }
        }
        [part appendFormat:@"%C", c];
      }
      if (!closed || !ALNSQLDialectIdentifierComponentIsValid(part)) return nil;
    } else {
      NSUInteger start = i;
      while (i < value.length && [value characterAtIndex:i] != '.') i++;
      [part appendString:[value substringWithRange:NSMakeRange(start, i - start)]];
      if (!ALNSQLDialectIdentifierIsSafe(part)) return nil;
    }
    [parts addObject:part];
    if (i == value.length) break;
    if ([value characterAtIndex:i++] != '.' || i == value.length) return nil;
  }
  return parts;
}
