#ifndef ALN_MSSQL_SQL_BUILDER_H
#define ALN_MSSQL_SQL_BUILDER_H

#import <Foundation/Foundation.h>

#import "ALNSQLBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNMSSQLSQLBuilder : ALNSQLBuilder

- (nullable NSDictionary *)buildForMSSQL:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)buildMSSQLSQL:(NSError *_Nullable *_Nullable)error;
- (NSArray *)buildMSSQLParameters:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
