#ifndef ALN_ORM_TYPESCRIPT_CODEGEN_H
#define ALN_ORM_TYPESCRIPT_CODEGEN_H

#import <Foundation/Foundation.h>

#import "ALNORMModelDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMTypeScriptCodegen : NSObject

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

+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromORMManifest:(NSDictionary<NSString *, id> *)manifest
                                                      openAPISpecification:
                                                          (nullable NSDictionary<NSString *, id> *)openAPISpecification
                                                              packageName:(nullable NSString *)packageName
                                                                  targets:(NSArray<NSString *> *)targets
                                                                    error:(NSError *_Nullable *_Nullable)error;

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
