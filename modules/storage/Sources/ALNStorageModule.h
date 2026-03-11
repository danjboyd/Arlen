#ifndef ALN_STORAGE_MODULE_H
#define ALN_STORAGE_MODULE_H

#import <Foundation/Foundation.h>

#import "ALNJobsModule.h"
#import "ALNModuleSystem.h"
#import "ALNServices.h"

@class ALNApplication;
@class ALNStorageModuleRuntime;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNStorageModuleErrorDomain;

typedef NS_ENUM(NSInteger, ALNStorageModuleErrorCode) {
  ALNStorageModuleErrorInvalidConfiguration = 1,
  ALNStorageModuleErrorValidationFailed = 2,
  ALNStorageModuleErrorNotFound = 3,
  ALNStorageModuleErrorTokenRejected = 4,
  ALNStorageModuleErrorPersistenceFailed = 5,
};

@protocol ALNStorageCollectionDefinition <NSObject>

- (NSString *)storageModuleCollectionIdentifier;
- (NSDictionary *)storageModuleCollectionMetadata;

@optional
- (BOOL)storageModuleValidateObjectNamed:(NSString *)name
                             contentType:(NSString *)contentType
                               sizeBytes:(NSUInteger)sizeBytes
                                metadata:(NSDictionary *)metadata
                                 runtime:(ALNStorageModuleRuntime *)runtime
                                   error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)storageModuleVariantRepresentationForObject:(NSDictionary *)objectRecord
                                                     variantDefinition:(NSDictionary *)variantDefinition
                                                          originalData:(NSData *)originalData
                                                      originalMetadata:(NSDictionary *)originalMetadata
                                                               runtime:(ALNStorageModuleRuntime *)runtime
                                                                 error:(NSError *_Nullable *_Nullable)error;

@end

@protocol ALNStorageCollectionProvider <NSObject>

- (nullable NSArray<id<ALNStorageCollectionDefinition>> *)storageModuleCollectionsForRuntime:
    (ALNStorageModuleRuntime *)runtime
                                                                 error:
                                                                     (NSError *_Nullable *_Nullable)error;

@end

@interface ALNStorageModuleRuntime : NSObject

@property(nonatomic, copy, readonly) NSString *prefix;
@property(nonatomic, copy, readonly) NSString *apiPrefix;
@property(nonatomic, assign, readonly) NSTimeInterval defaultUploadSessionTTLSeconds;
@property(nonatomic, assign, readonly) NSTimeInterval defaultDownloadTokenTTLSeconds;
@property(nonatomic, strong, readonly, nullable) ALNApplication *application;
@property(nonatomic, strong, readonly, nullable) id<ALNAttachmentAdapter> attachmentAdapter;

+ (instancetype)sharedRuntime;

- (BOOL)configureWithApplication:(ALNApplication *)application
                           error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)resolvedConfigSummary;
- (NSArray<NSDictionary *> *)registeredCollections;
- (nullable NSDictionary *)collectionMetadataForIdentifier:(NSString *)identifier;
- (NSArray<NSDictionary *> *)listObjectsForCollection:(nullable NSString *)collection
                                                query:(nullable NSString *)query;
- (nullable NSDictionary *)objectRecordForIdentifier:(NSString *)objectID
                                               error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)createUploadSessionForCollection:(NSString *)collection
                                                       name:(NSString *)name
                                                contentType:(NSString *)contentType
                                                  sizeBytes:(NSUInteger)sizeBytes
                                                   metadata:(nullable NSDictionary *)metadata
                                                 expiresIn:(NSTimeInterval)expiresIn
                                                      error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)storeUploadData:(NSData *)data
                      forUploadSessionID:(NSString *)sessionID
                                   token:(NSString *)token
                                   error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)storeObjectInCollection:(NSString *)collection
                                              name:(NSString *)name
                                       contentType:(NSString *)contentType
                                              data:(NSData *)data
                                          metadata:(nullable NSDictionary *)metadata
                                             error:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)issueDownloadTokenForObjectID:(NSString *)objectID
                                           expiresIn:(NSTimeInterval)expiresIn
                                               error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)payloadForDownloadToken:(NSString *)token
                                             error:(NSError *_Nullable *_Nullable)error;
- (nullable NSData *)downloadDataForToken:(NSString *)token
                                 metadata:(NSDictionary *_Nullable *_Nullable)metadata
                                    error:(NSError *_Nullable *_Nullable)error;
- (BOOL)deleteObjectIdentifier:(NSString *)objectID
                         error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)queueVariantGenerationForObjectID:(NSString *)objectID
                                                       error:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary *)processVariantJobPayload:(NSDictionary *)payload
                                              error:(NSError *_Nullable *_Nullable)error;
- (NSDictionary *)dashboardSummary;

@end

@interface ALNStorageModule : NSObject <ALNModule>
@end

NS_ASSUME_NONNULL_END

#endif
