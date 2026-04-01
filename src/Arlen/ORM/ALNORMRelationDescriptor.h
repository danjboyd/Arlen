#ifndef ALN_ORM_RELATION_DESCRIPTOR_H
#define ALN_ORM_RELATION_DESCRIPTOR_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ALNORMRelationKind) {
  ALNORMRelationKindBelongsTo = 1,
  ALNORMRelationKindHasOne = 2,
  ALNORMRelationKindHasMany = 3,
  ALNORMRelationKindManyToMany = 4,
};

FOUNDATION_EXPORT NSString *ALNORMRelationKindName(ALNORMRelationKind kind);
FOUNDATION_EXPORT ALNORMRelationKind ALNORMRelationKindFromString(NSString *value);

@interface ALNORMRelationDescriptor : NSObject

@property(nonatomic, assign, readonly) ALNORMRelationKind kind;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, readonly) NSString *sourceEntityName;
@property(nonatomic, copy, readonly) NSString *targetEntityName;
@property(nonatomic, copy, readonly) NSString *targetClassName;
@property(nonatomic, copy, readonly) NSString *throughEntityName;
@property(nonatomic, copy, readonly) NSString *throughClassName;
@property(nonatomic, copy, readonly) NSArray<NSString *> *sourceFieldNames;
@property(nonatomic, copy, readonly) NSArray<NSString *> *targetFieldNames;
@property(nonatomic, copy, readonly) NSArray<NSString *> *throughSourceFieldNames;
@property(nonatomic, copy, readonly) NSArray<NSString *> *throughTargetFieldNames;
@property(nonatomic, copy, readonly) NSArray<NSString *> *pivotFieldNames;
@property(nonatomic, assign, readonly, getter=isReadOnly) BOOL readOnly;
@property(nonatomic, assign, readonly, getter=isInferred) BOOL inferred;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithKind:(ALNORMRelationKind)kind
                        name:(NSString *)name
            sourceEntityName:(NSString *)sourceEntityName
            targetEntityName:(NSString *)targetEntityName
             targetClassName:(NSString *)targetClassName
           throughEntityName:(nullable NSString *)throughEntityName
            throughClassName:(nullable NSString *)throughClassName
            sourceFieldNames:(NSArray<NSString *> *)sourceFieldNames
            targetFieldNames:(NSArray<NSString *> *)targetFieldNames
     throughSourceFieldNames:(nullable NSArray<NSString *> *)throughSourceFieldNames
     throughTargetFieldNames:(nullable NSArray<NSString *> *)throughTargetFieldNames
             pivotFieldNames:(nullable NSArray<NSString *> *)pivotFieldNames
                    readOnly:(BOOL)readOnly
                    inferred:(BOOL)inferred NS_DESIGNATED_INITIALIZER;

- (NSString *)kindName;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
