#ifndef ALN_SQL_LEXICAL_H
#define ALN_SQL_LEXICAL_H

#import <Foundation/Foundation.h>

// Preserve UTF-16 offsets while hiding quoted data from placeholder/keyword scans.
// Input is compiler SQL or an explicitly trusted expression, not an SQL validator.
static inline NSString *ALNSQLMaskQuotedText(NSString *sql, BOOL brackets) {
  NSMutableString *masked = [sql mutableCopy];
  unichar delimiter = 0;
  for (NSUInteger i = 0; i < sql.length; i++) {
    unichar c = [sql characterAtIndex:i];
    if (delimiter == 0) {
      if (c == '\'' || c == '"' || (brackets && c == '[')) {
        delimiter = c == '[' ? ']' : c;
      } else {
        continue;
      }
    } else if (c == delimiter) {
      if (i + 1 < sql.length && [sql characterAtIndex:i + 1] == delimiter) {
        [masked replaceCharactersInRange:NSMakeRange(i++, 1) withString:@" "];
      } else {
        delimiter = 0;
      }
    }
    [masked replaceCharactersInRange:NSMakeRange(i, 1) withString:@" "];
  }
  return masked;
}

#endif
