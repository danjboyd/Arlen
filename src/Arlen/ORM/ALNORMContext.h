#ifndef ALN_ORM_CONTEXT_H
#define ALN_ORM_CONTEXT_H

#import <Foundation/Foundation.h>

#import "../Data/ALNDatabaseAdapter.h"
#import "ALNORMQuery.h"
#import "ALNORMValueConverter.h"
#import "ALNORMWriteOptions.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNORMModel;
@class ALNORMQuery;
@class ALNORMRepository;

typedef BOOL (^ALNORMContextBlock)(NSError *_Nullable *_Nullable error);

@interface ALNORMContext : NSObject

@property(nonatomic, strong, readonly) id<ALNDatabaseAdapter> adapter;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *capabilityMetadata;
@property(nonatomic, assign, readonly, getter=isIdentityTrackingEnabled) BOOL identityTrackingEnabled;
@property(nonatomic, assign) BOOL defaultStrictLoadingEnabled;
@property(nonatomic, assign, readonly) NSUInteger queryCount;
@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *queryEvents;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter;
- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter
         identityTrackingEnabled:(BOOL)identityTrackingEnabled NS_DESIGNATED_INITIALIZER;

+ (NSDictionary<NSString *, id> *)capabilityMetadataForAdapter:(nullable id<ALNDatabaseAdapter>)adapter;
- (nullable ALNORMRepository *)repositoryForModelClass:(Class)modelClass;
- (void)registerFieldConverters:(NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters
                  forModelClass:(Class)modelClass;
- (NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConvertersForModelClass:(Class)modelClass;
- (void)registerDefaultWriteOptions:(ALNORMWriteOptions *)writeOptions
                      forModelClass:(Class)modelClass;
- (nullable ALNORMWriteOptions *)defaultWriteOptionsForModelClass:(Class)modelClass;
- (void)resetTracking;
- (void)detachModel:(ALNORMModel *)model;
- (nullable ALNORMModel *)reloadModel:(ALNORMModel *)model
                                error:(NSError *_Nullable *_Nullable)error;
- (BOOL)withTransactionUsingBlock:(ALNORMContextBlock)block
                            error:(NSError *_Nullable *_Nullable)error;
- (BOOL)withSavepointNamed:(NSString *)name
                usingBlock:(ALNORMContextBlock)block
                     error:(NSError *_Nullable *_Nullable)error;
- (BOOL)withQueryBudget:(NSUInteger)maximum
             usingBlock:(ALNORMContextBlock)block
                  error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNORMQuery *)queryForRelationNamed:(NSString *)relationName
                                      fromModel:(ALNORMModel *)model
                                          error:(NSError *_Nullable *_Nullable)error;
- (BOOL)loadRelationNamed:(NSString *)relationName
                fromModel:(ALNORMModel *)model
                 strategy:(ALNORMRelationLoadStrategy)strategy
                    error:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray *)allForRelationNamed:(NSString *)relationName
                                fromModel:(ALNORMModel *)model
                                    error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
