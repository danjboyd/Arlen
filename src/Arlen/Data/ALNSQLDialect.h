#ifndef ALN_SQL_DIALECT_H
#define ALN_SQL_DIALECT_H

#import <Foundation/Foundation.h>
#import "../ALNExports.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNSQLBuilder;

@protocol ALNSQLDialect <NSObject>

- (NSString *)dialectName;
- (NSDictionary<NSString *, id> *)capabilityMetadata;
- (nullable NSDictionary *)compileBuilder:(ALNSQLBuilder *)builder
                                    error:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)migrationStateTableCreateSQLForTableName:(NSString *)tableName
                                                          error:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)migrationVersionsSelectSQLForTableName:(NSString *)tableName
                                                        error:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)migrationVersionInsertSQLForTableName:(NSString *)tableName
                                                       error:(NSError *_Nullable *_Nullable)error;

@end

ALN_EXPORT BOOL ALNSQLDialectIdentifierIsSafe(NSString *value);
ALN_EXPORT NSString *ALNSQLDialectDoubleQuoteIdentifier(NSString *value);
ALN_EXPORT NSString *ALNSQLDialectBracketQuoteIdentifier(NSString *value);

NS_ASSUME_NONNULL_END

#endif
