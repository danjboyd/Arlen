#ifndef ALN_ORM_DATAVERSE_REPOSITORY_H
#define ALN_ORM_DATAVERSE_REPOSITORY_H

#import <Foundation/Foundation.h>

#import "../Data/ALNDataverseQuery.h"
#import "ALNORMDataverseChangeset.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNORMDataverseContext;

@interface ALNORMDataverseRepository : NSObject

@property(nonatomic, strong, readonly) ALNORMDataverseContext *context;
@property(nonatomic, assign, readonly) Class modelClass;
@property(nonatomic, strong, readonly) ALNORMDataverseModelDescriptor *descriptor;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithContext:(ALNORMDataverseContext *)context
                     modelClass:(Class)modelClass NS_DESIGNATED_INITIALIZER;

- (nullable ALNDataverseQuery *)query;
- (nullable NSArray *)all:(NSError *_Nullable *_Nullable)error;
- (nullable NSArray *)allMatchingQuery:(nullable ALNDataverseQuery *)query
                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable id)firstMatchingQuery:(nullable ALNDataverseQuery *)query
                            error:(NSError *_Nullable *_Nullable)error;
- (nullable id)findByPrimaryID:(NSString *)primaryID
                         error:(NSError *_Nullable *_Nullable)error;
- (nullable id)findByAlternateKeyValues:(NSDictionary<NSString *, id> *)alternateKeyValues
                                  error:(NSError *_Nullable *_Nullable)error;
- (BOOL)loadRelationNamed:(NSString *)relationName
                fromModel:(ALNORMDataverseModel *)model
                    error:(NSError *_Nullable *_Nullable)error;
- (BOOL)saveModel:(ALNORMDataverseModel *)model error:(NSError *_Nullable *_Nullable)error;
- (BOOL)saveModel:(ALNORMDataverseModel *)model
        changeset:(nullable ALNORMDataverseChangeset *)changeset
            error:(NSError *_Nullable *_Nullable)error;
- (BOOL)upsertModel:(ALNORMDataverseModel *)model
  alternateKeyFields:(NSArray<NSString *> *)alternateKeyFields
           changeset:(nullable ALNORMDataverseChangeset *)changeset
               error:(NSError *_Nullable *_Nullable)error;
- (BOOL)deleteModel:(ALNORMDataverseModel *)model error:(NSError *_Nullable *_Nullable)error;
- (BOOL)saveModelsInBatch:(NSArray<ALNORMDataverseModel *> *)models
               changesets:(nullable NSArray<ALNORMDataverseChangeset *> *)changesets
                    error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
