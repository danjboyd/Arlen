#ifndef ALN_ORM_DATAVERSE_MODEL_DESCRIPTOR_H
#define ALN_ORM_DATAVERSE_MODEL_DESCRIPTOR_H

#import <Foundation/Foundation.h>

#import "ALNORMDataverseFieldDescriptor.h"
#import "ALNORMDataverseRelationDescriptor.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMDataverseModelDescriptor : NSObject

@property(nonatomic, copy, readonly) NSString *className;
@property(nonatomic, copy, readonly) NSString *logicalName;
@property(nonatomic, copy, readonly) NSString *entitySetName;
@property(nonatomic, copy, readonly) NSString *primaryIDAttribute;
@property(nonatomic, copy, readonly) NSString *primaryNameAttribute;
@property(nonatomic, copy, readonly) NSString *dataverseTarget;
@property(nonatomic, assign, readonly, getter=isReadOnly) BOOL readOnly;
@property(nonatomic, copy, readonly) NSArray<ALNORMDataverseFieldDescriptor *> *fields;
@property(nonatomic, copy, readonly) NSArray<NSArray<NSString *> *> *alternateKeyFieldSets;
@property(nonatomic, copy, readonly) NSArray<ALNORMDataverseRelationDescriptor *> *relations;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithClassName:(NSString *)className
                      logicalName:(NSString *)logicalName
                    entitySetName:(NSString *)entitySetName
               primaryIDAttribute:(NSString *)primaryIDAttribute
             primaryNameAttribute:(NSString *)primaryNameAttribute
                  dataverseTarget:(nullable NSString *)dataverseTarget
                         readOnly:(BOOL)readOnly
                           fields:(NSArray<ALNORMDataverseFieldDescriptor *> *)fields
            alternateKeyFieldSets:(nullable NSArray<NSArray<NSString *> *> *)alternateKeyFieldSets
                        relations:(nullable NSArray<ALNORMDataverseRelationDescriptor *> *)relations
    NS_DESIGNATED_INITIALIZER;
- (nullable ALNORMDataverseFieldDescriptor *)fieldNamed:(NSString *)fieldName;
- (nullable ALNORMDataverseFieldDescriptor *)fieldForReadKey:(NSString *)readKey;
- (nullable ALNORMDataverseRelationDescriptor *)relationNamed:(NSString *)relationName;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
