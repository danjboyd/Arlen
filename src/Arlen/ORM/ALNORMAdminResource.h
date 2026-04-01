#ifndef ALN_ORM_ADMIN_RESOURCE_H
#define ALN_ORM_ADMIN_RESOURCE_H

#import <Foundation/Foundation.h>

#import "ALNORMModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface ALNORMAdminResource : NSObject

@property(nonatomic, copy, readonly) NSString *resourceName;
@property(nonatomic, copy, readonly) NSString *modelClassName;
@property(nonatomic, copy, readonly) NSString *entityName;
@property(nonatomic, copy, readonly) NSString *titleFieldName;
@property(nonatomic, copy, readonly) NSArray<NSString *> *searchableFieldNames;
@property(nonatomic, copy, readonly) NSArray<NSString *> *sortableFieldNames;
@property(nonatomic, assign, readonly, getter=isReadOnly) BOOL readOnly;

- (instancetype)init NS_UNAVAILABLE;
+ (nullable instancetype)resourceForModelClass:(Class)modelClass;
- (instancetype)initWithResourceName:(NSString *)resourceName
                      modelClassName:(NSString *)modelClassName
                          entityName:(NSString *)entityName
                      titleFieldName:(NSString *)titleFieldName
                searchableFieldNames:(NSArray<NSString *> *)searchableFieldNames
                  sortableFieldNames:(NSArray<NSString *> *)sortableFieldNames
                            readOnly:(BOOL)readOnly NS_DESIGNATED_INITIALIZER;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END

#endif
