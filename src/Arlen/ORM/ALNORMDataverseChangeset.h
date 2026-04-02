#ifndef ALN_ORM_DATAVERSE_CHANGESET_H
#define ALN_ORM_DATAVERSE_CHANGESET_H

#import <Foundation/Foundation.h>

#import "ALNORMDataverseModel.h"
#import "ALNORMValueConverter.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMDataverseChangeset : NSObject

@property(nonatomic, strong, readonly) ALNORMDataverseModelDescriptor *descriptor;
@property(nonatomic, weak, readonly, nullable) ALNORMDataverseModel *model;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *values;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSArray<NSString *> *> *fieldErrors;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, ALNORMValueConverter *> *fieldConverters;
@property(nonatomic, copy, readonly) NSSet<NSString *> *requiredFieldNames;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)changesetWithModel:(ALNORMDataverseModel *)model;
- (instancetype)initWithDescriptor:(ALNORMDataverseModelDescriptor *)descriptor
                             model:(nullable ALNORMDataverseModel *)model
                    fieldConverters:(nullable NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters
                 requiredFieldNames:(nullable NSArray<NSString *> *)requiredFieldNames NS_DESIGNATED_INITIALIZER;
- (BOOL)castInputValue:(nullable id)value
          forFieldName:(NSString *)fieldName
                 error:(NSError *_Nullable *_Nullable)error;
- (BOOL)applyInputValues:(NSDictionary<NSString *, id> *)values
                   error:(NSError *_Nullable *_Nullable)error;
- (void)addError:(NSString *)message forFieldName:(NSString *)fieldName;
- (BOOL)validateRequiredFields;
- (BOOL)applyToModel:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary<NSString *, id> *)encodedValues:(NSError *_Nullable *_Nullable)error;
- (BOOL)hasErrors;
- (NSArray<NSString *> *)changedFieldNames;

@end

NS_ASSUME_NONNULL_END

#endif
