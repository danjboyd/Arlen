#ifndef ALN_POSTGRES_SQL_BUILDER_H
#define ALN_POSTGRES_SQL_BUILDER_H

#import <Foundation/Foundation.h>

#import "ALNSQLBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNPostgresSQLBuilder : ALNSQLBuilder

- (instancetype)onConflictDoNothing;
- (instancetype)onConflictColumns:(nullable NSArray<NSString *> *)columns
                doUpdateSetFields:(NSArray<NSString *> *)fields;
- (instancetype)onConflictColumns:(nullable NSArray<NSString *> *)columns
             doUpdateAssignments:(NSDictionary<NSString *, id> *)assignments;
- (instancetype)onConflictDoUpdateWhereExpression:(NSString *)expression
                                       parameters:(nullable NSArray *)parameters;

@end

NS_ASSUME_NONNULL_END

#endif
