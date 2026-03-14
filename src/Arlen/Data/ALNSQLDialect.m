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
  return [NSString stringWithFormat:@"\"%@\"", value ?: @""];
}

NSString *ALNSQLDialectBracketQuoteIdentifier(NSString *value) {
  return [NSString stringWithFormat:@"[%@]", value ?: @""];
}
