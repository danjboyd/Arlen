#ifndef ALN_ORM_QUERY_H
#define ALN_ORM_QUERY_H

#import <Foundation/Foundation.h>

#import "../Data/ALNSQLBuilder.h"
#import "ALNORMModelDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^ALNORMQueryScope)(id query);

typedef NS_ENUM(NSInteger, ALNORMRelationLoadStrategy) {
  ALNORMRelationLoadStrategyDefault = 0,
  ALNORMRelationLoadStrategyJoined = 1,
  ALNORMRelationLoadStrategySelectIn = 2,
  ALNORMRelationLoadStrategyNoLoad = 3,
  ALNORMRelationLoadStrategyRaiseOnAccess = 4,
};

FOUNDATION_EXPORT NSString *ALNORMRelationLoadStrategyName(ALNORMRelationLoadStrategy strategy);

@interface ALNORMQuery : NSObject

@property(nonatomic, assign, readonly) Class modelClass;
@property(nonatomic, strong, readonly) ALNORMModelDescriptor *descriptor;
@property(nonatomic, copy, readonly) NSArray<NSString *> *selectedFieldNames;
@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *joins;
@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *predicates;
@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *orderings;
@property(nonatomic, assign, readonly) BOOL hasLimit;
@property(nonatomic, assign, readonly) NSUInteger limitValue;
@property(nonatomic, assign, readonly) BOOL hasOffset;
@property(nonatomic, assign, readonly) NSUInteger offsetValue;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSNumber *> *relationLoadStrategies;
@property(nonatomic, assign, readonly, getter=isStrictLoadingEnabled) BOOL strictLoadingEnabled;

+ (nullable instancetype)queryWithModelClass:(Class)modelClass;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithModelClass:(Class)modelClass
                        descriptor:(ALNORMModelDescriptor *)descriptor NS_DESIGNATED_INITIALIZER;

- (ALNORMQuery *)selectFields:(nullable NSArray<NSString *> *)fieldNames;
- (ALNORMQuery *)selectProperties:(nullable NSArray<NSString *> *)propertyNames;
- (ALNORMQuery *)whereField:(NSString *)fieldName equals:(nullable id)value;
- (ALNORMQuery *)whereField:(NSString *)fieldName
                   operator:(NSString *)operatorName
                      value:(nullable id)value;
- (ALNORMQuery *)whereFieldIn:(NSString *)fieldName values:(NSArray *)values;
- (ALNORMQuery *)whereFieldNotIn:(NSString *)fieldName values:(NSArray *)values;
- (ALNORMQuery *)whereQualifiedField:(NSString *)qualifiedField
                            operator:(NSString *)operatorName
                               value:(nullable id)value;
- (ALNORMQuery *)whereExpression:(NSString *)expression parameters:(nullable NSArray *)parameters;
- (ALNORMQuery *)whereField:(NSString *)fieldName inSubquery:(ALNSQLBuilder *)subquery;
- (ALNORMQuery *)joinTable:(NSString *)tableName
               onLeftField:(NSString *)leftField
                  operator:(NSString *)operatorName
              onRightField:(NSString *)rightField;
- (ALNORMQuery *)orderByField:(NSString *)fieldName descending:(BOOL)descending;
- (ALNORMQuery *)limit:(NSUInteger)limit;
- (ALNORMQuery *)offset:(NSUInteger)offset;
- (ALNORMQuery *)applyScope:(nullable ALNORMQueryScope)scope;
- (ALNORMQuery *)withRelationNamed:(NSString *)relationName
                      loadStrategy:(ALNORMRelationLoadStrategy)loadStrategy;
- (ALNORMQuery *)withJoinedRelationNamed:(NSString *)relationName;
- (ALNORMQuery *)withSelectInRelationNamed:(NSString *)relationName;
- (ALNORMQuery *)withNoLoadRelationNamed:(NSString *)relationName;
- (ALNORMQuery *)withRaiseOnAccessRelationNamed:(NSString *)relationName;
- (ALNORMQuery *)strictLoading:(BOOL)enabled;
- (ALNORMRelationLoadStrategy)loadStrategyForRelationNamed:(NSString *)relationName;
- (nullable ALNSQLBuilder *)selectBuilder:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
