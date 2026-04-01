#ifndef ALN_ORM_REPOSITORY_H
#define ALN_ORM_REPOSITORY_H

#import <Foundation/Foundation.h>

#import "../Data/ALNDatabaseAdapter.h"
#import "ALNORMQuery.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNORMContext;

@interface ALNORMRepository : NSObject

@property(nonatomic, strong, readonly) ALNORMContext *context;
@property(nonatomic, assign, readonly) Class modelClass;
@property(nonatomic, strong, readonly) ALNORMModelDescriptor *descriptor;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContext:(ALNORMContext *)context
                     modelClass:(Class)modelClass NS_DESIGNATED_INITIALIZER;

- (nullable ALNORMQuery *)query;
- (nullable ALNORMQuery *)queryByApplyingScope:(nullable ALNORMQueryScope)scope;
- (nullable NSArray *)all:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray *)allMatchingQuery:(nullable ALNORMQuery *)query
                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable id)first:(NSError *_Nullable *_Nullable)error;
- (nullable id)firstMatchingQuery:(nullable ALNORMQuery *)query
                            error:(NSError *_Nullable *_Nullable)error;
- (NSUInteger)count:(NSError *_Nullable *_Nullable)error;
- (NSUInteger)countMatchingQuery:(nullable ALNORMQuery *)query
                           error:(NSError *_Nullable *_Nullable)error;
- (BOOL)exists:(NSError *_Nullable *_Nullable)error;
- (BOOL)existsMatchingQuery:(nullable ALNORMQuery *)query
                      error:(NSError *_Nullable *_Nullable)error;
- (nullable id)findByPrimaryKey:(id)primaryKey
                          error:(NSError *_Nullable *_Nullable)error;
- (nullable id)findByPrimaryKeyValues:(NSDictionary<NSString *, id> *)primaryKeyValues
                                error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary<NSString *, id> *)compiledPlanForQuery:(nullable ALNORMQuery *)query
                                                          error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
