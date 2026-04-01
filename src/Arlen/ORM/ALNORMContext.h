#ifndef ALN_ORM_CONTEXT_H
#define ALN_ORM_CONTEXT_H

#import <Foundation/Foundation.h>

#import "../Data/ALNDatabaseAdapter.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNORMModel;
@class ALNORMQuery;
@class ALNORMRepository;

@interface ALNORMContext : NSObject

@property(nonatomic, strong, readonly) id<ALNDatabaseAdapter> adapter;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *capabilityMetadata;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAdapter:(id<ALNDatabaseAdapter>)adapter NS_DESIGNATED_INITIALIZER;

+ (NSDictionary<NSString *, id> *)capabilityMetadataForAdapter:(nullable id<ALNDatabaseAdapter>)adapter;
- (nullable ALNORMRepository *)repositoryForModelClass:(Class)modelClass;
- (nullable ALNORMQuery *)queryForRelationNamed:(NSString *)relationName
                                      fromModel:(ALNORMModel *)model
                                          error:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray *)allForRelationNamed:(NSString *)relationName
                                fromModel:(ALNORMModel *)model
                                    error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
