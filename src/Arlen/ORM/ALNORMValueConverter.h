#ifndef ALN_ORM_VALUE_CONVERTER_H
#define ALN_ORM_VALUE_CONVERTER_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef id _Nullable (^ALNORMValueConversionBlock)(id _Nullable value,
                                                   NSError *_Nullable *_Nullable error);

@interface ALNORMValueConverter : NSObject

@property(nonatomic, copy, readonly) ALNORMValueConversionBlock decodeBlock;
@property(nonatomic, copy, readonly) ALNORMValueConversionBlock encodeBlock;

+ (instancetype)converterWithDecodeBlock:(ALNORMValueConversionBlock)decodeBlock
                              encodeBlock:(ALNORMValueConversionBlock)encodeBlock;
+ (instancetype)passthroughConverter;
+ (instancetype)stringConverter;
+ (instancetype)numberConverter;
+ (instancetype)integerConverter;
+ (instancetype)ISO8601DateTimeConverter;
+ (instancetype)JSONConverter;
+ (instancetype)arrayConverter;
+ (instancetype)enumConverterWithAllowedValues:(NSArray<NSString *> *)allowedValues;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDecodeBlock:(ALNORMValueConversionBlock)decodeBlock
                         encodeBlock:(ALNORMValueConversionBlock)encodeBlock NS_DESIGNATED_INITIALIZER;

- (nullable id)decodeValue:(nullable id)value error:(NSError *_Nullable *_Nullable)error;
- (nullable id)encodeValue:(nullable id)value error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
