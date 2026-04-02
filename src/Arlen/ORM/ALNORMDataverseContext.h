#ifndef ALN_ORM_DATAVERSE_CONTEXT_H
#define ALN_ORM_DATAVERSE_CONTEXT_H

#import <Foundation/Foundation.h>

#import "../Data/ALNDataverseClient.h"
#import "ALNORMValueConverter.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNORMDataverseModel;
@class ALNORMDataverseRepository;

@interface ALNORMDataverseContext : NSObject

@property(nonatomic, strong, readonly) ALNDataverseClient *client;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *capabilityMetadata;
@property(nonatomic, assign, readonly) BOOL identityTrackingEnabled;
@property(nonatomic, assign, readonly) NSUInteger queryCount;
@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *queryEvents;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithClient:(ALNDataverseClient *)client;
- (instancetype)initWithClient:(ALNDataverseClient *)client
        identityTrackingEnabled:(BOOL)identityTrackingEnabled NS_DESIGNATED_INITIALIZER;

+ (NSDictionary<NSString *, id> *)capabilityMetadataForClient:(nullable ALNDataverseClient *)client;
- (nullable ALNORMDataverseRepository *)repositoryForModelClass:(Class)modelClass;
- (void)registerFieldConverters:(NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters
                  forModelClass:(Class)modelClass;
- (NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConvertersForModelClass:(Class)modelClass;
- (BOOL)loadRelationNamed:(NSString *)relationName
                fromModel:(ALNORMDataverseModel *)model
                    error:(NSError *_Nullable *_Nullable)error;
- (void)resetTracking;
- (void)detachModel:(ALNORMDataverseModel *)model;

@end

NS_ASSUME_NONNULL_END

#endif
