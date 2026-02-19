#ifndef ALN_SQL_BUILDER_H
#define ALN_SQL_BUILDER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNSQLBuilderErrorDomain;

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
+ (instancetype)insertInto:(NSString *)tableName
                    values:(NSDictionary<NSString *, id> *)values;
+ (instancetype)updateTable:(NSString *)tableName
                     values:(NSDictionary<NSString *, id> *)values;
+ (instancetype)deleteFrom:(NSString *)tableName;

- (instancetype)whereField:(NSString *)field equals:(nullable id)value;
- (instancetype)whereField:(NSString *)field
                  operator:(NSString *)operatorName
                     value:(nullable id)value;
- (instancetype)whereFieldIn:(NSString *)field
                      values:(NSArray *)values;
- (instancetype)orderByField:(NSString *)field descending:(BOOL)descending;
- (instancetype)limit:(NSUInteger)limit;
- (instancetype)offset:(NSUInteger)offset;

- (nullable NSDictionary *)build:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)buildSQL:(NSError *_Nullable *_Nullable)error;
- (NSArray *)buildParameters:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
