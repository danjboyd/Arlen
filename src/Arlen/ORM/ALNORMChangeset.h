#ifndef ALN_ORM_CHANGESET_H
#define ALN_ORM_CHANGESET_H

#import <Foundation/Foundation.h>

#import "ALNORMModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMChangeset : NSObject

@property(nonatomic, strong, readonly) ALNORMModelDescriptor *descriptor;
@property(nonatomic, weak, readonly) ALNORMModel *model;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *values;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSArray<NSString *> *> *fieldErrors;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor
                             model:(nullable ALNORMModel *)model NS_DESIGNATED_INITIALIZER;

- (BOOL)setObject:(nullable id)value
     forFieldName:(NSString *)fieldName
            error:(NSError *_Nullable *_Nullable)error;
- (nullable id)objectForFieldName:(NSString *)fieldName;
- (void)addError:(NSString *)message forFieldName:(NSString *)fieldName;
- (BOOL)hasErrors;
- (NSArray<NSString *> *)changedFieldNames;

@end

NS_ASSUME_NONNULL_END

#endif
