#ifndef ALN_ORM_DATAVERSE_RELATION_DESCRIPTOR_H
#define ALN_ORM_DATAVERSE_RELATION_DESCRIPTOR_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMDataverseRelationDescriptor : NSObject

@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *currentEntityLogicalName;
@property(nonatomic, copy, readonly) NSString *queryEntityLogicalName;
@property(nonatomic, copy, readonly) NSString *queryEntitySetName;
@property(nonatomic, copy, readonly) NSString *targetClassName;
@property(nonatomic, copy, readonly) NSString *sourceValueFieldName;
@property(nonatomic, copy, readonly) NSString *queryFieldLogicalName;
@property(nonatomic, copy, readonly) NSString *navigationPropertyName;
@property(nonatomic, assign, readonly, getter=isCollection) BOOL collection;
@property(nonatomic, assign, readonly, getter=isReadOnly) BOOL readOnly;
@property(nonatomic, assign, readonly, getter=isInferred) BOOL inferred;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithName:(NSString *)name
    currentEntityLogicalName:(NSString *)currentEntityLogicalName
      queryEntityLogicalName:(NSString *)queryEntityLogicalName
         queryEntitySetName:(NSString *)queryEntitySetName
             targetClassName:(NSString *)targetClassName
        sourceValueFieldName:(NSString *)sourceValueFieldName
          queryFieldLogicalName:(NSString *)queryFieldLogicalName
      navigationPropertyName:(NSString *)navigationPropertyName
                   collection:(BOOL)collection
                     readOnly:(BOOL)readOnly
                     inferred:(BOOL)inferred NS_DESIGNATED_INITIALIZER;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
