#ifndef ALN_SQL_DIALECT_H
#define ALN_SQL_DIALECT_H

#import <Foundation/Foundation.h>

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

// Physical components are descriptor data, not SQL text. Empty/NUL names are invalid.
FOUNDATION_EXPORT BOOL ALNSQLDialectIdentifierComponentIsValid(NSString *value);
// Encode one physical component for the builder; ordinary names retain their spelling.
FOUNDATION_EXPORT NSString *ALNSQLDialectIdentifierComponent(NSString *value);
// Parse only dot-separated ordinary or SQL double-quoted components, never expressions.
FOUNDATION_EXPORT NSArray<NSString *> *_Nullable ALNSQLDialectIdentifierComponents(NSString *value);
FOUNDATION_EXPORT BOOL ALNSQLDialectIdentifierIsSafe(NSString *value);
FOUNDATION_EXPORT NSString *ALNSQLDialectDoubleQuoteIdentifier(NSString *value);
FOUNDATION_EXPORT NSString *ALNSQLDialectBracketQuoteIdentifier(NSString *value);

NS_ASSUME_NONNULL_END

#endif
