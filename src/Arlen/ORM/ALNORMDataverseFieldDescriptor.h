#ifndef ALN_ORM_DATAVERSE_FIELD_DESCRIPTOR_H
#define ALN_ORM_DATAVERSE_FIELD_DESCRIPTOR_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMDataverseFieldDescriptor : NSObject

@property(nonatomic, copy, readonly) NSString *logicalName;
@property(nonatomic, copy, readonly) NSString *schemaName;
@property(nonatomic, copy, readonly) NSString *displayName;
@property(nonatomic, copy, readonly) NSString *attributeType;
@property(nonatomic, copy, readonly) NSString *readKey;
@property(nonatomic, copy, readonly) NSString *objcType;
@property(nonatomic, copy, readonly) NSString *runtimeClassName;
@property(nonatomic, assign, readonly, getter=isNullable) BOOL nullable;
@property(nonatomic, assign, readonly, getter=isPrimaryID) BOOL primaryID;
@property(nonatomic, assign, readonly, getter=isPrimaryName) BOOL primaryName;
@property(nonatomic, assign, readonly, getter=isLogical) BOOL logical;
@property(nonatomic, assign, readonly, getter=isReadable) BOOL readable;
@property(nonatomic, assign, readonly, getter=isCreatable) BOOL creatable;
@property(nonatomic, assign, readonly, getter=isUpdateable) BOOL updateable;
@property(nonatomic, copy, readonly) NSArray<NSString *> *targets;
@property(nonatomic, copy, readonly) NSArray<NSDictionary<NSString *, id> *> *choices;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithLogicalName:(NSString *)logicalName
                         schemaName:(NSString *)schemaName
                        displayName:(NSString *)displayName
                      attributeType:(NSString *)attributeType
                            readKey:(NSString *)readKey
                           objcType:(NSString *)objcType
                   runtimeClassName:(NSString *)runtimeClassName
                           nullable:(BOOL)nullable
                          primaryID:(BOOL)primaryID
                        primaryName:(BOOL)primaryName
                            logical:(BOOL)logical
                           readable:(BOOL)readable
                          creatable:(BOOL)creatable
                         updateable:(BOOL)updateable
                            targets:(nullable NSArray<NSString *> *)targets
                            choices:(nullable NSArray<NSDictionary<NSString *, id> *> *)choices
    NS_DESIGNATED_INITIALIZER;
- (BOOL)isLookup;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
