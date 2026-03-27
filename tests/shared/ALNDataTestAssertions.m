#import "ALNDataTestAssertions.h"

NSString *ALNNormalizedSQLForAssertion(NSString *sql) {
  if (![sql isKindOfClass:[NSString class]]) {
    return @"";
  }

  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  for (NSString *component in [sql
           componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
    if ([component length] == 0) {
      continue;
    }
    [parts addObject:component];
  }
  return [parts componentsJoinedByString:@" "];
}
