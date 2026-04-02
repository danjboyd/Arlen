#ifndef ALN_ORM_MODEL_H
#define ALN_ORM_MODEL_H

#import <Foundation/Foundation.h>

#import "ALNORMQuery.h"
#import "ALNORMModelDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@class ALNORMContext;
@class ALNORMRepository;

typedef NS_ENUM(NSInteger, ALNORMModelState) {
  ALNORMModelStateNew = 1,
  ALNORMModelStateLoaded = 2,
  ALNORMModelStateDirty = 3,
  ALNORMModelStateDetached = 4,
};

FOUNDATION_EXPORT NSString *ALNORMModelStateName(ALNORMModelState state);
FOUNDATION_EXPORT NSString *const ALNORMStrictLoadingException;

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
@property(nonatomic, weak, readonly, nullable) ALNORMContext *context;
@property(nonatomic, copy, readonly) NSSet<NSString *> *loadedRelationNames;

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
- (nullable id)relationObjectForName:(NSString *)relationName
                               error:(NSError *_Nullable *_Nullable)error;
- (BOOL)isRelationLoaded:(NSString *)relationName;
- (void)attachToContext:(nullable ALNORMContext *)context;
- (BOOL)markRelationLoaded:(NSString *)relationName
                     value:(nullable id)value
                pivotRows:(nullable NSArray<NSDictionary<NSString *, id> *> *)pivotRows
                    error:(NSError *_Nullable *_Nullable)error;
- (void)markRelationNamed:(NSString *)relationName
            accessStrategy:(ALNORMRelationLoadStrategy)accessStrategy;
- (NSArray<NSDictionary<NSString *, id> *> *)pivotValueDictionariesForRelationName:(NSString *)relationName;
- (NSDictionary<NSString *, id> *)primaryKeyValues;
- (NSDictionary<NSString *, id> *)changedFieldValues;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
