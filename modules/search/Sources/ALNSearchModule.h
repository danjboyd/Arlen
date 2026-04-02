#ifndef ALN_SEARCH_MODULE_H
#define ALN_SEARCH_MODULE_H

#import <Foundation/Foundation.h>

#import "ALNModuleSystem.h"

@class ALNApplication;
@class ALNContext;
@class ALNSearchModuleRuntime;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNSearchModuleErrorDomain;

typedef NS_ENUM(NSInteger, ALNSearchModuleErrorCode) {
  ALNSearchModuleErrorInvalidConfiguration = 1,
  ALNSearchModuleErrorValidationFailed = 2,
  ALNSearchModuleErrorNotFound = 3,
  ALNSearchModuleErrorExecutionFailed = 4,
  ALNSearchModuleErrorUnauthorized = 5,
  ALNSearchModuleErrorForbidden = 6,
};

typedef BOOL (^ALNSearchResourceBatchConsumer)(NSArray<NSDictionary *> *records,
                                               NSError *_Nullable *_Nullable error);

@protocol ALNSearchEngine <NSObject>

- (nullable NSDictionary *)searchModuleSnapshotForMetadata:(NSDictionary *)metadata
                                                   records:(NSArray<NSDictionary *> *)records
                                                generation:(NSUInteger)generation
                                                     error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)searchModuleApplyOperation:(NSString *)operation
                                               record:(nullable NSDictionary *)record
                                             metadata:(NSDictionary *)metadata
                                      existingSnapshot:(nullable NSDictionary *)snapshot
                                                error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)searchModuleExecuteQuery:(nullable NSString *)query
                                     resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                  snapshotsByResource:(NSDictionary<NSString *, NSDictionary *> *)snapshotsByResource
                                              filters:(nullable NSDictionary *)filters
                                                 sort:(nullable NSString *)sort
                                                limit:(NSUInteger)limit
                                               offset:(NSUInteger)offset
                                                error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)searchModuleCapabilities;

@optional

- (BOOL)searchModuleConfigureWithRuntime:(ALNSearchModuleRuntime *)runtime
                             application:(ALNApplication *)application
                              moduleConfig:(NSDictionary *)moduleConfig
                                   error:(NSError *_Nullable *_Nullable)error;
- (nullable id)searchModuleBeginBuildForMetadata:(NSDictionary *)metadata
                                      generation:(NSUInteger)generation
                                           error:(NSError *_Nullable *_Nullable)error;
- (BOOL)searchModuleAppendBuildRecords:(NSArray<NSDictionary *> *)records
                              metadata:(NSDictionary *)metadata
                                 state:(id)state
                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)searchModuleFinalizeBuildState:(id)state
                                                 metadata:(NSDictionary *)metadata
                                                    error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)searchModuleExecuteQuery:(nullable NSString *)query
                                     resourceMetadata:(NSArray<NSDictionary *> *)resourceMetadata
                                  snapshotsByResource:(NSDictionary<NSString *, NSDictionary *> *)snapshotsByResource
                                              filters:(nullable NSDictionary *)filters
                                                 sort:(nullable NSString *)sort
                                                limit:(NSUInteger)limit
                                               offset:(NSUInteger)offset
                                              options:(nullable NSDictionary *)options
                                                error:(NSError *_Nullable *_Nullable)error;

@end

@protocol ALNSearchResourceDefinition <NSObject>

- (NSString *)searchModuleResourceIdentifier;
- (NSDictionary *)searchModuleResourceMetadata;
- (nullable NSArray<NSDictionary *> *)searchModuleDocumentsForRuntime:(ALNSearchModuleRuntime *)runtime
                                                                error:(NSError *_Nullable *_Nullable)error;

@optional

- (nullable NSDictionary *)searchModulePublicResultForDocument:(NSDictionary *)document
                                                       metadata:(NSDictionary *)metadata
                                                        runtime:(ALNSearchModuleRuntime *)runtime
                                                          error:(NSError *_Nullable *_Nullable)error;
- (BOOL)searchModuleAllowsQueryForContext:(ALNContext *)context
                                  runtime:(ALNSearchModuleRuntime *)runtime
                                    error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)searchModuleAdditionalFiltersForContext:(ALNContext *)context
                                                           metadata:(NSDictionary *)metadata
                                                            runtime:(ALNSearchModuleRuntime *)runtime
                                                              error:(NSError *_Nullable *_Nullable)error;
- (BOOL)searchModuleAllowsIndexingRecord:(NSDictionary *)record
                                 metadata:(NSDictionary *)metadata
                                  runtime:(ALNSearchModuleRuntime *)runtime
                                    error:(NSError *_Nullable *_Nullable)error;
- (BOOL)searchModuleEnumerateDocumentBatchesForRuntime:(ALNSearchModuleRuntime *)runtime
                                             batchSize:(NSUInteger)batchSize
                                            usingBlock:(ALNSearchResourceBatchConsumer)consumer
                                                 error:(NSError *_Nullable *_Nullable)error;

@end

@protocol ALNSearchResourceProvider <NSObject>

- (nullable NSArray<id<ALNSearchResourceDefinition>> *)searchModuleResourcesForRuntime:
    (ALNSearchModuleRuntime *)runtime
                                                                           error:
                                                                               (NSError *_Nullable *_Nullable)error;

@end

@interface ALNSearchModuleRuntime : NSObject

@property(nonatomic, copy, readonly) NSString *prefix;
@property(nonatomic, copy, readonly) NSString *apiPrefix;
@property(nonatomic, copy, readonly) NSArray<NSString *> *accessRoles;
@property(nonatomic, assign, readonly) NSUInteger minimumAuthAssuranceLevel;
@property(nonatomic, strong, readonly, nullable) ALNApplication *application;

+ (instancetype)sharedRuntime;

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)resolvedConfigSummary;
- (NSArray<NSDictionary *> *)registeredResources;
- (nullable NSDictionary *)resourceMetadataForIdentifier:(NSString *)identifier;
- (nullable NSDictionary *)queueReindexForResourceIdentifier:(nullable NSString *)identifier
                                                       error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)queueIncrementalSyncForResourceIdentifier:(NSString *)identifier
                                                               record:(nullable NSDictionary *)record
                                                            operation:(NSString *)operation
                                                                error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)processReindexJobPayload:(NSDictionary *)payload
                                              error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)searchQuery:(nullable NSString *)query
                    resourceIdentifier:(nullable NSString *)resourceIdentifier
                               filters:(nullable NSDictionary *)filters
                                  sort:(nullable NSString *)sort
                                limit:(NSUInteger)limit
                               offset:(NSUInteger)offset
                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)searchQuery:(nullable NSString *)query
                    resourceIdentifier:(nullable NSString *)resourceIdentifier
                               filters:(nullable NSDictionary *)filters
                                  sort:(nullable NSString *)sort
                                 limit:(NSUInteger)limit
                                offset:(NSUInteger)offset
                          queryOptions:(nullable NSDictionary *)queryOptions
                                 error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)resourceDrilldownForIdentifier:(nullable NSString *)identifier;
- (NSDictionary *)dashboardSummary;

@end

@interface ALNSearchModule : NSObject <ALNModule>
@end

NS_ASSUME_NONNULL_END

#endif
