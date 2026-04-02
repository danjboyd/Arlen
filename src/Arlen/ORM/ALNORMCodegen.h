#ifndef ALN_ORM_CODEGEN_H
#define ALN_ORM_CODEGEN_H

#import <Foundation/Foundation.h>

#import "ALNORMModelDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMCodegen : NSObject

+ (nullable NSArray<ALNORMModelDescriptor *> *)modelDescriptorsFromSchemaMetadata:(NSDictionary<NSString *, id> *)metadata
                                                                      classPrefix:(NSString *)classPrefix
                                                                            error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSArray<ALNORMModelDescriptor *> *)modelDescriptorsFromSchemaMetadata:(NSDictionary<NSString *, id> *)metadata
                                                                      classPrefix:(NSString *)classPrefix
                                                                   databaseTarget:(nullable NSString *)databaseTarget
                                                               descriptorOverrides:(nullable NSDictionary<NSString *, NSDictionary *> *)descriptorOverrides
                                                                            error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromSchemaMetadata:(NSDictionary<NSString *, id> *)metadata
                                                                 classPrefix:(NSString *)classPrefix
                                                                       error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromSchemaMetadata:(NSDictionary<NSString *, id> *)metadata
                                                                 classPrefix:(NSString *)classPrefix
                                                              databaseTarget:(nullable NSString *)databaseTarget
                                                          descriptorOverrides:(nullable NSDictionary<NSString *, NSDictionary *> *)descriptorOverrides
                                                                       error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
