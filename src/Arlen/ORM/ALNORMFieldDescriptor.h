#ifndef ALN_ORM_FIELD_DESCRIPTOR_H
#define ALN_ORM_FIELD_DESCRIPTOR_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMFieldDescriptor : NSObject

@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *propertyName;
@property(nonatomic, copy, readonly) NSString *columnName;
@property(nonatomic, copy, readonly) NSString *dataType;
@property(nonatomic, copy, readonly) NSString *objcType;
@property(nonatomic, copy, readonly) NSString *runtimeClassName;
@property(nonatomic, copy, readonly) NSString *propertyAttribute;
@property(nonatomic, assign, readonly) NSInteger ordinal;
@property(nonatomic, assign, readonly, getter=isNullable) BOOL nullable;
@property(nonatomic, assign, readonly, getter=isPrimaryKey) BOOL primaryKey;
@property(nonatomic, assign, readonly, getter=isUnique) BOOL unique;
@property(nonatomic, assign, readonly, getter=hasDefaultValue) BOOL hasDefault;
@property(nonatomic, assign, readonly, getter=isReadOnly) BOOL readOnly;
@property(nonatomic, copy, readonly) NSString *defaultValueShape;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithName:(NSString *)name
                propertyName:(NSString *)propertyName
                  columnName:(NSString *)columnName
                    dataType:(NSString *)dataType
                    objcType:(NSString *)objcType
            runtimeClassName:(nullable NSString *)runtimeClassName
           propertyAttribute:(NSString *)propertyAttribute
                     ordinal:(NSInteger)ordinal
                    nullable:(BOOL)nullable
                  primaryKey:(BOOL)primaryKey
                      unique:(BOOL)unique
                  hasDefault:(BOOL)hasDefault
                    readOnly:(BOOL)readOnly
           defaultValueShape:(NSString *)defaultValueShape NS_DESIGNATED_INITIALIZER;

- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
