#ifndef ALN_ORM_CHANGESET_H
#define ALN_ORM_CHANGESET_H

#import <Foundation/Foundation.h>

#import "ALNORMModel.h"
#import "ALNORMValueConverter.h"

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^ALNORMFieldValidationBlock)(ALNORMFieldDescriptor *field,
                                           id _Nullable value,
                                           NSError *_Nullable *_Nullable error);

@interface ALNORMChangeset : NSObject

@property(nonatomic, strong, readonly) ALNORMModelDescriptor *descriptor;
@property(nonatomic, weak, readonly) ALNORMModel *model;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *values;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, NSArray<NSString *> *> *fieldErrors;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, ALNORMValueConverter *> *fieldConverters;
@property(nonatomic, copy, readonly) NSSet<NSString *> *requiredFieldNames;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, ALNORMChangeset *> *nestedChangesets;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)changesetWithModel:(ALNORMModel *)model;
- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor
                             model:(nullable ALNORMModel *)model;
- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor
                             model:(nullable ALNORMModel *)model
                    fieldConverters:(nullable NSDictionary<NSString *, ALNORMValueConverter *> *)fieldConverters
                 requiredFieldNames:(nullable NSArray<NSString *> *)requiredFieldNames NS_DESIGNATED_INITIALIZER;

- (BOOL)setObject:(nullable id)value
     forFieldName:(NSString *)fieldName
            error:(NSError *_Nullable *_Nullable)error;
- (BOOL)castInputValue:(nullable id)value
          forFieldName:(NSString *)fieldName
                 error:(NSError *_Nullable *_Nullable)error;
- (BOOL)applyInputValues:(NSDictionary<NSString *, id> *)values
                   error:(NSError *_Nullable *_Nullable)error;
- (nullable id)objectForFieldName:(NSString *)fieldName;
- (void)addError:(NSString *)message forFieldName:(NSString *)fieldName;
- (BOOL)validateRequiredFields;
- (BOOL)validateFieldName:(NSString *)fieldName
               usingBlock:(ALNORMFieldValidationBlock)validationBlock;
- (BOOL)setNestedChangeset:(ALNORMChangeset *)changeset
            forRelationName:(NSString *)relationName
                     error:(NSError *_Nullable *_Nullable)error;
- (nullable ALNORMChangeset *)nestedChangesetForRelationName:(NSString *)relationName;
- (BOOL)applyToModel:(NSError *_Nullable *_Nullable)error;
- (nullable NSDictionary<NSString *, id> *)encodedValues:(NSError *_Nullable *_Nullable)error;
- (BOOL)hasErrors;
- (NSArray<NSString *> *)changedFieldNames;

@end

NS_ASSUME_NONNULL_END

#endif
