#ifndef ALN_SCHEMA_CODEGEN_H
#define ALN_SCHEMA_CODEGEN_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNSchemaCodegenErrorDomain;

typedef NS_ENUM(NSInteger, ALNSchemaCodegenErrorCode) {
  ALNSchemaCodegenErrorInvalidArgument = 1,
  ALNSchemaCodegenErrorInvalidMetadata = 2,
  ALNSchemaCodegenErrorIdentifierCollision = 3,
};

@interface ALNSchemaCodegen : NSObject

+ (nullable NSArray<NSDictionary<NSString *, id> *> *)normalizedColumnsFromRows:(NSArray<NSDictionary *> *)rows
                                                                          error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromColumns:(NSArray<NSDictionary *> *)rows
                                                           classPrefix:(NSString *)classPrefix
                                                                 error:(NSError *_Nullable *_Nullable)error;

+ (nullable NSDictionary<NSString *, id> *)renderArtifactsFromColumns:(NSArray<NSDictionary *> *)rows
                                                           classPrefix:(NSString *)classPrefix
                                                        databaseTarget:(nullable NSString *)databaseTarget
                                                                 error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
