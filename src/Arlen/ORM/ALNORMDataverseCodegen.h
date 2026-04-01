#ifndef ALN_ORM_DATAVERSE_CODEGEN_H
#define ALN_ORM_DATAVERSE_CODEGEN_H

#import <Foundation/Foundation.h>

#import "ALNORMDataverseModelDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMDataverseCodegen : NSObject

+ (nullable NSArray<ALNORMDataverseModelDescriptor *> *)modelDescriptorsFromMetadata:
                                                   (NSDictionary<NSString *, id> *)metadata
                                                                       classPrefix:(NSString *)classPrefix
                                                                   dataverseTarget:(nullable NSString *)dataverseTarget
                                                                              error:
                                                                                  (NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
