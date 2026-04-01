#ifndef ALN_ORM_MODEL_DESCRIPTOR_H
#define ALN_ORM_MODEL_DESCRIPTOR_H

#import <Foundation/Foundation.h>

#import "ALNORMFieldDescriptor.h"
#import "ALNORMRelationDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMModelDescriptor : NSObject

@property(nonatomic, copy, readonly) NSString *className;
@property(nonatomic, copy, readonly) NSString *entityName;
@property(nonatomic, copy, readonly) NSString *schemaName;
@property(nonatomic, copy, readonly) NSString *tableName;
@property(nonatomic, copy, readonly) NSString *qualifiedTableName;
@property(nonatomic, copy, readonly) NSString *relationKind;
@property(nonatomic, copy, readonly) NSString *databaseTarget;
@property(nonatomic, assign, readonly, getter=isReadOnly) BOOL readOnly;
@property(nonatomic, copy, readonly) NSArray<ALNORMFieldDescriptor *> *fields;
@property(nonatomic, copy, readonly) NSArray<NSString *> *primaryKeyFieldNames;
@property(nonatomic, copy, readonly) NSArray<NSArray<NSString *> *> *uniqueConstraintFieldSets;
@property(nonatomic, copy, readonly) NSArray<ALNORMRelationDescriptor *> *relations;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithClassName:(NSString *)className
                       entityName:(NSString *)entityName
                       schemaName:(NSString *)schemaName
                        tableName:(NSString *)tableName
               qualifiedTableName:(NSString *)qualifiedTableName
                     relationKind:(NSString *)relationKind
                   databaseTarget:(nullable NSString *)databaseTarget
                         readOnly:(BOOL)readOnly
                           fields:(NSArray<ALNORMFieldDescriptor *> *)fields
             primaryKeyFieldNames:(NSArray<NSString *> *)primaryKeyFieldNames
         uniqueConstraintFieldSets:(NSArray<NSArray<NSString *> *> *)uniqueConstraintFieldSets
                        relations:(nullable NSArray<ALNORMRelationDescriptor *> *)relations NS_DESIGNATED_INITIALIZER;

- (nullable ALNORMFieldDescriptor *)fieldNamed:(NSString *)fieldName;
- (nullable ALNORMFieldDescriptor *)fieldForPropertyName:(NSString *)propertyName;
- (nullable ALNORMFieldDescriptor *)fieldForColumnName:(NSString *)columnName;
- (nullable ALNORMRelationDescriptor *)relationNamed:(NSString *)relationName;
- (NSArray<NSString *> *)allFieldNames;
- (NSArray<NSString *> *)allColumnNames;
- (NSArray<NSString *> *)allQualifiedColumnNames;
- (BOOL)hasUniqueConstraintForFieldSet:(NSArray<NSString *> *)fieldNames;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
