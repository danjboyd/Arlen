#ifndef ALN_VALUE_TRANSFORMERS_H
#define ALN_VALUE_TRANSFORMERS_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ALNValueTransformerErrorDomain;
extern NSString *const ALNValueTransformerNameKey;

typedef NS_ENUM(NSInteger, ALNValueTransformerErrorCode) {
  ALNValueTransformerErrorUnknownTransformer = 1,
  ALNValueTransformerErrorTransformFailed = 2,
  ALNValueTransformerErrorInvalidArgument = 3,
};

void ALNRegisterDefaultValueTransformers(void);
BOOL ALNRegisterValueTransformer(NSString *name, NSValueTransformer *transformer);
NSValueTransformer *_Nullable ALNValueTransformerNamed(NSString *name);
NSArray<NSString *> *ALNRegisteredValueTransformerNames(void);
id _Nullable ALNApplyValueTransformerNamed(NSString *name,
                                           id _Nullable value,
                                           NSError **_Nullable error);

NS_ASSUME_NONNULL_END

#endif
