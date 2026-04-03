#ifndef ALN_ORM_TYPESCRIPT_CODEGEN_H
#define ALN_ORM_TYPESCRIPT_CODEGEN_H

#import <Foundation/Foundation.h>

#import "ALNORMModelDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

/** Render a descriptor-first TypeScript package from ORM descriptors plus optional OpenAPI contracts. */
@interface ALNORMTypeScriptCodegen : NSObject

/** Render TypeScript artifacts from raw schema metadata or wrapped metadata JSON. */
+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromSchemaMetadata:(NSDictionary<NSString *, id> *)metadata
                                                                 classPrefix:(NSString *)classPrefix
                                                              databaseTarget:(nullable NSString *)databaseTarget
                                                          descriptorOverrides:
                                                              (nullable NSDictionary<NSString *, NSDictionary *> *)descriptorOverrides
                                                         openAPISpecification:
                                                             (nullable NSDictionary<NSString *, id> *)openAPISpecification
                                                                 packageName:(nullable NSString *)packageName
                                                                     targets:(NSArray<NSString *> *)targets
                                                                       error:(NSError *_Nullable *_Nullable)error;

/** Render TypeScript artifacts from a checked-in `arlen-orm-descriptor-v1` manifest. */
+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromORMManifest:(NSDictionary<NSString *, id> *)manifest
                                                      openAPISpecification:
                                                          (nullable NSDictionary<NSString *, id> *)openAPISpecification
                                                              packageName:(nullable NSString *)packageName
                                                                  targets:(NSArray<NSString *> *)targets
                                                                    error:(NSError *_Nullable *_Nullable)error;

/** Render TypeScript artifacts from already-materialized ORM model descriptors. */
+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromModelDescriptors:
    (NSArray<ALNORMModelDescriptor *> *)descriptors
                                           openAPISpecification:
                                               (nullable NSDictionary<NSString *, id> *)openAPISpecification
                                                   packageName:(nullable NSString *)packageName
                                                       targets:(NSArray<NSString *> *)targets
                                                         error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
