#ifndef ALN_ORM_MODEL_H
#define ALN_ORM_MODEL_H

#import <Foundation/Foundation.h>

#import "ALNORMModelDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNORMContext;
@class ALNORMQuery;
@class ALNORMRepository;

typedef NS_ENUM(NSInteger, ALNORMModelState) {
  ALNORMModelStateNew = 1,
  ALNORMModelStateLoaded = 2,
  ALNORMModelStateDirty = 3,
  ALNORMModelStateDetached = 4,
};

FOUNDATION_EXPORT NSString *ALNORMModelStateName(ALNORMModelState state);

@protocol ALNORMModelClass <NSObject>
+ (nullable ALNORMModelDescriptor *)modelDescriptor;
@optional
+ (nullable instancetype)modelFromRow:(NSDictionary<NSString *, id> *)row
                                error:(NSError *_Nullable *_Nullable)error;
@end

@interface ALNORMModel : NSObject <ALNORMModelClass>

@property(nonatomic, strong, readonly) ALNORMModelDescriptor *descriptor;
@property(nonatomic, assign, readonly) ALNORMModelState state;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *fieldValues;
@property(nonatomic, copy, readonly) NSDictionary<NSString *, id> *relationValues;
@property(nonatomic, copy, readonly) NSSet<NSString *> *dirtyFieldNames;

- (instancetype)init;
- (instancetype)initWithDescriptor:(ALNORMModelDescriptor *)descriptor NS_DESIGNATED_INITIALIZER;

+ (nullable ALNORMModelDescriptor *)modelDescriptor;
+ (nullable ALNORMQuery *)query;
+ (nullable ALNORMRepository *)repositoryWithContext:(ALNORMContext *)context;
+ (nullable instancetype)modelFromRow:(NSDictionary<NSString *, id> *)row
                                error:(NSError *_Nullable *_Nullable)error;
+ (NSArray<NSString *> *)allFieldNames;
+ (NSArray<NSString *> *)allColumnNames;
+ (NSArray<NSString *> *)allQualifiedColumnNames;
+ (NSString *)entityName;

- (nullable id)objectForFieldName:(NSString *)fieldName;
- (nullable id)objectForPropertyName:(NSString *)propertyName;
- (nullable id)objectForColumnName:(NSString *)columnName;
- (BOOL)setObject:(nullable id)value
     forFieldName:(NSString *)fieldName
            error:(NSError *_Nullable *_Nullable)error;
- (BOOL)setObject:(nullable id)value
  forPropertyName:(NSString *)propertyName
            error:(NSError *_Nullable *_Nullable)error;
- (BOOL)applyRow:(NSDictionary<NSString *, id> *)row
           error:(NSError *_Nullable *_Nullable)error;
- (void)markClean;
- (void)markDetached;
- (BOOL)setRelationObject:(nullable id)value
          forRelationName:(NSString *)relationName
                    error:(NSError *_Nullable *_Nullable)error;
- (nullable id)relationObjectForName:(NSString *)relationName;
- (NSDictionary<NSString *, id> *)primaryKeyValues;
- (NSDictionary<NSString *, id> *)changedFieldValues;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
