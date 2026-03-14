#import "ALNMSSQLSQLBuilder.h"

#import "ALNMSSQLDialect.h"

@implementation ALNMSSQLSQLBuilder

- (NSDictionary *)buildForMSSQL:(NSError **)error {
  return [self buildWithDialect:[ALNMSSQLDialect sharedDialect] error:error];
}

- (NSString *)buildMSSQLSQL:(NSError **)error {
  return [self buildSQLWithDialect:[ALNMSSQLDialect sharedDialect] error:error];
}

- (NSArray *)buildMSSQLParameters:(NSError **)error {
  return [self buildParametersWithDialect:[ALNMSSQLDialect sharedDialect] error:error];
}

@end
