#ifndef ALN_SQL_BUILDER_H
#define ALN_SQL_BUILDER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNSQLBuilderErrorDomain;

@class ALNSQLBuilder;

typedef void (^ALNSQLBuilderGroupBlock)(ALNSQLBuilder *groupBuilder);

typedef NS_ENUM(NSInteger, ALNSQLBuilderErrorCode) {
  ALNSQLBuilderErrorInvalidArgument = 1,
  ALNSQLBuilderErrorInvalidIdentifier = 2,
  ALNSQLBuilderErrorUnsupportedOperator = 3,
  ALNSQLBuilderErrorCompileFailed = 4,
};

typedef NS_ENUM(NSInteger, ALNSQLBuilderKind) {
  ALNSQLBuilderKindSelect = 1,
  ALNSQLBuilderKindInsert = 2,
  ALNSQLBuilderKindUpdate = 3,
  ALNSQLBuilderKindDelete = 4,
};

@interface ALNSQLBuilder : NSObject

@property(nonatomic, assign, readonly) ALNSQLBuilderKind kind;
@property(nonatomic, copy, readonly) NSString *tableName;

+ (instancetype)selectFrom:(NSString *)tableName
                   columns:(nullable NSArray<NSString *> *)columns;
+ (instancetype)selectFrom:(NSString *)tableName
                     alias:(nullable NSString *)alias
                   columns:(nullable NSArray<NSString *> *)columns;
+ (instancetype)insertInto:(NSString *)tableName
                    values:(NSDictionary<NSString *, id> *)values;
+ (instancetype)updateTable:(NSString *)tableName
                     values:(NSDictionary<NSString *, id> *)values;
+ (instancetype)deleteFrom:(NSString *)tableName;

- (instancetype)fromAlias:(NSString *)alias;

- (instancetype)selectExpression:(NSString *)expression
                           alias:(nullable NSString *)alias;
- (instancetype)selectExpression:(NSString *)expression
                           alias:(nullable NSString *)alias
                      parameters:(nullable NSArray *)parameters;
