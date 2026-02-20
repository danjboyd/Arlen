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

- (instancetype)whereField:(NSString *)field equals:(nullable id)value;
- (instancetype)whereField:(NSString *)field
                  operator:(NSString *)operatorName
                     value:(nullable id)value;
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

- (instancetype)groupByField:(NSString *)field;
- (instancetype)groupByFields:(NSArray<NSString *> *)fields;

- (instancetype)havingField:(NSString *)field equals:(nullable id)value;
- (instancetype)havingField:(NSString *)field
                   operator:(NSString *)operatorName
                      value:(nullable id)value;
- (instancetype)havingAnyGroup:(ALNSQLBuilderGroupBlock)groupBlock;
- (instancetype)havingAllGroup:(ALNSQLBuilderGroupBlock)groupBlock;

- (instancetype)withCTE:(NSString *)name builder:(ALNSQLBuilder *)builder;
- (instancetype)withRecursiveCTE:(NSString *)name
                          builder:(ALNSQLBuilder *)builder;

- (instancetype)orderByField:(NSString *)field descending:(BOOL)descending;
- (instancetype)limit:(NSUInteger)limit;
- (instancetype)offset:(NSUInteger)offset;

- (instancetype)returningField:(NSString *)field;
- (instancetype)returningFields:(NSArray<NSString *> *)fields;

- (nullable NSDictionary *)build:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)buildSQL:(NSError *_Nullable *_Nullable)error;
- (NSArray *)buildParameters:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