- (instancetype)selectExpression:(NSString *)expression
                           alias:(nullable NSString *)alias
              identifierBindings:
                  (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                      parameters:(nullable NSArray *)parameters;

- (instancetype)whereField:(NSString *)field equals:(nullable id)value;
- (instancetype)whereField:(NSString *)field
                  operator:(NSString *)operatorName
                     value:(nullable id)value;
- (instancetype)whereExistsSubquery:(ALNSQLBuilder *)subquery;
- (instancetype)whereNotExistsSubquery:(ALNSQLBuilder *)subquery;
- (instancetype)whereField:(NSString *)field
                  operator:(NSString *)operatorName
               anySubquery:(ALNSQLBuilder *)subquery;
- (instancetype)whereField:(NSString *)field
                  operator:(NSString *)operatorName
               allSubquery:(ALNSQLBuilder *)subquery;
- (instancetype)whereExpression:(NSString *)expression
                     parameters:(nullable NSArray *)parameters;
- (instancetype)whereExpression:(NSString *)expression
             identifierBindings:
                 (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                     parameters:(nullable NSArray *)parameters;
- (instancetype)whereFieldIn:(NSString *)field
                      values:(NSArray *)values;
- (instancetype)whereFieldNotIn:(NSString *)field
                          values:(NSArray *)values;
- (instancetype)whereField:(NSString *)field
              betweenLower:(nullable id)lower
                     upper:(nullable id)upper;
- (instancetype)whereField:(NSString *)field
           notBetweenLower:(nullable id)lower
                     upper:(nullable id)upper;
- (instancetype)whereField:(NSString *)field
                inSubquery:(ALNSQLBuilder *)subquery;
- (instancetype)whereField:(NSString *)field
             notInSubquery:(ALNSQLBuilder *)subquery;
- (instancetype)whereAnyGroup:(ALNSQLBuilderGroupBlock)groupBlock;
- (instancetype)whereAllGroup:(ALNSQLBuilderGroupBlock)groupBlock;

- (instancetype)joinTable:(NSString *)tableName
                    alias:(nullable NSString *)alias
              onLeftField:(NSString *)leftField
                 operator:(NSString *)operatorName
             onRightField:(NSString *)rightField;
- (instancetype)leftJoinTable:(NSString *)tableName
                        alias:(nullable NSString *)alias
                  onLeftField:(NSString *)leftField
                     operator:(NSString *)operatorName
                 onRightField:(NSString *)rightField;
- (instancetype)rightJoinTable:(NSString *)tableName
                         alias:(nullable NSString *)alias
                   onLeftField:(NSString *)leftField
                      operator:(NSString *)operatorName
                  onRightField:(NSString *)rightField;
- (instancetype)fullJoinTable:(NSString *)tableName
                         alias:(nullable NSString *)alias
                   onLeftField:(NSString *)leftField
                      operator:(NSString *)operatorName
                  onRightField:(NSString *)rightField;
- (instancetype)crossJoinTable:(NSString *)tableName
                         alias:(nullable NSString *)alias;
- (instancetype)joinTable:(NSString *)tableName
                    alias:(nullable NSString *)alias
               usingFields:(NSArray<NSString *> *)fields;
- (instancetype)leftJoinTable:(NSString *)tableName
                        alias:(nullable NSString *)alias
                   usingFields:(NSArray<NSString *> *)fields;
- (instancetype)rightJoinTable:(NSString *)tableName
                         alias:(nullable NSString *)alias
                    usingFields:(NSArray<NSString *> *)fields;
- (instancetype)fullJoinTable:(NSString *)tableName
                         alias:(nullable NSString *)alias
                    usingFields:(NSArray<NSString *> *)fields;
- (instancetype)joinSubquery:(ALNSQLBuilder *)subquery
                       alias:(NSString *)alias
                onExpression:(NSString *)expression
                  parameters:(nullable NSArray *)parameters;
- (instancetype)joinSubquery:(ALNSQLBuilder *)subquery
                       alias:(NSString *)alias
                onExpression:(NSString *)expression
          identifierBindings:
              (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                  parameters:(nullable NSArray *)parameters;
- (instancetype)leftJoinSubquery:(ALNSQLBuilder *)subquery
                           alias:(NSString *)alias
                    onExpression:(NSString *)expression
                      parameters:(nullable NSArray *)parameters;
- (instancetype)leftJoinSubquery:(ALNSQLBuilder *)subquery
                           alias:(NSString *)alias
                    onExpression:(NSString *)expression
              identifierBindings:
                  (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                      parameters:(nullable NSArray *)parameters;
- (instancetype)rightJoinSubquery:(ALNSQLBuilder *)subquery
                            alias:(NSString *)alias
                     onExpression:(NSString *)expression
                       parameters:(nullable NSArray *)parameters;
- (instancetype)rightJoinSubquery:(ALNSQLBuilder *)subquery
                            alias:(NSString *)alias
                     onExpression:(NSString *)expression
               identifierBindings:
                   (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                       parameters:(nullable NSArray *)parameters;
- (instancetype)fullJoinSubquery:(ALNSQLBuilder *)subquery
                            alias:(NSString *)alias
                     onExpression:(NSString *)expression
                       parameters:(nullable NSArray *)parameters;
- (instancetype)fullJoinSubquery:(ALNSQLBuilder *)subquery
                            alias:(NSString *)alias
                     onExpression:(NSString *)expression
               identifierBindings:
                   (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                       parameters:(nullable NSArray *)parameters;
- (instancetype)joinLateralSubquery:(ALNSQLBuilder *)subquery
                              alias:(NSString *)alias
                       onExpression:(NSString *)expression
                         parameters:(nullable NSArray *)parameters;
- (instancetype)joinLateralSubquery:(ALNSQLBuilder *)subquery
                              alias:(NSString *)alias
                       onExpression:(NSString *)expression
                 identifierBindings:
                     (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                         parameters:(nullable NSArray *)parameters;
- (instancetype)leftJoinLateralSubquery:(ALNSQLBuilder *)subquery
                                  alias:(NSString *)alias
                           onExpression:(NSString *)expression
                             parameters:(nullable NSArray *)parameters;
- (instancetype)leftJoinLateralSubquery:(ALNSQLBuilder *)subquery
                                  alias:(NSString *)alias
                           onExpression:(NSString *)expression
                     identifierBindings:
                         (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                             parameters:(nullable NSArray *)parameters;
- (instancetype)rightJoinLateralSubquery:(ALNSQLBuilder *)subquery
                                   alias:(NSString *)alias
                            onExpression:(NSString *)expression
                              parameters:(nullable NSArray *)parameters;
- (instancetype)rightJoinLateralSubquery:(ALNSQLBuilder *)subquery
                                   alias:(NSString *)alias
                            onExpression:(NSString *)expression
                      identifierBindings:
                          (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                              parameters:(nullable NSArray *)parameters;
- (instancetype)fullJoinLateralSubquery:(ALNSQLBuilder *)subquery
                                   alias:(NSString *)alias
                            onExpression:(NSString *)expression
                              parameters:(nullable NSArray *)parameters;
- (instancetype)fullJoinLateralSubquery:(ALNSQLBuilder *)subquery
                                   alias:(NSString *)alias
                            onExpression:(NSString *)expression
                      identifierBindings:
                          (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                              parameters:(nullable NSArray *)parameters;

- (instancetype)groupByField:(NSString *)field;
- (instancetype)groupByFields:(NSArray<NSString *> *)fields;

- (instancetype)havingField:(NSString *)field equals:(nullable id)value;
- (instancetype)havingField:(NSString *)field
                   operator:(NSString *)operatorName
                      value:(nullable id)value;
- (instancetype)havingExpression:(NSString *)expression
                      parameters:(nullable NSArray *)parameters;
- (instancetype)havingExpression:(NSString *)expression
              identifierBindings:
                  (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                      parameters:(nullable NSArray *)parameters;
- (instancetype)havingAnyGroup:(ALNSQLBuilderGroupBlock)groupBlock;
- (instancetype)havingAllGroup:(ALNSQLBuilderGroupBlock)groupBlock;

- (instancetype)withCTE:(NSString *)name builder:(ALNSQLBuilder *)builder;
- (instancetype)withCTE:(NSString *)name
                columns:(nullable NSArray<NSString *> *)columns
                builder:(ALNSQLBuilder *)builder;
- (instancetype)withRecursiveCTE:(NSString *)name
                          builder:(ALNSQLBuilder *)builder;
- (instancetype)withRecursiveCTE:(NSString *)name
                         columns:(nullable NSArray<NSString *> *)columns
                         builder:(ALNSQLBuilder *)builder;

- (instancetype)windowNamed:(NSString *)name
                 expression:(NSString *)expression
                 parameters:(nullable NSArray *)parameters;
- (instancetype)windowNamed:(NSString *)name
                 expression:(NSString *)expression
        identifierBindings:(nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                 parameters:(nullable NSArray *)parameters;

- (instancetype)unionWith:(ALNSQLBuilder *)builder;
- (instancetype)unionAllWith:(ALNSQLBuilder *)builder;
- (instancetype)intersectWith:(ALNSQLBuilder *)builder;
- (instancetype)exceptWith:(ALNSQLBuilder *)builder;

- (instancetype)orderByField:(NSString *)field descending:(BOOL)descending;
- (instancetype)orderByField:(NSString *)field
                  descending:(BOOL)descending
                       nulls:(nullable NSString *)nullsDirective;
- (instancetype)orderByExpression:(NSString *)expression
                       descending:(BOOL)descending
                            nulls:(nullable NSString *)nullsDirective;
- (instancetype)orderByExpression:(NSString *)expression
                       descending:(BOOL)descending
                            nulls:(nullable NSString *)nullsDirective
                       parameters:(nullable NSArray *)parameters;
- (instancetype)orderByExpression:(NSString *)expression
                       descending:(BOOL)descending
                            nulls:(nullable NSString *)nullsDirective
               identifierBindings:
                   (nullable NSDictionary<NSString *, NSString *> *)identifierBindings
                       parameters:(nullable NSArray *)parameters;
- (instancetype)limit:(NSUInteger)limit;
- (instancetype)offset:(NSUInteger)offset;
- (instancetype)forUpdate;
- (instancetype)forUpdateOfTables:(nullable NSArray<NSString *> *)tables;
- (instancetype)skipLocked;

- (instancetype)returningField:(NSString *)field;
- (instancetype)returningFields:(NSArray<NSString *> *)fields;

- (nullable NSDictionary *)build:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)buildSQL:(NSError *_Nullable *_Nullable)error;
- (NSArray *)buildParameters:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
